
function keepAttacking()
	-- if my target is still an enemy, keep attacking.
	return STATE.enemies[STATE.myTarget] ~= nil;
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
		castSpellAtUnit(STATE.meleeSpell, enemy);
		send(CMSG_ATTACKSWING, {target=enemy.guid});
		STATE.meleeing = true;
	end
end

function mostEffectiveSpell(spells)
	local maxPpc = 0;
	local maxPointsForFree = 0;
	local maxPoints = 0;
	local bestSpell = nil;
	local myValues = STATE.my.values;
	for id, s in pairs(spells) do
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

		local points = 0;
		for i, e in ipairs(s.effect) do
			if(e.id == SPELL_EFFECT_WEAPON_DAMAGE_NOSCHOOL or
				e.id == SPELL_EFFECT_SCHOOL_DAMAGE or
				e.id == SPELL_EFFECT_NORMALIZED_WEAPON_DMG or
				e.id == SPELL_EFFECT_WEAPON_DAMAGE or
				e.id == SPELL_EFFECT_HEAL)
			then
				points = points + calcAvgEffectPoints(level, e);
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

		--[[
		print("availablePower("..powerIndex.."): "..tostring(availablePower)..
			" cost("..s.powerType.."): "..cost..
			" points: "..points..
			" id: "..id..
			" name: "..s.name.." "..s.rank);
		]]
		if(not availablePower) then availablePower = 0; end
		--sanity check.
		assert(availablePower < 100000);
		if(availablePower < cost) then goto continue; end

		if(cost == 0 and points > maxPointsForFree) then
			maxPointsForFree = points;
			bestSpell = s;
			maxPoints = points;
		elseif(maxPointsForFree == 0) then
			local ppc = points / cost;
			if(ppc > maxPpc) then
				maxPpc = ppc;
				bestSpell = s;
				maxPoints = points;
			end
		end
		::continue::
	end
	return bestSpell, maxPoints;
end

function doSpell(dist, realTime, target, bestSpell)
	-- calculate distance.
	local requiredDistance = MELEE_DIST;
	local behindTarget = false;
	if(bestSpell) then
		print("bestSpell: "..bestSpell.name.." "..bestSpell.rank);

		if(bit32.btest(bestSpell.AttributesEx, SPELL_ATTR_EX_BEHIND_TARGET_1) and
			bit32.btest(bestSpell.AttributesEx2, SPELL_ATTR_EX2_BEHIND_TARGET_2))
		then	-- Backstab or equivalent.
			behindTarget = true;
			-- todo: if we have aggro from this target, this kind of spell won't work,
			-- so we must disregard it from our selection of attack spells.
		end

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
	local tookAction = false;
	if(behindTarget) then
		closeEnough = doCombatMoveBehindTarget(getRealTime(), target);
		tookAction = true;
	elseif(requiredDistance) then
		-- also sets orientation, so is worthwhile to do even if we're already in range.
		doMoveToTarget(getRealTime(), target, requiredDistance);
		closeEnough = (dist < requiredDistance);
		tookAction = true;
	end

	if(closeEnough and bestSpell) then
		setTarget(target);
		castSpellAtUnit(bestSpell.id, target);
		-- todo: handle cooldown.
		local recovery = math.max(bestSpell.RecoveryTime,
			bestSpell.CategoryRecoveryTime,
			bestSpell.StartRecoveryTime);
		local castTime = cSpellCastTime(bestSpell.CastingTimeIndex).base;
		print("recovery: "..recovery.." castTime: "..castTime);
		local cooldown = math.max(recovery, castTime);
		STATE.spellCooldown = realTime + cooldown / 1000;
		tookAction = true;
	end
	return tookAction;
end

function attackSpell(dist, realTime, enemy)
	-- look at all our spells and find the best one.
	local bestSpell = mostEffectiveSpell(STATE.attackSpells);
	return doSpell(dist, realTime, enemy, bestSpell);
end

function setTarget(t)
	STATE.myTarget = t.guid;
	send(CMSG_SET_SELECTION, {target=t.guid});
end

-- returns true if we're healing.
function doHeal(realTime)
	local healSpell, points = mostEffectiveSpell(STATE.healingSpells);
	if(not healSpell) then return; end
	for i,m in ipairs(STATE.groupMembers) do
		local o = STATE.knownObjects[m.guid];
		if(not o) then return false; end
		local maxHealth = o.values[UNIT_FIELD_MAXHEALTH];
		local health = o.values[UNIT_FIELD_HEALTH];
		if(((maxHealth - health) >= points) or (health <= (maxHealth/2))) then
			local dist = distanceToObject(o);
			return doSpell(dist, realTime, o, healSpell);
		end
	end
	return false;
end

function doBuff(realTime)
	-- check each party member
	for i,m in ipairs(STATE.groupMembers) do
		local o = STATE.knownObjects[m.guid];
		if(not o) then return false; end
		-- check all auras. if there's one aura of ours they DON'T have, give it.
		for id, s in pairs(STATE.buffSpells) do
			if(not hasAura(o, id)) then
				local dist = distanceToObject(o);
				return doSpell(dist, realTime, o, s);
			end
		end
	end
	return false;
end