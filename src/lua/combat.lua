
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

	local shouldUseSpells = true;
	if(STATE.amHealer) then shouldUseSpells = false; end
	if(STATE.amTank and not hasSunder(enemy)) then shouldUseSpells = false; end

	if(shouldUseSpells) then
		-- todo: set stance, cast area buffs.

		if(attackSpell(dist, realTime, enemy)) then return; end
	end

	if(STATE.meleeing ~= enemy.guid) then
		--print("Starting melee because STATE.meleeing: "..tostring(STATE.meleeing));
		-- if we have a wand or if we're a hunter with bow and arrows, use those.
		--
		local ss = shootSpell();
		if(ss and bit32.btest(ss.AttributesEx2, SPELL_ATTR_EX2_AUTOREPEAT_FLAG)) then
			setTarget(enemy);
			print("Target set: "..enemy.guid:hex());
			if(doSpell(dist, realTime, enemy, ss) and (not STATE.moving)) then
				print("Now shooting "..enemy.guid:hex());
				STATE.meleeing = enemy.guid;
			end
			return;
		end
		--]]
		--print("start melee");
		setTarget(enemy);
		if(doSpell(dist, realTime, enemy, STATE.meleeSpell) and
			(dist < MELEE_RANGE) and (not STATE.moving))
		then
			send(CMSG_ATTACKSWING, {target=enemy.guid});
			STATE.meleeing = enemy.guid;
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
		if(proto.itemClass ~= ITEM_CLASS_WEAPON) then return 0; end
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
	if(not proto) then return 0; end
	local avg = avgItemDamage(proto);
	local attackPower = STATE.my.values[UNIT_FIELD_ATTACK_POWER] or 0;
	avg = avg + (attackPower / 14) * normalizationSpeed(proto);
	return avg;
end

function spellLevel(s)
	local level = math.max(0, math.min(STATE.myLevel, s.maxLevel) - s.spellLevel);
	--assert(s.spellLevel == s.baseLevel);

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

	return cost;
end

local function comboTarget()
	return guidFromValues(STATE.me, PLAYER_FIELD_COMBO_TARGET);
end

function comboPoints()
	return bit32.extract(STATE.my.values[PLAYER_FIELD_BYTES] or 0, 8, 8);
end

local function spellPoints(s, level)
	local points = 0;

	level = level or spellLevel(s);

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
		if(e.id == SPELL_EFFECT_APPLY_AURA and
			e.applyAuraName == SPELL_AURA_PERIODIC_TRIGGER_SPELL)
		then
			local ts = cSpell(e.triggerSpell);
			local duration = getDuration(s.DurationIndex, level);
			local multiplier = duration / (e.amplitude / 1000);
			points = points + spellPoints(ts, level) * multiplier;
		end
		--[[
		if(e.id == SPELL_EFFECT_PERSISTENT_AREA_AURA and
			e.applyAuraName == SPELL_AURA_PERIODIC_DAMAGE)
		then
			local duration = getDuration(s.DurationIndex, level);
			local multiplier = duration / (e.amplitude / 1000);
			points = points + calcAvgEffectPoints(level, e) * multiplier;
		end
		--]]
	end
	return points;
end

local function spellIsOnGlobalCooldown(realTime, s)
	if((STATE.spellGlobalCooldowns[s.StartRecoveryCategory] or 0) > realTime) then
		if(sLog) then
			print(s.name..": global cooldown "..s.StartRecoveryCategory.." "..
				STATE.spellGlobalCooldowns[s.StartRecoveryCategory].." > realTime "..realTime..
				" diff "..(STATE.spellGlobalCooldowns[s.StartRecoveryCategory] - realTime));
		end
		return true;
	end
	return false;
end

local function spellIsOnLocalCooldown(realTime, s)
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

function spellIsOnCooldown(realTime, s)
	if(spellIsOnGlobalCooldown(realTime, s)) then return true; end
	if(spellIsOnLocalCooldown(realTime, s)) then return true; end
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

function canCastIgnoreGcd(s, realTime, ignoreLowPower)
	return canCastBase(s, realTime, ignoreLowPower, spellIsOnLocalCooldown);
end

function canCast(s, realTime, ignoreLowPower)
	return canCastBase(s, realTime, ignoreLowPower, spellIsOnCooldown);
end

function canCastIgnoreStance(s, realTime)
	return canCastBase(s, realTime, false, spellIsOnCooldown, true);
end

function requiresComboPoints(s)
	return bit32.btest(s.AttributesEx,
		bit32.bor(SPELL_ATTR_EX_REQ_COMBO_POINTS, SPELL_ATTR_EX_REQ_TARGET_COMBO_POINTS));
end

-- returns false or
-- level, duration, cost, powerIndex, availablePower.
function canCastBase(s, realTime, ignoreLowPower, coolDownTest, ignoreStance)
	local level, duration, cost, powerIndex, availablePower;
	-- if spell's cooldown hasn't yet expired, don't try to cast it.
	if(coolDownTest(realTime, s)) then return false; end

	-- if the spell requires a special aura that we don't have, skip it.
	if(spellRequiresAuraState(s)) then
		if(sLog) then
			print(s.name.." Needs CasterAuraState "..s.CasterAuraState);
		end
		return false;
	end

	-- if the spell requires that we be in a different form, skip it.
	local myForm = shapeshiftForm(STATE.me);
	if((not ignoreStance) and (not haveStanceForSpell(s))) then
		if(sLog) then
			print(s.name.." Needs form "..hex(s.Stances).." (have "..myForm..")");
		end
		return false;
	end

	if(not STATE.stealthed and bit32.btest(s.Attributes, SPELL_ATTR_ONLY_STEALTHED)) then
		if(sLog) then
			print(s.name.." Needs stealth.");
		end
		return false;
	end

	-- if the spell requires combo points but we don't have any, skip it.
	if(requiresComboPoints(s) and comboPoints() == 0) then
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
	if(availablePower < cost and (not ignoreLowPower)) then
		if(sLog) then
			print(s.name.." Need more power!", availablePower.." < "..cost);
		end
		return false;
	end

	return level, duration, cost, powerIndex, availablePower;
end

local BASE_MELEERANGE_OFFSET = 1.333;

local function intAsFloat(int, default)
	if(not int) then return default; end
	return cIntAsFloat(int);
end

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
			intAsFloat(STATE.my.values[UNIT_FIELD_COMBATREACH], 1.5) +
			intAsFloat(target.values[UNIT_FIELD_COMBATREACH], 1.5)) - 1), nil
	else
		local range = cSpellRange(ri);
		if(range) then
			if(range.min == 0) then range.min = nil; end
			return range.max, range.min;
		end
	end
end

function dumpMostEffectiveSpell(spells)
	sLog = true
	mostEffectiveSpell(getRealTime(), spells, true)
	sLog = false
end

-- if ignoreLowPower, don't ignore spells we don't have enough power for.
-- instead, if we can't cast the best, don't cast anything.
function mostEffectiveSpell(realTime, spells, ignoreLowPower, target)
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

	-- if we're the target of more than one enemy, don't try channeled spells.
	local countOfEnemiesTargetingUs = 0;
	for guid,o in pairs(STATE.enemies) do
		if(guidFromValues(o, UNIT_FIELD_TARGET) == STATE.myGuid) then
			countOfEnemiesTargetingUs = countOfEnemiesTargetingUs + 1;
		end
	end

	if(STATE.myClassName == 'Rogue') then
		--sLog = true
	end
	if(sLog and next(spells)) then print("testing...") end
	for id, s in pairs(spells) do
		local level, duration, cost, powerIndex, availablePower =
			canCastIgnoreGcd(s, realTime, ignoreLowPower);
		if(not level) then goto continue; end
		if(s == STATE.interruptSpell) then goto continue; end
		availP = availablePower;

		if(countOfEnemiesTargetingUs > 1 and
			bit32.btest(s.AttributesEx, bit32.bor(SPELL_ATTR_EX_CHANNELED_1, SPELL_ATTR_EX_CHANNELED_2)))
		then
			if(sLog) then print("Skipped due to "..countOfEnemiesTargetingUs.." enemies targeting us."); end
			goto continue;
		end

		-- if we're too close, ignore the spell.
		if(target) then
			local rangeMax, rangeMin = spellRange(s, target);
			if(rangeMin and (dist > rangeMin)) then goto continue; end
		end

		local points = spellPoints(s, level);
		local ppc = points / cost;
		s.ppc = ppc;

		if(sLog) then
			print("ap("..powerIndex.."): "..tostring(availablePower)..
				" cost("..s.powerType.."): "..cost..
				" level: "..level..
				" points: "..points..
				" ppc: "..ppc..
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
	if(bestSpell and (bestCost > availP) and (not ignoreLowPower)) then
		if(sLog) then
			print(bestSpell.name.." Not enough power!", availP.." < "..bestCost);
		end
		return nil, 0;
	end
	return bestSpell, maxPoints;
end

-- dist may be false.
function doSpell(dist, realTime, target, s, customRange)
	assert(s);
	if(not canCastIgnoreGcd(s, realTime)) then return false; end
	-- calculate distance.
	dist = dist or distanceToObject(target)
	local behindTarget = false;
	if(STATE.myClassName == 'Rogue') then
		--sLog = true
	end
	if(sLog) then
		print("s: "..s.name.." "..s.rank);
	end

	if(bit32.btest(s.AttributesEx, SPELL_ATTR_EX_BEHIND_TARGET_1) and
		bit32.btest(s.AttributesEx2, SPELL_ATTR_EX2_BEHIND_TARGET_2))
	then	-- Backstab or equivalent.
		if(sLog) then
			print("BehindTarget");
		end
		behindTarget = true;
		-- todo: if we have aggro from this target, this kind of spell won't work,
		-- so we must disregard it from our selection of attack spells.
	end

	local requiredDistance = customRange or spellRange(s, target) or MELEE_DIST;

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

	if(closeEnough and (not spellIsOnGlobalCooldown(realTime, s))) then
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

	-- first, check direct damage
	local bestSpell = mostEffectiveSpell(realTime, STATE.attackSpells, true, enemy);
	if(not bestSpell) then
		return false;
	end
	-- if an AoE attack would serve us better, do that.
	if(doAoeAttack(realTime, bestSpell)) then return true; end

	-- if any of our self buffs would be better, do that.
	if(doSelfCombatBuff(realTime, bestSpell)) then return true; end

	return doSpell(dist, realTime, enemy, bestSpell);
end

function setTarget(t)
	if(STATE.myTarget == t.guid) then return; end
	STATE.myTarget = t.guid;
	send(CMSG_SET_SELECTION, {target=t.guid});
end

local function doHealSingle(o, healSpell, points, realTime)
	local maxHealth = o.values[UNIT_FIELD_MAXHEALTH];
	local health = o.values[UNIT_FIELD_HEALTH];
	if(health <= 1) then
		-- they're dead.
		return false;
	end
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
	local healSpell, points = mostEffectiveSpell(realTime, STATE.healingSpells, true);
	if(not healSpell) then return; end
	-- if an AoE attack would serve us better, do that.
	if(doAoeHeal(realTime, healSpell, points)) then return true; end
	-- if we don't have enough mana to cast the spell, don't try.
	-- TODO: heal all allies, not just toons.
	for i,m in ipairs(STATE.groupMembers) do
		local o = STATE.knownObjects[m.guid];
		if(not o) then return false; end
		local res = doHealSingle(o, healSpell, points, realTime);
		if(res) then return res; end
	end
	return doHealSingle(STATE.me, healSpell, points, realTime);
end

local function doBuffSingle(o, realTime, buffSpells)
	-- if target is dead, don't bother.
	if(o.values[UNIT_FIELD_HEALTH] <= 1) then return false; end

	-- check all auras. if there's one aura of ours they DON'T have, give it.
	for buffName, s in pairs(buffSpells) do
		local h = hasAura(o, s.id);
		--sLog = true;
		local c = canCast(s, realTime);
		sLog = false;
		if(not h and c) then
			objectNameQuery(o, function(name)
				setAction("Buffing "..name);
			end)
			if(requiresComboPoints(s)) then
				local o = STATE.knownObjects[guidFromValues(STATE.me, UNIT_FIELD_TARGET)];
				if(o) then
					investigateAuras(o, function(s, level)
						print("Aura: "..s.name.." ("..s.id..") level "..level);
					end);
				end
			end
			return doSpell(false, realTime, o, s);
		else
			--print("not buffing "..s.name..": "..tostring(h).." "..tostring(c));
		end
	end
	return false;
end

function doBuff(realTime)
	-- if we're dead, don't bother.
	if(STATE.my.values[UNIT_FIELD_HEALTH] <= 1) then return false; end
	-- buff ourselves first.
	if(doBuffSingle(STATE.me, realTime, STATE.selfBuffSpells)) then return true; end
	-- check each party member
	for i,m in ipairs(STATE.groupMembers) do
		local o = STATE.knownObjects[m.guid];
		if(o) then
			--print("doBuff "..m.guid:hex());
			local res = doBuffSingle(o, realTime, STATE.buffSpells);
			if(res) then return res; end
		end
	end
	return doBuffSingle(STATE.me, realTime, STATE.buffSpells);
end

local function creatureTypeMask(info)
	local ct = info.type;
	if(ct == 0) then
		return 0;
	else
		return 2 ^ (ct-1);
	end
end

function isTargetOfPartyMember(o)
	for i,m in ipairs(STATE.groupMembers) do
		local go = STATE.knownObjects[m.guid];
		if(go and unitTarget(go) == o.guid) then return true; end
	end
	return false;
end

-- don't try to cc targets with any of these auras
local ccAuras = {
	[SPELL_AURA_MOD_CONFUSE]=true,
	[SPELL_AURA_MOD_STUN]=true,
	[SPELL_AURA_MOD_TAUNT]=true,
	[SPELL_AURA_MOD_POSSESS]=true,
	[SPELL_AURA_MOD_CHARM]=true,
	[SPELL_AURA_MOD_FEAR]=true,
	[SPELL_AURA_MOD_PACIFY]=true,
	[SPELL_AURA_MOD_ROOT]=true,
	[SPELL_AURA_MOD_PACIFY_SILENCE]=true,
	[SPELL_AURA_PREVENTS_FLEEING]=true,
	[SPELL_AURA_MOD_UNATTACKABLE]=true,
	[SPELL_AURA_PERIODIC_DAMAGE]=true,
}

local ccTransforms = {
	[620]=true,
	[1933]=true,
	[14801]=true,
	[16371]=true,
	[16372]=true,
	[16377]=true,
	[16479]=true,
	[16779]=true,
}

local function hasCrowdControlAura(o)
	local res = false;
	investigateAuraEffects(o, function(e, level)
		if(ccAuras[e.applyAuraName]) then
			--print("hasCrowdControlAura:", o.guid:hex());
			res = true;
		end
		if(e.applyAuraName == SPELL_AURA_TRANSFORM and ccTransforms[e.miscValue]) then
			res = true;
		end
		return false;
	end)
	return res;
end

function doCrowdControl(realTime)
	-- Sap
	if(STATE.sapSpell) then
		local o = raidTargetByIcon(RAID_ICON_DIAMOND, true);
		--print("sapTest", tostring(o), dump(STATE.raidIcons));
		if(o and (not hasCrowdControlAura(o)) and (not STATE.enemies[o.guid])) then
			doStealthSpell(realTime, o, STATE.sapSpell);
			return true;
		end
	end

	if((not STATE.ccSpell) or (not PERMASTATE.eliteCombat)) then return false; end

	-- no other enemy must be afflicted by our cc already.
	-- unfortunately, we have no way to know which enemy aura is ours.
	-- we can perhaps save the last enemy we tried to cc, and just check that one...
	-- but that won't work if another player of the same class hit it before us.
	-- still, better than nothing.
	if(STATE.ccTarget and hasCrowdControlAura(STATE.ccTarget)) then return false; end

	if(not canCastIgnoreGcd(STATE.ccSpell, realTime)) then return false; end

	local target;
	local targetInfo;
	-- the target must be an enemy with full health,
	-- must be of the correct type for the spell,
	-- mustn't be immune to the spell (we can't check this),
	-- that is not being targeted by any party member.
	-- elites are preferred.
	local count = 0;
	for guid,o in pairs(STATE.enemies) do
		local info = STATE.knownCreatures[o.values[OBJECT_FIELD_ENTRY]];
		if(info and bit32.btest(STATE.ccSpell.TargetCreatureType, creatureTypeMask(info)) and
			((o.bot.ccTime or 0) + 5 < realTime) and
			(not hasCrowdControlAura(o)))
		then
			-- moon icon takes priority.
			if(raidTargetByIcon(RAID_ICON_MOON) == o) then
				target = o;
				targetInfo = info;
			elseif(
				(o.values[UNIT_FIELD_HEALTH] == o.values[UNIT_FIELD_MAXHEALTH]) and
				(raidTargetByIcon(RAID_ICON_SKULL) ~= o) and
				(raidTargetByIcon(RAID_ICON_SQUARE) ~= o) and
				(raidTargetByIcon(RAID_ICON_MOON) ~= o) and
				(not isTargetOfPartyMember(o)) and
				((not targetInfo) or
					((targetInfo.rank == CREATURE_ELITE_NORMAL) and (info.rank ~= CREATURE_ELITE_NORMAL))
				))
			then
				target = o;
				targetInfo = info;
			end
		end
		count = count + 1;
	end
	if(target and count > 1) then
		STATE.ccTarget = target;
		STATE.ccSpell.goCallback = function()
			target.bot.ccTime = realTime;
		end
		return doSpell(false, realTime, target, STATE.ccSpell);
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
		if(info and enemyFilter(info) and (raidTargetByIcon(RAID_ICON_MOON) ~= o)) then
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
		return doSpell(false, realTime, target, s);
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

function shootSpell()
	-- if we have a ranged weapon equipped
	-- and a spell requires it, then
	-- that spell is our Shoot spell.
	local rangedWeaponGuid = equipmentInSlot(EQUIPMENT_SLOT_RANGED);
	if(not rangedWeaponGuid) then return nil; end
	local proto = itemProtoFromId(itemIdOfGuid(rangedWeaponGuid));
	for id,s in pairs(STATE.attackSpells) do
		if(s.EquippedItemClass == ITEM_CLASS_WEAPON and
			proto and
			bit32.btest(s.EquippedItemSubClassMask, 2 ^ proto.subClass))
		then
			return s;
		end
	end
	return nil;
end

-- find the Charge spell with the lowest cooldown that is immediately castable.
local function getChargeSpell(realTime)
	local best = nil;
	--sLog = true;
	for id,s in pairs(STATE.chargeSpells) do
		--print("getChargeSpell", s.name);
		if(not canCastIgnoreStance(s, realTime)) then goto continue; end
		if(not best) then
			best = s;
		elseif(s.CategoryRecoveryTime < best.CategoryRecoveryTime) then
			best = s;
		end
		::continue::
	end
	--sLog = false;
	--print("result:", tostring(best and best.name));
	return best;
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
			if(doSpell(false, realTime, enemy, shootSpell())) then
				return true;
			else
				-- then run to leader.
				goToPullPosition(realTime);
				return true;
			end
		end

		-- if we do have it or can't cast it, Charge!
		local chargeSpell = getChargeSpell(realTime);
		if(chargeSpell) then
			chargeSpell.goCallback = function()
				print("Charge complete, position updated.");
				STATE.my.location.position = contactPoint(STATE.my.location.position,
					enemy.location.position, MELEE_DIST);
			end
			if(doStanceSpell(realTime, chargeSpell, enemy)) then
				print("Charged!");
				return true;
			end
		end
		-- if we couldn't cast Charge, we'll just run in, the normal way.
	end

	-- wait for enemy to arrive.
	local dist = distanceToObject(enemy);
	if(STATE.raidIcons[RAID_ICON_SQUARE] == enemy.guid) then
		if(dist > MELEE_RANGE) then
			goToPullPosition(realTime);
			return true;
		end
	end

	-- if we're still in Battle Stance, do Thunder Clap.
	-- TODO: move closer to enemies.
	--sLog = true;
	if(STATE.pbAoeSpell and canCast(STATE.pbAoeSpell, realTime) and dist < MELEE_RANGE) then
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
	--sLog = true;
	if(doStanceSpell(realTime, STATE.sunderSpell, enemy)) then return true; end
	sLog = false;
	--[[	-- aura detection seems broken.
	if(not hasAura(STATE.me, STATE.blockBuffSpell)) then
		if(doStanceSpell(realTime, STATE.blockBuffSpell)) then return true; end
	end
	--]]

	-- taunt someone, if we can and should.
	local target = chooseTankTarget();
	if(not target) then return false; end
	if(doStanceSpell(realTime, STATE.tauntSpell, target)) then return true; end
	return false;
end

local function mainTankTarget()
	if(not STATE.mainTank) then return nil; end
	return unitTarget(STATE.mainTank);
end

function raidTargetByIcon(iconId, needntBeEnemy)
	local guid = STATE.raidIcons[iconId]
	if(isValidGuid(guid)) then
		if(not needntBeEnemy and not STATE.enemies[guid]) then return false; end
		local o = STATE.knownObjects[guid];
		if(isAlly(o)) then return false; end
		return o;
	end
	return false;
end

-- Skull, Moon, Diamond
local function raidTarget()
	local o = raidTargetByIcon(RAID_ICON_SKULL);
	if(o) then return o; end
	o = raidTargetByIcon(RAID_ICON_SQUARE);
	if(o) then return o; end
	--o = raidTargetByIcon(RAID_ICON_MOON);
	--if(o and not(hasCrowdControlAura(o))) then return o; end
	o = raidTargetByIcon(RAID_ICON_DIAMOND);
	if(o and not(hasCrowdControlAura(o))) then return o; end
	return nil;
end

local function tankIsWarrior()
	if(not STATE.mainTank) then return false; end
	return class(STATE.mainTank) == CLASS_WARRIOR;
end

function hasSunder(o)
	return GetMaxNegativeAuraModifier(o, SPELL_AURA_MOD_RESISTANCE) ~= 0;
end

function chooseEnemy()
	-- if an enemy targets a party member, attack that enemy.
	-- if there are several enemies, pick any one.
	local enemy;
	for i,e in pairs(STATE.enemies) do
		if(not(hasCrowdControlAura(e))) then
			enemy = e;
			break;
		end
	end
	if(STATE.amTank) then
		enemy = raidTarget() or enemy;
		enemy = chooseTankTarget() or enemy;
	else
		-- focus on main tank's target, if any.
		enemy = raidTarget() or enemy;
		enemy = STATE.enemies[mainTankTarget()] or enemy;
		-- if enemy is attacking tank but doesn't have sunder yet, don't attack.
		if(enemy and PERMASTATE.eliteCombat and
			tankIsWarrior() and (not hasSunder(enemy)) and
			unitTarget(enemy) == STATE.mainTank.guid)
		then
			enemy = false;
		end
	end
	return enemy;
end

function doInterrupt(realTime)
	if(not STATE.interruptSpell) then return false; end
	if(not canCastIgnoreGcd(STATE.interruptSpell, realTime, false)) then return false; end
	for guid,enemy in pairs(STATE.enemies) do
		local s = enemy.bot.casting;
		if(s and bit32.btest(s.InterruptFlags, SPELL_INTERRUPT_FLAG_INTERRUPT) and
			(s.PreventionType == SPELL_PREVENTION_TYPE_SILENCE))
		then
			return doSpell(false, realTime, enemy, STATE.interruptSpell);
		end
	end
	return false;
end

local function matchDispel(realTime, o, s, enemy)
	if(not o) then return false; end
	local res = false;
	investigateAuras(o, function(aura, level)
		for i, e in ipairs(s.effect) do
			if(e.id == SPELL_EFFECT_DISPEL) then
				local effectMask;
				if(e.miscValue == DISPEL_ALL) then
					effectMask = 0x1E;
				else
					effectMask = 2^e.miscValue;
				end
				if(bit32.btest(2^aura.Dispel, effectMask) and
					(aura.id ~= 6819) and	-- Corrupted Stamina. Small effect, continually reapplies itself.
					(enemy == isPositiveAura(aura)))
				then
					objectNameQuery(o, function(name)
						print("dispelling "..aura.name.." ("..aura.id..") from "..name);
					end);
					res = doSpell(false, realTime, o, s);
					return false;
				end
			end
		end
	end);
	return res;
end

-- for each ally, check if they have any auras this spell can dispel.
local function friendlyDispel(s, realTime)
	if(not canCastIgnoreGcd(s, realTime, false)) then return false; end
	if(matchDispel(realTime, STATE.me, s, false)) then
		return true;
	end
	for i,m in ipairs(STATE.groupMembers) do
		local o = STATE.knownObjects[m.guid];
		if(matchDispel(realTime, o, s, false)) then
			return true;
		end
	end
	return false;
end

local function enemyDispel(s, realTime)
	if(not canCastIgnoreGcd(s, realTime, false)) then return false; end
	for guid,o in pairs(STATE.enemies) do
		if(matchDispel(realTime, o, s, true)) then
			return true;
		end
	end
	return false;
end

function doDispel(realTime)
	for id,s in pairs(STATE.friendDispelSpells) do
		if(friendlyDispel(s, realTime)) then return true; end
	end
	for id,s in pairs(STATE.enemyDispelSpells) do
		if(enemyDispel(s, realTime)) then return true; end
	end
	return false;
end

function doAoeAttack(realTime, singleTargetSpell)
	if(PERMASTATE.eliteCombat) then return false; end
	-- Find our best AoE spell.
	local s = mostEffectiveSpell(realTime, STATE.aoeAttackSpells, true);
	if(not s) then return false; end
	-- Count enemies.
	local count = 0;
	for guid,o in pairs(STATE.enemies) do
		count = count + 1;
	end
	-- If there aren't enough enemies to make the AoE spell more efficient, skip it.
	if(s.ppc * count < singleTargetSpell.ppc) then return false; end
	-- If there are, check which ones are close enough together
	-- that the AoE spell will hit as many as possible.

	local radius = cSpellRadius(s.effect[1].radiusIndex).radius;

	-- This is an NP-complete problem of complexity O((n+1)!).
	-- Given that we may face up to 20 enemies at once, attempting a complete solution would be useless.
	-- Instead, test the positions of each of our allies. This will take O(n*m) and,
	-- given that at least one ally is human, should give us a decent result.
	local target
	local targetCount = 0
	for i,m in ipairs(STATE.groupMembers) do
		local o = STATE.knownObjects[m.guid];
		if(o) then
			local c = 0
			for guid,e in pairs(STATE.enemies) do
				if(distance3(o.location.position, e.location.position) < radius) then
					c = c + 1
				end
			end
			if(c > targetCount) then
				target = o;
				targetCount = c;
			end
		end
	end
	if(s.ppc * targetCount < singleTargetSpell.ppc) then return false; end

	-- Go to ally and cast spell.
	return doSpell(false, realTime, target, s, 1);
end

function doAoeHeal(realTime, singleTargetSpell, singleTargetPoints)
	-- Find our best AoE spell.
	local s, aoePoints = mostEffectiveSpell(realTime, STATE.aoeHealSpells, true);
	if(not s) then return false; end

	local radius = cSpellRadius(s.effect[1].radiusIndex).radius;

	-- Figure out how much the AoE spell would heal, given optimum position.
	local target
	local healAmountForTarget = 0
	local nearbyAllies
	for i,m in ipairs(STATE.groupMembers) do
		local o = STATE.knownObjects[m.guid];
		if(o) then
			local amount = 0
			local allies = {}
			for j,n in pairs(STATE.groupMembers) do
				local p = STATE.knownObjects[n.guid];
				if(p and distance3(o.location.position, p.location.position) < radius) then
					local maxHealth = p.values[UNIT_FIELD_MAXHEALTH];
					local health = p.values[UNIT_FIELD_HEALTH];
					-- don't bother healing the dead.
					if(health > 1) then
						amount = amount + math.min(maxHealth - health, aoePoints);
						allies[o.guid] = o;
					end
				end
			end
			if(amount > healAmountForTarget) then
				target = o;
				healAmountForTarget = amount;
				nearbyAllies = allies;
			end
		end
	end
	if(healAmountForTarget < singleTargetPoints) then return false; end

	s.goCallback = function()
		for guid,o in pairs(nearbyAllies) do
			o.values[UNIT_FIELD_HEALTH] = o.values[UNIT_FIELD_HEALTH] + aoePoints;
		end
	end

	-- Go to ally and cast spell.
	return doSpell(false, realTime, target, s, 1);
end

-- these buffs can last until the end of combat.
-- we need statistics on our own attacks to determine their value.
-- but for now, we'll force-apply them every time we don't have them up.
local selfCombatBuffEffects = {
	[SPELL_AURA_MOD_ATTACKSPEED]=true,
	[SPELL_AURA_MOD_MELEE_HASTE]=true,
	[SPELL_AURA_MOD_DAMAGE_DONE]=true,
}

function doSelfCombatBuff(realTime, singleTargetSpell)
	local estimatedCombatTimeRemaining =
		STATE.currentCombatRecord.sumEnemyHealth / STATE.averageGroupDps;
	-- this seems way too simple. :}
	if(not STATE.me) then return false; end
	if(doBuffSingle(STATE.me, realTime, STATE.selfBuffSpells)) then return true; end
	return false;
end
