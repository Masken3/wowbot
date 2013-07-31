#include "world.h"
#include "log.h"
#include "WorldSocketStructs.h"
#include "Opcodes.h"

static void handleServerPacket(Socket sock, ServerPktHeader, char* buf);

void runWorld(Socket sock) {
	do {
		char buf[1024 * 64];	// large enough for theoretical max packet size.
		ServerPktHeader sph;
		receiveExact(sock, &sph, sizeof(sph));
		//sph.cmd = ntohs(sph.cmd); // cmd is not swapped
		sph.size = ntohs(sph.size);
		LOG("Packet: cmd 0x%x, size %i\n", sph.cmd, sph.size);
		receiveExact(sock, buf, sph.size - 2);
		if(sph.cmd == SMSG_LOGOUT_COMPLETE) {
			LOG("SMSG_LOGOUT_COMPLETE\n");
			break;
		}
		handleServerPacket(sock, sph, buf);
	} while(1);
}

static void handleServerPacket(Socket sock, ServerPktHeader sph, char* buf) {

}
