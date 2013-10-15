-- todo: popup should show what mouse-clicks will do (left/right, modified by shift-keys).

local iconSize = 40
local marginFraction = 0.2

local mainForm
local initializeItemForm
local updateIcons

local itemIcons = {}
local slotSquare

function doInventoryWindow()
	local totalSlotCount = 16	-- backpack
	local freeSlotCount = investigateBags(function(bag, bagSlot, slotCount)
		totalSlotCount = totalSlotCount + slotCount
	end)

	slotSquare = math.ceil(totalSlotCount ^ 0.5)

	mainForm = VCL.Form{
		name="mainForm",
		caption = STATE.myName.."'s Inventory",
		position="podesktopcenter",
		height=slotSquare*iconSize*(1+marginFraction*2),
		width=slotSquare*iconSize*(1+marginFraction*2),
		color=VCL.clBlack,
		onclosequery = "onCloseQueryEventHandler",
		onMouseMove='invDisablePopup',
	}
	initializeItemForm()
	mainForm:ShowModal()
	mainForm:Free()
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
		-- name must be unique, or weird things will happen.
		local n = 'i'..tostring(itemId)..x..y

		local border = VCL.Shape{Name=n.."b",
			shape=VCL.stRoundRect,
			brush={color=VCL.clBrightGreen},
			width=iconSize+4,
			height=iconSize+4,
			top=top-2,
			left=left-2,
			visible=false,
			onMouseMove='itemPopup',
			onMouseDown='itemClick',
		}

		local icon = VCL.Image{Name=n,
			onMouseMove='itemPopup',
			onMouseDown='itemClick',
			width=iconSize,
			height=iconSize,
			top=top,
			left=left,
			visible=true,
			stretch=true,
			proportional=true,
		}
		icon:LoadFromFile(cIcon(cItemDisplayInfo(proto.DisplayInfoID).icon))

		local stackCount = o.values[ITEM_FIELD_STACK_COUNT]
		local stackLabel
		if(stackCount > 1) then
			stackLabel = VCL.Label{Name=n.."rb",
				onMouseMove='itemPopup',
				onMouseDown='itemClick',
				transparent=false,
				color=VCL.clBlack,
				visible=true,
				caption=stackCount,
				left = icon.left + icon.width /1.5,
				top = icon.top + icon.height /1.5,
			}
			stackLabel.font.name="Verdana"
			stackLabel.font.color=VCL.clBrightGreen
		end
		local t = {o=o, proto=proto, icon=icon, border=border, stackLabel=stackLabel }
		itemIcons[n] = t
		itemIcons[n.."rb"] = t
		itemIcons[n.."b"] = t

		x = x + 1
		if(x >= slotSquare) then
			x = 0
			y = y + 1
		end
	end)

	-- creating this after the icons causes the popup to appear above them.
	createItemPopup()
	invDisablePopup()

	updateIcons()
end	--initializeForm

local popup
function createItemPopup()
popup = {
	border = VCL.Shape{
		shape=VCL.stRoundRect,
		brush={color=VCL.clWhite},
		width=iconSize*8+6,
		height=iconSize*3.5+6,
	},
	inner = VCL.Shape{
		shape=VCL.stRoundRect,
		brush={color=VCL.clBlack},
		width=iconSize*8+2,
		height=iconSize*3.5+2,
		left=2,
		top=2,
	},
	name = VCL.Label{
		left=4,
		top=4,
	},
	requirements = VCL.Label{
		left=4,
	},
	description = VCL.Label{
		WordWrap=true,
		left=4,
	},
}
end

function invDisablePopup(sender, shift, x, y)
	for n,c in pairs(popup) do
		c.visible = false
	end
end

function itemPopup(sender, shift, x, y)
	--print("itemPopup "..sender.name, x, y, dump(sender))
	local t = itemIcons[sender.name]
	if(not t) then
		print("itemPopup "..tostring(sender.name), x, y)
	end
	assert(t);
	--if(not t) then return; end
	x = sender.left + iconSize*1.5
	y = sender.top + iconSize*1.5

	if(mainForm.width < x + popup.border.width) then
		x = mainForm.width - popup.border.width
	end
	if(mainForm.height < y + popup.border.height) then
		y = y - (popup.border.height + iconSize*2)
	end

	popup.border.left = x
	popup.border.top = y
	popup.inner.left = x+2
	popup.inner.top = y+2

	popup.name.top = y+4
	popup.requirements.top = popup.name.top + popup.name.height
	popup.description.top = popup.requirements.top + popup.requirements.height

	local up
	for n,c in pairs(popup) do
		up = c.visible
		c.visible = true
		c.transparent = true
		if(c.font) then
			c.font.name = "Verdana"
			c.constraints = {MaxWidth = popup.inner.width-4}
			c.autosize = true
			c.width = popup.inner.width-4
			c.height = iconSize /2
			c.left = x+4
		end
		c.onMouseMove = "invDisablePopup"
	end
	popup.description.height = iconSize * 2
	--if(up) then return; end

	popup.name.font.color = VCL.clWhite
	popup.name.caption = t.proto.name

	popup.requirements.font.color = VCL.clRed
	--popup.requirements.caption =

	popup.description.font.color = VCL.clYellow
	popup.description.caption = t.proto.description
end

function updateIcons(itemId)
	for name,t in pairs(itemIcons) do
		local itemId = t.proto.itemId
		if(PERMASTATE.shouldLoot[itemId]) then
			t.border.visible = true
			t.border.brush = {color=VCL.clYellow}
		elseif(STATE.itemsToSell[itemId]) then
			t.border.visible = true
			t.border.brush = {color=VCL.clGreen}
		else
			t.border.visible = false
		end
	end
end

function itemClick(sender, button, shift, x, y)
	--print(dump(package))
	local t = itemIcons[sender.name]
	local itemId = t.proto.itemId
	local ssShift = shift:find('ssShift')
	local ssAlt = shift:find('ssAlt')
	local ssCtrl = shift:find('ssCtrl')
	local plain = (not ssShift) and (not ssAlt) and (not ssCtrl)
	if(button == "mbLeft") then
		if(plain) then
			-- assumes wowfoot is running on your auth server.
			os.execute("start http://"..STATE.authAddress..":3002/item="..itemId)
		end
		if(ssAlt and (not ssShift) and (not ssCtrl)) then
			PERMASTATE.shouldLoot[itemId] = (not PERMASTATE.shouldLoot[itemId]) or nil
			saveState()
			updateIcons()
		end
	elseif(button == "mbRight") then
		if(plain) then
			print(gUseItem(itemId))
		elseif(ssAlt and (not ssShift) and (not ssCtrl)) then
			maybeEquip(t.o.guid, true)
		elseif(ssCtrl and (not ssShift) and (not ssAlt)) then
			STATE.itemsToSell[itemId] = true
		elseif(ssShift and (not ssAlt) and (not ssCtrl)) then
			STATE.tradeGiveItems[itemId] = true
			if(STATE.tradeStatus == TRADE_STATUS_OPEN_WINDOW) then
				-- should cause bot to add the item to the trade window.
				hSMSG_TRADE_STATUS({status=TRADE_STATUS_OPEN_WINDOW})
			else
				send(CMSG_INITIATE_TRADE, {guid=STATE.leader.guid})
			end
		end
	end
end
