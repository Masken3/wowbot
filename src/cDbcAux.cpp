extern "C" {
#include <lauxlib.h>
}
#include "cDbc.h"
#include "dbcSkillLineAbility/SkillLineAbility.index.h"

void loadAuxDBC() {
	SkillLineAbilityIndex::load();
}

static int l_skillIdBySpell(lua_State* L) {
	int narg = lua_gettop(L);
	if(narg != 1) {
		lua_pushstring(L, "l_spell error: args!");
		lua_error(L);
	}
	int id = luaL_checkint(L, 1);
	auto pair = SkillLineAbilityIndex::findSpell(id);
	if(pair.first != pair.second) {
		lua_pushinteger(L, pair.first->second->skill);
	} else {
		lua_pushnil(L);
	}
	return 1;
}


void registerLuaAuxDBC(lua_State* L) {
	lua_register(L, "cSkillIdBySpell", l_skillIdBySpell);
}