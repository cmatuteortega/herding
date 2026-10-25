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
--   love . --astral     dev: straight into phase 3, astral projection, through the gate
--   love . --beyond     dev: straight into phase 4 (you are a sheep in the line), past the cut cord
--                       (--astral --autoplay N: a scripted player in phase 3)

local G = require "gfx"
local Game = require "game"
local Lucid = require "lucid.game"
local Astral = require "astral.game"
local Beyond = require "beyond.game"
local Bot = require "beyond.bot"
local C = require "config"
local UI = require "ui"
local Scene = require "scene"
local Audio = require "audio"
local flux = require "lib.flux"
local N = require "num"

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
local function bringPoints(s)
    s.dreams = math.max(s.dreams, 19)
    s.dreamEarned = math.max(s.dreamEarned, 7000)
    s.dreamPoints = math.max(s.dreamPoints, 750)
end

local function jumpToLucid(s)
    bringPoints(s)
    s.phase, s.asleep = "lucid", false
    s.lucid = Lucid.fresh(s)
    s.dreamPoints = 0
    UI.setState(s)
    require("lucid.ui").enter()
end

-- The reset button (in every phase's top bar): everything gone, saved over,
-- and a new game from the first night, from scratch (the sound and motion
-- settings stay as they were).
local function resetAll(title, line)
    local old = UI.state()
    local s = Game.fresh()
    s.muted, s.reducedMotion = old.muted, old.reducedMotion
    Game.events, Lucid.events = {}, {}
    Audio.setLucid(false)
    Audio.setAstral(false)
    Audio.setBeyond(false)
    Audio.setAsleep(false)
    Audio.setLullabies(s.owned.lullaby)
    UI.setState(s)
    UI.newNight()
    UI.save()
    UI.banner(title or "A NEW GAME", line or "EVERYTHING WAS RESET")
    UI.intro()
end

-- Dev: phase 3 now, through the gate, after a dream played the way a usual
-- player plays it (to the gate).
local function readyAstral(s)
    local L = s.lucid
    L.intro, L.gate = false, true
    L.sheepTotal, L.runs, L.best = N.max(L.sheepTotal, N.from(1e90)), N.max(L.runs, N.from(2e6)), math.max(L.best, 900)
    for _, c in ipairs(C.dream.challenges) do L.done[c.id] = true end
    s.allTime = N.max(s.allTime, N.from(3e14))
end

local function jumpToAstral(s)
    readyAstral(s)
    Game.goAstral(s)
    UI.setState(s)
    UI.showAstral()
end

-- Dev: phase 4 now, the Sleeper lit and the cord cut.
local function readyBeyond(s)
    local P = s.astral
    for _, c in ipairs(Astral.CONSTELLATIONS) do P.lit[c.id] = #c.stars end
    P.intro, P.out, P.cut, P.paid = false, false, true, true
end

local function jumpToBeyond(s)
    readyBeyond(s)
    Game.goBeyond(s)
    UI.setState(s)
    UI.showBeyond()
end

-- Dev: the phase button beside reset, for testing. Each phase plays its own
-- ending first, and the next one starts when that is over: phase 1 falls
-- asleep, a lucid night (its card, then the dream), 2 goes through the gate
-- (Sheep-OS), 3 cuts the cord (the count, the light), and 4 goes back to a
-- new game at the first night.
local function nextPhase()
    local s = UI.state()
    Game.events, Lucid.events, Astral.events = {}, {}, {}
    if s.phase == "nights" then
        if s.asleep then return end
        bringPoints(s)
        Game.fallAsleep(s, true)
    elseif s.phase == "lucid" then
        readyAstral(s)
        require("lucid.ui").leave()
    elseif s.phase == "astral" then
        readyBeyond(s)
        require("astral.ui").leave()
    else
        resetAll("PHASE 1", "DEV: A NEW GAME")
    end
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
    local fresh, toLucid, toAstral, toBeyond = false, false, false, false
    for k, a in ipairs(args or {}) do
        if a == "--speed" then speed = max(1, min(1000, tonumber(args[k + 1]) or 1)); dev = true end
        if a == "--fresh" then fresh = true; dev = true end
        if a == "--lucid" then toLucid, fresh, dev = true, true, true end
        if a == "--astral" then toLucid, toAstral, fresh, dev = true, true, true, true end
        if a == "--beyond" then toLucid, toAstral, toBeyond, fresh, dev = true, true, true, true, true end
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
    UI.resetAll = resetAll
    UI.nextPhase = nextPhase
    if shots then
        require("shots").run(UI, fit)
        return
    end
    if autoplay then fresh, UI.noSave, dev = true, true, true end
    local s = not fresh and UI.load() or nil
    local firstTime = s == nil
    UI.setState(s or Game.fresh())
    s = UI.state()
    Audio.setMuted(s.muted)
    Audio.setLullabies(s.owned.lullaby)
    if toLucid then
        jumpToLucid(s)
        if toAstral then jumpToAstral(s) end
        if toBeyond then jumpToBeyond(s) end
    elseif s.phase == "beyond" then
        UI.showBeyond()
    elseif s.phase == "astral" then
        UI.showAstral()
        UI.away(os.difftime(os.time(), s.lastSeen))
    elseif s.phase == "lucid" then
        UI.showLucid()
        UI.away(os.difftime(os.time(), s.lastSeen))
    elseif s.asleep then
        Scene.fx.lids.close = 1
        Audio.setAsleep(true)
        UI.showEnding()
    else
        UI.away(os.difftime(os.time(), s.lastSeen))
        if firstTime and not autoplay then UI.intro() end
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
        if s.phase == "lucid" and s.lucid then Lucid.step(s.lucid, STEP)
        elseif s.phase == "astral" and s.astral then Astral.step(s.astral, STEP)
        elseif s.phase == "beyond" and s.beyond then Beyond.step(s.beyond, STEP)
        elseif s.phase == "nights" then Game.step(s, STEP) end
        acc, n = acc - STEP, n + 1
    end
    if n >= 4000 then acc = 0 end
    if autoplay and s.phase == "astral" then
        -- Phase 3: through the word on the way in; out whenever it can, back
        -- at 80% until the Silver Thread, a breath (a tap on the dark) on
        -- every tug; the comet caught, for its Ether; every star it can
        -- light, the cheapest upgrade, the cheapest dreamer; and every ten
        -- seconds the next tab, to see them all.
        local P = s.astral
        if P.intro then UI.key("return") end
        if P.comet and P.comet.t > 1 then Astral.catchComet(P) end
        if P.choosing then Astral.choose(P, "ether") end
        if P.out and not Astral.threaded(P) and Astral.strain(P) >= 0.8 then Astral.reelIn(P) end
        if not P.out and P.rest <= 0 and not Astral.tranced(P) then Astral.project(P) end
        if P.out and P.tugLeft > 0 then
            local r = UI.sceneRect()
            UI.pressed(r.x + r.w * 0.6, r.y + r.h * 0.8, "auto")
            UI.released(r.x + r.w * 0.6, r.y + r.h * 0.8, "auto")
        end
        for _, c in ipairs(Astral.CONSTELLATIONS) do
            if Astral.light(P, c.id) then autoplay.firsts[#autoplay.firsts + 1] = ("%s%d@%ds"):format(c.id, Astral.lit(P, c.id), P.time) end
        end
        local ub, up
        for _, u in ipairs(Astral.UPS) do
            if Astral.upState(P, u.id) == "open" and (not up or Astral.upPrice(P, u.id) < up) then ub, up = u.id, Astral.upPrice(P, u.id) end
        end
        if ub and Astral.grow(P, ub) and Astral.rank(P, ub) == 1 then autoplay.firsts[#autoplay.firsts + 1] = ("%s@%ds"):format(ub, P.time) end
        for k = #Astral.DREAMERS, 1, -1 do Astral.buyDreamer(P, k, 1) end
        Astral.cutCord(P)
        local tabFor = math.floor(P.time / 10) % 4 + 1
        if tabFor ~= autoplay.tab then autoplay.tab = tabFor; UI.key(tostring(tabFor)) end
        if P.time >= autoplay.left then autoplay.done = true end
    elseif autoplay and s.phase == "beyond" then
        -- Phase 4: through the dialogs, then a simple player (beyond/bot.lua) twice a
        -- second: it whispers, jumps to calm the Dogs, pairs the best two, buys the
        -- cheapest splice or motion, descends, and votes once awake. Every ten
        -- seconds the next tab, to see them all. Done when the fence is down.
        local b = s.beyond
        if require("beyond.ui").dialog() then UI.key("return") end
        autoplay.botT = (autoplay.botT or 0) + dt * speed
        while autoplay.botT >= 0.5 do
            autoplay.botT = autoplay.botT - 0.5
            local did = Bot.act(b, 0.5, nil, { tap = 1.5 })
            if did.grow and Beyond.rank(b, did.grow) == 1 then autoplay.firsts[#autoplay.firsts + 1] = ("%s@%ds"):format(did.grow, b.time) end
            if did.descend then autoplay.firsts[#autoplay.firsts + 1] = ("gen%d@%ds"):format(b.gen, b.time) end
        end
        local tabFor = math.floor(b.time / 10) % 3 + 1
        if tabFor ~= autoplay.tab then autoplay.tab = tabFor; UI.key(tostring(tabFor)) end
        if b.escaped or b.time >= autoplay.left then autoplay.done = true end
    elseif autoplay and s.phase == "lucid" then
        -- Phase 2: catch the golden sheep (take the frenzy), buy layers top
        -- down, build the first thing it can on the first free plot, grow the
        -- first upgrade it can, count every flock that comes to the fence,
        -- and every minute hold the field for twenty seconds, steering the
        -- bouncing sheep from cloud to cloud.
        local L = s.lucid
        UI.key("return") -- the word on the way in, or a golden gift: the first button
        local r = UI.sceneRect()
        if not L.nightmare and L.time % 60 < 20 then
            local x = r.x + require("lucid.bounce").bot(L.bounce) * r.w / C.dream.bounce.w
            if not autoplay.held then UI.pressed(x, r.y + r.h * 0.7, "climb"); autoplay.held = true
            else UI.moved(x, r.y + r.h * 0.7, "climb") end
        elseif autoplay.held then
            UI.released(r.x, r.y, "climb"); autoplay.held = false
        end
        for _, root in ipairs(Lucid.ROOTS) do
            if Lucid.grow(L, root.id) then autoplay.firsts[#autoplay.firsts + 1] = ("%s@%ds"):format(root.id, L.time) end
        end
        -- Counting sheep: start every flock, tap on every top.
        if L.flock and L.flock.t > 2 then Lucid.startSong(L) end
        if L.song then require("lucid.count").bot(L.song, 0) end
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
        if s.phase == "beyond" then
            local b = s.beyond
            print(("autoplay, beyond: %ds, wits %s (%s/s), count %s, followers %s, gen %d, flock %d, culled %d, rung %s, escaped %s"):format(b.time,
                N.format(b.wits), N.format(Beyond.witRate(b)), N.format(b.count), N.format(b.followers), b.gen, Beyond.flock(b), b.culled,
                C.beyond.rungs[Beyond.rungOf(b)].name, tostring(b.escaped)))
        elseif s.phase == "astral" then
            local P = s.astral
            local lit, all = Astral.litCount(P)
            print(("autoplay, astral: %ds, %s Ether, cord %s, reach %s, %d out, %d snapped, lit %d/%d, phase %s"):format(P.time,
                N.format(P.ether), N.format(Astral.cord(P)), N.format(P.reach), P.projections, P.snaps, lit, all, s.phase))
        elseif s.phase == "lucid" then
            local L = s.lucid
            print(("autoplay, lucid: %ds, %s runs, %.1f runs/s, %s DP, %s dream sheep, flow %s, best height %d"):format(L.time,
                N.format(L.runs), Lucid.runsPerSecond(L), N.format(L.dp), N.format(L.sheep), tostring(L.flow), L.best))
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
    elseif key == "l" and dev and UI.state() and UI.state().phase == "nights" then
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
