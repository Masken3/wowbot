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
	investigateInventory(function(o, bagSlot, slot)
		msg = msg..o.values[OBJECT_FIELD_ENTRY]..' '..o.guid:hex().."\n"
		send(CMSG_DESTROYITEM, {slot = slot, bagSlot = bagSlot,
			count = o.values[ITEM_FIELD_STACK_COUNT]})
	end)
	reply(p, msg)
end

local function listItems(p)
	local msg = 'Inventory items:'
	investigateInventory(function(o)
		msg = msg..o.values[OBJECT_FIELD_ENTRY]..' '..o.guid:hex().."\n"
	end)
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

function hSMSG_TRADE_STATUS(p)
	if((p.status == TRADE_STATUS_OPEN_WINDOW) and STATE.tradeGiveAll) then
		STATE.tradeGiveAll = false
		print("TRADE_STATUS_OPEN_WINDOW")
		local tradeSlot = 0
		investigateInventory(function(o, bagSlot, slot)
			send(CMSG_SET_TRADE_ITEM, {tradeSlot = tradeSlot, bag = bagSlot, slot = slot})
			print(tradeSlot..": "..o.values[OBJECT_FIELD_ENTRY]..' '..o.guid:hex())
			tradeSlot = tradeSlot + 1
			if(tradeSlot >= TRADE_SLOT_TRADED_COUNT) then
				return false
			end
		end)
		print("giving "..tradeSlot.." items...")
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
	elseif(p.text == 'recreate') then
		recreate(p)
	end
end

function partyChat(msg)
	send(CMSG_MESSAGECHAT, {type=CHAT_MSG_PARTY, language=LANG_UNIVERSAL, msg=msg})
end
