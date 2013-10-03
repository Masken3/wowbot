require "vcl"

mainForm = VCL.Form{
	name="mainForm",
	caption = "Talents",
	position="podesktopcenter",
	height=400,
	width=(256+64)*3,
	onclosequery = "onCloseQueryEventHandler"
}

function onCloseQueryEventHandler(Sender)
	return true -- the form can be closed
end

-- internalName:tab
local tabs = {}

-- when this is empty, all images have been resized.
local resizingImages = {}

local images = {}

function onResize(i)
	--print(i.Width, i.Name)
	--print(dump(i))
	resizingImages[i.Name] = nil
	if(not next(resizingImages)) then
		setBackgroundPosition()
		resizingImages['foobar'] = true -- prevent further resize
	end
	local t = images[i.Name]
	if(t.talent) then
		local tab = t.tab
		print(tab.tabPage.." "..t.talent.col.." "..t.talent.row)
		t.i.Left = tab.tabPage * (images[tab.internalName..'TopLeft'].i.Width +
			images[tab.internalName..'TopRight'].i.Width) + t.talent.col * t.i.Width * 1.1 + t.i.Width * 0.1
		t.i.Top = t.talent.row * t.i.Height * 1.1 + t.i.Height * 0.1
	end
end

function setBackgroundPosition()
	print("setBackgroundPosition")
	for name,t in pairs(images) do
		local tab = t.tab
		if(t.part == 'TopLeft') then
			t.i.Left = tab.tabPage * (t.i.Width + images[tab.internalName..'TopRight'].i.Width)
		end
		if(t.part == 'TopRight') then
			local tlw = images[tab.internalName..'TopLeft'].i.Width
			t.i.Left = tab.tabPage * (t.i.Width + tlw) + tlw
		end
		if(t.part == 'BottomRight') then
			local tlw = images[tab.internalName..'TopLeft'].i.Width
			t.i.Left = tab.tabPage * (t.i.Width + tlw) + tlw
			t.i.Top = images[tab.internalName..'TopRight'].i.Height
		end
		if(t.part == 'BottomLeft') then
			t.i.Left = tab.tabPage * (t.i.Width + images[tab.internalName..'TopRight'].i.Width)
			t.i.Top = images[tab.internalName..'TopLeft'].i.Height
		end
	end
end

local backgroundParts = {'TopLeft','TopRight','BottomLeft','BottomRight'}

for tab in cTalentTabs() do
	--print(dump(tt))
	if(tab.spellIcon == 11) then tab.tabPage = 1; end	-- patch MageFire
	if(tab.classMask == 128) then	-- mage
		-- gotta wait until onResize before positioning.
		for i,p in ipairs(backgroundParts) do
			local n = tab.internalName..p
			local i = VCL.Image{onresize="onResize", Name=n}
			local t = {tab=tab, part=p, i=i}
			images[n] = t
			resizingImages[n] = true
			i.AutoSize = true
			i:LoadFromFile(cIconRaw("Interface\\TalentFrame\\"..tab.internalName.."-"..p))
		end
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
				i.Width = 40
				i.Height = 40
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
