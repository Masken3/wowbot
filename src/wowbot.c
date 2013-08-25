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

#define DEFAULT_REALMSERVER_PORT 3724

int main(void) {
	WorldSession session;
	lua_State* L;
	int res;

	loadDBC();

	memset(&session, 0, sizeof(session));

	session.L = L = luaL_newstate();
	luaL_openlibs(L);
	initLua(&session);
	res = readLua(&session);
	if(!res) {
		exit(1);
	}

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
