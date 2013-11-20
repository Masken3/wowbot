-- todo: popup should show what mouse-clicks will do (left/right, modified by shift-keys).

local iconSize = 40
local marginFraction = 0.2

-- functions
local initializeItemForm
local updateIcons
local drawInvWindow
local onCloseInvWindow
local invHandleClickEvent

local itemIcons = {}	-- o:t
local invWidth
local bankHeight
local myWindow
local slotSquare
local bankSlotSquare

function doInventoryWindow()
	if(gWindow) then
		return false
	end

	local totalSlotCount = 16	-- backpack
	local freeSlotCount = investigateBags(function(bag, bagSlot, slotCount)
		totalSlotCount = totalSlotCount + slotCount
	end)

	slotSquare = math.ceil(totalSlotCount ^ 0.5)

	local bankSlotCount = BANK_SLOT_ITEM_END - BANK_SLOT_ITEM_START
	investigateBankBags(function(bag, bagSlot, slotCount)
		bankSlotCount = bankSlotCount + slotCount
	end)
	bankSlotSquare = math.ceil(bankSlotCount ^ 0.5)

	local sizePerSlot = iconSize*(1+marginFraction*2)
	invWidth = slotSquare*sizePerSlot
	local width = (slotSquare+bankSlotSquare)*sizePerSlot
	-- +1 for the bank bags.
	bankHeight = bankSlotSquare*sizePerSlot
	local height = math.max(slotSquare*sizePerSlot, bankHeight+sizePerSlot)
	gWindow = SDL.SDL_CreateWindow(STATE.myName.."'s Inventory & Bank", 32, 32,
		width, height, SDL.SDL_WINDOW_SHOWN)
	gSurface = SDL.SDL_GetWindowSurface(gWindow)
	myWindow = gWindow
	updateInventoryScreen()
	showNonModal(drawInvWindow, onCloseInvWindow, invHandleClickEvent)
	return true
end

function updateInventoryScreen()
	if(gWindow ~= myWindow) then return end
	itemIcons = {}
	initializeItemForm(0, 0, slotSquare, investigateInventory)
	initializeItemForm(slotSquare, 0, bankSlotSquare, investigateBank)
	initializeItemForm(slotSquare, bankSlotSquare, bankSlotSquare, investigateBankBags)
end

function initializeItemForm(x, y, w, investigationFunction)
	local origX = x
	investigationFunction(function(o, bagSlot, slot)
		local left = x*iconSize*(1+marginFraction*2) + marginFraction*iconSize
		local top = y*iconSize*(1+marginFraction*2) + marginFraction*iconSize
		--print(x, y, left, top);

		local itemId = o.values[OBJECT_FIELD_ENTRY]
		local proto = itemProtoFromId(itemId)
		assert(proto);

		local icon = getItemIcon(proto)

		local stackCount = o.values[ITEM_FIELD_STACK_COUNT]

		local r = SDL_Rect(left, top, iconSize, iconSize)
		local t = {o=o, proto=proto, icon=icon, r=r, stackCount=stackCount }

		itemIcons[o] = t

		x = x + 1
		if(x >= origX + w) then
			x = origX
			y = y + 1
		end
	end)
end	--initializeForm

-- returns table {description=string, f=function} or nil
-- TODO: vary for bank items
local function getClickInfo(t, button)
	--print(dump(package))
	local itemId = t.proto.itemId
	local shift = tonumber(SDL.SDL_GetModState())
	--print("shift:", shift)
	local ssShift = bit32.btest(shift, SDL.KMOD_LSHIFT) or bit32.btest(shift, SDL.KMOD_RSHIFT)
	local ssAlt = bit32.btest(shift, SDL.KMOD_LALT) or bit32.btest(shift, SDL.KMOD_RALT)
	local ssCtrl = bit32.btest(shift, SDL.KMOD_LCTRL) or bit32.btest(shift, SDL.KMOD_RCTRL)
	local plain = (not ssShift) and (not ssAlt) and (not ssCtrl)
	local isBankItem = (t.r.x >= invWidth) and (t.r.y < bankHeight)
	local isBankBag = (t.r.x >= invWidth) and (t.r.y >= bankHeight)
	local isInventoryItem = t.r.x < invWidth
	if(button == SDL_BUTTON_LEFT) then
		if(plain) then
			return {description="Open link...", f=function()
				-- assumes wowfoot is running on your auth server.
				os.execute("start http://"..STATE.authAddress..":3002/item="..itemId)
			end}
		end
		if(ssAlt and (not ssShift) and (not ssCtrl)) then
			return {description="Toggle 'shouldLoot'", f=function()
				PERMASTATE.shouldLoot[itemId] = (not PERMASTATE.shouldLoot[itemId]) or nil
				saveState()
			end}
		elseif(ssAlt and (not ssShift) and ssCtrl) then
			return {description="Toggle 'undisenchantable'", f=function()
				PERMASTATE.undisenchantable[itemId] = (not PERMASTATE.undisenchantable[itemId]) or nil
				saveState()
			end}
		elseif(ssShift and (not ssAlt) and (not ssCtrl)) then
			if(isInventoryItem) then
				return {description="Store in bank", f=function()
					partyChat(storeItemInBank(itemId))
				end}
			elseif(isBankItem) then
				return {description="Fetch from bank", f=function()
					partyChat(fetchItemFromBank(itemId))
				end}
			end
		end
	elseif(button == SDL_BUTTON_RIGHT and isBankItem) then
		if(plain and t.proto.InventoryType == INVTYPE_BAG) then
			return {description="Toggle 'forced bank bag'", f=function()
				PERMASTATE.forcedBankBags[itemId] = (not PERMASTATE.forcedBankBags[itemId]) or nil
				saveState()
			end}
		end
	elseif(button == SDL_BUTTON_RIGHT and isInventoryItem) then
		if(plain) then
			local d = "Use"
			if(bit32.btest(t.proto.Flags, ITEM_FLAG_LOOTABLE)) then d = "Open" end
			if(t.proto.InventoryType == INVTYPE_BAG) then d = "Put in bank slot" end
			if(t.proto.InventoryType == INVTYPE_AMMO) then d = "Use as ammo" end
			--if(t.proto.InventoryType == INVTYPE_BAG) then return nil end
			return {description=d, f=function()
				print(gUseItem(itemId))
			end}
		elseif(ssAlt and (not ssShift) and (not ssCtrl)) then
			return {description="maybeEquip", f=function()
				maybeEquip(t.o.guid, true)
			end}
		elseif(ssAlt and (not ssShift) and ssCtrl) then
			return {description="forceEquip", f=function()
				forceEquip(t.o.guid)
			end}
		elseif(ssCtrl and (not ssShift) and (not ssAlt)) then
			return {description="Sell", f=function()
				STATE.itemsToSell[itemId] = true
				decision()
			end}
		elseif(ssShift and (not ssAlt) and (not ssCtrl)) then
			return {description="Give", f=function()
				STATE.tradeGiveItems[itemId] = true
				if(STATE.tradeStatus == TRADE_STATUS_OPEN_WINDOW) then
					-- should cause bot to add the item to the trade window.
					hSMSG_TRADE_STATUS({status=TRADE_STATUS_OPEN_WINDOW})
				else
					initiateTrade(STATE.leader.guid);
				end
			end}
		elseif(ssAlt and ssShift and ssCtrl) then
			return {description="Drop", f=function()
				partyChat(gDropItem(itemId))
			end}
		end
	end
	return nil
end

local function itemClick(t, button)
	--print(dump(package))
	local info = getClickInfo(t, button)
	if(info) then
		info.f()
	end
end

function invHandleClickEvent(event)
	for tal,t in pairs(itemIcons) do
		if(pointIsInRect(event.button.x, event.button.y, t.r)) then
			itemClick(t, event.button.button)
		end
	end
end

function drawInvWindow()
	--print("drawInvWindow")
	-- the black
	SDL.SDL_FillRect(gSurface, SDL_Rect(0, 0, gSurface.w, gSurface.h), 0)

	-- divider between inventory and bank
	SDL.SDL_FillRect(gSurface, SDL_Rect(invWidth, 0, 1, gSurface.h), 0xffffffff)

	-- divider between bank items and bags
	SDL.SDL_FillRect(gSurface, SDL_Rect(invWidth, bankHeight, gSurface.w-invWidth, 1), 0xffffffff)

	-- icon icons
	local mouseOverItem = nil
	for o, t in pairs(itemIcons) do

		if(pointIsInRect(gMouseX, gMouseY, t.r)) then
			assert(mouseOverItem == nil)	-- seems to fail for no reason, not really critical.
			mouseOverItem = t
		end

		-- border
		local itemId = t.proto.itemId
		local borderColor
		if(STATE.itemsToSell[itemId]) then
			borderColor = 0x00ff00	-- bright green
		elseif(PERMASTATE.shouldLoot[itemId]) then
			borderColor = 0xffff00	-- yellow
		elseif(PERMASTATE.undisenchantable[itemId]) then
			borderColor = 0x0000ff	-- blue
		elseif(PERMASTATE.forcedBankBags[itemId]) then
			borderColor = 0xff0000	-- red
		end
		if(borderColor) then
			local r = SDL_Rect(t.r.x-2, t.r.y-2, t.r.w+4, t.r.h+4)
			SDL.SDL_FillRect(gSurface, r, borderColor)
		end

		-- icon
		SDL.SDL_UpperBlitScaled(t.icon, nil, gSurface, t.r)

		-- count label
		if(t.stackCount > 1) then
			drawText(tostring(t.stackCount), SDL_brightGreen, t.r.x+t.r.w/1.5, t.r.y+t.r.h/1.5)
		end
	end

	-- popup
	if(mouseOverItem) then
		local t = mouseOverItem
		-- calculate position
		local x = t.r.x + iconSize
		local y = t.r.y + iconSize*1.5
		local w = iconSize*8
		local h = iconSize*3.5

		if(gSurface.w < x + w) then
			x = gSurface.w - (w + iconSize)
		end
		if(gSurface.h < y + h) then
			y = y - (h + iconSize*2)
		end

		-- border
		SDL.SDL_FillRect(gSurface, SDL_Rect(x-3, y-3, w+6, h+6), 0xffffffff)
		-- inner
		SDL.SDL_FillRect(gSurface, SDL_Rect(x-2, y-2, w+4, h+4), 0)

		local itemQualityColor = ITEM_QUALITY[t.proto.Quality].color

		local buttonText = ''
		local l = getClickInfo(t, SDL_BUTTON_LEFT)
		if(l) then
			buttonText = buttonText..l.description
		end
		buttonText = buttonText.." | "
		l = getClickInfo(t, SDL_BUTTON_RIGHT)
		if(l) then
			buttonText = buttonText..l.description
		end
		y = y + drawText(buttonText, SDL_white, x+2, y+2).h

		y = y + drawText(t.proto.name, itemQualityColor, x+2, y+2).h
		if(bit32.btest(t.o.values[ITEM_FIELD_FLAGS] or 0, ITEM_DYNFLAG_BINDED)) then
			y = y + drawText("Soulbound", SDL_white, x+2, y+2).h
		end
		-- TODO: requirements
		if(#t.proto.description > 0) then
			drawTextWrap(t.proto.description, SDL_yellow, x+2, y+2, w-4)
		end
	end
end

function onCloseInvWindow()
end
