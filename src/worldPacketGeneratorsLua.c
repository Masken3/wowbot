#include "worldPacketGeneratorsLua.h"
#include "movement.h"
#include "Opcodes.h"
#include "DBCEnums.h"
#include "log.h"
#include <lua.h>
#include <lauxlib.h>
#include <string.h>
#include <assert.h>

#define MLOG(...) //LOG

#define GL_START byte* ptr = buf;
#define GL_END assert(ptr - buf < UINT16_MAX); return ptr - buf

static void lua_gen_uint32(lua_State* L, const char* name, byte** pp) {
	*(uint32*)(*pp) = luaL_checkunsigned(L, -1);
	(*pp) += 4;
}

static void lua_gen_uint16(lua_State* L, const char* name, byte** pp) {
	uint32 num = luaL_checkunsigned(L, -1);
	if(num > 0xFFFF) {
		luaL_error(L, "gen error: %s is too big to fit in an uint16 (0x%x)!", name, num);
	}
	*(uint16*)(*pp) = (uint16)num;
	(*pp) += 2;
}

#if 0
static void lua_gen_byte(lua_State* L, const char* name, byte** pp) {
	uint32 num = luaL_checkunsigned(L, -1);
	if(num > 0xFF) {
		luaL_error(L, "gen error: %s is too big to fit in a byte (0x%x)!", name, num);
	}
	**pp = (byte)num;
	(*pp) += 1;
}
#endif

static void lua_gen_float(lua_State* L, const char* name, byte** pp) {
	*(float*)(*pp) = (float)luaL_checknumber(L, -1);
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
	lua_len(L, -1);
	len = lua_tonumber(L, -1);
	lua_pop(L, 1);
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

static uint16 genCMSG_CAST_SPELL(lua_State* L, byte* buf) {
	GL_START;
	M(uint32, spellId);
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
	GL_END;
}

static uint16 genCMSG_CANCEL_CAST(lua_State* L, byte* buf) {
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
		default: return NULL;
	}
}