#ifndef WORLDPACKETPARSERSLUA_H
#define WORLDPACKETPARSERSLUA_H

#include "Common.h"

typedef struct WorldSession WorldSession;

#define pLUA_ARGS WorldSession* session, char* buf, uint16 bufSize

void pSMSG_MONSTER_MOVE(pLUA_ARGS);
void pSMSG_UPDATE_OBJECT(pLUA_ARGS);
void pSMSG_COMPRESSED_UPDATE_OBJECT(pLUA_ARGS);

#endif	//WORLDPACKETPARSERSLUA_H
