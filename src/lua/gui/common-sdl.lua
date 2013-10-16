
gMouseX = 0
gMouseY = 0

-- can only have one window per Lua state (for now)
gWindow = false
gSurface = false
gameover = false

local function initSDL()
	SDL = rawget(_G, 'SDL') or false
	if(SDL) then
		print("SDL already loaded")
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

	SDL.SDL_Init(SDL_INIT_VIDEO)
	SDLttf.TTF_Init()
	gFont = SDLttf.TTF_OpenFont("C:/Windows/Fonts/verdana.ttf", 16)
	SDLimage.IMG_Init(SDL.IMG_INIT_PNG)
end
initSDL()

function drawText(text, color, left, top)
	local s = SDLttf.TTF_RenderText_Solid(gFont, text, color)
	local r = SDL_Rect(left, top, s.w, s.h)
	SDL.SDL_FillRect(gSurface, r, 0)
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

function drawButton(b)
	local r = SDL_Rect(b.r)
	SDL.SDL_FillRect(gSurface, r, 0x00ff00)
	r.x=r.x+2
	r.y=r.y+2
	r.w=r.w-4
	r.h=r.h-4
	SDL.SDL_FillRect(gSurface, r, 0)
	drawText(b.caption, SDL_brightGreen, r.x+2, r.y+2)
end

function pointIsInRect(x, y, r)
	return (x >= r.x and x <= r.x+r.w and
		y >= r.y and y <= r.y+r.h)
end


local drawFunction
local onCloseFunction
local handleClickEvent

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

	if etype == SDL.SDL_KEYDOWN then
		local sym = event.key.keysym.sym
		if sym == SDL.SDLK_ESCAPE then
			-- Escape is pressed
			gameover = true
			return
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

function showNonModal(d, c, h)
	drawFunction, onCloseFunction, handleClickEvent = d, c, h
	gameover = false
	setTimer(checkEvents, getRealTime() + 0.1)
end
