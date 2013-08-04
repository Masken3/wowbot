
#include <lua.h>
#include <zlib.h>
#include <stdint.h>
//#include <assert.h>

#include "movementFlags.h"
#include "updateBlockFlags.h"
#include "Common.h"
#include "types.h"
#include "worldPacketParsersLua.h"
#include "world.h"
#include "log.h"
#include "dumpPacket.h"

static void crash(void) {
	*(int*)NULL = 0;
}

#define assert(a) if(!(a)) { LOG("assert(%s) failed\n", #a); crash(); }

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
// member array, variable element length
#define MAV(type, name, count) { uint32 c = (count);\
	lua_pushstring(L, #name);\
	lua_createtable(L, c, 0);\
	for(uint32 _i=1; _i<=c; _i++) { lua_vpush_##type; lua_rawseti(L, -2, _i); }\
	lua_settable(L, -3); }

#define lua_vpush_PackedGuid { uint64 guid = readPackGUID((byte**)&ptr, PL_REMAIN);\
	lua_pushlstring(L, (char*)&guid, 8); }

static uint64 readPackGUID(byte** src, int remain) {
	uint64 guid = 0;
	byte* ptr = *src;
	const uint8 guidmark = *(*src)++;
	if(remain < 10)
		dumpPacket((char*)ptr, remain);
	assert(guidmark != 0);
	for(int i = 0; i < 8; ++i) {
		if(guidmark & (1) << i) {
			uint8 bit = *(*src)++;
			if(remain < (*src - ptr)) {
				LOG("remain %i < %i\n", remain, (*src - ptr));
				crash();
			}
			guid |= ((uint64)bit) << (i * 8);
		}
	}
	return guid;
}

// helpers
#define PL_START lua_State* L = session->L; char* ptr = buf; lua_newtable(L); assert(PL_REMAIN == bufSize)
#define PL_PARSED (ptr - buf)	// number of parsed bytes
#define PL_REMAIN (bufSize - PL_PARSED)	// number of unparsed bytes
#define PL_SIZE(size) char* cur = ptr; assert((size) <= (size_t)PL_REMAIN); ptr += (size)

void pSMSG_MONSTER_MOVE(pLUA_ARGS) {
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

void pSMSG_UPDATE_OBJECT(pLUA_ARGS) {
	PL_START;
	dumpPacket(buf, bufSize);
	{
		MM(uint32, blockCount);
		M(byte, hasTransport);

		lua_pushstring(L, "blocks");
		lua_createtable(L, blockCount, 0);
		for(uint32 i=1; i<=blockCount; i++) {
			MM(byte, type);
			lua_createtable(L, 0, 0);
			switch(type) {
			case UPDATETYPE_OUT_OF_RANGE_OBJECTS:
				{
					MM(uint32, count);
					MAV(PackedGuid, guids, count);
				}
				break;
			case UPDATETYPE_NEAR_OBJECTS:
			case UPDATETYPE_VALUES:
			case UPDATETYPE_MOVEMENT:
			case UPDATETYPE_CREATE_OBJECT:
			case UPDATETYPE_CREATE_OBJECT2:
			default:
				LOG("Unknown update block type %i\n", type);
				exit(1);
			}
			lua_rawseti(L, -2, i);
		}
		lua_settable(L, -3);
	}
}

void pSMSG_COMPRESSED_UPDATE_OBJECT(pLUA_ARGS) {
	// pSize is the size of the buffer that would have been passed to pSMSG_UPDATE_OBJECT.
	uint32 pSize = *(uint32*)buf;
	byte* inflatedBuf;
	int res;
	z_stream zs;

	LOG("pSMSG_COMPRESSED_UPDATE_OBJECT %i -> %i\n", bufSize, pSize);
	//dumpPacket(buf, bufSize);

	assert(pSize < UINT16_MAX);

	memset(&zs, 0, sizeof(zs));
	res = inflateInit(&zs);
	assert(res == Z_OK);
	zs.next_in = (byte*)buf + sizeof(uint32);
	zs.avail_in = bufSize - sizeof(uint32);
	zs.next_out = inflatedBuf = (byte*)malloc(pSize);
	zs.avail_out = pSize;
	res = inflate(&zs, Z_FINISH);
	if(res != Z_STREAM_END) {
		LOG("inflate error %i\n", res);
		exit(1);
	}
	assert(zs.total_out == pSize);
	assert(zs.avail_in == 0);
	res = inflateEnd(&zs);
	assert(res == Z_OK);

	pSMSG_UPDATE_OBJECT(session, (char*)inflatedBuf, pSize);
	free(zs.next_out);
}
