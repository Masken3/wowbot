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

#ifndef MANGOSSERVER_QUEST_H
#define MANGOSSERVER_QUEST_H

#define MAX_QUEST_LOG_SIZE 20

#define QUEST_OBJECTIVES_COUNT 4
#define QUEST_ITEM_OBJECTIVES_COUNT QUEST_OBJECTIVES_COUNT
#define QUEST_SOURCE_ITEM_IDS_COUNT 4
#define QUEST_REWARD_CHOICES_COUNT 6
#define QUEST_REWARDS_COUNT 4
#define QUEST_DEPLINK_COUNT 10
#define QUEST_REPUTATIONS_COUNT 5
#define QUEST_EMOTE_COUNT 4

// [-ZERO] need update
enum QuestFailedReasons
{
	INVALIDREASON_DONT_HAVE_REQ                 = 0,
	INVALIDREASON_QUEST_FAILED_LOW_LEVEL        = 1,        //You are not high enough level for that quest.
	INVALIDREASON_QUEST_FAILED_WRONG_RACE       = 6,        //That quest is not available to your race.
	INVALIDREASON_QUEST_ONLY_ONE_TIMED          = 12,       //You can only be on one timed quest at a time.
	INVALIDREASON_QUEST_ALREADY_ON              = 13,       //You are already on that quest
	INVALIDREASON_QUEST_FAILED_MISSING_ITEMS    = 21,       //You don't have the required items with you. Check storage.
	INVALIDREASON_QUEST_FAILED_NOT_ENOUGH_MONEY = 23,       //You don't have enough money for that quest.
	//[-ZERO] tbc enumerations [?]
	INVALIDREASON_QUEST_ALREADY_ON2             = 18,       //You are already on that quest
	INVALIDREASON_QUEST_ALREADY_DONE            = 7,        //You have completed that quest.
};

enum QuestShareMessages
{
	QUEST_PARTY_MSG_SHARING_QUEST           = 0,            // ERR_QUEST_PUSH_SUCCESS_S
	QUEST_PARTY_MSG_CANT_TAKE_QUEST         = 1,            // ERR_QUEST_PUSH_INVALID_S
	QUEST_PARTY_MSG_ACCEPT_QUEST            = 2,            // ERR_QUEST_PUSH_ACCEPTED_S
	QUEST_PARTY_MSG_DECLINE_QUEST           = 3,            // ERR_QUEST_PUSH_DECLINED_S
	QUEST_PARTY_MSG_TOO_FAR                 = 4,            // removed in 3.x
	QUEST_PARTY_MSG_BUSY                    = 5,            // ERR_QUEST_PUSH_BUSY_S
	QUEST_PARTY_MSG_LOG_FULL                = 6,            // ERR_QUEST_PUSH_LOG_FULL_S
	QUEST_PARTY_MSG_HAVE_QUEST              = 7,            // ERR_QUEST_PUSH_ONQUEST_S
	QUEST_PARTY_MSG_FINISH_QUEST            = 8,            // ERR_QUEST_PUSH_ALREADY_DONE_S
};

enum __QuestTradeSkill
{
	QUEST_TRSKILL_NONE           = 0,
	QUEST_TRSKILL_ALCHEMY        = 1,
	QUEST_TRSKILL_BLACKSMITHING  = 2,
	QUEST_TRSKILL_COOKING        = 3,
	QUEST_TRSKILL_ENCHANTING     = 4,
	QUEST_TRSKILL_ENGINEERING    = 5,
	QUEST_TRSKILL_FIRSTAID       = 6,
	QUEST_TRSKILL_HERBALISM      = 7,
	QUEST_TRSKILL_LEATHERWORKING = 8,
	QUEST_TRSKILL_POISONS        = 9,
	QUEST_TRSKILL_TAILORING      = 10,
	QUEST_TRSKILL_MINING         = 11,
	QUEST_TRSKILL_FISHING        = 12,
	QUEST_TRSKILL_SKINNING       = 13,
};

enum QuestStatus
{
	QUEST_STATUS_NONE           = 0,
	QUEST_STATUS_COMPLETE       = 1,
	QUEST_STATUS_UNAVAILABLE    = 2,
	QUEST_STATUS_INCOMPLETE     = 3,
	QUEST_STATUS_AVAILABLE      = 4,                        // unused in fact
	QUEST_STATUS_FAILED         = 5,
	MAX_QUEST_STATUS
};

enum __QuestGiverStatus
{
	DIALOG_STATUS_NONE                     = 0,
	DIALOG_STATUS_UNAVAILABLE              = 1,
	DIALOG_STATUS_CHAT                     = 2,
	DIALOG_STATUS_INCOMPLETE               = 3,
	DIALOG_STATUS_REWARD_REP               = 4,
	DIALOG_STATUS_AVAILABLE                = 5,
	DIALOG_STATUS_REWARD_OLD               = 6,             // red dot on minimap
	DIALOG_STATUS_REWARD2                  = 7,             // yellow dot on minimap
	// [-ZERO] tbc?  DIALOG_STATUS_REWARD                   = 8              // yellow dot on minimap
};

// values based at QuestInfo.dbc
enum QuestTypes
{
	QUEST_TYPE_ELITE               = 1,
	QUEST_TYPE_LIFE                = 21,
	QUEST_TYPE_PVP                 = 41,
	QUEST_TYPE_RAID                = 62,
	QUEST_TYPE_DUNGEON             = 81,
	//tbc?
	QUEST_TYPE_WORLD_EVENT         = 82,
	QUEST_TYPE_LEGENDARY           = 83,
	QUEST_TYPE_ESCORT              = 84,
};

enum QuestFlags
{
	// Flags used at server and sent to client
	QUEST_FLAGS_NONE           = 0x00000000,
	QUEST_FLAGS_STAY_ALIVE     = 0x00000001,                // Not used currently
	QUEST_FLAGS_PARTY_ACCEPT   = 0x00000002,                // If player in party, all players that can accept this quest will receive confirmation box to accept quest CMSG_QUEST_CONFIRM_ACCEPT/SMSG_QUEST_CONFIRM_ACCEPT
	QUEST_FLAGS_EXPLORATION    = 0x00000004,                // Not used currently
	QUEST_FLAGS_SHARABLE       = 0x00000008,                // Can be shared: Player::CanShareQuest()
	//QUEST_FLAGS_NONE2        = 0x00000010,                // Not used currently
	QUEST_FLAGS_EPIC           = 0x00000020,                // Not used currently: Unsure of content
	QUEST_FLAGS_RAID           = 0x00000040,                // Not used currently

	QUEST_FLAGS_UNK2           = 0x00000100,                // Not used currently: _DELIVER_MORE Quest needs more than normal _q-item_ drops from mobs
	QUEST_FLAGS_HIDDEN_REWARDS = 0x00000200,                // Items and money rewarded only sent in SMSG_QUESTGIVER_OFFER_REWARD (not in SMSG_QUESTGIVER_QUEST_DETAILS or in client quest log(SMSG_QUEST_QUERY_RESPONSE))
	QUEST_FLAGS_AUTO_REWARDED  = 0x00000400,                // These quests are automatically rewarded on quest complete and they will never appear in quest log client side.
};

enum QuestSpecialFlags
{
	// Mangos flags for set SpecialFlags in DB if required but used only at server
	QUEST_SPECIAL_FLAG_REPEATABLE           = 0x001,        // |1 in SpecialFlags from DB
	QUEST_SPECIAL_FLAG_EXPLORATION_OR_EVENT = 0x002,        // |2 in SpecialFlags from DB (if required area explore, spell SPELL_EFFECT_QUEST_COMPLETE casting, table `*_script` command SCRIPT_COMMAND_QUEST_EXPLORED use, set from script DLL)
	// reserved for future versions           0x004,        // |4 in SpecialFlags.

	// Mangos flags for internal use only
	QUEST_SPECIAL_FLAG_DELIVER              = 0x008,        // Internal flag computed only
	QUEST_SPECIAL_FLAG_SPEAKTO              = 0x010,        // Internal flag computed only
	QUEST_SPECIAL_FLAG_KILL_OR_CAST         = 0x020,        // Internal flag computed only
	QUEST_SPECIAL_FLAG_TIMED                = 0x040,        // Internal flag computed only
};

#define QUEST_SPECIAL_FLAG_DB_ALLOWED (QUEST_SPECIAL_FLAG_REPEATABLE | QUEST_SPECIAL_FLAG_EXPLORATION_OR_EVENT)

enum QuestUpdateState
{
	QUEST_UNCHANGED = 0,
	QUEST_CHANGED = 1,
	QUEST_NEW = 2
};

#endif
