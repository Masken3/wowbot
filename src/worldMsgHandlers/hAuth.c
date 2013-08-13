#include "socket.h"
#include "config.h"
#include "Common.h"
#include "world.h"
#include "Opcodes.h"
#include <openssl/sha.h>
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include "WorldCrypt.h"
#include "worldHandlers.h"
#include "log.h"
#include "SharedDefines.h"

#include "hAuth.h"

#if defined( __GNUC__ )
#pragma pack(1)
#else
#pragma pack(push,1)
#endif

typedef struct sSMSG_AUTH_CHALLENGE {
	uint32 seed;
} sSMSG_AUTH_CHALLENGE;

typedef struct sCMSG_AUTH_SESSION {
	uint32 clientBuild;
	uint32 unk2;
	const char* accountName;
	uint32 seed;
	uint8 digest[20];
} sCMSG_AUTH_SESSION;

#if defined( __GNUC__ )
#pragma pack()
#else
#pragma pack(pop)
#endif

// server sends this when we first connect.
// it expects a CMSG_AUTH_SESSION, and will respond to that with SMSG_AUTH_RESPONSE.
void hSMSG_AUTH_CHALLENGE(WorldSession* session, char* buf, uint16 size) {
	char cbuf[1024];
	uint32 t = 0;
	SHA_CTX mC;

	sCMSG_AUTH_SESSION c = {
		5875,
		0,
		CONFIG_ACCOUNT_NAME,
		rand(),
		"",
	};

	sSMSG_AUTH_CHALLENGE* s = (sSMSG_AUTH_CHALLENGE*)buf;
	assert(size == sizeof(sSMSG_AUTH_CHALLENGE));

	SHA1_Init(&mC);
	SHA1_Update(&mC, CONFIG_ACCOUNT_NAME, strlen(CONFIG_ACCOUNT_NAME));
	SHA1_Update(&mC, &t, 4);
	SHA1_Update(&mC, &c.seed, 4);
	SHA1_Update(&mC, &s->seed, 4);
	SHA1_Update(&mC, session->key, 40);
	SHA1_Final(c.digest, &mC);

	memcpy(cbuf, &c, 8);
	strcpy(cbuf + 8, CONFIG_ACCOUNT_NAME);
	memcpy(cbuf + 8 + sizeof(CONFIG_ACCOUNT_NAME), &c.seed, 24);

	sendWorld(session, CMSG_AUTH_SESSION, cbuf, 8 + sizeof(CONFIG_ACCOUNT_NAME) + 24);

	// once we've sent the session key to the server, packet headers will be encrypted.
	initCrypto(session);
}

void hSMSG_AUTH_RESPONSE(WorldSession* session, char* buf, uint16 size) {
	if(buf[0] == AUTH_OK) {
		LOG("AUTH_OK!\n");
		// at this point, we can request the list of toons.
		sendWorld(session, CMSG_CHAR_ENUM, NULL, 0);
	} else {
		LOG("Auth error code 0x%02x\n", buf[0]);
	}
}
