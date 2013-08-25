extern "C" {
#include <lauxlib.h>
}
#include "cDbc.h"
#include "../build/dbcSpell/dbcSpell.h"

void loadDBC(void) {
	gSpells.load();
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
