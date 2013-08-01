#include "world.h"
#include "log.h"
#include "WorldSocketStructs.h"
#include "WorldCrypt.h"
#include "Opcodes.h"
#include "worldMsgHandlers/hAuth.h"
#include "worldMsgHandlers/hChar.h"

#include <lua.h>

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

#define LUA_HANDLERS(m)\
	m(SMSG_MONSTER_MOVE)\
	m(MSG_MOVE_HEARTBEAT)\
	m(SMSG_COMPRESSED_UPDATE_OBJECT)\
	m(SMSG_UPDATE_OBJECT)\

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
}

static void handleLuaServerPacket(WorldSession* session, const char* hName, char* buf, uint16 size) {
	lua_State* L = session->L;
	lua_getglobal(L, hName);
	lua_pushlstring(L, buf, size);
	lua_call(L, 1, 0);
}

static void handleServerPacket(WorldSession* session, ServerPktHeader sph, char* buf) {
#define LSP LOG("serverPacket %s (%i)\n", s, sph.size)
#define CASE_HANDLER(name) case name: LSP; h##name(session, buf, sph.size - 2); break;
#define CASE_LUA_HANDLER(name) case name: handleLuaServerPacket(session, "h" #name, buf, sph.size - 2); break;
	const char* s = opcodeString(sph.cmd);
	switch(sph.cmd) {
		HANDLERS(CASE_HANDLER);
		LUA_HANDLERS(CASE_LUA_HANDLER);
		default:
		{
			LSP;
			if(s) {
				LOG("Unhandled opcode %s\n", s);
			} else {
				LOG("Unknown opcode 0x%x\n", sph.cmd);
			}
		}
	}
}
