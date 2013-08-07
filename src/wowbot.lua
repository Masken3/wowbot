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

STATE = {
	inGroup = false,
	leaderGuid = nil,
}

function hSMSG_MONSTER_MOVE(p)
	--print("SMSG_MONSTER_MOVE", dump(p));
end
function hMSG_MOVE_HEARTBEAT(p)
	print("MSG_MOVE_HEARTBEAT", dump(p));
end
function hSMSG_COMPRESSED_UPDATE_OBJECT(p)
	--print("SMSG_COMPRESSED_UPDATE_OBJECT", dump(p));
end
function hSMSG_UPDATE_OBJECT(p)
	--print("SMSG_UPDATE_OBJECT", dump(p));
end

function hSMSG_GROUP_INVITE(p)
	print("SMSG_GROUP_INVITE", dump(p));
	if(STATE.inGroup) then
		sendWorld(CMSG_GROUP_DECLINE);
	else
		sendWorld(CMSG_GROUP_ACCEPT);
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
	print("SMSG_GROUP_INVITE", dump(p));
	STATE.leaderGuid = p.leaderGuid;
end

function hMSG_MOVE_START_FORWARD(p); print("MSG_MOVE_START_FORWARD"); end
function hMSG_MOVE_START_BACKWARD(p); print("MSG_MOVE_START_BACKWARD"); end
function hMSG_MOVE_STOP(p); print("MSG_MOVE_STOP"); end
function hMSG_MOVE_START_STRAFE_LEFT(p); print("MSG_MOVE_START_STRAFE_LEFT"); end
function hMSG_MOVE_START_STRAFE_RIGHT(p); print("MSG_MOVE_START_STRAFE_RIGHT"); end
function hMSG_MOVE_STOP_STRAFE(p); print("MSG_MOVE_STOP_STRAFE"); end
function hMSG_MOVE_JUMP(p); print("MSG_MOVE_JUMP"); end
function hMSG_MOVE_START_TURN_LEFT(p); print("MSG_MOVE_START_TURN_LEFT"); end
function hMSG_MOVE_START_TURN_RIGHT(p); print("MSG_MOVE_START_TURN_RIGHT"); end
function hMSG_MOVE_STOP_TURN(p); print("MSG_MOVE_STOP_TURN"); end
function hMSG_MOVE_START_PITCH_UP(p); print("MSG_MOVE_START_PITCH_UP"); end
function hMSG_MOVE_START_PITCH_DOWN(p); print("MSG_MOVE_START_PITCH_DOWN"); end
function hMSG_MOVE_STOP_PITCH(p); print("MSG_MOVE_STOP_PITCH"); end
function hMSG_MOVE_SET_RUN_MODE(p); print("MSG_MOVE_SET_RUN_MODE"); end
function hMSG_MOVE_SET_WALK_MODE(p); print("MSG_MOVE_SET_WALK_MODE"); end
function hMSG_MOVE_FALL_LAND(p); print("MSG_MOVE_FALL_LAND"); end
function hMSG_MOVE_START_SWIM(p); print("MSG_MOVE_START_SWIM"); end
function hMSG_MOVE_STOP_SWIM(p); print("MSG_MOVE_STOP_SWIM"); end
function hMSG_MOVE_SET_FACING(p); print("MSG_MOVE_SET_FACING"); end
function hMSG_MOVE_SET_PITCH(p); print("MSG_MOVE_SET_PITCH"); end
