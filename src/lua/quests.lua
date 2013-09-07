
function getQuests(giver)
	local dist = distanceToObject(giver);
	doMoveToTarget(getRealTime(), giver, MELEE_DIST);
	if(dist <= MELEE_DIST) then
		if(not giver.bot.chatting) then
			send(CMSG_QUESTGIVER_HELLO, {guid=giver.guid});
			giver.bot.chatting = true;
		end
	end
end

function hSMSG_QUESTGIVER_QUEST_LIST(p)
	print("SMSG_QUESTGIVER_QUEST_LIST", p.guid:hex(), p.title);
	for i,q in ipairs(p.quests) do
		if((q.icon == DIALOG_STATUS_AVAILABLE) or
			(q.icon == DIALOG_STATUS_CHAT)) then
			print("Accpeting quest "..q.title.." ("..q.id..")...");
			send(CMSG_QUESTGIVER_ACCEPT_QUEST, {guid=p.guid, questId=q.id});
		end
		if((q.icon == DIALOG_STATUS_REWARD_REP) or
			(q.icon == DIALOG_STATUS_REWARD2)) then
			print("Finishing quest "..q.title.." ("..q.id..")...");
			send(CMSG_QUESTGIVER_REQUEST_REWARD, {guid=p.guid, questId=q.id});
		end
	end
	STATE.questGivers[p.guid].bot.chatting = false;
	STATE.questGivers[p.guid] = nil;
	print(countTable(STATE.questGivers).. " quest givers remaining.");
end

function hSMSG_QUESTGIVER_OFFER_REWARD(p)
	if(not p._quiet) then
		print("SMSG_QUESTGIVER_OFFER_REWARD", dump(p));
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

	for i, item in ipairs(p.rewChoiceItems) do
		print("Item "..i..": "..item.itemId);
		local v = vendorSalePrice(item.itemId) * item.count;
		print("Value: "..v);
		local w = wantToWear(item.itemId);
		print("Wear: "..tostring(w));
		local better = false;
		if(w) then
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
		error("p.rewChoiceItemsCount == 0. What to do?");
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
	doMoveToTarget(getRealTime(), finisher, MELEE_DIST);
	if(dist <= MELEE_DIST) then
		if(not finisher.bot.chatting) then
			send(CMSG_QUESTGIVER_HELLO, {guid=finisher.guid});
			finisher.bot.chatting = true;
		end
	end
end

function hSMSG_QUESTGIVER_REQUEST_ITEMS(p)
	print("SMSG_QUESTGIVER_REQUEST_ITEMS", dump(p));
	print("Finishing quest "..p.questId);
	send(CMSG_QUESTGIVER_REQUEST_REWARD, p);
end

function hSMSG_QUESTGIVER_QUEST_COMPLETE(p)
	print("Finished quest "..p.questId);
end

function hSMSG_QUESTGIVER_QUEST_DETAILS(p)
	print("SMSG_QUESTGIVER_QUEST_DETAILS", dump(p));
	send(CMSG_QUESTGIVER_ACCEPT_QUEST, p);
	print("accepted quest "..p.questId);
	local o = STATE.knownObjects[p.guid];
	if(o.bot.chatting) then
		o.bot.chatting = false;
		STATE.questGivers[p.guid] = nil;
		print(countTable(STATE.questGivers).. " quest givers remaining.");
	end
end

function hSMSG_QUESTGIVER_STATUS_MULTIPLE(p)
	print("SMSG_QUESTGIVER_STATUS_MULTIPLE", dump(p));
	for i, giver in ipairs(p.givers) do
		hSMSG_QUESTGIVER_STATUS(giver);
	end
	STATE.checkNewObjectsForQuests = true;
	loginComplete();
	decision();
end

function hSMSG_QUESTGIVER_STATUS(p)
	--print("SMSG_QUESTGIVER_STATUS", dump(p));
	if((p.status == DIALOG_STATUS_AVAILABLE) or
		(p.status == DIALOG_STATUS_CHAT)) then
		print("Added quest giver "..p.guid:hex());
		STATE.questGivers[p.guid] = STATE.knownObjects[p.guid];
	end
	if((p.status == DIALOG_STATUS_REWARD_REP) or
		(p.status == DIALOG_STATUS_REWARD2)) then
		print("Added quest finisher "..p.guid:hex());
		STATE.questFinishers[p.guid] = STATE.knownObjects[p.guid];
	end
end