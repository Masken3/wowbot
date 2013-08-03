#include "config.h"
#include "socket.h"
#include "log.h"
#include "world.h"
#include "auth.h"

#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <assert.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#define DEFAULT_REALMSERVER_PORT 3724

int main(void) {
	WorldSession session;
	lua_State* L;
	int res;

	L = luaL_newstate();
	luaL_openlibs(L);
	res = luaL_loadfile(L, "src/wowbot.lua");
	if(res != LUA_OK) {
		LOG("LUA load error!\n");
		LOG("%s\n", lua_tostring(L, -1));
		exit(1);
	}
	res = lua_pcall(L, 0, 0, 0);
	if(res != LUA_OK) {
		LOG("LUA run error!\n");
		LOG("%s\n", lua_tostring(L, -1));
		exit(1);
	}
	session.L = L;

	worldCheckLua(&session);

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

	LOG("Connecting...\n");
	session.authSock = connectNewSocket(CONFIG_SERVER_ADDRESS, DEFAULT_REALMSERVER_PORT);
	if(session.authSock == INVALID_SOCKET) {
		exit(1);
	}
	LOG("Connected.\n");

	authenticate(&session);
	if(1) {//config.realmName) {
		runWorld(&session);
	} else {
		dumpRealmList(session.authSock, NULL);
	}

	return 0;
}
