local function reply(p, msg)
	p.targetGuid = p.senderGuid
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
			msg = msg..id.."\n"
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
	-- backpack only for now.
	for i = PLAYER_FIELD_PACK_SLOT_1, PLAYER_FIELD_PACK_SLOT_LAST, 2 do
		local guid = guidFromValues(STATE.me, i)
		if(isValidGuid(guid)) then
			local o = STATE.knownObjects[guid]
			msg = msg..o.values[OBJECT_FIELD_ENTRY]..' '..guid:hex().."\n"
			send(CMSG_DESTROYITEM, {
				slot = INVENTORY_SLOT_ITEM_START + ((i - PLAYER_FIELD_PACK_SLOT_1) / 2),
				bag = INVENTORY_SLOT_BAG_0,
				count = o.values[ITEM_FIELD_STACK_COUNT],
			})
		end
	end
	reply(p, msg)
end

local function listItems(p)
	local msg = 'Backpack items:'
	-- backpack only for now.
	for i = PLAYER_FIELD_PACK_SLOT_1, PLAYER_FIELD_PACK_SLOT_LAST, 2 do
		local guid = guidFromValues(STATE.me, i)
		if(isValidGuid(guid)) then
			local o = STATE.knownObjects[guid]
			msg = msg..o.values[OBJECT_FIELD_ENTRY]..' '..guid:hex().."\n"
		end
	end
	reply(p, msg)
end

local function listMoney(p)
	local msg = STATE.my.values[PLAYER_FIELD_COINAGE]..'c'
	reply(p, msg)
end

local function giveAll(p)
	reply(p, 'giving all...')
	send(CMSG_INITIATE_TRADE, {guid=p.senderGuid})
end

function hSMSG_TRADE_STATUS(p)
	if(p.status == TRADE_STATUS_OPEN_WINDOW) then
		print("TRADE_STATUS_OPEN_WINDOW")
		local tradeSlot = 0
		for i = PLAYER_FIELD_PACK_SLOT_1, PLAYER_FIELD_PACK_SLOT_LAST, 2 do
			local guid = guidFromValues(STATE.me, i)
			if(isValidGuid(guid)) then
				local o = STATE.knownObjects[guid]
				send(CMSG_SET_TRADE_ITEM, {
					tradeSlot = tradeSlot,
					bag = INVENTORY_SLOT_BAG_0,
					slot = INVENTORY_SLOT_ITEM_START + ((i - PLAYER_FIELD_PACK_SLOT_1) / 2),
				})
				print(tradeSlot..": "..o.values[OBJECT_FIELD_ENTRY]..' '..guid:hex())
				tradeSlot = tradeSlot + 1
				if(tradeSlot >= TRADE_SLOT_TRADED_COUNT) then
					break
				end
			end
		end
		print("giving "..tradeSlot.." items...")
		send(CMSG_ACCEPT_TRADE, {padding=0})
	elseif(p.status == TRADE_STATUS_TRADE_CANCELED) then
		print("Trade cancelled!")
	elseif(p.status == TRADE_STATUS_TRADE_COMPLETE) then
		print("Trade complete!")
	else
		print("Trade status "..p.status)
	end
end

function handleChatMessage(p)
	if(p.text == 'lq') then
		listQuests(p)
	elseif(p.text == 'daq') then
		dropAllQuests(p)
	elseif(p.text == 'li') then
		listItems(p)
	elseif(p.text == 'dai') then
		dropAllItems(p)
	elseif(p.text == 'lm') then
		listMoney(p)
	elseif(p.text == 'give all') then
		giveAll(p)
	end
end

function partyChat(msg)
	send(CMSG_MESSAGECHAT, {type=CHAT_MSG_PARTY, language=LANG_UNIVERSAL, msg=msg})
end
