
function makeReadOnly(t)
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = v
	end
	local mt = {       -- create metatable
		__index = copy,
		__pairs = function()
			return pairs(copy)
		end,
		__newindex = function (t,k,v)
			error("attempt to update a read-only table", 2)
		end,
	}
	setmetatable(t, mt)
end

Struct = {
new = function(members)
	local m = members
	makeReadOnly(m)
	--print(dump(m))
	local struct = {
		new = function(a)
			--print("m"..dump(m));
			--print("a"..dump(a));
			local proxy = {}
			local instance = {}
			local meta = {
				-- with a read-only metatable, we can compare structs and get the types of instances,
				-- while keeping the members table safe from modification.
				-- this also prevents access to this metatable.
				__metatable = m,
				__index = function(t, k)
					assert(t == proxy);
					local v = instance[k];
					if(v == nil) then
						--error(k.." is not set", 2);
					end
					return v;
				end,
				__pairs = function()
					return pairs(instance);
				end,
				__newindex = function(t, k, v)
					assert(t == proxy);
					local meta = getmetatable(t);
					local memberType = m[k]
					if(not memberType) then
						error(k.." is not a valid member.", 2);
					end
					if(type(memberType) == 'table') then
						--print(dump(memberType));
						memberType = memberType.members;
					end
					if(type(v) == 'table' and memberType ~= 'table') then
						local metaV = getmetatable(v)
						if(memberType ~= metaV) then
							error(k.." has wrong type: "..dump(metaV)..". "..dump(memberType).." needed.", 2)
						end
					elseif(memberType ~= type(v)) then
						error(k.." has wrong type: "..type(v)..". "..dump(memberType).." needed.", 2)
					end
					instance[k] = v;
				end,
			}
			setmetatable(proxy, meta);
			if(a) then
				for k,v in pairs(a) do
					proxy[k] = v
				end
			end
			return proxy;
		end,
		members = m,
	}
	return struct;
end,
}

-- tests
if(false) then
	t = {x=0}
	t = readOnly(t);
	t.x = 1;
	t.y = 1;
end

if(false) then
Position = Struct.new{x='number', y='number', z='number'}
Location = Struct.new{mapId='number', position=Position, orientation='number'}
Movement = Struct.new{dx='number', dy='number', startTime='number'}
MovingObject = Struct.new{guid='string', location=Location, movement=Movement}

	p = Position.new()
	p.x = 0;

	l = Location.new()
	l.mapId = 1;
	l.position = p;
	l.position = Position.new{x=1, y=1, z=1};
	l.position.x = 2;
	print(l.position.x);
	print(dump(l.position));
	l.position = {x=0, y=0, z=0};
	l.position = 0;

	p.y = "foo";
	p.v = 1;

	error("Shouldn't be here...");
end
