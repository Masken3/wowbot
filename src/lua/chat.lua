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

local function dropQuest(p)
	local quests = {}
	for questId in p.text:sub(4):gmatch("%w+") do
		quests[tonumber(questId)] = true
	end
	local msg = 'Dropped quests:'
	for i=0,19 do
		local id = STATE.my.values[PLAYER_QUEST_LOG_1_1 + i*3]
		if(id ~= nil and quests[id]) then
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

local function baseListItems(p, name, investigateFunction, testFunction, skipFreeSlotCount)
	local msg = name..': '
	local items = {}
	local freeSlotCount = investigateFunction(function(o)
		local id = o.values[OBJECT_FIELD_ENTRY]
		if((not testFunction) or testFunction(id)) then
			local count = o.values[ITEM_FIELD_STACK_COUNT]
			if(count > 1) then
				items[id] = (items[id] or 0) + count
			else
				msg = msg..itemLink(o).." ("..id..")\n"
			end
		end
	end)
	for id,count in pairs(items) do
		msg = msg..itemLinkFromId(id).." ("..id..") x"..count.."\n"
	end
	if(not skipFreeSlotCount) then
		msg = msg..freeSlotCount.." slots free."
	end
	reply(p, msg)
end

local function listItems(p)
	baseListItems(p, 'Inventory', investigateInventory)
end

local function listBankItems(p)
	baseListItems(p, 'Bank', investigateBank)
end

local function listQuestItems(p)
	baseListItems(p, 'Inventory', investigateInventory, function(id)
		return hasQuestForItem(id)
	end, true)
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

function giveDrinkTo(drinkId, targetGuid)
	STATE.tradeGiveItems = {[drinkId]=true}
	-- this should be enough, assuming bots always accept trade.
	send(CMSG_INITIATE_TRADE, {guid=targetGuid})
	STATE.drinkRecipients[targetGuid] = nil
end

local function giveDrink(p)
	local drinkItem, drinkId = findDrinkItem()
	if(drinkId) then
		giveDrinkTo(drinkId, p.senderGuid)
	else
		if(STATE.conjureDrinkSpell) then
			STATE.drinkRecipients[p.senderGuid] = true
			reply(p, 'Hold on, conjuring...')
		else
			reply(p, 'No can do.')
		end
	end
end

local function giveItem(p)
	local items = {}
	for itemId in p.text:sub(6):gmatch("%w+") do
		items[tonumber(itemId)] = true
	end
	reply(p, 'giving items...')
	STATE.tradeGiveItems = items
	send(CMSG_INITIATE_TRADE, {guid=p.senderGuid})
end

function hSMSG_TRADE_STATUS(p)
	STATE.tradeStatus = p.status
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
	elseif((p.status == TRADE_STATUS_OPEN_WINDOW) and next(STATE.tradeGiveItems)) then
		local tradeSlot = 0
		investigateInventory(function(o, bagSlot, slot)
			local itemId = o.values[OBJECT_FIELD_ENTRY]
			if(STATE.tradeGiveItems[itemId]) then
				send(CMSG_SET_TRADE_ITEM, {tradeSlot = tradeSlot, bag = bagSlot, slot = slot})
				print(tradeSlot..": "..itemId..' '..o.guid:hex())
				tradeSlot = tradeSlot + 1
				if(tradeSlot >= TRADE_SLOT_TRADED_COUNT) then
					return false
				end
			end
		end)
		print("giving "..tradeSlot.." items...", dump(STATE.tradeGiveItems))
		STATE.tradeGiveItems = {}
		send(CMSG_ACCEPT_TRADE, {padding=0})
	elseif(p.status == TRADE_STATUS_TRADE_CANCELED) then
		print("Trade cancelled!")
		-- if this was not the drink-giver, we'll just ask again soon.
		STATE.waitingForDrink = false
	elseif(p.status == TRADE_STATUS_TRADE_COMPLETE) then
		print("Trade complete!")
		STATE.me.updateValuesCallbacks[p] = function(p)
			investigateInventory(function(o)
				maybeEquip(o.guid)
			end)
		end
		-- if this was not the drink-giver, we'll just ask again soon.
		STATE.waitingForDrink = false
	elseif(p.status == TRADE_STATUS_BEGIN_TRADE) then
		-- player has requested to trade with us. just accept.
		print("Remote trade initiated!")
		send(CMSG_BEGIN_TRADE)
	elseif(p.status == TRADE_STATUS_TRADE_ACCEPT) then
		send(CMSG_ACCEPT_TRADE, {padding=0})
	else
		print("Trade status "..p.status)
	end
end

function hSMSG_TRADE_STATUS_EXTENDED(p)
	STATE.extendedTradeStatus = p
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
	print("invite", dump(p))
	STATE.newLeader = p.senderGuid
	send(CMSG_NAME_QUERY, {guid=p.senderGuid})
	PERMASTATE.invitee = p.senderGuid:hex()
	saveState()
end

function hSMSG_NAME_QUERY_RESPONSE(p)
	local o = STATE.knownObjects[p.guid]
	o.bot.nameData = p
	if(STATE.newLeader == p.guid and (not isGroupMember(o))) then
		print("CMSG_GROUP_INVITE", dump(p))
		send(CMSG_GROUP_INVITE, p)
	end
	if(o.bot.nameCallback) then
		local cb = o.bot.nameCallback
		o.bot.nameCallback = nil
		cb(p)
	end
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
	local myPos = STATE.myLocation.position
	-- find nearest usable gameobject.
	local closestPos
	local closestObject
	local count = 0
	for guid, o in pairs(STATE.knownObjects) do
		if(isGameObject(o) and
			o.values[GAMEOBJECT_POS_X])
			--bit32.btest(o.values[GAMEOBJECT_DYN_FLAGS], GO_DYNFLAG_LO_ACTIVATE))
		then
			count = count + 1
			-- problematic; stored as uint32, but are really float. how to convert? Use C.
			local pos = goPos(o)
			if((not closestObject) or (distance3(myPos, pos) < distance3(myPos, closestPos))) then
				closestPos = pos
				closestObject = o
			end
		end
	end
	print("Found "..count.." objects.")
	if(closestObject) then
		partyChat(closestObject.guid:hex()..": "..distance3(myPos, closestPos).." yards.")
		--send(CMSG_GAMEOBJ_USE, {guid=closestObject.guid})
		--castSpellAtGO(22810, closestObject)

		openGameobject(closestObject)
	else
		partyChat("No objects found.")
	end
end

local function train(p)
	if(p.type ~= CHAT_MSG_WHISPER) then
		reply(p, "Must whisper this command.")
	end
	local trainerGuid = guidFromValues(STATE.knownObjects[p.senderGuid], UNIT_FIELD_TARGET)
	local trainer = STATE.knownObjects[trainerGuid]
	if(not trainer) then
		reply(p, "No valid target!")
		return
	end
	goTrain(trainer)
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
	local msg = 'Selling items:'
	local items = {}
	for itemId in p.text:sub(6):gmatch("%w+") do
		--print(itemId)
		items[tonumber(itemId)] = true
	end
	investigateInventory(function(o, bagSlot, slot)
		local itemId = o.values[OBJECT_FIELD_ENTRY]
		if(items[itemId]) then
			msg = msg..itemId..' x'..o.values[ITEM_FIELD_STACK_COUNT]..' '..o.guid:hex().."\n"
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
	STATE.fishingOrientation = STATE.my.location.orientation;
	STATE.fishing = true
	reply(p, "Started Fishing.")
end

local function stop(p)
	if(STATE.fishing) then
		STATE.fishing = false
		reply(p, "Stopped fishing.")
	end
end

function itemIsOnCooldown(proto)
	for i,is in ipairs(proto.spells) do
		if(is.trigger == ITEM_SPELLTRIGGER_ON_USE and is.id ~= 0) then
			local s = cSpell(is.id)
			if(spellIsOnCooldown(getRealTime(), s)) then return true end
		end
	end
	return false
end

function gUseItem(itemId)
	local msg = 'Using item:'
	local done = false
	investigateInventory(function(o, bagSlot, slot)
		if(itemId == o.values[OBJECT_FIELD_ENTRY] and not done) then
			msg = msg..' '..o.guid:hex()
			local proto = itemProtoFromId(itemId)
			if(proto.StartQuest ~= 0) then
				-- callbacks will start the quest.
				send(CMSG_QUESTGIVER_QUERY_QUEST, {guid=o.guid, questId=proto.StartQuest})
			elseif(proto.InventoryType == INVTYPE_BAG) then
				-- put in bank bag slot
				local done = false
				investigateBankBags(function()end, function(bankBagSlot)
					if(done) then return end
					done = true
					--print("CMSG_AUTOEQUIP_ITEM_SLOT "..bankBagSlot)
					--send(CMSG_AUTOEQUIP_ITEM_SLOT, {itemGuid=o.guid, dstSlot=bankBagSlot})
					local p = {dstbag=INVENTORY_SLOT_BAG_0, dstslot=bankBagSlot,
						srcbag=bagSlot, srcslot=slot}
					print("CMSG_SWAP_ITEM ", dump(p))
					send(CMSG_SWAP_ITEM, p)
				end)
			elseif(bit32.btest(proto.Flags, ITEM_FLAG_LOOTABLE)) then
				send(CMSG_OPEN_ITEM, {slot = slot, bagSlot = bagSlot})
			elseif(proto.InventoryType == INVTYPE_AMMO) then
				print("CMSG_SET_AMMO "..itemId)
				send(CMSG_SET_AMMO, {itemId=itemId})
			elseif(itemIsOnCooldown(proto)) then
				return false
			else
				STATE.casting = getRealTime()
				send(CMSG_USE_ITEM, {slot = slot, bag = bagSlot, spellCount = 0, targetFlags = 0})
			end
			done = true
		end
	end)
	return msg
end

local function useItem(p)
	local itemId = tonumber(p.text:sub(5))
	reply(p, gUseItem(itemId))
end

local function disenchant(p)
	if(not STATE.disenchantSpell) then return end
	local itemId = tonumber(p.text:sub(5))
	STATE.disenchantItems = STATE.disenchantItems or {}
	STATE.disenchantItems[itemId] = true
	decision()
end

local function disenchantAll(p)
	if(not STATE.disenchantSpell) then return end
	STATE.disenchantItems = STATE.disenchantItems or {}
	investigateInventory(function(o, bagSlot, slot)
		local itemId = o.values[OBJECT_FIELD_ENTRY]
		local proto = itemProtoFromId(itemId)
		if(proto.Quality >= ITEM_QUALITY_UNCOMMON) then
			STATE.disenchantItems[itemId] = true
		end
	end)
	decision()
end

function storeItemInBank(itemId)
	local msg = 'Storing items'
	local count = 0
	investigateInventory(function(o, bagSlot, slot)
		if(itemId == o.values[OBJECT_FIELD_ENTRY]) then
			msg = msg..' '..o.guid:hex()
			send(CMSG_AUTOSTORE_BANK_ITEM, {bag=bagSlot, slot=slot})
			count = count + o.values[ITEM_FIELD_STACK_COUNT]
		end
	end)
	msg = msg..', total '..count
	return msg
end

local function store(p)
	local itemId = tonumber(p.text:sub(7))
	reply(p, storeItemInBank(itemId))
end

function fetchItemFromBank(itemId)
	local msg = 'Fetching items'
	local count = 0
	investigateBank(function(o, bagSlot, slot)
		if(itemId == o.values[OBJECT_FIELD_ENTRY]) then
			msg = msg..' '..o.guid:hex()
			send(CMSG_AUTOSTORE_BANK_ITEM, {bag=bagSlot, slot=slot})
			count = count + o.values[ITEM_FIELD_STACK_COUNT]
		end
	end)
	return msg..', total '..count
end

local function fetch(p)
	local itemId = tonumber(p.text:sub(7))
	reply(p, fetchItemFromBank(itemId))
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

local function skills(p)
	local msg = ''
	for idx=PLAYER_SKILL_INFO_1_1,(PLAYER_SKILL_INFO_1_1+384),3 do
		local skillId = bit32.band(STATE.my.values[idx] or 0, 0xFFFF)
		local skillLine = cSkillLine(skillId)
		if(skillLine) then
			local val, max = skillLevelByIndex(idx)
			msg = msg..skillId..", "..skillLine.name..": "..tostring(val).."/"..tostring(max).."\n"
		end
	end
	reply(p, msg)
end

local function equip(p)
	local itemId = tonumber(p.text:sub(7))
	local found = false
	investigateInventory(function(o, bagSlot, slot)
		if(itemId == o.values[OBJECT_FIELD_ENTRY]) then
			found = true
			reply(p, "Testing "..o.guid:hex())
			maybeEquip(o.guid, true)
		end
	end)
	if(not found) then
		reply(p, "Not found!")
	end
end

local function spells(p)
	local skillId = tonumber(p.text:sub(8))
	local skillLine = cSkillLine(skillId)
	if(not skillLine) then
		reply(p, "Bad skillLine "..skillId)
		return
	end
	local val, max = skillLevel(skillId)
	local msg = skillLine.name..": "..tostring(val).."/"..tostring(max).."\n"
	local lines = {}
	for id, s in pairs(STATE.knownSpells) do
		local sla = cSkillLineAbilityBySpell(id)
		if(sla and sla.skill == skillId) then
			local line = sla.minValue.."-"..sla.maxValue.." "..id.." "..s.name
			if(#s.rank > 0) then line = line.." "..s.rank end
			table.insert(lines, line)
		end
	end
	table.sort(lines)
	for i,line in ipairs(lines) do msg = msg..line.."\n" end
	reply(p, msg)
end

local function talents(p)
	reply(p, "Opening talent window...")
	doTalentWindow()
end

local function inventory(p)
	reply(p, "Opening inventory window...")
	doInventoryWindow()
end

local function profession(p)
	local skillId = tonumber(p.text:sub(3))
	local skillLine = cSkillLine(skillId)
	reply(p, "Opening profession window for "..skillLine.name.."...")
	doProfessionWindow(skillLine)
end

local function permaToggle(p, len, stateName)
	local state = p.text:sub(len)
	if(state == "off") then
		PERMASTATE[stateName] = false
	elseif(state == "on") then
		PERMASTATE[stateName] = true
	else
		reply(p, "Invalid state ("..state.."). Must be 'on' or 'off'.")
		return
	end
	saveState()
	reply(p, stateName.." set to '"..state.."'.")
end

local function autoQuestGet(p)
	permaToggle(p, 5, 'autoQuestGet')
end

local function eliteCombat(p)
	permaToggle(p, 4, 'eliteCombat')
end

local function gq(p)
	local targetGuid = guidFromValues(STATE.knownObjects[p.senderGuid], UNIT_FIELD_TARGET)
	local target = STATE.knownObjects[targetGuid]
	if(not target) then
		reply(p, "No valid target!")
		STATE.questFinishers = {}
		return
	end
	--getQuests(target)
	target.bot.questOverride = true
	STATE.questFinishers[targetGuid] = target
end

local function listBags(p)
	local msg = 'Bags ('..countFreeSlots().." free slots)\n"
	local freeSlotCount = investigateBags(function(bag, bagSlot, slotCount)
		local id = bag.values[OBJECT_FIELD_ENTRY]
		local proto = itemProtoFromId(id)
		msg = msg..itemLink(bag).." "..slotCount.."\n"
	end)
	reply(p, msg)
end

local function listBankBags(p)
	local msg = 'Bank bags ('..countFreeBankSlots().." free slots)\n"
	local freeSlotCount = investigateBankBags(function(bag, bagSlot, slotCount)
		local id = bag.values[OBJECT_FIELD_ENTRY]
		local proto = itemProtoFromId(id)
		msg = msg..itemLink(bag).." "..slotCount.."\n"
	end)
	reply(p, msg)
end

local function report(p)
	reply(p, tostring(STATE.currentAction))
end

local function buyBankSlot(p)
	local targetGuid = guidFromValues(STATE.knownObjects[p.senderGuid], UNIT_FIELD_TARGET)
	send(CMSG_BUY_BANK_SLOT, {guid=targetGuid})
	reply(p, "buyBankSlot @ "..targetGuid:hex())
end

local function amTank(p)
	local o = STATE.knownObjects[p.senderGuid]
	if(not o) then return end
	o.bot.isTank = true
	-- todo when we start raiding: allow for multiple mainTanks and offTanks.
	STATE.mainTank = o
	--print("tank", p.senderGuid:hex())
end

local function amHealer(p)
	local o = STATE.knownObjects[p.senderGuid]
	if(not o) then return end
	o.bot.isHealer = true
	--print("healer", p.senderGuid:hex())
end

local function test(p)
	local targetGuid = guidFromValues(STATE.knownObjects[p.senderGuid], UNIT_FIELD_TARGET)
	local target = STATE.knownObjects[targetGuid]
	reply(p, tostring(isTargetOfPartyMember(target)))
end

local function chat(p)
	local targetGuid = guidFromValues(STATE.knownObjects[p.senderGuid], UNIT_FIELD_TARGET)
	local target = STATE.knownObjects[targetGuid]
	if(not target) then
		reply(p, "No valid target!")
		return
	end
	target.bot.chat = true
	target.bot.questOverride = true
	STATE.questFinishers[targetGuid] = target
	objectNameQuery(target, function(name)
		reply(p, "Chatting with "..name)
	end)
end

function handleChatMessage(p)
	if(not p.text) then return end
	if(p.text == 'lq') then
		listQuests(p)
	--elseif(p.text == 'daq') then
		--dropAllQuests(p)
	elseif(p.text:startWith('dq ')) then
		dropQuest(p)
	elseif(p.text == 'li') then
		listItems(p)
	elseif(p.text == 'lqi') then
		listQuestItems(p)
	--elseif(p.text == 'dai') then
		--dropAllItems(p)
	elseif(p.text:startWith('drop ')) then
		dropItem(p)
	elseif(p.text == 'lm') then
		listMoney(p)
	elseif(p.text == 'give all') then
		giveAll(p)
	elseif(p.text == 'give drink') then
		giveDrink(p)
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
	elseif(p.text == 'dis') then
		disenchantAll(p)
	elseif(p.text:startWith('store ')) then
		store(p)
	elseif(p.text:startWith('fetch ')) then
		fetch(p)
	elseif(p.text == 'lb') then
		listBankItems(p)
	elseif(p.text == 'repair') then
		repair(p)
	elseif(p.text == 'skills') then
		skills(p)
	elseif(p.text:startWith('equip ')) then
		equip(p)
	elseif(p.text:startWith('spells ')) then
		spells(p)
	elseif(p.text == 'n') then
		talents(p)
	elseif(p.text:startWith('aqg ')) then
		autoQuestGet(p)
	elseif(p.text == 'gq') then
		gq(p)
	elseif(p.text == 'lg') then
		listBags(p)
	elseif(p.text == 'lbg') then
		listBankBags(p)
	elseif(p.text == 'report') then
		report(p)
	elseif(p.text == 'i') then
		inventory(p)
	elseif(p.text:startWith('p ')) then
		profession(p)
	elseif(p.text == 'bbs') then
		buyBankSlot(p)
	elseif(p.text == 'amTank') then
		amTank(p)
	elseif(p.text == 'amHealer') then
		amHealer(p)
	elseif(p.text:startWith('ec ')) then
		eliteCombat(p)
	elseif(p.text == 'test') then
		test(p)
	elseif(p.text == 'chat') then
		chat(p)
	else
		if(p.type == CHAT_MSG_WHISPER or p.type == CHAT_MSG_WHISPER_INFORM) then
			print("Whisper: "..p.text)
		end
		return
	end
	--print("Chat command: "..p.text)
end

function partyChat(msg)
	print("partyChat("..msg..")")
	send(CMSG_MESSAGECHAT, {type=CHAT_MSG_PARTY, language=LANG_UNIVERSAL, msg=msg})
end

function whisper(recipient, msg)
	objectNameQuery(recipient, function(name)
		send(CMSG_MESSAGECHAT, {type=CHAT_MSG_WHISPER, language=LANG_ADDON,
			msg=msg, targetName=name})
	end)
end
