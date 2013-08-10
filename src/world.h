#ifndef WORLD_H
#define WORLD_H

#include "socket.h"
#include "Common.h"
#include <time.h>

// Session crypty state.
struct Crypto;

typedef struct WorldSession {
	Socket authSock;
	Socket sock;
	char* worldServerAddress;
	uint8 key[40];	// session crypto key
	struct Crypto* crypto;
	struct lua_State* L;
	time_t luaTime;
} WorldSession;

void runWorld(WorldSession*);

void initLua(WorldSession*);
BOOL readLua(WorldSession*);

void enterWorld(WorldSession* session, uint64 guid);

#endif	//WORLD_H
