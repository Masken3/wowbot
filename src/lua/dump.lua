
if(not rawget(_G, 'oldPrint')) then oldPrint = print end

function print(...)
	local s = rawget(_G, 'STATE')
	local str = ''
	if(s) then str = str..STATE.myClassName..": " end
	local arg = {...}
	for i,v in ipairs(arg) do
		if(i > 1) then
			str = str.."\t"
		end
		str = str..tostring(v)
	end
	oldPrint(str)
end

function string.endWith(s, o)
	return s:sub(-#o) == o;
end

function string.startWith(s, o)
	return s:sub(1, #o) == o;
end

function countTable(tab)
	local c = 0;
	for _ in pairs(tab) do c = c + 1; end
	return c;
end

local dumpedTables
function dump(o, level)
	if(not level) then
		dumpedTables = {
			[_G]=true,
		}
		level = 0
	end
	if type(o) == 'table' then
		if(dumpedTables[o]) then
			return tostring(o);
		end
		dumpedTables[o] = true;
		local s = '{'
		for k,v in pairs(o) do
			local vs;
			if(type(v) == 'string' and type(k) == 'string' and (k == "guid" or k:endWith('Guid'))) then
				vs = v:hex();
			elseif(k == 'loaded') then
				vs = tostring(v);
			else
				vs = dump(v, level + 1);
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
