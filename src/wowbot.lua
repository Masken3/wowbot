dofile("src/lua/timers.lua")

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

-- Location: {mapId, position{x,y,z}, orientation}.

if(STATE == nil) then
	STATE = {
		inGroup = false,
		leaderGuid = nil,	-- set by hSMSG_GROUP_LIST.
		leaderLocation = {},
		leaderMovement = {}, -- scalar x, y, startTime.
		reloadCount = 0,
		myGuid = nil,	-- set by C function enterWorld.
		myLocation = nil,	-- set by hSMSG_LOGIN_VERIFY_WORLD.
		moving = false,
		moveStartTime = nil,	-- floating point, in seconds. valid if moving == true.

		-- timer-related stuff
		timers = {},
		inTimerCallback = false,
		newTimers = {},
		removedTimers = {},
	}
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
function hSMSG_COMPRESSED_UPDATE_OBJECT(p)
	--print("SMSG_COMPRESSED_UPDATE_OBJECT", dump(p));
end
function hSMSG_UPDATE_OBJECT(p)
	--print("SMSG_UPDATE_OBJECT", dump(p));
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
	STATE.leaderGuid = p.leaderGuid;
	if(p.memberCount == 0) then
		STATE.inGroup = false;
		print("Group disbanded.");
	else
		STATE.inGroup = true;
		print("Group rejoined.");
	end
end

function hSMSG_LOGIN_VERIFY_WORLD(p)
	print("SMSG_LOGIN_VERIFY_WORLD", dump(p));
	STATE.myLocation = p;
end

-- returns the distance between xyz points a and b.
function distance3(a, b)
	local dx = a.x - b.x
	local dy = a.y - b.y
	local dz = a.z - b.z
	local square = dx^2 + dy^2 + dz^2
	return square^0.5
end

-- returns the vector from xyz points a to b.
-- assertion: a + d = b
-- conclusion: d = b - a
-- conclusion: diff3(a, b) != diff3(b, a)
function diff3(a, b)
	local d = {}
	d.x = b.x - a.x
	d.y = b.y - a.y
	d.z = b.z - a.z
	return d
end

-- returns the length of xyz vector v.
function length3(v)
	local square = v.x^2 + v.y^2 + v.z^2
	return square^0.5
end

-- returns the orientation, in radians, of the xy vector v.
function orient2(v)
	return math.atan2(v.y, v.x);
end

-- In yards, the same unit as world coordinates.
-- Bot will run until it's within TOLERANCE of DIST yards from leader.
-- Then it will follow leader's movements:
-- (running, walking, stopping, sitting, but not jumping).
-- This is the lowest-priority action a bot will take.
-- All other activities will take precedence.
FOLLOW_DIST = 5
FOLLOW_TOLERANCE = 0.5

-- Bot will stop if it's farther away than this.
FOLLOW_MAX_DIST = 100

-- This is modified by target hitbox size.
MELEE_RANGE = 5
MELEE_DIST = 3
MELEE_TOLERANCE = FOLLOW_TOLERANCE

-- In yards per second.
RUN_SPEED = 7
WALK_SPEED = 2.5

-- format guid
function fg(guid)
	local res = "";
	--print(#guid)
	for i=1, #guid do
		res = res .. string.format("%02x", string.byte(guid, i));
	end
	return res
end

function sendStop()
	STATE.moving = false;
	local data = {
		flags = 0,
		pos = STATE.myLocation.position,
		o = STATE.myLocation.orientation,
		time = 0,
		fallTime = 0,
	}
	send(MSG_MOVE_STOP, data);
end

function hMovement(opcode, p)
	print("hMovement", fg(p.guid), opcode, p.flags)

	--print("p,l:", fg(p.guid), fg(STATE.leaderGuid));
	if(p.guid == STATE.leaderGuid) then
		local realTime = getRealTime();
		updatePosition(realTime);
		STATE.leaderLocation.position = p.pos;
		STATE.leaderLocation.orientation = p.o;

		local f = p.flags;
		local speed = RUN_SPEED;	-- speed, in yards per second.
		local x = 0;
		local y = 0;
		if(f == MOVEFLAG_STOP) then
			STATE.leaderMovement.speed = 0;
		end
		if(bit32.btest(f, MOVEFLAG_WALK_MODE)) then
			speed = WALK_SPEED;
		end
		if(bit32.btest(f, MOVEFLAG_FORWARD) then
			assert(not bit32.btest(f, MOVEFLAG_BACKWARD);
			y = 1;
		end
		if(bit32.btest(f, MOVEFLAG_BACKWARD)) then
			speed = WALK_SPEED;
			y = -1;
			-- todo: is it slower to walk backwards?
		end
		if(bit32.btest(f, MOVEFLAG_STRAFE_LEFT)) then
			assert(not bit32.btest(f, MOVEFLAG_STRAFE_RIGHT));
			x = -1;
		end
		if(bit32.btest(f, MOVEFLAG_STRAFE_RIGHT)) then
			x = 1;
		end
		if(bit32.btest(f, MOVEFLAG_TURN_LEFT)) then
			assert(not bit32.btest(f, MOVEFLAG_TURN_RIGHT));
			-- todo: handle non-linear movement.
			print("Warning: MOVEFLAG_TURN_LEFT unhandled!");
		end
		if(bit32.btest(f, MOVEFLAG_PITCH_UP)) then
			assert(not bit32.btest(f, MOVEFLAG_PITCH_DOWN));
			-- todo: figure out what this means. is it ever used?
			print("Warning: MOVEFLAG_PITCH_UP unhandled!");
		end
		-- normalize vector.
		local factor = speed;
		if(x ~= 0 and y ~= 0) then
			-- multiply vector by square root of 2.
			factor = factor * 2^0.5;
		end
		STATE.leaderMovement.x = x * factor;
		STATE.leaderMovement.y = y * factor;
		STATE.leaderMovement.startTime = realTime;

		-- todo: handle the case of being on different maps.
		doMoveToTarget(realTime, p.pos, FOLLOW_DIST)
	end
end

function doMoveToLeader(realTime)
	doMoveToTarget(realTime, STATE.leaderLocation.position, FOLLOW_DIST)
end

function doMoveToTarget(realTime, p, maxDist)
	local myPos = STATE.myLocation.position;
	local diff = diff3(myPos, p);
	local dist = length3(diff);
	print("dist:", dist);
	--  or dist < (FOLLOW_DIST - FOLLOW_TOLERANCE)
	if(dist > maxDist) then
		local data = {
			flags = MOVEFLAG_FORWARD,
			pos = myPos,
			o = orient2(diff),
			time = 0,
			fallTime = 0,
		}
		STATE.myLocation.orientation = data.o;
		STATE.moving = true;
		--print(dump(data));
		send(MSG_MOVE_START_FORWARD, data);
		-- set timer to when we'll arrive, or at most one second.
		STATE.moveStartTime = getRealTime();
		-- todo: take into account movement speed modifiers,
		-- like ghost form, mount effects and other auras.
		local moveEndTime = STATE.moveStartTime + (dist - maxDist) / RUN_SPEED;
		local timerTime = math.min(moveEndTime, STATE.moveStartTime + 1);
		setTimer(movementTimerCallback, timerTime);
	elseif(STATE.moving) then
		sendStop();
		removeTimer(movementTimerCallback);
	end
end

function updatePosition(realTime)
	if(not STATE.moving) then
		return;
	end
	local diffTime = realTime - STATE.moveStartTime;
	local p = STATE.myLocation.position;
	local o = STATE.myLocation.orientation;
	p.x = p.x + math.cos(o) * diffTime * RUN_SPEED;
	p.y = p.y + math.sin(o) * diffTime * RUN_SPEED;
	STATE.moveStartTime = realTime;
end

function updateLeaderPosition(realTime)
	local p = STATE.leaderLocation.position;
	local m = STATE.leaderMovement;
	local diffTime = realTime - m.startTime;
	p.x = p.x + m.x * diffTime;
	p.y = p.y + m.y * diffTime;
	m.startTime = realTime;
end

function movementTimerCallback(t)
	updatePosition(t);
	updateLeaderPosition(t);
	doMoveToLeader(t);
end
