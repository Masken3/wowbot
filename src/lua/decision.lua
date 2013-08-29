
-- implementation of the decision tree from notes.txt
function decision()
	-- if we're already attacking someone, keep at it.
	if(STATE.attacking) then
		keepAttacking();
	end
	-- if an enemy targets a party member, attack that enemy.
	-- if there are several enemies, pick any one.
	local enemy = next(STATE.enemies);
	if(enemy) then
		attack(enemy);
		return;
	end
	if(STATE.inGroup) then
		follow(STATE.leader);
		return;
	end
	print("Nothing to do.");
end

function follow(mo)
	doMoveToTarget(getRealTime(), mo, FOLLOW_DIST);
end

function attack(enemy)
	STATE.attacking = true;
	-- todo: if we have a good ranged attack, use that.
	-- otherwise, go to melee.
	local dist = distanceToObject(enemy);
	if(dist > MELEE_DIST) then
		doMoveToTarget(getRealTime(), enemy, MELEE_DIST);
	end
	if(dist < MELEE_RANGE and not STATE.meleeing) then
		castSpell(STATE.meleeSpell, enemy);
		STATE.meleeing = true;
	end
end
