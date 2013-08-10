#ifndef WORLDPACKETGENERATORSLUA_H
#define WORLDPACKETGENERATORSLUA_H

#include "Common.h"
#include "types.h"

typedef struct lua_State lua_State;

// buf is 64 KiB.
typedef uint16 (*PacketGenerator)(lua_State*, byte* buf);

PacketGenerator getPacketGenerator(int opcode);

#endif	//WORLDPACKETGENERATORSLUA_H
