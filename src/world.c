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
#include "worldHandlers.h"
#include "worldPacketGeneratorsLua.h"
#include "movement.h"
#include "getRealTime.h"
#include "spellStrings.h"
#include "cDbc.h"

#include <lua.h>
#include <lauxlib.h>
#include <assert.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <string.h>

#include "UpdateFieldsLua.h"
#include "updateBlockFlagsLua.h"
#include "SharedDefinesLua.h"
#include "UnitLua.h"
#include "ObjectGuidLua.h"
#include "DBCEnumsLua.h"

#define DEFAULT_WORLDSERVER_PORT 8085

static void handleServerPacket(WorldSession*, ServerPktHeader, char* buf);
static void luaTimerCallback(double t, void* user);
static BOOL luaPcall(lua_State* L, int nargs);

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

void enterWorld(WorldSession* session, uint64 guid) {
	// set Lua STATE.myGuid.
	lua_State* L = session->L;
	lua_getglobal(L, "STATE");
	lua_pushstring(L, "myGuid");
	lua_pushlstring(L, (char*)&guid, 8);
	lua_settable(L, -3);
	lua_pop(L, 1);

	sendWorld(session, CMSG_PLAYER_LOGIN, &guid, sizeof(guid));
}

#define HANDLERS(m)\
	m(SMSG_AUTH_CHALLENGE)\
	m(SMSG_AUTH_RESPONSE)\
	m(SMSG_CHAR_ENUM)\
	m(SMSG_CHAR_CREATE)\

#define IGNORED_PACKET_TYPES(m)\
	m(MSG_MOVE_HEARTBEAT)\
	m(SMSG_SET_PROFICIENCY)\
	m(SMSG_MESSAGECHAT)\

static BOOL checkLuaFunction(lua_State* L, const char* name) {
	//LOG("checking for Lua function %s...\n", name);
	lua_getglobal(L, name);
	if(!lua_isfunction(L, -1)) {
		LOG("LUA function %s is missing!\n", name);
		return FALSE;
	}
	lua_pop(L, 1);
	return TRUE;
}

BOOL readLua(WorldSession* session) {
	lua_State* L = session->L;
	int res;

	// Read file's date.
	{
		struct stat s;
		res = stat("src/wowbot.lua", &s);
		if(res != 0) {
			LOG("stat(src/wowbot.lua) failed: %s\n", strerror(errno));
			return FALSE;
		}
		if(s.st_mtime == session->luaTime)
			return FALSE;
		session->luaTime = s.st_mtime;
	}

	// Load file.
	res = luaL_loadfile(L, "src/wowbot.lua");
	if(res != LUA_OK) {
		LOG("LUA load error!\n");
		LOG("%s\n", lua_tostring(L, -1));
		return FALSE;
	}
	// Run file (parses functions, sets up global variables).
	if(!luaPcall(L, 0)) {
		LOG("LUA run error!\n");
		return FALSE;
	}

	// Make sure all required functions are present.
#define CHECK_LUA_HANDLER(name) if(!checkLuaFunction(L, "h" #name)) return FALSE;
	LUA_HANDLERS(CHECK_LUA_HANDLER);
	CHECK_LUA_HANDLER(Movement);

	return TRUE;
}

static int l_send(lua_State* L) {
	WorldSession* session;
	uint32 opcode;
	const char* s;
	const void* data = NULL;
	byte buf[64*1024];
	uint32 size = 0;
	int narg = lua_gettop(L);

	opcode = luaL_checkunsigned(L, 1);
	s = opcodeString(opcode);
	if(!s) {
		lua_pushfstring(L, "send error: unknown opcode %i!", opcode);
		lua_error(L);
	}
	//LOG("l_send(%s)\n", s);

	{
		lua_getfield(L, LUA_REGISTRYINDEX, "SESSION");
		if(!lua_isuserdata(L, -1)) {
			LOG("SESSION corrupted! Emergency exit!\n");
			exit(1);
		}
		session = (WorldSession*)lua_topointer(L, -1);
		lua_pop(L, 1);	// required for proper PacketGenerator operation.
	}
	if(narg > 2) {
		lua_pushstring(L, "send error: too many args!");
		lua_error(L);
	}
	if(narg == 2) {
		PacketGenerator pg = getPacketGenerator(opcode);
		luaL_checktype(L, 2, LUA_TTABLE);
		if(!pg) {
			lua_pushstring(L, "send error: no PacketGenerator for opcode!");
			lua_error(L);
		}
		size = pg(L, buf);
		data = buf;
	}
	sendWorld(session, opcode, data, size);
	return 0;
}

// Returns a float that measures times in seconds since some undefined starting point.
// The starting point is guaranteed to remain static during an OS process, but not beyond that.
static int l_getRealTime(lua_State* L) {
	int narg = lua_gettop(L);
	if(narg != 0) {
		lua_pushstring(L, "getRealTime error: too many args!");
		lua_error(L);
	}
	lua_pushnumber(L, getRealTime());
	return 1;
}

// args: t.
// Causes "luaTimerCallback" to be called as soon as possible after getRealTime() would return >= t.
static int l_setTimer(lua_State* L) {
	int narg = lua_gettop(L);
	double t;
	if(narg != 1) {
		lua_pushstring(L, "setTimer error: not one arg!");
		lua_error(L);
	}
	t = luaL_checknumber(L, 1);

	//printf("socketSetTimer(%f)\n", t);
	socketSetTimer(t, luaTimerCallback, L);
	return 0;
}

static int l_removeTimer(lua_State* L) {
	int narg = lua_gettop(L);
	if(narg != 0) {
		lua_pushstring(L, "removeTimer error: args!");
		lua_error(L);
	}
	socketRemoveTimer(luaTimerCallback, L);
	return 0;
}

static void luaTimerCallback(double t, void* user) {
	lua_State* L = (lua_State*)user;
	lua_getglobal(L, "luaTimerCallback");
	lua_pushnumber(L, t);
	luaPcall(L, 1);
}

static int l_spellEffectName(lua_State* L) {
	int narg = lua_gettop(L);
	if(narg != 1) {
		lua_pushstring(L, "spellEffectName error: args!");
		lua_error(L);
	}
	lua_pushstring(L, spellEffectName(luaL_checkint(L, 1)));
	return 1;
}

static int l_traceback(lua_State* L) {
	luaL_traceback(L, L, lua_tostring(L, -1), 1);
	LOG("%s\n", lua_tostring(L, -1));
	return 1;
}

#if 0
// bad idea; strings don't have individual metatables.
static int l_setGuid(lua_State* L) {
	lua_createtable(L, 0, 2);
	lua_pushstring(L, "__tostring");
	lua_getglobal(L, "dumpGuid");
	lua_settable(L, -3);
	lua_pushstring(L, "__index");
	lua_getglobal(L, "string");
	lua_settable(L, -3);
	lua_setmetatable(L, -2);
	return 0;
}
#endif

void initLua(WorldSession* session) {
	lua_State* L = session->L;

	lua_pushlightuserdata(L, session);
	lua_setfield(L, LUA_REGISTRYINDEX, "SESSION");

	lua_register(L, "send", l_send);
	lua_register(L, "getRealTime", l_getRealTime);
	lua_register(L, "cSetTimer", l_setTimer);
	lua_register(L, "cRemoveTimer", l_removeTimer);
	lua_register(L, "cSpellEffectName", l_spellEffectName);
	lua_register(L, "cSpell", l_spell);
	lua_register(L, "cTraceback", l_traceback);

	opcodeLua(L);
	movementFlagsLua(L);
	UpdateFieldsLua(L);
	updateBlockFlagsLua(L);
	SharedDefinesLua(L);
	UnitLua(L);
	ObjectGuidLua(L);
	DBCEnumsLua(L);
}

static BOOL luaPcall(lua_State* L, int nargs) {
	int res;
	lua_pushcfunction(L, l_traceback);
	lua_insert(L, 1);
	res = lua_pcall(L, nargs, 0, 1);
	lua_remove(L, 1);
	if(res == LUA_OK)
		return TRUE;
	// if not OK, an error has occurred.
	// print it.
	//LOG("Lua error: %s\n", lua_tostring(L, -1));
	lua_pop(L, 1);
	// at some point, we'll want to reload the Lua code, if you've fixed the error.
	return FALSE;
}

static void handleServerPacket(WorldSession* session, ServerPktHeader sph, char* buf) {
#define LSP LOG("serverPacket %s (%i)\n", s, sph.size)
#define CASE_HANDLER(name) case name: LSP; h##name(session, buf, sph.size - 2); break;
#define CASE_IGNORED_HANDLER(name) case name: break;
#define CASE_LUA_HANDLER(name) _CASE_LUA_HANDLER(name, p##name);

#define CASE_MOVEMENT_OPCODE(name) case name:\
	lua_getglobal(L, "hMovement");\
	lua_pushnumber(L, sph.cmd);\
	pMovementInfo(session, buf, sph.size - 2);\
	luaPcall(L, 2);\
	break;\

#define _CASE_LUA_HANDLER(name, parser) case name:\
	lua_getglobal(L, "h" #name);\
	parser(session, buf, sph.size - 2);\
	luaPcall(L, 1);\
	break;\

	lua_State* L = session->L;
	const char* s = opcodeString(sph.cmd);

	readLua(session);

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
