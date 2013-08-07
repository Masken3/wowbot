#include "world.h"
#include "log.h"
#include "WorldSocketStructs.h"
#include "WorldCrypt.h"
#include "Opcodes.h"
#include "worldMsgHandlers/hAuth.h"
#include "worldMsgHandlers/hChar.h"
#include "dumpPacket.h"
#include "auth.h"
#include "worldPacketParsersLua.h"

#include <lua.h>
#include <assert.h>

#define DEFAULT_WORLDSERVER_PORT 8085

static void handleServerPacket(WorldSession*, ServerPktHeader, char* buf);

static int runWorld2(WorldSession* session) {
	Socket sock = session->sock;
	do {
		char buf[1024 * 64];	// large enough for theoretical max packet size.
		ServerPktHeader sph;
		if(receiveExact(sock, &sph, sizeof(sph)) <= 0)
			return 0;
		decryptHeader(session, &sph);
		//sph.cmd = ntohs(sph.cmd); // cmd is not swapped
		sph.size = ntohs(sph.size);
		//LOG("Packet: cmd 0x%x, size %i\n", sph.cmd, sph.size);
		if(receiveExact(sock, buf, sph.size - 2) <= 0)
			return 0;
		if(sph.cmd == SMSG_LOGOUT_COMPLETE) {
			LOG("SMSG_LOGOUT_COMPLETE\n");
			return 1;
		}
		handleServerPacket(session, sph, buf);
	} while(1);
}

static void connectToWorld(WorldSession* session, const char* realmName) {
	char* colon;
	int port;
	const char* host;
	const char* address;
	if(!session->worldServerAddress)
		session->worldServerAddress = dumpRealmList(session->authSock, realmName);
	address = session->worldServerAddress;
	if(!address) {
		LOG("realm not found!\n");
		exit(1);
	}
	DUMPSTR(address);
	colon = strchr(address, ':');
	if(!colon) {
		port = DEFAULT_WORLDSERVER_PORT;
	} else {
		*colon = 0;
		port = strtol(colon + 1, NULL, 10);
	}
	host = address;
	session->sock = connectNewSocket(host, port);
}

void runWorld(WorldSession* session) {
	do {
		connectToWorld(session, "Plain");
		if(runWorld2(session))
			return;
	} while(1);
}

#define HANDLERS(m)\
	m(SMSG_AUTH_CHALLENGE)\
	m(SMSG_AUTH_RESPONSE)\
	m(SMSG_CHAR_ENUM)\
	m(SMSG_CHAR_CREATE)\

#define IGNORED_PACKET_TYPES(m)\
	m(MSG_MOVE_HEARTBEAT)\
	m(SMSG_SET_PROFICIENCY)\

#define MOVEMENT_OPCODES(m)\
	m(MSG_MOVE_START_FORWARD)\
	m(MSG_MOVE_START_BACKWARD)\
	m(MSG_MOVE_STOP)\
	m(MSG_MOVE_START_STRAFE_LEFT)\
	m(MSG_MOVE_START_STRAFE_RIGHT)\
	m(MSG_MOVE_STOP_STRAFE)\
	m(MSG_MOVE_JUMP)\
	m(MSG_MOVE_START_TURN_LEFT)\
	m(MSG_MOVE_START_TURN_RIGHT)\
	m(MSG_MOVE_STOP_TURN)\
	m(MSG_MOVE_START_PITCH_UP)\
	m(MSG_MOVE_START_PITCH_DOWN)\
	m(MSG_MOVE_STOP_PITCH)\
	m(MSG_MOVE_SET_RUN_MODE)\
	m(MSG_MOVE_SET_WALK_MODE)\
	m(MSG_MOVE_FALL_LAND)\
	m(MSG_MOVE_START_SWIM)\
	m(MSG_MOVE_STOP_SWIM)\
	m(MSG_MOVE_SET_FACING)\
	m(MSG_MOVE_SET_PITCH)\

static void checkLuaFunction(lua_State* L, const char* name) {
	LOG("checking for Lua function %s...\n", name);
	lua_getglobal(L, name);
	if(!lua_isfunction(L, -1)) {
		LOG("LUA function %s is missing!\n", name);
		exit(1);
	}
	lua_pop(L, 1);
}

void worldCheckLua(WorldSession* session) {
	lua_State* L = session->L;
#define CHECK_LUA_HANDLER(name) checkLuaFunction(L, "h" #name);
	LUA_HANDLERS(CHECK_LUA_HANDLER);
	MOVEMENT_OPCODES(CHECK_LUA_HANDLER);
}

static void handleServerPacket(WorldSession* session, ServerPktHeader sph, char* buf) {
#define LSP LOG("serverPacket %s (%i)\n", s, sph.size)
#define CASE_HANDLER(name) case name: LSP; h##name(session, buf, sph.size - 2); break;
#define CASE_IGNORED_HANDLER(name) case name: break;
#define CASE_MOVEMENT_OPCODE(name) _CASE_LUA_HANDLER(name, pMovementInfo);
#define CASE_LUA_HANDLER(name) _CASE_LUA_HANDLER(name, p##name);

#define _CASE_LUA_HANDLER(name, parser) case name:\
	lua_getglobal(L, "h" #name);\
	parser(session, buf, sph.size - 2);\
	lua_call(L, 1, 0);\
	break;\

	lua_State* L = session->L;
	const char* s = opcodeString(sph.cmd);
	switch(sph.cmd) {
		HANDLERS(CASE_HANDLER);
		IGNORED_PACKET_TYPES(CASE_IGNORED_HANDLER);
		MOVEMENT_OPCODES(CASE_MOVEMENT_OPCODE);
		LUA_HANDLERS(CASE_LUA_HANDLER);
		default:
		{
			if(s) {
				LOG("Unhandled opcode %s (%i)\n", s, sph.size);
			} else {
				LOG("Unknown opcode 0x%x (%i)\n", sph.cmd, sph.size);
			}
		}
	}
}
