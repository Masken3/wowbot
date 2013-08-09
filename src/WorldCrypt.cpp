#include "world.h"
#include "AuthCrypt.h"
#include "WorldSocketStructs.h"
#include "WorldCrypt.h"
#include "worldHandlers.h"
#include "log.h"
#include "Opcodes.h"

struct Crypto {
	AuthCrypt ac;
};

void sendWorld(WorldSession* session, uint32 opcode, const void* src, uint16 size) {
	LOG("send %s (%i)\n", opcodeString(opcode), size);
	ClientPktHeader c = { htons(size + 4), opcode };
	if(session->crypto)
		session->crypto->ac.EncryptSend((uint8*)&c, sizeof(c));
	sendExact(session->sock, (char*)&c, sizeof(c));
	if(size > 0)
		sendExact(session->sock, (char*)src, size);
}

void decryptHeader(WorldSession* session, ServerPktHeader* sph) {
	if(!session->crypto)
		return;
	session->crypto->ac.DecryptRecv((uint8*)sph, sizeof(*sph));
}

void initCrypto(WorldSession* session) {
	session->crypto = new Crypto;
	session->crypto->ac.Init();
	session->crypto->ac.SetKey(session->key, 40);
}
