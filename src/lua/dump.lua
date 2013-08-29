
function dump(o)
	if type(o) == 'table' then
		local s = '{ '
		for k,v in pairs(o) do
			if type(k) ~= 'number' then k = '"'..k..'"' end
			s = s .. '['..k..'] = ' .. dump(v) .. ','
		end
		return s .. '} '
	else
		return tostring(o)
	end
end

local function spacify(s, len)
	return s..string.rep(' ', len-#s)
end

local function spellEffectNames(s)
	local res = {};
	for i, e in ipairs(s.effect) do
		res[i] = spacify(cSpellEffectName(e.id), 15);
	end
	return (res);
end
