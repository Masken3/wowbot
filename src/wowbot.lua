do
	-- lock down the Global table, to catch undefined variable reading.
	-- this code must appear last.
	local mt = getmetatable(_G) or {}
	mt.__index = function(t,k)
		error("attempt to access an undefined variable: "..k, 2)
	end
	setmetatable(_G, mt)
end

SUBFILES = {
	'dump.lua',
	'timers.lua',
	'struct.lua',
	'movement.lua',
	'decision.lua',
	'chat.lua',
	'quests.lua',
	'item.lua',
}
for i,f in ipairs(SUBFILES) do
	dofile('src/lua/'..f)
end

-- Position: x, y, z
-- Location: {mapId, position{x,y,z}, orientation}.
-- Movement: dx, dy, startTime.
-- MovingObject: guid, Location, Movement.
Position = Struct.new{x='number', y='number', z='number'}
Location = Struct.new{mapId='number', position=Position, orientation='number'}
Movement = Struct.new{dx='number', dy='number', startTime='number'}
MovingObject = Struct.new{guid='string', location=Location, movement=Movement}

-- values is an int-key table. See UpdateFields.h for a list of keys.
-- bot is for storing our own data concerning this object.
-- updateValuesCallbacks are called after receiving SMSG_UPDATE_OBJECT regarding this object.
KnownObject = Struct.new{guid='string', values='table', monsterMovement='table',
	location=Location, movement=Movement, bot='table', updateValuesCallbacks='table'}

if(rawget(_G, 'STATE') == nil) then
	STATE = {
		inGroup = false,
		leader = MovingObject.new{
			location=Location.new{position=Position.new()},
			movement=Movement.new(),
		},

		groupMembers = {},	-- set by hSMSG_GROUP_LIST.

		knownObjects = {},

		-- key:guid. value:knownObject from knownObjects.
		enemies = {},
		questGivers = {},
		questFinishers = {},

		checkNewObjectsForQuests = false,	-- set to true after login.

		reloadCount = 0,
		myGuid = '',	-- set by C function enterWorld.
		myLevel = 0,	-- set by C function enterWorld.
		myLocation = Location.new(),	-- set by hSMSG_LOGIN_VERIFY_WORLD.
		my = false,	-- KnownObject.
		me = false,	-- == my.
		moving = false,
		moveStartTime = 0,	-- floating point, in seconds. valid if moving == true.

		myTarget = false,	-- guid of my target.

		attackSpells = {},	-- Spells we know that are useful for attacking other creatures.
		meleeSpell = false,
		attacking = false,
		meleeing = false,

		-- key: id. value: table. All the spells we know.
		knownSpells = {},

		-- set of itemIds that we need data for.
		itemProtosWaiting = {},

		-- key: id. value: table.
		itemProtos = {},

		-- key: parameter. value: function.
		-- they will be called when itemDataWaiting is empty.
		itemDataCallbacks = {},

		tradeGiveAll = false,
		recreate = false,

		-- timer-related stuff
		timers = {},
		inTimerCallback = false,
		newTimers = {},
		removedTimers = {},
		callbackTime = 0,
	}
	-- type-securing STATE is too much work, but at least we can prevent unregistered members.
	local mt = {
		__index = function(t, k)
			error("STATE."..k.." does not exist.");
		end,
		__newindex = function(t, k)
			error("STATE."..k.." must not exist.");
		end,
	}
	setmetatable(STATE, mt);
else
	STATE.reloadCount = STATE.reloadCount + 1;
	print("STATE.reloadCount", STATE.reloadCount);
end

local updateMonsterPosition;

function hSMSG_MONSTER_MOVE(p)
	--print("SMSG_MONSTER_MOVE", dump(p));
	local o = STATE.knownObjects[p.guid];
	if(not o) then return; end
	o.monsterMovement = p;
	o.location.position = Position.new(p.point);
	if(p.type == MonsterMoveFacingAngle) then
		o.location.orientation = p.angle;
	end
	if(not o.movement) then o.movement = Movement.new(); end
	local mov = o.movement;
	mov.dx = 0;
	mov.dy = 0;
	if(p.type == MonsterMoveStop) then return; end
	local dur = p.duration / 1000;
	-- save destination in unused key "dst".
	if(p.count) then
		assert(p.count <= 1);
		if(p.count == 0) then return; end
		-- todo: enable handling of more than 1 points.
		p.dst = p.points[1];
	else
		p.dst = p.destination;
	end
	mov.dx = (p.dst.x - p.point.x) / dur;
	mov.dy = (p.dst.y - p.point.y) / dur;
	mov.startTime = getRealTime();
	-- don't bother with timers; we can update all of them at decision time.
end

function updateMonsterPosition(realTime, o)
	--print("updateMonsterPosition", o.guid:hex());
	-- todo: enable handling of more than 1 points.
	local mm = o.monsterMovement;
	local mov = o.movement;
	local dst = mm.dst;
	if(not mm or not mov or not dst) then return; end
	local elapsedTime = realTime - mov.startTime;
	if(elapsedTime >= mm.duration / 1000) then
		o.location.position = Position.new(dst);
		mov.dx = 0;
		mov.dy = 0;
		return;
	else
		local pos = o.location.position;
		pos.x = pos.x + mov.dx * elapsedTime;
		pos.y = pos.y + mov.dy * elapsedTime;
		mov.startTime = realTime;
	end
end

function updateEnemyPositions(realTime)
	local c = 0;
	for guid, o in pairs(STATE.enemies) do
		updateMonsterPosition(realTime, o);
		c = c + 1;
	end
	if(c > 1) then
		print(c.." enemies.");
	end
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
		print("Group joined.");
		STATE.groupMembers = p.members;
		for i,m in ipairs(STATE.groupMembers) do
			print(m.guid:hex());
		end
	end
end

function hSMSG_LOGIN_VERIFY_WORLD(p)
	print("SMSG_LOGIN_VERIFY_WORLD", dump(p));
	STATE.myLocation = p;
	send(CMSG_QUESTGIVER_STATUS_MULTIPLE_QUERY);
end

function loginComplete()
	itemLoginComplete();
end

-- may need reversing.
function bit32.bytes(x)
	return bit32.extract(x,0,8),bit32.extract(x,8,8),bit32.extract(x,16,8),bit32.extract(x,24,8)
end

function guidFromValues(o, idx)
	local a = o.values[idx];
	local b = o.values[idx+1];
	if((not a) or (not b)) then return nil; end
	--print("guidFromValues", idx, a, b);
	local s = string.char(bit32.bytes(a)) .. string.char(bit32.bytes(b));
	--local s = string.format("%08X%08X", a, b);
	--print("guidFromValues", s);
	assert(#s == 8);
	--print("guidFromValues", s:hex());
	return s;
end

ZeroGuid = string.rep(string.char(0), 8);

function isValidGuid(g)
	if(not g) then return false; end
	return g ~= ZeroGuid;
end

-- returns true iff o is me or a member of my group.
local function isGroupMember(o)
	if(o.guid == STATE.myGuid) then return true; end
	if(not STATE.inGroup) then return false; end
	for i,m in ipairs(STATE.groupMembers) do
		if(m.guid == o.guid) then
			return true
		end
	end
	return false;
end

--[[
    bool IsEmpty()         const { return m_guid == 0; }
    bool IsCreature()      const { return GetHigh() == HIGHGUID_UNIT; }
    bool IsPet()           const { return GetHigh() == HIGHGUID_PET; }
    bool IsCreatureOrPet() const { return IsCreature() || IsPet(); }
    bool IsAnyTypeCreature() const { return IsCreature() || IsPet(); }
    bool IsPlayer()        const { return !IsEmpty() && GetHigh() == HIGHGUID_PLAYER; }
    bool IsUnit()          const { return IsAnyTypeCreature() || IsPlayer(); }
    bool IsItem()          const { return GetHigh() == HIGHGUID_ITEM; }
    bool IsGameObject()    const { return GetHigh() == HIGHGUID_GAMEOBJECT; }
    bool IsDynamicObject() const { return GetHigh() == HIGHGUID_DYNAMICOBJECT; }
    bool IsCorpse()        const { return GetHigh() == HIGHGUID_CORPSE; }
    bool IsTransport()     const { return GetHigh() == HIGHGUID_TRANSPORT; }
    bool IsMOTransport()   const { return GetHigh() == HIGHGUID_MO_TRANSPORT; }
--]]
local function isUnit(o)
	return bit32.btest(o.values[OBJECT_FIELD_TYPE], TYPEMASK_UNIT);
end

local function isSummonedByGroupMember(o)
	if(not o.values[UNIT_FIELD_SUMMONEDBY]) then return false; end
	local g = guidFromValues(o, UNIT_FIELD_SUMMONEDBY);
	return isGroupMember(STATE.knownObjects[g]);
end

-- returns true iff o is a member of my group (including me), or a pet or summon belonging to a member.
local function isAlly(o)
	if(not isUnit(o)) then return false; end
	return isGroupMember(o) or isSummonedByGroupMember(o);
end

local function valueUpdated(o, idx)
	if(not isUnit(o)) then return; end
	if(idx == UNIT_NPC_FLAGS) then
		local flags = o.values[idx];
	end
end
-- first write the values
local function updateValues(o, b)
	local j = 1;
	for i, m in ipairs(b.updateMask) do
		for k=0,31 do
			if(bit32.extract(m, k) ~= 0) then
				local idx = k+(i-1)*32;
				--print(idx, b.values[j]);
				assert(b.values[j] ~= nil);
				o.values[idx] = b.values[j];
				j = j+1;
			end
		end
	end
end
-- then react to updates
local function valuesUpdated(o, b)
	for i, m in ipairs(b.updateMask) do
		for k=0,31 do
			if(bit32.extract(m, k) ~= 0) then
				local idx = k+(i-1)*32;
				--print(idx, o.values[idx]);
				valueUpdated(o, idx);
			end
		end
	end
end

local function updateMovement(o, b)
	if(b.pos) then
		if(not o.location) then
			o.location = Location.new{mapId=STATE.myLocation.mapId};
		end
		o.location.position = Position.new(b.pos);
		o.location.orientation = b.orientation;
	end
end

function hSMSG_COMPRESSED_UPDATE_OBJECT(p)
	--print("SMSG_COMPRESSED_UPDATE_OBJECT", dump(p));
	hSMSG_UPDATE_OBJECT(p);
end
function hSMSG_UPDATE_OBJECT(p)
	--print("SMSG_UPDATE_OBJECT", dump(p));
	print("SMSG_UPDATE_OBJECT", #p.blocks);
	-- todo: get notified when someone is in combat with a party member.
	for i,b in ipairs(p.blocks) do
		if(b.type == UPDATETYPE_OUT_OF_RANGE_OBJECTS) then
			for j,guid in ipairs(b.guids) do
				STATE.knownObjects[guid] = nil;
			end
		elseif(b.type == UPDATETYPE_CREATE_OBJECT or b.type == UPDATETYPE_CREATE_OBJECT2) then
			local o = KnownObject.new{guid=b.guid, values={}, bot={}, updateValuesCallbacks={}}
			updateValues(o, b);
			updateMovement(o, b);
			STATE.knownObjects[b.guid] = o;

			if(b.guid == STATE.myGuid) then
				STATE.my = o;
				STATE.me = o;
				print("CreateObject me!");
			end

			-- player objects don't get the OBJECT_FIELD_TYPE update for some reason,
			-- so we'll roll our own.
			if(not o.values[OBJECT_FIELD_TYPE]) then
				local high = b.guid:sub(-2);
				if(high == string.rep(string.char(0), 2)) then
					o.values[OBJECT_FIELD_TYPE] = bit32.bor(TYPEMASK_PLAYER, TYPEMASK_UNIT);
				else
					error("Unknown highGuid");
				end
			end
			--print("CREATE_OBJECT", b.guid:hex(), hex(o.values[OBJECT_FIELD_TYPE]), dump(b.pos));
			--, dump(o.movement), dump(o.values));

			if(STATE.checkNewObjectsForQuests) then
				send(CMSG_QUESTGIVER_STATUS_QUERY, {guid=b.guid});
			end
		elseif(b.type == UPDATETYPE_VALUES) then
			updateValues(STATE.knownObjects[b.guid], b);
			if(STATE.checkNewObjectsForQuests) then
				send(CMSG_QUESTGIVER_STATUS_QUERY, {guid=b.guid});
			end
			if(b.guid == STATE.myGuid) then
				print("UpdateObject me!");
			end
			doCallbacks(STATE.knownObjects[b.guid].updateValuesCallbacks);
		elseif(b.type == UPDATETYPE_MOVEMENT) then
			updateMovement(STATE.knownObjects[b.guid], b);
			if(b.guid == STATE.myGuid) then
				print("UpdateMovement me!");
			end
		else
			error("Unknown update type "..b.type);
		end
		--UNIT_FIELD_TARGET
	end
	for i,b in ipairs(p.blocks) do
		if(b.updateMask and b.guid) then
			valuesUpdated(STATE.knownObjects[b.guid], b);
		end
	end
	decision(getRealTime());
end

local SPELL_ATTACK_EFFECTS = {
	[SPELL_EFFECT_WEAPON_DAMAGE_NOSCHOOL]=true,
	[SPELL_EFFECT_FORCE_CRITICAL_HIT]=true,
	[SPELL_EFFECT_GUARANTEE_HIT]=true,
	[SPELL_EFFECT_WEAPON_DAMAGE]=true,	--?
	[SPELL_EFFECT_ATTACK]=true,
	[SPELL_EFFECT_ADD_COMBO_POINTS]=true,
	[SPELL_EFFECT_SCHOOL_DAMAGE]=true,
	[SPELL_EFFECT_ADD_EXTRA_ATTACKS]=true,
	[SPELL_EFFECT_ENVIRONMENTAL_DAMAGE]=true,	--?
}

function hSMSG_INITIAL_SPELLS(p)
	--print("SMSG_INITIAL_SPELLS", dump(p));
	--print(dump(SPELL_ATTACK_EFFECTS));
	for i,id in ipairs(p.spells) do
		local s = cSpell(id);
		--print(id, spacify(s.name, 23), spacify(s.rank, 15), unpack(spellEffectNames(s)));
		for i, e in ipairs(s.effect) do
			--print(e.id, SPELL_ATTACK_EFFECTS[e.id]);
			if(SPELL_ATTACK_EFFECTS[e.id]) then
				STATE.attackSpells[id] = s;
			end
			if(e.id == SPELL_EFFECT_ATTACK) then
				-- assuming that there's only one melee spell
				assert(not STATE.meleeSpell);
				print("Melee spell:", id);
				STATE.meleeSpell = id;
			end
		end
		STATE.knownSpells[id] = s;
	end
	print("Found "..dumpKeys(STATE.attackSpells).." attack spells.");
end

function castSpell(spellId, target)
	local data = {
		spellId = spellId,
		targetFlags = TARGET_FLAG_UNIT,
		unitTarget = target.guid,
	}
	print("castSpell "..spellId.." @"..target.guid:hex());
	send(CMSG_CAST_SPELL, data);
end

function hSMSG_ATTACKSTART(p)
	print("victim:", p.victim:hex());
	if(isAlly(STATE.knownObjects[p.victim])) then
		print("enemy:", p.attacker:hex());
		STATE.enemies[p.attacker] = STATE.knownObjects[p.attacker];
	end
end

function hSMSG_ATTACKSTOP(p)
	if(isAlly(STATE.knownObjects[p.victim])) then
		print("peace:", p.attacker:hex());
		STATE.enemies[p.attacker] = nil;
	end
end

-- misleading name; also sent when cast succeeds.
function hSMSG_CAST_FAILED(p)
	print("SMSG_CAST_FAILED", dump(p));
end

local function handleAttackCanceled()
	STATE.meleeing = false;
	decision(getRealTime());
end

function hSMSG_ATTACKSWING_NOTINRANGE(p)
	print("SMSG_ATTACKSWING_NOTINRANGE");
	handleAttackCanceled();
end
function hSMSG_ATTACKSWING_BADFACING(p)
	print("SMSG_ATTACKSWING_BADFACING");
	handleAttackCanceled();
end
function hSMSG_ATTACKSWING_NOTSTANDING(p)
	print("SMSG_ATTACKSWING_NOTSTANDING");
	handleAttackCanceled();
end
function hSMSG_ATTACKSWING_DEADTARGET(p)
	print("SMSG_ATTACKSWING_DEADTARGET");
	handleAttackCanceled();
end
function hSMSG_ATTACKSWING_CANT_ATTACK(p)
	print("SMSG_ATTACKSWING_CANT_ATTACK");
	handleAttackCanceled();
end
function hSMSG_CANCEL_COMBAT(p)
	print("SMSG_CANCEL_COMBAT");
	handleAttackCanceled();
end
function hSMSG_CANCEL_AUTO_REPEAT(p)
	print("SMSG_CANCEL_AUTO_REPEAT");
	handleAttackCanceled();
end

function hSMSG_MESSAGECHAT(p)
	print("SMSG_MESSAGECHAT", dump(p));
	handleChatMessage(p);
end

do
	-- lock down the Global table, to catch undefined variable creation.
	-- this code must appear last.
	local mt = getmetatable(_G) or {}
	mt.__newindex = function(t,k,v)
		error("attempt to add a global at runtime: "..k, 2)
	end
	setmetatable(_G, mt)
end
