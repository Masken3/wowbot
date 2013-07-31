#ifndef WORLDHANDLERS_H
#define WORLDHANDLERS_H

/// Support routines and enums for world packet handlers.

#ifdef __cplusplus
extern "C"
#endif
void sendWorld(WorldSession*, uint32 opcode, const void* src, uint16 size);

enum EquipmentSlots                                         // 19 slots
{
	EQUIPMENT_SLOT_START        = 0,
	EQUIPMENT_SLOT_HEAD         = 0,
	EQUIPMENT_SLOT_NECK         = 1,
	EQUIPMENT_SLOT_SHOULDERS    = 2,
	EQUIPMENT_SLOT_BODY         = 3,
	EQUIPMENT_SLOT_CHEST        = 4,
	EQUIPMENT_SLOT_WAIST        = 5,
	EQUIPMENT_SLOT_LEGS         = 6,
	EQUIPMENT_SLOT_FEET         = 7,
	EQUIPMENT_SLOT_WRISTS       = 8,
	EQUIPMENT_SLOT_HANDS        = 9,
	EQUIPMENT_SLOT_FINGER1      = 10,
	EQUIPMENT_SLOT_FINGER2      = 11,
	EQUIPMENT_SLOT_TRINKET1     = 12,
	EQUIPMENT_SLOT_TRINKET2     = 13,
	EQUIPMENT_SLOT_BACK         = 14,
	EQUIPMENT_SLOT_MAINHAND     = 15,
	EQUIPMENT_SLOT_OFFHAND      = 16,
	EQUIPMENT_SLOT_RANGED       = 17,
	EQUIPMENT_SLOT_TABARD       = 18,
	EQUIPMENT_SLOT_END          = 19
};

enum InventorySlots                                         // 4 slots
{
	INVENTORY_SLOT_BAG_START    = 19,
	INVENTORY_SLOT_BAG_END      = 23
};

enum InventoryPackSlots                                     // 16 slots
{
	INVENTORY_SLOT_ITEM_START   = 23,
	INVENTORY_SLOT_ITEM_END     = 39
};

enum BankItemSlots                                          // 28 slots
{
	BANK_SLOT_ITEM_START        = 39,
	BANK_SLOT_ITEM_END          = 63
};

enum BankBagSlots                                           // 7 slots
{
	BANK_SLOT_BAG_START         = 63,
	BANK_SLOT_BAG_END           = 69
};

enum BuyBackSlots                                           // 12 slots
{
	// stored in m_buybackitems
	BUYBACK_SLOT_START          = 69,
	BUYBACK_SLOT_END            = 81
};

enum KeyRingSlots                                           // 32 slots
{
	KEYRING_SLOT_START          = 81,
	KEYRING_SLOT_END            = 97
};

#endif	//WORLDHANDLERS_H
