#include "worldPacketGeneratorsLua.h"
#include "movement.h"
#include "Opcodes.h"
#include "DBCEnums.h"
#include "SharedDefines.h"
#include "log.h"
#include <lua.h>
#include <lauxlib.h>
#include "lua_version.h"
#include <string.h>
#include <assert.h>

#define MLOG(...) //LOG

#define GL_START byte* ptr = buf;
#define GL_END assert(ptr - buf < UINT16_MAX); return ptr - buf

static void lua_gen_uint32(lua_State* L, const char* name, byte** pp) {
	if(!lua_isnumber(L, -1)) {
		luaL_error(L, "gen error: %s is not a number!", name);
	}
	*(uint32*)(*pp) = lua_tointeger(L, -1);
	(*pp) += 4;
}

static void lua_gen_uint16(lua_State* L, const char* name, byte** pp) {
	uint32 num = lua_tointeger(L, -1);
	if(!lua_isnumber(L, -1)) {
		luaL_error(L, "gen error: %s is not a number!", name);
	}
	if(num > 0xFFFF) {
		luaL_error(L, "gen error: %s is too big to fit in an uint16 (0x%x)!", name, num);
	}
	*(uint16*)(*pp) = (uint16)num;
	(*pp) += 2;
}

static void lua_gen_byte(lua_State* L, const char* name, byte** pp) {
	uint32 num = lua_tointeger(L, -1);
	if(!lua_isnumber(L, -1)) {
		luaL_error(L, "gen error: %s is not a number!", name);
	}
	if(num > 0xFF) {
		luaL_error(L, "gen error: %s is too big to fit in a byte (0x%x)!", name, num);
	}
	**pp = (byte)num;
	(*pp) += 1;
}

static void lua_gen_float(lua_State* L, const char* name, byte** pp) {
	if(!lua_isnumber(L, -1)) {
		luaL_error(L, "gen error: %s is not a number!", name);
	}
	*(float*)(*pp) = (float)lua_tonumber(L, -1);
	(*pp) += 4;
}

static void lua_gen_Vector3(lua_State* L, const char* name, byte** pp) {
	if(!lua_istable(L, -1)) {
		lua_pushfstring(L, "gen error: %s is not a table!", name);
		lua_error(L);
	}
	lua_pushstring(L, "x");
	lua_gettable(L, -2);
	lua_gen_float(L, "x", pp);
	lua_pop(L, 1);
	lua_pushstring(L, "y");
	lua_gettable(L, -2);
	lua_gen_float(L, "y", pp);
	lua_pop(L, 1);
	lua_pushstring(L, "z");
	lua_gettable(L, -2);
	lua_gen_float(L, "z", pp);
	lua_pop(L, 1);
}

static void lua_check_Guid(lua_State* L, const char* name) {
	int len;
	if(!lua_isstring(L, -1)) {
		lua_pushfstring(L, "gen error: %s is not a string!", name);
		lua_error(L);
	}
	len = luaL_getn(L, -1);
	if(len != 8) {
		lua_pushfstring(L, "gen error: %s does not have the correct length!", name);
		lua_error(L);
	}
}

#if 1
static void lua_gen_PackedGuid(lua_State* L, const char* name, byte** pp) {
	lua_check_Guid(L, name);
	{
		const byte* raw = (byte*)lua_tostring(L, -1);
		byte* guidmark = *pp;
		byte* ptr = guidmark + 1;
		*guidmark = 0;
		for(byte i = 0; i < 8; ++i) {
			if(raw[i] != 0) {
				*guidmark |= 1 << i;
				*(ptr++) = raw[i];
			}
		}
		*pp = ptr;
	}
}
#endif

static void lua_gen_string(lua_State* L, const char* name, byte** pp) {
	size_t len;
	const char* str = lua_tolstring(L, -1, &len);
	if(str == NULL) {
		luaL_error(L, "gen error: %s is not a string!", name);
	}
	memcpy(*pp, str, len+1);
	*pp += len+1;
}

static void lua_gen_Guid(lua_State* L, const char* name, byte** pp) {
	lua_check_Guid(L, name);
	memcpy(*pp, lua_tostring(L, -1), 8);
	*pp += 8;
}

#define M(type, name) do {\
	MLOG("M(%s, %s)\n", #type, #name);\
	lua_pushstring(L, #name);\
	lua_gettable(L, -2);\
	lua_gen_##type(L, #name, &ptr);\
	lua_pop(L, 1);\
	} while(0)

#define MM(type, name) type name; {\
	byte* cur = ptr;\
	M(type, name);\
	name = *(type*)cur; }\

#define MV M

static uint16 genMovement(lua_State* L, byte* buf) {
	GL_START;
	// unlike the server version of this packet, the client version does not send PackedGuid.
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
	GL_END;
}

static void spellTargets(lua_State* L, byte** pp) {
	byte* ptr = *pp;
	{
		MM(uint16, targetFlags);

		if (targetFlags & (TARGET_FLAG_UNIT | TARGET_FLAG_UNK2))
			M(PackedGuid, unitTarget);

		if (targetFlags & (TARGET_FLAG_OBJECT | TARGET_FLAG_OBJECT_UNK))
			M(PackedGuid, goTarget);

		if (targetFlags & (TARGET_FLAG_ITEM | TARGET_FLAG_TRADE_ITEM))
			M(PackedGuid, itemTarget);

		if (targetFlags & TARGET_FLAG_SOURCE_LOCATION)
			M(Vector3, srcPosition);

		if (targetFlags & TARGET_FLAG_DEST_LOCATION)
			M(Vector3, dstPosition);

		if (targetFlags & TARGET_FLAG_STRING)
			M(string, strTarget);

		if (targetFlags & (TARGET_FLAG_CORPSE | TARGET_FLAG_PVP_CORPSE))
			M(PackedGuid, corpseTarget);
	}
	*pp = ptr;
}

static uint16 genCMSG_CAST_SPELL(lua_State* L, byte* buf) {
	GL_START;
	M(uint32, spellId);
	spellTargets(L, &ptr);
	GL_END;
}

static uint16 genCMSG_USE_ITEM(lua_State* L, byte* buf) {
	GL_START;
	M(byte, bag);
	M(byte, slot);
	M(byte, spellCount);
	spellTargets(L, &ptr);
	GL_END;
}

static uint16 genCMSG_CANCEL_CAST(lua_State* L, byte* buf) {
	GL_START;
	M(uint32, spellId);
	GL_END;
}

static uint16 genCMSG_SET_SELECTION(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, target);
	GL_END;
}

static uint16 genCMSG_ATTACKSWING(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, target);
	GL_END;
}

static uint16 genCMSG_QUESTGIVER_ACCEPT_QUEST(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, guid);
	M(uint32, questId);
	GL_END;
}

static uint16 genCMSG_MESSAGECHAT(lua_State* L, byte* buf) {
	GL_START;
	{
		MM(uint32, type);
		M(uint32, language);
		switch (type) {
		case CHAT_MSG_SAY:
		case CHAT_MSG_EMOTE:
		case CHAT_MSG_YELL:
		case CHAT_MSG_PARTY:
		case CHAT_MSG_GUILD:
		case CHAT_MSG_OFFICER:
		case CHAT_MSG_RAID:
		case CHAT_MSG_RAID_LEADER:
		case CHAT_MSG_RAID_WARNING:
		case CHAT_MSG_BATTLEGROUND:
		case CHAT_MSG_BATTLEGROUND_LEADER:
		case CHAT_MSG_AFK:
		case CHAT_MSG_DND:
			// message only
			break;
		case CHAT_MSG_WHISPER:
			// also "to"
			M(string, targetName);
			break;
		case CHAT_MSG_CHANNEL:
			// also string channel name
			M(string, channelName);
			break;
		default:
			lua_pushfstring(L, "gen error: unknown chat type: %i", type);
			lua_error(L);
		}
		M(string, msg);
	}
	GL_END;
}

static uint16 genCMSG_QUESTLOG_REMOVE_QUEST(lua_State* L, byte* buf) {
	GL_START;
	M(byte, slot);
	GL_END;
}

static uint16 genCMSG_QUESTGIVER_STATUS_QUERY(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, guid);
	GL_END;
}

static uint16 genCMSG_QUESTGIVER_HELLO(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, guid);
	GL_END;
}

static uint16 genCMSG_QUESTGIVER_REQUEST_REWARD(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, guid);
	M(uint32, questId);
	GL_END;
}

static uint16 genCMSG_QUESTGIVER_CHOOSE_REWARD(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, guid);
	M(uint32, questId);
	M(uint32, reward);
	GL_END;
}

static uint16 genCMSG_QUESTGIVER_COMPLETE_QUEST(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, guid);
	M(uint32, questId);
	GL_END;
}

static uint16 genCMSG_ITEM_QUERY_SINGLE(lua_State* L, byte* buf) {
	GL_START;
	M(uint32, itemId);
	M(Guid, guid);
	GL_END;
}

static uint16 genCMSG_AUTOEQUIP_ITEM_SLOT(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, itemGuid);
	M(byte, dstSlot);
	GL_END;
}

static uint16 genCMSG_DESTROYITEM(lua_State* L, byte* buf) {
	GL_START;
	M(byte, bag);
	M(byte, slot);
	M(byte, count);
	// 3 bytes padding.
	ptr += 3;
	GL_END;
}

static uint16 genCMSG_INITIATE_TRADE(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, guid);
	GL_END;
}

static uint16 genCMSG_SET_TRADE_ITEM(lua_State* L, byte* buf) {
	GL_START;
	M(byte, tradeSlot);
	M(byte, bag);
	M(byte, slot);
	GL_END;
}

static uint16 genCMSG_ACCEPT_TRADE(lua_State* L, byte* buf) {
	GL_START;
	M(uint32, padding);
	GL_END;
}

static uint16 genCMSG_CHAR_DELETE(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, guid);
	GL_END;
}

static uint16 genCMSG_NAME_QUERY(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, guid);
	GL_END;
}

static uint16 genCMSG_GROUP_INVITE(lua_State* L, byte* buf) {
	GL_START;
	M(string, name);
	GL_END;
}

static uint16 genCMSG_GROUP_SET_LEADER(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, guid);
	GL_END;
}

static uint16 genCMSG_LOOT(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, guid);
	GL_END;
}

static uint16 genCMSG_AUTOSTORE_LOOT_ITEM(lua_State* L, byte* buf) {
	GL_START;
	M(byte, lootSlot);
	GL_END;
}

static uint16 genCMSG_LOOT_RELEASE(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, guid);
	GL_END;
}

static uint16 genCMSG_QUEST_QUERY(lua_State* L, byte* buf) {
	GL_START;
	M(uint32, questId);
	GL_END;
}

// client's format is different from server's.
static uint16 genMSG_MOVE_TELEPORT_ACK(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, guid);
	M(uint32, counter);
	M(uint32, time);
	GL_END;
}

static uint16 genCMSG_CREATURE_QUERY(lua_State* L, byte* buf) {
	GL_START;
	M(uint32, entry);
	M(Guid, guid);
	GL_END;
}

static uint16 genCMSG_TRAINER_LIST(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, guid);
	GL_END;
}

static uint16 genCMSG_TRAINER_BUY_SPELL(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, guid);
	M(uint32, spellId);
	GL_END;
}

static uint16 genCMSG_CANCEL_AURA(lua_State* L, byte* buf) {
	GL_START;
	M(uint32, spellId);
	GL_END;
}

static uint16 genCMSG_GAMEOBJ_USE(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, guid);
	GL_END;
}

static uint16 genCMSG_GAMEOBJECT_QUERY(lua_State* L, byte* buf) {
	GL_START;
	M(uint32, id);
	M(Guid, guid);
	GL_END;
}

static uint16 genMSG_MINIMAP_PING(lua_State* L, byte* buf) {
	GL_START;
	M(float, x);
	M(float, y);
	GL_END;
}

static uint16 genCMSG_SELL_ITEM(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, vendorGuid);
	M(Guid, itemGuid);
	M(byte, count);
	GL_END;
}

// automoves an item from bank or inventory.
// source slot is specified.
static uint16 genCMSG_AUTOSTORE_BANK_ITEM(lua_State* L, byte* buf) {
	GL_START;
	M(byte, bag);
	M(byte, slot);
	GL_END;
}

static uint16 genCMSG_REPAIR_ITEM(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, npcGuid);
	M(Guid, itemGuid);
	GL_END;
}

static uint16 genCMSG_LEARN_TALENT(lua_State* L, byte* buf) {
	GL_START;
	M(uint32, talentId);
	M(uint32, requestedRank);
	GL_END;
}

static uint16 genCMSG_LOOT_ROLL(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, lootedTarget);
	M(uint32, slot);
	M(byte, rollType);
	GL_END;
}

static uint16 genCMSG_QUESTGIVER_QUERY_QUEST(lua_State* L, byte* buf) {
	GL_START;
	M(Guid, guid);
	M(uint32, questId);
	GL_END;
}

static uint16 genCMSG_CANCEL_CHANNELLING(lua_State* L, byte* buf) {
	GL_START;
	M(uint32, spellId);
	GL_END;
}

PacketGenerator getPacketGenerator(int opcode) {
#define MOVEMENT_CASE(name) case name: return genMovement;
#define GEN_CASE(name) case name: return gen##name;
	switch(opcode) {
		MOVEMENT_OPCODES(MOVEMENT_CASE);
		GEN_CASE(CMSG_CAST_SPELL);
		GEN_CASE(CMSG_CANCEL_CAST);
		GEN_CASE(CMSG_SET_SELECTION);
		GEN_CASE(CMSG_ATTACKSWING);
		GEN_CASE(CMSG_QUESTGIVER_ACCEPT_QUEST);
		GEN_CASE(CMSG_MESSAGECHAT);
		GEN_CASE(CMSG_QUESTLOG_REMOVE_QUEST);
		GEN_CASE(CMSG_QUESTGIVER_STATUS_QUERY);
		GEN_CASE(CMSG_QUESTGIVER_HELLO);
		GEN_CASE(CMSG_QUESTGIVER_REQUEST_REWARD);
		GEN_CASE(CMSG_QUESTGIVER_CHOOSE_REWARD);
		GEN_CASE(CMSG_QUESTGIVER_COMPLETE_QUEST);
		GEN_CASE(CMSG_ITEM_QUERY_SINGLE);
		GEN_CASE(CMSG_AUTOEQUIP_ITEM_SLOT);
		GEN_CASE(CMSG_DESTROYITEM);
		GEN_CASE(CMSG_INITIATE_TRADE);
		GEN_CASE(CMSG_SET_TRADE_ITEM);
		GEN_CASE(CMSG_ACCEPT_TRADE);
		GEN_CASE(CMSG_CHAR_DELETE);
		GEN_CASE(CMSG_NAME_QUERY);
		GEN_CASE(CMSG_GROUP_INVITE);
		GEN_CASE(CMSG_GROUP_SET_LEADER);
		GEN_CASE(CMSG_LOOT);
		GEN_CASE(CMSG_AUTOSTORE_LOOT_ITEM);
		GEN_CASE(CMSG_LOOT_RELEASE);
		GEN_CASE(CMSG_QUEST_QUERY);
		GEN_CASE(MSG_MOVE_TELEPORT_ACK);
		GEN_CASE(CMSG_CREATURE_QUERY);
		GEN_CASE(CMSG_TRAINER_LIST);
		GEN_CASE(CMSG_TRAINER_BUY_SPELL);
		GEN_CASE(CMSG_CANCEL_AURA);
		GEN_CASE(CMSG_GAMEOBJ_USE);
		GEN_CASE(CMSG_GAMEOBJECT_QUERY);
		GEN_CASE(MSG_MINIMAP_PING);
		GEN_CASE(CMSG_SELL_ITEM);
		GEN_CASE(CMSG_USE_ITEM);
		GEN_CASE(CMSG_AUTOSTORE_BANK_ITEM);
		GEN_CASE(CMSG_REPAIR_ITEM);
		GEN_CASE(CMSG_LEARN_TALENT);
		GEN_CASE(CMSG_LOOT_ROLL);
		GEN_CASE(CMSG_QUESTGIVER_QUERY_QUEST);
		GEN_CASE(CMSG_CANCEL_CHANNELLING);
		default: return NULL;
	}
}
