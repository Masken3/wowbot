
dofile("src/lua/dump.lua")
dofile("src/lua/timers.lua")
dofile("src/lua/struct.lua")
dofile("src/lua/movement.lua")
dofile("src/lua/decision.lua")

-- Position: x, y, z
-- Location: {mapId, position{x,y,z}, orientation}.
-- Movement: dx, dy, startTime.
-- MovingObject: guid, Location, Movement.
Position = Struct.new{x='number', y='number', z='number'}
Location = Struct.new{mapId='number', position=Position, orientation='number'}
Movement = Struct.new{dx='number', dy='number', startTime='number'}
MovingObject = Struct.new{guid='string', location=Location, movement=Movement}

if(STATE == nil) then
	STATE = {
		inGroup = false,
		leader = MovingObject.new{
			location=Location.new{position=Position.new()},
			movement=Movement.new(),
		},

		groupMembers = {},	-- set by hSMSG_GROUP_LIST.

		knownObjects = {},

		enemies = {},	-- key:guid. value:knownObject.

		reloadCount = 0,
		myGuid = '',	-- set by C function enterWorld.
		myLocation = Location.new(),	-- set by hSMSG_LOGIN_VERIFY_WORLD.
		moving = false,
		moveStartTime = 0,	-- floating point, in seconds. valid if moving == true.

		attackSpells = {},	-- Spells we know that are useful for attacking other creatures.
		meleeSpell = false,

		-- timer-related stuff
		timers = {},
		inTimerCallback = false,
		newTimers = {},
		removedTimers = {},
		callbackTime = 0,
	}
	-- type-securing STATE is too much work, but at least we can prevent unregistered members.
	local mt = {
		__index = "not implemented",
		__newindex = "no go",
	}
	setmetatable(STATE, mt);
else
	STATE.reloadCount = STATE.reloadCount + 1;
	print("STATE.reloadCount", STATE.reloadCount);
end

function hSMSG_MONSTER_MOVE(p)
	--print("SMSG_MONSTER_MOVE", dump(p));
end
function hMSG_MOVE_HEARTBEAT(p)
	print("MSG_MOVE_HEARTBEAT", dump(p));
end

function hSMSG_GROUP_INVITE(p)
	--print("SMSG_GROUP_INVITE", dump(p));
	if(STATE.inGroup) then
		send(CMSG_GROUP_DECLINE);
	else
		send(CMSG_GROUP_ACCEPT);
		STATE.inGroup = true;
	end
end
function hSMSG_GROUP_UNINVITE(p)
	print("SMSG_GROUP_UNINVITE");
	STATE.inGroup = false;
end
function hSMSG_GROUP_DESTROYED(p)
	print("SMSG_GROUP_DESTROYED");
	STATE.inGroup = false;
end
function hSMSG_GROUP_LIST(p)
	print("SMSG_GROUP_LIST", dump(p));
	STATE.leader.guid = p.leaderGuid;
	if(p.memberCount == 0) then
		STATE.inGroup = false;
		print("Group disbanded.");
	else
		STATE.inGroup = true;
		print("Group rejoined.");
		STATE.groupMembers = p.members;
	end
end

function hSMSG_LOGIN_VERIFY_WORLD(p)
	print("SMSG_LOGIN_VERIFY_WORLD", dump(p));
	STATE.myLocation = p;
end

function hSMSG_COMPRESSED_UPDATE_OBJECT(p)
	--print("SMSG_COMPRESSED_UPDATE_OBJECT", dump(p));
	hSMSG_UPDATE_OBJECT(p);
end
function hSMSG_UPDATE_OBJECT(p)
	--print("SMSG_UPDATE_OBJECT", dump(p));
	-- todo: get notified when someone is in combat with a party member.
	for i,b in ipairs(p.blocks) do
		if(b.type == UPDATETYPE_OUT_OF_RANGE_OBJECTS) then
			for j,guid in ipairs(b.guids) do
				STATE.knownObjects[guid] = nil;
			end
		elseif(b.type == UPDATETYPE_CREATE_OBJECT or b.type == UPDATETYPE_CREATE_OBJECT2) then
			local o = {}
			updateValues(o, b);
			updateMovement(o, b);
			STATE.knownObjects[b.guid] = o;
		elseif(b.type == UPDATETYPE_VALUES) then
			updateValues(STATE.knownObjects[b.guid], b);
		elseif(b.type == UPDATETYPE_MOVEMENT) then
			updateMovement(STATE.knownObjects[b.guid], b);
		else
			error("Unknown update type "..b.type);
		end
		--UNIT_FIELD_TARGET
	end
	decision();
end
function updateValues(o, b)
	local j = 1;
	-- first write the values
	for i, m in ipairs(b.updateMask) do
		for k=0,31 do
			if(bit32.extract(m, k) ~= 0) then
				o.values[1+k+(i-1)*32] = b.values[j];
				j = j+1;
			end
		end
	end
	-- then react to updates
	for i, m in ipairs(b.updateMask) do
		for k=0,31 do
			if(bit32.extract(m, k) ~= 0) then
				local idx = 1+k+(i-1)*32;
				valueUpdated(o, idx);
			end
		end
	end
end
-- may need reversing.
function bit32.bytes(x)
	return bit32.extract(x,0,8),bit32.extract(x,8,8),bit32.extract(x,16,8),bit32.extract(x,24,8)
end
local guidFromValues(o, idx)
	return string.char(bit32.bytes(o.values[idx]), bit32.bytes(o.values[idx+1]))
end
-- returns true iff o is a member of my group.
local function isGroupMember(o)
	for i,m in ipairs(STATE.members) do
		if(m.guid == o.guid) then
			return true
		end
	end
	return false;
end
-- returns true iff o is a member of my group, or a pet or summon belonging to a member.
local function isAlly(o)
	return isGroupMember(o) or isGroupMember(guidFromValues(o, UNIT_FIELD_SUMMONEDBY));
end
local function valueUpdated(o, idx)
	if(idx == UNIT_FIELD_TARGET and not isAlly(o)) then
		-- if a non-ally targets an ally, they become an enemy.
		if(isAlly(guidFromValues(o, idx))) then
			STATE.enemies[o.guid] = o;
		end
	end
	if(idx == UNIT_NPC_FLAGS) then
		local flags = o.values[idx];
	end
end

function updateMovement(o, b)
	o.movement = b;
end

local SPELL_ATTACK_EFFECTS = {
	SPELL_EFFECT_WEAPON_DAMAGE_NOSCHOOL=true,
	SPELL_EFFECT_FORCE_CRITICAL_HIT=true,
	SPELL_EFFECT_GUARANTEE_HIT=true,
	SPELL_EFFECT_WEAPON_DAMAGE=true,	--?
	SPELL_EFFECT_ATTACK=true,
	SPELL_EFFECT_ADD_COMBO_POINTS=true,
	SPELL_EFFECT_SCHOOL_DAMAGE=true,
	SPELL_EFFECT_ADD_EXTRA_ATTACKS=true,
	SPELL_EFFECT_ENVIRONMENTAL_DAMAGE=true,	--?
}

function hSMSG_INITIAL_SPELLS(p)
	print("SMSG_INITIAL_SPELLS", dump(p));
	for i,id in ipairs(p.spells) do
		local s = cSpell(id);
		print(id, spacify(s.name, 23), spacify(s.rank, 15), unpack(spellEffectNames(s)));
		for i, e in ipairs(s.effect) do
			if(SPELL_ATTACK_EFFECTS[e.id]) then
				STATE.attackSpells[id] = s
			end
			if(e.id == SPELL_EFFECT_ATTACK) then
				-- assuming that there's only one melee spell
				assert(not STATE.meleeSpell);
				STATE.meleeSpell = id;
			end
		end
	end
end

function castSpell(spellId, target)
	local data = {
		spellId = spellId,
		targetFlags = TARGET_FLAG_UNIT,
		unitTarget = target.guid,
	}
	send(CMSG_CAST_SPELL, data);
end
