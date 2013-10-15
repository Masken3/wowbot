
bit32 = require("bit")

function bit32.btest(a, b)
	return bit32.band(a, b) ~= 0
end

function bit32.extract(n, field, width)
	width = width or 1
	assert(width > 0 and width <= 32)
	assert(field >= 0 and field < 32)
	assert(field + width <= 32)
	local s = bit32.rshift(n, field)
	local mask = (2^(width))-1
	local res = bit32.band(s, mask)
	--print("extract", hex(n), field, width, hex(s), hex(mask), hex(res))
	return res
end
