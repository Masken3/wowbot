--todo: fix negative bonuses.
function skillLevel(skillId)
	for idx=PLAYER_SKILL_INFO_1_1,(PLAYER_SKILL_INFO_1_1+384),3 do
		if(STATE.my.values[idx] and bit32.band(STATE.my.values[idx], 0xFFFF) == skillId) then
			return skillLevelByIndex(idx);
		end
	end
	return nil;
end

function skillIndex(skillId)
	for idx=PLAYER_SKILL_INFO_1_1,(PLAYER_SKILL_INFO_1_1+384),3 do
		if(STATE.my.values[idx] and bit32.band(STATE.my.values[idx], 0xFFFF) == skillId) then
			return idx;
		end
	end
	return nil;
end

function skillLevelByIndex(idx)
	if(not STATE.my.values[idx+1]) then return nil; end
	local value = bit32.band(STATE.my.values[idx+1], 0xFFFF);	-- base value
	local bonus = STATE.my.values[idx+2];
	if(bonus) then
		value = value + bit32.band(bonus, 0xFFFF) +	-- temp bonus
			bit32.extract(bonus, 16, 16);	-- perm bonus
	end
	local max = bit32.extract(STATE.my.values[idx+1], 16, 16)
	return value, max;
end

function spellSkillLevel(spellId)
	local skillId = skillIdBySpell(spellId);
	if(not skillId) then return nil; end
	return skillLevel(skillId);
end

function skillIdBySpell(spellId)
	local sla = cSkillLineAbilityBySpell(spellId);
	if(not sla) then return nil; end
	return sla.skill;
end
