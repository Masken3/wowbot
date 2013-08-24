
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

dofile("src/lua/timers.lua")
dofile("src/lua/struct.lua")

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

		reloadCount = 0,
		myGuid = '',	-- set by C function enterWorld.
		myLocation = Location.new(),	-- set by hSMSG_LOGIN_VERIFY_WORLD.
		moving = false,
		moveStartTime = 0,	-- floating point, in seconds. valid if moving == true.

		-- timer-related stuff
		timers = {},
		inTimerCallback = false,
		newTimers = {},
		removedTimers = {},
		callbackTime = 0,
	}
	-- type-securing STATE is too much work, but at least we can prevent unregistered members.
	local mt = {
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
	--print("hMovement", fg(p.guid), opcode, p.flags)

	--print("p,l:", fg(p.guid), fg(STATE.leaderGuid));
	if(p.guid == STATE.leader.guid) then
		local realTime = getRealTime();
		updatePosition(realTime);
		if(STATE.leader.movement.startTime) then
			updateLeaderPosition(realTime);
			-- calculated leader position
			local clp = STATE.leader.location.position;
			--print("clp, p:", dump(clp), dump(p.pos));
			local d = diff3(clp, p.pos);
			--print("diff:", d.x, d.y);
		end
		STATE.leader.location.position.x = p.pos.x;
		STATE.leader.location.position.y = p.pos.y;
		STATE.leader.location.position.z = p.pos.z;
		STATE.leader.location.orientation = p.o;

		local f = p.flags;
		local speed = RUN_SPEED;	-- speed, in yards per second.
		local x = 0;
		local y = 0;
		if(f == MOVEFLAG_STOP) then
			speed = 0;
		end
		if(bit32.btest(f, MOVEFLAG_WALK_MODE)) then
			speed = WALK_SPEED;
		end
		if(bit32.btest(f, MOVEFLAG_FORWARD)) then
			assert(not bit32.btest(f, MOVEFLAG_BACKWARD));
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
		STATE.leader.movement.dx = y * factor * math.cos(p.o) + x * factor * math.cos(p.o);
		STATE.leader.movement.dy = y * factor * math.sin(p.o) + x * factor * math.sin(p.o);
		STATE.leader.movement.startTime = realTime;

		-- todo: handle the case of being on different maps.
		--print("leaderMovement", realTime);
		doMoveToTarget(realTime, STATE.leader, FOLLOW_DIST);
	end
end

function doMoveToLeader(realTime)
	return doMoveToTarget(realTime, STATE.leader, FOLLOW_DIST)
end

function doMoveToTarget(realTime, mo, maxDist)
	local myPos = STATE.myLocation.position;
	local tarPos = mo.location.position;
	local diff = diff3(myPos, tarPos);
	local dist = length3(diff);
	--  or dist < (FOLLOW_DIST - FOLLOW_TOLERANCE)
	if(dist > maxDist) then
		--print("dist:", dist);
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
		STATE.moveStartTime = realTime;

		-- if target is close, and moving in roughly the same direction and speed as us,
		-- wait longer before resetting our movement. otherwise,
		-- a target running away will cause tons of unneeded update packets.
		local mov = mo.movement;
		if(mov.dx ~=0 or mov.dy ~=0) then
			--see math-notes.txt, 14:33 2013-08-24
			local a, b, c;
			if(mov.dy == 0) then
				b = 0;
			else
				b = -1;
			end
			a = mov.dx/mov.dy;
			c = -(a*tarPos.x + b*tarPos.y);
			local x = myPos.x;
			local y = myPos.y;
			local dx = math.cos(data.o) * RUN_SPEED;
			local dy = math.sin(data.o) * RUN_SPEED;
			local t1 = (maxDist*((a^2+b^2)^0.5) - (a*x+b*y+c)) / (a*dx+b*dy);
			local t2 = (maxDist*((a^2+b^2)^0.5) + a*x+b*y+c) / -(a*dx+b*dy);
			local t = math.max(t1, t2);
			local tMin = math.min(t1, t2);

			--print("a, b, c:", a, b, c);
			--print("dx, dy:", dx, dy);
			--print("moving T:", t);
			assert(t > 0);
			--assert(tMin < 0);
			setTimer(movementTimerCallback, realTime + t);
			return;
		end

		-- todo: take into account movement speed modifiers,
		-- like ghost form, mount effects and other auras.
		local moveEndTime = STATE.moveStartTime + (dist - maxDist) / RUN_SPEED;
		--local timerTime = math.min(moveEndTime, STATE.moveStartTime + 1);
		local timerTime = moveEndTime;
		--print("still T:", timerTime - realTime);
		setTimer(movementTimerCallback, timerTime);
		return;
	elseif(STATE.moving) then
		--print("stop");
		sendStop();
		if(mo.movement.dx == 0 and mo.movement.dy == 0) then
			removeTimer(movementTimerCallback);
			--print("removed timer.");
			return;
		end
	end
	if(mo.movement.dx ~= 0 or mo.movement.dy ~= 0) then
		-- see math-notes.txt, 2013-08-18 20:03:46
		local dx = STATE.leader.movement.dx;
		local dy = STATE.leader.movement.dy;
		local x = mo.location.position.x - myPos.x;
		local y = mo.location.position.y - myPos.y;
		local a = dx^2 + dy^2;
		local b = 2*(x*dx+y*dy);
		local c = (x^2+y^2-FOLLOW_DIST^2);
		assert(a ~= 0);
		local t1 = (-b + (b^2 - 4*a*c)^0.5) / (2*a);
		local t2 = (-b - (b^2 - 4*a*c)^0.5) / (2*a);
		local t = math.max(t1, t2);
		--print("inside t:", t);
		assert(t > 0);
		assert(math.min(t1, t2) < 0);
		setTimer(movementTimerCallback, realTime + t);
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
	local p = STATE.leader.location.position;
	local m = STATE.leader.movement;
	local diffTime = realTime - m.startTime;
	p.x = p.x + m.dx * diffTime;
	p.y = p.y + m.dy * diffTime;
	m.startTime = realTime;
end

function movementTimerCallback(t)
	--print("movementTimerCallback", t)
	updatePosition(t);
	updateLeaderPosition(t);
	doMoveToLeader(t);
	--print("movementTimerCallback ends", t)
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
end
function updateValues(o, b)
	local j = 0
	for i, m in ipairs(b.updateMask) do
	end
end
function updateMovement(o, b)
end

function hSMSG_INITIAL_SPELLS(p)
	print("SMSG_INITIAL_SPELLS", dump(p));
end
