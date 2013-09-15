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
	--print("SMSG_GAMEOBJECT_QUERY_RESPONSE", dump(p));
	STATE.knownGameObjects[p.goId] = p;
	STATE.goInfoWaiting[p.goId] = nil;
end
