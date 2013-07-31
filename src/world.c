#include "world.h"
#include "log.h"
#include "WorldSocketStructs.h"
#include "WorldCrypt.h"
#include "Opcodes.h"
#include "worldMsgHandlers/hAuth.h"
#include "worldMsgHandlers/hChar.h"

static void handleServerPacket(WorldSession*, ServerPktHeader, char* buf);

void runWorld(WorldSession* session) {
	Socket sock = session->sock;
	do {
		char buf[1024 * 64];	// large enough for theoretical max packet size.
		ServerPktHeader sph;
		receiveExact(sock, &sph, sizeof(sph));
		decryptHeader(session, &sph);
		//sph.cmd = ntohs(sph.cmd); // cmd is not swapped
		sph.size = ntohs(sph.size);
		//LOG("Packet: cmd 0x%x, size %i\n", sph.cmd, sph.size);
		receiveExact(sock, buf, sph.size - 2);
		if(sph.cmd == SMSG_LOGOUT_COMPLETE) {
			LOG("SMSG_LOGOUT_COMPLETE\n");
			break;
		}
		handleServerPacket(session, sph, buf);
	} while(1);
}

#define HANDLERS(m)\
	m(SMSG_AUTH_CHALLENGE)\
	m(SMSG_AUTH_RESPONSE)\
	m(SMSG_CHAR_ENUM)\
	m(SMSG_CHAR_CREATE)\

static void handleServerPacket(WorldSession* session, ServerPktHeader sph, char* buf) {
#define CASE_HANDLER(name) case name: h##name(session, buf, sph.size - 2); break;
	const char* s = opcodeString(sph.cmd);
	LOG("serverPacket %s (%i)\n", s, sph.size);
	switch(sph.cmd) {
		HANDLERS(CASE_HANDLER);
		default:
		{
			if(s) {
				LOG("Unhandled opcode %s\n", s);
			} else {
				LOG("Unknown opcode 0x%x\n", sph.cmd);
			}
		}
	}
}
