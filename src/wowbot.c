#include "config.h"
#include "socket.h"
#include "log.h"
#include "world.h"
#include "auth.h"
#include "cDbc.h"

#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <assert.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include "lua_version.h"

#include "ConfigLua.h"

#define DEFAULT_REALMSERVER_PORT 3724

static void startSession(WorldSession* session, const char* authAddress) {
	lua_State* L;
	int res;

	session->L = L = luaL_newstate();
	luaL_openlibs(L);
	initLua(session);
	res = readLua(session);
	if(!res) {
		exit(1);
	}

	LOG("Connecting...\n");
	session->authSock = connectNewSocket(authAddress, DEFAULT_REALMSERVER_PORT);
	if(session->authSock == INVALID_SOCKET) {
		exit(1);
	}
	LOG("Connected.\n");

	authenticate(session);
	//dumpRealmList(session->authSock, NULL);
}

// global
static char* luaG_strdup(lua_State* L, const char* key) {
	char* c;
	lua_getglobal(L, key);
	c = strdup(lua_tostring(L, -1));
	lua_pop(L, 1);
	return c;
}

// table on top of stack
static char* luaT_strdup(lua_State* L, const char* key) {
	char* c;
	lua_pushstring(L, key);
	lua_gettable(L, -2);
	c = strdup(luaL_checkstring(L, -1));
	lua_pop(L, 1);
	return c;
}

// table on top of stack
static int luaT_int(lua_State* L, const char* key) {
	int i;
	lua_pushstring(L, key);
	lua_gettable(L, -2);
	i = luaL_checkint(L, -1);
	lua_pop(L, 1);
	return i;
}

// table on top of stack
static int luaT_bool(lua_State* L, const char* key) {
	int i;
	lua_pushstring(L, key);
	lua_gettable(L, -2);
	i = lua_toboolean(L, -1);
	lua_pop(L, 1);
	return i;
}

static int luaPanic(lua_State *L) {
	LOG("luaPanic: %s\n", lua_tostring(L, -1));
	*(int*)NULL = 0;	// induce a crash that can be caught by a debugger.
	return 0;
}

int main(void) {
	lua_State* L;
	int res;

	loadDBC();
	loadAuxDBC();

#ifdef WIN32
	{
		// Initialize Winsock
		WSADATA wsaData;
		res = WSAStartup(MAKEWORD(2,2), &wsaData);
		if (res != 0) {
			printf("WSAStartup failed: %d\n", res);
			exit(1);
		}
	}
#endif

	L = luaL_newstate();
	luaL_openlibs(L);
	lua_atpanic(L, luaPanic);

	// insert constants that the config file can use.
	ConfigLua(L);

	if(!luaDoFile(L, "src/lua/globalLockdown.lua"))
		return 1;

	if(!luaDoFile(L, "config.lua"))
		return 1;

	// Read config.
	{
		uint toonCount;
		WorldSession* sessions;
		char* authAddress = luaG_strdup(L, "AUTH_ADDRESS");
		char* realmName = luaG_strdup(L, "REALM_NAME");
		FILE* sqlFile = fopen("build/accounts.sql", "w");

		// Export SQL code for creating accounts.

		// TOONS is an array of tables.
		lua_getglobal(L, "TOONS");
		toonCount = lua_len(L, -1);

		LOG("toonCount: %i\n", toonCount);

		sessions = (WorldSession*)malloc(sizeof(WorldSession) * toonCount);
		memset(sessions, 0, sizeof(WorldSession) * toonCount);

		fprintf(sqlFile, "INSERT INTO account (username, sha_pass_hash) VALUES\n");
		for(uint i=0; i<toonCount; i++) {
			lua_rawgeti(L, 1, i+1);
			sessions[i].authAddress = authAddress;
			sessions[i].accountName = luaT_strdup(L, "accountName");
			sessions[i].password = luaT_strdup(L, "password");
			sessions[i].toonName = luaT_strdup(L, "toonName");
			sessions[i]._class = luaT_int(L, "class");
			sessions[i].race = luaT_int(L, "race");
			sessions[i].gender = luaT_int(L, "gender");
			sessions[i].realmName = realmName;
			sessions[i].amTank = luaT_bool(L, "tank");
			sessions[i].amHealer = luaT_bool(L, "healer");
			fprintf(sqlFile, "('%s', SHA1(CONCAT(UPPER('%s'),':',UPPER('%s'))))",
				sessions[i].accountName, sessions[i].accountName, sessions[i].password);
			if(i != toonCount - 1)
				fprintf(sqlFile, ",\n");
			else
				fprintf(sqlFile, ";\n");
		}
		fclose(sqlFile);

		// Start sessions.
		LOG("Starting %i sessions...\n", toonCount);
		for(uint i=0; i<toonCount; i++) {
			startSession(&sessions[i], authAddress);
		}
		runWorlds(sessions, toonCount);
	}

	return 0;
}
