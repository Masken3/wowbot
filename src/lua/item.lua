
local itemInventoryToEquipmentSlot = {
	[INVTYPE_HEAD] = EQUIPMENT_SLOT_HEAD,
	[INVTYPE_NECK] = EQUIPMENT_SLOT_NECK,
	[INVTYPE_SHOULDERS] = EQUIPMENT_SLOT_SHOULDERS,
	[INVTYPE_BODY] = EQUIPMENT_SLOT_BODY,
	[INVTYPE_CHEST] = EQUIPMENT_SLOT_CHEST,
	[INVTYPE_ROBE] = EQUIPMENT_SLOT_CHEST,
	[INVTYPE_WAIST] = EQUIPMENT_SLOT_WAIST,
	[INVTYPE_LEGS] = EQUIPMENT_SLOT_LEGS,
	[INVTYPE_FEET] = EQUIPMENT_SLOT_FEET,
	[INVTYPE_WRISTS] = EQUIPMENT_SLOT_WRISTS,
	[INVTYPE_HANDS] = EQUIPMENT_SLOT_HANDS,
	[INVTYPE_FINGER] = {EQUIPMENT_SLOT_FINGER1, EQUIPMENT_SLOT_FINGER2},
	[INVTYPE_TRINKET] = {EQUIPMENT_SLOT_TRINKET1, EQUIPMENT_SLOT_TRINKET2},
	[INVTYPE_CLOAK] = EQUIPMENT_SLOT_BACK,
	[INVTYPE_WEAPON] = {EQUIPMENT_SLOT_MAINHAND, EQUIPMENT_SLOT_OFFHAND},
	[INVTYPE_SHIELD] = EQUIPMENT_SLOT_OFFHAND,
	[INVTYPE_RANGED] = EQUIPMENT_SLOT_RANGED,
	[INVTYPE_2HWEAPON] = EQUIPMENT_SLOT_MAINHAND,
	[INVTYPE_TABARD] = EQUIPMENT_SLOT_TABARD,
	[INVTYPE_WEAPONMAINHAND] = EQUIPMENT_SLOT_MAINHAND,
	[INVTYPE_WEAPONOFFHAND] = EQUIPMENT_SLOT_OFFHAND,
	[INVTYPE_HOLDABLE] = EQUIPMENT_SLOT_OFFHAND,
	[INVTYPE_THROWN] = EQUIPMENT_SLOT_RANGED,
	[INVTYPE_RANGEDRIGHT] = EQUIPMENT_SLOT_RANGED,
	[INVTYPE_RELIC] = EQUIPMENT_SLOT_RANGED,
}

-- returns a table based on DB item_template.
-- sends a request for data, and returns nil, if none exists.
-- register a callback in STATE.itemDataCallbacks.
function itemProtoFromId(id)
	local ip = STATE.itemProtos[id];
	if(ip) then return ip; end
	if(STATE.itemProtosWaiting[id]) then return nil; end
	STATE.itemProtosWaiting[id] = true;
	send(CMSG_ITEM_QUERY_SINGLE, {itemId=id, guid=ZeroGuid});
end

function doCallbacks(callbacks)
	-- keep a separate set; new callbacks may be added by old callbacks.
	local set = {}
	local count = 0;
	for p, f in pairs(callbacks) do
		set[p] = true;
		count = count + 1;
		f(p);
	end
	print(count.." callbacks called.");
	-- remove only those callbacks that we called.
	-- do it after the iteration, so the iterator doesn't get confused.
	for p, t in pairs(set) do
		callbacks[p] = nil;
	end
end

function hSMSG_ITEM_QUERY_SINGLE_RESPONSE(p)
	print("SMSG_ITEM_QUERY_SINGLE_RESPONSE "..p.itemId);
	STATE.itemProtosWaiting[p.itemId] = nil;
	STATE.itemProtos[p.itemId] = p;
	if(not next(STATE.itemProtosWaiting)) then
		print("All item protos received.");
		doCallbacks(STATE.itemDataCallbacks);
	end
end

-- returns one of enum EquipmentSlots.
function itemEquipSlot(proto)
	--print("itemSlotIndex("..proto.InventoryType..")", dump(itemInventoryToEquipmentSlot));
	return itemInventoryToEquipmentSlot[proto.InventoryType];
end

-- returns guid
function equipmentInSlot(eSlot)
	local guid = guidFromValues(STATE.me, PLAYER_FIELD_INV_SLOT_HEAD + (eSlot * 2));
	if(not isValidGuid(guid)) then return nil; end
	return guid;
end

function itemIdOfGuid(guid)
	return STATE.knownObjects[guid].values[OBJECT_FIELD_ENTRY];
end


function itemSkillSpell(proto)
	if(proto.itemClass == ITEM_CLASS_WEAPON) then
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_AXE) then return 196; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_AXE2) then return 197; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_BOW) then return 264; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_GUN) then return 266; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_MACE) then return 198; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_MACE2) then return 199; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_POLEARM) then return 200; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_SWORD) then return 201; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_SWORD2) then return 202; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_STAFF) then return 227; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_DAGGER) then return 1180; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_THROWN) then return 2567; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_SPEAR) then return 3386; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_CROSSBOW) then return 5011; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_WAND) then return 5009; end
	elseif(proto.itemClass == ITEM_CLASS_ARMOR) then
		if(proto.subClass == ITEM_SUBCLASS_ARMOR_CLOTH) then return 9078; end
		if(proto.subClass == ITEM_SUBCLASS_ARMOR_LEATHER) then return 9077; end
		if(proto.subClass == ITEM_SUBCLASS_ARMOR_MAIL) then return 8737; end
		if(proto.subClass == ITEM_SUBCLASS_ARMOR_PLATE) then return 750; end
		if(proto.subClass == ITEM_SUBCLASS_ARMOR_SHIELD) then return 9116; end
	end
	return nil;
end


function wantToWear(id)
	-- this is tricky.
	-- we don't want to wear anything we can't wear.
	-- we want to wear something with "better" stats than what we already have.
	-- for now, assume higher id means better stats.
	local proto = itemProtoFromId(id);
	print("Testing weariness of item "..proto.name.." ("..id..")...");

	-- if it's not equipment, we can't wear it.
	local slot = itemEquipSlot(proto);
	if(not slot) then
		print("no slot found.");
		return false;
	end

	-- make sure we have the skill needed to wear it.
	local spellId = itemSkillSpell(proto);
	if(spellId) then
		if(not STATE.knownSpells[spellId]) then
			print("proficiency not known: "..spellId);
			return false;
		end
	else
		-- some items don't require skills. We can use them.
		print("No proficiency needed. class: "..proto.itemClass.." subClass: "..proto.subClass);
	end

	local equippedGuid = equipmentInSlot(slot);
	if(not equippedGuid) then
		print("no item equipped in that slot. I'm gonna wear it!");
		return true;
	end
	local eid = itemIdOfGuid(equippedGuid);
	print("equipped id: "..eid);
	--return id > eid;
	print("price: "..vendorSalePrice(id).." vs "..vendorSalePrice(itemIdOfGuid(equippedGuid)));
	return vendorSalePrice(id) > vendorSalePrice(itemIdOfGuid(equippedGuid));
end

-- only call this function if itemProtoFromId(id) returns non-nil.
function vendorSalePrice(id)
	local ip = itemProtoFromId(id);
	assert(ip);
	return ip.SellPrice;
end

function itemLoginComplete()
	-- fetch item info for all equipped items.
	print("Equipped items:");
	for i = EQUIPMENT_SLOT_START, EQUIPMENT_SLOT_END-1 do
		local equippedGuid = equipmentInSlot(i);
		if(equippedGuid) then
			local id = itemIdOfGuid(equippedGuid);
			print(id);
			itemProtoFromId(id);
		end
	end
end

function itemTest()
	--local id = 719;	-- Rabbit Handler Gloves. everyone should be able to wear them.
	--local id = 6171;	-- Wold Handler Gloves. mages can't wear them.
	local id = 17723;	--Green Holiday Shirt. should be more expensive than the standard shirt.
	local proto = itemProtoFromId(id);
	if(not proto) then
		STATE.itemDataCallbacks[id] = itemTest;
		return;
	end
	wantToWear(id);
end

function hSMSG_ITEM_PUSH_RESULT(p)
	print("SMSG_ITEM_PUSH_RESULT", dump(p));
	-- we've got a new item. if we want to wear it, then wear it.

	-- if it wasn't us who got the item, we don't care.
	if(p.playerGuid ~= STATE.myGuid) then
		print("WEIRD: got SMSG_ITEM_PUSH_RESULT for another player.");
		return;
	end

	-- if items stacks, it's not equipment.
	if(p.itemSlot == 0xFFFFFFFF) then
		print("itemSlot -1.");
		return;
	end

	-- SMSG_ITEM_PUSH_RESULT is always followed by SMSG_UPDATE_OBJECT,
	-- which sets the item's guid. We'll have to wait for it.
	STATE.me.updateValuesCallbacks[p] = handleItemPush;
end

function handleItemPush(p)
	-- find item's guid.
	local guid;

	-- item is in backpack, or directly equipped.
	if(p.bagSlot == INVENTORY_SLOT_BAG_0) then
		print("INVENTORY_SLOT_BAG_0.");

		if((p.itemSlot >= INVENTORY_SLOT_ITEM_START) and (p.itemSlot <= INVENTORY_SLOT_ITEM_END)) then
			print("In backpack.");
			local index = PLAYER_FIELD_PACK_SLOT_1 + ((p.itemSlot - INVENTORY_SLOT_ITEM_START) * 2);
			guid = guidFromValues(STATE.me, index);
		else
			print("Not in backpack?");
			return;
		end
	end

	if((p.bagSlot >= INVENTORY_SLOT_BAG_START) and (p.bagSlot <= INVENTORY_SLOT_BAG_END)) then
		print("In bag!");
		local bagIndex = PLAYER_FIELD_BAG_SLOT_1 + ((p.bagSlot - INVENTORY_SLOT_BAG_START) * 2);
		local bagGuid = guidFromValues(STATE.me, bagIndex);
		local bag = STATE.knownObjects[bagGuid];
		assert(p.itemSlot < 32);	-- sanity check, max bag size.
		assert(p.itemSlot < bag.values[CONTAINER_FIELD_NUM_SLOTS]);
		local index = CONTAINER_FIELD_SLOT_1 + (p.itemSlot * 2);
		guid = guidFromValues(bag, index);
	end

	if(not guid) then
		print("Guid not found, out of ideas.");
		return;
	end

	local proto = itemProtoFromId(p.itemId);
	if(not proto) then
		-- we can't pass item's slots here, even though equip() needs them,
		-- because the item may have moved before the callback is called.
		STATE.itemDataCallbacks[guid] = maybeEquip;
		return;
	end
	maybeEquip(guid);
end

function maybeEquip(itemGuid)
	local itemId = STATE.knownObjects[itemGuid].values[OBJECT_FIELD_ENTRY];
	if(wantToWear(itemId)) then
		equip(itemGuid);
	end
end

function equip(itemGuid)
	local itemId = STATE.knownObjects[itemGuid].values[OBJECT_FIELD_ENTRY];
	local proto = itemProtoFromId(itemId);
	print("Equipping "..itemId.." "..itemGuid:hex().." "..proto.name);
	--[[
	-- search all bag slots for item.
	-- if not found, error.
	local slot, bagSlot;
	for i = PLAYER_FIELD_PACK_SLOT_1, PLAYER_FIELD_PACK_SLOT_LAST, 2 do
		if(guidFromValues(STATE.me, i) == itemGuid) then
			slot = i;
			bagSlot = INVENTORY_SLOT_BAG_0;
			break;
		end
	end
	if(not slot) then for i = PLAYER_FIELD_BAG_SLOT_1, PLAYER_FIELD_BAG_SLOT_LAST, 2 do
		local bag = STATE.knownObjects[guidFromValues(STATE.me, i)];
		if(isValidGuid(bag)) then for j = 0, bag.values[CONTAINER_FIELD_NUM_SLOTS], 1 do
			if(guidFromValues(bag, CONTAINER_FIELD_SLOT_1 + (j*2)) == itemGuid) then
				bagSlot = i;
				slot = j;
				goto haveSlot;
			end
		end end
	end end
	if(not slot) then
		error("Item not found in any slot. What happened?");
	end
	::haveSlot::
	--]]
	-- todo: for items that can go in more than one slot, pick a good one.
	local dstSlot = itemEquipSlot(proto);
	print(dump(dstSlot), type(dstSlot));
	send(CMSG_AUTOEQUIP_ITEM_SLOT, {itemGuid=itemGuid, dstSlot=dstSlot});
end
