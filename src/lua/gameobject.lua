-- calls f(o, info).
-- may delay until info is available.
function gameObjectInfo(o, f)
	assert(bit32.btest(o.values[OBJECT_FIELD_TYPE], TYPEMASK_GAMEOBJECT));
	local id = o.values[OBJECT_FIELD_ENTRY];
	local info = STATE.knownGameObjects[id];
	if(not info) then
		if(not STATE.goInfoWaiting[id]) then
			STATE.goInfoWaiting[id] = {};
			send(CMSG_GAMEOBJECT_QUERY, {id=id, guid=o.guid});
		end
		STATE.goInfoWaiting[id][o] = f;
	else
		f(o, info);
	end
end

function hSMSG_GAMEOBJECT_QUERY_RESPONSE(p)
	--print("SMSG_GAMEOBJECT_QUERY_RESPONSE", dump(p));
	STATE.knownGameObjects[p.goId] = p;
	if(STATE.goInfoWaiting[p.goId]) then
		for o,f in pairs(STATE.goInfoWaiting[p.goId]) do
			f(o, p);
		end
		STATE.goInfoWaiting[p.goId] = nil;
	end
end

local function goLockSkillEntry(o)
	local p = STATE.knownGameObjects[o.values[OBJECT_FIELD_ENTRY]];
	if(p.type == GAMEOBJECT_TYPE_CHEST) then
		local lockId = p.data[1];
		local lock = cLock(lockId);
		if(not lock) then return nil; end
		for i, e in ipairs(lock.e) do
			if(e.type == LOCK_KEY_SKILL) then
				return e;
			end
		end
	end
	return nil;
end

function goLockIndex(o)
	local e = goLockSkillEntry(o);
	if(e) then
		local lockIndex = e.index;
		--lockSkill = e.skill;
		return lockIndex;
	end
	return nil;
end

function goPos(o)
	return Position.new{
		x=cIntAsFloat(o.values[GAMEOBJECT_POS_X]),
		y=cIntAsFloat(o.values[GAMEOBJECT_POS_Y]),
		z=cIntAsFloat(o.values[GAMEOBJECT_POS_Z]),
	}
end

local goodLocks = {
	LOCKTYPE_PICKLOCK=true,
	LOCKTYPE_HERBALISM=true,
	LOCKTYPE_MINING=true,
	LOCKTYPE_CALCIFIED_ELVEN_GEMS=true,
	LOCKTYPE_GAHZRIDIAN=true,
	LOCKTYPE_FISHING=true,
}

function canOpenGO(o)
	local lockIndex = goLockIndex(o);
	if(not lockIndex) then return false; end
	--if(not goodLocks[lockIndex]) then return false; end
	local spell = STATE.openLockSpells[lockIndex];
	if(not spell) then return false; end
	return true;
end

function newGameObject(o, info)
	if(not canOpenGO(o)) then return; end
	o.location = Location.new();
	local pos = goPos(o);
	o.location.position = pos;
	local myPos = STATE.myLocation.position;
	partyChat(info.name..", "..distance3(myPos, pos).." yards.");
	send(MSG_MINIMAP_PING, pos);
	STATE.openables[o.guid] = o;
end

-- returns true iff we have sufficient skill to open the lock.
function haveSkillToOpen(o)
	local e = goLockSkillEntry(o);
	if(not e) then return false; end
	local spellId = STATE.openLockSpells[e.index];
	if(not spellId) then return false; end
	local mySkillLevel = spellSkillLevel(spellId);
	if(not mySkillLevel) then return false; end
	return mySkillLevel >= e.skill;
end
