
-- returns the distance between xyz points a and b.
local function distance3(a, b)
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
local function diff3(a, b)
	local d = {}
	d.x = b.x - a.x
	d.y = b.y - a.y
	d.z = b.z - a.z
	return d
end

-- returns the length of xyz vector v.
local function length3(v)
	local square = v.x^2 + v.y^2 + v.z^2
	return square^0.5
end

-- returns the orientation, in radians, of the xy vector v.
local function orient2(v)
	return math.atan2(v.y, v.x);
end

function distanceToObject(o)
	return distance3(STATE.myLocation.position, o.location.position);
end

-- In yards, the same unit as world coordinates.
-- Bot will run until it's within TOLERANCE of DIST yards from leader.
-- Then it will follow leader's movements:
-- (running, walking, stopping, sitting, but not jumping).
-- This is the lowest-priority action a bot will take.
-- All other activities will take precedence.
FOLLOW_DIST = 5
FOLLOW_TOLERANCE = 1

-- Bot will stop if it's farther away than this.
FOLLOW_MAX_DIST = 100

-- This is modified by target hitbox size.
MELEE_RANGE = 5
MELEE_DIST = 4
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

local function sendMovement(opcode)
	STATE.moving = false;
	local data = {
		flags = 0,
		pos = STATE.myLocation.position,
		o = STATE.myLocation.orientation,
		time = 0,
		fallTime = 0,
	}
	send(opcode, data);
end

function updateMyPosition(realTime)
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
	if(not m.startTime) then return; end
	local diffTime = realTime - m.startTime;
	p.x = p.x + m.dx * diffTime;
	p.y = p.y + m.dy * diffTime;
	m.startTime = realTime;
end

local function movementTimerCallback(t)
	--print("movementTimerCallback", t)
	decision(t);
	--print("movementTimerCallback ends", t)
end

function hMovement(opcode, p)
	--print("hMovement", fg(p.guid), opcode, p.flags)

	--print("p,l:", fg(p.guid), fg(STATE.leaderGuid));
	if(p.guid == STATE.leader.guid) then
		local realTime = getRealTime();
		updateMyPosition(realTime);
		--if(STATE.leader.movement.startTime) then
			--updateLeaderPosition(realTime);
			-- calculated leader position
			--local clp = STATE.leader.location.position;
			--print("clp, p:", dump(clp), dump(p.pos));
			--local d = diff3(clp, p.pos);
			--print("diff:", d.x, d.y);
		--end
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
		decision(realTime);
	end
end

-- returns the smallest number greater than or equal to zero.
local function minGEZ(a, b)
	local tMax = math.max(a, b);
	local tMin = math.min(a, b);
	if(tMin > 0) then
		return tMin;
	else
		return tMax;
	end
end

function doMoveToTarget(realTime, mo, maxDist)
	local myPos = STATE.myLocation.position;
	local tarPos = mo.location.position;
	local mov = mo.movement;
	local diff = diff3(myPos, tarPos);
	local dist = length3(diff);
	local newOrientation = orient2(diff);
	local oChanged = (STATE.myLocation.orientation ~= newOrientation);
	STATE.myLocation.orientation = newOrientation;
	--  or dist < (FOLLOW_DIST - FOLLOW_TOLERANCE)
	if(dist > maxDist) then
		--print("dist:", dist);
		local data = {
			flags = MOVEFLAG_FORWARD,
			pos = myPos,
			o = newOrientation,
			time = 0,
			fallTime = 0,
		}
		STATE.moving = true;
		--print(dump(data));
		send(MSG_MOVE_START_FORWARD, data);
		-- set timer to when we'll arrive, or at most one second.
		STATE.moveStartTime = realTime;

		-- if target is close, and moving in roughly the same direction and speed as us,
		-- wait longer before resetting our movement. otherwise,
		-- a target running away will cause tons of unneeded update packets.
		if(mov and (mov.dx ~=0 or mov.dy ~=0)) then
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
			local t = minGEZ(t1, t2);

			--print("a, b, c:", a, b, c);
			--print("dx, dy:", dx, dy);
			print("moving T:", t);
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
		print("still T:", timerTime - realTime);
		setTimer(movementTimerCallback, timerTime);
		return;
	elseif(STATE.moving) then
		--print("stop");
		myPos.z = tarPos.z;	--hack
		sendMovement(MSG_MOVE_STOP);
		if(not mov or (mov.dx == 0 and mov.dy == 0)) then
			removeTimer(movementTimerCallback);
			--print("removed timer.");
			return;
		end
	end
	if(oChanged) then
		sendMovement(MSG_MOVE_SET_FACING);
	end
	if(mov and (mov.dx ~= 0 or mov.dy ~= 0)) then
		-- see math-notes.txt, 2013-08-18 20:03:46
		local dx = mov.dx;
		local dy = mov.dy;
		local x = math.abs(tarPos.x - myPos.x);
		local y = math.abs(tarPos.y - myPos.y);
		local a = dx^2 + dy^2;
		local b = 2*(x*dx+y*dy);
		local c = (x^2+y^2-FOLLOW_DIST^2);
		assert(a ~= 0);
		local t1 = (-b + (b^2 - 4*a*c)^0.5) / (2*a);
		local t2 = (-b - (b^2 - 4*a*c)^0.5) / (2*a);
		local t = minGEZ(t1, t2);
		--print("inside t: "..t, "t1t2", t1, t2, "temp", (b^2 - 4*a*c), (b^2 - 4*a*c)^0.5,
			--"xyabc", x, y, a, b, c, "mov:"..dump(mov));
		if(t <= 0) then return; end
		setTimer(movementTimerCallback, realTime + t);
	end
end
