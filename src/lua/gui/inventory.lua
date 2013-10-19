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
local slotSquare

function doInventoryWindow()
	if(gWindow) then
		return false
	end

	local totalSlotCount = 16	-- backpack
	local freeSlotCount = investigateBags(function(bag, bagSlot, slotCount)
		totalSlotCount = totalSlotCount + slotCount
	end)

	slotSquare = math.ceil(totalSlotCount ^ 0.5)

	local size = slotSquare*iconSize*(1+marginFraction*2)
	gWindow = SDL.SDL_CreateWindow(STATE.myName.."'s Inventory", 32, 32,
		size, size, SDL.SDL_WINDOW_SHOWN)
	gSurface = SDL.SDL_GetWindowSurface(gWindow)
	itemIcons = {}
	initializeItemForm()
	showNonModal(drawInvWindow, onCloseInvWindow, invHandleClickEvent)
	return true
end

function initializeItemForm()
	local x = 0
	local y = 0
	investigateInventory(function(o, bagSlot, slot)
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
		if(x >= slotSquare) then
			x = 0
			y = y + 1
		end
	end)
end	--initializeForm

-- returns table {description=string, f=function} or nil
local function getClickInfo(t, button)
	--print(dump(package))
	local itemId = t.proto.itemId
	local shift = tonumber(SDL.SDL_GetModState())
	--print("shift:", shift)
	local ssShift = bit32.btest(shift, SDL.KMOD_LSHIFT) or bit32.btest(shift, SDL.KMOD_RSHIFT)
	local ssAlt = bit32.btest(shift, SDL.KMOD_LALT) or bit32.btest(shift, SDL.KMOD_RALT)
	local ssCtrl = bit32.btest(shift, SDL.KMOD_LCTRL) or bit32.btest(shift, SDL.KMOD_RCTRL)
	local plain = (not ssShift) and (not ssAlt) and (not ssCtrl)
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
		elseif(ssShift and (not ssAlt) and (not ssCtrl)) then
			return {description="Store in bank", f=function()
				partyChat(storeItemInBank(itemId))
			end}
		end
	elseif(button == SDL_BUTTON_RIGHT) then
		if(plain) then
			return {description="Use", f=function()
				print(gUseItem(itemId))
			end}
		elseif(ssAlt and (not ssShift) and (not ssCtrl)) then
			return {description="maybeEquip", f=function()
				maybeEquip(t.o.guid, true)
			end}
		elseif(ssCtrl and (not ssShift) and (not ssAlt)) then
			return {description="Sell", f=function()
				STATE.itemsToSell[itemId] = true
			end}
		elseif(ssShift and (not ssAlt) and (not ssCtrl)) then
			return {description="Give", f=function()
				STATE.tradeGiveItems[itemId] = true
				if(STATE.tradeStatus == TRADE_STATUS_OPEN_WINDOW) then
					-- should cause bot to add the item to the trade window.
					hSMSG_TRADE_STATUS({status=TRADE_STATUS_OPEN_WINDOW})
				else
					send(CMSG_INITIATE_TRADE, {guid=STATE.leader.guid})
				end
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
		if(PERMASTATE.shouldLoot[itemId]) then
			borderColor = 0xffff00	-- yellow
		elseif(STATE.itemsToSell[itemId]) then
			borderColor = 0x00ff00	-- bright green
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
		-- TODO: requirements
		if(#t.proto.description > 0) then
			drawTextWrap(t.proto.description, SDL_yellow, x+2, y+2, w-4)
		end
	end
end

function onCloseInvWindow()
end
