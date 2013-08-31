/*
* Copyright (C) 2005-2012 MaNGOS <http://getmangos.com/>
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

#ifndef MANGOS_OBJECT_GUID_H
#define MANGOS_OBJECT_GUID_H

enum TypeID
{
	TYPEID_OBJECT        = 0,
	TYPEID_ITEM          = 1,
	TYPEID_CONTAINER     = 2,
	TYPEID_UNIT          = 3,
	TYPEID_PLAYER        = 4,
	TYPEID_GAMEOBJECT    = 5,
	TYPEID_DYNAMICOBJECT = 6,
	TYPEID_CORPSE        = 7
};

#define MAX_TYPE_ID        8

enum TypeMask
{
	TYPEMASK_OBJECT         = 0x0001,
	TYPEMASK_ITEM           = 0x0002,
	TYPEMASK_CONTAINER      = 0x0004,
	TYPEMASK_UNIT           = 0x0008,                       // players also have it
	TYPEMASK_PLAYER         = 0x0010,
	TYPEMASK_GAMEOBJECT     = 0x0020,
	TYPEMASK_DYNAMICOBJECT  = 0x0040,
	TYPEMASK_CORPSE         = 0x0080,

	// used combinations in Player::GetObjectByTypeMask (TYPEMASK_UNIT case ignore players in call)
	TYPEMASK_CREATURE_OR_GAMEOBJECT = TYPEMASK_UNIT | TYPEMASK_GAMEOBJECT,
	TYPEMASK_CREATURE_GAMEOBJECT_OR_ITEM = TYPEMASK_UNIT | TYPEMASK_GAMEOBJECT | TYPEMASK_ITEM,
	TYPEMASK_CREATURE_GAMEOBJECT_PLAYER_OR_ITEM = TYPEMASK_UNIT | TYPEMASK_GAMEOBJECT | TYPEMASK_ITEM | TYPEMASK_PLAYER,

	TYPEMASK_WORLDOBJECT = TYPEMASK_UNIT | TYPEMASK_PLAYER | TYPEMASK_GAMEOBJECT | TYPEMASK_DYNAMICOBJECT | TYPEMASK_CORPSE,
};

enum HighGuid
{
	HIGHGUID_ITEM           = 0x4000,                       // blizz 4000
	HIGHGUID_CONTAINER      = 0x4000,                       // blizz 4000
	HIGHGUID_PLAYER         = 0x0000,                       // blizz 0000
	HIGHGUID_GAMEOBJECT     = 0xF110,                       // blizz F110
	HIGHGUID_TRANSPORT      = 0xF120,                       // blizz F120 (for GAMEOBJECT_TYPE_TRANSPORT)
	HIGHGUID_UNIT           = 0xF130,                       // blizz F130
	HIGHGUID_PET            = 0xF140,                       // blizz F140
	HIGHGUID_DYNAMICOBJECT  = 0xF100,                       // blizz F100
	HIGHGUID_CORPSE         = 0xF101,                       // blizz F100
	HIGHGUID_MO_TRANSPORT   = 0x1FC0,                       // blizz 1FC0 (for GAMEOBJECT_TYPE_MO_TRANSPORT)
};

#endif
