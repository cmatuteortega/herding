-- Counting Sheep: a cozy bedtime incremental game. You count sheep to fall
-- asleep: it starts with one fence at dusk and ends with sheep in orbit and an
-- AI counting for you, and when the Drowsiness bar fills, you sleep.
--
-- Everything renders into one low-res canvas blown up by a whole number, so a
-- game pixel is always an exact block of screen pixels (herding's fit, and
-- underroot's): the zoom is picked off the window's short edge, never under 3,
-- so the 3x5 lettering stands at least 15 pixels tall. The bodies are
-- ellipsoids, ray-traced a pose at a time and kept (tracer.lua, models.lua).
--
-- The rules are game.lua, on a fixed step here; every number is config.lua.
-- The field is scene.lua, everything round it ui.lua, the sound audio.lua.
--
--   love .              play
--   love . --speed 10   dev: the rules run ten times as fast (1 to 1000)
--   love . --shots      dev: plays a few scripted moments, writes pictures, quits
--   love . --sounds     dev: every sound and pad layer written as a .wav, then quits
--   love . --fresh      dev: ignores the save and starts a new game
--   love . --autoplay N dev: a scripted player taps and buys for N game seconds
--                       (with --speed, quickly), prints how it went, writes a picture
--   love . --lucid      dev: straight into phase 2, lucid dreaming, with points to
--                       spend (L does the same mid-game, with any dev flag on)

local G = require "gfx"
local Game = require "game"
local Lucid = require "lucid.game"
local C = require "config"
local UI = require "ui"
local Scene = require "scene"
local Audio = require "audio"
local flux = require "lib.flux"

local floor, min, max = math.floor, math.min, math.max

local SHORT = 240 -- game pixels down the short edge, at the most
local MOBILE = love.system.getOS() == "Android" or love.system.getOS() == "iOS"

local canvas
local vw, vh, zoom, offX, offY = 320, 240, 1, 0, 0
local speed = 1
local acc, saveIn, wall = 0, C.save.intervalSeconds, os.time()
local shots, autoplay
local dev = false -- any dev flag: the L key jumps to phase 2

-- Dev: phase 2 now, as if a lucid night had just been slept, with the points a
-- player usually brings (about twenty nights' worth earned, one night's held).
local function jumpToLucid(s)
    s.dreams = math.max(s.dreams, 19)
    s.dreamEarned = math.max(s.dreamEarned, 7000)
    s.dreamPoints = math.max(s.dreamPoints, 750)
    s.phase, s.asleep = "lucid", false
    s.lucid = Lucid.fresh(s)
    s.dreamPoints = 0
    UI.setState(s)
    require("lucid.ui").enter()
end

local function fit()
    local w, h = love.graphics.getDimensions()
    local short = min(w, h)
    -- As many game pixels as fit, but each at least three screen pixels.
    zoom = max(1, floor(short / SHORT))
    if zoom < 3 and short >= 3 * 160 then zoom = 3 end
    local cw, ch = math.ceil(w / zoom), math.ceil(h / zoom)
    if cw ~= vw or ch ~= vh or not canvas then
        vw, vh = cw, ch
        canvas = love.graphics.newCanvas(vw, vh)
        canvas:setFilter("nearest", "nearest")
    end
    offX, offY = floor((w - vw * zoom) / 2), floor((h - vh * zoom) / 2)
    -- Notches and gesture bars: a margin off each edge.
    local inset = { l = 0, t = 0, r = 0, b = 0 }
    if love.window.getSafeArea then
        local sx, sy, sw, sh = love.window.getSafeArea()
        local l, t = (sx - offX) / zoom, (sy - offY) / zoom
        inset.l, inset.t = max(0, floor(l)), max(0, floor(t))
        inset.r = max(0, math.ceil(vw - (l + sw / zoom)))
        inset.b = max(0, math.ceil(vh - (t + sh / zoom)))
    end
    UI.fit(vw, vh, inset)
    return vw, vh
end

-- A window pixel to a canvas pixel.
local function toGame(x, y) return (x - offX) / zoom, (y - offY) / zoom end

function love.load(args)
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setLineStyle("rough")
    love.graphics.setPointSize(1)
    love.keyboard.setKeyRepeat(false)
    local fresh, toLucid = false, false
    for k, a in ipairs(args or {}) do
        if a == "--speed" then speed = max(1, min(1000, tonumber(args[k + 1]) or 1)); dev = true end
        if a == "--fresh" then fresh = true; dev = true end
        if a == "--lucid" then toLucid, fresh, dev = true, true, true end
        if a == "--shots" then shots = true end
        if a == "--sounds" then
            local t0 = love.timer.getTime()
            print(Audio.dump(), ("%.2fs"):format(love.timer.getTime() - t0))
            love.event.quit()
            return
        end
        if a == "--autoplay" then autoplay = { left = tonumber(args[k + 1]) or 300, tap = 0, shop = 0, firsts = {} } end
    end
    if MOBILE then love.window.setFullscreen(true, "desktop") end
    fit()
    Audio.init()
    Scene.cue = function(name) UI.cue(name) end
    if shots then
        require("shots").run(UI, fit)
        return
    end
    if autoplay then fresh, UI.noSave, dev = true, true, true end
    local s = not fresh and UI.load() or nil
    UI.setState(s or Game.fresh())
    s = UI.state()
    Audio.setMuted(s.muted)
    Audio.setLullabies(s.owned.lullaby)
    if toLucid then
        jumpToLucid(s)
    elseif s.phase == "lucid" then
        UI.showLucid()
        UI.away(os.difftime(os.time(), s.lastSeen))
    elseif s.asleep then
        Scene.fx.lids.close = 1
        Audio.setAsleep(true)
        UI.showEnding()
    else
        UI.away(os.difftime(os.time(), s.lastSeen))
    end
    if speed > 1 then print(("counting sheep: speed x%d"):format(speed)) end
end

function love.resize() fit() end
function love.displayrotated() fit() end

local STEP = 1 / C.tickRate

function love.update(dt)
    if shots or not UI.state() then return end
    dt = min(dt, 0.25)
    local s = UI.state()
    -- Gone a while with the game still running (a phone locked, a laptop
    -- asleep): that counts as away, not as one enormous frame.
    local now = os.time()
    local gap = os.difftime(now, wall)
    wall = now
    if gap > 5 then UI.away(gap); dt = 0 end
    acc = acc + dt * speed
    local n = 0
    while acc >= STEP and n < 4000 do
        if s.phase == "lucid" and s.lucid then Lucid.step(s.lucid, STEP) else Game.step(s, STEP) end
        acc, n = acc - STEP, n + 1
    end
    if n >= 4000 then acc = 0 end
    if autoplay and s.phase == "lucid" then
        -- Phase 2: catch the golden sheep (take the frenzy), buy dimensions
        -- top down, and build the first thing it can on the first free plot.
        local L = s.lucid
        if L.golden and L.golden.t > 2 then Lucid.catchGolden(L) end
        if L.choosing then Lucid.choose(L, "frenzy") end
        L.intro = false
        for k = #L.dims, 1, -1 do if Lucid.dimVisible(L, k) then Lucid.buyDim(L, k, "max", 0.5) end end
        for _, b in ipairs(Lucid.BUILD) do
            if Lucid.canBuild(L, b.id) then
                for c in pairs(L.open) do
                    if not L.grid[c] and Lucid.build(L, b.id, c) then
                        autoplay.firsts[#autoplay.firsts + 1] = ("%s@%ds"):format(b.id, L.time)
                        break
                    end
                end
            end
        end
        if L.time >= autoplay.left then autoplay.done = true end
    elseif autoplay then
        -- Two taps a game second, and the priciest thing it can pay for.
        autoplay.tap = autoplay.tap + dt * speed * 2
        while autoplay.tap >= 1 do
            autoplay.tap = autoplay.tap - 1
            local r = UI.sceneRect()
            UI.pressed(r.x + r.w / 2, r.y + r.h * 0.8, "auto")
        end
        if s.golden and s.golden.t > 2 then Game.catchGolden(s) end
        local best, cost = nil, -1
        for _, it in ipairs(Game.ITEMS) do
            local q = Game.visible(s, it.id) and Game.quote(s, it.id, "1")
            if q and q.ok and q.cost > cost then best, cost = it.id, q.cost end
        end
        if best then
            if s.owned[best] == 0 then autoplay.firsts[#autoplay.firsts + 1] = ("%s@%ds"):format(best, s.runTime) end
            UI.buy(best)
        end
        if s.runTime >= autoplay.left then
            autoplay.done = true
        end
    end
    UI.drain()
    Scene.update(dt, s)
    UI.update(dt)
    flux.update(dt)
    Audio.update(dt)
    saveIn = saveIn - dt
    if saveIn <= 0 then saveIn = C.save.intervalSeconds; UI.save() end
end

function love.draw()
    if not UI.state() then return end -- a dev run that never started a night
    love.graphics.setCanvas(canvas)
    love.graphics.clear(G.C.n)
    UI.draw()
    love.graphics.setCanvas()
    love.graphics.clear(G.C.n)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas, offX, offY, 0, zoom, zoom)
    if autoplay and autoplay.done then
        local s = UI.state()
        local N = require "num"
        if s.phase == "lucid" then
            local L = s.lucid
            print(("autoplay, lucid: %ds, %s runs, %.1f runs/s, %s DP, %s dream sheep, flow %s"):format(L.time,
                N.format(L.runs), Lucid.runsPerSecond(L), N.format(L.dp), N.format(L.sheep), tostring(L.flow)))
        else
            print(("autoplay: %ds, counted %s, drowsy %d%%, stage %d"):format(s.runTime, N.format(s.runTotal),
                Game.drowsiness(s) * 100, s.stage))
        end
        print("firsts: " .. table.concat(autoplay.firsts, " "))
        print(("sound: %d sounds and %d of 6 pad layers ready, pad playing: %s"):format(Audio.status()))
        canvas:newImageData():encode("png", "autoplay.png")
        love.event.quit()
    end
end

-- The canvas, for the shots.
function love.getCanvasPicture() return canvas end

--- input: a finger or the mouse, the same --------------------------------------

function love.mousepressed(x, y, b, istouch)
    if istouch or b ~= 1 then return end
    local gx, gy = toGame(x, y)
    UI.pressed(gx, gy, "mouse")
end
function love.mousemoved(x, y, _, _, istouch)
    if istouch then return end
    local gx, gy = toGame(x, y)
    UI.moved(gx, gy, "mouse")
end
function love.mousereleased(x, y, b, istouch)
    if istouch or b ~= 1 then return end
    local gx, gy = toGame(x, y)
    UI.released(gx, gy, "mouse")
end
function love.touchpressed(id, x, y) local gx, gy = toGame(x, y); UI.pressed(gx, gy, id) end
function love.touchmoved(id, x, y) local gx, gy = toGame(x, y); UI.moved(gx, gy, id) end
function love.touchreleased(id, x, y) local gx, gy = toGame(x, y); UI.released(gx, gy, id) end
function love.wheelmoved(_, dy) UI.wheel(dy) end

function love.keypressed(key)
    if key == "f11" or (key == "return" and love.keyboard.isDown("lalt", "ralt")) then
        love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
        fit()
    elseif key == "escape" and not MOBILE then
        love.event.quit()
    elseif key == "l" and dev and UI.state() and UI.state().phase ~= "lucid" then
        jumpToLucid(UI.state())
    else
        UI.key(key)
    end
end

--- out of sight: keep the night as it stands ---------------------------------------

function love.focus(f) if not f and not shots then UI.save() end end
function love.visible(v)
    if shots then return end
    if not v then UI.save() end
    Audio.hide(not v)
end
function love.quit()
    if not shots and UI.state() then UI.save() end
    Audio.stop()
end
