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
#include "SharedDefines.h"

#include <lua.h>
#include <lauxlib.h>
#include "lua_version.h"
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
#include "movementLua.h"
#include "QuestDefLua.h"
#include "ItemPrototypeLua.h"
#include "PlayerLua.h"
#include "LootMgrLua.h"
#include "GossipDefLua.h"
#include "SpellAuraDefinesLua.h"
#include "worldHandlersLua.h"
#include "ItemLua.h"

#define DEFAULT_WORLDSERVER_PORT 8085

static void handleServerPacket(WorldSession*, ServerPktHeader, char* buf);
static void luaTimerCallback(double t, SocketControl*);
static void connectToWorld(WorldSession* session);
static void reconnect(SocketControl* sc, WorldSession* session);
static WorldSession* lua_getSession(lua_State* L);

static const int BUFSIZE = 1024 * 64;

static void worldDataCallback(SocketControl* sc, int result) {
	WorldSession* session = (WorldSession*)sc->user;
	if(result < 0) {
		exit(1);
	}
	if(result == 0) {
		LOG("Disconnected. Reconnecting...\n");
		reconnect(sc, session);
		return;
	}
	// if we got a header...
	if(sc->dst == &session->sph) {
		decryptHeader(session, &session->sph);
		//sph.cmd = ntohs(sph.cmd); // cmd is not swapped
		session->sph.size = ntohs(session->sph.size);
		//LOG("Packet: cmd 0x%x, size %i\n", sph.cmd, sph.size);
		if(session->sph.size > 2) {
			sc->dst = session->buf;
			sc->dstSize = session->sph.size - 2;
		} else {
			handleServerPacket(session, session->sph, session->buf);
		}
		return;
	}
	// if we got the meat of a packet...
	if(sc->dst == &session->buf) {
		sc->dst = &session->sph;
		sc->dstSize = sizeof(session->sph);
		handleServerPacket(session, session->sph, session->buf);
		return;
	}
	// no other dst:s are acceptable.
	assert(0);
}

static void reconnect(SocketControl* sc, WorldSession* session) {
	connectToWorld(session);

	sc->sock = session->sock;
	sc->dst = &session->sph;
	sc->dstSize = sizeof(session->sph);
	sc->dataCallback = worldDataCallback;
	sc->timerCallback = NULL;
}

void runWorlds(WorldSession* sessions, int toonCount) {
	// initialize SocketControl.
	SocketControl* scs = (SocketControl*)malloc(sizeof(SocketControl) * toonCount);
	for(int i=0; i<toonCount; i++) {
		SocketControl* sc = &scs[i];
		WorldSession* session = &sessions[i];
		session->sc = sc;
		sc->user = session;
		reconnect(sc, session);
	}
	// run the worlds. this function does not return.
	runSocketControl(scs, toonCount);
}

static void connectToWorld(WorldSession* session) {
	char* colon;
	int port;
	const char* host;
	const char* address;
	if(!session->worldServerAddress)
		session->worldServerAddress = dumpRealmList(session->authSock, session->realmName);
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

static const char* className(int _class) {
	switch(_class) {
	case CLASS_WARRIOR: return "Warrior";
	case CLASS_PALADIN: return "Paladin";
	case CLASS_HUNTER: return "Hunter";
	case CLASS_ROGUE: return "Rogue";
	case CLASS_PRIEST: return "Priest";
	case CLASS_SHAMAN: return "Shaman";
	case CLASS_MAGE: return "Mage";
	case CLASS_WARLOCK: return "Warlock";
	case CLASS_DRUID: return "Druid";
	default: abort();
	}
}

void enterWorld(WorldSession* session, uint64 guid, uint8 level) {
	// set Lua STATE.myGuid.
	lua_State* L = session->L;
	lua_getglobal(L, "STATE");

	lua_pushstring(L, "myGuid");
	lua_pushlstring(L, (char*)&guid, 8);
	lua_settable(L, -3);

	lua_pushstring(L, "myLevel");
	lua_pushnumber(L, level);
	lua_settable(L, -3);

	lua_pushstring(L, "myName");
	lua_pushstring(L, session->toonName);
	lua_settable(L, -3);

	lua_pushstring(L, "myClassName");
	lua_pushstring(L, className(session->_class));
	lua_settable(L, -3);

	lua_pushstring(L, "amTank");
	lua_pushboolean(L, session->amTank);
	lua_settable(L, -3);

	lua_pushstring(L, "amHealer");
	lua_pushboolean(L, session->amHealer);
	lua_settable(L, -3);

	lua_pushstring(L, "authAddress");
	lua_pushstring(L, session->authAddress);
	lua_settable(L, -3);

	lua_pop(L, 1);

	lua_getglobal(L, "loadState");
	if(!luaPcall(L, 0)) {
		abort();
	}

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
	m(SMSG_PARTY_MEMBER_STATS)\
	m(SMSG_SPELLLOGEXECUTE)\
	m(MSG_CHANNEL_UPDATE)\
	m(SMSG_LOOT_REMOVED)\
	m(MSG_CHANNEL_START)\
	m(SMSG_UPDATE_AURA_DURATION)\
	m(SMSG_SET_EXTRA_AURA_INFO_NEED_UPDATE)\
	m(SMSG_WEATHER)\
	m(SMSG_GROUP_SET_LEADER)\
	m(SMSG_PARTY_COMMAND_RESULT)\
	m(SMSG_ATTACKERSTATEUPDATE)\
	m(SMSG_SPELLNONMELEEDAMAGELOG)\
	m(SMSG_PARTYKILLLOG)\
	m(SMSG_LOG_XPGAIN)\
	m(SMSG_EMOTE)\
	m(SMSG_AI_REACTION)\
	m(SMSG_INITIALIZE_FACTIONS)\
	m(SMSG_TUTORIAL_FLAGS)\
	m(SMSG_LOGIN_SETTIMESPEED)\
	m(SMSG_BINDPOINTUPDATE)\
	m(SMSG_SET_REST_START)\
	m(SMSG_ACTION_BUTTONS)\
	m(SMSG_FRIEND_LIST)\
	m(SMSG_IGNORE_LIST)\
	m(SMSG_ACCOUNT_DATA_TIMES)\
	m(SMSG_LOOT_MONEY_NOTIFY)\
	m(SMSG_PERIODICAURALOG)\
	m(SMSG_SPLINE_MOVE_SET_RUN_MODE)\
	m(SMSG_SPLINE_MOVE_SET_WALK_MODE)\
	m(SMSG_INIT_WORLD_STATES)\
	m(SMSG_ENVIRONMENTALDAMAGELOG)\
	m(SMSG_SET_FLAT_SPELL_MODIFIER)\
	m(SMSG_LOOT_CLEAR_MONEY)\
	m(SMSG_LOOT_MASTER_LIST)\
	m(SMSG_SPELLHEALLOG)\
	m(SMSG_SET_PCT_SPELL_MODIFIER)\
	m(MSG_MOVE_SET_SWIM_SPEED)\
	m(MSG_MOVE_SET_RUN_SPEED)\
	m(SMSG_FORCE_RUN_SPEED_CHANGE)\

#define EMPTY_PACKET_LUA_HANDLERS(m)\
	m(SMSG_ATTACKSWING_NOTINRANGE)\
	m(SMSG_ATTACKSWING_BADFACING)\
	m(SMSG_ATTACKSWING_NOTSTANDING)\
	m(SMSG_ATTACKSWING_DEADTARGET)\
	m(SMSG_ATTACKSWING_CANT_ATTACK)\
	m(SMSG_CANCEL_COMBAT)\
	m(SMSG_CANCEL_AUTO_REPEAT)\
	m(SMSG_LOGOUT_COMPLETE)\


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

static BOOL checkLuaFileDates(WorldSession* session) {
	lua_State* L = session->L;
	int res;
	char buf[128] = "src/lua/";
	size_t baseLen = strlen(buf);
	int fileCount;
	BOOL foundDifference = FALSE;

	// file is already loaded. check the other ones.
	lua_getglobal(L, "SUBFILES");
	fileCount = luaL_getn(L, -1);
	assert(fileCount > 1 && fileCount < 100);	// sanity check
	if(fileCount != session->luaTimeCount) {
		if(session->luaTimes)
			free(session->luaTimes);
		session->luaTimes = (time_t*)malloc(sizeof(time_t)*fileCount);
		session->luaTimeCount = fileCount;
		if(!foundDifference)
			LOG("New SUBFILES count: %i\n", fileCount);
		foundDifference = TRUE;
	}
	for(int i=0; i<fileCount; i++) {
		struct stat s;
		lua_rawgeti(L, -1, i+1);
		strcpy(buf + baseLen, lua_tostring(L, -1));
		lua_pop(L, 1);
		res = stat(buf, &s);
		if(res != 0) {
			LOG("stat(%s) failed: %s\n", buf, strerror(errno));
			return FALSE;
		}
		if(session->luaTimes[i] != s.st_mtime) {
			session->luaTimes[i] = s.st_mtime;
			if(!foundDifference)
				LOG("SUBFILE diff: %s\n", buf);
			foundDifference = TRUE;
		}
	}
	lua_pop(L, 1);
	return foundDifference;
}

BOOL readLua(WorldSession* session) {
	lua_State* L = session->L;

	// Read file's date.
	time_t oldTime = session->luaTime;
	{
		struct stat s;
		int res = stat("src/wowbot.lua", &s);
		if(res != 0) {
			LOG("stat(src/wowbot.lua) failed: %s\n", strerror(errno));
			return FALSE;
		}
		session->luaTime = s.st_mtime;
		if(s.st_mtime == oldTime) {
			if(!checkLuaFileDates(session))
				return FALSE;
		} else {
			LOG("MAINFILE diff: %li %li\n", s.st_mtime, oldTime);
		}
	}

	if(!luaDoFile(L, "src/wowbot.lua"))
		return FALSE;

	// if this is our first time,
	// load the file dates so we don't have to reload on the first packet.
	if(oldTime == 0)
		checkLuaFileDates(session);

	// Make sure all required functions are present.
#define CHECK_LUA_HANDLER(name) if(!checkLuaFunction(L, "h" #name)) return FALSE;
	LUA_HANDLERS(CHECK_LUA_HANDLER);
	CHECK_LUA_HANDLER(Movement);

	return TRUE;
}

BOOL luaDoFile(struct lua_State* L, const char* filename) {
	// Load file.
	int res = luaL_loadfile(L, filename);
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
	return TRUE;
}

static WorldSession* lua_getSession(lua_State* L) {
	WorldSession* session;
	lua_getfield(L, LUA_REGISTRYINDEX, "SESSION");
	if(!lua_isuserdata(L, -1)) {
		LOG("SESSION corrupted! Emergency exit!\n");
		exit(1);
	}
	session = (WorldSession*)lua_topointer(L, -1);
	lua_pop(L, 1);
	return session;
}

static int l_send(lua_State* L) {
	WorldSession* session = lua_getSession(L);
	uint32 opcode;
	const char* s;
	const void* data = NULL;
	byte buf[64*1024];
	uint32 size = 0;
	int narg = lua_gettop(L);

	opcode = luaL_checkinteger(L, 1);
	s = opcodeString(opcode);
	if(!s) {
		lua_pushfstring(L, "send error: unknown opcode %i!", opcode);
		lua_error(L);
	}
	//LOG("l_send(%s)\n", s);

	if(narg > 2) {
		lua_pushstring(L, "send error: too many args!");
		lua_error(L);
	}
	if(narg == 2) {
		PacketGenerator pg = getPacketGenerator(opcode);
		luaL_checktype(L, 2, LUA_TTABLE);
		if(!pg) {
			luaL_error(L, "send error: no PacketGenerator for opcode %s", s);
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
	WorldSession* session = lua_getSession(L);
	int narg = lua_gettop(L);
	double t;
	if(narg != 1) {
		lua_pushstring(L, "setTimer error: not one arg!");
		lua_error(L);
	}
	t = luaL_checknumber(L, 1);

	//printf("socketSetTimer(%f)\n", t);
	session->sc->timerTime = t;
	session->sc->timerCallback = luaTimerCallback;
	return 0;
}

static int l_removeTimer(lua_State* L) {
	WorldSession* session = lua_getSession(L);
	int narg = lua_gettop(L);
	if(narg != 0) {
		lua_pushstring(L, "removeTimer error: args!");
		lua_error(L);
	}
	session->sc->timerCallback = NULL;
	return 0;
}

static void luaTimerCallback(double t, SocketControl* sc) {
	WorldSession* session = (WorldSession*)sc->user;
	lua_State* L = session->L;
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
	LOG("l_traceback\n");
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

static int l_intAsFloat(lua_State* L) {
	union {
		uint32 i;
		float f;
	} u;
	u.i = luaL_checkinteger(L, 1);
	lua_pushnumber(L, u.f);
	return 1;
}

static int l_exit(lua_State* L) {
	exit(luaL_checkint(L, 1));
}

void initLua(WorldSession* session) {
	lua_State* L = session->L;

	lua_pushlightuserdata(L, session);
	lua_setfield(L, LUA_REGISTRYINDEX, "SESSION");

	lua_register(L, "send", l_send);
	lua_register(L, "getRealTime", l_getRealTime);
	lua_register(L, "cSetTimer", l_setTimer);
	lua_register(L, "cRemoveTimer", l_removeTimer);
	lua_register(L, "cSpellEffectName", l_spellEffectName);
	lua_register(L, "cTraceback", l_traceback);
	lua_register(L, "cIntAsFloat", l_intAsFloat);
	lua_register(L, "cExit", l_exit);

	registerLuaDBC(L);
	registerLuaAuxDBC(L);

	opcodeLua(L);
	movementFlagsLua(L);
	UpdateFieldsLua(L);
	updateBlockFlagsLua(L);
	SharedDefinesLua(L);
	UnitLua(L);
	ObjectGuidLua(L);
	DBCEnumsLua(L);
	movementLua(L);
	QuestDefLua(L);
	ItemPrototypeLua(L);
	PlayerLua(L);
	LootMgrLua(L);
	GossipDefLua(L);
	SpellAuraDefinesLua(L);
	worldHandlersLua(L);
	ItemLua(L);
}

BOOL luaPcall(lua_State* L, int nargs) {
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
#define LSP //LOG("serverPacket %s (%i)\n", s, sph.size)
#define CASE_HANDLER(name) case name: LSP; h##name(session, buf, sph.size - 2); break;
#define CASE_IGNORED_HANDLER(name) case name: break;
#define CASE_LUA_HANDLER(name) _CASE_LUA_HANDLER(name, p##name);
#define CASE_EMPTY_LUA_HANDLER(name) _CASE_LUA_HANDLER(name, pEmpty);

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
	double startTime, endTime;

	readLua(session);

	startTime = getRealTime();
	switch(sph.cmd) {
		HANDLERS(CASE_HANDLER);
		IGNORED_PACKET_TYPES(CASE_IGNORED_HANDLER);
		MOVEMENT_OPCODES(CASE_MOVEMENT_OPCODE);
		LUA_HANDLERS(CASE_LUA_HANDLER);
		EMPTY_PACKET_LUA_HANDLERS(CASE_EMPTY_LUA_HANDLER);
		default:
		{
			if(s) {
				LOG("Unhandled opcode %s (%i)\n", s, sph.size);
			} else {
				LOG("Unknown opcode 0x%x (%i)\n", sph.cmd, sph.size);
			}
		}
	}
	endTime = getRealTime();
	if(endTime - startTime > 0.1)
		LOG("%s: %.3f s\n", s, endTime - startTime);
}
