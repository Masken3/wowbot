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
	m(SMSG_LOGIN_VERIFY_WORLD)\
	m(SMSG_INITIAL_SPELLS)\
	m(SMSG_ATTACKSTART)\
	m(SMSG_ATTACKSTOP)\
	m(SMSG_CAST_FAILED)\
	m(SMSG_QUESTGIVER_QUEST_DETAILS)\
	m(SMSG_MESSAGECHAT)\
	m(SMSG_QUESTGIVER_STATUS)\
	m(SMSG_QUESTGIVER_STATUS_MULTIPLE)\
	m(SMSG_QUESTGIVER_QUEST_LIST)\
	m(SMSG_QUESTGIVER_OFFER_REWARD)\
	m(SMSG_QUESTGIVER_REQUEST_ITEMS)\
	m(SMSG_QUESTGIVER_QUEST_COMPLETE)\
	m(SMSG_ITEM_QUERY_SINGLE_RESPONSE)\
	m(SMSG_ITEM_PUSH_RESULT)\


#define pLUA_ARGS WorldSession* session, const char* buf, uint16 bufSize

#define DECLARE_LUA_HANDLER(name) void p##name(pLUA_ARGS);

LUA_HANDLERS(DECLARE_LUA_HANDLER);

void pMovementInfo(pLUA_ARGS);
void pEmpty(pLUA_ARGS);

#endif	//WORLDPACKETPARSERSLUA_H
