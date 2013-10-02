#define __STDC_FORMAT_MACROS
#include <inttypes.h>
#include <stdlib.h>

extern "C" {
#include <lauxlib.h>
}
#include "cDbc.h"
#include "dbcSkillLineAbility/SkillLineAbility.index.h"
#include "dbcTalent/dbcTalent.h"
#include "dbcTalentTab/dbcTalentTab.h"
#include "log.h"
#include "icon/icon.h"

#define NARG_CHECK(n) int narg = lua_gettop(L);\
	if(narg != n) {\
		luaL_error(L, "%s error: args!", __FUNCTION__);\
	}

static void dumpTalents();

void loadAuxDBC() {
	SkillLineAbilityIndex::load();
	dumpTalents();
}

static int l_skillLineAbilityBySpell(lua_State* L) {
	NARG_CHECK(1);
	int id = luaL_checkint(L, 1);
	auto pair = SkillLineAbilityIndex::findSpell(id);
	if(pair.first != pair.second) {
		luaPushSkillLineAbility(L, *pair.first->second);
	} else {
		lua_pushnil(L);
	}
	return 1;
}

static void dumpTalents() {
#if 0
	LOG("%" PRIuPTR " talentTab entries:\n", gTalentTabs.size());
	for(auto itr = gTalentTabs.begin(); itr != gTalentTabs.end(); ++itr) {
		const TalentTab& tt(itr->second);
		LOG("tab %i: c 0x%x t %i si %i '%s' '%s'\n",
			itr->first,
			tt.classMask, tt.tabPage, tt.spellIcon, tt.internalName, tt.name);
	}
	LOG("%" PRIuPTR " talent entries:\n", gTalents.size());
	for(auto itr = gTalents.begin(); itr != gTalents.end(); ++itr) {
		const Talent& t(itr->second);
		LOG("id %i: tab %i r %i c %i sid %i %i %i %i %i p %i %i\n",
			itr->first,
			t.tabId, t.row, t.col, t.spellId[0], t.spellId[1], t.spellId[2],
			t.spellId[3], t.spellId[4], t.prereq, t.prereqRank);
	}
	exit(0);
#endif
}

static int litr_talents(lua_State* L) {
	Talents::citr* p = (Talents::citr*)lua_touserdata(L, lua_upvalueindex(1));
	if(*p == gTalents.end()) {
		return 0;
	}
	luaPushTalent(L, (*p)->second);
	++(*p);
	return 1;
}

static int l_talents(lua_State* L) {
	NARG_CHECK(0);
	Talents::citr* p = (Talents::citr*)lua_newuserdata(L, sizeof(Talents::citr));
	*p = gTalents.begin();
	lua_pushcclosure(L, litr_talents, 1);
	return 1;
}

static int litr_talentTabs(lua_State* L) {
	TalentTabs::citr* p = (TalentTabs::citr*)lua_touserdata(L, lua_upvalueindex(1));
	if(*p == gTalentTabs.end()) {
		return 0;
	}
	luaPushTalentTab(L, (*p)->second);
	++(*p);
	return 1;
}

static int l_talentTabs(lua_State* L) {
	NARG_CHECK(0);
	TalentTabs::citr* p = (TalentTabs::citr*)lua_newuserdata(L, sizeof(TalentTabs::citr));
	*p = gTalentTabs.begin();
	lua_pushcclosure(L, litr_talentTabs, 1);
	return 1;
}

static int l_iconRaw(lua_State* L) {
#if 0
	LOG("iconRaw(%s)\n", luaL_checkstring(L, 1));
	fflush(stdout);
#endif
	NARG_CHECK(1);
	lua_pushstring(L, getIconRaw(luaL_checkstring(L, 1)).c_str());
	return 1;
}

void registerLuaAuxDBC(lua_State* L) {
	lua_register(L, "cSkillLineAbilityBySpell", l_skillLineAbilityBySpell);

	lua_register(L, "cTalents", l_talents);
	lua_register(L, "cTalentTabs", l_talentTabs);

	lua_register(L, "cIconRaw", l_iconRaw);
}
