#include "world.h"
#include "log.h"
#include "WorldSocketStructs.h"
#include "WorldCrypt.h"
#include "Opcodes.h"
#include "worldMsgHandlers/hAuth.h"
#include "worldMsgHandlers/hChar.h"
#include "dumpPacket.h"
#include "auth.h"

#include <lua.h>
#include <assert.h>

#include "movementFlags.h"

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

#define LUA_HANDLERS(m)\
	m(SMSG_MONSTER_MOVE)\

#define IGNORED_PACKET_TYPES(m)\
	m(MSG_MOVE_HEARTBEAT)\
	m(SMSG_COMPRESSED_UPDATE_OBJECT)\
	m(SMSG_UPDATE_OBJECT)\
	m(SMSG_SET_PROFICIENCY)\

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

// These macros parse data from a server packet into a Lua table,
// which is on top of the Lua stack.

typedef uint64 Guid;
#define lua_push_Guid	lua_pushlstring(L, cur, 8)

#define lua_push_float lua_pushnumber(L, *(float*)cur)

#define lua_push_byte lua_pushnumber(L, *(byte*)cur)
static byte local_byte(const char* p) { return *p; }

#define lua_push_uint32 lua_pushnumber(L, *(uint32*)cur)
static uint32 local_uint32(const char* p) { return *(uint32*)p; }

#define lua_push_int32 lua_pushnumber(L, *(int32*)cur)

typedef struct Vector3 {
	float x, y, z;
} Vector3;
#define lua_push_Vector3\
	lua_createtable(L, 0, 3);\
	lua_pushstring(L, "x");\
	lua_push_float;\
	lua_settable(L, -3);\
	cur += 4;\
	lua_pushstring(L, "y");\
	lua_push_float;\
	lua_settable(L, -3);\
	cur += 4;\
	lua_pushstring(L, "z");\
	lua_push_float;\
	lua_settable(L, -3);\

// member
#define M(type, name) { PL_SIZE(sizeof(type));\
	lua_pushstring(L, #name);\
	lua_push_##type;\
	lua_settable(L, -3); }
// member, with local copy
#define MM(type, name) type name; M(type, name); name = local_##type(ptr - sizeof(type))
// member array
#define MA(type, name, count) { uint32 c = (count); PL_SIZE(sizeof(type) * c);\
	lua_pushstring(L, #name);\
	lua_createtable(L, c, 0);\
	for(uint32 i=1; i<=c; i++) { lua_push_##type; lua_rawseti(L, -2, i); }\
	lua_settable(L, -3); }
// member, variable length
#define MV(type, name)\
	lua_pushstring(L, #name);\
	lua_vpush_##type;\
	lua_settable(L, -3);

#define lua_vpush_PackedGuid { uint64 guid = readPackGUID((byte**)&ptr);\
	lua_pushlstring(L, (char*)&guid, 8); }

static uint64 readPackGUID(byte** src) {
	uint64 guid = 0;
	const uint8 guidmark = *(*src)++;
	for(int i = 0; i < 8; ++i) {
		if(guidmark & (1) << i) {
			uint8 bit = *(*src)++;
			guid |= ((uint64)bit) << (i * 8);
		}
	}
	return guid;
}

// helpers
#define pLUA_ARGS WorldSession* session, char* buf, uint16 bufSize
#define PL_START lua_State* L = session->L; char* ptr = buf; lua_newtable(L);
#define PL_PARSED (ptr - buf)	// number of parsed bytes
#define PL_REMAIN (bufSize - PL_PARSED)	// number of unparsed bytes
#define PL_SIZE(size) char* cur = ptr; assert((size) <= (size_t)PL_REMAIN); ptr += (size)

static void pSMSG_MONSTER_MOVE(pLUA_ARGS) {
	PL_START;
	//dumpPacket(buf, bufSize);
	MV(PackedGuid, guid);
	M(Vector3, point);
	M(uint32, id);
	{
		MM(byte, type);
		switch(type) {
		case MonsterMoveNormal: break;

			// Weird packet type; server doesn't have code for sending it, yet server sends it!
			// Anyway, analysis shows that it has no data beyond the "type" byte,
			// so return; here works well.
		case MonsterMoveStop: return;

		case MonsterMoveFacingTarget: M(Guid, target); break;
		case MonsterMoveFacingAngle: M(float, angle); break;
		case MonsterMoveFacingSpot: M(Vector3, spot); break;
		default: LOG("warning: unknown MonsterMove type %i\n", type);
		}
	}
	{
		MM(uint32, flags);
		M(int32, duration);
		if(flags & Mask_CatmullRom) {
			MM(uint32, count);
			MA(Vector3, points, count);
		} else {
			MM(uint32, lastIdx);
			M(Vector3, destination);
			MA(uint32, offsets, lastIdx - 1);
		}
	}
}

static void handleServerPacket(WorldSession* session, ServerPktHeader sph, char* buf) {
#define LSP LOG("serverPacket %s (%i)\n", s, sph.size)
#define CASE_HANDLER(name) case name: LSP; h##name(session, buf, sph.size - 2); break;
#define CASE_IGNORED_HANDLER(name) case name: break;

#define CASE_LUA_HANDLER(name) case name:\
	lua_getglobal(L, "h" #name);\
	p##name(session, buf, sph.size - 2);\
	lua_call(L, 1, 0);\
	break;\

	lua_State* L = session->L;
	const char* s = opcodeString(sph.cmd);
	switch(sph.cmd) {
		HANDLERS(CASE_HANDLER);
		LUA_HANDLERS(CASE_LUA_HANDLER);
		IGNORED_PACKET_TYPES(CASE_IGNORED_HANDLER);
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
