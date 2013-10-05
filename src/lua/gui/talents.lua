require "vcl"

VCL.clBrightGreen = 0x00ff00

local gAvailablePoints

-- internalName:tab
local tabs = {}

-- when this is empty, all images have been resized.
local resizingImages = {}

local talentIcons = {}

local iconSize = 40
local marginFraction = 0.25

local tabWidth = iconSize*4 + (iconSize*marginFraction*6)
local tabHeight = iconSize*8 + (iconSize*marginFraction*10)

local mainForm
local initializeForm
local handleResults

local results = {
	ok = false,
	newTalents = {},	-- talent:maxRequestedRank
}

function doTalentWindow()
	mainForm = VCL.Form{
	name="mainForm",
	caption = "Talents",
	position="podesktopcenter",
	height=tabHeight + iconSize*(1+marginFraction*2),
	width=tabWidth*3,
	color=VCL.clBlack,
	onclosequery = "onCloseQueryEventHandler",
	onMouseMove='disablePopup',
	}
	gAvailablePoints = STATE.my.values[PLAYER_CHARACTER_POINTS1] or 0
	initializeForm()
	mainForm:ShowModal()
	mainForm:Free()
	handleResults()
end

local function talentRank(talent)
	local i = 1
	local rank = 0
	-- earlier ranks are forgotten.
	while(i <= 5) do
		if(STATE.knownSpells[talent.spellId[i]]) then
			rank = i
		end
		i = i + 1
	end
	return rank
end

function handleResults()
	if(not results.ok) then return; end
	for talent, maxRank in pairs(results.newTalents) do
		local c = talentRank(talent)
		for requestedRank=c+1, maxRank do
			send(CMSG_LEARN_TALENT, {talentId=talent.id, requestedRank=requestedRank})
		end
	end
end

local gAvailablePointsLabel
local gOkButton
local gCancelButton
local function createGlobals()
gAvailablePointsLabel = VCL.Label{
	top = tabHeight + iconSize/2,
	left = iconSize/2,
}

gOkButton = VCL.Button{
	caption = "OK",
	default = true,
	top = tabHeight + iconSize/2,
	left = tabWidth*2,
	onClick = 'onOK',
}

gCancelButton = VCL.Button{
	caption = "Cancel",
	cancel = true,
	top = tabHeight + iconSize/2,
	left = tabWidth*2.5,
	onClick = 'onCancel',
}
end

function onCloseQueryEventHandler(Sender)
	return true -- the form can be closed
end

local function setTalentIconPos(i, tab, talent)
	i.Left = tab.tabPage * tabWidth +
		talent.col * iconSize * (1+marginFraction) +
		iconSize * marginFraction
	i.Top = (talent.row+1) * iconSize * (1+marginFraction) + iconSize * marginFraction
end

local function talentIconFromPos(x, y)
	for n,t in pairs(talentIcons) do
		local i = t.i
		if(x >= i.Left and x < i.Left + i.Width and
			y >= i.Top and y < i.Top + i.Height)
		then
			return t
		end
	end
	return nil
end

local function setBackgroundPosition(t)
	local tab = t.tab
	if(t.part == 'TopLeft') then
		t.i.Left = tab.tabPage * tabWidth
		t.i.Top = iconSize*(1+marginFraction)
		-- left width is 4x of right width.
		-- top height is 2x of bottom height.
		t.i.Width = tabWidth * 4/5
		t.i.Height = tabHeight * 2/3
	end
	if(t.part == 'TopRight') then
		t.i.Left = tab.tabPage * tabWidth + tabWidth * 4/5
		t.i.Top = iconSize*(1+marginFraction)
		t.i.Width = tabWidth /5
		t.i.Height = tabHeight * 2/3
	end
	if(t.part == 'BottomRight') then
		t.i.Left = tab.tabPage * tabWidth + tabWidth * 4/5
		t.i.Top = tabHeight * 2/3 + iconSize*(1+marginFraction)
		t.i.Width = tabWidth /5
		t.i.Height = tabHeight /3
	end
	if(t.part == 'BottomLeft') then
		t.i.Left = tab.tabPage * tabWidth
		t.i.Top = tabHeight * 2/3 + iconSize*(1+marginFraction)
		t.i.Width = tabWidth * 4/5
		t.i.Height = tabHeight /3
	end
end

local backgroundParts = {'TopLeft','TopRight','BottomLeft','BottomRight'}

local function tabLabelCaption(tab)
	return tab.name.." ("..tab.spentPoints.."/"..tab.rankCount..")"
end

function myClassMask()
	return bit32.lshift(1, (bit32.extract(STATE.my.values[UNIT_FIELD_BYTES_0], 8, 8) - 1))
end

function myRaceMask()
	return bit32.lshift(1, (bit32.extract(STATE.my.values[UNIT_FIELD_BYTES_0], 0, 8) - 1))
end

function initializeForm()
createGlobals()
gAvailablePointsLabel.font.name = "Verdana"
gAvailablePointsLabel.font.color = VCL.clWhite

for tab in cTalentTabs() do
	--print(dump(tt))
	if(tab.spellIcon == 11) then tab.tabPage = 1; end	-- patch MageFire
	if(tab.classMask == myClassMask()) then	-- mage
		tab.spentPoints = 0
		tab.rankCount = 0
		tab.rows = {}	-- row:{col:t}

		-- gotta wait until onResize before AutoSize takes effect.
		-- tab background
		for i,p in ipairs(backgroundParts) do
			local n = tab.internalName..p
			local i = VCL.Image{Name=n, onMouseMove='disablePopup'}
			local t = {tab=tab, part=p, i=i}
			--images[n] = t
			--resizingImages[n] = true
			i.AutoSize = false
			i.Stretch = true
			i.Proportional = false
			setBackgroundPosition(t)
			i:LoadFromFile(cIconRaw("Interface\\TalentFrame\\"..tab.internalName.."-"..p))
		end
		-- talent icons
		for talent in cTalents() do
			if(talent.tabId == tab.id) then
				local n = 's'..tostring(talent.id)
				local spell = cSpell(talent.spellId[1])
				if(not spell) then
					print("talent "..n.." spellId "..talent.spellId[1].." not valid?!?")
				end
				--print("talent "..n..": "..spell.name)

				local shape
				do
					local s = VCL.Shape{Name=n.."b",
						shape=VCL.stRoundRect,
						brush={color=VCL.clBrightGreen},--VCL.clGreen},
						width=iconSize+4,
						height=iconSize+4,
						onMouseMove='talentPopup',
						onMouseDown='talentClick',
					}
					setTalentIconPos(s, tab, talent)
					s.Left = s.Left - 2
					s.Top = s.Top - 2
					s.Visible = false
					shape = s
				end

				local i = VCL.Image{Name=n,
					onMouseMove='talentPopup',
					onMouseDown='talentClick',
				}
				--resizingImages[n] = true
				local rankCount=0
				for i,sid in ipairs(talent.spellId) do
					if(sid ~= 0) then rankCount = i; end
				end
				tab.rankCount = tab.rankCount + rankCount
				--i.AutoSize = true
				i.Width = iconSize
				i.Height = iconSize
				i.Hint = spell.name
				i.ShowHint = false
				i.Stretch = true
				i.Proportional = true
				--i.Transparent = true
				setTalentIconPos(i, tab, talent)
				i:LoadFromFile(cIconRaw(cSpellIcon(spell.spellIconID).icon))

				if(shape) then
					local s = shape
					--[[
					local rb = VCL.Image{Name=n.."rb",
						Left = i.Left+i.Width /2,
						Top = i.Top+i.Height /1.5,
						onMouseMove='disablePopup',
						Visible = false,
						autosize=false,
						width=iconSize,
						height=iconSize,
						stretch=true,
						proportional=false,
					}
					rb:LoadFromFile(cIconRaw("Interface\\TalentFrame\\TalentFrame-RankBorder"))
					--]]
					local spentPoints = talentRank(talent)
					tab.spentPoints = tab.spentPoints + spentPoints
					local l = VCL.Label{Name=n.."rb",
						transparent=false,
						color=VCL.clBlack,
						visible=false,
						caption=spentPoints.."/"..rankCount,
						Left = i.Left+i.Width /2,
						Top = i.Top+i.Height /1.5,
					}
					l.font.name="Verdana"
					l.font.color=VCL.clBrightGreen
					if(tab.spentPoints >= talent.row * 5) then
						s.visible = true
						--rb.visible = true
						l.visible = true
					end
					local t = {tab=tab, spell=spell, i=i, talent=talent,
						rankCount=rankCount, spentPoints=spentPoints,
						border = shape, --rankBorder = rb,
						rankLabel = l,
					}
					talentIcons[n] = t
					talentIcons[n.."rb"] = t
					talentIcons[n.."b"] = t
					tab.rows[talent.row] = tab.rows[talent.row] or {}
					tab.rows[talent.row][talent.col] = t
				end
			end
		end
		-- tab icon
		do
			local i = VCL.Image{onMouseMove='disablePopup'}
			i.Width = iconSize
			i.Height = iconSize
			i.Top = iconSize * marginFraction/2
			i.Left = tabWidth * tab.tabPage + (iconSize*(marginFraction))
			i.Hint = tab.name
			i.ShowHint = true
			i.Stretch = true
			i.Proportional = true
			i:LoadFromFile(cIconRaw(cSpellIcon(tab.spellIcon).icon))
			local l = VCL.Label{
				caption = tabLabelCaption(tab),
				top = iconSize * marginFraction/2,
				left = i.left + iconSize*(1+marginFraction),
			}
			l.font.color = VCL.clWhite
			l.font.name = "Verdana"
			tab.label = l
		end
	end
end
createPopup()
disablePopup()
updateAvail()
end	--initializeForm

local popup
function createPopup()
popup = {
	border = VCL.Shape{
		shape=VCL.stRoundRect,
		brush={color=VCL.clWhite},
		width=tabWidth*2+6,
		height=iconSize*3.5+6,
	},
	inner = VCL.Shape{
		shape=VCL.stRoundRect,
		brush={color=VCL.clBlack},
		width=tabWidth*2+2,
		height=iconSize*3.5+2,
		left=2,
		top=2,
	},
	name = VCL.Label{
		left=4,
		top=4,
	},
	rank = VCL.Label{
		left=4,
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

function disablePopup(sender, shift, x, y)
	for n,c in pairs(popup) do
		c.visible = false
	end
end

local function popupRankCaption(t)
	return "Rank "..t.spentPoints.."/"..t.rankCount
end

function talentPopup(sender, shift, x, y)
	--print("talentPopup "..sender.name, x, y)
	local t = talentIcons[sender.name]
	--if(not t) then return; end
	x = x + sender.left + iconSize
	y = y + sender.top + iconSize

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
	popup.rank.top = popup.name.top + popup.name.height
	popup.requirements.top = popup.rank.top + popup.rank.height
	popup.description.top = popup.requirements.top + popup.requirements.height

	local up
	for n,c in pairs(popup) do
		up = c.visible
		c.visible = true
		c.transparent = true
		if(c.font) then
			c.font.name = "Verdana"

			-- causes crash.
			--c.Constraints.MaxWidth = popup.inner.width
			--c.Constraints.MinWidth = 0
			--c.Constraints.maxHeight = 1000
			--c.Constraints.minHeight = 0
			--c.OnChange = "onChange"

			-- but this works.
			c.constraints = {MaxWidth = popup.inner.width-4}

			c.autosize = true
			c.width = popup.inner.width-2
			c.height = iconSize /2
			c.left = x+4
		end
		c.onMouseMove = "disablePopup"
	end
	popup.description.height = iconSize * 2
	--if(up) then return; end

	popup.name.font.size = popup.rank.font.size * 1.5
	popup.name.font.color = VCL.clWhite
	popup.name.caption = t.spell.name

	popup.rank.font.color = VCL.clWhite
	popup.rank.caption = popupRankCaption(t)

	popup.requirements.font.color = VCL.clRed
	--popup.requirements.caption =

	popup.description.font.color = VCL.clYellow
	popup.description.caption = t.spell.description
end

function updateAvail()
	gAvailablePointsLabel.caption = "Available points: "..gAvailablePoints
end

local function updateTalent(t)
	-- update labels and shapes
	popup.rank.caption = popupRankCaption(t)
	t.rankLabel.caption = t.spentPoints.."/"..t.rankCount
	t.tab.label.caption = tabLabelCaption(t.tab)

	if(t.spentPoints == t.rankCount) then
		t.rankLabel.font.color = VCL.clYellow
		-- attempting to set brush.color directly causes crash.
		t.border.brush = {color=VCL.clYellow}
	else
		t.rankLabel.font.color = VCL.clBrightGreen
		t.border.brush = {color=VCL.clBrightGreen}
	end

	if(t.tab.spentPoints % 5 == 0) then
		local row = t.tab.spentPoints / 5
		local r = t.tab.rows[row]
		if(r) then for col,t in pairs(r) do
			t.border.visible = true
			t.rankLabel.visible = true
		end end
	else
		local row = math.floor(t.tab.spentPoints / 5)
		local r = t.tab.rows[row+1]
		if(r) then for col,t in pairs(r) do
			t.border.visible = false
			t.rankLabel.visible = false
		end end
	end
	updateAvail()
end

local function canAddPoint(t)
	if(t.spentPoints >= t.rankCount) then return false; end
	if(gAvailablePoints <= 0) then return false; end
	--todo: check talent requirements
	return true
end

local function canRemovePoint(t)
	if(t.spentPoints <= 0) then return false; end
	-- must not allow point removal if it would lead to an impossible tree.
	-- must not allow point removal past levels as they were on form creation.
	return true
end

function talentClick(sender, button, shift, x, y)
	local t = talentIcons[sender.name]
	--print(button)
	if(button == "mbLeft" and canAddPoint(t)) then
		t.spentPoints = t.spentPoints + 1
		t.tab.spentPoints = t.tab.spentPoints + 1
		gAvailablePoints = gAvailablePoints - 1
		updateTalent(t)
		results.newTalents[t.talent] = t.spentPoints
	end
	if(button == "mbRight" and canRemovePoint(t)) then
		t.spentPoints = t.spentPoints - 1
		t.tab.spentPoints = t.tab.spentPoints - 1
		gAvailablePoints = gAvailablePoints + 1
		updateTalent(t)
	end
end

function onCancel(sender)
	print("Cancel")
	results.ok = false
	mainForm:Close()
end

function onOK(sender)
	print("OK")
	results.ok = true
	mainForm:Close()
end

