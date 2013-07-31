#include "world.h"
#include "AuthCrypt.h"
#include "WorldSocketStructs.h"
#include "WorldCrypt.h"
#include "worldHandlers.h"

struct Crypto {
	AuthCrypt ac;
};

void sendWorld(WorldSession* session, uint32 opcode, const void* src, uint16 size) {
	ClientPktHeader c = { htons(size + 4), opcode };
	session->crypto->ac.EncryptSend((uint8*)&c, sizeof(c));
	sendExact(session->sock, (char*)&c, sizeof(c));
	if(size > 0)
		sendExact(session->sock, (char*)src, size);
}

void decryptHeader(WorldSession* session, ServerPktHeader* sph) {
	session->crypto->ac.DecryptRecv((uint8*)sph, sizeof(*sph));
}

void initCrypto(WorldSession* session) {
	session->crypto = new Crypto;
	session->crypto->ac.Init();
	session->crypto->ac.SetKey(session->key, 40);
}
