do
	-- lock down the Global table, to catch undefined variable reading.
	-- this code must appear last.
	local mt = getmetatable(_G) or {}
	mt.__index = function(t,k)
		error("attempt to access an undefined variable: "..k, 2)
	end
	setmetatable(_G, mt)
end
