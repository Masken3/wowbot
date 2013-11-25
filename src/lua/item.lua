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

function itemProtoFromObject(o)
	return itemProtoFromId(o.values[OBJECT_FIELD_ENTRY]);
end

function delayedItemProto(id, f)
	local proto = itemProtoFromId(id);
	if(proto) then
		f(proto);
	else
		STATE.itemDataCallbacks[{id=id, f=f}] = function(t)
			t.f(itemProtoFromId(t.id));
		end;
	end
end

function doCallbacks(callbacks)
	-- keep a separate set; new callbacks may be added by old callbacks.
	local set = {}
	local count = 0;
	for p, f in pairs(callbacks) do
		set[p] = f;
	end
	for p, f in pairs(set) do
		count = count + 1;
		--print("type: ", p, type(f))
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
	return STATE.knownSpells[674] and not STATE.amTank
end

-- returns one of enum EquipmentSlots.
function itemEquipSlot(proto)
	--print("itemEquipSlot "..proto.name);

	--[[
	-- rogues must have a dagger in their main hand.
	if(STATE.myClassName == 'Rogue' and
		proto.itemClass == ITEM_CLASS_WEAPON)
	then
		-- TEMP: rogues must have a dagger in their main hand.
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_DAGGER) then
			print("mainhand only.");
			return EQUIPMENT_SLOT_MAINHAND;
		elseif(proto.InventoryType == INVTYPE_WEAPONMAINHAND) then
			print("not mainhand.");
			return nil;
		elseif(proto.InventoryType == INVTYPE_WEAPON) then
			print("offhand only.");
			return EQUIPMENT_SLOT_OFFHAND;
		end
	end
	--]]

	--print("itemSlotIndex("..proto.InventoryType..")", dump(itemInventoryToEquipmentSlot));
	if((proto.InventoryType == INVTYPE_WEAPON) and (not canDualWield())) then
		return EQUIPMENT_SLOT_MAINHAND;
	end
	-- tanks may not use 2handers or off-hand items except shields.
	if(STATE.amTank and (
		proto.InventoryType == INVTYPE_2HWEAPON or
		proto.InventoryType == INVTYPE_WEAPONOFFHAND or
		proto.InventoryType == INVTYPE_HOLDABLE))
	then
		return nil;
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
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_AXE2 and not STATE.amTank) then return 197; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_BOW) then return 264; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_GUN) then return 266; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_MACE) then return 198; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_MACE2 and not STATE.amTank) then return 199; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_POLEARM and not STATE.amTank) then return 200; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_SWORD) then return 201; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_SWORD2 and not STATE.amTank) then return 202; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_STAFF and not STATE.amTank) then return 227; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_DAGGER) then return 1180; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_THROWN) then return 2567; end
		if(proto.subClass == ITEM_SUBCLASS_WEAPON_SPEAR and not STATE.amTank) then return 3386; end
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


-- returns false, or slot [, valueDiff]
function wantToWear(id, guid, verbose)
	-- this is tricky.
	-- we don't want to wear anything we can't wear.
	-- we want to wear something with "better" stats than what we already have.
	local proto = itemProtoFromId(id);
	if(verbose) then
		partyChat("Testing weariness of item "..proto.name.." ("..id..")...");
	end

	-- TODO: tanks shouldn't wear 2-handers or off-hand items that aren't shields.

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
	local newValue = valueOfItem(id, guid, verbose);
	local valueDiff = nil;
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
		local equippedValue = valueOfItem(equippedId, equippedGuid, verbose);
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
				valueDiff = newValue - equippedValue;
			end
		else
			if(verbose) then
				partyChat("it's worse.");
			end
		end
	end
	return chosenSlot, valueDiff;
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
	if(proto.Delay == 0) then return 0; end
	return avgItemDamage(proto) / (proto.Delay / 1000);
end

ClassInfo = {
	Mage = {
		ranged=true,
		primary=STAT_INTELLECT,
		secondaries={STAT_STAMINA, STAT_SPIRIT},
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
		primary={[STAT_AGILITY]=20, [STAT_STRENGTH]=15},
		secondaries={STAT_STAMINA},
	},
	Warrior = {
		ranged=false,
		primary={[STAT_STAMINA]=20, [STAT_STRENGTH]=15},
		secondaries={STAT_AGILITY},
	},
	Paladin = {
		ranged=false,
		primary=STAT_STRENGTH,	-- Retribution or Holy/Damage
		secondaries={STAT_STAMINA, STAT_INTELLECT},
		--[[ Holy/Healing
		primary=STAT_INTELLECT,
		secondaries={STAT_SPIRIT, STAT_STAMINA},]]
		--[[ Protection
		primary=STAT_STAMINA,
		secondaries={STAT_STRENGTH,STAT_AGILITY},]]
	},
}

-- if this returns true, ranged attack power is useless.
local function isCaster(ci)
	return ci.ranged and (ci.primary ~= STAT_AGILITY);
end

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

local function addDumpIf(a, b, name, verbose)
	if((verbose == true) or (b ~= 0 and verbose == 1)) then
		print(name..": "..tostring(b));
	end
	return a+b;
end

local function addDamageValueRaw(v, dps, isRangedDamage, ci, verbose)
	-- damage is worthless on melee weapons for ranged characters.
	-- likewise, damage is worthless on ranged weapons for melee characters.
	-- there are some non-weapon items with damage on them,
	-- but they're too rare to bother with now.
	if(isRangedDamage and ci.ranged and (not isCaster(ci)))
	then
		v = addDumpIf(v, dps * 100, "DPS ranged", verbose);
	elseif(not isRangedDamage and not ci.ranged) then
		v = addDumpIf(v, dps * 100, "DPS melee", verbose);
	else
		v = addDumpIf(v, dps, "DPS useless", verbose);
	end
	return v;
end

local function addDamageValueFromItem(v, dps, p, ci, verbose)
	return addDamageValueRaw(v, dps,
		(p.itemClass == ITEM_CLASS_WEAPON and rangedSubclass[p.subClass]), ci, verbose);
end

local function addModValues(v, mods, p, ci, verbose)
	local primaryStatValue;
	if(type(ci.primary) == 'table') then
		primaryStatValue = 0;
		for s, v in pairs(ci.primary) do
			primaryStatValue = primaryStatValue + (mods[itemModStat[s]] or 0) * v;
		end
		primaryStatValue = primaryStatValue / 20;
	else
		primaryStatValue = mods[itemModStat[ci.primary]] or 0;
	end
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
	return v;
end

local function addItemSpellValue(v, mods, s, proto, ci, verbose, pointFactor)
--print(s.name, e.spellId);
	pointFactor = pointFactor or 1;
	local level = spellLevel(s);
	for j,se in ipairs(s.effect) do
		local points = calcAvgEffectPoints(level, se) * pointFactor;
		if(se.id == SPELL_EFFECT_APPLY_AURA) then
			if(se.applyAuraName == SPELL_AURA_MOD_STAT) then
				-- for this aura, miscValue is one of the STAT_ defines (0-4).
				if(se.miscValue == -2) then	-- all stats
					for s,m in pairs(itemModStat) do
						mods[m] = (mods[m] or 0) + points;
					end
				else
					local m = itemModStat[se.miscValue];
					-- assuming level 0 here. may need modification.
					mods[m] = (mods[m] or 0) + points;
				end
			elseif(se.applyAuraName == SPELL_AURA_MOD_DAMAGE_DONE) then
				-- se.miscValue is schoolMask (1 << enum SpellSchools)

				-- it's really hard to assign a reasonable value to this effect;
				-- you have to know if you would more damage with it than without.
				-- that requires you to know if you have any spells in this school
				-- that you're actually using.
				-- for now, we'll just ignore it.

				-- all schools
				if(se.miscValue == 0x7E) then
					v = addDumpIf(v, points*10, "Magic Damage+", verbose)
				end
			elseif(se.applyAuraName == SPELL_AURA_MOD_ATTACK_POWER) then
				v = addDamageValueRaw(v, points / 14, false, ci, verbose)
			elseif(se.applyAuraName == SPELL_AURA_MOD_RANGED_ATTACK_POWER) then
				v = addDamageValueRaw(v, points / 14, true, ci, verbose)
			elseif(se.applyAuraName == SPELL_AURA_MOD_MELEE_ATTACK_POWER_VERSUS) then
				v = addDamageValueRaw(v, points / 140, false, ci, verbose)
			elseif(se.applyAuraName == SPELL_AURA_MOD_RANGED_ATTACK_POWER_VERSUS) then
				v = addDamageValueRaw(v, points / 140, true, ci, verbose)
			elseif(se.applyAuraName == SPELL_AURA_MOD_INCREASE_ENERGY) then
				if(ci.ranged) then
					v = addDumpIf(v, points, "Mana+", verbose)
				end
			elseif(se.applyAuraName == SPELL_AURA_MOD_INCREASE_HEALTH) then
				v = addDumpIf(v, points, "Health+", verbose)
			elseif(se.applyAuraName == SPELL_AURA_MOD_RESISTANCE) then
				-- we don't care much about resistances yet.
				v = addDumpIf(v, points, "Resistance", verbose)
			elseif(se.applyAuraName == SPELL_AURA_MOD_DAMAGE_DONE_CREATURE) then
				v = addDumpIf(v, points, "CreatureDmg+", verbose)
			elseif(se.applyAuraName == SPELL_AURA_MOD_HEALING_DONE) then
				if(STATE.amHealer) then
					v = addDumpIf(v, points*10, "Healing+", verbose)
				end
			elseif(se.applyAuraName == SPELL_AURA_PROC_TRIGGER_SPELL) then
				-- check all proc flags
				local procFlags = s.procFlags
				local flagsOnHit = bit32.bor(PROC_FLAG_TAKEN_MELEE_HIT, PROC_FLAG_TAKEN_MELEE_SPELL_HIT)
				if(bit32.btest(procFlags, flagsOnHit)) then
					-- remove the flags
					procFlags = bit32.band(procFlags, bit32.bnot(flagsOnHit))
					-- only if we're the tank is it useful to be hit by enemies.
					if(STATE.amTank) then
						local hitsPerSecond = 1	-- the approximate hits per second a tank takes.
						local factor = hitsPerSecond * getDuration(s.DurationIndex, level) * s.procChance / 100
						v = addItemSpellValue(v, mods, cSpell(se.triggerSpell), proto,
							ci, verbose, pointFactor)
					end
				end
				if(procFlags ~= 0) then
					print("WARN: unhandled procFlags 0x"..hex(procFlags)..
						" on spell="..s.id.." ("..s.name.."), item="..proto.itemId.." ("..proto.name..")");
				end
			elseif(se.applyAuraName == SPELL_AURA_MOD_MANA_REGEN_INTERRUPT) then
				v = addDumpIf(v, points*20, "Casting Mana Regen+%", verbose)
			elseif(se.applyAuraName == SPELL_AURA_MOD_SKILL) then
				if(se.miscValue == 95) then	-- Defense
					if(STATE.amTank) then
						v = addDumpIf(v, points*20, "Defense+", verbose)
					end
				elseif(se.miscValue == 356) then	-- Fishing
					v = addDumpIf(v, points, "Fishing+", verbose)
				else
					print("WARN: unhandled skill "..se.miscValue..
						" on spell="..s.id.." ("..s.name.."), item="..proto.itemId.." ("..proto.name..")");
				end
			elseif(se.applyAuraName == SPELL_AURA_MOD_BLOCK_PERCENT) then
				if(STATE.amTank) then
					v = addDumpIf(v, points*(STATE.myLevel^1.5), "Block%+", verbose)
				end
			elseif(se.applyAuraName == SPELL_AURA_MOD_DODGE_PERCENT) then
				local factor = 10
				if(STATE.amTank) then factor = (STATE.myLevel^1.5) end
				v = addDumpIf(v, points*factor, "Dodge%+", verbose)
			elseif(se.applyAuraName == SPELL_AURA_PERIODIC_HEAL) then
				local factor = 10
				if(STATE.amTank) then factor = 50 end
				v = addDumpIf(v, points * factor, "HP"..(se.amplitude / 1000), verbose)
			elseif(se.applyAuraName == SPELL_AURA_MOD_HEALTH_REGEN_IN_COMBAT) then
				-- this does the exact same thing as SPELL_AURA_PERIODIC_HEAL, with less options.
				-- weird, eh?
				local factor = 10
				if(STATE.amTank) then factor = 50 end
				v = addDumpIf(v, points * factor, "HP5", verbose)
			elseif(se.applyAuraName == SPELL_AURA_MOD_POWER_REGEN) then
				local factor = 1
				if(isCaster(ci)) then factor = 50 end
				v = addDumpIf(v, points * factor, "MP5", verbose)
			elseif(se.applyAuraName == SPELL_AURA_MOD_MOUNTED_SPEED_ALWAYS) then
				-- pretty worthless.
				v = addDumpIf(v, points, "Mount speed", verbose)
			elseif(se.applyAuraName == SPELL_AURA_DUMMY) then
				-- does different things depending on spell id.
				if(s.id == 17670) then	-- Argent Dawn Commission
					-- required for human players in plaguelands, scholomance and stratholme,
					-- useless everywhere else.
				else
					print("WARN: unhandled dummy effect "..
						" on spell="..s.id.." ("..s.name.."), item="..proto.itemId.." ("..proto.name..")");
				end
			elseif(se.applyAuraName == SPELL_AURA_SCHOOL_ABSORB) then
				if(STATE.amTank) then
					-- arbitrary factor
					v = addDumpIf(v, points * 2, "Damage absorbtion", verbose)
				end
			elseif(se.applyAuraName == SPELL_AURA_DAMAGE_SHIELD) then
				if(STATE.amTank) then
					-- arbitrary factor
					v = addDumpIf(v, points*200, "Damage shield", verbose)
				end
			elseif(se.applyAuraName == SPELL_AURA_MOD_CRIT_PERCENT) then
				if(not isCaster(ci)) then
					v = addDumpIf(v, points*200, "Crit%+", verbose)
				end
			else
				print("WARN: unhandled aura "..se.applyAuraName..
					" on spell="..s.id.." ("..s.name.."), item="..proto.itemId.." ("..proto.name..")");
			end
		elseif(se.id == SPELL_EFFECT_SCHOOL_DAMAGE) then
			local factor = 100
			if(isCaster(ci)) then factor = 10 end
			v = addDumpIf(v, points*factor, "Damage", verbose)
		elseif(se.id == SPELL_EFFECT_ADD_EXTRA_ATTACKS) then
			v = addDamageValueFromItem(v, avgItemDamage(proto)*pointFactor, proto, ci, verbose);
		elseif(se.id ~= 0) then
			print("WARN: unhandled effect "..se.id..
				" on spell="..s.id.." ("..s.name.."), item="..proto.itemId.." ("..proto.name..")");
		end
	end
	return v;
end

function positiveSpellPoints(s, verbose)
	local v = 0;
	local mods = {};
	local ci = ClassInfo[STATE.myClassName];
	local proto = {itemId='nil',name='nil'};
	v = addItemSpellValue(v, mods, s, proto, ci, verbose);
	v = addModValues(v, mods, proto, ci, verbose and 1);
	return v;
end

function enchValue(enchId, proto, ci, verbose)
	local ench = cSpellItemEnchantment(enchId);
	ci = ci or ClassInfo[STATE.myClassName];
	if(not ench) then return 0; end

	local v = 0;
	local mods = {};
	for i,e in ipairs(ench.effect) do
		if(verbose and e.type ~= 0) then
			print("Effect "..i..": type "..tostring(e.type).." amount "..e.amount.." spell "..e.spellId);
		end
		if(e.type == ITEM_ENCHANTMENT_TYPE_DAMAGE) then
			if(proto.Delay > 0) then
				v = addDamageValueFromItem(v, e.amount / (proto.Delay / 1000), proto, ci, verbose)
			else
				-- such an enchantment would affect all equipped weapons?
				-- todo: find out. low prio.
			end
		elseif(e.type == ITEM_ENCHANTMENT_TYPE_EQUIP_SPELL) then
			local s = cSpell(e.spellId);
			v = addItemSpellValue(v, mods, s, proto, ci, verbose);
		elseif(e.type == ITEM_ENCHANTMENT_TYPE_STAT) then
			mods[e.spellId] = (mods[e.spellId] or 0) + e.amount;
		elseif(e.type == ITEM_ENCHANTMENT_TYPE_RESISTANCE) then
			v = addDumpIf(v, e.amount, "Resistance", verbose);
		--ITEM_ENCHANTMENT_TYPE_COMBAT_SPELL
		--ITEM_ENCHANTMENT_TYPE_TOTEM
		elseif(e.type ~= ITEM_ENCHANTMENT_TYPE_NONE) then
			print("WARN: unknown enchantment effect "..e.type.." in enchantment "..enchId);
		end
	end
	v = addModValues(v, mods, proto, ci, verbose and 1);
	return v;
end

local function addSpellValueFromItem(v, proto, ci, verbose)
	local mods = {};
	for i,spell in ipairs(proto.spells) do
		if(spell.trigger == ITEM_SPELLTRIGGER_ON_EQUIP and spell.id ~= 0) then
			v = addItemSpellValue(v, mods, cSpell(spell.id), proto, ci, verbose);
		elseif(spell.trigger == ITEM_SPELLTRIGGER_CHANCE_ON_HIT and spell.id ~= 0) then
			-- this proc-factor estimate a very rough, but I don't think the server tells us much about it.
			-- perhaps we can use statistics to refine an item's proc value after seeing it in action some.
			local procFactor = 0.1;
			if(proto.itemClass == ITEM_CLASS_WEAPON) then procFactor = 0.05; end
			if(proto.itemClass == ITEM_CLASS_ARMOR) then procFactor = 0.3; end
			v = addItemSpellValue(v, mods, cSpell(spell.id), proto, ci, verbose, procFactor);
		elseif(spell.trigger == ITEM_SPELLTRIGGER_ON_USE) then
			-- ignore it, since we don't have any code for using such items.
		elseif(spell.id ~= 0) then
			local s = cSpell(spell.id);
			print("WARN: unhandled trigger "..spell.trigger..
				" on spell="..s.id.." ("..s.name.."), item="..proto.itemId.." ("..proto.name..")");
		end
	end
	v = addModValues(v, mods, proto, ci, verbose and 1);
	return v;
end

function hasFishingEnchantment(o)
	local proto = itemProtoFromObject(o);
	for i,spell in ipairs(proto.spells) do
		if(spell.trigger == ITEM_SPELLTRIGGER_ON_EQUIP and spell.id ~= 0) then
			local s = cSpell(spell.id);
			for j,e in ipairs(s.effect) do
				--local points = calcAvgEffectPoints(level, e);
				if(e.id == SPELL_EFFECT_APPLY_AURA and
					e.applyAuraName == SPELL_AURA_MOD_SKILL and
					e.miscValue == 356)	-- Fishing
				then
					return true;
				end
			end
		end
	end
	return false;
end

-- only call this function if itemProtoFromId(id) returns non-nil.
function valueOfItem(id, guid, verbose)
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
		print("Calculating value for "..p.name..":");
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

	v = addModValues(v, mods, p, ci, verbose);

	v = addDamageValueFromItem(v, avgItemDps(p), p, ci, verbose);

	v = addSpellValueFromItem(v, p, ci, verbose);

	if(guid) then
		local o = STATE.knownObjects[guid];
		---- ignore player-made enchantments, because those can be put on the new item, too.
		for slot=PROP_ENCHANTMENT_SLOT_0,(MAX_ENCHANTMENT_SLOT-1) do
			local idx = ITEM_FIELD_ENCHANTMENT + slot*3;
			--[[
			-- ignore temporary enchantments.
			if((o.values[idx+ENCHANTMENT_DURATION_OFFSET] or 0) == 0 and
				(o.values[idx+ENCHANTMENT_CHARGES_OFFSET] or 0) == 0)
			then]]do
				local enchId = o.values[idx+ENCHANTMENT_ID_OFFSET];
				if(enchId) then
					if(verbose) then
						print("Enchantment "..slot..":");
					end
					v = v + enchValue(enchId, p, ci, verbose);
				end
			end
		end
	end

	if(v == 0) then
		return ip.SellPrice / 1000;
	end

	return v;
end

function itemLoginComplete()
	-- fetch item info for all equipped items.
	--print("Equipped items:");

	--STATE.itemDataCallbacks["temp"] = doInventoryWindow;
	--STATE.itemDataCallbacks[STATE.attackSpells] = dumpMostEffectiveSpell;
	--STATE.itemDataCallbacks[STATE.aoeAttackSpells] = dumpMostEffectiveSpell;
	STATE.itemDataCallbacks["drink"] = function() STATE.readyToDrink = true; end

	-- Engineering
	--STATE.itemDataCallbacks[cSkillLine(202)] = doProfessionWindow;

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
		itemProtoFromId(id);
		--maybeEquip(o.guid);
	end)
	investigateBank(function(o)
		itemProtoFromObject(o);
	end)
	investigateBags(function(o)
		itemProtoFromObject(o);
	end)
	investigateBankBags(function(o)
		itemProtoFromObject(o);
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

	-- make sure to get protos for all new items.
	itemProtoFromId(p.itemId);

	-- if it wasn't us who got the item, we don't care.
	if(p.playerGuid ~= STATE.myGuid) then
		--print("got SMSG_ITEM_PUSH_RESULT for another player.");
		return;
	end

	-- if the item stacks, it's not equipment.
	if(p.itemSlot == 0xFFFFFFFF) then
		--print("itemSlot -1.");
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
		--print("In bag!");
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
	if(not itemGuid) then
		print("WARN: maybeEquip(nil)");
		return false;
	end
	if(not STATE.knownObjects[itemGuid]) then
		print("WARN: maybeEquip(unknown["..itemGuid:hex().."])");
		return false;
	end
	local id = itemIdOfGuid(itemGuid);
	if(not itemProtoFromId(id)) then
		STATE.itemDataCallbacks[itemGuid] = maybeEquip;
		return;
	end
	local slot = wantToWear(id, itemGuid, verbose);
	if(slot) then
		equip(itemGuid, id, slot);
	end
end

function forceEquip(itemGuid)
	local id = itemIdOfGuid(itemGuid);
	local proto = itemProtoFromId(id);
	local slot = itemEquipSlot(proto);
	if(type(slot) == 'table') then
		slot = slot[1];
	end
	equip(itemGuid, id, slot);
end

-- slot is one of the EQUIPMENT_SLOT constants.
function equip(itemGuid, itemId, slot)
	local proto = itemProtoFromId(itemId);
	local msg = "Equipping "..itemId.." "..itemGuid:hex().." "..proto.name;
	print(msg);
	partyChat(msg);

	send(CMSG_AUTOEQUIP_ITEM_SLOT, {itemGuid=itemGuid, dstSlot=slot});
end

function baseInvestigateBags(bagField1, bagFieldLast, bagSlotStart, f, emptySlotFunction)
	for i = bagField1, bagFieldLast, 2 do
		local bagGuid = guidFromValues(STATE.me, i);
		local bagSlot = bagSlotStart + ((i - bagField1) / 2);
		if(bagSlot >= 100) then
			print("bagSlot("..i..", "..bagField1..") = "..bagSlot..", "..((i - bagField1) / 2));
		end
		assert(bagSlot < 100);
		if(isValidGuid(bagGuid)) then
			local bag = STATE.knownObjects[bagGuid];
			if(bag) then
				local slotCount = bag.values[CONTAINER_FIELD_NUM_SLOTS];
				if(slotCount) then
					local res = f(bag, bagSlot, slotCount);
					if(res == false) then return; end
				end
			end
		elseif(emptySlotFunction) then
			emptySlotFunction(bagSlot);
		end
	end
end

local function investigateSlots(directField1, directFieldLast,
	bagSlot, directItemSlotStart, f, emptySlotFunction)
	local freeSlotCount = 0;
	for i = directField1, directFieldLast, 2 do
		local guid = guidFromValues(STATE.me, i);
		local slot = directItemSlotStart + ((i - directField1) / 2);
		if(isValidGuid(guid)) then
			local o = STATE.knownObjects[guid];
			if(o) then
				local res = f(o, bagSlot, slot);
				if(res == false) then return false; end
			end
		else
			if(emptySlotFunction) then
				emptySlotFunction(bagSlot, slot);
			end
			freeSlotCount = freeSlotCount + 1;
		end
	end
	return freeSlotCount;
end

local function baseInvestigate(directField1, directFieldLast,
	directBagSlot, directItemSlotStart,
	bagField1, bagFieldLast, bagSlotStart, f, emptySlotFunction)
	local freeSlotCount = 0;
	-- backpack
	freeSlotCount = investigateSlots(directField1, directFieldLast,
		directBagSlot, directItemSlotStart, f, emptySlotFunction);
	if(not freeSlotCount) then return; end
	-- bags
	baseInvestigateBags(bagField1, bagFieldLast, bagSlotStart, function(bag, bagSlot, slotCount)
		--print(slotCount);
		for j = 0, (slotCount-1), 1 do
			local guid = guidFromValues(bag, CONTAINER_FIELD_SLOT_1 + (j*2))
			local slot = j;
			if(isValidGuid(guid)) then
				local o = STATE.knownObjects[guid];
				if(o) then
					local res = f(o, bagSlot, slot);
					if(res == false) then return false; end
				end
			else
				if(emptySlotFunction) then
					emptySlotFunction(bagSlot, slot);
				end
				freeSlotCount = freeSlotCount + 1;
			end
		end
	end)
	return freeSlotCount;
end

function countFreeSlots()
	return investigateInventory(function()end)
end

function countFreeBankSlots()
	return investigateBank(function()end)
end

-- f(o, bagSlot, slot)
-- emptySlotFunction(bagSlot, slot)
function investigateEquipment(f, emptySlotFunction)
	return investigateSlots(PLAYER_FIELD_INV_SLOT_HEAD, PLAYER_FIELD_BAG_SLOT_1-2,
		INVENTORY_SLOT_BAG_0, EQUIPMENT_SLOT_START, f, emptySlotFunction)
end

function investigateInventory(f, emptySlotFunction)
	return baseInvestigate(PLAYER_FIELD_PACK_SLOT_1, PLAYER_FIELD_PACK_SLOT_LAST,
		INVENTORY_SLOT_BAG_0, INVENTORY_SLOT_ITEM_START,
		PLAYER_FIELD_BAG_SLOT_1, PLAYER_FIELD_BAG_SLOT_LAST,
		INVENTORY_SLOT_BAG_START, f, emptySlotFunction)
end

function investigateBank(f, emptySlotFunction)
	return baseInvestigate(PLAYER_FIELD_BANK_SLOT_1, PLAYER_FIELD_BANK_SLOT_LAST,
		INVENTORY_SLOT_BAG_0, BANK_SLOT_ITEM_START,
		PLAYER_FIELD_BANKBAG_SLOT_1, PLAYER_FIELD_BANKBAG_SLOT_LAST,
		BANK_SLOT_BAG_START, f, emptySlotFunction)
end

function investigateBags(f, emptySlotFunction)
	baseInvestigateBags(PLAYER_FIELD_BAG_SLOT_1, PLAYER_FIELD_BAG_SLOT_LAST,
		INVENTORY_SLOT_BAG_START, f, emptySlotFunction)
end

function investigateBankBags(f, emptySlotFunction)
	baseInvestigateBags(PLAYER_FIELD_BANKBAG_SLOT_1, PLAYER_FIELD_BANKBAG_SLOT_LAST,
		BANK_SLOT_BAG_START, f, emptySlotFunction)
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
	local proto = itemProtoFromObject(o);
	local link = "|cff"..itemColors[proto.Quality].."|H"..itemString(o).."|h["..proto.name.."]|h|r";
	return link;
end

function itemLinkFromId(id)
	--|cffffffff|Hitem:2886:0:0:0|h[Crag Boar Rib]|h|r
	local proto = itemProtoFromId(id);
	local link = "|cff"..itemColors[proto.Quality].."|Hitem:"..id..":0:0:0|h["..proto.name.."]|h|r";
	return link;
end

function itemLinkFromTrade(proto, i)
	return "|cff"..itemColors[proto.Quality].."|Hitem:"..proto.itemId..
		":"..i.enchantment..":"..i.randomPropertyId..":0|h["..proto.name.."]|h|r";
end

function isFishingPole(o)
	local proto = itemProtoFromObject(o);
	return (proto.itemClass == ITEM_CLASS_WEAPON and
		proto.subClass == ITEM_SUBCLASS_WEAPON_FISHING_POLE);
end

function itemLockSkillEntry(o)
	local proto = itemProtoFromObject(o);
	if(not proto) then return nil; end
	if(proto.LockID == 0) then return nil; end
	return lockSkillEntry(proto.LockID);
end

function haveSkillToOpenItem(o)
	return haveSkillToOpenLockSkillEntry(itemLockSkillEntry(o));
end
