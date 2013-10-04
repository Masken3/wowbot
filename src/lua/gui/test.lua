require "vcl"

-- internalName:tab
local tabs = {}

-- when this is empty, all images have been resized.
local resizingImages = {}

local talentIcons = {}

local iconSize = 40
local marginFraction = 0.25

local tabWidth = iconSize*4 + (iconSize*marginFraction*6)
local tabHeight = iconSize*8 + (iconSize*marginFraction*10)

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

function onCloseQueryEventHandler(Sender)
	return true -- the form can be closed
end

function setTalentIconPos(i, tab, talent)
	i.Left = tab.tabPage * tabWidth +
		talent.col * iconSize * (1+marginFraction) +
		iconSize * marginFraction
	i.Top = (talent.row+1) * iconSize * (1+marginFraction) + iconSize * marginFraction
end

function talentIconFromPos(x, y)
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

function setBackgroundPosition(t)
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

for tab in cTalentTabs() do
	--print(dump(tt))
	if(tab.spellIcon == 11) then tab.tabPage = 1; end	-- patch MageFire
	if(tab.classMask == 128) then	-- mage
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
		-- tab icon
		do
			local i = VCL.Image{onMouseMove='disablePopup'}
			i.Width = iconSize
			i.Height = iconSize
			i.Top = iconSize * marginFraction/2
			i.Left = tabWidth * (tab.tabPage + 0.5) - (iconSize*(1+marginFraction)/2)
			i.Hint = tab.name
			i.ShowHint = true
			i.Stretch = true
			i.Proportional = true
			i:LoadFromFile(cIconRaw(cSpellIcon(tab.spellIcon).icon))
		end
		-- talent icons
		for talent in cTalents() do
			if(talent.tabId == tab.id) then
				local n = 's'..tostring(talent.id)
				local spell = cSpell(talent.spellId[1])
				if(not spell) then
					print("talent "..n.." spellId "..talent.spellId[1].." not valid?!?")
				end

				local shape
				if(talent.row == 0) then
					local s = VCL.Shape{
						shape=VCL.stRoundRect,
						brush={color=0x00FF00},--VCL.clGreen},
						width=iconSize+4,
						height=iconSize+4,
						onMouseMove='talentPopup',
					}
					setTalentIconPos(s, tab, talent)
					s.Left = s.Left - 2
					s.Top = s.Top - 2
					shape = s
				end

				local i = VCL.Image{Name=n,
					onMouseMove='talentPopup',
				}
				--resizingImages[n] = true
				local rankCount=0
				for i,sid in ipairs(talent.spellId) do
					if(sid ~= 0) then rankCount = i; end
				end
				talentIcons[n] = {tab=tab, spell=spell, i=i, talent=talent, rankCount=rankCount, spentPoints=0}
				--i.AutoSize = true
				i.Width = iconSize
				i.Height = iconSize
				i.Hint = spell.name
				i.ShowHint = true
				i.Stretch = true
				i.Proportional = true
				--i.Transparent = true
				setTalentIconPos(i, tab, talent)
				i:LoadFromFile(cIconRaw(cSpellIcon(spell.spellIconID).icon))

				if(talent.row == 0) then
					local s = shape
					local i = VCL.Image{--Name=n,
						Left = i.Left+i.Width - 16,
						Top = i.Top+i.Height - 16,
						onMouseMove='talentPopup',
					}
					i:LoadFromFile(cIconRaw("Interface\\TalentFrame\\TalentFrame-RankBorder"))
				end
			end
		end
	end
end

local popup = {
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

function disablePopup(sender, shift, x, y)
	for n,c in pairs(popup) do
		c.visible = false
	end
end

function talentPopup(sender, shift, x, y)
	local t = talentIcons[sender.name]
	if(not t) then return; end
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

			-- causes crash
			--c.Constraints.MaxWidth = popup.inner.width
			--c.Constraints.MinWidth = 0
			--c.Constraints.maxHeight = 1000
			--c.Constraints.minHeight = 0
			--c.OnChange = "onChange"

			c.autosize = false
			c.width = popup.inner.width-2
			c.height = iconSize /2
			c.left = x+4
		end
		c.onMouseMove = "disablePopup"
	end
	popup.description.height = iconSize * 2
	if(up) then return; end

	popup.name.font.size = popup.rank.font.size * 1.5
	popup.name.font.color = VCL.clWhite
	popup.name.caption = t.spell.name

	popup.rank.font.color = VCL.clWhite
	popup.rank.caption = "Rank "..t.spentPoints.."/"..t.rankCount

	popup.requirements.font.color = VCL.clRed
	--popup.requirements.caption =

	popup.description.font.color = VCL.clYellow
	popup.description.caption = t.spell.description
end

disablePopup()

cIconRaw("Interface\\TalentFrame\\TalentFrame-RankBorder")
cIconRaw("Interface\\TalentFrame\\UI-TalentArrows")
cIconRaw("Interface\\TalentFrame\\UI-TalentBranches")
cIconRaw("Interface\\TalentFrame\\UI-TalentFrame-BotLeft")
cIconRaw("Interface\\TalentFrame\\UI-TalentFrame-BotRight")

mainForm:ShowModal()
mainForm:Free()

exit(0)
