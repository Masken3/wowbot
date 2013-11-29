
-- implementation of the decision tree from notes.txt
function decision(realTime)
	realTime = realTime or getRealTime();

	if((STATE.freeze or 0) > realTime) then
		print("Frozen for "..(STATE.freeze - realTime).." more seconds.");
		return;
	end

	-- if we're currently casting a spell, don't try anything else until it's complete.
	if(STATE.casting) then
		if(STATE.casting > realTime + 3) then
			print("casting overdue "..(realTime - STATE.casting));
			STATE.casting = false;
		else
			--print("casting.");
			return;
		end
	end

	if(STATE.looting) then return; end

	local COMBAT_RECORD_MAX = 5;
	local c = STATE.currentCombatRecord;
	if(next(STATE.enemies)) then	-- if we're in combat
		if(not STATE.inCombat) then	-- and we weren't before
			-- set up record-keeping.
			STATE.inCombat = true;
			c.startTime = realTime;
			c.sumEnemyHealth = 0;
			c.enemies = {};
			for guid,o in pairs(STATE.enemies) do
				c.enemies[guid] = o.values[UNIT_FIELD_HEALTH];
				c.sumEnemyHealth = c.sumEnemyHealth + o.values[UNIT_FIELD_HEALTH];
			end
		else	-- if we were
			-- add any new enemies to the record.
			for guid,o in pairs(STATE.enemies) do
				if(not c.enemies[guid]) then
					c.enemies[guid] = o.values[UNIT_FIELD_HEALTH];
					c.sumEnemyHealth = c.sumEnemyHealth + o.values[UNIT_FIELD_HEALTH];
				end
			end
		end
	elseif(STATE.inCombat) then	-- if we just left combat
		STATE.inCombat = false;
		-- finalize the record of this combat.
		local record = {
			duration = realTime - c.startTime,
			sumEnemyHealth = c.sumEnemyHealth,
			dps = c.sumEnemyHealth / (realTime - c.startTime),
		};
		print("Combat finished:", dump(record));
		STATE.combatRecords[STATE.nextCombatRecordId] = record;
		STATE.nextCombatRecordId = STATE.nextCombatRecordId + 1;
		if(STATE.nextCombatRecordId > COMBAT_RECORD_MAX) then
			STATE.nextCombatRecordId = 1;
		end
		-- and update average group dps.
		local total = 0;
		local count = 0;
		for i,r in ipairs(STATE.combatRecords) do
			total = total + r.dps;
			count = count + 1;
		end
		STATE.averageGroupDps = (total / count);
	end

	updateEnemyPositions(realTime);
	updateMyPosition(realTime);
	updateLeaderPosition(realTime);

	-- update stealth state.
	if(STATE.stealthSpell) then
		STATE.stealthed = hasAura(STATE.me, STATE.stealthSpell.id);
	end

	local leaderPos = STATE.leader and STATE.leader.location.position;
	if(not leaderPos) then
		print("not leaderPos");
		return;
	end

	--print("decision...");
	-- if we're already attacking someone, keep at it.
	-- todo: handle multiple enemies here.
	if(false) then--STATE.meleeing) then
		if(keepAttacking()) then
			print("keep meleeing.");
			return;
		end
	end

	-- if there are units that can be skinned, go get them.
	-- todo: if we're healer or tank, skinning should get lower prio.
	local i, skinnable = next(STATE.skinnables);
	if(skinnable) then
		setAction("Skinning "..skinnable.guid:hex());
		goSkin(skinnable);
		return;
	end

	STATE.skinning = false;

	-- if anyone needs healing, do that.
	if(doHeal(realTime)) then
		setAction("healing...");
		return;
	end

	-- if there's an appropriate confusion target, hit it.
	--
	if(doCrowdControl(realTime)) then
		setAction("CrowdControl...");
		return;
	end
	--]]

	-- if we can interrupt an enemy spell, do so.
	if(doInterrupt(realTime)) then
		setAction("doInterrupt");
		return;
	end

	-- if we're the tank and an enemy targets another party member, taunt them.
	if(STATE.amTank and doTanking(realTime)) then
		setAction("tanking...");
		return;
	end

	if(doDispel(realTime)) then
		setAction("dispelling...");
		return;
	end

	-- attack an enemy.
	local enemy = chooseEnemy();
	if(enemy) then
		setAction("Attacking "..enemy.guid:hex());
		attack(realTime, enemy);
		return;
	end
	STATE.meleeing = false;

	-- if we can buff anyone, do that.
	if(doBuff(realTime)) then
		setAction("buffing...");
		return;
	end

	-- if hostiles are near, apply temporary enchantments, if we have any.
	if(doApplyTempEnchant(realTime)) then
		setAction("doApplyTempEnchant...");
		return;
	end

	-- continue repeated spell casting.
	if(STATE.repeatSpellCast.count > 0) then
		if(STATE.waitingForEnchantResponse) then return; end
		local s = STATE.knownSpells[STATE.repeatSpellCast.id];
		if(spellIsOnCooldown(realTime, s)) then return; end
		setAction("Casting "..s.name..", "..STATE.repeatSpellCast.count.." remain");
		STATE.repeatSpellCast.count = STATE.repeatSpellCast.count - 1;
		if(s.Targets == TARGET_FLAG_ITEM) then
			local protoTest = spellCanTargetItemProtoTest(s);
			-- first, check the trade window's last slot.
			--print(STATE.tradeStatus, dump(STATE.extendedTradeStatus));
			if(STATE.tradeStatus == TRADE_STATUS_BACK_TO_TRADE and STATE.extendedTradeStatus) then
				local item = STATE.extendedTradeStatus.items[TRADE_SLOT_NONTRADED];
				local itemId = item.itemId;
				if(itemId ~= 0) then
					local proto = itemProtoFromId(itemId);
					if(protoTest(proto)) then
						objectNameQuery(STATE.tradingPartner, function(name)
							partyChat(name.." "..itemLinkFromTrade(proto, item).." "..s.name);
						end)
						castSpellAtTradeSlot(s.id, TRADE_SLOT_NONTRADED);
					end
				end
				-- if the trade window is open at all, don't check own inventory;
				-- likely that trader wants an enchantment,
				-- and we don't want to waste reagents.
				return;
			end

			-- ask party member bots, if any.
			local e = s.effect[1];
			if(e.id == SPELL_EFFECT_ENCHANT_ITEM and offerEnchantToBots(s)) then
				return;
			end

			doLocalEnchant(protoTest, s);
		else
			castSpellWithoutTarget(STATE.repeatSpellCast.id);
		end
		--print("trade?");
		return;
	end

	-- sell items.
	local itemToSell, dummy = next(STATE.itemsToSell);
	local i, vendor = next(STATE.vendors);
	if(itemToSell and vendor) then
		setAction("Selling ...");
		goSell(itemToSell);
		return;
	end

	-- if there are units that can be looted, go get them.
	local minDist = PERMASTATE.gatherRadius;
	local lootable;
	for guid, o in pairs(STATE.lootables) do
		local dist = distance3(leaderPos, o.location.position);
		if((dist < minDist)) then
			minDist = dist;
			lootable = o;
		end
	end
	--if(false) then
	if(lootable) then
		setAction("Looting "..lootable.guid:hex());
		goLoot(lootable);
		return;
	end

	-- if we have quest finishers or givers, go to them.
	local i, finisher = next(STATE.questFinishers);
	if(finisher) then
		finisher = getClosest(finisher, STATE.questFinishers);
		if(finishQuests(finisher)) then
			setAction("Finishing quests at "..finisher.guid:hex());
			return;
		end
	end
	local i, giver = next(STATE.questGivers);
	if(giver and PERMASTATE.autoQuestGet) then
		giver = getClosest(giver, STATE.questGivers);
		if(getQuests(giver)) then
			setAction("Getting quests at "..giver.guid:hex());
			return;
		end
	end

	-- visit our class trainer at even levels.
	local i, trainer = next(STATE.classTrainers);
	if(trainer and (bit32.band(STATE.myLevel, bit32.bnot(1)) >
		PERMASTATE.classTrainingCompleteForLevel) and
		not STATE.hostiles[trainer.guid])
	then
		goTrain(trainer);
		return;
	end

	-- gather nearby ore and herbs.
	local minDist = PERMASTATE.gatherRadius;
	local openable;
	for guid, o in pairs(STATE.openables) do
		local distFromLeader = distance3(leaderPos, o.location.position);
		local distFromMe = distance3(STATE.my.location.position, o.location.position);
		if((distFromLeader < PERMASTATE.gatherRadius) and
			(distFromMe < minDist) and haveSkillToOpenGO(o))
		then
			minDist = distFromMe;
			openable = o;
		end
	end
	if(openable) then
		gameObjectInfo(openable, function(o, info)
			setAction("Gathering "..info.name);
		end);
		goOpen(realTime, openable);
		return;
	end

	-- Pick Pocket
	if(doPickpocket(realTime)) then
		return;
	end

	-- Fishing
	if(STATE.fishing) then
		doFish(realTime);
		return;
	end

	-- if we're near a focus and we have reagents, then cast a spell.
	local minDist = PERMASTATE.gatherRadius;
	local focusObject;
	local focusSpell;
	for guid, o in pairs(STATE.focusObjects) do
		local dist = distance3(leaderPos, o.location.position);
		local spell = haveReagentsFor(o);
		if((dist < minDist) and spell) then
			minDist = dist;
			focusObject = o;
			focusSpell = spell;
		end
	end
	if(focusObject) then
		setAction(focusSpell.name.." @ "..focusObject.guid:hex());
		goFocusObject(realTime, focusObject, focusSpell);
		return;
	end

	-- Disenchant
	if(STATE.disenchantItems and not STATE.tempSkipDisenchant) then
		local s = STATE.knownSpells[STATE.disenchantSpell];
		if(spellIsOnCooldown(realTime, s)) then return; end
		local found = false;
		investigateInventory(function(o, bagSlot, slot)
			local itemId = o.values[OBJECT_FIELD_ENTRY];
			if(STATE.disenchantItems[itemId] and
				(STATE.currentDisenchant ~= o) and
				(not PERMASTATE.undisenchantable[itemId]))
			then
				assert(not found);
				partyChat("Dis: "..itemLink(o));
				-- if disenchant fails, remember that.
				STATE.currentDisenchant = o;
				moveStop();
				castSpellAtItem(STATE.disenchantSpell, o);
				found = true
				return false;
			end
		end)
		if(found) then
			return;
		else
			STATE.disenchantItems = false;
		end
	end
	STATE.tempSkipDisenchant = false;

	-- equip better bags
	if(doBags()) then
		return;
	end

	-- move profession items into profession bags.
	if(moveProfessionItems()) then
		return;
	end

	-- if we can pick locks and have locks to pick, do so.
	if(doPickLockOnItem(realTime)) then
		return;
	end

	if(doDrink(realTime)) then
		return;
	end

	-- don't try following the leader if we don't know where he is.
	if(STATE.inGroup and STATE.leader and STATE.leader.location.position.x and
		STATE.leader.location.mapId == STATE.myLocation.mapId)
	then
		if(STATE.currentAction ~= "Following leader") then
			print("Cancel cast...");
			-- ought to cancel any spell currently being cast.
			send(CMSG_CANCEL_CAST, {spellId=0});
		end
		setAction("Following leader");
		follow(realTime, STATE.leader);
		--local myValues = STATE.my.values;
		--print("Following. XP: "..tostring(myValues[PLAYER_XP])..
			--" / "..tostring(myValues[PLAYER_NEXT_LEVEL_XP]));
		return;
	end

	setAction("Noting to do...");
end


function offerEnchantToBots(s)
	local count = 0;
	print("offerEnchantToBots");
	for i,m in ipairs(STATE.groupMembers) do
		local o = STATE.knownObjects[m.guid];
		if(o and o.bot.isBot) then
			whisper(o, "offerEnchant "..s.id);
			count = count + 1;
		end
	end
	print("offerEnchantToBots "..count);
	if(count > 0) then
		STATE.waitingForEnchantResponse = count;
		STATE.enchantResponseCount = 0;
		STATE.enchantResponses = {};
		return true;
	end
	return false;
end

-- runs on the receiver bot.
function handleOfferEnchant(p, spellId)
	-- calculate remote spell's value.
	local s = cSpell(spellId);
	local protoTest = spellCanTargetItemProtoTest(s);
	local remoteEnchId = s.effect[1].miscValue;
	print("Enchantment offered. spell="..spellId);

	-- investigateEquipment, search for matching items and compare
	-- the remote value with whatever local value we have.
	local highestDiff;
	investigateEquipment(function(o, bagSlot, slot)
		local proto = itemProtoFromObject(o);
		if(protoTest(proto)) then
			local localEnchId = o.values[ITEM_FIELD_ENCHANTMENT + PERM_ENCHANTMENT_SLOT*3 + ENCHANTMENT_ID_OFFSET];
			local localValue = 0;
			if(localEnchId and localEnchId ~= 0) then
				localValue = enchValue(localEnchId, proto, nil, true);
			end
			local remoteValue = enchValue(remoteEnchId, proto, nil, true);
			print("Item match found. r "..remoteValue.." vs l "..localValue);
			local diff = remoteValue - localValue;
			if((not highestDiff) or (diff > highestDiff)) then
				highestDiff = diff;
				STATE.enchantTradeItem = {tradeSlot = TRADE_SLOT_NONTRADED, bag = bagSlot, slot = slot};
			end
		end
	end);

	reply(p, "enchantValue "..tostring(highestDiff));
end

-- runs on the enchanter bot.
function handleEnchantValue(p, enchantValue)
	STATE.enchantResponses[p] = enchantValue;
	STATE.enchantResponseCount = STATE.enchantResponseCount + 1;
	if(STATE.enchantResponseCount == STATE.waitingForEnchantResponse) then
		-- choose which one will get the enchant and open a trade window.
		-- once it has an item in the slot, clear waitingForEnchantResponse,
		-- up repeatSpellCast.count and call decision(),
		-- which should cause the spell to be cast.
		-- values may be less than zero, in which case they already have a better enchant.
		local targetGuid;
		local value = 0;
		for p,v in pairs(STATE.enchantResponses) do
			if(v > value) then
				targetGuid = p.senderGuid
				value = v;
			end
		end
		-- if no one wanted it, do it on our own equipment.
		if(not targetGuid) then
			STATE.waitingForEnchantResponse = false;
			local s = STATE.knownSpells[STATE.repeatSpellCast.id];
			doLocalEnchant(spellCanTargetItemProtoTest(s), s);
			return;
		end
		local target = STATE.knownObjects[targetGuid];
		if(targetGuid and not target) then
			partyChat("ERROR: enchantResponse from unknown object "..targetGuid:hex());
			return;
		end
		initiateTrade(targetGuid);
	end
end

function doLocalEnchant(protoTest, s)
	local itemTarget;
	local f = function(o)
		local proto = itemProtoFromObject(o);
		if protoTest(proto) then
			itemTarget = o;
			return false;
		end
	end
	investigateEquipment(f)
	if(not itemTarget) then
		investigateInventory(f)
	end
	if(not itemTarget) then
		partyChat("No appropriate target for "..s.name);
		return;
	end
	castSpellAtItem(s.id, itemTarget);
end


function isAlive(o)
	return ((o.values[UNIT_FIELD_HEALTH] or 0) > 0);
end

local function hostilesAreNear()
	for guid, o in pairs(STATE.hostiles) do
		local dist = distance3(STATE.my.location.position, o.location.position);
		if((dist < 40) and isAlive(o)) then return true; end
	end
	return false;
end

function spellCanTargetItemProtoTest(s)
	assert(s.Targets == TARGET_FLAG_ITEM);
	local mask = s.EquippedItemInventoryTypeMask;
	if(mask == 0) then
		local class = s.EquippedItemClass;
		mask = s.EquippedItemSubClassMask;
		return function(proto)
			return (class == proto.itemClass and bit32.btest(mask, (2 ^ proto.subClass)));
		end
	else
		return function(proto)
			--print(string.format("test 0x%x, 0x%x (%i), %s",
				--mask, (2 ^ proto.InventoryType), proto.InventoryType, proto.name));
			return (bit32.btest(mask, (2 ^ proto.InventoryType)));
		end
	end
end

local function tempEnchantSpellOnItem(o)
	return spellOnItem(o, SPELL_EFFECT_ENCHANT_ITEM_TEMPORARY)
end

function spellOnItem(o, effectId)
	local proto = itemProtoFromObject(o);
	if(not proto) then return nil; end
	for i,is in ipairs(proto.spells) do
		if(is.trigger == ITEM_SPELLTRIGGER_ON_USE and is.id ~= 0) then
			local s = cSpell(is.id);
			if(s.effect[1].id == effectId) then
				return s;
			end
		end
	end
	return nil;
end

-- use item in slot on item b.
function useItemOnItem(realTime, bagSlot, slot, b)
	moveStop();
	STATE.casting = realTime;
	send(CMSG_USE_ITEM, {bag = bagSlot, slot = slot, spellCount = 0,
		targetFlags = TARGET_FLAG_ITEM, itemTarget = b.guid});
end

function hasTempEnchant(o)
	return (o.values[ITEM_FIELD_ENCHANTMENT + TEMP_ENCHANTMENT_SLOT*3] or 0) ~= 0;
end

function useItemOnEquipment(realTime, o, bagSlot, slot, s)
	local protoTest = spellCanTargetItemProtoTest(s);
	local didSomething = false;
	investigateEquipment(function(e)
		local proto = itemProtoFromObject(e);
		if(proto and protoTest(proto) and (not hasTempEnchant(e))) then
			useItemOnItem(realTime, bagSlot, slot, e);
			didSomething = true;
			return false;
		end
	end);
	return didSomething;
end

-- if hostiles are near, apply temporary enchantments, if we have any.
function doApplyTempEnchant(realTime)
	if(not hostilesAreNear()) then return false; end
	-- scan our inventory for enchanter items.
	local didSomething = false;
	investigateInventory(function(o, bagSlot, slot)
		-- if one is found, see if we have any equipment it'd be usable and useful on.
		local s = tempEnchantSpellOnItem(o);
		if(s and (not spellIsOnCooldown(realTime, s))) then
			didSomething = useItemOnEquipment(realTime, o, bagSlot, slot, s);
			return false;
		end
	end);
	return didSomething;
end

-- returns the regen points of the drink, or nil.
local function isDrinkSpell(s, level)
	-- these attributes are observed on every drink spell.
	if(bit32.band(s.Attributes, 0x18000100) ~= 0x18000100) then return nil; end
	for i,e in ipairs(s.effect) do
		if(e.id == SPELL_EFFECT_APPLY_AURA and
			e.applyAuraName == SPELL_AURA_MOD_POWER_REGEN and
			e.implicitTargetA == TARGET_SELF)
		then
			return calcAvgEffectPoints(level, e);
		end
	end
	return nil;
end

-- returns the regen points of the drink, or nil.
function isDrinkItem(itemId)
	local s;
	local points = nil;
	local proto = itemProtoFromId(itemId);
	if(not proto) then return false; end
	for i,is in ipairs(proto.spells) do
		if(is.trigger == ITEM_SPELLTRIGGER_ON_USE and is.id ~= 0) then
			s = cSpell(is.id);
			local level = spellLevel(s);
			points = isDrinkSpell(s, level) or points;
		end
	end
	return points, s;
end

-- returns item KnownObject, id or false.
function findDrinkItem()
	local item = false;
	local id;
	investigateInventory(function(o)
		id = o.values[OBJECT_FIELD_ENTRY];
		if(isDrinkItem(id)) then
			item = o;
			return false;
		end
	end);
	return item, id;
end

function amDrinking()
	local points = nil;
	investigateAuras(STATE.me, function(s, level)
		points = isDrinkSpell(s, level) or points;
	end);
	return points;
end

local function findPartyMage()
	for i,m in ipairs(STATE.groupMembers) do
		local o = STATE.knownObjects[m.guid];
		if(o and (class(o) == CLASS_MAGE)) then return o; end
	end
	return nil;
end

-- make drink if we don't have any.
-- ask mage for drink if we can't make any.
-- drink up if we're low on mana.
function doDrink(realTime)
	if(not getClassInfo(STATE.me).drink) then return false; end
	if(not STATE.readyToDrink) then return false; end

	local drinkItem, id = findDrinkItem();
	--print("doDrink()");
	if(not drinkItem) then
		--print("doDrink not");
		if(STATE.conjureDrinkSpell) then
			if(spellIsOnCooldown(realTime, STATE.conjureDrinkSpell)) then return false; end
			castSpellWithoutTarget(STATE.conjureDrinkSpell.id);
			return true;
		elseif(not STATE.waitingForDrink) then
			local partyMage = findPartyMage();
			if(partyMage) then
				whisper(partyMage, 'give drink');
				STATE.waitingForDrink = true;
				return true;
			end
		end
		return false;
	end
	local id = drinkItem.values[OBJECT_FIELD_ENTRY];
	--print("doDrink id "..id);
	local guid,dummy = next(STATE.drinkRecipients);
	if(guid) then
		objectNameQuery(STATE.knownObjects[guid], function(recName)
			objectNameQuery(drinkItem, function(drinkName)
				print("giveDrink "..drinkName.." to "..recName);
			end);
		end);
		giveDrinkTo(id, guid);
		return true;
	end
	if(amDrinking()) then
		--print("amDrinking");
		return true;
	end
	if((manaFraction(STATE.me) < 0.25) and
		true)
		--((STATE.lastDrinkTime + 30) < realTime))
	then
		STATE.lastDrinkTime = realTime;
		setAction("Drinking "..itemLink(drinkItem), true);
		return gUseItem(id);
	end
	--print("doneDrink()");
	return false;
end

function doPickLockOnItem(realTime)
	if(STATE.stealthed) then return false; end
	if(hostilesAreNear()) then return false; end
	local s = STATE.openLockSpells[LOCKTYPE_PICKLOCK];
	if(not s or spellIsOnCooldown(realTime, s)) then return false; end
	local done = false;
	investigateInventory(function(o)
		if(haveSkillToOpenItem(o)) then
			partyChat("Unlocking "..itemLink(o).."...");
			moveStop();
			castSpellAtItem(s.id, o);
			done = true;
			return false;
		end
	end);
	return done;
end

local function baseDoBags(bif, iif, minBagCount)
	--print("baseDoBags "..tostring(minBagCount));
	if(not STATE.doBags) then
		--print("STATE.doBags: "..tostring(STATE.doBags));
		return false;
	end
	-- equip bigger bags.
	-- find the smallest equipped bag, if we have 4 equipped already.
	-- then look for bigger unequipped bags. if we find one,
	-- move all items out of the smaller bag (give error if impossible),
	-- and replace it.
	-- TODO: do the same for bank bags.
	local smallestBag = nil;
	local bagCount = 0;
	local genericBags = {};	-- bagSlot:bag
	bif(function(bag, bagSlot, slotCount)
		bagCount = bagCount + 1;
		local proto = itemProtoFromObject(bag);
		if(not proto) then return false; end
		if((not smallestBag or smallestBag.count > slotCount) and
			(not PERMASTATE.forcedBankBags[proto.itemId]))
		then
			smallestBag = {count=slotCount, o=bag, bagSlot=bagSlot};
		end
		if(proto.subClass == ITEM_SUBCLASS_CONTAINER) then
			genericBags[bagSlot] = bag;
		end
	end);
	if(minBagCount and bagCount < minBagCount) then
		--print("bagCount: "..bagCount.." minBagCount: "..minBagCount);
		return false;
	end
	if(not smallestBag) then
		--print("not smallestBag");
		return false;
	end
	local itemsInSmallestBag = {}	-- o:slot
	local biggestBag = nil;
	local freeSlots = {} -- array:{bagSlot,slot}
	local freeSlotCount = 0;
	local itemsInSmallestBagCount = 0;
	iif(function(o, bagSlot, slot)
		--print("compare "..bagSlot..", "..smallestBag.bagSlot);
		if(bagSlot == smallestBag.bagSlot) then
			itemsInSmallestBagCount = itemsInSmallestBagCount + 1;
			itemsInSmallestBag[o] = slot;
		end
		local proto = itemProtoFromObject(o);
		if(not proto) then
			print("not proto!");
			return false;
		end
		if(PERMASTATE.forcedBankBags[proto.itemId]) then
			print("testing "..proto.name..". iif test: "..tostring(iif == investigateBank));
		end
		if(proto.itemClass == ITEM_CLASS_CONTAINER and
			-- profession bags should only be used in the bank.
			((proto.subClass == ITEM_SUBCLASS_CONTAINER) or
			(iif == investigateBank)))
		then
			local count = o.values[CONTAINER_FIELD_NUM_SLOTS];
			if(PERMASTATE.forcedBankBags[proto.itemId]) then
				print("testing "..proto.name..". iif test: "..tostring(iif == investigateBank));
			end
			if((PERMASTATE.forcedBankBags[proto.itemId] and
				(iif == investigateBank)) or
				((count > smallestBag.count) and
					((not biggestBag) or
					(biggestBag.count < count))))
			then
				print("biggestBag: "..proto.name.." ("..count.." slots)");
				biggestBag = {o=o, bagSlot=bagSlot, slot=slot, count=count};
			end
		end
	end, function(bagSlot, slot)
		if((bagSlot == smallestBag.bagSlot) or (not genericBags[bagSlot])) then
			return;
		end
		freeSlotCount = freeSlotCount + 1
		freeSlots[freeSlotCount] = {bagSlot=bagSlot, slot=slot};
	end);
	if(not biggestBag) then
		--print("not biggestBag");
		return false;
	end
	if(itemsInSmallestBagCount > freeSlotCount) then
		print("ERR: Can't swap bags; not enough free space: "..itemsInSmallestBagCount.." > "..freeSlotCount);
		-- this should encourage user to remedy the problem.
		return true;
	end
	local i = 0;
	for o,slot in pairs(itemsInSmallestBag) do
		i = i + 1;
		send(CMSG_SWAP_ITEM, {dstbag=freeSlots[i].bagSlot, dstslot=freeSlots[i].slot,
			srcbag=smallestBag.bagSlot, srcslot=slot});
		if(biggestBag.bagSlot == smallestBag.bagSlot and biggestBag.slot == slot) then
			biggestBag.bagSlot = freeSlots[i].bagSlot;
			biggestBag.slot = freeSlots[i].slot;
		end
	end
	print("Moved "..i.." items.");
	--print(biggestBag.o.guid:hex()..", "..smallestBag.bagSlot);
	--send(CMSG_AUTOEQUIP_ITEM_SLOT, {itemGuid=biggestBag.o.guid, dstSlot=smallestBag.bagSlot});
	local p = {dstbag=INVENTORY_SLOT_BAG_0, dstslot=smallestBag.bagSlot,
		srcbag=biggestBag.bagSlot, srcslot=biggestBag.slot}
	print("CMSG_SWAP_ITEM ", dump(p))
	send(CMSG_SWAP_ITEM, p)

	-- avoid spam repeats
	STATE.doBags = false;
	STATE.my.updateValuesCallbacks["doBags"] = function()
		STATE.doBags = true;
	end

	partyChat(itemLink(biggestBag.o)..">"..itemLink(smallestBag.o));
	return true;
end

function doBags()
	if(baseDoBags(investigateBags, investigateInventory, 4)) then return true; end
	return baseDoBags(investigateBankBags, investigateBank);
end

local sItemToBagTypeMap = {
	-- we don't need to handle these.
	--[BAG_FAMILY_NONE] = nil,
	--[BAG_FAMILY_KEYS]

	-- requires non-container itemClass.
	--[BAG_FAMILY_ARROWS] = ITEM_SUBCLASS_QUIVER,
	--[BAG_FAMILY_BULLETS] = ITEM_SUBCLASS_AMMO_POUCH,

	[BAG_FAMILY_SOUL_SHARDS] = ITEM_SUBCLASS_SOUL_CONTAINER,
	[BAG_FAMILY_HERBS] = ITEM_SUBCLASS_HERB_CONTAINER,
	[BAG_FAMILY_ENCHANTING_SUPP] = ITEM_SUBCLASS_ENCHANTING_CONTAINER,
	[BAG_FAMILY_ENGINEERING_SUPP] = ITEM_SUBCLASS_ENGINEERING_CONTAINER,

	-- added in patch 2.0.3
	--ITEM_SUBCLASS_GEM_CONTAINER
	--ITEM_SUBCLASS_MINING_CONTAINER
	--ITEM_SUBCLASS_LEATHERWORKING_CONTAINER
};

local function itemCanGoInBag(o, bag)
	local op = itemProtoFromObject(o);
	local bp = itemProtoFromObject(bag);
	assert(bp.itemClass == ITEM_CLASS_CONTAINER);
	assert(bp.subClass ~= ITEM_SUBCLASS_CONTAINER);
	return bp.subClass == sItemToBagTypeMap[o.BagFamily];
end

function moveProfessionItems()
	-- first, find all profession bags.
	local profBags = {};	-- bagSlot:{bag, freeSlots(i:slot)}
	investigateBankBags(function(bag, bagSlot, slotCount)
		local proto = itemProtoFromObject(bag);
		if(not proto) then return false; end
		if(proto.subClass ~= ITEM_SUBCLASS_CONTAINER) then
			profBags[bagSlot] = {bag=bag, freeSlots={}};
		end
	end);
	if(not next(profBags)) then return false; end
	-- then find free slots in the profBags.
	investigateBank(function(o, bagSlot, slot)
	end, function(bagSlot, slot)
		if(profBags[bagSlot]) then
			table.insert(profBags[bagSlot].freeSlots, slot);
		end
	end);
	--if((freeSlotCount == 0) or (not next(itemsThatCanBeMoved)) then return false; end
	-- then, find items that would fit in one of the bags that aren't in one.
	-- and assign them to free slots.
	local swapCount = 0;
	investigateBank(function(o, bagSlot, slot)
		if(not profBags[bagSlot]) then
			for dstBag,pb in pairs(profBags) do
				if((#pb.freeSlots > 0) and itemCanGoInBag(o, pb.bag)) then
					-- use and remove the last free slot.
					send(CMSG_SWAP_ITEM, {dstbag=dstBag, dstslot=pb.freeSlots[#pb.freeSlots],
						srcbag=bagSlot, srcslot=slot});
					table.insert(pb.freeSlots[#pb.freeSlots]);
					swapCount = swapCount + 1;
				end
			end
		end
	end);
	return swapCount > 0;
end

function getItemCounts()
	local itemCounts = {};
	investigateInventory(function(o)
		local itemId = o.values[OBJECT_FIELD_ENTRY];
		itemCounts[itemId] = (itemCounts[itemId] or 0) + o.values[ITEM_FIELD_STACK_COUNT];
	end)
	return itemCounts;
end

-- return the number of times one could cast the spell, given the available reagents.
-- or false.
-- also returns the maximum for one reagent.
function haveReagents(itemCounts, s)
	local haveAllReagents = true;
	local minMulti = 1000;
	local maxMulti = 0;
	for i,r in ipairs(s.reagent) do
		if(r.count > 0) then
			if((itemCounts[r.id] or 0) < r.count) then
				haveAllReagents = false;
			else
				local multi = math.floor(itemCounts[r.id] / r.count);
				if(multi < minMulti) then minMulti = multi; end
				if(multi > maxMulti) then maxMulti = multi; end
			end
		end
	end
	return haveAllReagents and (minMulti ~= 1000) and minMulti, maxMulti;
end

-- returns the id of the spell (with the lowest skillValue) (we have reagents for).
function haveReagentsFor(o)
	local goId = o.values[OBJECT_FIELD_ENTRY];
	local info = STATE.knownGameObjects[goId];
	assert(info);
	local focusId = GOFocusId(info);
	assert(focusId);
	local spells = STATE.focusTypes[focusId];
	assert(spells);
	-- todo: maintain itemCounts, so we don't have to investigateInventory so often.
	local itemCounts = getItemCounts();
	local lowSpell;
	local lowValue = 1000;	-- higher than any skill level.
	for id,s in pairs(spells) do
		local haveAllReagents = haveReagents(itemCounts, s);
		if(haveAllReagents) then
			local val = cSkillLineAbilityBySpell(id).minValue;
			if(val < lowValue) then
				lowValue = val;
				lowSpell = s;
			end
		end
	end
	return lowSpell;
end

function goFocusObject(realTime, o, s)
	if(doMoveToTarget(realTime, o, MELEE_DIST)) then
		if(spellIsOnCooldown(realTime, s)) then return; end
		castSpellWithoutTarget(s.id);
	end
end

function unitTarget(o)
	return guidFromValues(o, UNIT_FIELD_TARGET);
end

function leaderTarget()
	if(not STATE.leader) then return nil; end
	return unitTarget(STATE.leader);
end

function doFish(realTime)
	setAction("Fishing...");
	if(not STATE.fishingBobber) then
		local s = STATE.knownSpells[STATE.fishingSpell];
		if(spellIsOnCooldown(realTime, s)) then return; end
		stopMoveWithOrientation(STATE.fishingOrientation);
		castSpellWithoutTarget(STATE.fishingSpell);
		return;
	end
end

function manaFraction(o)
	return o.values[UNIT_FIELD_POWER1] / o.values[UNIT_FIELD_MAXPOWER1];
end

local function allHealersHaveAtLeastHalfMana()
	if(not STATE.inGroup) then return true; end
	for i,m in ipairs(STATE.groupMembers) do
		local o = STATE.knownObjects[m.guid];
		if((not o) or (o.bot.isHealer and (manaFraction(o) < 0.5))) then return false; end
	end
	return true;
end

function doPickpocket(realTime)
	if(not STATE.stealthSpell) then return false; end
	if(not STATE.pickpocketSpell) then return false; end
	local minDist = PERMASTATE.gatherRadius * 1.5;
	if(not STATE.leader) then return false; end
	if(not allHealersHaveAtLeastHalfMana()) then return false; end
	if((not STATE.stealthed) and (not canCast(STATE.stealthSpell, realTime))) then return false; end
	local leaderPos = STATE.leader.location.position;
	local tar;
	local skipDead = 0;
	local skipFriend = 0;
	local skipDist = 0;
	-- find the closest one.
	for guid, o in pairs(STATE.pickpocketables) do
		-- if the target is dead, disregard it.
		if((o.values[UNIT_FIELD_HEALTH] or 0) == 0) then
			skipDead = skipDead + 1;
			goto continue;
		end
		-- if there are any hostiles within 20 yards of the target, disregard it.
		for hg, ho in pairs(STATE.hostiles) do
			if(ho ~= o and
				(ho.values[UNIT_FIELD_HEALTH] or 0) > 0 and
				distance3(ho.location.position, o.location.position) < 20)
			then
				skipFriend = skipFriend + 1;
				goto continue;
			end
		end

		local dist = distance3(leaderPos, o.location.position);
		if(dist < minDist) then
			minDist = dist;
			tar = o;
		else
			skipDist = skipDist + 1;
		end
		::continue::
	end
	--print("pp: dead "..skipDead..", friend "..skipFriend..", dist "..skipDist);
	if(tar) then
		objectNameQuery(tar, function(name)
			setAction("Pickpocketing "..name, true);
		end)
		pickpocket(realTime, tar);
		return true;
	elseif(STATE.stealthed) then
		-- TODO: de-stealth only when out of all hostiles' aggro radius.
		--[[
		partyChat("Canceling stealth...");
		send(CMSG_CANCEL_AURA, {spellId=STATE.stealthSpell.id});
		STATE.stealthed = false;
		--]]
	end
	return false;
end

-- returns true iff the spell was cast.
function doStealthSpell(realTime, target, spell)
	local dist = distanceToObject(target);
	local stealthDist = (MELEE_DIST*2 + aggroRadius(target));
	doMoveToTarget(realTime, target, stealthDist);
	if((dist <= stealthDist) and not STATE.stealthed) then
		if(spellIsOnCooldown(realTime, STATE.stealthSpell)) then return false; end
		castSpellAtUnit(STATE.stealthSpell.id, STATE.me);
		--todo: make sure to set this to false on spell fail or aura removed.
		--also: on stealth fail, remove all pickpocketing targets, because we'll be stuck in combat.
		STATE.stealthed = true;
	end
	if(STATE.stealthed) then
		if(doStealthMoveBehindTarget(realTime, target, MELEE_DIST)) then
			castSpellAtUnit(spell.id, target);
			STATE.freeze = realTime + 1;
			return true;
		end
	end
	return false;
end

function pickpocket(realTime, target)
	if(doStealthSpell(realTime, target, STATE.pickpocketSpell)) then
		partyChat("Pickpocketed "..target.guid:hex());
		target.bot.pickpocketed = true;
		STATE.pickpocketables[target.guid] = nil;
	end
end

local function closestVendor()
	local dist;
	local vendor;
	for guid,o in pairs(STATE.vendors) do
		local d = distanceToObject(o);
		if((not dist) or (d < dist)) then
			dist = d;
			vendor = o;
		end
	end
	return vendor;
end

function goSell(itemId)
	local vendor = closestVendor();
	local msg = nil
	if(doMoveToTarget(getRealTime(), vendor, MELEE_DIST)) then
		investigateInventory(function(o, bagSlot, slot)
			local itemId = o.values[OBJECT_FIELD_ENTRY];
			if(STATE.itemsToSell[itemId]) then
				local count = o.values[ITEM_FIELD_STACK_COUNT]
				send(CMSG_SELL_ITEM, {vendorGuid=vendor.guid, itemGuid=o.guid,
					count=count});
				msg = msg or ''
				msg = msg.."Sold "..itemProtoFromId(itemId).name.." x"..count.."\n"
			end
		end)
		if(msg) then
			partyChat(msg);
		end
		-- clear the list afterwards, as we may have more than one stack.
		STATE.itemsToSell = {};
	end
end

function goTrain(trainer)
	objectNameQuery(trainer, function(name)
		setAction("Training at "..name);
	end);
	if(doMoveToTarget(getRealTime(), trainer, MELEE_DIST)) then
		if(not trainer.bot.chatting) then
			send(CMSG_TRAINER_LIST, trainer);
			trainer.bot.chatting = true;
		end
	end
end

local function checkTraining(p)
	local trainer = STATE.knownObjects[p.guid];
	local i, spell = next(STATE.training);
	if(not spell) then
		-- we're done.
		print("Training complete.");
		trainer.bot.chatting = false;
		if(STATE.classTrainers[p.guid]) then
			PERMASTATE.classTrainingCompleteForLevel = STATE.myLevel;
			saveState();
		end
	end
end

function hSMSG_TRAINER_LIST(p)
	--print("SMSG_TRAINER_LIST", dump(p));
	local msg = ''
	local count = 0
	for i, s in ipairs(p.spells) do
		if(s.state == TRAINER_SPELL_GREEN) then
			local cs = cSpell(s.spellId);
			msg = msg.."Training spell "..s.spellId.." ("..cs.name..", "..cs.rank..")\n";
			count = count + 1
			STATE.training[s.spellId] = p.guid;
			send(CMSG_TRAINER_BUY_SPELL, {guid=p.guid, spellId=s.spellId});
			break;
		end
	end
	msg = msg..count.." spells trained."
	partyChat(msg);
	checkTraining(p);
end

function hSMSG_TRAINER_BUY_SUCCEEDED(p)
	assert(STATE.training[p.spellId] == p.guid);
	STATE.training[p.spellId] = nil;
	local trainer = STATE.knownObjects[p.guid];
	trainer.bot.chatting = false;
	checkTraining(p);
end

function goOpen(realTime, o)
	if(doMoveToTarget(realTime, o, MELEE_DIST) and (not STATE.looting)) then
		local lockIndex = goLockIndex(o);
		local s = STATE.openLockSpells[lockIndex];
		if(spellIsOnCooldown(realTime, s)) then return; end
		castSpellAtGO(s.id, o);
		STATE.looting = true;
	end
end

function goSkin(o)
	if(doMoveToTarget(getRealTime(), o, MELEE_DIST)) then
		if(not STATE.skinning) then
			castSpellAtUnit(STATE.skinningSpell, o);
			STATE.skinning = true;
		end
	end
end

function goLoot(o)
	if(doMoveToTarget(getRealTime(), o, MELEE_DIST)) then
		if(not STATE.looting) then
			send(CMSG_LOOT, {guid=o.guid});
			STATE.looting = true;
			STATE.looted[o.guid] = true;
		end
	end
end

local function wantToLoot(itemId)
	if(PERMASTATE.shouldLoot[itemId]) then return true; end
	return needsItemForQuest(itemId);
end

function hSMSG_LOOT_RESPONSE(p)
	if(not p._quiet) then
		print("SMSG_LOOT_RESPONSE", dump(p));
	end
	if(p.gold > 0) then
		send(CMSG_LOOT_MONEY)
	end
	for i, item in ipairs(p.items) do
		print("item "..item.itemId.." x"..item.count);
		local proto = itemProtoFromId(item.itemId);
		if(not proto) then
			p._quiet = true;
			STATE.itemDataCallbacks[p] = hSMSG_LOOT_RESPONSE;
			return;
		end
		if((p.lootType ~= LOOT_CORPSE) or
			-- couldn't find a lootType for items, so doing isUnit check.
			(not isUnit(STATE.knownObjects[p.guid])) or
			(item.lootSlotType == LOOT_SLOT_NORMAL) and wantToLoot(item.itemId))
			-- every loot type except corpses are single-user.
			-- in such cases, if we don't loot every item, the unlooted ones would be lost.
		then
			print("Looting item "..item.itemId.." x"..item.count);
			send(CMSG_AUTOSTORE_LOOT_ITEM, item);
		end
	end
	send(CMSG_LOOT_RELEASE, p);
	STATE.looting = false;
	STATE.lootables[p.guid] = nil;
	--STATE.openables[p.guid] = nil;
end

function hSMSG_LOOT_RELEASE_RESPONSE(p)
	--print("Loot release "..p.guid:hex());
	STATE.looting = false;
end

function follow(realTime, mo)
	-- move apart a little bit.
	if((distanceToObject(mo) < FOLLOW_DIST) and doMoveApartFromGroup(realTime)) then return; end
	doMoveToTarget(realTime, mo, FOLLOW_DIST);
end
