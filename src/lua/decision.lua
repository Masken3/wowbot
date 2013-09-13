
-- implementation of the decision tree from notes.txt
function decision(realTime)
	realTime = realTime or getRealTime();
	updateEnemyPositions(realTime);
	updateMyPosition(realTime);
	updateLeaderPosition(realTime);
	--print("decision...");
	-- if we're already attacking someone, keep at it.
	-- todo: handle multiple enemies here.
	if(false) then--STATE.meleeing) then
		if(keepAttacking()) then
			print("keep meleeing.");
			return;
		end
	end
	-- if an enemy targets a party member, attack that enemy.
	-- if there are several enemies, pick any one.
	local i, enemy = next(STATE.enemies);
	if(enemy and not STATE.stealthed) then
		setAction("Attacking "..enemy.guid:hex());
		attack(realTime, enemy);
		return;
	end
	STATE.meleeing = false;

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
	local i, lootable = next(STATE.lootables);
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
	if(giver) then
		setAction("Getting quests at "..giver.guid:hex());
		getQuests(giver);
		return;
	end

	-- visit our class trainer at even levels.
	local i, trainer = next(STATE.trainers);
	if(trainer and (bit32.band(STATE.myLevel, bit32.bnot(1)) >
		PERMASTATE.classTrainingCompleteForLevel))
	then
		setAction("Training at "..trainer.guid:hex());
		goTrain(trainer);
		return;
	end

	-- don't try following the leader if we don't know where he is.
	if(STATE.inGroup and STATE.leader.location.position.x) then
		setAction("Following leader");
		follow(STATE.leader);
		--local myValues = STATE.my.values;
		--print("Following. XP: "..tostring(myValues[PLAYER_XP])..
			--" / "..tostring(myValues[PLAYER_NEXT_LEVEL_XP]));
		return;
	end
	--print("Nothing to do.");
end

function pickpocket(target)
	local dist = distanceToObject(target);
	local stealthDist = (MELEE_DIST*2 + aggroRadius(target));
	doMoveToTarget(getRealTime(), target, stealthDist);
	if((dist <= stealthDist) and not STATE.stealthed) then
		castSpell(STATE.stealthSpell.id, STATE.me);
		--todo: make sure to set this to false on spell fail or aura removed.
		--also: on stealth fail, remove all pickpocketing targets, because we'll be stuck in combat.
		STATE.stealthed = true;
	end
	if(STATE.stealthed) then
		doStealthMoveBehindTarget(getRealTime(), target, MELEE_DIST);
		if(dist <= MELEE_DIST and not target.bot.pickpocketed) then
			--castSpell(STATE.pickpocketSpell.id, target);
			target.bot.pickpocketed = true;
		end
	end
end

function goTrain(trainer)
	local dist = distanceToObject(trainer);
	doMoveToTarget(getRealTime(), trainer, MELEE_DIST);
	if(dist <= MELEE_DIST) then
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
		PERMASTATE.classTrainingCompleteForLevel = STATE.myLevel;
		saveState();
	end
end

function hSMSG_TRAINER_LIST(p)
	print("SMSG_TRAINER_LIST", dump(p));
	for i, s in ipairs(p.spells) do
		if(s.state == TRAINER_SPELL_GREEN) then
			local cs = cSpell(s.spellId);
			local msg = "Training spell "..s.spellId.." ("..cs.name..", "..cs.rank..")...";
			print(msg);
			partyChat(msg);
			STATE.training[s.spellId] = p.guid;
			send(CMSG_TRAINER_BUY_SPELL, {guid=p.guid, spellId=s.spellId});
		end
	end
	checkTraining(p);
end

function hSMSG_TRAINER_BUY_SUCCEEDED(p)
	assert(STATE.training[p.spellId] == p.guid);
	STATE.training[p.spellId] = nil;
	checkTraining(p);
end

function goLoot(o)
	local dist = distanceToObject(o);
	doMoveToTarget(getRealTime(), o, MELEE_DIST);
	if(dist <= MELEE_DIST) then
		if(not STATE.looting) then
			print("Looting "..o.guid:hex());
			send(CMSG_LOOT, {guid=o.guid});
			STATE.looting = true;
			STATE.lootables[o.guid] = nil;
		end
	end
end

local function wantToLoot(itemId)
	return hasQuestForItem(itemId);
end

function hSMSG_LOOT_RESPONSE(p)
	print("SMSG_LOOT_RESPONSE");
	for i, item in ipairs(p.items) do
		print("item "..item.itemId.." x"..item.count);
		if((item.lootSlotType == LOOT_SLOT_NORMAL) and wantToLoot(item.itemId)) or
			-- every loot type except corpses are single-user.
			-- in such cases, if we don't loot every item, the unlooted ones would be lost.
			(p.lootType ~= LOOT_CORPSE)
		then
			print("Looting item "..item.itemId.." x"..item.count);
			send(CMSG_AUTOSTORE_LOOT_ITEM, item);
		end
	end
	send(CMSG_LOOT_RELEASE, p);
	STATE.looting = false;
end

function hSMSG_LOOT_RELEASE_RESPONSE(p)
	print("Loot release "..p.guid:hex());
end

function keepAttacking()
	-- if my target is still an enemy, keep attacking.
	return STATE.enemies[STATE.myTarget] ~= nil;
end

function follow(mo)
	doMoveToTarget(getRealTime(), mo, FOLLOW_DIST);
end

function calcAvgEffectPoints(level, e)
	local dmg = e.basePoints;

	dmg = dmg + e.realPointsPerLevel * level;

	local randomPoints = e.dieSides + level * e.dicePerLevel;
	if(randomPoints <= 1 and randomPoints >= 0) then
		dmg = dmg + e.baseDice;
	else
		dmg = dmg + (e.baseDice + randomPoints) / 2;
	end

	-- todo: combo points
	return dmg;
end

-- in seconds.
local function getDuration(index, level)
	local sd = cSpellDuration(index);
	if(not sd) then return 0; end
	local dur = sd.base + sd.perLevel * level;
	if(dur > sd.max) then dur = sd.max; end
	return dur / 1000;
end

function attack(realTime, enemy)
	local dist = distanceToObject(enemy);
	print("attack, dist", dist);

	-- if we have a good ranged attack, use that.
	-- otherwise, go to melee.

	if(realTime >= STATE.spellCooldown) then
		if(attackSpell(dist, realTime, enemy)) then return; end
	end

	if(dist < MELEE_DIST and not STATE.meleeing) then
		print("start melee");
		setTarget(enemy);
		castSpell(STATE.meleeSpell, enemy);
		send(CMSG_ATTACKSWING, {target=enemy.guid});
		STATE.meleeing = true;
	end
end

function attackSpell(dist, realTime, enemy)
	-- look at all our attack spells and find the best one.
	local maxDpc = 0;
	local maxDamageForFree = 0;
	local bestSpell = nil;
	local myValues = STATE.knownObjects[STATE.myGuid].values;
	--print(dump(myValues));
	for id, s in pairs(STATE.attackSpells) do
		local level = STATE.myLevel;
		--print("myLevel: "..level.." maxLevel: "..s.maxLevel);

		if (level > s.maxLevel and s.maxLevel > 0) then
			level = s.maxLevel;
		elseif (level < s.baseLevel) then
			level = s.baseLevel;
		end
		level = level - s.spellLevel;

		local duration = getDuration(s.DurationIndex, level);

		local cost = s.manaCost + level * s.manaCostPerLevel +
			duration * (s.manaPerSecond + s.manaPerSecondPerLevel * level);

		if(s.ManaCostPercentage ~= 0) then
			if(s.powerType == POWER_HEALTH) then
				cost = cost + s.ManaCostPercentage * myValues[UNIT_FIELD_BASE_HEALTH] / 100;
			elseif(s.powerType == POWER_MANA) then
				cost = cost + s.ManaCostPercentage * myValues[UNIT_FIELD_BASE_MANA] / 100;
			else
				cost = cost + s.ManaCostPercentage * myValues[UNIT_FIELD_MAXPOWER1 + s.powerType] / 100;
			end
		end

		if(s.powerType == POWER_RAGE) then
			cost = cost * 10;
		end

		local powerIndex;
		if(s.powerType == POWER_HEALTH) then
			powerIndex = UNIT_FIELD_HEALTH;
		else
			powerIndex = UNIT_FIELD_POWER1 + s.powerType;
		end
		local availablePower = myValues[powerIndex];

		--print("cost("..s.powerType.."): "..cost.." availablePower("..powerIndex.."): "..tostring(availablePower));
		if(not availablePower) then availablePower = 0; end
		--sanity check.
		assert(availablePower < 100000);
		if(availablePower < cost) then goto continue; end

		local damage = 0;
		for i, e in ipairs(s.effect) do
			if(e.id == SPELL_EFFECT_WEAPON_DAMAGE_NOSCHOOL or
				e.id == SPELL_EFFECT_SCHOOL_DAMAGE or
				e.id == SPELL_EFFECT_NORMALIZED_WEAPON_DMG or
				e.id == SPELL_EFFECT_WEAPON_DAMAGE) then
				damage = damage + calcAvgEffectPoints(level, e);
				-- todo: handle combo-point spells
				-- todo: add normalized weapon damage to such effects
				if(e.pointsPerComboPoint ~= 0) then
					print("ppc: "..e.pointsPerComboPoint);
				end
			end
		end

		if(bit32.btest(s.AttributesEx, SPELL_ATTR_EX_NOT_IN_COMBAT_TARGET) or
			bit32.btest(s.AttributesEx, SPELL_ATTR_EX_REQ_TARGET_COMBO_POINTS)) then
			goto continue;
		end

		print("availablePower("..powerIndex.."): "..tostring(availablePower)..
			" cost("..s.powerType.."): "..cost..
			" damage: "..damage..
			" id: "..id..
			" name: "..s.name.." "..s.rank);
		if(not availablePower) then availablePower = 0; end
		--sanity check.
		assert(availablePower < 100000);
		if(availablePower < cost) then goto continue; end

		if(cost == 0 and damage > maxDamageForFree) then
			maxDamageForFree = damage;
			bestSpell = s;
		elseif(maxDamageForFree == 0) then
			local dpc = damage / cost;
			if(dpc > maxDpc) then
				maxDpc = dpc;
				bestSpell = s;
			end
		end
		::continue::
	end

	-- calculate distance.
	local requiredDistance = MELEE_DIST;
	if(bestSpell) then
		print("bestSpell: "..bestSpell.name.." "..bestSpell.rank);
		local ri = bestSpell.rangeIndex;
		if(ri == SPELL_RANGE_IDX_SELF_ONLY or
			ri == SPELL_RANGE_IDX_COMBAT or
			ri == SPELL_RANGE_IDX_ANYWHERE)
		then
			--hack
			-- requiredDistance = nil;
		else
			local range = cSpellRange(ri);
			if(range) then
				requiredDistance = range.max;
				-- todo: move away from target if we're closer than range.min.
			end
		end
	end

	-- start moving.
	local closeEnough = true;
	if(requiredDistance) then
		-- also sets orientation, so is worthwhile to do even if we're already in range.
		doMoveToTarget(getRealTime(), enemy, requiredDistance);
		closeEnough = (dist < requiredDistance);
	end

	if(closeEnough and bestSpell) then
		setTarget(enemy);
		castSpell(bestSpell.id, enemy);
		-- todo: handle cooldown.
		local recovery = math.max(bestSpell.RecoveryTime,
			bestSpell.CategoryRecoveryTime,
			bestSpell.StartRecoveryTime);
		local castTime = cSpellCastTime(bestSpell.CastingTimeIndex).base;
		print("recovery: "..recovery.." castTime: "..castTime);
		local cooldown = math.max(recovery, castTime);
		STATE.spellCooldown = realTime + cooldown / 1000;
		return true;
	end
	return false;
end

function setTarget(t)
	STATE.myTarget = t.guid;
	send(CMSG_SET_SELECTION, {target=t.guid});
end
