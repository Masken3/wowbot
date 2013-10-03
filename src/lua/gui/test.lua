require "vcl"

-- internalName:tab
local tabs = {}

-- when this is empty, all images have been resized.
local resizingImages = {}

local images = {}

local iconSize = 40
local marginFraction = 0.25

local tabWidth = iconSize*4 + (iconSize*marginFraction*6)
local tabHeight = iconSize*8 + (iconSize*marginFraction*10)

mainForm = VCL.Form{
	name="mainForm",
	caption = "Talents",
	position="podesktopcenter",
	height=tabHeight,
	width=tabWidth*3,
	color=VCL.clBlack,
	onclosequery = "onCloseQueryEventHandler"
}

function onCloseQueryEventHandler(Sender)
	return true -- the form can be closed
end

function onResize(i)
	--print(i.Width, i.Name)
	--print(dump(i))
	resizingImages[i.Name] = nil
	if(not next(resizingImages)) then
		resizingImages['foobar'] = true -- prevent further resize
		--setBackgroundPosition()
	end
	local t = images[i.Name]
	if(t.talent) then
		local tab = t.tab
		--print(tab.tabPage.." "..t.talent.col.." "..t.talent.row)
		t.i.Left = tab.tabPage * tabWidth +
			t.talent.col * t.i.Width * (1+marginFraction) +
			t.i.Width * marginFraction
		t.i.Top = (t.talent.row+1) * t.i.Height * (1+marginFraction) + t.i.Height * marginFraction
	end
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
			local i = VCL.Image{onresize="onResize", Name=n}
			local t = {tab=tab, part=p, i=i}
			images[n] = t
			resizingImages[n] = true
			i.AutoSize = false
			i.Stretch = true
			i.Proportional = false
			setBackgroundPosition(t)
			i:LoadFromFile(cIconRaw("Interface\\TalentFrame\\"..tab.internalName.."-"..p))
		end
		-- tab icon
		do
			local i = VCL.Image{}
			i.Width = iconSize
			i.Height = iconSize
			i.Top = iconSize * marginFraction/2
			i.Left = tabWidth * (tab.tabPage + 0.5) - (iconSize/2)
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
				local s = cSpell(talent.spellId[1])
				if(not s) then
					print("talent "..n.." spellId "..talent.spellId[1].." not valid?!?")
				end
				local i = VCL.Image{onresize="onResize", Name=n}
				--resizingImages[n] = true
				images[n] = {tab=tab, spell=s, i=i, talent=talent}
				--i.AutoSize = true
				i.Width = iconSize
				i.Height = iconSize
				i.Hint = s.name
				i.ShowHint = true
				i.Stretch = true
				i.Proportional = true
				i:LoadFromFile(cIconRaw(cSpellIcon(s.spellIconID).icon))
			end
		end
	end
end

cIconRaw("Interface\\TalentFrame\\TalentFrame-RankBorder")
cIconRaw("Interface\\TalentFrame\\UI-TalentArrows")
cIconRaw("Interface\\TalentFrame\\UI-TalentBranches")
cIconRaw("Interface\\TalentFrame\\UI-TalentFrame-BotLeft")
cIconRaw("Interface\\TalentFrame\\UI-TalentFrame-BotRight")

mainForm:ShowModal()
mainForm:Free()

exit(0)
