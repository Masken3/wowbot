/**
* This code is part of MaNGOS. Contributor & Copyright details are in AUTHORS/THANKS.
*
* This program is free software; you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation; either version 2 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program; if not, write to the Free Software
* Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*/

#ifndef MANGOS_LOOTMGR_H
#define MANGOS_LOOTMGR_H

#define MAX_NR_LOOT_ITEMS 16
// note: the client cannot show more than 16 items total
#define MAX_NR_QUEST_ITEMS 32
// unrelated to the number of quest items shown, just for reserve

enum PermissionTypes
{
	ALL_PERMISSION    = 0,
	GROUP_PERMISSION  = 1,
	MASTER_PERMISSION = 2,
	OWNER_PERMISSION  = 3,                                  // for single player only loots
	NONE_PERMISSION   = 4
};

enum LootType
{
	LOOT_CORPSE                 = 1,
	LOOT_PICKPOCKETING          = 2,
	LOOT_FISHING                = 3,
	LOOT_DISENCHANTING          = 4,
	// ignored always by client
	LOOT_SKINNING               = 6,                        // unsupported by client, sending LOOT_PICKPOCKETING instead

	LOOT_FISHINGHOLE            = 20,                       // unsupported by client, sending LOOT_FISHING instead
	LOOT_FISHING_FAIL           = 21,                       // unsupported by client, sending LOOT_FISHING instead
	LOOT_INSIGNIA               = 22                        // unsupported by client, sending LOOT_CORPSE instead
};

enum LootSlotType
{
	LOOT_SLOT_NORMAL  = 0,                                  // can be looted
	LOOT_SLOT_VIEW    = 1,                                  // can be only view (ignore any loot attempts)
	LOOT_SLOT_MASTER  = 2,                                  // can be looted only master (error message)
	LOOT_SLOT_REQS    = 3,                                  // can't be looted (error message about missing reqs)
	MAX_LOOT_SLOT_TYPE                                      // custom, use for mark skipped from show items
};

#endif
