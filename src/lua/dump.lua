
function dump(o)
	if type(o) == 'table' then
		local s = '{ '
		for k,v in pairs(o) do
			if type(k) ~= 'number' then k = '"'..k..'"' end
			s = s .. '['..k..'] = ' .. dump(v) .. ','
		end
		return s .. '} '
	elseif type(o) == 'number' then
		if(math.floor(o) == o) then
			return tostring(o);
		else
			return string.format("%.1f", o)
		end
	else
		return tostring(o)
	end
end

function dumpKeys(o)
	local s = '{ '
	for k,v in pairs(o) do
		if type(k) ~= 'number' then k = '"'..k..'"' end
		s = s .. '['..k..'],'
	end
	return s .. '} '
end

function spacify(s, len)
	return s..string.rep(' ', len-#s)
end

function spellEffectNames(s)
	local res = {};
	for i, e in ipairs(s.effect) do
		res[i] = spacify(e.id.." "..cSpellEffectName(e.id), 15);
	end
	return (res);
end

function string.hex(s)
	return string.format(string.rep("%02X", #s), s:byte(1, #s));
end

function hex(n)
	return string.format("%X", n);
end
