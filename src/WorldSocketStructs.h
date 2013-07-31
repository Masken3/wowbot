#ifndef WORLDSOCKETSTRUCTS_H
#define WORLDSOCKETSTRUCTS_H

#include "Common.h"

// copied from WorldSocket.cpp

#if defined( __GNUC__ )
#pragma pack(1)
#else
#pragma pack(push,1)
#endif

typedef struct ServerPktHeader
{
	uint16 size;
	uint16 cmd;
} ServerPktHeader;

typedef struct ClientPktHeader
{
	uint16 size;
	uint32 cmd;
} ClientPktHeader;

#if defined( __GNUC__ )
#pragma pack()
#else
#pragma pack(pop)
#endif

#endif	//AUTHSOCKETSTRUCTS_H
