#include <lua.h>

#ifdef __cplusplus
extern "C" {
#endif
void loadDBC(void);
void loadAuxDBC(void);
void registerLuaDBC(lua_State*);
void registerLuaAuxDBC(lua_State*);
#ifdef __cplusplus
}
#endif
