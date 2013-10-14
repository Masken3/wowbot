-- load the luajit ffi module
local ffi = require "ffi"
-- Parse the C API header
-- It's generated with:
--
--     echo '#include <SDL.h>' > stub.c
--     gcc -I /usr/include/SDL -E stub.c | grep -v '^#' > ffi_SDL.h
--
ffi.cdef(io.open('build/ffi_SDL.h', 'r'):read('*a'))
-- Load the shared object
local SDL = ffi.load('SDL2')
local SDLttf = ffi.load('SDL2_ttf')
local SDLimage = ffi.load('SDL2_image')
-- Define some constants that were in declares
local SDL_INIT_VIDEO = 0x20
local SDL_BUTTON_LEFT = 1
local SDL_BUTTON_MIDDLE = 2
local SDL_BUTTON_RIGHT = 3
-- Make an easy constructor metatype
local SDL_Rect = ffi.metatype("SDL_Rect", {})
local SDL_Color = ffi.metatype("SDL_Color", {})

local SDL_white = SDL_Color(0xff,0xff,0xff,0xff)
local SDL_brightGreen = SDL_Color(0,0xff,0,0xff)
local SDL_yellow = SDL_Color(0xff,0xff,0,0xff)
local SDL_darkGreen = SDL_Color(0,0x80,0,0xff)
local SDL_black = SDL_Color(0,0,0,0xff)

local gAvailablePoints = 11

local gMouseX = 0
local gMouseY = 0

-- internalName:tab
local tabs = {}

local talentIcons = {}

local iconSize = 40
local marginFraction = 0.25

local tabWidth = iconSize*4 + (iconSize*marginFraction*6)
local tabHeight = iconSize*8 + (iconSize*marginFraction*10)

-- Create the window
SDL.SDL_Init(SDL_INIT_VIDEO)
local window = SDL.SDL_CreateWindow("Talents", 32, 32,
	tabWidth*3, tabHeight + iconSize*(1+marginFraction*2), SDL.SDL_WINDOW_SHOWN)
local surface = SDL.SDL_GetWindowSurface(window)

SDLttf.TTF_Init()
local font = SDLttf.TTF_OpenFont("C:/Windows/Fonts/verdana.ttf", 16)

SDLimage.IMG_Init(SDL.IMG_INIT_PNG)

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

for tab in cTalentTabs() do
	--print(dump(tab))
	if(tab.spellIcon == 11) then tab.tabPage = 1; end	-- patch MageFire
	if(tab.classMask == 128) then	-- mage
		tabs[tab.internalName] = tab
		tab.spentPoints = 0
		tab.rankCount = 0
		tab.rows = {}	-- row:{col:t}
		tab.backgroundParts = {}	--name:t

		-- gotta wait until onResize before AutoSize takes effect.
		-- tab background
		for i,p in ipairs(backgroundParts) do
			local t = {tab=tab, part=p, i={}}
			setBackgroundPosition(t)
			t.img = SDLimage.IMG_Load(cIconRaw("Interface\\TalentFrame\\"..tab.internalName.."-"..p))
			tab.backgroundParts[p] = t
		end
		--print(tabs[tab.internalName].backgroundParts)
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
				local t = {
					img=SDLimage.IMG_Load(cIconRaw(cSpellIcon(spell.spellIconID).icon)),
					tab=tab,
					rankCount=rankCount,
					spentPoints=0,
					spell=spell,
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
	end
	if(button == SDL_BUTTON_RIGHT and canRemovePoint(t)) then
		t.spentPoints = t.spentPoints - 1
		t.tab.spentPoints = t.tab.spentPoints - 1
		gAvailablePoints = gAvailablePoints + 1
	end
end

function onCancel(sender)
	print("Cancel")
	mainForm:Close()
end

function onOK(sender)
	print("OK")
	mainForm:Close()
end

cIconRaw("Interface\\TalentFrame\\TalentFrame-RankBorder")
cIconRaw("Interface\\TalentFrame\\UI-TalentArrows")
cIconRaw("Interface\\TalentFrame\\UI-TalentBranches")
cIconRaw("Interface\\TalentFrame\\UI-TalentFrame-BotLeft")
cIconRaw("Interface\\TalentFrame\\UI-TalentFrame-BotRight")

local function drawText(text, color, left, top)
	local s = SDLttf.TTF_RenderText_Solid(font, text, color)
	local r = SDL_Rect(left, top, s.w, s.h)
	SDL.SDL_FillRect(surface, r, 0)
	SDL.SDL_UpperBlit(s, nil, surface, r)
	SDL.SDL_FreeSurface(s)
	return r
end

local function drawTextWrap(text, color, left, top, w)
	local s = SDLttf.TTF_RenderText_Blended_Wrapped(font, text, color, w)
	local r = SDL_Rect(left, top, s.w, s.h)
	SDL.SDL_UpperBlit(s, nil, surface, r)
	SDL.SDL_FreeSurface(s)
	return r
end

local function drawButton(b)
	local r = SDL_Rect(b.r)
	SDL.SDL_FillRect(surface, r, 0x00ff00)
	r.x=r.x+2
	r.y=r.y+2
	r.w=r.w-4
	r.h=r.h-4
	SDL.SDL_FillRect(surface, r, 0)
	drawText(b.caption, SDL_brightGreen, r.x+2, r.y+2)
end

local function pointIsInRect(x, y, r)
	return (x >= r.x and x <= r.x+r.w and
		y >= r.y and y <= r.y+r.h)
end

local gOkButton = {
	caption = "OK",
	r = SDL_Rect(tabWidth*2, tabHeight + iconSize/2, iconSize*2, iconSize*0.75),
}

local gCancelButton = {
	caption = "Cancel",
	r = SDL_Rect(tabWidth*2.5, tabHeight + iconSize/2, iconSize*2, iconSize*0.75),
}

local function drawTalentWindow()
	--print("drawTalentWindow")
	-- the black
	SDL.SDL_FillRect(surface, SDL_Rect(0, 0, surface.w, surface.h), 0)
	-- tabs
	for internalName, tab in pairs(tabs) do
		--print(internalName, tab)
		-- background
		for name,t in pairs(tab.backgroundParts) do
			local r = SDL_Rect(t.i.Left, t.i.Top, t.i.Width, t.i.Height)
			--print(t.img, r)
			SDL.SDL_UpperBlitScaled(t.img, nil, surface, r)
		end
		-- icon
		local iconRect = SDL_Rect(
			tabWidth * tab.tabPage + (iconSize*(marginFraction)),
			iconSize * marginFraction/2,
			iconSize, iconSize)
		SDL.SDL_UpperBlitScaled(tab.icon, nil, surface, iconRect)
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
			SDL.SDL_FillRect(surface, r, borderColor)
		end

		-- icon
		SDL.SDL_UpperBlitScaled(t.img, nil, surface, t.r)

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

		if(surface.w < x + w) then
			x = surface.w - (w + iconSize)
		end
		if(surface.h < y + h) then
			y = y - (h + iconSize*2)
		end

		-- border
		SDL.SDL_FillRect(surface, SDL_Rect(x-3, y-3, w+6, h+6), 0xffffffff)
		-- inner
		SDL.SDL_FillRect(surface, SDL_Rect(x-2, y-2, w+4, h+4), 0)

		y = y + drawText(t.spell.name, SDL_white, x+2, y+2).h
		y = y + drawText("Rank "..t.spentPoints.."/"..t.rankCount, SDL_white, x+2, y+2).h
		drawTextWrap(t.spell.description, SDL_yellow, x+2, y+2, w-4)
	end
end

-- Set up our event loop
local gameover = false
local event = ffi.new("SDL_Event")
while not gameover do
	--[[
	-- Draw 8192 randomly colored rectangles to the screen
	for i = 0,0x2000 do
		local r = SDL_Rect(math.random(surface.w)-10, math.random(surface.h)-10,20,20)
		local color = math.random(0x1000000)
		SDL.SDL_SetRenderDrawColor(render, math.random(256), math.random(256), math.random(256), 0xff)
		SDL.SDL_RenderFillRect(render, r)
	end
	--]]
	drawTalentWindow()

	-- Flush the output
	SDL.SDL_UpdateWindowSurface(window)

	-- Check for escape keydown or quit events to stop the loop
	if (SDL.SDL_WaitEvent(event)) then

		local etype=event.type

		if etype == SDL.SDL_QUIT then
			-- close button clicked
			gameover = true
			break
		end

		if etype == SDL.SDL_MOUSEMOTION then
			gMouseX = event.motion.x
			gMouseY = event.motion.y
		end

		if etype == SDL.SDL_MOUSEBUTTONDOWN then
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

		if etype == SDL.SDL_KEYDOWN then
			local sym = event.key.keysym.sym
			if sym == SDL.SDLK_ESCAPE then
				-- Escape is pressed
				gameover = true
				break
			end
		end

	end

end

-- When the loop finishes, clean up, print a message, and exit
SDL.SDL_Quit();
print("Thanks for Playing!");

cExit(0)
