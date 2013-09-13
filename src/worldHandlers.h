#ifndef WORLDHANDLERS_H
#define WORLDHANDLERS_H

/// Support routines and enums for world packet handlers.

#include "world.h"

#ifdef __cplusplus
extern "C"
#endif
void sendWorld(WorldSession*, uint32 opcode, const void* src, uint16 size);

enum RaidIcons
{
	RAID_ICON_STAR = 0,
	RAID_ICON_CIRCLE = 1,
	RAID_ICON_DIAMOND = 2,
	RAID_ICON_TRIANGLE = 3,
	RAID_ICON_MOON = 4,
	RAID_ICON_SQUARE = 5,
	RAID_ICON_CROSS = 6,
	RAID_ICON_SKULL = 7,
};

#endif	//WORLDHANDLERS_H
