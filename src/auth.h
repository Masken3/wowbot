#include "socket.h"
#include "world.h"

// will result in silence unless the server considers us "authed".
char* dumpRealmList(Socket, const char* targetRealmName);
void authenticate(WorldSession*);
