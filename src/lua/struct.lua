
Struct = {
new = function(members)
	local m = {}
	--print(dump(members))
	for i, v in pairs(members) do
		m[v] = true
	end
	--print(dump(m))
	local meta = {
		__metatable = "protected",
		__newindex = function(t, k, v)
			local meta = getmetatable(t);
			if(m[k]) then
				rawset(t, k, v);
			else
				error(k.." is not a valid member.");
			end
		end,
	}
	local struct = {
		new = function()
			local instance = {}
			setmetatable(instance, meta);
			return instance;
		end
	}
	return struct;
end,
}

-- test
if(false) then
	Position = Struct.new({'x', 'y', 'z'})

	p = Position.new()
	p.x = 0;
	p.v = 1;

	error("Shouldn't be here...");
end
