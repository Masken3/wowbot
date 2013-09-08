#include "auth.h"
#include "AuthCodes.h"
#include "AuthSocketStructs.h"
#include "AuthCalc.h"
#include "config.h"
#include "log.h"

#include <assert.h>
#include <string.h>
#include <stdlib.h>

void authenticate(WorldSession* session) {
	Socket sock = session->authSock;
	sAuthLogonChallenge_S lcs;
	sAuthLogonProof_C lpc;
	sAuthLogonProof_S1 lps1;
	byte M2[20], serverM2[20];
	uint32 accountFlags;
	// send & receive challenge
	{
		char buf[1024];
		sAuthLogonChallenge_C* lcc = (sAuthLogonChallenge_C*)buf;
		memset(lcc, 0, sizeof(*lcc));
		lcc->cmd = CMD_AUTH_LOGON_CHALLENGE;
		lcc->I_len = strlen(session->accountName)+1;
		lcc->size = sizeof(*lcc) + (lcc->I_len - 1) - 4;
		lcc->build = 5875;	// client version 1.12.1
		strcpy((char*)lcc->I, session->accountName);
		sendAndReceiveExact(sock, buf, lcc->size + 4, &lcs, sizeof(lcs));
	}
	// calculate proof
	CalculateLogonProof(&lcs, &lpc, session->accountName, session->password, M2, session->key);
	// send proof
	{
		lpc.cmd = CMD_AUTH_LOGON_PROOF;
		sendAndReceiveExact(sock, (char*)&lpc, sizeof(lpc), &lps1, sizeof(lps1));
		LOG("proof received. cmd %02x, code %02x\n", lps1.cmd, lps1.error);
		if(lps1.error == 0) {
			if(receiveExact(sock, serverM2, sizeof(serverM2)) <= 0)
				exit(1);
			LOG("M2 %smatch.\n", memcmp(M2, serverM2, 20) ? "mis" : "");
		}
		if(receiveExact(sock, &accountFlags, sizeof(accountFlags)) <= 0)
			exit(1);
		LOG("accountFlags: %08X\n", accountFlags);
	}
}

char* dumpRealmList(Socket sock, const char* targetRealmName) {
	sAuthRealmHeader_S rhs;
	char buf[6];
	buf[0] = CMD_REALM_LIST;
	LOG("dumpRealmList send...\n");
	sendAndReceiveExact(sock, buf, sizeof(buf), &rhs, sizeof(rhs));
	//DUMPINT(rhs.size);
	DUMPINT(rhs.count);
	{
		int rlSize = rhs.size-5;
		char* rlBuf = (char*)malloc(rlSize);
		char* ptr = rlBuf;
		if(receiveExact(sock, rlBuf, rlSize) <= 0)
			exit(1);
		for(int i=0; i<rhs.count; i++) {
			sAuthRealmEntry1_S* e1;
			sAuthRealmEntry2_S* e2;
			const char* name;
			char* address;
			e1 = (sAuthRealmEntry1_S*)ptr;
			ptr += sizeof(sAuthRealmEntry1_S);
			name = ptr;
			ptr += strlen(ptr) + 1;
			address = ptr;
			ptr += strlen(ptr) + 1;
			e2 = (sAuthRealmEntry2_S*)ptr;
			ptr += sizeof(sAuthRealmEntry2_S);
			assert(ptr - rlBuf <= rlSize);

			if(targetRealmName) {
				if(!strcmp(name, targetRealmName)) {
					// memory leak, but it's only one small buffer, so we don't care.
					return address;
				}
			} else {
				LOG("%i: %s (%s) p%f c%i t%i i%i f%02x\n", i, name, address,
					e2->popLevel, e2->charCount, e2->timezone, e1->icon, e1->flags);
			}
		}
		free(rlBuf);
	}
	return NULL;
}
