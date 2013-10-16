
local gAvailablePoints

-- internalName:tab
local tabs = {}

local talentIcons = {}

local iconSize = 40
local marginFraction = 0.25

local tabWidth = iconSize*4 + (iconSize*marginFraction*6)
local tabHeight = iconSize*8 + (iconSize*marginFraction*10)

-- functions
local initializeForm
local handleResults
local talentHandleClickEvent
local drawTalentWindow
local showModal

local gInitialized

local results = {
	ok = false,
	newTalents = {},	-- t:maxRequestedRank
}

function doTalentWindow()
	if(gWindow) then
		return false
	end
	gWindow = SDL.SDL_CreateWindow(STATE.myName.."'s Talents", 32, 32,
		tabWidth*3, tabHeight + iconSize*(1+marginFraction*2), SDL.SDL_WINDOW_SHOWN)
	gSurface = SDL.SDL_GetWindowSurface(gWindow)
	gAvailablePoints = STATE.my.values[PLAYER_CHARACTER_POINTS1] or 0
	initializeForm()
	showNonModal(drawTalentWindow, handleResults, talentHandleClickEvent)
	return true
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
	for t, maxRank in pairs(results.newTalents) do
		print("CMSG_LEARN_TALENT "..t.talent.id.." "..maxRank)
		send(CMSG_LEARN_TALENT, {talentId=t.talent.id, requestedRank=maxRank})
	end
end

local function setTalentIconPos(i, tab, talent)
	i.Left = tab.tabPage * tabWidth +
		talent.col * iconSize * (1+marginFraction) +
		iconSize * marginFraction
	i.Top = (talent.row+1) * iconSize * (1+marginFraction) + iconSize * marginFraction
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
if(gInitialized) then
	return
end
gInitialized = true
for tab in cTalentTabs() do
	--print(dump(tt))
	if(tab.spellIcon == 11) then tab.tabPage = 1; end	-- patch MageFire
	if(tab.classMask == myClassMask()) then	-- mage
		tab.spentPoints = 0
		tab.rankCount = 0
		tab.rows = {}	-- row:{col:t}
		tab.backgroundParts = {}	--name:t
		tabs[tab.internalName] = tab

		-- gotta wait until onResize before AutoSize takes effect.
		-- tab background
		for i,p in ipairs(backgroundParts) do
			local t = {tab=tab, part=p, i={}}
			setBackgroundPosition(t)
			t.img = SDLimage.IMG_Load(cIconRaw("Interface\\TalentFrame\\"..tab.internalName.."-"..p))
			tab.backgroundParts[p] = t
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

				local rankCount=0
				for i,sid in ipairs(talent.spellId) do
					if(sid ~= 0) then rankCount = i; end
				end
				tab.rankCount = tab.rankCount + rankCount

				local spentPoints = talentRank(talent)
				tab.spentPoints = tab.spentPoints + spentPoints

				local t = {
					img=SDLimage.IMG_Load(cIconRaw(cSpellIcon(spell.spellIconID).icon)),
					tab=tab,
					rankCount=rankCount,
					spentPoints=spentPoints,
					spell=spell,
					talent=talent,
				}
				setTalentIconPos(t, tab, talent)
				t.r = SDL_Rect(t.Left, t.Top, iconSize, iconSize)
				talentIcons[talent] = t
			end
		end
		-- tab icon
		tab.icon = SDLimage.IMG_Load(cIconRaw(cSpellIcon(tab.spellIcon).icon))
	end
end
end	--initializeForm

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

function talentClick(t, button)
	--print(button)
	if(button == SDL_BUTTON_LEFT and canAddPoint(t)) then
		t.spentPoints = t.spentPoints + 1
		t.tab.spentPoints = t.tab.spentPoints + 1
		gAvailablePoints = gAvailablePoints - 1
		results.newTalents[t] = t.spentPoints-1
		print("set "..t.talent.id.." "..t.spentPoints)
	end
	if(button == SDL_BUTTON_RIGHT and canRemovePoint(t)) then
		local sm1 = t.spentPoints - 1
		t.spentPoints = sm1
		t.tab.spentPoints = t.tab.spentPoints - 1
		gAvailablePoints = gAvailablePoints + 1
		if(sm1 == 0) then
			results.newTalents[t] = nil
		else
			results.newTalents[t] = sm1
		end
	end
end

local gOkButton = {
	caption = "OK",
	r = SDL_Rect(tabWidth*2, tabHeight + iconSize/2, iconSize*2, iconSize*0.75),
}

local gCancelButton = {
	caption = "Cancel",
	r = SDL_Rect(tabWidth*2.5, tabHeight + iconSize/2, iconSize*2, iconSize*0.75),
}

function drawTalentWindow()
	--print("drawTalentWindow")
	-- the black
	SDL.SDL_FillRect(gSurface, SDL_Rect(0, 0, gSurface.w, gSurface.h), 0)
	-- tabs
	for internalName, tab in pairs(tabs) do
		--print(internalName, tab)
		-- background
		for name,t in pairs(tab.backgroundParts) do
			local r = SDL_Rect(t.i.Left, t.i.Top, t.i.Width, t.i.Height)
			--print(t.img, r)
			SDL.SDL_UpperBlitScaled(t.img, nil, gSurface, r)
		end
		-- icon
		local iconRect = SDL_Rect(
			tabWidth * tab.tabPage + (iconSize*(marginFraction)),
			iconSize * marginFraction/2,
			iconSize, iconSize)
		SDL.SDL_UpperBlitScaled(tab.icon, nil, gSurface, iconRect)
		-- label
		local t = tabLabelCaption(tab)
		--print(t)
		drawText(t, SDL_white, iconRect.x + iconSize*(1+marginFraction), iconRect.y)
	end

	-- talent icons
	local mouseOverTalent
	for talent, t in pairs(talentIcons) do
		local topRow = math.floor(t.tab.spentPoints / 5)
		local rankColor
		local borderColor

		if(pointIsInRect(gMouseX, gMouseY, t.r)) then
			assert(mouseOverTalent == nil)
			mouseOverTalent = t
		end

		-- border
		if(talent.row <= topRow) then
			if(t.spentPoints == t.rankCount) then
				rankColor = SDL_yellow
				borderColor = 0xffff00
			else
				rankColor = SDL_brightGreen
				borderColor = 0x00ff00
			end
			local r = SDL_Rect(t.r.x-2, t.r.y-2, t.r.w+4, t.r.h+4)
			SDL.SDL_FillRect(gSurface, r, borderColor)
		end

		-- icon
		SDL.SDL_UpperBlitScaled(t.img, nil, gSurface, t.r)

		-- rank label
		if(talent.row <= topRow) then
			drawText(t.spentPoints.."/"..t.rankCount, rankColor, t.r.x+t.r.w/2, t.r.y+t.r.h/1.5)
		end
	end

	-- "available points" label
	drawText("Available points: "..gAvailablePoints, SDL_white, iconSize/2, tabHeight + iconSize/2)

	-- buttons
	drawButton(gOkButton)
	drawButton(gCancelButton)

	-- popup
	if(mouseOverTalent) then
		local t = mouseOverTalent
		-- calculate position
		local x = t.Left + iconSize
		local y = t.Top + iconSize*1.5
		local w = tabWidth*2
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

		y = y + drawText(t.spell.name, SDL_white, x+2, y+2).h
		y = y + drawText("Rank "..t.spentPoints.."/"..t.rankCount, SDL_white, x+2, y+2).h
		drawTextWrap(t.spell.description, SDL_yellow, x+2, y+2, w-4)
	end
end

-- Set up our event loop
local function onCancel(sender)
	print("Cancel")
	gameover = true
end

local function onOK(sender)
	print("OK")
	gameover = true
	results.ok = true
end

function talentHandleClickEvent(event)
	for tal,t in pairs(talentIcons) do
		if(pointIsInRect(event.button.x, event.button.y, t.r)) then
			talentClick(t, event.button.button)
		end
	end
	if(pointIsInRect(event.button.x, event.button.y, gOkButton.r)) then
		onOK()
	end
	if(pointIsInRect(event.button.x, event.button.y, gCancelButton.r)) then
		onCancel()
	end
end

function showModal()
	gameover = false
	local event = ffi.new("SDL_Event")
	while not gameover do
		drawTalentWindow()

		-- Flush the output
		SDL.SDL_UpdateWindowSurface(gWindow)

		-- Check for escape keydown or quit events to stop the loop
		if (SDL.SDL_WaitEvent(event)) then
			handleEvent(event)
		end
	end
	SDL.SDL_DestroyWindow(gWindow)
	gWindow = false
end
