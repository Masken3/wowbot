#include "socket.h"
#include "world.h"

// will result in silence unless the server considers us "authed".
char* dumpRealmList(Socket, const char* targetRealmName);

// returns 1 on success, 0 on timeout. calls exit() on other failures.
int authenticate(WorldSession*);
