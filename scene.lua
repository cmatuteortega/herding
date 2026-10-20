-- The field: the sky, the hills, the fence and every sheep, drawn into its own
-- low-res canvas. It reads the game's state; what only looks (a sheep
-- mid-hop, a number floating up, the eyelids) lives here in `fx` and never
-- feeds back into the rules.

local G = require "gfx"
local T = require "tracer"
local Models = require "models"
local Game = require "game"
local N = require "num"
local C = require "config"
local lume = require "lib.lume"

local floor, min, max, abs, sin, cos, sqrt = math.floor, math.min, math.max, math.abs, math.sin, math.cos, math.sqrt
local TAU = 2 * math.pi

local Scene = {}

local canvas, cw, ch = nil, 0, 0
local L = {} -- the layout, in field pixels
local bg, bgKey = nil, ""
local stars = {}
local t = 0
local rng = love.math.newRandomGenerator(1) -- the screen's dice, apart from the rules'
local function rand() return rng:random() end
Scene.reduced = false
Scene.cue = function() end -- set by main: a sound for something that happened here

local fx = {
    hoppers = {}, particles = {}, floats = {}, zzz = {}, hearts = {}, smoke = {}, launched = {},
    fenceBounce = 0, shake = 0, autoAcc = 0, zAcc = 0, smokeAcc = 0, heartAcc = 0,
    lids = { blink = 0, next = 6, close = 0 },
    queueBob = 0, flash = 0,
}
Scene.fx = fx

local function seeded(seed)
    local r = love.math.newRandomGenerator(seed)
    return function() return r:random() end
end

--- size and layout -------------------------------------------------------------

function Scene.resize(w, h)
    if w == cw and h == ch and canvas then return end
    cw, ch = w, h
    canvas = love.graphics.newCanvas(cw, ch)
    canvas:setFilter("nearest", "nearest")
    local horizon = floor(ch * 0.55)
    local lane = floor(horizon + (ch - horizon) * 0.55)
    L = {
        horizon = horizon, lane = lane,
        fenceX = floor(cw * 0.5),
        fieldTop = horizon + 3, fieldBot = lane - 9,
        belt = ch - lane >= 20 and lane + 9 or nil,
        queueX = floor(cw * 0.5) - 24,
    }
    local r = seeded(cw * 131 + ch)
    stars = {}
    for _ = 1, floor(cw * horizon / 90) do
        stars[#stars + 1] = { x = floor(r() * cw), y = floor(r() * (horizon - 12)), at = r(), ph = r() * TAU, big = r() < 0.12 }
    end
    table.sort(stars, function(a, b) return a.at < b.at end)
    bgKey = ""
end

function Scene.size() return cw, ch end
function Scene.canvas() return canvas end

--- the backdrop: sky, hills, grass. Painted again only when the night deepens a step.

local SKY = { "b", "l", "i", "p", "v", "n" }
local function hillY(x, stage)
    local y = L.horizon - 5 - 3 * sin(x * 0.045 + 1.3) - 2 * sin(x * 0.11 + 0.4)
    if stage >= 2 then y = y - 2 - 2 * sin(x * 0.02 + 2) end
    return floor(y + 0.5)
end
local function nearHillY(x)
    return floor(L.horizon - 1 - 2.5 * sin(x * 0.07 + 4) - 1.5 * sin(x * 0.19) + 0.5)
end

local function backdrop(d, stage)
    local data = love.image.newImageData(cw, ch)
    local night = min(1, d * 1.1)
    local function dim(x, y, k) return G.dither(x, y, night) and G.DARKER[k] or k end
    for x = 0, cw - 1 do
        local hy, ny = hillY(x, stage), nearHillY(x)
        for y = 0, ch - 1 do
            local k
            if y < hy then
                -- The sky: a step down the ramp from the dusk glow at the
                -- horizon up, the night pushing the whole ramp darker, and
                -- between two steps a dither.
                local v = lume.clamp((1 - y / L.horizon) * 2.1 + d * 3.3, 0, #SKY - 1)
                local lo = floor(v)
                k = SKY[min(#SKY, (G.dither(x, y, v - lo) and lo + 1 or lo) + 1)]
            elseif y < ny and y < L.horizon then
                k = dim(x, y, y == hy and "g" or "t") -- the far hills
                if stage >= 2 and y == hy + 1 and x % 9 == 0 then k = "s" end -- a fence line on the far field
            else
                -- Grass: lighter tufts in a loose pattern, a worn path along the lane.
                local h = bit.bxor((x + 17) * 73856093, (y + 31) * 19349663) % 1000003
                k = "g"
                if y == ny or (h % 41 == 0 and y < L.lane - 4) then k = "m"
                elseif h % 67 == 0 then k = "t" end
                if abs(y - (L.lane + 1)) <= 1 and G.dither(x, y, 0.55) then k = "m" end
                if y > L.lane + 4 and h % 19 == 0 then k = "t" end
                k = dim(x, y, k)
            end
            local c = G.C[k]
            data:setPixel(x, y, c[1], c[2], c[3], 1)
        end
    end
    local img = love.graphics.newImage(data)
    img:setFilter("nearest", "nearest")
    return img
end

--- pieces ------------------------------------------------------------------------

-- A painted body with its pivot (the ground under it) at (x, y).
local function blit(sp, x, y)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(sp.img, floor(x + 0.5) - sp.oi, floor(y + 0.5) - sp.oj)
end

local function px(k, x, y, w, h) G.rect(k, floor(x + 0.5), floor(y + 0.5), w or 1, h or 1) end

local function shadow(x, y, w)
    w = max(3, floor(w + 0.5))
    local pts = {}
    for i = -w, w do
        if G.dither(floor(x + 0.5) + i, y, 0.6) then G.plot(pts, x + i, y) end
    end
    G.points("t", pts)
end

local function look(stage) return stage >= 3 and "pj" or "plain" end

--- what the rules ask for -------------------------------------------------------

local function floatText(text, x, y, k, z, life)
    fx.floats[#fx.floats + 1] = { text = text, x = floor(x), y = y, t = 0, k = k, z = z, life = life }
    return fx.floats[#fx.floats]
end

local function burst(x, y, n, keys, power)
    power = power or 1
    if Scene.reduced then n = math.ceil(n / 3) end
    for i = 1, n do
        local a = rand() * TAU
        local v = (20 + rand() * 40) * power
        fx.particles[#fx.particles + 1] = { x = x, y = y, vx = cos(a) * v, vy = sin(a) * v * 0.7 - 25 * power,
            t = 0, life = 0.5 + rand() * 0.5, k = keys[(i - 1) % #keys + 1] }
    end
end

local function hop(x0, stage, auto)
    if #fx.hoppers >= C.visual.maxHoppers then return end
    local toOrbit = auto and stage >= 4 and rand() < 0.3
    fx.hoppers[#fx.hoppers + 1] = {
        x = x0, phase = "run", ph = 0, z = floor(rand() * 3) - 1,
        h = toOrbit and 200 or 17 + rand() * 6, look = look(stage), orbit = toOrbit, speed = auto and 62 or 90,
    }
end

-- A tap: a sheep from the queue runs and hops the fence, and the number pops.
-- Quick taps pile into one number that keeps growing, rather than a stack of them.
function Scene.tapped(value, s, atx)
    fx.fenceBounce, fx.queueBob = 1, 1
    hop(L.queueX, s.stage, false)
    local last = fx.floats[#fx.floats]
    if last and last.tap and last.t < 0.35 then
        last.value = N.add(last.value, value)
        last.text = "+" .. N.format(last.value)
        last.t, last.pop = 0, 1
        last.x = floor(lume.clamp(last.cx - G.textWidth(last.text, 2) / 2, 2, cw - G.textWidth(last.text, 2) - 2))
        return
    end
    local text = "+" .. N.format(value)
    local cx = (atx or L.fenceX) + rand() * 16 - 8
    local f = floatText(text, lume.clamp(cx - G.textWidth(text, 2) / 2, 2, cw - G.textWidth(text, 2) - 2), L.lane - 40, "w", 2, 0.95)
    f.tap, f.value, f.cx, f.pop = true, value, cx, 1
end

-- Where the golden sheep is, `gs.t` into its crossing: the rules keep only the
-- time, so the tap test and the drawing both ask here.
local function goldenPos(gs)
    local p = gs.t / C.golden.crossTime
    local x = -14 + (cw + 28) * p
    local base = L.horizon - 8 - gs.lane * L.horizon * 0.2
    return x, base - abs(sin(p * math.pi * 7)) * 7
end

function Scene.hitGolden(s, gx, gy)
    if not s.golden then return false end
    local x, y = goldenPos(s.golden)
    return sqrt((gx - x) ^ 2 + ((gy - (y - 6)) * 1.2) ^ 2) < 16
end

function Scene.goldenCaught(value, s, gs)
    local x, y = cw / 2, L.horizon / 2
    if gs then x, y = goldenPos(gs) end
    burst(x, y - 6, 28, { "y", "w", "h", "y" }, 1.4)
    local text = "+" .. N.format(value)
    floatText(text, lume.clamp(x - G.textWidth(text, 3) / 2, 2, cw - G.textWidth(text, 3) - 2), y - 26, "y", 3, 1.8)
    fx.flash = 1
    if not Scene.reduced then fx.shake = 0.35 end
end

-- A puff of wool where the new thing appears.
function Scene.bought(id)
    local where = {
        dog = { L.fenceX, L.fieldBot }, meadow = { cw * 0.3, L.fieldTop + 4 }, pen = { cw * 0.8, L.fieldBot - 2 },
        mill = { 20, L.horizon - 10 }, drones = { cw * 0.5, L.horizon * 0.5 }, os = { cw - 16, L.fieldBot },
        betterFence = { L.fenceX, L.lane - 8 }, tapPower = { L.queueX, L.lane - 6 },
        barn = { cw * 0.85, L.horizon - 4 }, lullaby = { cw / 2, L.horizon * 0.4 },
    }
    local w = where[id] or { cw / 2, L.lane }
    burst(w[1], w[2], 12, { "w", "l", "m" })
    if id == "betterFence" then
        fx.fenceBounce = 1.5
        if not Scene.reduced then fx.shake = 0.15 end
    end
end

-- A new night: nothing left mid-air, the eyes open.
function Scene.reset()
    fx.hoppers, fx.floats, fx.launched, fx.zzz = {}, {}, {}, {}
    fx.lids.close, fx.lids.blink = 0, 0
end

--- each frame ------------------------------------------------------------------

local function keep(list, alive)
    local j = 0
    for i = 1, #list do
        local v = list[i]
        list[i] = nil
        if alive(v) then j = j + 1; list[j] = v end
    end
end

function Scene.update(dt, s)
    t = t + dt
    local d = Game.drowsiness(s)
    fx.fenceBounce = max(0, fx.fenceBounce - dt * 6)
    fx.queueBob = max(0, fx.queueBob - dt * 5)
    fx.shake = max(0, fx.shake - dt)
    fx.flash = max(0, fx.flash - dt * 3)

    -- The helpers (and Sleepwalking) send sheep over too, at a calm pace that
    -- grows with them.
    local rate = N.toNumber(Game.totalPerSecond(s))
    if rate > 0 and not s.asleep then
        fx.autoAcc = fx.autoAcc + dt * min(C.visual.autoHopsPerSecond, 0.35 + math.log10(1 + rate) * 0.3)
        if fx.autoAcc >= 1 then fx.autoAcc = fx.autoAcc - 1; hop(-12, s.stage, true) end
    end

    local from, to = L.fenceX - 12, L.fenceX + 12
    for _, h in ipairs(fx.hoppers) do
        if h.phase == "run" then
            h.x = h.x + h.speed * dt
            if h.x >= from then h.phase, h.ph, h.x = "jump", 0, from end
        elseif h.phase == "jump" then
            h.ph = h.ph + dt / (h.orbit and 1.4 or 0.42)
            h.x = from + (to - from) * min(1, h.ph) * (h.orbit and 0.6 or 1)
            if h.orbit and h.ph >= 0.5 then
                h.done = true
                fx.launched[#fx.launched + 1] = { x = h.x, y = L.lane - h.h * 0.5 }
            elseif h.ph >= 1 then
                h.phase, h.ph, h.x = "land", 0, to
                burst(h.x, L.lane, 4, { "m", "w" })
                Scene.cue("land")
            end
        elseif h.phase == "land" then
            h.ph = h.ph + dt / 0.14
            if h.ph >= 1 then h.phase = "out" end
        else
            h.x = h.x + h.speed * 0.9 * dt
            if h.x > cw + 16 then h.done = true end
        end
    end
    keep(fx.hoppers, function(h) return not h.done end)

    for _, l in ipairs(fx.launched) do l.y, l.x = l.y - dt * 120, l.x + dt * 20 end
    keep(fx.launched, function(l) return l.y > -20 end)

    for _, p in ipairs(fx.particles) do
        p.t = p.t + dt
        p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
        p.vy, p.vx = p.vy + 140 * dt, p.vx * (1 - dt * 2)
    end
    keep(fx.particles, function(p) return p.t < p.life end)

    for _, f in ipairs(fx.floats) do f.t = f.t + dt end
    keep(fx.floats, function(f) return f.t < f.life end)

    -- Zzz from the queue, more of them the sleepier you are.
    if d > 0.3 and not Scene.reduced then
        fx.zAcc = fx.zAcc + dt * (d - 0.25) * 1.4
        if fx.zAcc >= 1 then
            fx.zAcc = 0
            fx.zzz[#fx.zzz + 1] = { x = L.queueX - 10 + rand() * 16, y = L.lane - 14, t = 0,
                z = (d > 0.75 and rand() < 0.4) and 2 or 1, ph = rand() * TAU }
        end
    end
    for _, z in ipairs(fx.zzz) do z.t = z.t + dt end
    keep(fx.zzz, function(z) return z.t < 2.6 end)

    -- Chimney smoke, and hearts over the pen.
    if s.owned.mill > 0 or s.stage >= 3 then
        fx.smokeAcc = fx.smokeAcc + dt * 1.6
        if fx.smokeAcc >= 1 then fx.smokeAcc = 0; fx.smoke[#fx.smoke + 1] = { x = 30, y = L.horizon - 30, t = 0 } end
    end
    for _, sm in ipairs(fx.smoke) do
        sm.t = sm.t + dt
        sm.y, sm.x = sm.y - dt * 6, sm.x + dt * 4 + sin(sm.t * 2) * dt * 2
    end
    keep(fx.smoke, function(sm) return sm.t < 4 end)
    if s.owned.pen > 0 then
        fx.heartAcc = fx.heartAcc + dt * 0.7
        if fx.heartAcc >= 1 then
            fx.heartAcc = 0
            fx.hearts[#fx.hearts + 1] = { x = cw * 0.8 + rand() * 14 - 7, y = L.fieldBot - 10, t = 0 }
        end
    end
    for _, h in ipairs(fx.hearts) do h.t, h.y = h.t + dt, h.y - dt * 7 end
    keep(fx.hearts, function(h) return h.t < 1.8 end)

    -- The eyelids: a droop near the end, blinks more and more often, and shut
    -- for good when you fall asleep.
    local lids = fx.lids
    if s.asleep then lids.close = min(1, lids.close + dt / 2.4)
    else lids.close = max(0, lids.close - dt / 1.2) end
    if d > 0.55 and not s.asleep and not Scene.reduced then
        lids.next = lids.next - dt
        if lids.next <= 0 then
            lids.blink = 1
            lids.next = 2.5 + rand() * (10 - 9 * (d - 0.55) / 0.45)
        end
    end
    lids.blink = max(0, lids.blink - dt / 0.38)
end

--- drawing -----------------------------------------------------------------------

local function drawHeart(x, y, tt)
    local dens = tt > 1.2 and 1 - (tt - 1.2) / 0.6 or 1
    local rows = { ".l.l.", "lllll", ".lll.", "..l.." }
    local pts = {}
    for r, row in ipairs(rows) do
        for c = 1, 5 do
            local xx, yy = floor(x) + c - 3, floor(y) + r - 1
            if row:sub(c, c) == "l" and (dens >= 1 or G.dither(xx, yy, dens)) then G.plot(pts, xx, yy) end
        end
    end
    G.points("l", pts)
end

local function drawSky(s, d)
    -- Stars come out a quarter of the way to sleep, and twinkle.
    local shown = (d - 0.2) / 0.6
    for _, st in ipairs(stars) do
        if st.at > shown then break end
        if st.y < hillY(st.x, s.stage) - 1 then
            local tw = sin(t * 1.3 + st.ph)
            if tw > -0.85 then
                px(tw > 0.6 and "w" or "l", st.x, st.y)
                if st.big and tw > 0.3 then
                    px("l", st.x - 1, st.y); px("l", st.x + 1, st.y); px("l", st.x, st.y - 1); px("l", st.x, st.y + 1)
                end
            end
        end
    end

    -- The moon rises with drowsiness; in Orbit, sheep circle it.
    if d > 0.3 or s.stage >= 4 then
        local rise = lume.clamp((d - 0.3) / 0.5, 0, 1)
        local mx, my = cw - max(16, cw * 0.16), floor(L.horizon - 6 - rise * L.horizon * 0.6)
        local n = s.stage >= 4 and 3 + min(6, s.owned.os + floor(s.owned.drones / 10)) or 0
        local orbit = {}
        for i = 1, n do
            local a = t * 0.45 + i * TAU / n
            orbit[i] = { a = a, x = mx + cos(a) * 18, y = my + sin(a) * 5 - 2 }
        end
        local function one(o) blit(Models.sheep(o.a + math.pi / 2, 0, 2, "pj", false, 0.5), o.x, o.y + 3) end
        for _, o in ipairs(orbit) do if sin(o.a) < 0 then one(o) end end
        blit(Models.moon(9), mx, my)
        for _, o in ipairs(orbit) do if sin(o.a) >= 0 then one(o) end end
    end

    -- The sheep Orbit sends straight up, a spark under each.
    for _, l in ipairs(fx.launched) do
        blit(Models.sheep(-math.pi / 2 + 0.6, -2, 2, "pj"), l.x, l.y)
        if floor(t * 20) % 2 == 1 then px("y", l.x - 1, l.y + 2, 2, 2) end
    end

    -- Drones on patrol, a light blinking on each, and now and then a beam
    -- straight down as one counts.
    local drones = s.owned.drones > 0 and min(5, 1 + floor(s.owned.drones / 8)) or 0
    for i = 0, drones - 1 do
        local ph = i * 2.1
        local x = cw / 2 + sin(t * 0.35 + ph) * cw * 0.38
        local y = L.horizon * 0.62 + sin(t * 0.8 + ph * 1.7) * 6 - i * 3
        local vx = cos(t * 0.35 + ph)
        blit(Models.drone(vx > 0.3 and 1 or (vx < -0.3 and -1 or 0)), x, y)
        if floor(t * 2 + i) % 2 == 0 then px("y", x, y - 2) end
        if sin(t * 0.9 + ph) > 0.85 then
            local pts = {}
            for yy = floor(y + 3), L.horizon - 1 do
                if G.dither(floor(x + 0.5), yy, 0.25) then G.plot(pts, x, yy) end
            end
            G.points("y", pts)
        end
    end

    -- The Wool Mill, behind the hills: a sawtooth roof, lit windows, smoke.
    if s.owned.mill > 0 or s.stage >= 3 then
        local x0, y0 = 6, L.horizon - 18
        G.box(x0, y0, 28, 18, "p")
        for i = 0, 3 do
            for r = 0, 3 do
                px("o", x0 + i * 7 + r, y0 - 1 - r)
                px("i", x0 + i * 7 + r, y0 - r, 1, r)
            end
            px("o", x0 + i * 7 + 4, y0 - 5, 1, 5)
        end
        G.box(x0 + 22, y0 - 13, 4, 13, "s")
        for i = 0, 2 do px(sin(t * 1.5 + i * 2) > -0.6 and "y" or "h", x0 + 3 + i * 8, y0 + 5, 4, 4) end
        for _, sm in ipairs(fx.smoke) do
            G.disc(sm.t < 2 and "w" or "b", sm.x, sm.y, 1 + floor(sm.t * 0.8), max(0.15, 0.8 - sm.t * 0.2))
        end
    end
end

local function drawField(s)
    local things = {}
    local function put(y, f) things[#things + 1] = { y = y, f = f } end
    -- Grazing sheep, more with each Meadow, ambling across.
    local grazers = s.owned.meadow > 0 and min(9, 1 + math.ceil(s.owned.meadow / 3)) or 0
    local r = seeded(77)
    for i = 1, grazers do
        local bx, by = r() * cw, L.fieldTop + 2 + r() * (L.fieldBot - L.fieldTop - 2)
        local dir = r() < 0.5 and 1 or -1
        local x = (bx + dir * t * 1.2 + cw + 20) % (cw + 20) - 10
        local graze = sin(t * 0.7 + i * 1.9) > -0.2
        put(by, function()
            blit(Models.sheep(dir > 0 and 0.3 or math.pi - 0.3, 0, 0, look(s.stage), graze, 0.75), x, by)
        end)
    end
    -- Dogs running loops round the field.
    local dogs = s.owned.dog > 0 and min(3, 1 + floor(s.owned.dog / 15)) or 0
    for i = 0, dogs - 1 do
        local a = t * (0.55 + i * 0.12) + i * 2.2
        local rx, ry = cw * 0.38, (L.fieldBot - L.fieldTop) / 2
        local x, y = L.fenceX + cos(a) * rx, (L.fieldTop + L.fieldBot) / 2 + sin(a) * ry
        local h = math.atan2(cos(a) * ry / T.SE, -sin(a) * rx)
        local gait = floor(t * 12 + i) % 4
        put(y, function() blit(Models.dog(h, gait), x, y) end)
    end
    -- The Breeding Pen: a little fold of bouncing lambs, hearts rising.
    if s.owned.pen > 0 then
        local x0, y0 = floor(cw * 0.8) - 11, L.fieldBot - 3
        local lambs = min(4, 1 + floor(s.owned.pen / 8))
        put(y0, function()
            px("o", x0 - 1, y0 - 7, 24, 1); px("b", x0, y0 - 6, 22, 1)
            for i = 0, lambs - 1 do
                local b = abs(sin(t * 3 + i * 1.3)) * 3
                blit(Models.sheep(i % 2 == 1 and 0.4 or math.pi - 0.4, 0, b > 1.5 and 2 or 0, look(s.stage), false, 0.55),
                    x0 + 4 + i * 5, y0 - 1 - b)
            end
            px("o", x0 - 1, y0 - 2, 24, 1); px("b", x0, y0 - 1, 22, 1)
            for _, xx in ipairs({ x0, x0 + 11, x0 + 22 }) do blit(Models.post(), xx, y0 + 1) end
        end)
        put(1e9, function() for _, h in ipairs(fx.hearts) do drawHeart(h.x, h.y, h.t) end end)
    end
    -- Sheep-OS: a terminal in the grass, counting.
    if s.owned.os > 0 then
        local x0, y0 = cw - 26, L.fieldBot - 14
        put(y0 + 14, function()
            G.box(x0, y0, 20, 14, "s")
            px("n", x0 + 2, y0 + 2, 16, 9)
            for row = 0, 2 do
                local n = floor(t * 6 + row * 3) % 13
                for i = 0, n - 1 do
                    if (i * 7 + row + floor(t * 4)) % 5 ~= 0 then px(row == 2 and "y" or "m", x0 + 3 + i, y0 + 3 + row * 3) end
                end
            end
            px("o", x0 + 8, y0 + 14, 4, 2); px("o", x0 + 5, y0 + 15, 10, 1)
        end)
    end
    table.sort(things, function(a, b) return a.y < b.y end)
    for _, th in ipairs(things) do th.f() end
end

local function drawLane(s)
    local lane = L.lane
    -- The queue: three sheep waiting their turn, dozing as the night goes on.
    for i = 2, 0, -1 do
        local x = L.queueX - i * 14 - 2
        if x > -10 then
            local breathe = sin(t * 1.4 + i) > 0.6 and 1 or 0
            shadow(x, lane + 1, 6)
            local bob = i == 0 and fx.queueBob or 0
            blit(Models.sheep(0.35, bob > 0.5 and 1 or breathe, 0, look(s.stage)), x, lane - floor(bob * 2))
        end
    end
    -- The hoppers, then the fence over them, so they sail over its rails.
    for _, h in ipairs(fx.hoppers) do
        local y, squash, leg = lane + h.z, 0, floor(h.x / 4) % 2
        if h.phase == "jump" then
            local p = min(1, h.ph)
            y = y - sin(p * math.pi) * h.h * (h.orbit and max(1, p * 2) or 1)
            leg = 2
            squash = p < 0.12 and 1 or (p < 0.4 and -2 or (p < 0.7 and -1 or 0))
            shadow(h.x, lane + 1, 6 - sin(p * math.pi) * 3)
        else
            shadow(h.x, lane + 1, 6)
            if h.phase == "land" then squash, leg = h.ph < 0.5 and 3 or 1, 0 end
        end
        if Scene.reduced then squash = 0 end
        blit(Models.sheep(0.35, squash, leg, h.look), h.x, y)
    end
    local fb = fx.fenceBounce
    local sq = Scene.reduced and 0 or (fb > 0.6 and 2 or (fb > 0.2 and 1 or 0))
    blit(Models.fence(s.owned.betterFence, sq), L.fenceX, lane + 3)
end

local function drawBelt(s)
    if not L.belt or s.stage < 3 then return end
    local y = L.belt
    px("o", 0, y - 1, cw, 7)
    px("s", 0, y, cw, 2)
    px("p", 0, y + 2, cw, 3)
    local off = floor(t * 18) % 8
    for x = -8 + off, cw, 8 do px("b", x, y, 3, 1); px("o", x + 3, y + 2, 1, 3) end
    -- Pajama sheep riding it to wherever sheep go.
    local riders = min(7, 2 + floor(s.owned.mill / 4))
    for i = 0, riders - 1 do
        local x = (i * (cw + 24) / riders + t * 18) % (cw + 24) - 12
        blit(Models.sheep(0.1, 0, 0, "pj", false, 0.8), x, y + 1)
    end
end

local function drawGolden(gs)
    local x, y = goldenPos(gs)
    local p = gs.t / C.golden.crossTime
    -- A sparkle trail, then the sheep itself.
    for i = 1, 5 do
        local tx, ty = goldenPos({ t = max(0, gs.t - i * 0.08), lane = gs.lane })
        if (floor(t * 14) + i) % 2 == 1 then px(i < 3 and "y" or "w", tx - 6 + sin(i * 3 + t * 9) * 2, ty - 4 + cos(i * 2) * 2) end
    end
    local air = abs(sin(p * math.pi * 7))
    blit(Models.sheep(0.25, air < 0.15 and 1 or -1, air > 0.15 and 2 or 0, "gold"), x, y)
    if floor(t * 6) % 2 == 1 then px("w", x + 6, y - 15); px("w", x - 8, y - 10) end
end

local function drawOver(s)
    for _, p in ipairs(fx.particles) do px(p.k, p.x, p.y) end
    for _, z in ipairs(fx.zzz) do
        local dens = z.t > 1.8 and 1 - (z.t - 1.8) / 0.8 or 1
        G.label("l", "Z", floor(z.x + sin(z.t * 2 + z.ph) * 3), floor(z.y - z.t * 9), z.z, dens)
    end
    if s.golden then drawGolden(s.golden) end
    for _, f in ipairs(fx.floats) do
        local p = f.t / f.life
        local rise = Scene.reduced and 0 or (1 - (1 - min(1, p * 1.4)) ^ 3) * (f.z > 2 and 18 or 14)
        local dens = p > 0.65 and 1 - (p - 0.65) / 0.35 or 1
        local up = (f.pop and f.t < 0.08 and not Scene.reduced) and 1 or 0
        G.label(f.k, f.text, f.x, floor(f.y - rise) - up, f.z, dens)
    end
    if fx.flash > 0 then
        local pts = {}
        for y = 0, ch - 1 do
            for x = 0, cw - 1 do if G.dither(x, y, fx.flash * 0.25) then G.plot(pts, x, y) end end
        end
        G.points("y", pts)
    end
end

local function drawLids(d)
    local l = fx.lids
    local rest = d > 0.85 and (d - 0.85) / 0.15 * 0.18 or 0
    local blink = l.blink > 0 and sin(l.blink * math.pi) or 0
    local amt = min(1, max(rest, blink * 0.9, l.close))
    if amt <= 0 then return end
    local half = ch / 2 + 2
    local top, bot = floor(half * amt), ch - floor(half * amt)
    G.rect("n", 0, 0, cw, max(0, top - 2))
    G.rect("n", 0, bot + 2, cw, ch)
    local pts = {}
    for y = max(0, top - 2), top + 1 do
        for x = 0, cw - 1 do if G.dither(x, y, 1 - (y - (top - 2)) / 4) then G.plot(pts, x, y) end end
    end
    for y = bot - 2, bot + 1 do
        for x = 0, cw - 1 do if G.dither(x, y, (y - (bot - 2)) / 4) then G.plot(pts, x, y) end end
    end
    G.points("n", pts)
    if amt > 0.6 and amt < 1 then -- lashes, nearly shut
        for x = 6, cw - 1, 7 do px("o", x, top + 1); px("o", x + 1, top + 2) end
    end
end

-- Draws the field into its canvas and returns it.
function Scene.draw(s)
    local d = Game.drowsiness(s)
    local key = ("%d.%d"):format(floor(d * 48 + 0.5), s.stage >= 2 and 1 or 0)
    if key ~= bgKey then bg, bgKey = backdrop(floor(d * 48 + 0.5) / 48, s.stage), key end
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(G.C.n)
    if fx.shake > 0 and not Scene.reduced then
        love.graphics.translate(floor((rand() - 0.5) * 4 * fx.shake + 0.5), floor((rand() - 0.5) * 4 * fx.shake + 0.5))
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(bg, 0, 0)
    drawSky(s, d)
    drawField(s)
    drawLane(s)
    drawBelt(s)
    drawOver(s)
    love.graphics.origin()
    drawLids(d)
    love.graphics.pop()
    return canvas
end

--- shop icons: the same bodies, small -------------------------------------------

local ART = {
    hand = {
        ".y...oo.......", "..y.owwo......", "....owwo......", "yy..owwoooo...",
        "....owwowwooo.", "....owwowwowwo", ".ooooww.wwowwo", "owwowwwwwwwwwo",
        "owwwwwwwwwwwwo", ".owwwwwwwwwwbo", "..owwwwwwwwbo.", "...owwwwwwbo..",
        "....obbbbbo...", ".....ooooo....",
    },
    os = {
        "oooooooooooooooooo", "osssssssssssssssso", "osnnnnnnnnnnnnnnso", "osnmmnmnmmmnnnnnso",
        "osnnnnnnnnnnnnnnso", "osnmmmnmnmmnnnnnso", "osnnnnnnnnnnnnnnso", "osnyynyyynynnnnnso",
        "osnnnnnnnnnnnnnnso", "osssssssssssssssso", "oooooooooooooooooo", ".......oooo.......",
        ".....oooooooo.....",
    },
    barn = {
        "........o........", "......ooiooo.....", "....ooiiiiioo....", "..ooiiiiiiiiioo..",
        ".oiiiiiwwwiiiiio.", "ooooooowwwooooooo", ".opppppppppppppo.", ".opwwwwwwwwwwwpo.",
        ".opwpwpwowpwpwpo.", ".opwwpwwowwpwwpo.", ".opwpwpwowpwpwpo.", ".opwwwwwowwwwwpo.",
        ".opppppppppppppo.", "ooooooooooooooooo",
    },
    lullaby = {
        "...oooo..........", "..owwwo......oo..", ".owwwo.......olo.", ".owwo........olo.",
        "owwwo........ol..", "owwwo........ol..", "owwwwo.....oool..", ".owwwwo...olllo..",
        ".owwwwwooooolo...", "..owwwwwwwo.oo...", "...ooowwoo.......", "......oo.........",
        "..y.......y......", "......y..........",
    },
    heart = { ".l.l.", "lllll", ".lll.", "..l.." },
    eye = {
        "....ooooooo.....", "..oowwwwwwwoo...", ".owwwwoooowwwo..", "owwwwoyyyyowwwo.",
        "owwwwoyooyowwwwo", ".owwwoyyyyowwwo.", "..oowwoooowwoo..", "....ooooooo.....",
    },
    z = { "llll", "..l.", ".l..", "llll" },
    bed = {
        "oo..............", "owo.............", "owo..ooooooooooo", "owoooowwwwlllllo",
        "owowwwolllllilio", "owowwwolilllllio", "owoooooooooooooo", "owpppppppppppppo",
        "oooooooooooooooo", "oo............oo",
    },
    catcher = {
        "....ooooooo....", "..oollllllloo..", ".olo.l.l.l.olo.", ".ol.l.l.l.l.lo.", "ol...l.l.l...lo",
        "ollllllyllllllo", "ol...l.l.l...lo", ".ol.l.l.l.l.lo.", ".olo.l.l.l.olo.", "..oollllllloo..",
        "....ooooooo....", "...o...o...o...", "..owo.owo.owo..", "..owo.owo.owo..", "..obo.obo.obo..",
        "...o...o...o...",
    },
}
Scene.ART = ART

-- The picture on a shop card, drawn with its middle at (x, y): 28 by 22.
function Scene.icon(id, x, y)
    x, y = floor(x - 14), floor(y - 11)
    if id == "tapPower" then G.art(ART.hand, x + 7, y + 4)
    elseif id == "betterFence" then blit(Models.fence(1, 0), x + 14, y + 19)
    elseif id == "dog" then blit(Models.dog(0.4, 1), x + 14, y + 18)
    elseif id == "meadow" then
        blit(Models.sheep(0.35, 0, 0, "plain", true), x + 13, y + 19)
        G.art({ "m.m...m..m", ".g..m..gm." }, x + 8, y + 19)
    elseif id == "pen" then
        blit(Models.sheep(0.4, 0, 0, "plain", false, 0.6), x + 8, y + 18)
        blit(Models.sheep(math.pi - 0.4, 0, 0, "plain", false, 0.6), x + 20, y + 18)
        G.art(ART.heart, x + 12, y + 2)
    elseif id == "mill" then blit(Models.sheep(0.35, 0, 0, "pj"), x + 13, y + 19)
    elseif id == "drones" then blit(Models.drone(0), x + 14, y + 11); px("y", x + 14, y + 7)
    elseif id == "os" then G.art(ART.os, x + 5, y + 4)
    elseif id == "barn" then G.art(ART.barn, x + 6, y + 4)
    elseif id == "lullaby" then G.art(ART.lullaby, x + 6, y + 4)
    -- The Dream shop.
    elseif id == "sleepwalk" then
        blit(Models.sheep(0.35, 0, 1, "pj"), x + 13, y + 19)
        G.art(ART.z, x + 21, y + 2)
    elseif id == "nightShift" then
        blit(Models.dog(0.4, 1), x + 14, y + 18)
        G.art({ "..yy", ".y..", ".y..", "..yy" }, x + 3, y + 2)
    elseif id == "goldenDreams" then blit(Models.sheep(0.35, 0, 0, "gold"), x + 13, y + 19)
    elseif id == "sleepTalk" then
        G.art(ART.hand, x + 7, y + 4)
        G.art(ART.z, x + 22, y + 2)
    elseif id == "tuckedIn" then
        G.art(ART.barn, x + 6, y + 4)
        G.art(ART.z, x + 22, y + 1)
    elseif id == "deepSleep" then blit(Models.moon(8), x + 14, y + 11)
    elseif id == "dreamCatcher" then G.art(ART.catcher, x + 7, y + 3)
    elseif id == "warmBed" then
        G.art(ART.bed, x + 6, y + 9)
        G.art(ART.z, x + 20, y + 2)
    -- The ways of sleeping: a hand that wakes for the gold, a bed that doesn't.
    elseif id == "lightSleeper" then
        G.art(ART.hand, x + 7, y + 4)
        G.art({ ".y.", "yyy", ".y." }, x + 21, y + 2)
    elseif id == "heavySleeper" then
        G.art(ART.bed, x + 6, y + 10)
        G.art(ART.z, x + 13, y + 3)
        G.art(ART.z, x + 20, y + 1)
    -- Restless nights.
    elseif id == "insomnia" then G.art(ART.eye, x + 6, y + 7)
    elseif id == "shortage" then
        blit(Models.sheep(0.35, 0, 0, "plain", false, 0.75), x + 12, y + 19)
        G.art({ "..y..", ".yyy.", "y.y.y", "..y..", "..y.." }, x + 21, y + 2)
    elseif id == "wideAwake" then
        blit(Models.sheep(0.35, 0, 1, "pj"), x + 13, y + 19)
        G.art({ "yy", "yy", "yy", "..", "yy" }, x + 22, y + 2)
    elseif id == "coldFeet" then
        G.art(ART.barn, x + 6, y + 6)
        G.art({ "w...w", ".....", "..w..", "w...." }, x + 3, y + 1)
        G.art({ "....w", "w....", "...w." }, x + 19, y + 2)
    end
end

return Scene
