#include <lua.h>

#ifdef __cplusplus
extern "C" {
#endif
void loadDBC(void);
int l_spell(lua_State* L);
int l_spellDuration(lua_State* L);
int l_spellRange(lua_State* L);
#ifdef __cplusplus
}
#endif
