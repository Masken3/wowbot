local function reply(p, msg)
	for i,m in ipairs(STATE.groupMembers) do
		if(p.senderGuid == m.guid) then
			p.targetName = m.name
		end
	end
	p.msg = msg
	send(CMSG_MESSAGECHAT, p)
end

local function listQuests(p)
	local msg = ''
	for i=0,19 do
		local id = STATE.my.values[PLAYER_QUEST_LOG_1_1 + i*3]
		-- including counters 6bits+6bits+6bits+6bits + state 8bits
		local state = STATE.my.values[PLAYER_QUEST_LOG_1_2 + i*3]
		-- in seconds. if 0, there is no timeout.
		local timeLeft = STATE.my.values[PLAYER_QUEST_LOG_1_3 + i*3]
		if(id ~= 0 and id ~= nil) then
			msg = msg..id.." "..STATE.knownQuests[id].title.."\n"
		end
	end
	reply(p, msg)
end

local function dropAllQuests(p)
	local msg = 'Dropped quests:'
	for i=0,19 do
		local id = STATE.my.values[PLAYER_QUEST_LOG_1_1 + i*3]
		if(id ~= 0 and id ~= nil) then
			msg = msg..' '..id
			send(CMSG_QUESTLOG_REMOVE_QUEST, {slot=i})
		end
	end
	reply(p, msg)
end

-- destroys all items in bags, but not equipped items.
-- does destroy unequipped bags.
local function dropAllItems(p)
	local msg = 'Dropped items:'
	investigateInventory(function(o, bagSlot, slot)
		msg = msg..o.values[OBJECT_FIELD_ENTRY]..' '..o.guid:hex().."\n"
		send(CMSG_DESTROYITEM, {slot = slot, bag = bagSlot,
			count = o.values[ITEM_FIELD_STACK_COUNT]})
	end)
	reply(p, msg)
end

local function listItems(p)
	local msg = 'Inventory: '
	local freeSlotCount = investigateInventory(function(o)
		local id = o.values[OBJECT_FIELD_ENTRY]
		local proto = itemProtoFromId(id)
		msg = msg..itemLink(o).." ("..id..') x'..o.values[ITEM_FIELD_STACK_COUNT].."\n"
	end)
	msg = msg..freeSlotCount.." slots free."
	reply(p, msg)
end

local function listBankItems(p)
	local msg = 'Bank: '
	local freeSlotCount = investigateBank(function(o)
		local id = o.values[OBJECT_FIELD_ENTRY]
		local proto = itemProtoFromId(id)
		msg = msg..itemLink(o).." ("..id..') x'..o.values[ITEM_FIELD_STACK_COUNT].."\n"
	end)
	msg = msg..freeSlotCount.." slots free."
	reply(p, msg)
end

local function listMoney(p)
	local msg = STATE.my.values[PLAYER_FIELD_COINAGE]..'c'
	reply(p, msg)
end

local function giveAll(p)
	reply(p, 'giving all...')
	STATE.tradeGiveAll = true
	send(CMSG_INITIATE_TRADE, {guid=p.senderGuid})
end

local function giveItem(p)
	local itemId = tonumber(p.text:sub(6))
	reply(p, 'giving item '..itemId..'...')
	STATE.tradeGiveItem = itemId
	send(CMSG_INITIATE_TRADE, {guid=p.senderGuid})
end

function hSMSG_TRADE_STATUS(p)
	if((p.status == TRADE_STATUS_OPEN_WINDOW) and STATE.tradeGiveAll) then
		STATE.tradeGiveAll = false
		print("TRADE_STATUS_OPEN_WINDOW")
		local tradeSlot = 0
		investigateInventory(function(o, bagSlot, slot)
			-- todo: skip soulbound items.
			send(CMSG_SET_TRADE_ITEM, {tradeSlot = tradeSlot, bag = bagSlot, slot = slot})
			print(tradeSlot..": "..o.values[OBJECT_FIELD_ENTRY]..' '..o.guid:hex())
			tradeSlot = tradeSlot + 1
			if(tradeSlot >= TRADE_SLOT_TRADED_COUNT) then
				return false
			end
		end)
		print("giving "..tradeSlot.." items...")
		send(CMSG_ACCEPT_TRADE, {padding=0})
	elseif((p.status == TRADE_STATUS_OPEN_WINDOW) and STATE.tradeGiveItem) then
		local tradeSlot = 0
		investigateInventory(function(o, bagSlot, slot)
			if(o.values[OBJECT_FIELD_ENTRY] == STATE.tradeGiveItem) then
				send(CMSG_SET_TRADE_ITEM, {tradeSlot = tradeSlot, bag = bagSlot, slot = slot})
				print(tradeSlot..": "..o.values[OBJECT_FIELD_ENTRY]..' '..o.guid:hex())
				tradeSlot = tradeSlot + 1
				if(tradeSlot >= TRADE_SLOT_TRADED_COUNT) then
					return false
				end
			end
		end)
		print("giving "..tradeSlot.." items...")
		STATE.tradeGiveItem = false
		send(CMSG_ACCEPT_TRADE, {padding=0})
	elseif(p.status == TRADE_STATUS_TRADE_CANCELED) then
		print("Trade cancelled!")
	elseif(p.status == TRADE_STATUS_TRADE_COMPLETE) then
		print("Trade complete!")
		STATE.me.updateValuesCallbacks[p] = function(p)
			investigateInventory(function(o)
				maybeEquip(o.guid)
			end)
		end
	elseif(p.status == TRADE_STATUS_BEGIN_TRADE) then
		-- player has requested to trade with us. just accept.
		print("Remote trade initiated!")
		send(CMSG_BEGIN_TRADE)
	else
		print("Trade status "..p.status)
	end
end

function hSMSG_TRADE_STATUS_EXTENDED(p)
	send(CMSG_ACCEPT_TRADE, {padding=0})
end

local function recreate(p)
	STATE.recreate = true
	send(CMSG_LOGOUT_REQUEST)
end

function hSMSG_LOGOUT_COMPLETE(p)
	if(STATE.recreate) then
		STATE.recreate = false
		send(CMSG_CHAR_DELETE, {guid=STATE.myGuid})
		send(CMSG_CHAR_ENUM)	-- should trigger character recreation.
	end
end

local function invite(p)
	STATE.newLeader = p.senderGuid;
	send(CMSG_NAME_QUERY, {guid=p.senderGuid})
	PERMASTATE.invitee = p.senderGuid:hex()
	saveState()
end

function hSMSG_NAME_QUERY_RESPONSE(p)
	send(CMSG_GROUP_INVITE, p)
end

local function dropItem(p)
	local itemId = tonumber(p.text:sub(6))
	local msg = 'Dropped items:'
	investigateInventory(function(o, bagSlot, slot)
		if(itemId == o.values[OBJECT_FIELD_ENTRY]) then
			msg = msg..o.values[OBJECT_FIELD_ENTRY]..' '..o.guid:hex().."\n"
			send(CMSG_DESTROYITEM, {slot = slot, bag = bagSlot,
				count = o.values[ITEM_FIELD_STACK_COUNT]})
		end
	end)
	reply(p, msg)
end

local function leave(p)
	send(CMSG_GROUP_DISBAND)
	reply(p, 'Leaving group.')
end

local function gameobject(p)
	local myPos = STATE.myLocation.position;
	-- find nearest usable gameobject.
	local closestPos;
	local closestObject;
	local count = 0;
	for guid, o in pairs(STATE.knownObjects) do
		if(isGameObject(o) and
			o.values[GAMEOBJECT_POS_X])
			--bit32.btest(o.values[GAMEOBJECT_DYN_FLAGS], GO_DYNFLAG_LO_ACTIVATE))
		then
			count = count + 1;
			-- problematic; stored as uint32, but are really float. how to convert? Use C.
			local pos = goPos(o);
			if((not closestObject) or (distance3(myPos, pos) < distance3(myPos, closestPos))) then
				closestPos = pos;
				closestObject = o;
			end
		end
	end
	print("Found "..count.." objects.");
	if(closestObject) then
		partyChat(closestObject.guid:hex()..": "..distance3(myPos, closestPos).." yards.");
		--send(CMSG_GAMEOBJ_USE, {guid=closestObject.guid});
		--castSpellAtGO(22810, closestObject);

		openGameobject(closestObject);
	else
		partyChat("No objects found.");
	end
end

local function train(p)
	if(p.type ~= CHAT_MSG_WHISPER) then
		reply(p, "Must whisper this command.");
	end
	local trainerGuid = guidFromValues(STATE.knownObjects[p.senderGuid], UNIT_FIELD_TARGET)
	local trainer = STATE.knownObjects[trainerGuid];
	if(not trainer) then
		reply(p, "No valid target!");
		return;
	end
	goTrain(trainer);
end

local function gather(p)
	local radius = tonumber(p.text:sub(8))
	PERMASTATE.gatherRadius = radius
	saveState()
	reply(p, "Gather radius set: "..radius)
end

local function cast(p)
	local spaceIdx, countIdx = p.text:find(' ', 6)
	local count
	local spellId
	--print(spaceIdx, countIdx, p.text:sub(6, spaceIdx-1), p.text:sub(6))
	if(countIdx) then
		count = tonumber(p.text:sub(countIdx))
		spellId = tonumber(p.text:sub(6, spaceIdx-1))
	else
		spellId = tonumber(p.text:sub(6))
	end
	local s = STATE.knownSpells[spellId]
	if(not s) then
		reply(p, "Don't know spell "..spellId)
		return
	end
	if(countIdx) then
		reply(p, "Will cast "..s.name.." "..s.rank.." "..count.." times.")
		STATE.repeatSpellCast.id = spellId
		STATE.repeatSpellCast.count = count
		decision()
		return
	end
	local targetGuid = guidFromValues(STATE.knownObjects[p.senderGuid], UNIT_FIELD_TARGET)
	local target = STATE.knownObjects[targetGuid]
	if(not target) then
		reply(p, "No valid target!")
		return
	end
	castSpellAtUnit(spellId, target)
	reply(p, "Casting "..s.name.." "..s.rank)
end

-- destroys all items in bags, but not equipped items.
-- does destroy unequipped bags.
local function sell(p)
	local itemId = tonumber(p.text:sub(6))
	local msg = 'Selling items:'
	investigateInventory(function(o, bagSlot, slot)
		if(itemId == o.values[OBJECT_FIELD_ENTRY]) then
			msg = msg..o.values[OBJECT_FIELD_ENTRY]..' '..o.guid:hex().."\n"
			--STATE.itemsToSell[o.guid] = {slot = slot, bag = bagSlot,
				--count = o.values[ITEM_FIELD_STACK_COUNT]}
			STATE.itemsToSell[itemId] = true
		end
	end)
	reply(p, msg)
	decision()
end

local function echo(p)
	print("echo", dump(p))
end

-- start fishing.
local function fish(p)
	if(not STATE.fishingSpell) then
		reply(p, "I don't know Fishing.")
		return
	end
	-- if no Fishing Pole is equipped, check our inventory for one and equip it.
	local eg = equipmentInSlot(EQUIPMENT_SLOT_MAINHAND)
	local eo = STATE.knownObjects[eg]
	if(not eo or not isFishingPole(eo)) then
		local success = false
		investigateInventory(function(o)
			-- we may have more than one pole. equip the first one.
			if(isFishingPole(o) and not success) then
				equip(o.guid, o.values[OBJECT_FIELD_ENTRY], EQUIPMENT_SLOT_MAINHAND)
				success = true
			end
		end)
		if(not success) then
			reply(p, "I don't have a Fishing Pole!")
			return
		end
	end
	STATE.fishing = true
	reply(p, "Started Fishing.")
end

local function stop(p)
	if(STATE.fishing) then
		STATE.fishing = false
		reply(p, "Stopped fishing.")
	end
end

local function useItem(p)
	local itemId = tonumber(p.text:sub(5))
	local msg = 'Using item:'
	local done = false
	investigateInventory(function(o, bagSlot, slot)
		if(itemId == o.values[OBJECT_FIELD_ENTRY] and not done) then
			msg = msg..' '..o.guid:hex()
			send(CMSG_USE_ITEM, {slot = slot, bag = bagSlot, spellCount = 0, targetFlags = 0})
			done = true
		end
	end)
	reply(p, msg)
end

local function disenchant(p)
	if(not STATE.disenchantSpell) then return end
	local itemId = tonumber(p.text:sub(5))
	local msg = 'Disenchanting item:'
	local done = false
	investigateInventory(function(o, bagSlot, slot)
		if(itemId == o.values[OBJECT_FIELD_ENTRY] and not done) then
			msg = msg..' '..o.guid:hex()
			castSpellAtItem(STATE.disenchantSpell, o)
			done = true
		end
	end)
	reply(p, msg)
end

local function store(p)
	local itemId = tonumber(p.text:sub(7))
	local msg = 'Storing items'
	local count = 0
	investigateInventory(function(o, bagSlot, slot)
		if(itemId == o.values[OBJECT_FIELD_ENTRY]) then
			msg = msg..' '..o.guid:hex()
			send(CMSG_AUTOSTORE_BANK_ITEM, {bag=bagSlot, slot=slot})
			count = count + o.values[ITEM_FIELD_STACK_COUNT];
		end
	end)
	msg = msg..', total '..count
	reply(p, msg)
end

local function fetch(p)
	local itemId = tonumber(p.text:sub(7))
	local msg = 'Fetching items'
	local count = 0
	investigateBank(function(o, bagSlot, slot)
		if(itemId == o.values[OBJECT_FIELD_ENTRY]) then
			msg = msg..' '..o.guid:hex()
			send(CMSG_AUTOSTORE_BANK_ITEM, {bag=bagSlot, slot=slot})
			count = count + o.values[ITEM_FIELD_STACK_COUNT];
		end
	end)
	msg = msg..', total '..count
	reply(p, msg)
end

local function repair(p)
	local targetGuid = guidFromValues(STATE.knownObjects[p.senderGuid], UNIT_FIELD_TARGET)
	local target = STATE.knownObjects[targetGuid]
	if(not target) then
		reply(p, "No valid target!")
		return
	end
	send(CMSG_REPAIR_ITEM, {npcGuid=targetGuid, itemGuid=ZeroGuid})
end

function handleChatMessage(p)
	if(not p.text) then return end
	if(p.text == 'lq') then
		listQuests(p)
	elseif(p.text == 'daq') then
		dropAllQuests(p)
	elseif(p.text == 'li') then
		listItems(p)
	elseif(p.text == 'dai') then
		dropAllItems(p)
	elseif(p.text:startWith('drop ')) then
		dropItem(p)
	elseif(p.text == 'lm') then
		listMoney(p)
	elseif(p.text == 'give all') then
		giveAll(p)
	elseif(p.text:startWith('give ')) then
		giveItem(p)
	elseif(p.text == 'recreate') then
		recreate(p)
	elseif(p.text == 'invite') then
		invite(p)
	elseif(p.text == 'leave') then
		leave(p)
	elseif(p.text == 'go') then
		gameobject(p)
	elseif(p.text == 'train') then
		train(p)
	elseif(p.text:startWith('gather ')) then
		gather(p)
	elseif(p.text:startWith('cast ')) then
		cast(p)
	elseif(p.text:startWith('sell ')) then
		sell(p)
	elseif(p.text:startWith('echo ')) then
		echo(p)
	elseif(p.text == 'fish') then
		fish(p)
	elseif(p.text == 'stop') then
		stop(p)
	elseif(p.text:startWith('use ')) then
		useItem(p)
	elseif(p.text:startWith('dis ')) then
		disenchant(p)
	elseif(p.text:startWith('store ')) then
		store(p)
	elseif(p.text == 'lb') then
		listBankItems(p)
	elseif(p.text == 'repair') then
		repair(p)
	else
		return
	end
	print("Chat command: "..p.text)
end

function partyChat(msg)
	print("partyChat("..msg..")");
	send(CMSG_MESSAGECHAT, {type=CHAT_MSG_PARTY, language=LANG_UNIVERSAL, msg=msg})
end
