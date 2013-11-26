
gMouseX = 0
gMouseY = 0

-- can only have one window per Lua state (for now)
gWindow = false
gSurface = false
gameover = false

local function initSDL()
	SDL = rawget(_G, 'SDL') or false
	if(SDL) then
		--print("SDL already loaded")
		return
	end

	print("Loading SDL...")
	-- load the luajit ffi module
	ffi = require "ffi"
	ffi.cdef(io.open('build/ffi_SDL.h', 'r'):read('*a'))
	-- Load the shared object
	SDL = ffi.load('SDL2')
	SDLttf = ffi.load('SDL2_ttf')
	SDLimage = ffi.load('SDL2_image')
	-- Define some constants that were in declares
	SDL_INIT_VIDEO = 0x20
	SDL_BUTTON_LEFT = 1
	SDL_BUTTON_MIDDLE = 2
	SDL_BUTTON_RIGHT = 3
	-- Make an easy constructor metatype
	SDL_Rect = ffi.metatype("SDL_Rect", {})
	SDL_Color = ffi.metatype("SDL_Color", {})

	SDL_white = SDL_Color(0xff,0xff,0xff,0xff)
	SDL_brightGreen = SDL_Color(0,0xff,0,0xff)
	SDL_yellow = SDL_Color(0xff,0xff,0,0xff)
	SDL_darkGreen = SDL_Color(0,0x80,0,0xff)
	SDL_black = SDL_Color(0,0,0,0xff)
	SDL_orange = SDL_Color(0xff,0x80,0,0xff)
	SDL_gray = SDL_Color(0x9d,0x9d,0x9d,0xff)

	SDL.SDL_Init(SDL_INIT_VIDEO)
	SDLttf.TTF_Init()
	gFont = SDLttf.TTF_OpenFont("C:/Windows/Fonts/verdana.ttf", 16)
	--gFont = SDLttf.TTF_OpenFont(cFindFontVerdana(), 16)
	--gFont = SDLttf.TTF_OpenFont("/usr/share/fonts/truetype/msttcorefonts/Verdana.ttf", 16)
	SDLimage.IMG_Init(SDL.IMG_INIT_PNG)
end
initSDL()

local function hexSub(s, a)
	return tonumber('0x'..s:sub(a,a+1))
end

local function h(s)	-- hexStringToSDL_Color
	return SDL_Color(hexSub(s,1), hexSub(s,3), hexSub(s,5), 0xff)
end

ITEM_QUALITY = {
	[0] = { color = h("9d9d9d"), name = "Poor" },
	[1] = { color = h("ffffff"), name = "Common" },
	[2] = { color = h("1eff00"), name = "Uncommon" },
	[3] = { color = h("0080ff"), name = "Rare" },
	[4] = { color = h("a335ee"), name = "Epic" },
	[5] = { color = h("ff8000"), name = "Legendary" },
	[6] = { color = h("ff0000"), name = "Artifact" },
	[7] = { color = h("e6cc80"), name = "Bind to Account" },
}

function drawText(text, color, left, top, backgroundColor)
	backgroundColor = backgroundColor or 0
	local s = SDLttf.TTF_RenderText_Solid(gFont, tostring(text), color)
	local r = SDL_Rect(left, top, s.w, s.h)
	if(backgroundColor) then
		if(type(backgroundColor) == "function") then
			backgroundColor(r)
		else
			SDL.SDL_FillRect(gSurface, r, backgroundColor)
		end
	end
	SDL.SDL_UpperBlit(s, nil, gSurface, r)
	SDL.SDL_FreeSurface(s)
	return r
end

function drawTextWrap(text, color, left, top, w)
	local s = SDLttf.TTF_RenderText_Blended_Wrapped(gFont, text, color, w)
	local r = SDL_Rect(left, top, s.w, s.h)
	SDL.SDL_UpperBlit(s, nil, gSurface, r)
	SDL.SDL_FreeSurface(s)
	return r
end

function drawButton(b, textColor)
	textColor = textColor or SDL_brightGreen
	local r = SDL_Rect(b.r)
	SDL.SDL_FillRect(gSurface, r, 0x00ff00)
	r.x=r.x+2
	r.y=r.y+2
	r.w=r.w-4
	r.h=r.h-4
	SDL.SDL_FillRect(gSurface, r, 0)
	drawText(b.caption, textColor, r.x+2, r.y+2)
end

function pointIsInRect(x, y, r)
	return (x >= r.x and x <= r.x+r.w and
		y >= r.y and y <= r.y+r.h)
end

-- save and reuse known images.
local iconImages = {}	-- name:SDL_Surface
function getImageFromFile(name)
	local icon = iconImages[name]
	if(not icon) then
		icon = SDLimage.IMG_Load(name)
		iconImages[name] = icon
	end
	return icon
end
function getItemIcon(proto)
	return getImageFromFile(cIcon(cItemDisplayInfo(proto.DisplayInfoID).icon))
end
function getSpellIcon(spellIconID)
	return getImageFromFile(cIconRaw(cSpellIcon(spellIconID).icon))
end


local drawFunction
local onCloseFunction
local handleClickEvent
local handleKeyEvent
local handleMouseUpEvent

local function handleEvent(event)
	local etype=event.type
	if etype == SDL.SDL_QUIT then
		-- close button clicked
		gameover = true
		return
	end

	if etype == SDL.SDL_MOUSEMOTION then
		gMouseX = event.motion.x
		gMouseY = event.motion.y
	end

	if etype == SDL.SDL_MOUSEBUTTONDOWN then
		handleClickEvent(event)
	end

	if etype == SDL.SDL_MOUSEBUTTONUP and handleMouseUpEvent then
		handleMouseUpEvent(event)
	end

	if etype == SDL.SDL_KEYDOWN then
		local sym = event.key.keysym.sym
		if sym == SDL.SDLK_ESCAPE then
			-- Escape is pressed
			gameover = true
			return
		end
		if(handleKeyEvent) then
			handleKeyEvent(event, sym)
		end
	end
end

local function checkEvents(realTime)
	--print("checkEvents", realTime)
	local event = ffi.new("SDL_Event")
	while((not gameover) and (SDL.SDL_PollEvent(event) == 1)) do
		handleEvent(event)
		drawFunction()
		SDL.SDL_UpdateWindowSurface(gWindow)
	end
	if(gameover) then
		SDL.SDL_DestroyWindow(gWindow)
		gWindow = false
		onCloseFunction()
	else
		setTimer(checkEvents, getRealTime() + 0.1)
	end
end

function showNonModal(d, c, h, k, u)
	drawFunction, onCloseFunction, handleClickEvent,
		handleKeyEvent, handleMouseUpEvent =
		d, c, h, k, u
	gameover = false
	setTimer(checkEvents, getRealTime() + 0.1)
end

local sAlphaFillRects = {}	-- string:SDL_surface

-- impossible to alpha-blend rect without SDL_render.
-- unless you create a temporary surface and blit it.
-- this function caches surfaces created. color format: RGBA.
function sdlAlphaFillRect(surface, r, color)
	local id = tostring(r.w).."x"..r.h.." "..color
	if(not sAlphaFillRects[id]) then
		sAlphaFillRects[id] = SDL.SDL_CreateRGBSurface(0,r.w,r.h,32,0,0,0, 0xff)
		SDL.SDL_FillRect(sAlphaFillRects[id], SDL_Rect(0,0,r.w,r.h), color)
	end
	SDL.SDL_UpperBlit(sAlphaFillRects[id], nil, gSurface, r)
end
