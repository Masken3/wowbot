local iconSize=40
local marginFraction = 0.2

-- functions
local init
local createWindow
local drawProfWindow
local onCloseProfWindow
local profHandleClickEvent
local profHandleMouseUpEvent
local profHandleKeyEvent

local sSkillValue
local sSkillMax
local sSkillModifier
local sSkillIndex
local sSkillLine
local sSpells = {}	-- array:{s,sla}
local sMouseDownOnSpell
local sSelectedSpell
local sCreateAllButton
local sCreateCountBox = {caption=1}
local sCreateButton
local sCancelButton

local function windowTitle()
	return sSkillLine.name.." - "..sSkillValue.."/"..(sSkillMax+sSkillModifier)
end

function doProfessionWindow(skillLine)
	if(gWindow) then
		return false
	end

	-- at first try, it's likely we won't have all item protos required to display the window.
	-- wait until we do, and block other windows from being opened in the meantime.
	if(init(skillLine)) then
		createWindow()
	else
		gWindow = true
		STATE.itemDataCallbacks["profession"] = createWindow
	end
	return true
end

function createWindow()
	gWindow = SDL.SDL_CreateWindow(windowTitle(), 32, 32,
		800, 600, SDL.SDL_WINDOW_SHOWN)
	gSurface = SDL.SDL_GetWindowSurface(gWindow)

	showNonModal(drawProfWindow, onCloseProfWindow, profHandleClickEvent,
		profHandleKeyEvent, profHandleMouseUpEvent)
end

function init(skillLine)
	local count = 0
	local haveAllProtos = true

	sSkillLine = skillLine
	sSkillIndex = skillIndex(skillLine.id)
	sSkillValue, sSkillMax = skillLevelByIndex(sSkillIndex)

	sSkillModifier = GetMaxPassiveAuraModifierWithMisc(
		SPELL_AURA_MOD_SKILL_TALENT, skillLine.id)
	--print("sSkillModifier: "..sSkillModifier)
	--print(dump(STATE.knownSpells[20593]))

	for id, s in pairs(STATE.knownSpells) do
		local sla = cSkillLineAbilityBySpell(id)
		if(sla and sla.skill == skillLine.id) then
			count = count + 1
			sSpells[count] = {s=s,sla=sla}

			-- check protos
			local e = s.effect[1]
			if(e.id == SPELL_EFFECT_CREATE_ITEM) then
				-- created item
				local itemId = e.itemType
				local proto = itemProtoFromId(itemId)
				if(not proto) then haveAllProtos = false end
				for i,rea in ipairs(s.reagent) do
					if(rea.count > 0) then
						local proto = itemProtoFromId(rea.id)
						if(not proto) then haveAllProtos = false end
					end
				end
			end
		end
	end
	table.sort(sSpells, function(first, last)
		return first.sla.minValue > last.sla.minValue
	end)
	return haveAllProtos
end

-- Notes on interface design:

-- on the left, a list of spells with scroll bar.
-- avail-count is added if all reagents are present.
-- spells are colored and ordered by difficulty.
-- when selected, text becomes white and row background gets difficulty color.
-- mouse-down: displace text 1 pixel down-right.
-- mouse-up: end displacement. if cursor is still on displaced text, select it.

-- on the right, controls:
-- created-item icon, name(colored).
-- reagents: 2x4, icon (overlay count have/required), name.
-- if you don't have enough reagents for one item, gray out the icon by
-- drawing a black half-transparent rect over it.
-- clicking on icons or names opens item link in a browser.

-- Below the reagents, buttons:
-- Create All, textbox(count), Create.
-- number keystrokes writes to textbox. backspace deletes. empty textbox resets to "1".

function drawProfWindow()
	if(not gWindow) then return end

	local x = 2
	local y = 2
	local itemCounts = getItemCounts()

	sSkillValue, sSkillMax = skillLevelByIndex(sSkillIndex)
	SDL.SDL_SetWindowTitle(gWindow, windowTitle())

	-- the black
	SDL.SDL_FillRect(gSurface, SDL_Rect(0, 0, gSurface.w, gSurface.h), 0)

	-- spells
	for i,sp in ipairs(sSpells) do
		local spellText = sp.s.name
		local sla = sp.sla
		local count = haveReagents(itemCounts, sp.s)
		if(count) then
			spellText = spellText.." ["..count.."]"
			sp.max = count
		end

		local spellColor
		local backgroundColor
		local modifiedSkillValue = sSkillValue - sSkillModifier
		if(modifiedSkillValue < sla.minValue) then
			spellColor = SDL_orange
			backgroundColor = 0xffc06000
		elseif(modifiedSkillValue < ((sla.minValue + sla.maxValue) / 2)) then
			spellColor = SDL_yellow
			backgroundColor = 0xff808000
		elseif(modifiedSkillValue < sla.maxValue) then
			spellColor = SDL_darkGreen
			backgroundColor = 0xff008000
		else
			spellColor = SDL_gray
			backgroundColor = 0xff9d9d9d
		end

		if(sSelectedSpell == i) then
			spellColor = SDL_white
			local bc = backgroundColor
			backgroundColor = function(r)
				r.w = gSurface.w/2
				SDL.SDL_FillRect(gSurface, r, bc)
			end
		else
			backgroundColor = 0
		end

		local offset = 0
		if(sMouseDownOnSpell == i) then
			offset = 1
		end

		local r = drawText(spellText, spellColor, x+offset, y+offset, backgroundColor)
		sp.r = {x=x, y=y, w=gSurface.w/2, h=r.h}

		y = y + r.h
	end

	-- right side
	x = gSurface.w / 2
	y = 2
	if(not sSelectedSpell) then
		return
	end
	local sp = sSpells[sSelectedSpell]
	local s = sp.s
	local e = s.effect[1]
	local spellTextColor
	local icon
	if(e.id == SPELL_EFFECT_CREATE_ITEM) then
		-- created item
		local itemId = e.itemType
		local proto = itemProtoFromId(itemId)
		if(not proto) then
			-- at this point, something's gone wrong and we won't be able to display anything useful.
			-- likely caused by a hidden spell, like 13166 (Battle Chicken)
			return
		end
		spellTextColor = ITEM_QUALITY[proto.Quality].color
		icon = getItemIcon(proto)
	else
		spellTextColor = SDL_white
		icon = getSpellIcon(s.spellIconID)
	end
	local r = SDL_Rect(x, y, icon.w, icon.h)
	SDL.SDL_UpperBlit(icon, nil, gSurface, r)
	drawText(s.name, SDL_white, x+icon.w+2, y+2)

	-- reagents
	y = y + icon.h * (1+marginFraction*2)
	local a=0
	local b=0
	for i,rea in ipairs(s.reagent) do
		local ax = x + a * gSurface.w / 4
		local by = y + b * iconSize * (1+marginFraction)
		local textOffset = (iconSize * (1+marginFraction))
		local textWidth = (gSurface.w / 4) - textOffset
		local textHeight = iconSize
		if(rea.count > 0) then
			local proto = itemProtoFromId(rea.id)
			-- icon
			local rect = SDL_Rect(ax, by, iconSize, iconSize)
			SDL.SDL_UpperBlitScaled(getItemIcon(proto), nil, gSurface, rect)
			local nameTextColor
			if((itemCounts[rea.id] or 0) < rea.count) then
				-- gray out
				--sdlAlphaFillRect(gSurface, rect, 0x80000000)	-- doesn't work.
				nameTextColor = SDL_gray
			else
				nameTextColor = SDL_white
			end
			-- counts
			drawText((itemCounts[rea.id] or 0).."/"..rea.count, SDL_brightGreen, ax, by+iconSize/1.5)
			-- item name
			drawTextWrap(proto.name, nameTextColor, ax + textOffset, by, textWidth)
		end
		-- move to next reagent UI slot
		a = a + 1
		if(a > 1) then
			a = 0
			b = b + 1
		end
	end

	-- buttons
	y = gSurface.h - iconSize*2

	sCreateAllButton = {caption="Create All", r=SDL_Rect(x, y, iconSize*3, iconSize)}
	drawButton(sCreateAllButton)
	x = x + iconSize*(3+marginFraction)

	sCreateCountBox.r = SDL_Rect(x, y, iconSize, iconSize)
	-- if the caption is not a number, use white text instead of the regular green.
	drawButton(sCreateCountBox, (type(sCreateCountBox.caption) == "string") and SDL_white)
	x = x + iconSize*(1+marginFraction)

	sCreateButton = {caption="Create", r=SDL_Rect(x, y, iconSize*2, iconSize)}
	drawButton(sCreateButton)
	x = x + iconSize*(2+marginFraction)

	sCancelButton = {caption="Cancel", r=SDL_Rect(x, y, iconSize*2, iconSize)}
	drawButton(sCancelButton)
end

function onCloseProfWindow()
end

local function castMulti(s, count)
	partyChat("Will cast "..s.name.." "..s.rank.." "..count.." times.")
	STATE.repeatSpellCast.id = s.id
	STATE.repeatSpellCast.count = count
	decision()
end

local function onCreateAll()
	local sp = sSpells[sSelectedSpell]
	castMulti(sp.s, sp.max)
end

local function onCreate()
	castMulti(sSpells[sSelectedSpell].s, tonumber(sCreateCountBox.caption))
end

local function onCancel()
	STATE.repeatSpellCast.count = 0
	send(CMSG_CANCEL_CAST, {spellId=0})
end

function profHandleClickEvent(event)
	for i,sp in ipairs(sSpells) do
		if(pointIsInRect(event.button.x, event.button.y, sp.r)) then
			sMouseDownOnSpell = i
			break
		end
	end
	if(not sCreateAllButton) then return end
	if(pointIsInRect(event.button.x, event.button.y, sCreateAllButton.r)) then
		onCreateAll()
	end
	if(pointIsInRect(event.button.x, event.button.y, sCreateButton.r)) then
		onCreate()
	end
	if(pointIsInRect(event.button.x, event.button.y, sCancelButton.r)) then
		onCancel()
	end
end

function profHandleMouseUpEvent(event)
	if(sMouseDownOnSpell and
		pointIsInRect(event.button.x, event.button.y, sSpells[sMouseDownOnSpell].r))
	then
		sSelectedSpell = sMouseDownOnSpell
	end
	sMouseDownOnSpell = false
end

function profHandleKeyEvent(event, sym)
	local c = sCreateCountBox.caption
	if(sym == SDL.SDLK_BACKSPACE) then
		if(type(c) == "string") then
			c = c:sub(1, #c - 1)
			if(#c == 0) then
				c = 1
			end
			sCreateCountBox.caption = c
		end
	elseif(sym >= SDL.SDLK_0 and sym <= SDL.SDLK_9) then
		local num = (sym - SDL.SDLK_0)
		if(type(c) == "string") then
			c = c..num
		else
			c = tostring(num)
		end
		sCreateCountBox.caption = c
	end
end
