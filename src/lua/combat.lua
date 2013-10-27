
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
function getDuration(index, level)
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

function spellLevel(s)
	local level = STATE.myLevel - s.spellLevel;
	--assert(s.spellLevel == s.baseLevel);

	if (level > s.maxLevel and s.maxLevel > 0) then
		level = s.maxLevel;
	elseif (level < s.baseLevel) then
		level = s.baseLevel;
	end

	return level;
end

POWER_HEALTH = -2;

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
			local offset = s.powerType;
			if(offset == POWER_HEALTH) then offset = -1; end
			print(cost, s.ManaCostPercentage, offset, myValues[UNIT_FIELD_MAXPOWER1 + offset]);
			cost = cost + s.ManaCostPercentage * myValues[UNIT_FIELD_MAXPOWER1 + offset] / 100;
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
			print(s.name..": global cooldown "..s.StartRecoveryCategory.." "..
				STATE.spellGlobalCooldowns[s.StartRecoveryCategory].." > realTime "..realTime..
				" diff "..(STATE.spellGlobalCooldowns[s.StartRecoveryCategory] - realTime));
		end
		return true;
	end
	if((STATE.spellCategoryCooldowns[s.Category] or 0) > realTime) then
		if(sLog) then
			print(s.name..": cat cooldown "..s.Category.." "..
				STATE.spellCategoryCooldowns[s.Category].." > realTime "..realTime);
		end
		return true;
	end
	if((STATE.spellCooldowns[s.id] or 0) > realTime) then
		if(sLog) then
			print(s.name..": spell cooldown "..s.id.." "..
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

--ShapeshiftForm(GetByteValue(UNIT_FIELD_BYTES_1, 2));
--if (!(spellInfo->Stances & (1 << (form - 1))))
local function shapeshiftForm(o)
	return bit32.extract(o.values[UNIT_FIELD_BYTES_1] or 0, 16, 8);
end

local function formIsGoodForStances(s, form)
	return bit32.btest(s.Stances, 2 ^ (form-1));
end

local function haveStanceForSpell(s)
	return s.Stances == 0 or
		bit32.btest(s.AttributesEx2, SPELL_ATTR_EX2_NOT_NEED_SHAPESHIFT) or
		formIsGoodForStances(s, shapeshiftForm(STATE.me));
end

-- returns false or
-- level, duration, cost, powerIndex, availablePower.
function canCast(s, realTime, abortOnLowPower)
	local level, duration, cost, powerIndex, availablePower;
	-- if spell's cooldown hasn't yet expired, don't try to cast it.
	if(spellIsOnCooldown(realTime, s)) then return false; end

	-- if the spell requires a special aura that we don't have, skip it.
	if(spellRequiresAuraState(s)) then
		if(sLog) then
			print(s.name.." Needs CasterAuraState "..s.CasterAuraState);
		end
		return false;
	end

	-- if the spell requires that we be in a different form, skip it.
	local myForm = shapeshiftForm(STATE.me);
	if(not haveStanceForSpell(s)) then
		if(sLog) then
			print(s.name.." Needs form "..hex(s.Stances).." (have "..myForm..")");
		end
		return false;
	end

	-- if the spell requires combo points but we don't have any, skip it.
	if(bit32.btest(s.AttributesEx, SPELL_ATTR_EX_REQ_TARGET_COMBO_POINTS) and
		comboPoints() == 0)
	then
		if(sLog) then
			print(s.name.." Needs combo points.");
		end
		return false;
	end

	-- todo: handle these.
	local inCombat = next(STATE.enemies);
	if(bit32.btest(s.AttributesEx, SPELL_ATTR_EX_NOT_IN_COMBAT_TARGET) and inCombat) then
		if(sLog) then
			print(s.name.." Must be out of combat.");
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
	if(availablePower < cost and (not abortOnLowPower)) then
		if(sLog) then
			print(s.name.." Need more power!");
		end
		return false;
	end

	return level, duration, cost, powerIndex, availablePower;
end

local BASE_MELEERANGE_OFFSET = 1.333;

-- returns rangeMax, rangeMin, or nil.
local function spellRange(s, target)
	local ri = s.rangeIndex;
	if(ri == SPELL_RANGE_IDX_SELF_ONLY or
		ri == SPELL_RANGE_IDX_ANYWHERE)
	then
		--hack
		return nil;
	elseif(ri == SPELL_RANGE_IDX_COMBAT) then
		-- algo copied from mangos.
		return (math.max(MELEE_RANGE,
			BASE_MELEERANGE_OFFSET +
			(cIntAsFloat(STATE.my.values[UNIT_FIELD_COMBATREACH]) or 1.5) +
			(cIntAsFloat(target.values[UNIT_FIELD_COMBATREACH]) or 1.5)) - 1), nil
	else
		local range = cSpellRange(ri);
		if(range) then
			if(range.min == 0) then range.min = nil; end
			return range.max, range.min;
		end
	end
end

-- if abortOnLowPower, don't ignore spells we don't have enough power for.
-- instead, if we can't cast the best, don't cast anything.
function mostEffectiveSpell(realTime, spells, abortOnLowPower, target)
	local maxPpc = 0;
	local maxPointsForFree = 0;
	local maxPoints = 0;
	local bestSpell = nil;
	local availP;
	local bestCost;
	local dist = 0;
	if(target) then
		dist = distanceToObject(target);
	end
	--sLog = true
	if(sLog and next(spells)) then print("testing...") end
	for id, s in pairs(spells) do
		local level, duration, cost, powerIndex, availablePower =
			canCast(s, realTime, abortOnLowPower);
		if(not level) then goto continue; end
		availP = availablePower;

		-- if we're too close, ignore the spell.
		local rangeMax, rangeMin = spellRange(s, target);
		if(rangeMin and (dist > rangeMin)) then goto continue; end

		local points = spellPoints(s, level);

		if(sLog) then
			print("ap("..powerIndex.."): "..tostring(availablePower)..
				" cost("..s.powerType.."): "..cost..
				" points: "..points..
				" id: "..id..
				" name: "..s.name.." "..s.rank);
		end

		if(cost == 0 and points > maxPointsForFree) then
			maxPointsForFree = points;
			bestSpell = s;
			bestCost = cost;
			maxPoints = points;
			if(sLog) then
				print(
					" cost("..s.powerType.."): "..cost..
					" points: "..points..
					" id: "..id..
					" name: "..s.name.." "..s.rank);
			end
		elseif(maxPointsForFree == 0) then
			local ppc = points / cost;
			if(ppc > maxPpc) then
				maxPpc = ppc;
				bestSpell = s;
				bestCost = cost;
				maxPoints = points;
				if(sLog) then
					print(
						" cost("..s.powerType.."): "..cost..
						" points: "..points..
						" ppc: "..ppc..
						" id: "..id..
						" name: "..s.name.." "..s.rank);
				end
			end
		end
		::continue::
	end
	if(sLog and next(spells)) then print("test complete.") end
	if(bestSpell and (bestCost > availP)) then return nil, 0; end
	return bestSpell, maxPoints;
end

function doSpell(dist, realTime, target, s)
	assert(s);
	-- calculate distance.
	local behindTarget = false;
	--print("bestSpell: "..bestSpell.name.." "..bestSpell.rank);

	if(bit32.btest(s.AttributesEx, SPELL_ATTR_EX_BEHIND_TARGET_1) and
		bit32.btest(s.AttributesEx2, SPELL_ATTR_EX2_BEHIND_TARGET_2))
	then	-- Backstab or equivalent.
		behindTarget = true;
		-- todo: if we have aggro from this target, this kind of spell won't work,
		-- so we must disregard it from our selection of attack spells.
	end

	local requiredDistance = spellRange(s, target) or MELEE_DIST;

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
		tookAction = true;	-- is this right?
	end
	return tookAction;
end

function attackSpell(dist, realTime, enemy)
	-- look at all our spells and find the best one.
	-- todo: also look at combatBuffSpells.
	local bestSpell = mostEffectiveSpell(realTime, STATE.attackSpells, true, enemy);
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

		-- update target health asap after cast, to avoid double cast.
		-- server's update, which comes later, will overwrite any inaccuracies.
		healSpell.goCallback = function()
			o.values[UNIT_FIELD_HEALTH] = o.values[UNIT_FIELD_HEALTH] + points;
		end

		return doSpell(dist, realTime, o, healSpell);
	end
end

-- returns true if we're healing.
function doHeal(realTime)
	local healSpell, points = mostEffectiveSpell(realTime, STATE.healingSpells, false);
	if(not healSpell) then return; end
	-- TODO: if we don't have enough mana to cast the spell, don't try.
	-- TODO: heal all allies, not just toons.
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
		if(o) then
			--print("doBuff "..m.guid:hex());
			local res = doBuffSingle(o, realTime);
			if(res) then return res; end
		end
	end
	return doBuffSingle(STATE.me, realTime);
end

local function creatureTypeMask(info)
	local ct = info.type;
	if(ct == 0) then
		return 0;
	else
		return 2 ^ (ct-1);
	end
end

function doCrowdControl(realTime)
	if(not STATE.ccSpell) then return false; end

	-- no other enemy must be afflicted by our cc already.
	-- unfortunately, we have no way to know which enemy aura is ours.
	-- we can perhaps save the last enemy we tried to cc, and just check that one...
	-- but that won't work if another player of the same class hit it before us.
	-- still, better than nothing.
	if(STATE.ccTarget and hasAura(STATE.ccTarget, STATE.ccSpell)) then return false; end

	if(not canCast(STATE.ccSpell, realTime)) then return false; end

	local target;
	local targetInfo;
	-- the target must be an enemy with full health,
	-- must be of the correct type for the spell,
	-- mustn't be immune to the spell (we can't check this),
	-- that is not being targeted by any party member.
	-- elites are preferred.
	for guid,o in pairs(STATE.enemies) do
		local info = STATE.knownCreatures[o.values[OBJECT_FIELD_ENTRY]];
		if(bit32.btest(STATE.ccSpell.TargetCreatureType, creatureTypeMask(info)) and
			(o.values[UNIT_FIELD_HEALTH] == o.values[UNIT_FIELD_MAXHEALTH]) and
			(not isTargetOfPartyMember(o)) and
			((not targetInfo) or
				((targetInfo.rank == CREATURE_ELITE_NORMAL) and (info.rank ~= CREATURE_ELITE_NORMAL))
			))
		then
			target = o;
			targetInfo = info;
		end
	end
	if(target) then
		return doSpell(distanceToObject(target), realTime, target, STATE.ccSpell);
	else
		return false;
	end
end

local classInfo = {
	[CLASS_WARRIOR] = {tankPrio = 1},
	[CLASS_PALADIN] = {tankPrio = 1, drink=true},
	[CLASS_HUNTER] = {tankPrio = 2, drink=true},
	[CLASS_SHAMAN] = {tankPrio = 2, drink=true},
	[CLASS_ROGUE] = {tankPrio = 3},
	[CLASS_DRUID] = {tankPrio = 3, drink=true},
	[CLASS_MAGE] = {tankPrio = 4, drink=true},
	[CLASS_WARLOCK] = {tankPrio = 4, drink=true},
	[CLASS_PRIEST] = {tankPrio = 4, drink=true},
}

function getClassInfo(o)
	return classInfo[class(o)];
end

-- healers first, then other clothies, leather-wearers, mail, plate, in that order.
local function tankPrio(o)
	if(not isAlly(o)) then return 0; end
	if(o.bot.isHealer) then return 99; end
	local c = class(o);
	return classInfo[c].tankPrio;
end

local function tankTargetTest(enemyFilter)
	local maxPrio = 0;
	local chosen = nil;
	for guid,o in pairs(STATE.enemies) do
		local info = STATE.knownCreatures[o.values[OBJECT_FIELD_ENTRY]];
		if(info and enemyFilter(info)) then
			local tGuid = unitTarget(o);
			local prio;
			if(not tGuid) then
				prio = 0.5;
			else
				prio = tankPrio(STATE.knownObjects[tGuid]);
			end
			if(STATE.myGuid ~= tGuid and prio > maxPrio) then
				prio = maxPrio;
				chosen = o;
			end
		end
	end
	return chosen;
end

-- pick an enemy that is attacking one of our allies.
local function chooseTankTarget()
	-- elites first.
	local t = tankTargetTest(function(info)
		return info.rank ~= CREATURE_ELITE_NORMAL;
	end);
	if(t) then return t; end

	-- then normal enemies
	return tankTargetTest(function(info)
		return info.rank == CREATURE_ELITE_NORMAL;
	end);
end

function doStanceSpell(realTime, s, target)
	if(not s) then return false; end
	if(spellIsOnCooldown(realTime, s)) then return false; end

	-- if the spell requires a different stance...
	local myForm = shapeshiftForm(STATE.me);
	if(s.Stances ~= 0 and (not formIsGoodForStances(s, myForm))) then
		-- see if we have a spell to put us there...
		for form, ss in pairs(STATE.shapeshiftSpells) do
			if(formIsGoodForStances(s, form) and canCast(ss, realTime)) then
				-- if we do, cast the shapeshift spell, but not the stance-requiring one.
				-- it will be cast later.
				castSpellWithoutTarget(ss.id);
				return true;
			end
		end
		-- if not, don't cast it.
		return false;
	end

	-- we're good. cast the spell.
	if(target) then
		return doSpell(distanceToObject(target), realTime, target, s);
	elseif(canCast(s, realTime)) then
		castSpellWithoutTarget(s.id);
		return true;
	end
	return false;
end

local function goToPullPosition(realTime)
	local dist = distance3(STATE.my.location.position, STATE.pullPosition);
	if(dist < 1) then
		if(STATE.moving) then
			sendMovement(MSG_MOVE_STOP);
			STATE.moving = false;
		end
	else
		doMoveToPoint(realTime, STATE.pullPosition);
	end
end

local function shootSpell()
	-- if we have a ranged weapon equipped
	-- and a spell requires it, then
	-- that spell is our Shoot spell.
	local rangedWeaponGuid = equipmentInSlot(EQUIPMENT_SLOT_RANGED);
	if(not rangedWeaponGuid) then return nil; end
	local proto = itemProtoFromId(itemIdOfGuid(rangedWeaponGuid));
	for id,s in pairs(STATE.attackSpells) do
		if(s.EquippedItemClass == ITEM_CLASS_WEAPON and
			bit32.btest(s.EquippedItemSubClassMask, 2 ^ proto.subClass))
		then
			return s;
		end
	end
	return nil;
end

-- return true if we did something useful.
function doTanking(realTime)
	assert(STATE.amTank);
	-- if we have an enemy but are not in combat ourselves, take time to do the rotation.
	-- for all these named spells, check not for specifics,
	-- but for the best spell among those we know, that have the required effects.
	local enemy = chooseEnemy();
	if(not enemy) then return false; end
	if(not bit32.btest(STATE.my.values[UNIT_FIELD_FLAGS], UNIT_FLAG_IN_COMBAT)) then
		-- if we don't have the bloodrage buff, try to get it.
		if(doStanceSpell(realTime, STATE.energizeSelfSpell)) then
			return true;
		end

		-- if RAID_ICON_SQUARE, pull it.
		if(STATE.raidIcons[RAID_ICON_SQUARE] == enemy.guid) then
			setAction("Pulling "..enemy.guid:hex());
			-- Shoot the pullee.
			-- make sure a ranged weapon and ammo are equipped.
			-- If they're not, tank is likely to go into a SPELL_FAILED loop.
			if(doSpell(distanceToObject(enemy), realTime, enemy, shootSpell())) then
				return true;
			else
				-- then run to leader.
				goToPullPosition(realTime);
				return true;
			end
		end

		-- if we do have it or can't cast it, Charge!
		STATE.chargeSpell.goCallback = function()
			STATE.my.location.position = contactPoint(STATE.my.location.position,
				enemy.location.position, MELEE_DIST);
		end
		if(doStanceSpell(realTime, STATE.chargeSpell, enemy)) then
			return true;
		end
		-- if we couldn't cast Charge, we'll just run in, the normal way.
	end

	-- wait for enemy to arrive.
	if(STATE.raidIcons[RAID_ICON_SQUARE] == enemy.guid) then
		local dist = distanceToObject(enemy);
		if(dist > MELEE_RANGE) then
			goToPullPosition(realTime);
			return true;
		end
	end

	-- if we're still in Battle Stance, do Thunder Clap.
	-- TODO: move closer to enemies.
	--sLog = true;
	if(STATE.pbAoeSpell and canCast(STATE.pbAoeSpell, realTime)) then
		castSpellWithoutTarget(STATE.pbAoeSpell.id);
		return true;
	end
	--sLog = false;
	-- if we can't cast that, go to Berserker/Defensive Stance.

	-- todo: Berserker Stance
	-- if we're in Berserker Stance, do Demoralizing Shout and Berserker Rage.
	-- not neccesarily in that order.
	-- once those are on cooldown, go to Defensive Stance.

	-- in Defensive Stance, do Shield Block and Sunder Armor
	if(doStanceSpell(realTime, STATE.sunderSpell, enemy)) then return true; end
	if(not hasAura(enemy, STATE.blockBuffSpell)) then
		if(doStanceSpell(realTime, STATE.blockBuffSpell)) then return true; end
	end

	-- taunt someone, if we can and should.
	local target = chooseTankTarget();
	if(not target) then return false; end
	if(doStanceSpell(realTime, STATE.tauntSpell, target)) then return true; end
end

local function mainTankTarget()
	if(not STATE.mainTank) then return nil; end
	return unitTarget(STATE.mainTank);
end

local function isRaidTarget(iconId)
	local guid = STATE.raidIcons[iconId]
	if(isValidGuid(guid)) then
		return STATE.knownObjects[guid] and STATE.enemies[guid];
	end
	return false;
end

-- Skull, Moon, Diamond
local function raidTarget()
	local o = isRaidTarget(RAID_ICON_SKULL);
	if(o) then return o; end
	o = isRaidTarget(RAID_ICON_SQUARE);
	if(o) then return o; end
	o = isRaidTarget(RAID_ICON_MOON);
	if(o) then return o; end
	o = isRaidTarget(RAID_ICON_DIAMOND);
	if(o) then return o; end
	return nil;
end

local function tankIsWarrior()
	if(not STATE.mainTank) then return false; end
	return class(STATE.mainTank) == CLASS_WARRIOR;
end

local function hasSunder(o)
	return GetMaxNegativeAuraModifier(o, SPELL_AURA_MOD_RESISTANCE) ~= 0;
end

function chooseEnemy()
	-- if an enemy targets a party member, attack that enemy.
	-- if there are several enemies, pick any one.
	local i, enemy = next(STATE.enemies);
	if(STATE.amTank) then
		enemy = raidTarget() or enemy;
		enemy = chooseTankTarget() or enemy;
	else
		-- focus on main tank's target, if any.
		enemy = raidTarget() or enemy;
		enemy = STATE.enemies[mainTankTarget()] or enemy;
		if(enemy and tankIsWarrior() and (not hasSunder(enemy))) then
			enemy = false;
		end
	end
	return enemy;
end
