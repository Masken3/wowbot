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
#include "ItemPrototype.h"

static void spMovementInfo(lua_State* L, const char** src, const char* buf, int bufSize);

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
	spMovementInfo(L, &ptr, buf, bufSize);
}

static void spMovementInfo(lua_State* L, const char** src, const char* buf, int bufSize) {
	const char* ptr = *src;
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
	*src = ptr;
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
				M(uint32, itemSubClassMask);
				M(uint32, itemInventoryTypeMask);
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
	byte bType;
	PL_START;
	if(PL_REMAIN == 0)
		return;
	{
		MM(byte, type);
		bType = type;
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
		case CHAT_MSG_WHISPER_INFORM:
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
	if(sizeof(uint32) > (size_t)PL_REMAIN) {
		LOG("WARNING: SMSG_MESSAGECHAT interrupted. type %i.\n", bType);
		return;
	}
	M(uint32, textLength);
	MV(string, text);
	M(byte, tag);
}

void pSMSG_QUESTGIVER_STATUS(pLUA_ARGS) {
	PL_START;
	M(Guid, guid);
	M(uint32, status);
}

void pSMSG_QUESTGIVER_STATUS_MULTIPLE(pLUA_ARGS) {
	PL_START;
	{
		MM(uint32, count);
		lua_pushstring(L, "givers");
		lua_createtable(L, count, 0);
		for(uint32 i=1; i<=count; i++) {
			lua_createtable(L, 0, 2);
			M(Guid, guid);
			M(byte, status);
			lua_rawseti(L, -2, i);
		}
		lua_settable(L, -3);
	}
}

void pSMSG_QUESTGIVER_QUEST_LIST(pLUA_ARGS) {
	PL_START;
	M(Guid, guid);
	MV(string, title);
	M(uint32, playerEmote);
	M(uint32, npcEmote);
	{
		MM(byte, menuItemCount);
		lua_pushstring(L, "quests");
		lua_createtable(L, menuItemCount, 0);
		for(uint32 i=1; i<=menuItemCount; i++) {
			lua_createtable(L, 0, 4);
			M(uint32, questId);
			M(uint32, icon);	// DIALOG_STATUS_*
			M(uint32, level);
			MV(string, title);
			lua_rawseti(L, -2, i);
		}
		lua_settable(L, -3);
	}
}

void pSMSG_QUESTGIVER_OFFER_REWARD(pLUA_ARGS) {
	PL_START;
	M(Guid, guid);
	M(uint32, questId);
	MV(string, title);
	MV(string, offerRewardText);
	M(uint32, enableNext);
	{
		MM(uint32, emoteCount);
		lua_pushstring(L, "emotes");
		lua_createtable(L, emoteCount, 0);
		for(uint32 i=1; i<=emoteCount; i++) {
			lua_createtable(L, 0, 2);
			M(uint32, delay);
			M(uint32, id);
			lua_rawseti(L, -2, i);
		}
		lua_settable(L, -3);
	}
	{
		MM(uint32, rewChoiceItemsCount);
		lua_pushstring(L, "rewChoiceItems");
		lua_createtable(L, rewChoiceItemsCount, 0);
		for(uint32 i=1; i<=rewChoiceItemsCount; i++) {
			lua_createtable(L, 0, 3);
			M(uint32, itemId);
			M(uint32, count);
			M(uint32, displayId);
			lua_rawseti(L, -2, i);
		}
		lua_settable(L, -3);
	}
	{
		MM(uint32, rewItemsCount);
		lua_pushstring(L, "rewItems");
		lua_createtable(L, rewItemsCount, 0);
		for(uint32 i=1; i<=rewItemsCount; i++) {
			lua_createtable(L, 0, 3);
			M(uint32, itemId);
			M(uint32, count);
			M(uint32, displayId);
			lua_rawseti(L, -2, i);
		}
		lua_settable(L, -3);
	}
	M(uint32, rewMoney);
	M(uint32, rewSpellCast);
	M(uint32, rewSpell);
}

void pSMSG_QUESTGIVER_REQUEST_ITEMS(pLUA_ARGS) {
	PL_START;
	M(Guid, guid);
	M(uint32, questId);
	// lots of crap we don't need.
}

void pSMSG_QUESTGIVER_QUEST_COMPLETE(pLUA_ARGS) {
	PL_START;
	M(uint32, questId);
	// lots of crap we don't need.
}

void pSMSG_ITEM_QUERY_SINGLE_RESPONSE(pLUA_ARGS) {
	PL_START;
	{
		MM(uint32, itemId);
		if(itemId & 0x80000000) {
			LOG("Fatal error: SMSG_ITEM_QUERY_SINGLE_RESPONSE: Unknown item %i\n", itemId & ~0x80000000);
			exit(1);
		}
	}
	// lots of crap we do need. :/
	M(uint32, itemClass);
	M(uint32, subClass);
	MV(string, name);

	// these are always empty.
	MV(string, name2);
	MV(string, name3);
	MV(string, name4);

	M(uint32, DisplayInfoID);
	M(uint32, Quality);
	M(uint32, Flags);
	M(uint32, BuyPrice);
	M(uint32, SellPrice);
	M(uint32, InventoryType);
	M(uint32, AllowableClass);
	M(uint32, AllowableRace);
	M(uint32, ItemLevel);
	M(uint32, RequiredLevel);
	M(uint32, RequiredSkill);
	M(uint32, RequiredSkillRank);
	M(uint32, RequiredSpell);
	M(uint32, RequiredHonorRank);
	M(uint32, RequiredCityRank);
	M(uint32, RequiredReputationFaction);
	M(uint32, RequiredReputationRank);
	M(uint32, MaxCount);
	M(uint32, Stackable);
	M(uint32, ContainerSlots);

	lua_pushstring(L, "stats");
	lua_createtable(L, MAX_ITEM_PROTO_STATS, 0);
	for(uint32 i=1; i<=MAX_ITEM_PROTO_STATS; i++) {
		lua_createtable(L, 0, 2);
		M(uint32, type);
		M(uint32, value);
		lua_rawseti(L, -2, i);
	}
	lua_settable(L, -3);

	lua_pushstring(L, "damages");
	lua_createtable(L, MAX_ITEM_PROTO_DAMAGES, 0);
	for(uint32 i=1; i<=MAX_ITEM_PROTO_DAMAGES; i++) {
		lua_createtable(L, 0, 3);
		M(float, min);
		M(float, max);
		M(uint32, type);
		lua_rawseti(L, -2, i);
	}
	lua_settable(L, -3);

	M(uint32, Armor);
	M(uint32, HolyRes);
	M(uint32, FireRes);
	M(uint32, NatureRes);
	M(uint32, FrostRes);
	M(uint32, ShadowRes);
	M(uint32, ArcaneRes);

	M(uint32, Delay);
	M(uint32, AmmoType);
	M(float, RangedModRange);

	lua_pushstring(L, "spells");
	lua_createtable(L, MAX_ITEM_PROTO_SPELLS, 0);
	for(uint32 i=1; i<=MAX_ITEM_PROTO_SPELLS; i++) {
		lua_createtable(L, 0, 6);
		M(uint32, id);
		M(uint32, trigger);
		M(uint32, charges);
		M(uint32, cooldown);
		M(uint32, category);
		M(uint32, categoryCooldown);
		lua_rawseti(L, -2, i);
	}
	lua_settable(L, -3);

	M(uint32, Bonding);
	MV(string, description);
	M(uint32, PageText);
	M(uint32, LanguageID);
	M(uint32, PageMaterial);
	M(uint32, StartQuest);
	M(uint32, LockID);
	M(uint32, Material);
	M(uint32, Sheath);
	M(uint32, RandomProperty);
	M(uint32, Block);
	M(uint32, ItemSet);
	M(uint32, MaxDurability);
	M(uint32, Area);
	M(uint32, Map);
	M(uint32, BagFamily);
}

void pSMSG_ITEM_PUSH_RESULT(pLUA_ARGS) {
	PL_START;
	M(Guid, playerGuid);
	M(uint32, received);	// 0=looted, 1=from npc
	M(uint32, created);	// 0=received, 1=created
	M(uint32, showChatMessage);
	M(byte, bagSlot);	// slot of bag in which the item is stored.
	M(uint32, itemSlot);	// item's slot in bag. 0xFFFFFFFF if part of a stack.
	M(uint32, itemId);
	M(uint32, itemSuffixFactor);
	M(uint32, itemRandomPropertyId);
	M(uint32, newCount);
	M(uint32, inventoryCount);
}

void pSMSG_TRADE_STATUS(pLUA_ARGS) {
	PL_START;
	{
		MM(uint32, status);
		if(status == TRADE_STATUS_BEGIN_TRADE) {
			// is 0 if you were the one who initiated the trade.
			M(Guid, guid);
		}
	}
}

void pSMSG_TRADE_STATUS_EXTENDED(pLUA_ARGS) {
	PL_START;
	M(byte, trader_state);
	{
		MM(uint32, count);
		{
			MM(uint32, count2);
			assert(count == count2);
		}
		M(uint32, money);
		M(uint32, spell);	// spell cast on lowest slot item
		lua_pushstring(L, "items");
		lua_createtable(L, count, 0);
		for(uint32 i=0; i<count; i++) {
			lua_createtable(L, 0, 14);
			M(byte, i);
			M(uint32, itemId);
			M(uint32, displayInfoID);
			M(uint32, count);
			M(uint32, isWrapped);
			M(Guid, wrapperGuid);
			M(uint32, enchantment);
			M(Guid, creatorGuid);
			M(uint32, charges);
			M(uint32, suffixFactor);
			M(uint32, randomProprtyId);
			M(uint32, lockId);
			M(uint32, maxDurability);
			M(uint32, durability);
			lua_rawseti(L, -2, i);
		}
		lua_settable(L, -3);
	}
}

void pSMSG_NAME_QUERY_RESPONSE(pLUA_ARGS) {
	PL_START;
	M(Guid, guid);
	MV(string, name);
	MV(string, realmName);
	M(uint32, race);
	M(uint32, gender);
	M(uint32, _class);
}

void pSMSG_LOOT_RESPONSE(pLUA_ARGS) {
	PL_START;
	M(Guid, guid);
	M(byte, lootType);
	M(uint32, gold);
	{
		MM(byte, itemCount);
		lua_pushstring(L, "items");
		lua_createtable(L, itemCount, 0);
		for(uint32 i=1; i<=itemCount; i++) {
			lua_createtable(L, 0, 7);
			M(byte, lootSlot);
			M(uint32, itemId);
			M(uint32, count);
			M(uint32, displayId);
			M(uint32, unk);
			M(uint32, randomPropertyId);
			M(byte, lootSlotType);
			lua_rawseti(L, -2, i);
		}
		lua_settable(L, -3);
	}
}

void pSMSG_QUEST_QUERY_RESPONSE(pLUA_ARGS) {
	PL_START;
	M(uint32, questId);
	M(uint32, method);
	M(uint32, level);
	M(uint32, zoneOrSort);
	M(uint32, type);
	M(uint32, repObjectiveFaction);
	M(uint32, repObjectiveValue);
	M(uint32, requiredOppositeRepFaction);	// always zero
	M(uint32, requiredOppositeRepValue);	// always zero
	M(uint32, nextQuestInChain);
	M(uint32, money);
	M(uint32, moneyAtMaxLevel);
	M(uint32, rewSpell);
	M(uint32, srcItemId);
	M(uint32, flags);

	lua_pushstring(L, "rewItems");
	lua_createtable(L, QUEST_REWARDS_COUNT, 0);
	for(uint32 i=1; i<=QUEST_REWARDS_COUNT; i++) {
		lua_createtable(L, 0, 2);
		M(uint32, itemId);
		M(uint32, count);
		lua_rawseti(L, -2, i);
	}
	lua_settable(L, -3);

	lua_pushstring(L, "rewChoiceItems");
	lua_createtable(L, QUEST_REWARD_CHOICES_COUNT, 0);
	for(uint32 i=1; i<=QUEST_REWARD_CHOICES_COUNT; i++) {
		lua_createtable(L, 0, 2);
		M(uint32, itemId);
		M(uint32, count);
		lua_rawseti(L, -2, i);
	}
	lua_settable(L, -3);

	M(uint32, mapId);
	M(float, x);
	M(float, y);
	M(float, opt);
	MV(string, title);
	MV(string, objectives);
	MV(string, details);
	MV(string, endtext);

	lua_pushstring(L, "objectives");
	lua_createtable(L, QUEST_OBJECTIVES_COUNT, 0);
	for(uint32 i=1; i<=QUEST_OBJECTIVES_COUNT; i++) {
		lua_createtable(L, 0, 5);
		M(uint32, creatureOrGoId);	// GO (& 0x80000000).
		M(uint32, creatureOrGoCount);
		M(uint32, itemId);
		M(uint32, itemCount);
		lua_rawseti(L, -2, i);
	}
	for(uint32 i=1; i<=QUEST_OBJECTIVES_COUNT; i++) {
		lua_rawgeti(L, -1, i);
		MV(string, text);
		lua_pop(L, 1);
	}
	lua_settable(L, -3);
}

void pSMSG_LOOT_RELEASE_RESPONSE(pLUA_ARGS) {
	PL_START;
	M(Guid, guid);
	M(byte, unk);	// always 1
}

void pMSG_MOVE_TELEPORT_ACK(pLUA_ARGS) {
	PL_START;
	MV(PackedGuid, guid);
	M(uint32, counter);
	spMovementInfo(L, &ptr, buf, bufSize);
}

void pSMSG_GOSSIP_MESSAGE(pLUA_ARGS) {
	PL_START;
	M(Guid, guid);
	M(uint32, titleTextId);
	{
		MM(uint32, gossipCount);
		assert(gossipCount <= 0x20);
		lua_pushstring(L, "gossips");
		lua_createtable(L, gossipCount, 0);
		for(uint32 i=1; i<=gossipCount; i++) {
			lua_createtable(L, 0, 4);
			M(uint32, index);	// value: i-1
			M(byte, icon);	// enum GossipOptionIcon
			M(byte, coded);
			MV(string, message);
			lua_rawseti(L, -2, i);
		}
		lua_settable(L, -3);
	}
	{
		MM(uint32, questCount);
		assert(questCount <= 0x20);
		lua_pushstring(L, "quests");
		lua_createtable(L, questCount, 0);
		for(uint32 i=1; i<=questCount; i++) {
			lua_createtable(L, 0, 4);
			M(uint32, questId);
			M(uint32, icon);	// enum __QuestGiverStatus
			M(uint32, level);
			MV(string, title);
			lua_rawseti(L, -2, i);
		}
		lua_settable(L, -3);
	}
}

void pSMSG_CREATURE_QUERY_RESPONSE(pLUA_ARGS) {
	PL_START;
	{
		MM(uint32, entry);
		if(entry & 0x80000000) {
			LOG("WARNING: NO CREATURE INFO for entry %i\n", entry & ~0x80000000);
			return;
		}
	}
	MV(string, name);
	MV(string, name2);
	MV(string, name3);
	MV(string, name4);
	MV(string, subName);
	M(uint32, typeFlags);
	M(uint32, type);
	M(uint32, family);
	M(uint32, rank);
	M(uint32, unk);
	M(uint32, petSpellDataId);
	M(uint32, displayId);
	M(uint16, civilian);
}

void pSMSG_DESTROY_OBJECT(pLUA_ARGS) {
	PL_START;
	M(Guid, guid);
}

void pSMSG_TRAINER_LIST(pLUA_ARGS) {
	PL_START;
	M(Guid, guid);
	M(uint32, trainerType);
	{
		MM(uint32, count);
		lua_pushstring(L, "spells");
		lua_createtable(L, count, 0);
		for(uint32 i=1; i<=count; i++) {
			lua_createtable(L, 0, 11);
			M(uint32, spellId);
			M(byte, state);
			M(uint32, cost);
			M(uint32, primaryProfCanLearn);
			M(uint32, primaryProfFirstRank);
			M(byte, reqCLevel);
			M(uint32, reqSkill);
			M(uint32, reqSkillValue);
			M(uint32, chainPrev);
			M(uint32, chainReq);
			M(uint32, unk);	// always zero.
			lua_rawseti(L, -2, i);
		}
		lua_settable(L, -3);
	}
	MV(string, title);
}

void pSMSG_TRAINER_BUY_SUCCEEDED(pLUA_ARGS) {
	PL_START;
	M(Guid, guid);
	M(uint32, spellId);
}

void pSMSG_SET_EXTRA_AURA_INFO(pLUA_ARGS) {
	PL_START;
	MV(PackedGuid, targetGuid);
	M(byte, auraSlot);
	M(uint32, spellId);
	M(uint32, maxDuration);
	M(uint32, duration);
}

void pMSG_RAID_TARGET_UPDATE(pLUA_ARGS) {
	static const uint TARGET_ICON_COUNT = 8;
	PL_START;
	{
		MM(byte, updateType);
		if(updateType == 0) {
			M(byte, id);
			M(Guid, guid);
		} else if(updateType == 1) {
			lua_pushstring(L, "icons");
			lua_createtable(L, TARGET_ICON_COUNT, 0);
			for(uint32 i=1; i<=TARGET_ICON_COUNT; i++) {
				lua_createtable(L, 0, 2);
				M(byte, id);
				M(Guid, guid);
				lua_rawseti(L, -2, i);
			}
			lua_settable(L, -3);
		} else {
			LOG("ERROR: MSG_RAID_TARGET_UPDATE updateType 0x%02x\n", updateType);
		}
	}
}

void pSMSG_GAMEOBJECT_QUERY_RESPONSE(pLUA_ARGS) {
	PL_START;
	{
		MM(uint32, goId);
		if(goId & 0x80000000) {
			LOG("Fatal error: SMSG_GAMEOBJECT_QUERY_RESPONSE: Unknown object %i\n", goId & ~0x80000000);
			exit(1);
		}
	}
	M(uint32, type);	// enum GameobjectTypes
	M(uint32, displayId);
	MV(string, name);
	M(uint16, name2);
	M(byte, name3);
	M(byte, name4);
	MA(uint32, data, 24);	// see union in GameObjectInfo in GameObject.h
}

void pMSG_MINIMAP_PING(pLUA_ARGS) {
	PL_START;
	// we're not interested.
}

void pSMSG_NOTIFICATION(pLUA_ARGS) {
	PL_START;
	MV(string, msg);
}

void pSMSG_GAMEOBJECT_CUSTOM_ANIM(pLUA_ARGS) {
	PL_START;
	M(Guid, guid);
	M(uint32, animId);
}

void pSMSG_LEARNED_SPELL(pLUA_ARGS) {
	PL_START;
	M(uint32, spellId);
}

void pSMSG_GAMEOBJECT_DESPAWN_ANIM(pLUA_ARGS) {
	PL_START;
	M(Guid, guid);
}

void pSMSG_LOOT_START_ROLL(pLUA_ARGS) {
	PL_START;
	M(Guid, lootedTarget);
	M(uint32, slot);
	M(uint32, itemId);
	M(uint32, dummy);
	M(uint32, randomPropId);
	M(uint32, countDown);
}

void pSMSG_SPELL_START(pLUA_ARGS) {
	PL_START;
	MV(PackedGuid, casterItemGuid);
	MV(PackedGuid, casterGuid);
	M(uint32, spellId);
	M(uint16, castFlags);
	M(uint32, timer);
	// todo: targets et.al
}

void pSMSG_SPELL_GO(pLUA_ARGS) {
	PL_START;
	// this one, however:
	MV(PackedGuid, casterItemGuid);
	MV(PackedGuid, casterGuid);
	M(uint32, spellId);
	M(uint16, castFlags);

#if 0
	WriteSpellGoTargets(&data);

	data << m_targets;

	if (castFlags & CAST_FLAG_AMMO)
		WriteAmmoToPacket(&data);
#endif
}

void pSMSG_SPELL_FAILURE(pLUA_ARGS) {
	PL_START;
	MV(PackedGuid, casterGuid);
	M(uint32, spellId);
	M(byte, result);
}

void pSMSG_SPELL_FAILED_OTHER(pLUA_ARGS) {
	PL_START;
	M(Guid, casterGuid);
	M(uint32, spellId);
}

void pSMSG_QUEST_CONFIRM_ACCEPT(pLUA_ARGS) {
	PL_START;
	M(uint32, questId);
	MV(string, title);
	M(Guid, starterGuid);
}
