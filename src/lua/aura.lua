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
