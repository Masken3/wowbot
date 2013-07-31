#ifndef WORLD_H
#define WORLD_H

#include "socket.h"
#include "Common.h"

// Session crypty state.
struct Crypto;

typedef struct WorldSession {
	Socket sock;
	uint8 key[40];	// session crypto key
	struct Crypto* crypto;
} WorldSession;

void runWorld(WorldSession*);

#endif	//WORLD_H
