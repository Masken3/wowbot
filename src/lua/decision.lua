
-- implementation of the decision tree from notes.txt
function decision()
	--print("decision...");
	-- if we're already attacking someone, keep at it.
	if(false) then--STATE.meleeing) then
		if(keepAttacking()) then
			print("keep meleeing.");
			return;
		end
	end
	-- if an enemy targets a party member, attack that enemy.
	-- if there are several enemies, pick any one.
	local i, enemy = next(STATE.enemies);
	if(enemy) then
		attack(enemy);
		return;
	end
	STATE.meleeing = false;
	-- don't try following the leader if we don't know where he is.
	if(STATE.inGroup and STATE.leader.location.position.x) then
		follow(STATE.leader);
		print("Following...");
		return;
	end
	print("Nothing to do.");
end

function keepAttacking()
	-- if my target is still an enemy, keep attacking.
	return STATE.enemies[STATE.myTarget] ~= nil;
end

function follow(mo)
	doMoveToTarget(getRealTime(), mo, FOLLOW_DIST);
end

function attack(enemy)
	--STATE.attacking = true;
	-- todo: if we have a good ranged attack, use that.
	-- otherwise, go to melee.
	local dist = distanceToObject(enemy);
	print("attack, dist", dist);
	if(dist > MELEE_RANGE or STATE.moving) then
		doMoveToTarget(getRealTime(), enemy, MELEE_DIST);
	end
	if(dist < MELEE_RANGE and not STATE.meleeing) then
		print("start melee");
		setTarget(enemy);
		castSpell(STATE.meleeSpell, enemy);
		STATE.meleeing = true;
	end
end

function setTarget(t)
	STATE.myTarget = t.guid;
	send(CMSG_SET_SELECTION, {target=t.guid});
end
