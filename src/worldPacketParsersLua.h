#ifndef WORLDPACKETPARSERSLUA_H
#define WORLDPACKETPARSERSLUA_H

#include "Common.h"

typedef struct WorldSession WorldSession;

#define LUA_HANDLERS(m)\
	m(SMSG_MONSTER_MOVE)\
	m(SMSG_UPDATE_OBJECT)\
	m(SMSG_COMPRESSED_UPDATE_OBJECT)\
	m(SMSG_GROUP_INVITE)\
	m(SMSG_GROUP_UNINVITE)\
	m(SMSG_GROUP_DESTROYED)\
	m(SMSG_GROUP_LIST)\

#define pLUA_ARGS WorldSession* session, const char* buf, uint16 bufSize

#define DECLARE_LUA_HANDLER(name) void p##name(pLUA_ARGS);

LUA_HANDLERS(DECLARE_LUA_HANDLER);

void pMovementInfo(pLUA_ARGS);

#endif	//WORLDPACKETPARSERSLUA_H
