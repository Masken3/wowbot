function dump(o)
	if type(o) == 'table' then
		local s = '{ '
		for k,v in pairs(o) do
			if type(k) ~= 'number' then k = '"'..k..'"' end
			s = s .. '['..k..'] = ' .. dump(v) .. ','
		end
		return s .. '} '
	else
		return tostring(o)
	end
end

function hSMSG_MONSTER_MOVE(p)
	print("SMSG_MONSTER_MOVE", dump(p));
end
function hMSG_MOVE_HEARTBEAT(p)
	print("MSG_MOVE_HEARTBEAT", dump(p));
end
function hSMSG_COMPRESSED_UPDATE_OBJECT(p)
	print("SMSG_COMPRESSED_UPDATE_OBJECT", dump(p));
end
function hSMSG_UPDATE_OBJECT(p)
	print("SMSG_UPDATE_OBJECT", dump(p));
end
