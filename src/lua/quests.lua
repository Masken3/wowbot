
function getQuests(giver)
	local dist = distanceToObject(giver);
	local res = doMoveToTargetIfNoHostilesAreNear(getRealTime(), giver, MELEE_DIST);
	if(res == nil) then return false; end
	if(dist <= MELEE_DIST) then
		if(not giver.bot.chatting) then
			if(isUnit(giver)) then
				send(CMSG_QUESTGIVER_HELLO, {guid=giver.guid});
			else
				send(CMSG_GAMEOBJ_USE, {guid=giver.guid});
			end
			giver.bot.chatting = true;
		end
	end
	return true;
end

function sendQuestQuery(questId, callback)
	local known = STATE.knownQuests[questId];
	if(known) then
		callback(known);
		return;
	end
	STATE.questQueryCallbacks[questId] = callback;
	send(CMSG_QUEST_QUERY, {questId=questId});
end

function hSMSG_QUEST_QUERY_RESPONSE(p)
	--print("SMSG_QUEST_QUERY_RESPONSE", dump(p));
	STATE.knownQuests[p.questId] = p;
	if(STATE.questQueryCallbacks[p.questId]) then
		STATE.questQueryCallbacks[p.questId](p);
		STATE.questQueryCallbacks[p.questId] = nil;
	end
end

local function wantQuest(q, p)
	local known = STATE.knownQuests[q.questId];
	if(q.title:find('Donation') or
		known.type == QUEST_TYPE_PVP)
	then
		local giver = STATE.knownObjects[p.guid];
		local npcId = giver.values[OBJECT_FIELD_ENTRY];
		if(giver.bot.questOverride) then return true; end
		partyChat("Avoiding npc="..npcId);
		PERMASTATE.avoidQuestGivers[npcId] = true;
		saveState();
		return false;
	end
	return true;
end

function hSMSG_QUESTGIVER_QUEST_LIST(p)
	print("SMSG_QUESTGIVER_QUEST_LIST", p.guid:hex(), p.title);
	for i,q in ipairs(p.quests) do
		sendQuestQuery(q.questId, function(k)
			if(not wantQuest(q, p)) then
				STATE.questGivers[p.guid] = nil;
				STATE.questFinishers[p.guid] = nil;
				return;
			end
			if((q.icon == DIALOG_STATUS_AVAILABLE) or
				(q.icon == DIALOG_STATUS_CHAT)) then
				print("Accpeting quest "..q.title.." ("..q.questId..")...");
				send(CMSG_QUESTGIVER_ACCEPT_QUEST, {guid=p.guid, questId=q.questId});
			end
			if((q.icon == DIALOG_STATUS_REWARD_REP) or
				(q.icon == DIALOG_STATUS_REWARD2)) then
				print("Finishing quest "..q.title.." ("..q.questId..")...");
				send(CMSG_QUESTGIVER_REQUEST_REWARD, {guid=p.guid, questId=q.questId});
			end
		end);
	end
	if(STATE.questGivers[p.guid]) then
		STATE.questGivers[p.guid].bot.chatting = false;
		STATE.questGivers[p.guid] = nil;
		print(countTable(STATE.questGivers).. " quest givers remaining.");
	end
	if(STATE.questFinishers[p.guid]) then
		print("Removing quest finisher "..p.guid:hex());
		STATE.questFinishers[p.guid].bot.chatting = false;
		STATE.questFinishers[p.guid] = nil;
	end
end

function hSMSG_GOSSIP_MESSAGE(p)
	print("SMSG_GOSSIP_MESSAGE", dump(p));
	hSMSG_QUESTGIVER_QUEST_LIST(p);
end

function hSMSG_QUESTGIVER_OFFER_REWARD(p)
	if(not p._quiet) then
		print("SMSG_QUESTGIVER_OFFER_REWARD", dump(p));
	end
	sendQuestQuery(p.questId, function(k)
		handleOfferReward(p)
	end);
end

function handleOfferReward(p)
	if(not wantQuest(p, p)) then
		return;
	end
	local rewardIndex = nil;
	-- pick the most valuable item that I want to wear.
	-- if I don't want to wear any of them, just pick the most valuable.
	-- we'll vendor or disenchant it.
	local wear = false;
	local maxValue = 0;

	-- we may have to wait for item data from the server.
	local haveItemData = true;
	for i, item in ipairs(p.rewChoiceItems) do
		if(not itemProtoFromId(item.itemId)) then
			haveItemData = false;
		end
	end
	if(not haveItemData) then
		-- p is a unique key.
		-- no other table can have its address as long as it's not garbage-collected.
		STATE.itemDataCallbacks[p] = hSMSG_QUESTGIVER_OFFER_REWARD;
		p._quiet = true;
		return;
	end

	-- if there are multiple items to wear,
	-- choose the one that would give the biggest difference in value.
	for i, item in ipairs(p.rewChoiceItems) do
		print("Item "..i..": "..item.itemId);
		local v = valueOfItem(item.itemId) * item.count;
		print("Value: "..v);
		local w, diff = wantToWear(item.itemId);
		print("Wear: "..tostring(w));
		local better = false;
		if(w) then
			v = diff;
			if(not wear) then
				better = true;
			end
			wear = true;
		end
		if((w == wear) and (v > maxValue)) then
			better = true;
		end
		if(better) then
			maxValue = v;
			rewardIndex = i;
		end
	end
	if(p.rewChoiceItemsCount > 0) then
		assert(rewardIndex);
		p.reward = rewardIndex - 1;
		send(CMSG_QUESTGIVER_CHOOSE_REWARD, p);
	else
		p.reward = 0;
		send(CMSG_QUESTGIVER_CHOOSE_REWARD, p);
	end
	-- could be problematic for multiple quests, but probably not.
	if(STATE.questFinishers[p.guid]) then
		print("Removing quest finisher "..p.guid:hex());
		STATE.questFinishers[p.guid].bot.chatting = false;
		STATE.questFinishers[p.guid] = nil;
	end
end

function finishQuests(finisher)
	local dist = distanceToObject(finisher);
	local res = doMoveToTargetIfNoHostilesAreNear(getRealTime(), finisher, MELEE_DIST);
	if(res == nil) then return false; end
	if(dist <= MELEE_DIST) then
		if(not finisher.bot.chatting) then
			if(isUnit(finisher)) then
				send(CMSG_QUESTGIVER_HELLO, {guid=finisher.guid});
			else
				send(CMSG_GAMEOBJ_USE, {guid=finisher.guid});
			end
			finisher.bot.chatting = true;
		end
	end
	return true;
end

function hSMSG_QUESTGIVER_REQUEST_ITEMS(p)
	print("SMSG_QUESTGIVER_REQUEST_ITEMS", dump(p));
	print("Finishing quest "..p.questId);
	send(CMSG_QUESTGIVER_REQUEST_REWARD, p);
end

function hSMSG_QUESTGIVER_QUEST_COMPLETE(p)
	partyChat("Finished quest "..p.questId);
end

function hSMSG_QUESTGIVER_QUEST_DETAILS(p)
	print("SMSG_QUESTGIVER_QUEST_DETAILS", dump(p));
	sendQuestQuery(p.questId, function(k)
		handleQuestDetails(p);
	end);
end

function handleQuestDetails(p)
	if(not wantQuest(p, p)) then
		return;
	end
	send(CMSG_QUESTGIVER_ACCEPT_QUEST, p);
	partyChat("Accepted quest "..p.questId.." "..p.title);
	local o = STATE.knownObjects[p.guid];
	if(o.bot.chatting) then
		o.bot.chatting = false;
		STATE.questGivers[p.guid] = nil;
		print(countTable(STATE.questGivers).. " quest givers remaining.");
	end
	send(CMSG_QUEST_QUERY, p);
end

function questLogin()
	for i=PLAYER_QUEST_LOG_1_1,PLAYER_QUEST_LOG_LAST_1,3 do
		local id = STATE.my.values[i];
		if(id and (id > 0)) then
			send(CMSG_QUEST_QUERY, {questId=id});
		end
	end
	send(CMSG_QUESTGIVER_STATUS_MULTIPLE_QUERY);
end

function hSMSG_QUESTGIVER_STATUS_MULTIPLE(p)
	--print("SMSG_QUESTGIVER_STATUS_MULTIPLE", dump(p));
	for i, giver in ipairs(p.givers) do
		hSMSG_QUESTGIVER_STATUS(giver);
	end
	STATE.checkNewObjectsForQuests = true;
	loginComplete();
	decision();
end

function hSMSG_QUESTGIVER_STATUS(p)
	--print("SMSG_QUESTGIVER_STATUS", dump(p));
	local o = STATE.knownObjects[p.guid];
	if(not o) then return; end
	local id = o.values[OBJECT_FIELD_ENTRY];
	if((not id) or (PERMASTATE.avoidQuestGivers[id] and
		(not o.bot.questOverride)))
	then
		return;
	end
	if((p.status == DIALOG_STATUS_AVAILABLE) or
		(p.status == DIALOG_STATUS_CHAT)) then
		print("Added quest giver "..p.guid:hex());
		STATE.questGivers[p.guid] = o;
	end
	if(--(p.status == DIALOG_STATUS_REWARD_REP) or
		(p.status == DIALOG_STATUS_REWARD2)) then
		print("Added quest finisher "..p.guid:hex());
		STATE.questFinishers[p.guid] = o;
	end
end

local function questItemCheck(itemId, objectiveTestFunction)
	-- check every quest
	--print("finding quests for item "..itemId.."...");
	for i=PLAYER_QUEST_LOG_1_1,PLAYER_QUEST_LOG_LAST_1,3 do
		local questId = STATE.my.values[i];
		local state = STATE.my.values[i+1];
		if(questId and (questId > 0) and ((not state) or (bit32.band(state, 0xFF) == QUEST_STATE_NONE))) then
			--print("checking active quest "..questId..": ", dump(STATE.knownQuests[questId].objectives));
			for j, o in ipairs(STATE.knownQuests[questId].objectives) do
				if((o.itemId == itemId) and objectiveTestFunction(o)) then
					print("found quest "..questId);
					return true;
				end
			end
		end
	end
	--print("none found.");
	return false;
end

function needsItemForQuest(itemId)
	-- we want all quest items.
	local proto = itemProtoFromId(itemId);
	if(proto.StartQuest ~= 0) then return true; end
	if(proto.Bonding == BIND_QUEST_ITEM) then return true; end

	return questItemCheck(itemId, function(o)
		return itemInventoryCountById(itemId) < o.itemCount;
	end);
end

function hasQuestForItem(itemId)
	return questItemCheck(itemId, function(o)
		return true;
	end);
end

function hSMSG_QUEST_CONFIRM_ACCEPT(p)
	print("SMSG_QUEST_CONFIRM_ACCEPT", dump(p));
	send(CMSG_QUEST_CONFIRM_ACCEPT, p);
end
