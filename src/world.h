#ifndef WORLD_H
#define WORLD_H

#include "socket.h"
#include "Common.h"
#include "WorldSocketStructs.h"
#include <time.h>

// Session crypty state.
struct Crypto;

typedef struct WorldSession {
	char* accountName;
	char* password;
	char* toonName;
	int _class;
	int race;
	int gender;
	int amTank;
	int amHealer;

	Socket authSock;
	Socket sock;
	char* realmName;
	char* worldServerAddress;
	uint8 key[40];	// session crypto key
	struct Crypto* crypto;
	struct lua_State* L;
	time_t luaTime;
	time_t* luaTimes;
	int luaTimeCount;

	ServerPktHeader sph;
	char buf[1024 * 64];
	SocketControl* sc;
} WorldSession;

void runWorlds(WorldSession* sessions, int toonCount) __attribute__ ((noreturn));

void initLua(WorldSession*);
BOOL readLua(WorldSession*);
BOOL luaPcall(struct lua_State* L, int nargs);
BOOL luaDoFile(struct lua_State* L, const char* filename);

void enterWorld(WorldSession* session, uint64 guid, uint8 level);

#endif	//WORLD_H
