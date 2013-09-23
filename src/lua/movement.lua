
-- returns the distance between xyz points a and b.
function distance3(a, b)
	local dx = a.x - b.x
	local dy = a.y - b.y
	local dz = a.z - b.z
	local square = dx^2 + dy^2 + dz^2
	return square^0.5
end

local function distance2(a, b)
	local dx = a.x - b.x
	local dy = a.y - b.y
	local square = dx^2 + dy^2
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

-- returns the length of xy vector v.
local function length2(v)
	local square = v.x^2 + v.y^2
	return square^0.5
end

-- returns the orientation, in radians, of the xy vector v.
local function orient2(v)
	return math.atan2(v.y, v.x);
end

function distanceToObject(o)
	-- todo: fix 3D movement and change this back to distance3.
	return distance2(STATE.myLocation.position, o.location.position);
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

local function runSpeed(target)
	local slow = GetMaxNegativeAuraModifier(target, SPELL_AURA_MOD_DECREASE_SPEED);
	return RUN_SPEED * (100 + slow) / 100;
end

local function myRunSpeed()
	return runSpeed(STATE.me);
end

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
	p.x = p.x + math.cos(o) * diffTime * myRunSpeed();
	p.y = p.y + math.sin(o) * diffTime * myRunSpeed();
	STATE.moveStartTime = realTime;
end

function updateLeaderPosition(realTime)
	if(not STATE.leader) then return; end
	local p = STATE.leader.location.position;
	local m = STATE.leader.movement;
	if(not m or not m.startTime) then return; end
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

function hMSG_MOVE_TELEPORT_ACK(p)
	print("MSG_MOVE_TELEPORT_ACK", dump(p));
	STATE.myLocation.position = Position.new(p.pos);
	STATE.myLocation.orientation = p.o;
	send(MSG_MOVE_TELEPORT_ACK, p);
end

function hMovement(opcode, p)
	--print("hMovement", fg(p.guid), opcode, p.flags)

	--print("p,l:", fg(p.guid), fg(STATE.leaderGuid));
	if(STATE.leader and p.guid == STATE.leader.guid) then
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
		if(f == MOVEFLAG_NONE) then
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
			--print("Warning: MOVEFLAG_TURN_LEFT unhandled!");
		end
		if(bit32.btest(f, MOVEFLAG_PITCH_UP)) then
			assert(not bit32.btest(f, MOVEFLAG_PITCH_DOWN));
			-- todo: figure out what this means. is it ever used?
			print("Warning: MOVEFLAG_PITCH_UP unhandled!");
		end
		-- normalize vector.
		local factor = speed;
		if(x ~= 0 and y ~= 0) then
			-- multiply vector by half the square root of 2.
			factor = factor * ((2^0.5) / 2);
		end
		if(not STATE.leader.movement) then STATE.leader.movement = Movement.new(); end
		--print("factor: "..factor.." x: "..x.." y: "..y);
		STATE.leader.movement.dx = y * factor * math.cos(p.o) + x * factor * math.cos(p.o - math.pi/2);
		STATE.leader.movement.dy = y * factor * math.sin(p.o) + x * factor * math.sin(p.o - math.pi/2);
		STATE.leader.movement.startTime = realTime;

		-- todo: handle the case of being on different maps.
		--print("leaderMovement", realTime);
		decision(realTime);
	end
end

local function updateMonsterPosition(realTime, o)
	local i, pp = next(STATE.pickpocketables);
	if(pp and o.guid == pp.guid) then
		--print("updateMonsterPosition", o.guid:hex());
	end

	-- todo: enable handling of more than 1 points.
	local mm = o.monsterMovement;
	if(not mm) then return; end
	local mov = o.movement;
	local dst = mm.dst;
	if(not mm or not mov or not dst) then return; end
	local elapsedTime = realTime - mov.startTime;
	if(realTime >= mm.endTime) then
		if(pp and o.guid == pp.guid) then
			--print("Monster stop.");
		end
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
	for guid, o in pairs(STATE.pickpocketables) do
		updateMonsterPosition(realTime, o);
		c = c + 1;
	end
end

function hSMSG_MONSTER_MOVE(p)
	local i, pp = next(STATE.pickpocketables);
	if(pp and p.guid == pp.guid) then
		--print("SMSG_MONSTER_MOVE", dump(p));
	end

	local o = STATE.knownObjects[p.guid];
	if(not o) then return; end
	o.monsterMovement = p;
	o.location.position = o.location.position or Position.new(p.point);
	local loc = o.location;
	o.movement = o.movement or Movement.new();
	local pos = loc.position;
	local mov = o.movement;
	mov.dx = 0;
	mov.dy = 0;
	if(p.type == MonsterMoveStop) then return; end
	local dur = p.duration / 1000;
	-- save destination in unused key "dst".
	local dst;
	if(p.count) then
		assert(p.count <= 1);
		if(p.count == 0) then return; end
		-- todo: enable handling of more than 1 points.
		p.dst = p.point;
	else
		p.dst = p.destination;
	end

	if(p.type == MonsterMoveNormal) then
		loc.orientation = orient2(diff3(pos, p.dst));
	elseif(p.type == MonsterMoveFacingTarget) then
		local spot = STATE.knownObjects[p.target].location.position;
		loc.orientation = orient2(diff3(pos, spot));
	elseif(p.type == MonsterMoveFacingSpot) then
		loc.orientation = orient2(diff3(pos, p.spot));
	elseif(p.type == MonsterMoveFacingAngle) then
		loc.orientation = p.angle;
	end

	mov.dx = (p.dst.x - pos.x) / dur;
	mov.dy = (p.dst.y - pos.y) / dur;
	mov.startTime = getRealTime();
	p.endTime = mov.startTime + dur;
	-- don't bother with timers; we can update all of them at decision time.
	decision();
end

function hMSG_MOVE_HEARTBEAT(p)
	print("MSG_MOVE_HEARTBEAT", dump(p));
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

function aggroRadius(target)
	-- maximum effective level diff: 25.
	local levelDiff = math.max(STATE.myLevel - target.values[UNIT_FIELD_LEVEL], -25);
	-- base radius: 20 yards.
	-- varies with 1 yard per level.
	-- minimum radius: 5 yards (melee distance).
	local radius = math.max(20 - levelDiff, 5);
	return radius;
end

local function closestOrientedPosition(mo, angleFactor, dist)
	local tarPos = mo.location.position;
	local tarO = mo.location.orientation;
	local myPos = STATE.myLocation.position;

	local dx = math.cos(tarO + math.pi*angleFactor) * dist;
	local dy = math.sin(tarO + math.pi*angleFactor) * dist;
	local rearPos1 = {x=tarPos.x+dx, y=tarPos.y+dy, z=math.max(tarPos.z, myPos.z)};
	local dx = math.cos(tarO - math.pi*angleFactor) * dist;
	local dy = math.sin(tarO - math.pi*angleFactor) * dist;
	local rearPos2 = {x=tarPos.x+dx, y=tarPos.y+dy, z=math.max(tarPos.z, myPos.z)};
	local rearPos;
	if(distance2(myPos, rearPos1) < distance2(myPos, rearPos2)) then
		return rearPos1;
	else
		return rearPos2;
	end
end

-- returns true if we're stopped in a proper position.
function doStealthMoveBehindTarget(realTime, mo, maxDist)
	local myPos = STATE.myLocation.position;
	local tarPos = mo.location.position;
	local tarO = mo.location.orientation;
	local mov = mo.movement;
	local diff = diff3(myPos, tarPos);
	local dist = length2(diff);
	local newOrientation = orient2(diff);

	-- max oDiff is pi radians, 180 degrees.
	if(newOrientation < 0) then newOrientation = newOrientation + math.pi*2; end
	local oDiff = math.abs(newOrientation - tarO);
	--print("dist: "..dist);
	--print("newOrientation: "..newOrientation, "tarO: "..tarO);
	if(oDiff > math.pi) then
		--print("orig oDiff: "..oDiff);
		oDiff = math.pi*2 - oDiff;
	end
	--print("oDiff: "..oDiff);
	assert(oDiff <= math.pi);

	local isBehind = oDiff < (math.pi / 4);	-- 45 degrees
	if(isBehind) then
		--setAction("Moving to rear...");
		return doMoveToTarget(realTime, mo, maxDist);
	end
	if(oDiff < (math.pi / 2)) then	-- 90 degrees
		-- move to a point 45 degrees behind target, at maxDist.
		local rearPos = closestOrientedPosition(mo, 0.75, maxDist);
		--setAction("Moving to side-rear...");
		return doMoveToPoint(realTime, rearPos);
	else
		if(dist < (maxDist * 2)) then
			-- we're too close. gotta move away before we can safely walk around.
			-- conflicts with "move to side".
			local dx = math.cos(newOrientation) * -maxDist*2;
			local dy = math.sin(newOrientation) * -maxDist*2;
			local safePos = {x=tarPos.x+dx, y=tarPos.y+dy, z=math.max(tarPos.z, myPos.z)};
			--setAction("Moving to safe position...");
			return doMoveToPoint(realTime, safePos);
		else
			-- move to a point 90 degrees off tarO, at maxDist * 3.
			local sidePos = closestOrientedPosition(mo, 0.5, maxDist*3);
			--setAction("Moving to side...");
			return doMoveToPoint(realTime, sidePos);
		end
	end
end

-- returns true if behind and stopped and close enough.
function doCombatMoveBehindTarget(realTime, mo)
	local myPos = STATE.myLocation.position;
	local tarPos = mo.location.position;
	local tarO = mo.location.orientation;
	local mov = mo.movement;
	local diff = diff3(myPos, tarPos);
	local dist = length2(diff);
	local newOrientation = orient2(diff);
	local maxDist = MELEE_DIST;

	if(newOrientation < 0) then newOrientation = newOrientation + math.pi*2; end
	local oDiff = math.abs(newOrientation - tarO);
	if(oDiff > math.pi) then
		oDiff = math.pi*2 - oDiff;
	end
	assert(oDiff <= math.pi);

	local isBehind = oDiff < (math.pi / 2);	-- 90 degrees
	if(isBehind) then
		return doMoveToTarget(realTime, mo, maxDist);
	end

	-- we're in front of the target. run past it, then turn around.
	local dx = math.cos(newOrientation) * maxDist/2;
	local dy = math.sin(newOrientation) * maxDist/2;
	local attackPos = {x=tarPos.x+dx, y=tarPos.y+dy, z=math.max(tarPos.z, myPos.z)};
	doMoveToPoint(realTime, attackPos);
	return false;
end

-- returns true if we're stopped in a proper position, which for this function is never.
function doMoveToPoint(realTime, tarPos)
	local myPos = STATE.myLocation.position;
	local diff = diff3(myPos, tarPos);
	local dist = length2(diff);
	local newOrientation = orient2(diff);
	local oChanged = (STATE.myLocation.orientation ~= newOrientation);
	STATE.myLocation.orientation = newOrientation;
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
	local moveEndTime = STATE.moveStartTime + dist / myRunSpeed();
	--print("tToPoint: "..(moveEndTime - realTime));
	setTimer(movementTimerCallback, moveEndTime);
	return false;
end

-- returns true if we're stopped in a proper position.
function doMoveToTarget(realTime, mo, maxDist)
	local myPos = STATE.myLocation.position;
	local tarPos = mo.location.position;
	local mov = mo.movement;
	local diff = diff3(myPos, tarPos);
	-- todo: fix 3D movement and change this back to length3.
	local dist = length2(diff);
	local newOrientation = orient2(diff);
	local oChanged = (STATE.myLocation.orientation ~= newOrientation);
	STATE.myLocation.orientation = newOrientation;
	myPos.z = math.min(STATE.leader.location.position.z + 3, math.max(myPos.z, tarPos.z));	--hack
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
			local dx = math.cos(data.o) * myRunSpeed();
			local dy = math.sin(data.o) * myRunSpeed();
			local t1 = (maxDist*((a^2+b^2)^0.5) - (a*x+b*y+c)) / (a*dx+b*dy);
			local t2 = (maxDist*((a^2+b^2)^0.5) + a*x+b*y+c) / -(a*dx+b*dy);
			local t = minGEZ(t1, t2);

			--print("a, b, c:", a, b, c);
			--print("dx, dy:", dx, dy);
			--print("moving T:", t);
			if(t > 0) then
				setTimer(movementTimerCallback, realTime + t);
			end
			return false;
		end

		local moveEndTime = STATE.moveStartTime + (dist - maxDist) / myRunSpeed();
		--local timerTime = math.min(moveEndTime, STATE.moveStartTime + 1);
		local timerTime = moveEndTime;
		--print("still T:", timerTime - realTime);
		setTimer(movementTimerCallback, timerTime);
		return false;
	elseif(STATE.moving) then
		--print("stop");
		myPos.z = tarPos.z;	--hack
		sendMovement(MSG_MOVE_STOP);
		if(not mov or (mov.dx == 0 and mov.dy == 0)) then
			removeTimer(movementTimerCallback, true);
			--print("removed timer.");
			return true;
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
		if(t > 0) then
			setTimer(movementTimerCallback, realTime + t);
		else
			sendMovement(MSG_MOVE_STOP);
		end
	end
	return true;
end
