local function range(start, _end)
	assert(_end > start);
	local r = {};
	for i=1,(_end-start) do
		r[i] = start + (i-1);
	end
	return r;
end

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
	[INVTYPE_BAG] = range(INVENTORY_SLOT_BAG_START, INVENTORY_SLOT_BAG_END),
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
	--print(count.." callbacks called.");
	-- remove only those callbacks that we called.
	-- do it after the iteration, so the iterator doesn't get confused.
	for p, t in pairs(set) do
		callbacks[p] = nil;
	end
end

function hSMSG_ITEM_QUERY_SINGLE_RESPONSE(p)
	--print("SMSG_ITEM_QUERY_SINGLE_RESPONSE "..p.itemId);
	STATE.itemProtosWaiting[p.itemId] = nil;
	STATE.itemProtos[p.itemId] = p;
	if(not next(STATE.itemProtosWaiting)) then
		--print("All item protos received.");
		doCallbacks(STATE.itemDataCallbacks);
	end
end

local function canDualWield()
	return STATE.knownSpells[674]
end

-- returns one of enum EquipmentSlots.
function itemEquipSlot(proto)
	--print("itemSlotIndex("..proto.InventoryType..")", dump(itemInventoryToEquipmentSlot));
	if((proto.InventoryType == INVTYPE_WEAPON) and not canDualWield()) then
		return EQUIPMENT_SLOT_MAINHAND;
	end
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


function wantToWear(id, verbose)
	-- this is tricky.
	-- we don't want to wear anything we can't wear.
	-- we want to wear something with "better" stats than what we already have.
	local proto = itemProtoFromId(id);
	if(verbose) then
		partyChat("Testing weariness of item "..proto.name.." ("..id..")...");
	end

	-- if it's not equipment, we can't wear it.
	local slots = itemEquipSlot(proto);
	if(not slots) then
		if(verbose) then
			partyChat("no slot found.");
		end
		return false;
	end

	-- make sure we have the skill needed to wear it.
	local spellId = itemSkillSpell(proto);
	if(spellId) then
		if(not STATE.knownSpells[spellId]) then
			if(verbose) then
				partyChat("proficiency not known: "..spellId);
			end
			return false;
		end
	else
		-- some items don't require skills. We can use them.
		if(verbose) then
			partyChat("No proficiency needed. class: "..proto.itemClass.." subClass: "..proto.subClass);
		end
	end

	-- make sure we're high enough level.
	--	-- disable this test; it's applied at quest reward selection,
	-- and we don't want to pass up the good stuff.
	if(verbose) then
		if(proto.RequiredLevel > STATE.myLevel) then
			partyChat("Need to be level "..proto.RequiredLevel.." to wear "..proto.name);
			return false;
		end
	end
	--]]

	if(type(slots) ~= 'table') then
		slots = {slots};
	end
	local chosenSlot = false;
	local chosenValue = nil;
	local newValue = valueOfItem(id, verbose);
	for i, slot in ipairs(slots) do
		local equippedGuid = equipmentInSlot(slot);
		if(not equippedGuid) then
			if(verbose) then
				partyChat("no item equipped in that slot. I'm gonna wear it!");
			end
			return slot;
		end
		local equippedId = itemIdOfGuid(equippedGuid);

		-- if new item is better than equipped item, replace it.
		local equippedValue = valueOfItem(equippedId, verbose);
		if(verbose) then
			partyChat("equipped: "..equippedValue..". new: "..newValue);
		end
		if(newValue > equippedValue) then
			-- if we have two items that can be swapped out, pick the cheaper one.
			if(verbose) then
				partyChat("it's better.");
			end
			if((not chosenValue) or (equippedValue < chosenValue)) then
				chosenSlot = slot;
				chosenValue = newValue;
			end
		else
			if(verbose) then
				partyChat("it's worse.");
			end
		end
	end
	return chosenSlot;
end

function avgItemDamage(proto)
	local avg = 0;
	--print(dump(proto.damages));
	for i,d in ipairs(proto.damages) do
		avg = avg + ((d.min + d.max) / 2);
	end
	--print("avgDamage: "..avg);
	return avg;
end

function avgItemDps(proto)
	--print("proto.Delay: "..proto.Delay);
	return avgItemDamage(proto) / (proto.Delay / 1000);
end

ClassInfo = {
	Mage = {
		ranged=true,
		primary=STAT_INTELLECT,
		secondaries={STAT_STAMINA},
	},
	--Druid	-- only feral spec.
	Priest = {
		ranged=true,
		primary=STAT_SPIRIT,
		secondaries={STAT_INTELLECT, STAT_STAMINA},
	},
	Warlock = {
		ranged=true,
		primary=STAT_INTELLECT,
		secondaries={STAT_STAMINA},
	},
	Hunter = {
		ranged=true,
		primary=STAT_AGILITY,
		secondaries={STAT_INTELLECT, STAT_STAMINA},
	},
	Shaman = {
		ranged=true,	-- except Enhancement spec.
		primary=STAT_AGILITY,	-- Enhancement
		--primary=STAT_SPIRIT,	-- Restoration
		--primary=STAT_INTELLECT,	-- Elemental
		secondaries={STAT_INTELLECT, STAT_STAMINA},	-- Enhancement
	},
	Rogue = {
		ranged=false,
		primary=STAT_AGILITY,
		secondaries={STAT_STRENGTH, STAT_STAMINA},
	},
	Warrior = {
		ranged=false,
		primary=STAT_STRENGTH,
		secondaries={STAT_AGILITY, STAT_STAMINA},
	},
	Paladin = {
		ranged=false,
		primary=STAT_STRENGTH,	-- Retribution
		secondaries={STAT_STAMINA},
		--[[ Holy
		primary=STAT_INTELLECT,
		secondaries={STAT_SPIRIT, STAT_STAMINA},]]
		--[[ Protection
		primary=STAT_STAMINA,
		secondaries={STAT_STRENGTH,STAT_AGILITY},]]
	},
}

local itemModStat = {
	[STAT_STRENGTH] = ITEM_MOD_STRENGTH,
	[STAT_AGILITY] = ITEM_MOD_AGILITY,
	[STAT_INTELLECT] = ITEM_MOD_INTELLECT,
	[STAT_SPIRIT] = ITEM_MOD_SPIRIT,
	[STAT_STAMINA] = ITEM_MOD_STAMINA,
}

local rangedSubclass = {
	[ITEM_SUBCLASS_WEAPON_BOW]=true,
	[ITEM_SUBCLASS_WEAPON_GUN]=true,
	[ITEM_SUBCLASS_WEAPON_WAND]=true,
};

local dMsg;

local function addDumpIf(a, b, name, verbose)
	if(verbose) then
		dMsg = dMsg..name..": "..tostring(b).."\n";
	end
	return a+b;
end

-- only call this function if itemProtoFromId(id) returns non-nil.
function valueOfItem(id, verbose)
	local ip = itemProtoFromId(id);
	assert(ip);
	--return ip.SellPrice;

	-- do proper value calculation.
	-- take into account: damage, armor, stats (weighted by primary and secondaries),
	-- resistances.
	-- todo: take into account any spells that may be active on the item.
	-- useful spells usually have the APPLY_AURA effect.

	-- unrelated factors like damage/armor are weighted arbitrarily.
	-- adjust weighting as needed.
	local p = itemProtoFromId(id);
	if(verbose) then
		dMsg = "Calculating value for "..p.name..":\n";
	end
	local v = addDumpIf(0, p.Armor, "Armor", verbose);

	-- Resistances are situational.
	-- In vanilla, we need only Fire in Molten Core, Nature in Ahn'Qiraj, and Frost in Naxxramas.
	-- todo: add a command to set value for a specific resistance. ex: 'itemResValue fire 10'
	--local avgRes = (p.HolyRes + p.FireRes + p.NatureRes + p.FrostRes + p.ShadowRes + p.ArcaneRes) / 6;
	--v = v + avgRes * 0;

	local ci = ClassInfo[STATE.myClassName];

	local mods = {};
	for i, s in ipairs(p.stats) do
		mods[s.type] = (mods[s.type] or 0) + s.value;
	end

	local primaryStatValue = mods[itemModStat[ci.primary]] or 0;
	local combinedSecondaryStatValue = 0;
	local hasSecondaryIntellect = false;
	for i, s in ipairs(ci.secondaries) do
		combinedSecondaryStatValue = combinedSecondaryStatValue + (mods[itemModStat[s]] or 0);
		if(s == STAT_INTELLECT) then hasSecondaryIntellect = true; end
	end
	v = addDumpIf(v, primaryStatValue * 20 + combinedSecondaryStatValue * 10, "Stats", verbose);

	if(ci.primary == STAT_INTELLECT or hasSecondaryIntellect) then
		v = addDumpIf(v, mods[ITEM_MOD_MANA] or 0, "Mana", verbose);
	end

	v = addDumpIf(v, mods[ITEM_MOD_HEALTH] or 0, "Health", verbose);

	-- damage is worthless on melee weapons for ranged characters.
	-- likewise, damage is worthless on ranged weapons for melee characters.
	-- there are some non-weapon items with damage on them,
	-- but they're too rare to bother with now.
	if(p._class == ITEM_CLASS_WEAPON and rangedSubclass[p.subClass] and ci.ranged)
	then
		v = addDumpIf(v, avgItemDps(p) * 100, "DPS ranged", verbose);
	elseif(not ci.ranged) then
		v = addDumpIf(v, avgItemDps(p) * 100, "DPS melee", verbose);
	else
		v = addDumpIf(v, avgItemDps(p), "DPS useless", verbose);
	end
	if(verbose) then
		print(dMsg);
	end
	return v;
end

function itemLoginComplete()
	-- fetch item info for all equipped items.
	--print("Equipped items:");
	for i = EQUIPMENT_SLOT_START, EQUIPMENT_SLOT_END-1 do
		local equippedGuid = equipmentInSlot(i);
		if(equippedGuid) then
			local id = itemIdOfGuid(equippedGuid);
			--print(id, equippedGuid:hex(), STATE.knownObjects[equippedGuid].values[ITEM_FIELD_STACK_COUNT]);
			itemProtoFromId(id);
		end
	end
	--print("Inventory items:");
	investigateInventory(function(o)
		local id = itemIdOfGuid(o.guid);
		--print(id, o.guid:hex(), o.values[ITEM_FIELD_STACK_COUNT]);
		maybeEquip(o.guid);
	end)
	investigateBank(function(o)
		itemProtoFromId(itemIdOfGuid(o.guid));
	end)
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
	--print("SMSG_ITEM_PUSH_RESULT", dump(p));
	-- we've got a new item. if we want to wear it, then wear it.

	-- if it wasn't us who got the item, we don't care.
	if(p.playerGuid ~= STATE.myGuid) then
		--print("got SMSG_ITEM_PUSH_RESULT for another player.");
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
		--print("INVENTORY_SLOT_BAG_0.");

		if((p.itemSlot >= INVENTORY_SLOT_ITEM_START) and (p.itemSlot <= INVENTORY_SLOT_ITEM_END)) then
			--print("In backpack.");
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

	maybeEquip(guid);
end

function maybeEquip(itemGuid, verbose)
	local id = itemIdOfGuid(itemGuid);
	if(not itemProtoFromId(id)) then
		STATE.itemDataCallbacks[itemGuid] = maybeEquip;
		return;
	end
	local slot = wantToWear(id, verbose);
	if(slot) then
		equip(itemGuid, id, slot);
	end
end

-- slot is one of the EQUIPMENT_SLOT constants.
function equip(itemGuid, itemId, slot)
	local proto = itemProtoFromId(itemId);
	local msg = "Equipping "..itemId.." "..itemGuid:hex().." "..proto.name;
	print(msg);
	partyChat(msg);

	-- todo: for items that can go in more than one slot, pick a good one.
	send(CMSG_AUTOEQUIP_ITEM_SLOT, {itemGuid=itemGuid, dstSlot=slot});
end

local function baseInvestigate(directField1, directFieldLast,
	directBagSlot, directItemSlotStart,
	bagField1, bagFieldLast, bagSlotStart, f)
	local freeSlotCount = 0;
	-- backpack
	for i = directField1, directFieldLast, 2 do
		local guid = guidFromValues(STATE.me, i);
		if(isValidGuid(guid)) then
			local o = STATE.knownObjects[guid];
			local bagSlot = directBagSlot;
			local slot = directItemSlotStart + ((i - directField1) / 2);
			local res = f(o, bagSlot, slot);
			if(res == false) then return; end
		else
			freeSlotCount = freeSlotCount + 1;
		end
	end
	-- bags
	for i = bagField1, bagFieldLast, 2 do
		local bagGuid = guidFromValues(STATE.me, i);
		if(isValidGuid(bagGuid)) then
			local bag = STATE.knownObjects[bagGuid];
			local slots;
			if(bag) then slots = bag.values[CONTAINER_FIELD_NUM_SLOTS]; end
			--print(tostring(slots));
			if(slots) then for j = 0, slots, 1 do
				local guid = guidFromValues(bag, CONTAINER_FIELD_SLOT_1 + (j*2))
				if(isValidGuid(guid)) then
					local o = STATE.knownObjects[guid];
					local bagSlot = bagSlotStart + ((i - bagField1) / 2);
					local slot = j;
					local res = f(o, bagSlot, slot);
					if(res == false) then return; end
				else
					freeSlotCount = freeSlotCount + 1;
				end
			end end
		end
	end
	return freeSlotCount;
end

function investigateInventory(f)
	return baseInvestigate(PLAYER_FIELD_PACK_SLOT_1, PLAYER_FIELD_PACK_SLOT_LAST,
		INVENTORY_SLOT_BAG_0, INVENTORY_SLOT_ITEM_START,
		PLAYER_FIELD_BAG_SLOT_1, PLAYER_FIELD_BAG_SLOT_LAST,
		INVENTORY_SLOT_BAG_START, f)
end

function investigateBank(f)
	return baseInvestigate(PLAYER_FIELD_BANK_SLOT_1, PLAYER_FIELD_BANK_SLOT_LAST,
		INVENTORY_SLOT_BAG_0, BANK_SLOT_ITEM_START,
		PLAYER_FIELD_BANKBAG_SLOT_1, PLAYER_FIELD_BANKBAG_SLOT_LAST,
		BANK_SLOT_BAG_START, f)
end

function itemInventoryCountById(itemId)
	local count = 0;
	investigateInventory(function(o)
		if(o.values[OBJECT_FIELD_ENTRY] == itemId) then
			count = count + o.values[ITEM_FIELD_STACK_COUNT];
		end
	end)
	return count;
end

local function itemString(o)
	--item:itemId:enchantId:suffixId:uniqueId
	return "item:"..o.values[OBJECT_FIELD_ENTRY]..":"..
		(o.values[ITEM_FIELD_ENCHANTMENT] or 0)..":"..
		(o.values[ITEM_FIELD_RANDOM_PROPERTIES_ID] or 0)..":0";
end

local itemColors = {
	[ITEM_QUALITY_POOR] = "9d9d9d",
	[ITEM_QUALITY_NORMAL] = "ffffff",
	[ITEM_QUALITY_UNCOMMON] = "1eff00",
	[ITEM_QUALITY_RARE] = "0070dd",
	[ITEM_QUALITY_EPIC] = "a335ee",
	[ITEM_QUALITY_LEGENDARY] = "ff8000",
	[ITEM_QUALITY_ARTIFACT] = "e6cc80",
};

function itemLink(o)
	--|cffffffff|Hitem:2886:0:0:0|h[Crag Boar Rib]|h|r
	local proto = itemProtoFromId(o.values[OBJECT_FIELD_ENTRY]);
	local link = "|cff"..itemColors[proto.Quality].."|H"..itemString(o).."|h["..proto.name.."]|h|r";
	return link;
end

function isFishingPole(o)
	local proto = itemProtoFromId(o.values[OBJECT_FIELD_ENTRY]);
	return (proto.itemClass == ITEM_CLASS_WEAPON and
		proto.subClass == ITEM_SUBCLASS_WEAPON_FISHING_POLE);
end
