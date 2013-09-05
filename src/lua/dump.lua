function string.endWith(s, o)
	return s:sub(-#o) == o;
end

function countTable(tab)
	local c = 0;
	for _ in pairs(tab) do c = c + 1; end
	return c;
end

function dump(o)
	if type(o) == 'table' then
		local s = '{'
		for k,v in pairs(o) do
			local vs;
			if(type(k) == 'string' and (k == "guid" or k:endWith('Guid'))) then
				vs = v:hex();
			else
				vs = dump(v);
			end
			s = s..' ['..k..']'..'='..vs..','
		end
		return s..'}'
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
	local s = '{'
	for k,v in pairs(o) do
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
