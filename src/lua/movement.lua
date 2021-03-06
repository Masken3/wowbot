
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

local function add3(a, b)
	local d = {}
	d.x = b.x + a.x
	d.y = b.y + a.y
	d.z = b.z + a.z
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

-- my, target, dist
function contactPoint(m, t, dist)
	local diff = diff3(m, t);
	local len = length3(diff);
	if(len < dist) then return m; end
	local f = (len - dist) / len;
	return Position.new({x = m.x + diff.x*f, y = m.y + diff.y*f, z = m.z + diff.z*f});
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

-- AreaTrigger Hash function
local function ath(x)
	return math.floor(x/100)
end

local function loadAreaTriggers()
	local t = {}
	local function addAT(at)
		local xv, xm = ath(at.x - at.radius), ath(at.x + at.radius);
		local yv, ym = ath(at.y - at.radius), ath(at.y + at.radius);
		local zv, zm = ath(at.z - at.radius), ath(at.z + at.radius);
		local m = t[at.map] or {};
		t[at.map] = m;
		for x = xv,xm do
			m[x] = m[x] or {};
			for y = yv,ym do
				m[x][y] = m[x][y] or {};
				for z = zv,zm do
					m[x][y][z] = m[x][y][z] or {};
					m[x][y][z][at.id] = at;
				end
			end
		end
	end
	local count = 0;
	for at in cAreaTriggers() do
		addAT(at);
		count = count + 1;
	end
	print("Loaded "..count.." AreaTriggers");
	return t;
end

sAreaTriggers = rawget(_G, 'sAreaTriggers') or loadAreaTriggers();

-- returns AreaTrigger table or false.
local function areaTriggerFromPos(pos)
	local map = sAreaTriggers[STATE.myLocation.mapId];
	local at = cAreaTrigger(362);
	--print("x: "..pos.x..". target: "..at.x + at.radius.." ("..at.radius..")");
	local x = map[ath(pos.x)];
	if(not x) then return false; end
	--print("y: "..pos.y..". target: "..at.y + at.radius);
	local y = x[ath(pos.y)];
	if(not y) then return false; end
	--print("z: "..pos.z..". target: "..at.z + at.radius);
	local z = y[ath(pos.z)];
	if(not z) then return false; end
	for id,at in pairs(z) do
		-- factor 0.75 to be on the safe side; server does more advanced checking than this,
		-- and since we only get one try, we don't want to fail.
		local d = distance3(pos, at);
		local r = at.radius;
		--print("Near AT "..id..": "..math.floor(d).." < "..math.floor(r));
		if(distance3(pos, at) < at.radius * 0.75) then
			return at;
		end
	end
	return false;
end

local function sendMovePacket(opcode, data)
	local at = areaTriggerFromPos(data.pos);
	if(at and STATE.areaTrigger ~= at) then
		partyChat("AreaTrigger "..at.id);
		send(CMSG_AREATRIGGER, {triggerID = at.id});
	end
	STATE.looting = false;
	STATE.areaTrigger = at;
	send(opcode, data);
end

function sendMovement(opcode)
	STATE.moving = false;
	local data = {
		flags = 0,
		pos = STATE.myLocation.position,
		o = STATE.myLocation.orientation,
		time = 0,
		fallTime = 0,
	}
	sendMovePacket(opcode, data);
end

function stopMoveWithOrientation(o)
	STATE.moving = false;
	local data = {
		flags = 0,
		pos = STATE.myLocation.position,
		o = o,
		time = 0,
		fallTime = 0,
	}
	sendMovePacket(MSG_MOVE_STOP, data);
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

function hSMSG_NEW_WORLD(p)
	print("SMSG_NEW_WORLD", dump(p));
	STATE.myLocation.mapId = p.mapId;
	STATE.myLocation.position = Position.new(p.pos);
	STATE.myLocation.orientation = p.o;
	-- prep for re-initialize.
	STATE.meleeSpell = false;
	STATE.pickpocketSpell = false;
	--STATE.leader = false;
	STATE.checkNewObjectsForQuests = false;
	-- ought to work.
	send(MSG_MOVE_WORLDPORT_ACK);
	moveStop();
end

function hMSG_MOVE_TELEPORT_ACK(p)
	print("MSG_MOVE_TELEPORT_ACK", dump(p));
	STATE.myLocation.position = Position.new(p.pos);
	STATE.myLocation.orientation = p.o;

	STATE.looting = false;

	-- assume all party members moved with you
	for i,m in ipairs(STATE.groupMembers) do
		local o = STATE.knownObjects[m.guid];
		if(o) then
			o.location = o.location or Location.new();
			o.location.position = Position.new(p.pos);
		end
	end

	send(MSG_MOVE_TELEPORT_ACK, p);
	moveStop();
end

function hMovement(opcode, p)
	--print("hMovement ", p.guid:hex(), opcode, p.flags)
	local o = STATE.knownObjects[p.guid];

	--print("p,l:", fg(p.guid), fg(STATE.leaderGuid));
	if(o) then
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
		o.location.position.x = p.pos.x;
		o.location.position.y = p.pos.y;
		o.location.position.z = p.pos.z;
		o.location.orientation = p.o;

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
		o.movement = o.movement or Movement.new();
		--print("factor: "..factor.." x: "..x.." y: "..y);
		o.movement.dx = y * factor * math.cos(p.o) + x * factor * math.cos(p.o - math.pi/2);
		o.movement.dy = y * factor * math.sin(p.o) + x * factor * math.sin(p.o - math.pi/2);
		o.movement.startTime = realTime;

		-- todo: handle the case of being on different maps.

		if(STATE.leader and p.guid == STATE.leader.guid) then
			--print("leaderMovement", realTime, distanceToObject(STATE.leader), dump(p.pos));
			--assert(o == STATE.leader);
			STATE.leader = o;
			decision(realTime);
		end
		if(p.guid == STATE.myGuid) then
			print("WTF: got own movement?");
		end
	elseif(p.guid == STATE.leaderGuid) then
		print("WARNING: lost track of leader!");
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
		--print(c.." enemies.");
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
	sendMovePacket(MSG_MOVE_START_FORWARD, data);
	-- set timer to when we'll arrive, or at most one second.
	STATE.moveStartTime = realTime;
	local moveEndTime = STATE.moveStartTime + dist / myRunSpeed();
	--print("tToPoint: "..(moveEndTime - realTime));
	setTimer(movementTimerCallback, moveEndTime);
	return false;
end

-- returns a, b, c in ax + by = c
-- see math-notes.txt, 16:05 2013-11-10
local function lineFromPoints(p1, p2)
	local a, b, c;
	if(p1.x == p2.x) then	-- vertical
		a = 1;
		b = 0;
		c = -p1.x;
	else
		local m = (p1.y - p2.y) / (p1.x - p2.x);
		a = m;
		b = -1;
		-- (mx - y = c) for all x,y pairs on the line, so we can just pick one of the pairs we know.
		c = (m*p1.x) - p1.y;
	end
	return a, b, c;
end

function getClosest(c, objects)
	for i,o in pairs(objects) do
		if(distanceToObject(o) < distanceToObject(c)) then
			c = o;
		end
	end
	return c;
end

-- returns true if we've arrived, false if still moving,
-- nil if enemies are nearby or it's otherwise impossible to move to target.
function doMoveToTargetIfNoHostilesAreNear(realTime, mo, maxDist)
	local myPos = STATE.my.location.position;
	local tarPos = mo.location.position;
	local diff = diff3(myPos, tarPos);

	-- if we're close enough, ignore hostiles.
	local dist = length2(diff);
	if(dist < maxDist) then goto continue; end

	-- our calculations are 2D, so don't move in 3D.
	if(math.abs(diff.z) > 10) then
		objectNameQuery(mo, function(name)
			print("diff.z: "..diff.z.." ("..name..")");
		end);
		return nil;
	end

	do
		local a, b, c = lineFromPoints(myPos, tarPos);
		for guid,o in pairs(STATE.hostiles) do
			if(isAlive(o)) then
				local p = o.location.position;
				local distToLine = (a*p.x + b*p.y - c) / ((a^2 + b^2)^0.5);
				local distToMe = distanceToObject(o);
				--if((distToLine < 40) and (distToMe < 80)) then return nil; end
				if(distToMe < 60) then
					objectNameQuery(mo, function(targetName)
						objectNameQuery(o, function(hostileName)
							print("would go to "..targetName..", but "..hostileName.." is only "..distToMe.." yards away.");
						end);
					end);
					return nil;
				end
			end
		end
	end
	::continue::
	return doMoveToTarget(realTime, mo, maxDist);
end

-- returns true if we're stopped in a proper position, false otherwise.
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
	myPos.z = math.max(myPos.z, tarPos.z);	--hack
	if(STATE.leader) then
		myPos.z = math.min(STATE.leader.location.position.z + 3, myPos.z);
	end
	--  or dist < (FOLLOW_DIST - FOLLOW_TOLERANCE)
	assert(dist >= 0);
	if(dist > maxDist) then
		if(dist > 100) then
			print("dist:", dist, mo.guid:hex());
		end
		local data = {
			flags = MOVEFLAG_FORWARD,
			pos = myPos,
			o = newOrientation,
			time = 0,
			fallTime = 0,
		}
		STATE.moving = true;
		--print(dump(data));
		sendMovePacket(MSG_MOVE_START_FORWARD, data);
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
	elseif(oChanged) then
		sendMovement(MSG_MOVE_SET_FACING);
	end
	assert(not STATE.moving);
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
		end
	end
	return true;
end

function moveStop()
	if(STATE.moving) then
		sendMovement(MSG_MOVE_STOP);
		STATE.moving = false;
	end
end

-- move 1 yard away from any group member who is closer than that.
function doMoveApartFromGroup(realTime)
	if(realTime < (STATE.my.bot.nextMoveApart or 0)) then return false; end
	for i,m in ipairs(STATE.groupMembers) do
		local o = STATE.knownObjects[m.guid];
		if(o) then
			local d = diff3(STATE.my.location.position, o.location.position);
			local l = length3(d);
			if(l < 1) then
				-- todo: let length of d be 1, not l.
				if(l == 0) then
					d = {x=math.random()*0.3, y=math.random()*0.3, z=0}
				end
				setAction('moving apart');
				doMoveToPoint(realTime, diff3(d, STATE.my.location.position));
				STATE.my.bot.nextMoveApart = realTime + 0.1;	-- rate limit
				return true;
			end
		end
	end
	return false;
end
