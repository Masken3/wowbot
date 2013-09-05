#include <inttypes.h>
#include <lua.h>
#include <zlib.h>
#include <stdint.h>
#include <stdlib.h>
//#include <assert.h>
#include <string.h>

#include "movement.h"
#include "updateBlockFlags.h"
#include "Common.h"
#include "types.h"
#include "worldPacketParsersLua.h"
#include "world.h"
#include "log.h"
#include "dumpPacket.h"
#include "SharedDefines.h"
#include "QuestDef.h"

#ifdef WIN32
static size_t strnlen(const char* str, size_t maxlen) {
	const char* p = (char*)memchr(str, 0, maxlen);
	return p - str;
}
#endif

static void crash(void) {
	*(int*)NULL = 0;
}

#define assert(a) if(!(a)) { LOG("assert(%s) failed\n", #a); crash(); }
#define MLOG(...) //LOG

// These macros parse data from a server packet into a Lua table,
// which is on top of the Lua stack.

typedef uint64 Guid;
#define lua_push_Guid	lua_pushlstring(L, cur, 8)
static Guid local_Guid(const char* p) { return *(Guid*)p; }

#define lua_push_float lua_pushnumber(L, *(float*)cur)

#define lua_push_byte lua_pushnumber(L, *(byte*)cur)
static byte local_byte(const char* p) { return *p; }

#define lua_push_uint32 lua_pushnumber(L, *(uint32*)cur)
static uint32 local_uint32(const char* p) { return *(uint32*)p; }

#define lua_push_uint16 lua_pushnumber(L, *(uint16*)cur)
static uint16 local_uint16(const char* p) { return *(uint16*)p; }

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

#define _M_NAME(prefix, type, name, cur) lua_pushstring(L, #name);\
	MLOG(prefix " %s %s @ %x\n", #type, #name, (cur - buf))

#define _BASE_MA(type, name, count, push, doSize)\
	MLOG("MA %s %s %i @ %x\n", #type, #name, count, PL_PARSED);\
	{ uint32 c = (count); doSize;\
	lua_pushstring(L, #name);\
	lua_createtable(L, c, 0);\
	for(uint32 _i=1; _i<=c; _i++) { push; lua_rawseti(L, -2, _i); }\
	lua_settable(L, -3); }

// member
#define M(type, name) { PL_SIZE(sizeof(type));\
	_M_NAME("M", type, name, cur);\
	lua_push_##type;\
	lua_settable(L, -3); }
// member, with local copy
#define MM(type, name) type name; M(type, name); name = local_##type(ptr - sizeof(type))
// member array
#define MA(type, name, count)\
	_BASE_MA(type, name, count, lua_push_##type; cur += sizeof(type), PL_SIZE(sizeof(type) * c))
// member array, with local copy
#define MMA(type, name, count) type name[count];\
	_BASE_MA(type, name, count,\
	name[_i-1] = local_##type(cur); lua_push_##type; cur += sizeof(type),\
	PL_SIZE(sizeof(type) * c))
// member, variable length
#define MV(type, name)\
	_M_NAME("MV", type, name, ptr);\
	lua_vpush_##type;\
	lua_settable(L, -3);
// member array, variable element length
#define MAV(type, name, count)\
	_BASE_MA(type, name, count, lua_vpush_##type, )

#define lua_vpush_PackedGuid { uint64 guid = readPackGUID((byte**)&ptr, PL_REMAIN);\
	lua_pushlstring(L, (char*)&guid, 8); }

typedef const char* string;
#define lua_vpush_string {\
	int len = strnlen(ptr, PL_REMAIN);\
	assert(len < PL_REMAIN);\
	lua_pushlstring(L, ptr, len);\
	ptr += len +1; } // +1 for the terminating zero.

static uint64 readPackGUID(byte** src, int remain) {
	uint64 guid = 0;
	byte* ptr = *src;
	const uint8 guidmark = *(*src)++;
	//if(remain < 10)
		//dumpPacket((char*)ptr, remain);
	assert(guidmark != 0);
	for(int i = 0; i < 8; ++i) {
		if(guidmark & (1) << i) {
			uint8 bit = *(*src)++;
			if(remain < (*src - ptr)) {
				LOG("remain %i < %" PRIiPTR "\n", remain, (*src - ptr));
				crash();
			}
			guid |= ((uint64)bit) << (i * 8);
		}
	}
	return guid;
}

// helpers
#define PL_START lua_State* L = session->L; const char* ptr = buf; lua_newtable(L); assert(PL_REMAIN == bufSize)
#define PL_PARSED (ptr - buf)	// number of parsed bytes
#define PL_REMAIN (bufSize - PL_PARSED)	// number of unparsed bytes
#define PL_SIZE(size) const char* cur = ptr; assert((size) <= (size_t)PL_REMAIN); ptr += (size)

void pSMSG_MONSTER_MOVE(pLUA_ARGS) {
	PL_START;
	//dumpPacket(buf, bufSize);
	MV(PackedGuid, guid);
	M(Vector3, point);
	M(uint32, curTime);
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

// sub-parser
static void spMovementUpdate(lua_State* L, const char** src, const char* buf, int bufSize) {
	const char* ptr = *src;
	BOOL isOnTransport = FALSE;
	BOOL isFalling = FALSE;
	BOOL isAscending = FALSE;
	MM(byte, updateFlags);
	if(updateFlags & UPDATEFLAG_LIVING) {
		MM(uint32, moveFlags);
		isOnTransport = moveFlags & MOVEFLAG_ONTRANSPORT;
		isFalling = moveFlags & MOVEFLAG_FALLING;
		isAscending = moveFlags & MOVEFLAG_ASCENDING;
		assert(!isFalling);
		M(uint32, msTime);
	}
	if(updateFlags & UPDATEFLAG_HAS_POSITION) {
		if(isOnTransport) {
			M(Vector3, transportPos);
			M(float, transportOrientation);

			M(Guid, transportGuid);
			M(Vector3, transportOffset);
			M(float, transportOffsetOrientation);
		} else {
			M(Vector3, pos);
			M(float, orientation);
		}
	}

	if (updateFlags & UPDATEFLAG_LIVING)                    // 0x20
	{
		M(float, unk1);

		// Unit speeds
		M(float, walkSpeed);
		M(float, runSpeed);
		M(float, runBackSpeed);
		M(float, swimSpeed);
		M(float, swimBackSpeed);
		M(float, turnRate);

		if (isAscending)
		{
			M(uint32, unk2);
			M(uint32, unk3);
			M(uint32, unk4);
			M(uint32, unk5);
			{
				MM(uint32, posCount);
				MA(Vector3, positions, posCount + 1);
			}
		}
	}

	if (updateFlags & UPDATEFLAG_ALL) {
		M(uint32, unk6);
	}

	if (updateFlags & UPDATEFLAG_TRANSPORT) {
		M(uint32, transportTime);
	}
	*src = ptr;
}

void pMovementInfo(pLUA_ARGS) {
	PL_START;
	MV(PackedGuid, guid);
	{
		MM(uint32, flags);
		M(uint32, time);
		M(Vector3, pos);
		M(float, o);
		if(flags & MOVEFLAG_ONTRANSPORT) {
			M(Guid, tGuid);
			M(Vector3, tPos);
			M(float, tO);
		}
		if(flags & MOVEFLAG_SWIMMING) {
			M(float, sPitch);
		}
		M(uint32, fallTime);
		if(flags & MOVEFLAG_FALLING) {
			M(float, jumpVelocity);
			M(float, jumpSin);
			M(float, jumpCos);
			M(float, jumpXYSpeed);
		}
		if(flags & MOVEFLAG_SPLINE_ELEVATION) {
			M(uint32, unk1);
		}
	}
}

static void spValuesUpdate(lua_State* L, const char** src, const char* buf, int bufSize) {
	const char* ptr = *src;
	int count = 0;
	MM(byte, updateMaskBlockCount);
	{
		MMA(uint32, updateMask, updateMaskBlockCount);
		// Count the 1-bits in updateMask. That is the count of the uint32 values that follow.
		for(byte i=0; i<updateMaskBlockCount; i++) {
			int pc = __builtin_popcount(updateMask[i]);
			MLOG("0x%08x: pc %i\n", updateMask[i], pc);
			assert(count >= 0);
			count += pc;
		}
	}
	if(count > 0) {
		MA(uint32, values, count);
	}
	*src = ptr;
}

void pSMSG_UPDATE_OBJECT(pLUA_ARGS) {
	PL_START;
	//dumpBinaryFile("pSMSG_UPDATE_OBJECT.bin", buf, bufSize);
	{
		MM(uint32, blockCount);
		M(byte, hasTransport);

		lua_pushstring(L, "blocks");
		lua_createtable(L, blockCount, 0);
		MLOG("%i blocks\n", blockCount);
		for(uint32 i=1; i<=blockCount; i++) {
			lua_createtable(L, 0, 0); {
			MM(byte, type);
			MLOG("block type %i @ %x bytes\n", type, PL_PARSED);
			switch(type) {
			case UPDATETYPE_OUT_OF_RANGE_OBJECTS:
				{
					MM(uint32, count);
					MAV(PackedGuid, guids, count);
				}
				break;
			case UPDATETYPE_CREATE_OBJECT:
			case UPDATETYPE_CREATE_OBJECT2:
				MV(PackedGuid, guid);
				M(byte, objectTypeId);
				spMovementUpdate(L, &ptr, buf, bufSize);
				spValuesUpdate(L, &ptr, buf, bufSize);
				break;
			case UPDATETYPE_VALUES:
				MV(PackedGuid, guid);
				spValuesUpdate(L, &ptr, buf, bufSize);
				break;
			case UPDATETYPE_MOVEMENT:
				M(Guid, guid);
				spMovementUpdate(L, &ptr, buf, bufSize);
				break;
			case UPDATETYPE_NEAR_OBJECTS:
			default:
				LOG("Unknown update block type %i\n", type);
				exit(1);
			}
			lua_rawseti(L, -2, i);
		} }
		lua_settable(L, -3);
	}
}

void pSMSG_COMPRESSED_UPDATE_OBJECT(pLUA_ARGS) {
	// pSize is the size of the buffer that would have been passed to pSMSG_UPDATE_OBJECT.
	uint32 pSize = *(uint32*)buf;
	byte* inflatedBuf;
	int res;
	z_stream zs;

	MLOG("pSMSG_COMPRESSED_UPDATE_OBJECT %i -> %i\n", bufSize, pSize);
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
	free(inflatedBuf);
}

void pSMSG_GROUP_INVITE(pLUA_ARGS) {
	PL_START;
	MV(string, name);	// name of the player who invited us.
}

void pSMSG_GROUP_UNINVITE(pLUA_ARGS) {
}
void pSMSG_GROUP_DESTROYED(pLUA_ARGS) {
}

void pSMSG_GROUP_LIST(pLUA_ARGS) {
	PL_START;
	M(byte, groupType);
	M(byte, flags);
	{
		MM(uint32, memberCount);	// excluding yourself.
		// array of structs
		lua_pushstring(L, "members");
		lua_createtable(L, memberCount, 0);
		for(uint32 _i=1; _i<=memberCount; _i++) {
			lua_createtable(L, 0, 4);
			MV(string, name);
			M(Guid, guid);
			M(byte, online);
			M(byte, flags);
			lua_rawseti(L, -2, _i);
		}
		lua_settable(L, -3);
		M(Guid, leaderGuid);
		if(memberCount > 0) {
			M(byte, lootMethod);
			M(Guid, looterGuid);
			M(byte, lootThreshold);
		}
	}
}

void pSMSG_LOGIN_VERIFY_WORLD(pLUA_ARGS) {
	PL_START;
	M(uint32, mapId);
	M(Vector3, position);
	M(float, orientation);
}

void pSMSG_INITIAL_SPELLS(pLUA_ARGS) {
	PL_START;
	M(byte, unk1);
	{
		MM(uint16, spellCount);
		MA(uint32, spells, spellCount);
	}
	{
		MM(uint16, cooldownCount);
		// array of structs
		lua_pushstring(L, "cooldowns");
		lua_createtable(L, cooldownCount, 0);
		for(uint32 _i=1; _i<=cooldownCount; _i++) {
			lua_createtable(L, 0, 5);
			M(uint16, spellId);
			M(uint16, itemId);
			M(uint16, spellCategory);

			// if one is 0, the other has the cooldown in milliseconds.
			// if cooldown is 1 and categoryCooldown is 0x80000000, the cooldown is infinite.
			M(uint32, cooldown);
			M(uint32, categoryCooldown);
			lua_rawseti(L, -2, _i);
		}
		lua_settable(L, -3);
	}
}

void pSMSG_ATTACKSTART(pLUA_ARGS) {
	PL_START;
	M(Guid, attacker);
	M(Guid, victim);
}

void pSMSG_ATTACKSTOP(pLUA_ARGS) {
	PL_START;
	MV(PackedGuid, attacker);
	MV(PackedGuid, victim);
	M(uint32, unk);
}

void pSMSG_CAST_FAILED(pLUA_ARGS) {
	PL_START;
	M(uint32, spellId);
	{
		MM(byte, status);
		if(status == 0) {	// success
			return;
		} else if(status == 2) {	// fail
			MM(byte, result);
			if(result == SPELL_FAILED_REQUIRES_SPELL_FOCUS) {
				M(uint32, focus);
			} else if(result == SPELL_FAILED_EQUIPPED_ITEM_CLASS) {
				M(uint32, itemClass);
				M(uint32, itemSubClass);
				M(uint32, itemInventoryType);
			}
		} else {
			LOG("pSMSG_CAST_FAILED: unknown status %i\n", status);
		}
	}
}

void pEmpty(pLUA_ARGS) {
	PL_START;
	assert(bufSize == 0);
}

void pSMSG_QUESTGIVER_QUEST_DETAILS(pLUA_ARGS) {
	PL_START;
	M(Guid, guid);	// sharer's guid.
	M(uint32, questId);
	MV(string, title);
	MV(string, details);
	MV(string, objectives);
	M(uint32, activateAccept);	// always 1
	{
		MM(uint32, rewItemChoiceCount);
		lua_pushstring(L, "rewItemChoice");
		lua_createtable(L, rewItemChoiceCount, 0);
		for(uint32 i=1; i<=rewItemChoiceCount; i++) {
			lua_createtable(L, 0, 3);
			M(uint32, itemId);
			M(uint32, count);
			M(uint32, displayId);
			lua_rawseti(L, -2, i);
		}
		lua_settable(L, -3);
	}
	{
		MM(uint32, rewItemCount);
		lua_pushstring(L, "rewItem");
		lua_createtable(L, rewItemCount, 0);
		for(uint32 i=1; i<=rewItemCount; i++) {
			lua_createtable(L, 0, 3);
			M(uint32, itemId);
			M(uint32, count);
			M(uint32, displayId);
			lua_rawseti(L, -2, i);
		}
		lua_settable(L, -3);
	}
	M(uint32, rewMoney);	// may be negative.

	M(uint32, reqItemsCount);
	lua_pushstring(L, "reqItem");
	lua_createtable(L, QUEST_OBJECTIVES_COUNT, 0);
	for(uint32 i=1; i<=QUEST_OBJECTIVES_COUNT; i++) {
		lua_createtable(L, 0, 2);
		// if zero, slot is ignored.
		M(uint32, itemId);
		M(uint32, count);
		lua_rawseti(L, -2, i);
	}
	lua_settable(L, -3);

	M(uint32, reqCreatureOrGoCount);
	lua_pushstring(L, "reqCreatureOrGo");
	lua_createtable(L, QUEST_OBJECTIVES_COUNT, 0);
	for(uint32 i=1; i<=QUEST_OBJECTIVES_COUNT; i++) {
		lua_createtable(L, 0, 2);
		// if positive, is creature id. if negative, is negated GO id.
		// if zero, slot is ignored.
		M(uint32, id);
		M(uint32, count);
		lua_rawseti(L, -2, i);
	}
	lua_settable(L, -3);
}

static BOOL guidIsPlayer(Guid g) {
	return (g & 0xFFFF) == 0;
}

void pSMSG_MESSAGECHAT(pLUA_ARGS) {
	BOOL hasSenderGuid = FALSE;
	BOOL hasTargetGuid = FALSE;
	BOOL hasSenderName = FALSE;
	PL_START;
	{
		MM(byte, type);
		M(uint32, language);
		switch(type) {
		case CHAT_MSG_CHANNEL:
			MV(string, channelName);
			M(uint32, targetGuid2);	// always zero?
			hasSenderGuid = TRUE;
			break;
		case CHAT_MSG_SYSTEM:
			hasSenderGuid = TRUE;
			break;
		case CHAT_MSG_SAY:
		case CHAT_MSG_YELL:
		case CHAT_MSG_PARTY:
			M(Guid, senderGuid);
			// indentional fallthrough
		case CHAT_MSG_RAID:
		case CHAT_MSG_GUILD:
		case CHAT_MSG_OFFICER:
		case CHAT_MSG_WHISPER:
		case CHAT_MSG_RAID_LEADER:
		case CHAT_MSG_RAID_WARNING:
		case CHAT_MSG_BG_SYSTEM_NEUTRAL:
		case CHAT_MSG_BG_SYSTEM_ALLIANCE:
		case CHAT_MSG_BG_SYSTEM_HORDE:
		case CHAT_MSG_BATTLEGROUND:
		case CHAT_MSG_BATTLEGROUND_LEADER:
			hasSenderGuid = TRUE;
			break;
		case CHAT_MSG_MONSTER_SAY:
		case CHAT_MSG_MONSTER_PARTY:
		case CHAT_MSG_MONSTER_YELL:
		case CHAT_MSG_MONSTER_WHISPER:
		case CHAT_MSG_MONSTER_EMOTE:
		case CHAT_MSG_RAID_BOSS_WHISPER:
		case CHAT_MSG_RAID_BOSS_EMOTE:
			hasSenderGuid = TRUE;
			hasTargetGuid = TRUE;
			hasSenderName = TRUE;
			break;
		default:
			LOG("Error: unknown chat message type: %i\n", type);
		}
	}
	if(hasSenderGuid) {
		M(Guid, senderGuid);
	}
	if(hasSenderName) {
		M(uint32, senderNameLength);
		MV(string, senderName);
	}
	if(hasTargetGuid) {
		MM(Guid, targetGuid);
		if(!guidIsPlayer(targetGuid)) {
			M(uint32, targetNameLength);
			MV(string, targetName);
		}
	}
	M(uint32, textLength);
	MV(string, text);
	M(byte, tag);
}
