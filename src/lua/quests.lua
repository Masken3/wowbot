
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
		print("Accpeting quest "..q.title.." ("..q.id..")...");
		send(CMSG_QUESTGIVER_ACCEPT_QUEST, {guid=p.guid, questId=q.id});
	end
	STATE.questGivers[p.guid].bot.chatting = false;
	STATE.questGivers[p.guid] = nil;
	print(countTable(STATE.questGivers).. " quest givers remaining.");
end

function finishQuests(finisher)
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
	decision();
end

function hSMSG_QUESTGIVER_STATUS(p)
	print("SMSG_QUESTGIVER_STATUS", dump(p));
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
