extern "C" {
#include <lauxlib.h>
}
#include "cDbc.h"
#include "../build/dbcSpell/dbcSpell.h"
#include "../build/dbcSpellDuration/dbcSpellDuration.h"
#include "../build/dbcSpellRange/dbcSpellRange.h"

void loadDBC(void) {
	gSpells.load();
	gSpellDurations.load();
	gSpellRanges.load();
}

int l_spell(lua_State* L) {
	int narg = lua_gettop(L);
	if(narg != 1) {
		lua_pushstring(L, "l_spell error: args!");
		lua_error(L);
	}
	int id = luaL_checkint(L, 1);
	const Spell* s = gSpells.find(id);
	if(s)
		luaPushSpell(L, *s);
	else
		lua_pushnil(L);
	return 1;
}

int l_spellDuration(lua_State* L) {
	int narg = lua_gettop(L);
	if(narg != 1) {
		lua_pushstring(L, "l_spellDuration error: args!");
		lua_error(L);
	}
	int id = luaL_checkint(L, 1);
	const SpellDuration* s = gSpellDurations.find(id);
	if(s)
		luaPushSpellDuration(L, *s);
	else
		lua_pushnil(L);
	return 1;
}

int l_spellRange(lua_State* L) {
	int narg = lua_gettop(L);
	if(narg != 1) {
		lua_pushstring(L, "l_spellRange error: args!");
		lua_error(L);
	}
	int id = luaL_checkint(L, 1);
	const SpellRange* s = gSpellRanges.find(id);
	if(s)
		luaPushSpellRange(L, *s);
	else
		lua_pushnil(L);
	return 1;
}
