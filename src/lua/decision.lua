
-- implementation of the decision tree from notes.txt
function decision(realTime)
	realTime = realTime or getRealTime();
	-- if we're currently casting a spell, don't try anything else until it's complete.
	if(STATE.casting) then
		setAction("casting...");
		if(STATE.casting > realTime + 3) then
			print("casting overdue "..(realTime - STATE.casting));
		end
		return;
	end

	updateEnemyPositions(realTime);
	updateMyPosition(realTime);
	updateLeaderPosition(realTime);

	local myPos = STATE.myLocation.position;

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

	-- if we can buff anyone, do that.
	if(doBuff(realTime)) then
		setAction("buffing...");
		return;
	end

	-- if we're the tank and an enemy targets another party member, taunt them.
	if(STATE.amTank and doTanking(realTime)) then
		setAction("tanking...");
		return;
	end

	-- if an enemy targets a party member, attack that enemy.
	-- if there are several enemies, pick any one.
	local i, enemy = next(STATE.enemies);
	if(enemy and not STATE.stealthed) then
		-- focus on leader's target, if any.
		local lt = STATE.enemies[leaderTarget()];
		if(lt) then enemy = lt; end

		setAction("Attacking "..enemy.guid:hex());
		attack(realTime, enemy);
		return;
	end
	STATE.meleeing = false;

	-- continue repeated spell casting.
	if(STATE.repeatSpellCast.count > 0) then
		local s = STATE.knownSpells[STATE.repeatSpellCast.id];
		if(spellIsOnCooldown(realTime, s)) then return; end
		STATE.repeatSpellCast.count = STATE.repeatSpellCast.count - 1;
		setAction("Casting "..s.name..", "..STATE.repeatSpellCast.count.." remain");
		castSpellWithoutTarget(STATE.repeatSpellCast.id);
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

	-- STATE.pickpocketables is filled only if you have
	-- STATE.stealthSpell and STATE.pickpocketSpell.
	local i, p = next(STATE.pickpocketables);
	if(p) then
		setAction("Pickpocketing "..p.guid:hex());
		pickpocket(p);
		return;
	elseif(STATE.stealthed) then
		partyChat("Canceling stealth...");
		send(CMSG_CANCEL_AURA, {spellId=STATE.stealthSpell.id});
		STATE.stealthed = false;
	end

	-- if there are units that can be looted, go get them.
	local minDist = PERMASTATE.gatherRadius;
	local lootable;
	for guid, o in pairs(STATE.lootables) do
		local dist = distance3(myPos, o.location.position);
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
		setAction("Finishing quests at "..finisher.guid:hex());
		finishQuests(finisher);
		return;
	end
	local i, giver = next(STATE.questGivers);
	if(giver and PERMASTATE.autoQuestGet) then
		setAction("Getting quests at "..giver.guid:hex());
		getQuests(giver);
		return;
	end

	-- visit our class trainer at even levels.
	local i, trainer = next(STATE.classTrainers);
	if(trainer and (bit32.band(STATE.myLevel, bit32.bnot(1)) >
		PERMASTATE.classTrainingCompleteForLevel))
	then
		setAction("training...");
		goTrain(trainer);
		return;
	end

	-- gather nearby ore and herbs.
	local minDist = PERMASTATE.gatherRadius;
	local openable;
	for guid, o in pairs(STATE.openables) do
		local dist = distance3(myPos, o.location.position);
		if((dist < minDist) and haveSkillToOpen(o)) then
			minDist = dist;
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

	if(STATE.fishing) then
		setAction("fishing...");
		doFish(realTime);
		return;
	end

	-- if we're near a focus and we have reagents, then cast a spell.
	local minDist = PERMASTATE.gatherRadius;
	local focusObject;
	local focusSpell;
	for guid, o in pairs(STATE.focusObjects) do
		local dist = distance3(myPos, o.location.position);
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

	if(STATE.disenchantItems) then
		local s = STATE.knownSpells[STATE.disenchantSpell];
		if(spellIsOnCooldown(realTime, s)) then return; end
		local found = false;
		investigateInventory(function(o, bagSlot, slot)
			local itemId = o.values[OBJECT_FIELD_ENTRY];
			if(STATE.disenchantItems[itemId] and
				(not PERMASTATE.undisenchantable[itemId]))
			then
				partyChat("Dis: "..o.guid:hex());
				-- if disenchant fails, remember that.
				STATE.currentDisenchant = itemId;
				castSpellAtItem(STATE.disenchantSpell, o);
				found = true
				return false;
			end
		end)
		if(not found) then
			STATE.disenchantItems = false;
		end
	end

	-- don't try following the leader if we don't know where he is.
	if(STATE.inGroup and STATE.leader and STATE.leader.location.position.x) then
		setAction("Following leader");
		follow(STATE.leader);
		--local myValues = STATE.my.values;
		--print("Following. XP: "..tostring(myValues[PLAYER_XP])..
			--" / "..tostring(myValues[PLAYER_NEXT_LEVEL_XP]));
		return;
	end
	setAction("Noting to do...");
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
	local itemCounts = {};
	investigateInventory(function(o)
		local itemId = o.values[OBJECT_FIELD_ENTRY];
		itemCounts[itemId] = (itemCounts[itemId] or 0) + o.values[ITEM_FIELD_STACK_COUNT];
	end)
	local lowSpell;
	local lowValue;
	for id,s in pairs(spells) do
		local haveAllReagents = true;
		for i,r in ipairs(s.reagent) do
			if(r.count > 0 and (itemCounts[r.id] or 0) < r.count) then
				haveAllReagents = false;
			end
		end
		if(haveAllReagents) then
			local val = cSkillLineAbilityBySpell(id).minValue;
			if(val > (lowValue or 0)) then
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
		castSpellWithoutTarget(STATE.fishingSpell);
		return;
	end
end

function pickpocket(target)
	local dist = distanceToObject(target);
	local stealthDist = (MELEE_DIST*2 + aggroRadius(target));
	doMoveToTarget(getRealTime(), target, stealthDist);
	if((dist <= stealthDist) and not STATE.stealthed) then
		if(spellIsOnCooldown(realTime, STATE.stealthSpell)) then return; end
		castSpellAtUnit(STATE.stealthSpell.id, STATE.me);
		--todo: make sure to set this to false on spell fail or aura removed.
		--also: on stealth fail, remove all pickpocketing targets, because we'll be stuck in combat.
		STATE.stealthed = true;
	end
	if(STATE.stealthed) then
		if(doStealthMoveBehindTarget(getRealTime(), target, MELEE_DIST) and
			not target.bot.pickpocketed)
		then
			castSpellAtUnit(STATE.pickpocketSpell.id, target);
			target.bot.pickpocketed = true;
		end
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
	setAction("Training at "..trainer.guid:hex());
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
		end
	end
	msg = msg..count.." spells trained."
	partyChat(msg);
	checkTraining(p);
end

function hSMSG_TRAINER_BUY_SUCCEEDED(p)
	assert(STATE.training[p.spellId] == p.guid);
	STATE.training[p.spellId] = nil;
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
	return hasQuestForItem(itemId);
end

function hSMSG_LOOT_RESPONSE(p)
	print("SMSG_LOOT_RESPONSE");
	for i, item in ipairs(p.items) do
		print("item "..item.itemId.." x"..item.count);
		if((p.lootType ~= LOOT_CORPSE) or
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
end

function follow(mo)
	doMoveToTarget(getRealTime(), mo, FOLLOW_DIST);
end
