SUBFILES = {
	'globalLockdown.lua',
	'dump.lua',
	'timers.lua',
	'struct.lua',
	'movement.lua',
	'decision.lua',
	'chat.lua',
	'quests.lua',
	'item.lua',
	'aura.lua',
	'gameobject.lua',
	'skill.lua',
	'combat.lua',
	--'gui/test.lua',
	'gui/talents.lua',
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

RepeatSpellCast = Struct.new{id='number', count='number'}

if(rawget(_G, 'STATE') == nil) then
	STATE = {
		inGroup = false,
		leader = false,
		newLeader = false,

		groupMembers = {},	-- set by hSMSG_GROUP_LIST.

		knownObjects = {},

		looting = false,
		skinning = false,

		-- set of guids, objects and creatures that have been looted already,
		-- and will not be looted again.
		looted = {},

		repeatSpellCast = RepeatSpellCast.new{id=0, count=0},

		knownQuests = {},

		checkNewObjectsForQuests = false,	-- set to true after login.

		reloadCount = 0,
		myGuid = '',	-- set by C function enterWorld.
		myLevel = 0,	-- set by C function enterWorld.
		myClassName = '',	-- set by C function enterWorld.

		myMoney = false,	-- in coppers. used to determine money changes.

		-- temporary set of the spells we're learning from a trainer.
		-- if this doesn't empty, something went wrong.
		training = {},

		currentAction = false,

		myLocation = Location.new(),	-- set by hSMSG_LOGIN_VERIFY_WORLD.
		my = false,	-- KnownObject.
		me = false,	-- == my.
		moving = false,
		moveStartTime = 0,	-- floating point, in seconds. valid if moving == true.

		myTarget = false,	-- guid of my target.

		attackSpells = {},	-- Spells we know that are useful for attacking other creatures.
		meleeSpell = false,	-- spell id.
		attacking = false,	-- boolean.
		meleeing = false,	-- boolean.
		spellCooldown = 0,	-- the realTime when the most recently spell will have cooled down.

		stealthed = false,	-- boolean.
		stealthSpell = false,	-- spell table.
		pickpocketSpell = false,	-- spell table.

		skinningSpell = false,	-- spellId.

		fishing = false,
		fishingSpell = false,	-- spellId.
		fishingBobber = false, -- KnownObject.

		disenchantSpell = false,	-- spellId.

		openLockSpells = {},	--miscValue:spellId.

		-- id:spellTable
		healingSpells = {},
		buffSpells = {},
		focusSpells = {},

		-- key: id. value: table. All the spells we know.
		knownSpells = {},

		-- set of RequiresSpellFocus.
		focusTypes = {},

		-- set of itemIds that we need data for.
		itemProtosWaiting = {},

		-- key: id. value: table.
		itemProtos = {},

		-- key: parameter. value: function.
		-- they will be called when itemDataWaiting is empty.
		itemDataCallbacks = {},

		---- guid:table{slot, bag, count}
		-- itemId:true
		-- if not empty and a vendor is nearby,
		-- will go to vendor and sell all inventory items with that id.
		itemsToSell = {},

		tradeGiveAll = false,
		tradeGiveItem = false,	-- itemId.
		recreate = false,

		knownCreatures = {},
		creatureQueryCallbacks = {},

		knownGameObjects = {},
		goInfoWaiting = {},

		-- timer-related stuff
		timers = {},
		inTimerCallback = false,
		newTimers = {},
		removedTimers = {},
		callbackTime = 0,
	}

	-- list of tables on the form guid:object.
	-- all of them are affected by SMSG_DESTROY_OBJECT.
	STATE.knownObjectHolders = {}

	-- key:guid. value:knownObject from knownObjects.
	local knownObjectHolders = {
		'enemies',
		'questGivers',
		'questFinishers',
		'lootables',
		'classTrainers',
		'pickpocketables',
		'skinnables',
		'openables',
		'vendors',
		'focusObjects',
	}
	for i,k in ipairs(knownObjectHolders) do
		STATE[k] = {};
		STATE.knownObjectHolders[k] = STATE.k;
	end

	-- saved to and loaded from disk.
	-- call saveState() after changing any of these.
	PERMASTATE = {
		-- the last level we saw our trainer. saved to disk, restored on load.
		classTrainingCompleteForLevel = 0,

		-- radius within which we will gather things automatically, even if there are nearby enemies.
		gatherRadius = 40,

		-- Guid. auto-invite this player if they come online but is not in party.
		invitee = false,
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
	setmetatable(PERMASTATE, mt);
else
	STATE.reloadCount = STATE.reloadCount + 1;
	print("STATE.reloadCount", STATE.reloadCount);
end

local function stateFileName()
	return "state/"..STATE.myGuid:hex()..".lua";
end

function loadState()
	-- note: this will cause unknown keys to raise an error.
	-- if you ever remove keys from PERMASTATE,
	-- you must also remove them from any saved state files before loading them.
	if(fileExists(stateFileName())) then
		dofile(stateFileName());
	else
		print("WARN: state file "..stateFileName().." does not exist.");
	end
end

function saveState()
	local file = io.open(stateFileName(), "w");
	file:write("-- "..STATE.myClassName.."\n");
	for k,v in pairs(PERMASTATE) do
		local vs = tostring(v);
		if(type(v) == 'string') then
			vs = '"'..vs..'"';
		end
		file:write("PERMASTATE."..k.." = "..vs..";\n");
	end
	file:close();
end

function fileExists(name)
	local f=io.open(name,"r")
	if f~=nil then io.close(f) return true else return false end
end

function setAction(a)
	if(STATE.currentAction ~= a) then
		STATE.currentAction = a;
		partyChat(a);
	end
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
	--print("SMSG_GROUP_LIST", dump(p));
	STATE.leader = STATE.knownObjects[p.leaderGuid] or false;
	if(p.memberCount == 0) then
		STATE.inGroup = false;
		print("Group disbanded.");
	else
		STATE.inGroup = true;
		--print("Group joined.");
		STATE.groupMembers = p.members;
		for i,m in ipairs(STATE.groupMembers) do
			--print(m.guid:hex());
			if(STATE.newLeader == m.guid) then
				send(CMSG_GROUP_SET_LEADER, {guid=m.guid});
				STATE.newLeader = false;
			end
		end
	end
end

function hSMSG_LOGIN_VERIFY_WORLD(p)
	print("SMSG_LOGIN_VERIFY_WORLD", dump(p));
	STATE.myLocation = p;
end

function loginComplete()
	itemLoginComplete();
	auraLoginComplete();
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
function isUnit(o)
	if(not o) then return false; end
	return bit32.btest(o.values[OBJECT_FIELD_TYPE], TYPEMASK_UNIT);
end

function isGameObject(o)
	if(not o) then return false; end
	return bit32.btest(o.values[OBJECT_FIELD_TYPE], TYPEMASK_GAMEOBJECT);
end

function isPlayer(o)
	if(not o) then return false; end
	return bit32.btest(o.values[OBJECT_FIELD_TYPE], TYPEMASK_PLAYER);
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
	local val = o.values[idx];
	if(isGameObject(o)) then
		if(idx == GAMEOBJECT_TYPE_ID) then
			local _type = val;
			if(STATE.checkNewObjectsForQuests and
				bit32.btest(_type, GAMEOBJECT_TYPE_QUESTGIVER))
			then
				send(CMSG_QUESTGIVER_STATUS_QUERY, o);
			end
		end
		if(idx == GAMEOBJECT_FLAGS) then
			if(bit32.btest(val, GO_FLAG_NO_INTERACT)) then
				STATE.openables[o.guid] = nil;
			end
		end
		if(idx == GAMEOBJECT_DYN_FLAGS) then
			if(bit32.btest(val, GO_DYNFLAG_LO_NO_INTERACT)) then
				STATE.openables[o.guid] = nil;
			end
		end
	end
	if(not isUnit(o)) then return; end
	if(idx == UNIT_NPC_FLAGS) then
		local flags = o.values[idx];
		if(bit32.btest(flags, UNIT_NPC_FLAG_TRAINER)) then
			sendCreatureQuery(o, function(p)
				--print("Found "..p.subName);
				if(p.subName == STATE.myClassName.." Trainer") then
					--print("MINE!");
					STATE.classTrainers[o.guid] = o;
				end
			end)
		end
		if(bit32.btest(flags, UNIT_NPC_FLAG_VENDOR)) then
			sendCreatureQuery(o, function(p)
				--print("Found Vendor "..p.name.." <"..p.subName..">");
				STATE.vendors[o.guid] = o;
			end)
		end
		if(STATE.checkNewObjectsForQuests and
			bit32.btest(flags, UNIT_NPC_FLAG_QUESTGIVER))
		then
			send(CMSG_QUESTGIVER_STATUS_QUERY, o);
		end
	end
	if(idx == UNIT_DYNAMIC_FLAGS) then
		if(bit32.btest(o.values[idx], UNIT_DYNFLAG_LOOTABLE) and not STATE.looted[o.guid]) then
			STATE.lootables[o.guid] = o;
		else
			STATE.lootables[o.guid] = nil;
		end
	end
	if(idx == UNIT_FIELD_FLAGS) then
		if(STATE.skinningSpell) then
			if(bit32.btest(o.values[idx], UNIT_FLAG_SKINNABLE)) then
				--partyChat("Found skinnable: "..o.guid:hex());
				STATE.skinnables[o.guid] = o;
			else
				STATE.skinnables[o.guid] = nil;
			end
		end
	end
	if(idx == UNIT_FIELD_LEVEL and o == STATE.me) then
		if(STATE.myLevel ~= o.values[idx]) then
			partyChat("Level up! "..o.values[idx]);
		end
		STATE.myLevel = o.values[idx];
	end
	-- money
	if(o == STATE.me and idx == PLAYER_FIELD_COINAGE) then
		local msg = "I have "..o.values[idx].."c";
		if(STATE.myMoney) then
			local diff = o.values[idx] - STATE.myMoney;
			if(diff > 0) then msg=msg.." +";
			else msg=msg.." "; end
			msg=msg..diff;
			partyChat(msg);
		end
		STATE.myMoney = o.values[idx];
	end
	-- skills
	if(o == STATE.me and idx >= PLAYER_SKILL_INFO_1_1 and idx <= PLAYER_SKILL_INFO_1_1+384) then
		local offset = idx - PLAYER_SKILL_INFO_1_1;
		local slot = math.floor(offset / 3);
		local baseIdx = PLAYER_SKILL_INFO_1_1 + slot * 3;
		--print(idx, offset, slot, baseIdx);
		local skillId = bit32.band(o.values[baseIdx], 0xFFFF);
		local skillLine = cSkillLine(skillId);
		local max;
		if(o.values[baseIdx+1]) then
			max = bit32.extract(o.values[baseIdx+1], 16, 16);
		end
		local val = skillLevelByIndex(baseIdx);
		if(STATE.checkNewObjectsForQuests) then
			partyChat("Skill "..((skillLine and skillLine.name) or skillId)..": "..tostring(val).."/"..tostring(max));
		end
	end
	--[[
	if(o == STATE.me and idx == PLAYER_CHARACTER_POINTS1) then
		if(o.values[idx] > 0) then
			doTalentWindow()
		end
	end
	--]]
	-- fishing bobber
	--[[	-- looks like this never happens.
	-- we'll have to listen to SMSG_GAMEOBJECT_CUSTOM_ANIM and SMSG_FISH_NOT_HOOKED instead.
	if(o == STATE.fishingBobber) then-- and idx == GAMEOBJECT_STATE) then
		print("Bobber "..idx..": "..o.values[idx]);
	end
	]]
end

function hSMSG_NOTIFICATION(p)
	print("SMSG_NOTIFICATION", dump(p));
end

function sendCreatureQuery(o, callback)
	local entry = o.values[OBJECT_FIELD_ENTRY];
	local known = STATE.knownCreatures[entry];
	if(known) then
		callback(known);
		return;
	end
	STATE.creatureQueryCallbacks[entry] = callback;
	send(CMSG_CREATURE_QUERY, {guid=o.guid, entry=entry});
end

function hSMSG_CREATURE_QUERY_RESPONSE(p)
	--print("SMSG_CREATURE_QUERY_RESPONSE", dump(p));
	STATE.knownCreatures[p.entry] = p
	local cb = STATE.creatureQueryCallbacks[p.entry];
	if(cb) then
		STATE.creatureQueryCallbacks[p.entry] = nil
		cb(p);
	end
end

function objectNameQuery(o, callback)
	if(isPlayer(o)) then
		if(o.bot.nameData) then
			callback(o.bot.nameData.name)
			return;
		end
		o.bot.nameCallback = function(p)
			callback(p.name);
		end
		send(CMSG_NAME_QUERY, {guid=o.guid});
		return;
	end
	if(isUnit(o)) then
		sendCreatureQuery(o, function(k)
			callback(k.name);
		end)
		return;
	end
	if(isGameObject(o)) then
		gameObjectInfo(o, function(info)
			callback(info.name);
		end)
		return;
	end
	error("objectNameQuery: Unhandled type (guid "..o.guid:hex()..")");
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
	--print("SMSG_UPDATE_OBJECT", #p.blocks);
	-- todo: get notified when someone is in combat with a party member.
	for i,b in ipairs(p.blocks) do
		if(b.type == UPDATETYPE_OUT_OF_RANGE_OBJECTS) then
			for j,guid in ipairs(b.guids) do
				STATE.knownObjects[guid] = nil;
			end
		elseif(b.type == UPDATETYPE_CREATE_OBJECT or b.type == UPDATETYPE_CREATE_OBJECT2) then
			local o = STATE.knownObjects[b.guid] or
				KnownObject.new{guid=b.guid, values={}, bot={}, updateValuesCallbacks={}};
			updateValues(o, b);
			updateMovement(o, b);
			STATE.knownObjects[b.guid] = o;

			if(b.guid == STATE.myGuid) then
				STATE.my = o;
				STATE.me = o;
				print("CreateObject me!");
				questLogin();
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

			-- gameobjects that have a location are of interest to us.
			if(isGameObject(o) and
				o.values[GAMEOBJECT_POS_X])
			then
				-- trigger query, if needed.
				gameObjectInfo(o, newGameObject);
			end

			if(o.guid:hex() == PERMASTATE.invitee and not isGroupMember(o)) then
				-- will trigger invite. see hSMSG_NAME_QUERY_RESPONSE.
				send(CMSG_NAME_QUERY, o);
			end

			--print("CREATE_OBJECT", b.guid:hex(), hex(o.values[OBJECT_FIELD_TYPE]), dump(b.pos));
			--, dump(o.movement), dump(o.values));

		elseif(b.type == UPDATETYPE_VALUES) then
			updateValues(STATE.knownObjects[b.guid], b);
			if(STATE.checkNewObjectsForQuests) then
				send(CMSG_QUESTGIVER_STATUS_QUERY, {guid=b.guid});
			end
			if(b.guid == STATE.myGuid) then
				--print("UpdateObject me!");
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
	decision();
end

function hSMSG_DESTROY_OBJECT(p)
	--print("SMSG_DESTROY_OBJECT", dump(p));
	for i, koh in pairs(STATE.knownObjectHolders) do
		koh[p.guid] = nil;
	end
	if(STATE.fishingBobber and p.guid == STATE.fishingBobber.guid) then
		print("fishingBobber destroyed.");
		STATE.fishingBobber = false;
		decision();
	end
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
	[SPELL_EFFECT_NORMALIZED_WEAPON_DMG]=true,
}

local function learnSpell(id)
	local s = cSpell(id);
	--print(id, spacify(s.name, 23), spacify(s.rank, 15), unpack(spellEffectNames(s)));
	for i, e in ipairs(s.effect) do
		--print(e.id, SPELL_ATTACK_EFFECTS[e.id]);
		if(SPELL_ATTACK_EFFECTS[e.id]) then
			if(not STATE.attackSpells[id]) then
				print("a"..id, spacify(s.name, 23), spacify(s.rank, 15), unpack(spellEffectNames(s)));
			end
			STATE.attackSpells[id] = s;
		end
		if(e.id == SPELL_EFFECT_ATTACK) then
			-- assuming that there's only one melee spell
			assert(not STATE.meleeSpell);
			--print("Melee spell:", id);
			STATE.meleeSpell = id;
		end
		if((e.id == SPELL_EFFECT_APPLY_AURA) and (e.applyAuraName == SPELL_AURA_MOD_STEALTH)) then
			if(not STATE.stealthSpell or (STATE.stealthSpell.rank < s.rank)) then
				--print("Stealth spell: "..id.." "..s.rank);
				STATE.stealthSpell = s;
			end
		end
		if(e.id == SPELL_EFFECT_PICKPOCKET) then
			assert(not STATE.pickpocketSpell);
			STATE.pickpocketSpell = s;
		end
		if(e.id == SPELL_EFFECT_SKINNING) then
			STATE.skinningSpell = id;
		end
		if(e.id == SPELL_EFFECT_TRANS_DOOR and e.miscValue == 35591) then
			STATE.fishingSpell = id;
		end
		if(e.id == SPELL_EFFECT_OPEN_LOCK) then
			if(e.implicitTargetA == TARGET_GAMEOBJECT) then
				--print("OpenLockSpell "..e.miscValue..": "..id);
				if(STATE.openLockSpells[e.miscValue]) then print("Override!"); end
				STATE.openLockSpells[e.miscValue] = id;
			end
		end
		if((e.id == SPELL_EFFECT_APPLY_AURA) and
			(e.implicitTargetA == TARGET_SINGLE_FRIEND))
		then
			-- buffs
			local buffAuras = {
				[SPELL_AURA_MOD_ATTACKSPEED]=true,
				[SPELL_AURA_MOD_DAMAGE_DONE]=true,
				[SPELL_AURA_MOD_RESISTANCE]=true,
				[SPELL_AURA_PERIODIC_ENERGIZE]=true,
				[SPELL_AURA_MOD_STAT]=true,
				[SPELL_AURA_MOD_SKILL]=true,
				[SPELL_AURA_MOD_INCREASE_SPEED]=true,
				[SPELL_AURA_MOD_INCREASE_HEALTH]=true,
				[SPELL_AURA_MOD_INCREASE_ENERGY]=true,
			}
			--print("aura: "..e.applyAuraName, dump(buffAuras));
			if(buffAuras[e.applyAuraName]) then
				if(not STATE.buffSpells[id]) then
					print("b"..id, spacify(s.name, 23), spacify(s.rank, 15), unpack(spellEffectNames(s)));
				end
				STATE.buffSpells[id] = s;
			end
			-- HoTs
			-- we count PW:S here.
			if((e.applyAuraName == SPELL_AURA_SCHOOL_ABSORB) or
				(e.applyAuraName == SPELL_AURA_PERIODIC_HEAL))
			then
				STATE.healingSpells[id] = s;
			end
			-- DoTs
			if(e.applyAuraName == SPELL_AURA_PERIODIC_DAMAGE) then
				STATE.attackSpells[id] = s;
			end
		end
		-- direct heals
		if(e.id == SPELL_EFFECT_HEAL and
			(e.implicitTargetA == TARGET_SINGLE_FRIEND))
		then
			if(not STATE.healingSpells[id]) then
				print("h"..id, spacify(s.name, 23), spacify(s.rank, 15), unpack(spellEffectNames(s)));
			end
			STATE.healingSpells[id] = s;
		end
		-- disenchant
		if(e.id == SPELL_EFFECT_DISENCHANT) then
			STATE.disenchantSpell = id;
		end
		-- automatic profession spells
		if(e.id == SPELL_EFFECT_CREATE_ITEM) then
			if(s.RequiresSpellFocus ~= 0) then
				-- see GAMEOBJECT_TYPE_SPELL_FOCUS and GOInfo.spellFocus.focusId.
				-- also GOInfo.spellFocus.dist.
				local skillId = skillIdBySpell(id);
				if(skillId == 186 or	-- mining
					skillId == 185 or	-- cooking
					false)
				then
					STATE.focusSpells[id] = s;
					STATE.focusTypes[s.RequiresSpellFocus] = STATE.focusTypes[s.RequiresSpellFocus] or {};
					STATE.focusTypes[s.RequiresSpellFocus][id] = s;
				end
			end
		end
	end
	STATE.knownSpells[id] = s;
	return s;
end

function hSMSG_INITIAL_SPELLS(p)
	--print("SMSG_INITIAL_SPELLS", dump(p));
	--print(dump(SPELL_ATTACK_EFFECTS));
	for i,id in ipairs(p.spells) do
		learnSpell(id);
	end
	print("Found "..dumpKeys(STATE.attackSpells).." attack spells.");
end

function hSMSG_LEARNED_SPELL(p)
	local s = learnSpell(p.spellId);
	partyChat("Learned spell "..s.name.." "..s.rank.." ("..p.spellId..")");
end

local function setSpellCooldown(spellId)
	local s = STATE.knownSpells[spellId]
	local recovery = math.max(s.RecoveryTime,
		s.CategoryRecoveryTime,
		s.StartRecoveryTime);
	local castTime = cSpellCastTime(s.CastingTimeIndex).base;
	-- add 100 ms lag, otherwise our cooldown will expire before the server's.
	local cooldown = math.max(recovery, castTime) + 100;
	--print("recovery: "..recovery.." castTime: "..castTime.." cooldown: "..cooldown);
	STATE.spellCooldown = getRealTime() + cooldown / 1000;
end

function castSpellAtUnit(spellId, target)
	local data = {
		spellId = spellId,
		targetFlags = TARGET_FLAG_UNIT,
		unitTarget = target.guid,
	}
	print("castSpellAtUnit "..spellId.." @"..target.guid:hex());
	setSpellCooldown(spellId);
	send(CMSG_CAST_SPELL, data);
end

function castSpellAtGO(spellId, target)
	local data = {
		spellId = spellId,
		targetFlags = bit32.bor(TARGET_FLAG_OBJECT, TARGET_FLAG_OBJECT_UNK),
		goTarget = target.guid,
	}
	print("castSpellAtGO "..spellId.." @"..target.guid:hex());
	setSpellCooldown(spellId);
	send(CMSG_CAST_SPELL, data);
end

function castSpellAtItem(spellId, target)
	local data = {
		spellId = spellId,
		targetFlags = TARGET_FLAG_ITEM,
		itemTarget = target.guid,
	}
	print("castSpellAtItem "..spellId.." @"..target.guid:hex());
	setSpellCooldown(spellId);
	send(CMSG_CAST_SPELL, data);
end

function castSpellWithoutTarget(spellId)
	local data = {
		spellId = spellId,
		targetFlags = 0,
	}
	print("castSpellWithoutTarget "..spellId.." "..getRealTime());
	setSpellCooldown(spellId);
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
	local hex;
	if(p.result) then
		STATE.spellCooldown = getRealTime() + 1;
		hex = string.format("0x%02X", p.result);
		print("SMSG_CAST_FAILED", tostring(hex), dump(p));
	end
	STATE.skinning = false;
	STATE.looting = false;
	decision();
end

local function handleAttackCanceled()
	STATE.meleeing = false;
	decision();
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
	--print("SMSG_MESSAGECHAT", dump(p));
	handleChatMessage(p);
end

function hMSG_RAID_TARGET_UPDATE(p)
	print("MSG_RAID_TARGET_UPDATE", dump(p));
	if(STATE.stealthSpell and (p.id == RAID_ICON_STAR)) then
		-- todo: also check STATE.pickpocketSpell
		STATE.pickpocketables = {};	--hack
		if(isValidGuid(p.guid)) then
			STATE.pickpocketables[p.guid] = STATE.knownObjects[p.guid];
		end
		decision();
	end
end

function hMSG_MINIMAP_PING(p)
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
