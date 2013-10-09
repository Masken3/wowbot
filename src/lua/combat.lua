
local sLog = false;

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
	--print("attack, dist", dist);

	-- if we have a good ranged attack, use that.
	-- otherwise, go to melee.

	if(not STATE.amHealer) then
		-- todo: set stance, cast area buffs.

		if(attackSpell(dist, realTime, enemy)) then return; end
	end

	-- todo: if we have a wand or if we're a hunter with bow and arrows, use those.

	if(not STATE.meleeing) then
		--print("start melee");
		setTarget(enemy);
		if(doSpell(dist, realTime, enemy, STATE.meleeSpell) and (dist < MELEE_DIST)) then
			send(CMSG_ATTACKSWING, {target=enemy.guid});
			STATE.meleeing = true;
		end
	end
end

local normalizationSpeed;	-- declare function as file-local
do
	local OneHandSpeed = 2.4;
	local TwoHandSpeed = 3.3;
	local RangedSpeed = 2.8;
	local weaponSubclassNormalizationSpeeds = {
		[ITEM_SUBCLASS_WEAPON_DAGGER] = 1.7,
		[ITEM_SUBCLASS_WEAPON_AXE2] = TwoHandSpeed,
		[ITEM_SUBCLASS_WEAPON_MACE2] = TwoHandSpeed,
		[ITEM_SUBCLASS_WEAPON_POLEARM] = TwoHandSpeed,
		[ITEM_SUBCLASS_WEAPON_SWORD2] = TwoHandSpeed,
		[ITEM_SUBCLASS_WEAPON_STAFF] = TwoHandSpeed,
		[ITEM_SUBCLASS_WEAPON_EXOTIC2] = TwoHandSpeed,
		[ITEM_SUBCLASS_WEAPON_SPEAR] = TwoHandSpeed,
		[ITEM_SUBCLASS_WEAPON_FISHING_POLE] = TwoHandSpeed,
		[ITEM_SUBCLASS_WEAPON_BOW] = RangedSpeed,
		[ITEM_SUBCLASS_WEAPON_GUN] = RangedSpeed,
		[ITEM_SUBCLASS_WEAPON_THROWN] = RangedSpeed,
		[ITEM_SUBCLASS_WEAPON_WAND] = RangedSpeed,
	}

	function normalizationSpeed(proto)
		if(proto._class ~= ITEM_CLASS_WEAPON) then return 0; end
		local speed = weaponSubclassNormalizationSpeeds[proto.subClass];
		if(speed) then
			return speed;
		else	-- one-handed
			return OneHandSpeed;
		end
	end
end

local function avgMainhandDamage()
	local weaponGuid = equipmentInSlot(EQUIPMENT_SLOT_MAINHAND);
	if(not weaponGuid) then return 0; end
	local weapon = STATE.knownObjects[weaponGuid];
	local proto = itemProtoFromId(weapon.values[OBJECT_FIELD_ENTRY]);
	local avg = avgItemDamage(proto);
	local attackPower = STATE.my.values[UNIT_FIELD_ATTACK_POWER] or 0;
	avg = avg + (attackPower / 14) * normalizationSpeed(proto);
	return avg;
end

local function spellLevel(s)
	local level = STATE.myLevel;
	--print("myLevel: "..level.." maxLevel: "..s.maxLevel);

	if (level > s.maxLevel and s.maxLevel > 0) then
		level = s.maxLevel;
	elseif (level < s.baseLevel) then
		level = s.baseLevel;
	end
	level = level - s.spellLevel;

	return level;
end

local function spellCost(s, level, duration)
	local myValues = STATE.my.values;
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
	return cost;
end

local function comboTarget()
	return guidFromValues(STATE.me, PLAYER_FIELD_COMBO_TARGET);
end

local function comboPoints()
	return bit32.extract(STATE.my.values[PLAYER_FIELD_BYTES] or 0, 8, 8);
end

local function spellPoints(s, level)
	local points = 0;

	-- if we're the tank, allocate bonus points to threatening spells.
	if(STATE.amTank) then
		points = points + (SPELL_THREAT[s.id] or 0);
	end

	for i, e in ipairs(s.effect) do
		if(e.id == SPELL_EFFECT_WEAPON_DAMAGE_NOSCHOOL or
			e.id == SPELL_EFFECT_SCHOOL_DAMAGE or
			e.id == SPELL_EFFECT_NORMALIZED_WEAPON_DMG or
			e.id == SPELL_EFFECT_WEAPON_DAMAGE or
			(e.id == SPELL_EFFECT_THREAT and STATE.amTank) or
			e.id == SPELL_EFFECT_HEAL)
		then
			points = points + calcAvgEffectPoints(level, e);

			-- add normalized weapon damage to such effects
			if(e.id == SPELL_EFFECT_NORMALIZED_WEAPON_DMG) then
				points = points + avgMainhandDamage();
			end

			-- todo: handle combo-point spells
			if(e.pointsPerComboPoint ~= 0) then
				--print("ppc: "..e.pointsPerComboPoint);
				points = points + comboPoints() * e.pointsPerComboPoint;
			end
		end
	end
	return points;
end

function spellIsOnCooldown(realTime, s)
	if((STATE.spellGlobalCooldowns[s.StartRecoveryCategory] or 0) > realTime) then
		if(sLog) then
			print("global cooldown "..s.StartRecoveryCategory.." "..
				STATE.spellGlobalCooldowns[s.StartRecoveryCategory].." > realTime "..realTime..
				" diff "..(STATE.spellGlobalCooldowns[s.StartRecoveryCategory] - realTime));
		end
		return true;
	end
	if((STATE.spellCategoryCooldowns[s.Category] or 0) > realTime) then
		if(sLog) then
			print("cat cooldown "..s.Category.." "..
				STATE.spellCategoryCooldowns[s.Category].." > realTime "..realTime);
		end
		return true;
	end
	if((STATE.spellCooldowns[s.id] or 0) > realTime) then
		if(sLog) then
			print("spell cooldown "..s.id.." "..
				STATE.spellCooldowns[s.id].." > realTime "..realTime);
		end
		return true;
	end
	return false;
end

local function spellRequiresAuraState(s)
	if(s.CasterAuraState == 0) then return false; end
	return bit32.extract(STATE.my.values[UNIT_FIELD_AURASTATE] or 0,
		s.CasterAuraState - 1) == 0;
end

-- returns false or
-- level, duration, cost, powerIndex, availablePower.
local function canCast(s, realTime)
	local level, duration, cost, powerIndex, availablePower;
	-- if spell's cooldown hasn't yet expired, don't try to cast it.
	if(spellIsOnCooldown(realTime, s)) then return false; end

	-- if the spell requires a special aura that we don't have, skip it.
	if(spellRequiresAuraState(s)) then
		if(sLog) then
			print("Needs CasterAuraState "..s.CasterAuraState);
		end
		return false;
	end

	-- if the spell requires combo points but we don't have any, skip it.
	if(bit32.btest(s.AttributesEx, SPELL_ATTR_EX_REQ_TARGET_COMBO_POINTS) and
		comboPoints() == 0) then return false; end

	-- todo: handle these.
	local inCombat = next(STATE.enemies);
	if(bit32.btest(s.AttributesEx, SPELL_ATTR_EX_NOT_IN_COMBAT_TARGET) and inCombat) then
		if(sLog) then
			print("Must be out of combat.");
		end
		return false;
	end

	level = spellLevel(s);
	duration = getDuration(s.DurationIndex, level);
	cost = spellCost(s, level, duration);

	if(s.powerType == POWER_HEALTH) then
		powerIndex = UNIT_FIELD_HEALTH;
	else
		powerIndex = UNIT_FIELD_POWER1 + s.powerType;
	end
	availablePower = STATE.my.values[powerIndex];

	--print("cost("..s.powerType.."): "..cost.." availablePower("..powerIndex.."): "..tostring(availablePower));
	if(not availablePower) then availablePower = 0; end

	--sanity check.
	assert(availablePower < 100000);

	-- if we can't cast the spell, ignore it.
	if(availablePower < cost) then
		if(sLog) then
			print("Need more power!");
		end
		return false;
	end

	return level, duration, cost, powerIndex, availablePower;
end

function mostEffectiveSpell(realTime, spells)
	local maxPpc = 0;
	local maxPointsForFree = 0;
	local maxPoints = 0;
	local bestSpell = nil;
	for id, s in pairs(spells) do
		local level, duration, cost, powerIndex, availablePower = canCast(s, realTime);
		if(not level) then goto continue; end

		local points = spellPoints(s, level);

		if(false) then
			print("availablePower("..powerIndex.."): "..tostring(availablePower)..
				" cost("..s.powerType.."): "..cost..
				" points: "..points..
				" id: "..id..
				" name: "..s.name.." "..s.rank);
		end

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

local BASE_MELEERANGE_OFFSET = 1.333;

function doSpell(dist, realTime, target, s)
	assert(s);
	-- calculate distance.
	local requiredDistance = MELEE_DIST;
	local behindTarget = false;
	--print("bestSpell: "..bestSpell.name.." "..bestSpell.rank);

	if(bit32.btest(s.AttributesEx, SPELL_ATTR_EX_BEHIND_TARGET_1) and
		bit32.btest(s.AttributesEx2, SPELL_ATTR_EX2_BEHIND_TARGET_2))
	then	-- Backstab or equivalent.
		behindTarget = true;
		-- todo: if we have aggro from this target, this kind of spell won't work,
		-- so we must disregard it from our selection of attack spells.
	end

	local ri = s.rangeIndex;
	if(ri == SPELL_RANGE_IDX_SELF_ONLY or
		ri == SPELL_RANGE_IDX_ANYWHERE)
	then
		--hack
		-- requiredDistance = nil;
	elseif(ri == SPELL_RANGE_IDX_COMBAT) then
		-- algo copied from mangos.
		requiredDistance = math.max(MELEE_RANGE,
			BASE_MELEERANGE_OFFSET +
			(cIntAsFloat(STATE.my.values[UNIT_FIELD_COMBATREACH]) or 1.5) +
			(cIntAsFloat(target.values[UNIT_FIELD_COMBATREACH]) or 1.5)) - 1
	else
		local range = cSpellRange(ri);
		if(range) then
			requiredDistance = range.max;
			-- todo: move away from target if we're closer than range.min.
		end
	end

	-- start moving.
	local closeEnough = true;
	local tookAction = false;
	if(behindTarget) then
		closeEnough = doCombatMoveBehindTarget(realTime, target);
		tookAction = true;
	elseif(requiredDistance) then
		-- also sets orientation, so is worthwhile to do even if we're already in range.
		closeEnough = doMoveToTarget(realTime, target, requiredDistance);
		tookAction = true;
	end

	if(closeEnough) then
		setTarget(target);
		print("requiredDistance for "..s.id..": "..requiredDistance);
		castSpellAtUnit(s.id, target);
	end
	return tookAction;
end

function attackSpell(dist, realTime, enemy)
	-- look at all our spells and find the best one.
	local bestSpell = mostEffectiveSpell(realTime, STATE.attackSpells);
	if(not bestSpell) then
		return false;
	end
	return doSpell(dist, realTime, enemy, bestSpell);
end

function setTarget(t)
	STATE.myTarget = t.guid;
	send(CMSG_SET_SELECTION, {target=t.guid});
end

local function doHealSingle(o, healSpell, points, realTime)
	local maxHealth = o.values[UNIT_FIELD_MAXHEALTH];
	local health = o.values[UNIT_FIELD_HEALTH];
	if(((maxHealth - health) >= points) or (health <= (maxHealth/2))) then
		objectNameQuery(o, function(name)
			setAction("Healing "..name);
		end)
		local dist = distanceToObject(o);
		return doSpell(dist, realTime, o, healSpell);
	end
end

-- returns true if we're healing.
function doHeal(realTime)
	local healSpell, points = mostEffectiveSpell(realTime, STATE.healingSpells);
	if(not healSpell) then return; end
	-- TODO: if we don't have enough mana to cast the spell, don't try.
	for i,m in ipairs(STATE.groupMembers) do
		local o = STATE.knownObjects[m.guid];
		if(not o) then return false; end
		local res = doHealSingle(o, healSpell, points, realTime);
		if(res) then return res; end
	end
	return doHealSingle(STATE.me, healSpell, points, realTime);
end

local function doBuffSingle(o, realTime)
	-- check all auras. if there's one aura of ours they DON'T have, give it.
	for buffName, s in pairs(STATE.buffSpells) do
		local h = hasAura(o, s.id);
		--sLog = true;
		local c = canCast(s, realTime);
		sLog = false;
		if(not h and c) then
			local dist = distanceToObject(o);
			objectNameQuery(o, function(name)
				setAction("Buffing "..name);
			end)
			return doSpell(dist, realTime, o, s);
		else
			--print("not buffing "..s.name..": "..tostring(h).." "..tostring(c));
		end
	end
	return false;
end

function doBuff(realTime)
	-- check each party member
	for i,m in ipairs(STATE.groupMembers) do
		local o = STATE.knownObjects[m.guid];
		if(not o) then return false; end
		--print("doBuff "..m.guid:hex());
		local res = doBuffSingle(o, realTime);
		if(res) then return res; end
	end
	return doBuffSingle(STATE.me, realTime);
end

-- return true if we did something useful.
local function doTaunt(realTime, o)
	return doSpell(distanceToObject(o), realTime, o, STATE.tauntSpell)
end

-- return true if we did something useful.
function doTanking(realTime)
	if(not STATE.tauntSpell) then return false; end
	if(not canCast(STATE.tauntSpell, realTime)) then return false; end
	-- elites first.
	for guid,o in pairs(STATE.enemies) do
		local info = STATE.knownCreatures[o.values[OBJECT_FIELD_ENTRY]];
		if(info and info.rank ~= CREATURE_ELITE_NORMAL) then
			local tGuid = unitTarget(o);
			local t = STATE.knownObjects[tGuid];
			if(STATE.myGuid ~= tGuid and isAlly(t)) then
				return doTaunt(realTime, o);
			end
		end
	end

	-- then normal enemies
	for guid,o in pairs(STATE.enemies) do
		local info = STATE.knownCreatures[o.values[OBJECT_FIELD_ENTRY]];
		if((not info) or info.rank == CREATURE_ELITE_NORMAL) then
			local tGuid = unitTarget(o);
			local t = STATE.knownObjects[tGuid];
			if(STATE.myGuid ~= tGuid and isAlly(t)) then
				return doTaunt(realTime, o);
			end
		end
	end
end
