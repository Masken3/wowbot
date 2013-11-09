function investigateAuras(target, f)
	for i=0,(MAX_AURAS-1) do
		local spellId = target.values[UNIT_FIELD_AURA + i];
		local s;
		if(spellId) then s = cSpell(spellId); end
		if(s) then
			local level = target.values[UNIT_FIELD_AURALEVELS + math.floor(i/4)]
			level = bit32.extract(level, bit32.band(i, 3) * 8, 8);
			local res = f(s, level);
			if(res == false) then return false; end
		end
	end
end

function investigateAuraEffects(target, f)
	investigateAuras(target, function(s, level)
		for i, e in ipairs(s.effect) do
			if((e.id == SPELL_EFFECT_APPLY_AURA)) then
				local res = f(e, level);
				if(res == false) then return false; end
			end
		end
	end)
end

function hasAura(target, spellId)
	for i=0,(MAX_AURAS-1) do
		local auraSpellId = target.values[UNIT_FIELD_AURA + i];
		if(auraSpellId == spellId) then
			return true;
		end
	end
	return false;
end

function hasAnyAura(target, spells)
	for i=0,(MAX_AURAS-1) do
		local auraSpellId = target.values[UNIT_FIELD_AURA + i];
		if(spells[auraSpellId]) then
			return true;
		end
	end
	return false;
end

function GetMaxNegativeAuraModifier(target, auraType)
	local modifier = 0;
	investigateAuraEffects(target, function(e, level)
		if(e.applyAuraName == auraType) then
			modifier = math.min(modifier, calcAvgEffectPoints(level, e));
		end
	end)
	return modifier;
end

function GetMaxPositiveAuraModifier(target, auraType)
	local modifier = 0;
	investigateAuraEffects(target, function(e, level)
		if(e.applyAuraName == auraType) then
			modifier = math.max(modifier, calcAvgEffectPoints(level, e));
		end
	end)
	return modifier;
end

function GetMaxPositiveAuraModifierWithMisc(target, auraType, miscValue)
	local modifier = 0;
	investigateAuraEffects(target, function(e, level)
		--print(e.applyAuraName, e.miscValue)
		if(e.applyAuraName == auraType and e.miscValue == miscValue) then
			modifier = math.max(modifier, calcAvgEffectPoints(level, e));
		end
	end)
	return modifier;
end

function GetMaxPassiveAuraModifierWithMisc(auraType, miscValue)
	local modifier = 0;
	for id, s in pairs(STATE.knownSpells) do
		local level = spellLevel(s);
		for i,e in ipairs(s.effect) do
			if(e.applyAuraName == auraType and e.miscValue == miscValue) then
				modifier = math.max(modifier, calcAvgEffectPoints(level, e));
			end
		end
	end
	return modifier;
end

function hSMSG_SET_EXTRA_AURA_INFO(p)
	--print("SMSG_SET_EXTRA_AURA_INFO", dump(p));
	if(STATE.stealthSpell and (p.spellId == STATE.stealthSpell.id)) then
		print("We're stealthed!");
		STATE.stealthed = true;
	end
end

function auraLoginComplete()
	if(STATE.stealthSpell and hasAura(STATE.me, STATE.stealthSpell.id)) then
		STATE.stealthed = true;
		print("We're stealthed!");
	end
end

local function negativeEffect(e)
	return e.basePoints < 0;
end

local function positiveEffect(e)
	return e.basePoints > 0;
end

local function alwaysPositive(e)
	return true;
end

local function alwaysNegative(e)
	return false;
end

local negativeMechanicImmunities = {
	[MECHANIC_BANDAGE] = true,
	[MECHANIC_SHIELD] = true,
	[MECHANIC_MOUNT] = true,
	[MECHANIC_INVULNERABILITY] = true,
}

local function modEffect(e)
	if(e.miscValue == SPELLMOD_COST) then
		return negativeEffect(e);
	else
		error("Unknown mod effect "..e.miscValue);
	end
end

local auraEffectIsPositiveTable = {
	[SPELL_AURA_MOD_DAMAGE_DONE] = positiveEffect,
	[SPELL_AURA_MOD_RESISTANCE] = positiveEffect,
	[SPELL_AURA_MOD_STAT] = positiveEffect,
	[SPELL_AURA_MOD_SKILL] = positiveEffect,
	[SPELL_AURA_MOD_DODGE_PERCENT] = positiveEffect,
	[SPELL_AURA_MOD_HEALING_PCT] = positiveEffect,
	[SPELL_AURA_MOD_HEALING_DONE] = positiveEffect,
	[SPELL_AURA_MOD_SPELL_CRIT_CHANCE] = positiveEffect,
	[SPELL_AURA_MOD_INCREASE_HEALTH_PERCENT] = positiveEffect,
	[SPELL_AURA_MOD_DAMAGE_PERCENT_DONE] = positiveEffect,
	[SPELL_AURA_MOD_ATTACK_POWER] = positiveEffect,
	[SPELL_AURA_PERIODIC_ENERGIZE] = positiveEffect,
	[SPELL_AURA_MOD_CASTING_SPEED_NOT_STACK] = positiveEffect,
	[SPELL_AURA_MOD_RESISTANCE_PCT] = positiveEffect,
	[SPELL_AURA_PERIODIC_HEAL] = positiveEffect,
	[SPELL_AURA_MOD_MANA_REGEN_INTERRUPT] = positiveEffect,

	[SPELL_AURA_MOD_DAMAGE_TAKEN] = negativeEffect,

	-- always positive
	[SPELL_AURA_ADD_TARGET_TRIGGER] = alwaysPositive,
	[SPELL_AURA_SCHOOL_IMMUNITY] = alwaysPositive,

	-- always negative?
	[SPELL_AURA_MOD_STUN] = alwaysNegative,
	[SPELL_AURA_MOD_PACIFY_SILENCE] = alwaysNegative,
	[SPELL_AURA_MOD_ROOT] = alwaysNegative,
	[SPELL_AURA_MOD_SILENCE] = alwaysNegative,
	[SPELL_AURA_PERIODIC_LEECH] = alwaysNegative,
	[SPELL_AURA_MOD_STALKED] = alwaysNegative,
	[SPELL_AURA_PERIODIC_DAMAGE_PERCENT] = alwaysNegative,
	[SPELL_AURA_PERIODIC_DAMAGE] = alwaysNegative,
	[SPELL_AURA_MOD_DECREASE_SPEED] = alwaysNegative,
	[SPELL_AURA_TRANSFORM] = alwaysNegative,
	[SPELL_AURA_MOD_CONFUSE] = alwaysNegative,
	[SPELL_AURA_MOD_FEAR] = alwaysNegative,
	[SPELL_AURA_PREVENTS_FLEEING] = alwaysNegative,
	[SPELL_AURA_PROC_TRIGGER_DAMAGE] = alwaysNegative,

	-- neither positive or negative.
	[SPELL_AURA_DUMMY] = function(e) return nil; end,
	[SPELL_AURA_PROC_TRIGGER_SPELL] = function(e) return nil; end,
	[SPELL_AURA_PERIODIC_TRIGGER_SPELL] = function(e) return nil; end,

	[SPELL_AURA_MECHANIC_IMMUNITY] = function(e)
		return not negativeMechanicImmunities[e.miscValue];
	end,
	[SPELL_AURA_ADD_FLAT_MODIFIER] = modEffect,
	[SPELL_AURA_ADD_PCT_MODIFIER] = modEffect,
};

function isPositiveAura(s)
	if(bit32.btest(s.AttributesEx, SPELL_ATTR_EX_NEGATIVE)) then return false; end
	-- assuming here that if the spell has at least one positive effect, it's good.
	local hasPositiveEffect = false;
	for i, e in ipairs(s.effect) do
		if(e.id == SPELL_EFFECT_APPLY_AURA) then
			local f = auraEffectIsPositiveTable[e.applyAuraName]
			if(not f) then
				error("Unhandled aura "..e.applyAuraName);
			end
			local res = f(e);
			if(res == true) then
				hasPositiveEffect = true;
			elseif((res ~= false) and (hasPositiveEffect ~= true)) then
				hasPositiveEffect = res;
			end
		end
	end
	return hasPositiveEffect;
end
