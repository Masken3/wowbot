
function setTimer(callback, targetTime)
	--print("setTimer", debug.getinfo(callback).name, targetTime)
	if(STATE.inTimerCallback) then
		if(STATE.removedTimers[callback]) then
			STATE.removedTimers[callback] = nil
		end
		assert(targetTime > STATE.callbackTime);
		STATE.newTimers[callback] = targetTime
		--print("inTimerCallback");
		return
	end
	assert(targetTime > getRealTime()-1);
	local timers = STATE.timers
	local closestTime = targetTime
	timers[callback] = targetTime
	for k, t in pairs(timers) do
		closestTime = math.min(closestTime, t)
	end
	cSetTimer(closestTime)
end

local function argEqual(a, b)
	if(a.n ~= b.n) then return false; end
	for i, av in ipairs(a) do
		if(av ~= b[i]) then return false; end
	end
	return true;
end

-- sets a timer uniquely defined by its function and argument values.
-- the callback gets the args.
function setArgTimer(callback, targetTime, ...)
	error("not implemented");
end

function removeTimer(callback)
	--print("removeTimer", debug.getinfo(callback).name)
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
	--print("luaTimerCallback", realTime);
	assert(not STATE.inTimerCallback)
	STATE.callbackTime = realTime
	STATE.inTimerCallback = true
	STATE.newTimers = {}
	STATE.removedTimers = {}

	local timers = STATE.timers
	for k, t in pairs(timers) do
		--print("timer", realTime, t);
		if(realTime >= t) then
			removeTimer(k)	-- should erase the element without interrupting the for loop.
			-- however, this function may add or remove other timers. we must protect the array.
			local res, err = xpcall(k, cTraceback, realTime)
			if(not res) then
				print(err);
			end
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
		--print("no timers remaining");
		return
	end
	-- reset the C timer.
	local closestTime = timers[first]
	local count = 0
	for k, t in pairs(timers) do
		closestTime = math.min(closestTime, t)
		count = count +1
	end
	--print("closestTime", count, closestTime, realTime);
	assert(closestTime > realTime);
	cSetTimer(closestTime)
end
