#include <string>
#include "AuthCalc.h"
#include "BigNumber.h"
#include "Sha1.h"
#include <stdlib.h>
#include <string.h>
#include <algorithm>

class BigNumSha1 : public Sha1Hash {
public:
	void UpdateBN(BigNumber bn, int len) {
		UpdateData(bn.AsByteArray(len), len);
	}
};

typedef uint8 Sha1Digest[20];

class SRP {
private:
	const BigNumber g, N, k;
	BigNumber a;
public:
	BigNumber A;
	Sha1Digest M1, M2;
	uint8 K[40];

	// sets A.
	SRP(BigNumber _N, BigNumber _g) : g(_g), N(_N), k(3) {
		a.SetRand(19*8);
		A = g.ModExp(a, N);
	}

	// sets M1 and M2.
	void feed(BigNumber s, BigNumber B, const char* username, const char* password) {
		BigNumSha1 sha;
		// Authentication hash consisting of username (I), a colon and password (P)
		// I & P are uppercased.
		// auth = H(I : P)
		sha.Initialize();
		std::string uu(username);
		for(size_t i=0; i<uu.size(); i++) {
			uu[i] = toupper(uu[i]);
		}
		std::string up(password);
		for(size_t i=0; i<up.size(); i++) {
			up[i] = toupper(up[i]);
		}
		sha.UpdateData(uu);
		sha.UpdateData((uint8*)":", 1);
		sha.UpdateData(up);
		sha.Finalize();
		Sha1Digest auth;
		memcpy(auth, sha.GetDigest(), SHA_DIGEST_LENGTH);

		// Salted authentication hash consisting of the salt and the authentication hash
		// x = H(s | auth)
		sha.Initialize();
		sha.UpdateBN(s, 32);
		sha.UpdateData(auth, SHA_DIGEST_LENGTH);
		sha.Finalize();
		BigNumber x;
		x.SetBinary(sha.GetDigest(), SHA_DIGEST_LENGTH);

		// Password verifier
		// v = g ^ x mod N
		const BigNumber v = g.ModExp(x, N);

		// Random scrambling parameter consisting of the public ephemeral values
		// u = H(A | B)
		sha.Initialize();
		sha.UpdateBN(A, 32);
		sha.UpdateBN(B, 32);
		sha.Finalize();
		BigNumber u;
		u.SetBinary(sha.GetDigest(), SHA_DIGEST_LENGTH);

		// Client-side session key
		// S = (B - (kg^x)) ^ (a + ux)
		const BigNumber kgx = k * v;
		const BigNumber aux = a + u * x;
		BigNumber S = (B - kgx).ModExp(aux, N);

		// Store odd and even bytes in separate byte-arrays
		uint8 S1[16], S2[16];
		uint8* sp = S.AsByteArray(32);
		for(int i=0; i<16; i++) {
			S1[i] = sp[i*2];
			S2[i] = sp[i*2+1];
		}

		// Hash these byte-arrays
		Sha1Digest S1h, S2h;

		sha.Initialize();
		sha.UpdateData(S1, 16);
		sha.Finalize();
		memcpy(S1h, sha.GetDigest(), SHA_DIGEST_LENGTH);

		sha.Initialize();
		sha.UpdateData(S2, 16);
		sha.Finalize();
		memcpy(S2h, sha.GetDigest(), SHA_DIGEST_LENGTH);

		// Shared session key generation by interleaving the previously generated hashes
		for(int i=0; i<20; i++) {
			K[i*2] = S1h[i];
			K[i*2+1] = S2h[i];
		}

		// Generate username hash (case-sensitive)
		Sha1Digest userHash;
		sha.Initialize();
		sha.UpdateData((uint8*)username, strlen(username));
		sha.Finalize();
		memcpy(userHash, sha.GetDigest(), SHA_DIGEST_LENGTH);

		// Hash both prime and generator
		Sha1Digest Nh, gh;

		sha.Initialize();
		sha.UpdateBN(N, 32);
		sha.Finalize();
		memcpy(Nh, sha.GetDigest(), SHA_DIGEST_LENGTH);

		sha.Initialize();
		sha.UpdateBN(g, 1);
		sha.Finalize();
		memcpy(gh, sha.GetDigest(), SHA_DIGEST_LENGTH);

		// XOR N-prime and generator
		Sha1Digest Ngh;
		for(int i=0; i<20; i++) {
			Ngh[i] = Nh[i] ^ gh[i];
		}

#if 0
		printf("t3: ");
		for(int i=0; i<20; i++) {
			printf("%02X", Ngh[19-i]);
		}
		printf("\n");

		printf("t4: ");
		for(int i=0; i<20; i++) {
			printf("%02X", userHash[19-i]);
		}
		printf("\n");

		printf("K: ");
		for(int i=0; i<40; i++) {
			printf("%02X", K[39-i]);
		}
		printf("\n");
#endif

		// Calculate M1 (client proof)
		// M1 = H( (H(N) ^ H(G)) | H(I) | s | A | B | K )
		sha.Initialize();
		sha.UpdateData(Ngh, 20);
		sha.UpdateData(userHash, 20);
		sha.UpdateBN(s, 32);
		sha.UpdateBN(A, 32);
		sha.UpdateBN(B, 32);
		sha.UpdateData(K, 40);
		sha.Finalize();
		memcpy(M1, sha.GetDigest(), SHA_DIGEST_LENGTH);

		// Pre-calculate M2 (expected server proof)
		// M2 = H( A | M1 | K )
		sha.Initialize();
		sha.UpdateBN(A, 32);
		sha.UpdateData(M1, 20);
		sha.UpdateData(K, 40);
		sha.Finalize();
		memcpy(M2, sha.GetDigest(), SHA_DIGEST_LENGTH);
	}
};

void CalculateLogonProof(sAuthLogonChallenge_S* lcs, sAuthLogonProof_C* lpc,
	const char* username, const char* password, uint8* M2, uint8* K)
{
	BigNumber g, N, B, salt;
	g.SetDword(lcs->g[0]);
	N.SetBinary(lcs->N, 32);
	B.SetBinary(lcs->B, 32);
	salt.SetBinary(lcs->s, 32);

#if 0
	printf("s: ");
	for(int i=0; i<32; i++) {
		printf("%02X", lcs->s[31-i]);
	}
	printf("\n");
#endif

	SRP srp(N, g);
	srp.feed(salt, B, username, password);

	memset(lpc, 0, sizeof(*lpc));
	memcpy(lpc->A, srp.A.AsByteArray(32), 32);
	memcpy(lpc->M1, srp.M1, 20);
	memcpy(M2, srp.M2, 20);
	memcpy(K, srp.K, 40);

#if 0
	printf("A: ");
	for(int i=0; i<32; i++) {
		printf("%02X", lpc->A[31-i]);
	}
	printf("\n");

	printf("B: ");
	for(int i=0; i<32; i++) {
		printf("%02X", lcs->B[31-i]);
	}
	printf("\n");

	printf("M1: ");
	for(int i=0; i<20; i++) {
		printf("%02X", lpc->M1[19-i]);
	}
	printf("\n");

	printf("M2: ");
	for(int i=0; i<20; i++) {
		printf("%02X", srp.M2[i]);
	}
	printf("\n");
#endif
}
