function gameObjectInfo(o)
	assert(bit32.btest(o.values[OBJECT_FIELD_TYPE], TYPEMASK_GAMEOBJECT));
	local id = o.values[OBJECT_FIELD_ENTRY];
	local info = STATE.knownGameObjects[id];
	if((not info) and (not STATE.goInfoWaiting[id])) then
		STATE.goInfoWaiting[id] = o;
		send(CMSG_GAMEOBJECT_QUERY, {id=id, guid=o.guid});
	end
	return info;
end

function hSMSG_GAMEOBJECT_QUERY_RESPONSE(p)
	print("SMSG_GAMEOBJECT_QUERY_RESPONSE", dump(p));
	STATE.knownGameObjects[p.goId] = p;
	STATE.goInfoWaiting[p.goId] = nil;
end

function goLockIndex(o)
	local p = STATE.knownGameObjects[o.values[OBJECT_FIELD_ENTRY]];
	if(p.type == GAMEOBJECT_TYPE_CHEST) then
		local lockId = p.data[1];
		local lock = cLock(lockId);
		if(not lock) then return nil; end
		for i, e in ipairs(lock.e) do
			if(e.type == LOCK_KEY_SKILL) then
				local lockIndex = e.index;
				--lockSkill = e.skill;
				return lockIndex;
			end
		end
	end
	return nil;
end
