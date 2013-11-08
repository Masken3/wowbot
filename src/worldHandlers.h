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

enum SpellSpecific
{
	SPELL_NORMAL            = 0,
	SPELL_SEAL              = 1,
	SPELL_BLESSING          = 2,
	SPELL_AURA              = 3,
	SPELL_STING             = 4,
	SPELL_CURSE             = 5,
	SPELL_ASPECT            = 6,
	SPELL_TRACKER           = 7,
	SPELL_WARLOCK_ARMOR     = 8,
	SPELL_MAGE_ARMOR        = 9,
	SPELL_ELEMENTAL_SHIELD  = 10,
	SPELL_MAGE_POLYMORPH    = 11,
	SPELL_POSITIVE_SHOUT    = 12,
	SPELL_JUDGEMENT         = 13,
	SPELL_BATTLE_ELIXIR     = 14,
	SPELL_GUARDIAN_ELIXIR   = 15,
	SPELL_FLASK_ELIXIR      = 16,
	// SPELL_PRESENCE          = 17,                        // used in 3.x
	// SPELL_HAND              = 18,                        // used in 3.x
	SPELL_WELL_FED          = 19,
	SPELL_FOOD              = 20,
	SPELL_DRINK             = 21,
	SPELL_FOOD_AND_DRINK    = 22,
};

#endif	//WORLDHANDLERS_H
