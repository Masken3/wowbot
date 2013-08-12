
function setTimer(callback, targetTime)
	if(STATE.inTimerCallback) then
		if(STATE.removedTimers[callback]) then
			STATE.removedTimers[callback] = nil
		end
		STATE.newTimers[callback] = targetTimer
		return
	end
	local timers = STATE.timers
	local closestTime = targetTime
	timers[callback] = targetTime
	for k, t in pairs(timers) do
		closestTime = math.min(closestTime, t)
	end
	cSetTimer(closestTime)
end

function countTable(tab)
	local c = 0;
	for _ in pairs(tab) do c = c + 1; end
	return c;
end

function removeTimer(callback)
	local timers = STATE.timers
	if(STATE.inTimerCallback) then
		if(STATE.newTimers[callback]) then
			STATE.newTimers[callback] = nil
		else
			assert(timers[callback])
			STATE.removedTimers[callback] = true
		end
		return
	end
	-- you may not remove a timer that doesn't exist.
	assert(timers[callback])
	local oldC = countTable(timers)
	local closestTime = timers[callback]
	local c = 0
	timers[callback] = nil	-- this should erase the element.
	for k, t in pairs(timers) do
		closestTime = math.min(closestTime, t)
		c = c + 1
	end
	assert(c == oldC - 1)	-- make sure the erasure worked.
	if(c == 0) then
		cRemoveTimer()
	else
		cSetTimer(closestTime)
	end
end

function luaTimerCallback(realTime)
	assert(not STATE.inTimerCallback)
	STATE.inTimerCallback = true
	STATE.newTimers = {}
	STATE.removedTimers = {}

	local timers = STATE.timers
	for k, t in pairs(timers) do
		if(realTime >= t) then
			removeTimer(k)	-- should erase the element without interrupting the for loop.
			-- however, this function may add or remove other timers. we must protect the array.
			k(realTime)
		end
	end

	-- apply any changes made during the callbacks.
	STATE.inTimerCallback = false
	for k, t in pairs(STATE.newTimers) do
		timers[k] = t
	end
	for k, t in pairs(STATE.removedTimers) do
		timers[k] = nil
	end
	-- check for remaining timers.
	local first = next(timers)
	if(not first) then
		return
	end
	-- reset the C timer.
	local closestTime = timers[first]
	for k, t in pairs(timers) do
		closestTime = math.min(closestTime, t)
	end
	cSetTimer(closestTime)
end
