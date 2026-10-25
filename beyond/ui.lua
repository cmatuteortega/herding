-- Phase 4, beyond: past the cut cord, the page turned over. Every phase before
-- was the dark (dusk, the night, the dream, the planes); this is the light, a
-- simple screen in the clear colours (cream, mint, grass), and in it WE are
-- the sheep. The point of view is a sheep's: we look up the lane at the backs of
-- the sheep queued ahead of us, and at the fence at the end of the line. Each in
-- turn the front sheep hops the fence and is counted, and the line shuffles up.
-- When the fence is right in front of us, it's our turn.
--
-- One action: JUMP (the button, or space). Jump with the fence in front of
-- you and you clear it, and are counted, and blink to the back of a new line.
-- Jump without it, and the sheep ahead turns round: BAD SHEEP.
--
-- The reset button, top right, starts everything over from the first night:
-- tap it, then tap it again while it asks. The phase button (dev) beside it
-- goes round to phase 1.
--
-- ui.lua hands everything over to this once `phase` is "beyond".

local G = require "gfx"
local C = require "config"
local Models = require "models"
local Audio = require "audio"

local floor, sin, sqrt, min, max, pi = math.floor, math.sin, math.sqrt, math.min, math.max, math.pi
local B = C.beyond

local BUI = {}
BUI.save = function() end -- set by ui.lua
BUI.back = function() end -- set by ui.lua: back to the stars (no button for it now)
BUI.resetAll = function() end -- set by ui.lua: wipe the save, a new game
BUI.nextPhase = function() end -- set by ui.lua (dev): round to phase 1

local S
local vw, vh = 320, 240
local t = 0 -- the clock
local reduced = false
local button, reset, phase
local scene = { h = 200, hor = 76, k = 124 } -- the view: its height, the horizon, horizon to our feet
local sizeK = 3 -- a sheep's size at our feet; it shrinks off up the lane
local confirm = 0 -- until when the reset button waits for its second tap
local RESET_ART = { "..ooo.o", ".o...oo", "o...ooo", "o......", "o.....o", ".o...o.", "..ooo.." }

-- The line. `pos` sheep are ahead of us; the fence stands `fz` sheep-lengths up
-- the lane (it eases down to pos + 1 as the line shuffles up). Distances are
-- in sheep-lengths from us, drawn in perspective.
local pos, fz = B.queueMin, B.queueMin + 1
local tNext = 0 -- until the front sheep hops
local hopper = nil -- { t }: the sheep at the front, over the fence
local walkers = {} -- { z }: the ones already counted, trotting off
local jump = nil -- { t, d, adv, good, landed }: us, in the air
local blink = nil -- { t, swapped }: the eyelids, between one line and the next
local flash = 0 -- until when BAD SHEEP is up
local glare = 0 -- until when the sheep ahead is looking round at us
local floats = {} -- { text, x, y, t }: a number rising
local scroll = 0 -- how far the ground has gone by
local down = 0 -- the button, just pressed

function BUI.setState(s)
    S = s
    s.beyond = s.beyond or {}
    local b = s.beyond
    b.count, b.mine, b.bad = b.count or 0, b.mine or 0, b.bad or 0
end
function BUI.setReduced(v) reduced = v end

function BUI.fit(w, h, inset)
    vw, vh = w, h
    local bw = min(vw - 40, 130)
    button = { x = floor(vw / 2 - bw / 2), y = vh - inset.b - 24, w = bw, h = 18 }
    reset = { x = vw - inset.r - 3 - 17, y = inset.t + 2, w = 17, h = 13 }
    phase = { x = reset.x - 20, y = reset.y, w = 17, h = 13 }
    scene.h = button.y - 8
    scene.hor = floor(scene.h * 0.38)
    scene.k = scene.h - scene.hor
    sizeK = max(1.6, min(vw / 30, scene.h / 38))
end

-- How many sheep are in the next line: it varies, the same way each time.
local function newLine(n)
    return B.queueMin + n % (B.queueMax - B.queueMin + 1)
end

-- Coming in: the back of a line.
function BUI.enter()
    confirm = 0
    pos = newLine(S.beyond.mine)
    fz, tNext = pos + 1, B.firstHop
    hopper, jump, blink, flash, glare, down = nil, nil, nil, 0, 0, 0
    walkers, floats, scroll = {}, {}, 0
    Audio.setAstral(false)
    Audio.setBeyond(true)
end

local function inside(r, x, y) return r and x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h end

local function say(text, x, y)
    floats[#floats + 1] = { text = text, x = x, y = y, t = 0 }
end

-- The one action. With the fence in front of us we clear it; without, we're a
-- bad sheep.
function BUI.jump()
    if jump or blink or hopper then return false end
    local good = pos == 0 and fz <= B.reach
    jump = { t = 0, good = good, d = good and B.jumpTime or B.badJumpTime, adv = good and fz + 0.9 or B.badAdv }
    Audio.cue("boing")
    return true
end

function BUI.pressed(x, y)
    Audio.start()
    if inside(button, x, y) then
        down = 0.15
        BUI.jump()
    elseif inside(reset, x, y) then
        Audio.cue("click")
        if confirm > t then
            confirm = 0
            Audio.setBeyond(false)
            BUI.resetAll()
        else
            confirm = t + 3
        end
    elseif inside(phase, x, y) then
        Audio.cue("click")
        Audio.setBeyond(false)
        BUI.nextPhase()
    end
end
function BUI.moved() end
function BUI.released() end
function BUI.wheel() end

function BUI.key(key)
    if key == "m" then
        S.muted = not S.muted
        Audio.setMuted(S.muted)
        BUI.save()
    elseif key == "space" or key == "return" then
        Audio.start()
        down = 0.15
        BUI.jump()
    end
end

-- A good jump landed: counted, and an eyelid's blink to the back of a new line.
local function counted()
    local b = S.beyond
    b.count, b.mine = b.count + 1, b.mine + 1
    say("COUNTED! " .. b.mine, vw / 2, scene.hor + scene.k * 0.5)
    Audio.cue("land")
    Audio.cue("star")
    blink = { t = 0, swapped = false }
    BUI.save()
end

function BUI.update(dt)
    t = t + dt
    down = max(0, down - dt)
    -- The ground goes by as the fence comes up.
    if fz > pos + 1 then
        local d = min(fz - (pos + 1), dt * B.walkSpeed)
        fz, scroll = fz - d, scroll + d
    end
    -- Us, in the air.
    if jump then
        jump.t = jump.t + dt
        if jump.t >= jump.d and not jump.landed then
            jump.landed = true
            if jump.good then
                counted()
            else
                S.beyond.bad = S.beyond.bad + 1
                flash, glare = t + B.badFlash, t + B.glare
                Audio.cue("land")
                Audio.cue("nope")
                Audio.cue("bleat")
                BUI.save()
            end
        end
        if jump.landed and not jump.good then jump = nil end
    end
    -- The eyelids: shut, a new line, open.
    if blink then
        blink.t = blink.t + dt
        if blink.t >= B.blinkTime / 2 and not blink.swapped then
            blink.swapped = true
            jump = nil
            pos = newLine(S.beyond.mine)
            fz, tNext = pos + 1, B.firstHop
            hopper, walkers = nil, {}
        end
        if blink.t >= B.blinkTime then blink = nil end
    end
    -- The front sheep hops the fence, and is counted.
    if hopper then
        hopper.t = hopper.t + dt
        if hopper.t >= B.hopTime then
            walkers[#walkers + 1] = { z = pos + 2 }
            hopper = nil
            pos = pos - 1
            S.beyond.count = S.beyond.count + 1
            say(tostring(S.beyond.count), vw / 2 + (pos % 2 == 0 and 16 or -16), scene.hor + scene.k * 0.2)
            Audio.cue("land")
            tNext = B.hopEvery
        end
    elseif pos > 0 and not jump and not blink then
        tNext = tNext - dt
        if tNext <= 0 and fz <= pos + 1.05 then hopper = { t = 0 } end
    end
    for i = #walkers, 1, -1 do
        walkers[i].z = walkers[i].z + dt * B.trot
        if walkers[i].z > 14 then table.remove(walkers, i) end
    end
    for i = #floats, 1, -1 do
        floats[i].t = floats[i].t + dt
        if floats[i].t > 1.4 then table.remove(floats, i) end
    end
end

--- drawing ---------------------------------------------------------------------

-- A distance as a scale: 1 at our feet, smaller up the lane.
local function wOf(z) return 1 / (1 + 0.55 * z) end

local function ellipse(k, cx, cy, rx, ry)
    rx, ry = max(1, floor(rx + 0.5)), max(1, floor(ry + 0.5))
    for dy = -ry, ry do
        local hw = floor(rx * sqrt(max(0, 1 - (dy / ry) ^ 2)) + 0.5)
        G.rect(k, cx - hw, cy + dy, hw * 2 + 1, 1)
    end
end

local function blit(sp, x, y)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(sp.img, floor(x + 0.5) - sp.oi, floor(y + 0.5) - sp.oj)
end

-- Sizes in steps, so the few poses are painted once and kept.
local function stepSize(s) return max(0.4, floor(s / 0.2 + 0.5) * 0.2) end

local function sky()
    local hor = scene.hor
    G.rect("c", 0, 0, vw, hor + 1)
    -- Haze toward the horizon.
    local pts = {}
    local band = min(hor, 46)
    for y = hor - band, hor do
        local d = (y - (hor - band)) / band
        for x = 0, vw - 1 do
            if G.dither(x, y, d * 0.9) then G.plot(pts, x, y) end
        end
    end
    G.points("w", pts)
    -- The sun, and clouds drifting.
    G.disc("y", floor(vw * 0.78), floor(hor * 0.38), max(5, floor(sizeK * 3)))
    local drift = reduced and 0 or t * 2
    for i, c in ipairs({ { 0.2, 0.3 }, { 0.55, 0.18 }, { 0.9, 0.5 } }) do
        local x = floor((c[1] * vw + drift * (0.6 + i * 0.2)) % (vw + 60) - 30)
        local y, r = floor(hor * c[2]), 4 + i
        G.disc("w", x, y, r)
        G.disc("w", x + r, y + 1, r - 1)
        G.disc("w", x - r, y + 2, r - 2)
    end
    -- Far hills.
    for x = 0, vw - 1, 2 do
        local hh = 5 + floor(4 * sin(x * 0.035) + 3 * sin(x * 0.09 + 1))
        G.rect("g", x, hor - hh, 2, hh + 1)
    end
end

local function ground(adv, camH)
    local hor, k = scene.hor, scene.k
    G.rect("m", 0, hor + 1, vw, scene.h - hor)
    -- The lane, a worn path widening toward us.
    local cx = vw / 2
    for y = hor + 1, scene.h - 1 do
        local hw = floor(vw * (0.05 + 0.30 * (y - hor) / (k + camH)))
        G.rect("w", cx - hw, y, hw * 2, 1)
    end
    -- Tufts, going by as the line moves up.
    local light, dark = {}, {}
    for i = 0, 47 do
        local z = (i * 0.37 - scroll - adv) % 17.6 - 0.8
        local w = wOf(z)
        local y = floor(hor + (k + camH) * w)
        if y > hor + 1 and y < scene.h - 1 then
            local hx = ((i * 7919) % 1000) / 1000
            local x = floor(cx + (hx - 0.5) * vw * (0.4 + 1.6 * w))
            for j = 0, max(1, floor(3 * sizeK * w)) - 1 do G.plot(i % 3 == 0 and dark or light, x, y - j) end
        end
    end
    G.points("g", dark)
    G.points("g", light)
end

local function fence(z, camH)
    local w = wOf(z)
    local y = floor(scene.hor + (scene.k + camH) * w)
    local x = floor(vw / 2)
    local sk = sizeK * w
    local fw, fh = max(8, floor(24 * sk)), max(5, floor(14 * sk))
    local pw = max(2, floor(2.2 * sk))
    ellipse("t", x, y, fw * 0.6, fh * 0.1)
    local rail = max(1, floor(1.8 * sk))
    G.box(x - floor(fw / 2), y - floor(fh * 0.78), fw, rail, "w", "o")
    G.box(x - floor(fw / 2), y - floor(fh * 0.38), fw, rail, "w", "o")
    for _, sx in ipairs({ -1, 1 }) do
        local px = x + sx * floor(fw / 2) - floor(pw / 2)
        G.box(px, y - fh, pw, fh, "w", "o")
        G.rect("b", px + pw - 1, y - fh, 1, fh)
    end
end

-- A sheep seen from behind (or, for a moment, from the front: it has turned
-- round to look at us).
local function sheep(z, camH, lift, squash, leg, round)
    local w = wOf(z)
    local x = floor(vw / 2)
    local y = scene.hor + (scene.k + camH) * w
    local sz = stepSize(sizeK * w)
    ellipse("t", x, floor(y), 6 * sz, sz * 1.8)
    blit(Models.sheep(round and pi / 2 or -pi / 2, squash, leg, "plain", false, sz), x, y - lift * sz)
end

-- Our own forefeet at the bottom edge.
local function hooves(camH)
    local y = scene.h - 3 + camH * 1.4
    local bob = (not reduced and fz > pos + 1.02) and floor(sin(t * 11) + 1) or 0
    for i, sx in ipairs({ -1, 1 }) do
        local x = floor(vw / 2 + sx * min(vw * 0.16, 26))
        local yy = y - (i == 1 and bob or 1 - bob)
        if yy < scene.h + 8 then
            G.box(x - 5, yy - 9, 10, 10, "p", "o")
            G.rect("s", x - 3, yy - 8, 3, 2)
        end
    end
end

-- The blink between one line and the next.
local function eyelids()
    if not blink then return end
    local c = sin(min(1, blink.t / B.blinkTime) * pi) -- 0 open, 1 shut
    local lid = floor(scene.h / 2 * min(1, c * 1.15) + 0.5)
    if lid <= 0 then return end
    G.rect("w", 0, 0, vw, lid)
    G.rect("b", 0, lid - 1, vw, 1)
    G.rect("w", 0, scene.h - lid, vw, lid)
    G.rect("b", 0, scene.h - lid, vw, 1)
end

function BUI.draw()
    -- Up in the air (a jump's arc): the camera rises, and what's near drops away.
    local camH, adv = 0, 0
    if jump then
        local u = min(1, jump.t / jump.d)
        camH = 4 * u * (1 - u) * scene.k * (jump.good and B.jumpHigh or B.badHigh)
        adv = jump.adv * u
    end
    sky()
    ground(adv, camH)

    -- Everything on the lane, far to near.
    local items = {}
    items[#items + 1] = { z = fz - adv, f = function(z) fence(z, camH) end }
    for k = 1, pos do
        local round = glare > t and k == 1
        items[#items + 1] = { z = k - adv, f = function(z)
            local breathe = (not reduced and sin(t * 1.8 + k * 2.1) > 0.7) and 1 or 0
            sheep(z, camH, 0, breathe, 0, round)
        end }
    end
    if hopper then
        local u = min(1, hopper.t / B.hopTime)
        items[#items + 1] = { z = pos + 2 * u - adv, f = function(z)
            local ends = u < 0.15 or u > 0.85
            sheep(z, camH, sin(u * pi) * 11, ends and 2 or -2, ends and 1 or 2)
        end }
    end
    for _, wk in ipairs(walkers) do
        items[#items + 1] = { z = wk.z - adv, f = function(z) sheep(z, camH, 0, 0, floor(wk.z * 2) % 2) end }
    end
    table.sort(items, function(a, b) return a.z > b.z end)
    for _, it in ipairs(items) do
        if it.z > -1.3 then it.f(it.z) end
    end

    hooves(camH)
    eyelids()

    -- The counting, top left.
    local b = S.beyond
    G.label("w", "COUNTED " .. b.count, 6, 5)
    G.label("w", "YOU " .. b.mine, 6, 13)
    if b.bad > 0 then G.label("r", "BAD " .. b.bad, 6, 21) end

    -- Where we stand in the line.
    if not jump and not blink and flash <= t then
        local turn = pos == 0 and fz <= B.reach
        local text = turn and "YOUR TURN!" or (pos == 0 and "ALMOST..." or (pos .. " AHEAD"))
        if not turn or reduced or floor(t * 3) % 2 == 0 then
            G.label(turn and "y" or "w", text, floor(vw / 2 - G.textWidth(text) / 2), scene.h - 30)
        end
    end

    -- BAD SHEEP.
    if flash > t then
        local bob = reduced and 0 or floor(sin(t * 14) * 1.5)
        local s1, s2 = "BAD SHEEP!", "WAIT YOUR TURN"
        local bw = G.textWidth(s1, 2) + 16
        local bx, by = floor(vw / 2 - bw / 2), floor(scene.hor + scene.k * 0.25) + bob
        G.box(bx, by, bw, 32, "r", "o")
        G.text("o", s1, floor(vw / 2 - G.textWidth(s1, 2) / 2), by + 5, 2)
        G.text("p", s2, floor(vw / 2 - G.textWidth(s2) / 2), by + 21)
    end

    -- Numbers rising.
    for _, f in ipairs(floats) do
        G.label("o", f.text, floor(f.x - G.textWidth(f.text) / 2), floor(f.y - f.t * 14), 1, f.t > 1 and (1.4 - f.t) / 0.4 or 1, "w")
    end

    -- The bar under the view, and its one button.
    G.rect("o", 0, scene.h, vw, 1)
    G.rect("w", 0, scene.h + 1, vw, vh - scene.h)
    local bt = button
    local ready = pos == 0 and fz <= B.reach and not jump
    local lift = down > 0 and 1 or 0
    local fill = ready and ((reduced or floor(t * 4) % 2 == 0) and "y" or "h") or "m"
    G.box(bt.x, bt.y + lift, bt.w, bt.h, fill, "o")
    G.rect("w", bt.x + 1, bt.y + lift + 1, bt.w - 2, 1)
    local s = "JUMP"
    G.text("o", s, floor(bt.x + bt.w / 2 - G.textWidth(s, 2) / 2), bt.y + lift + 4, 2)

    -- The reset button: an arrow coming round, and its question while it waits.
    G.box(reset.x + 1, reset.y + 1, reset.w - 2, reset.h - 2, "w", confirm > t and "h" or "s")
    G.art(RESET_ART, reset.x + 5, reset.y + 3)
    -- The phase button (dev): round to phase 1, a new game.
    G.box(phase.x + 1, phase.y + 1, phase.w - 2, phase.h - 2, "w", "s")
    G.text("o", "4>1", phase.x + 3, phase.y + 4)
    if confirm > t then
        local q = "TAP AGAIN TO RESET ALL"
        G.label("h", q, floor(max(4, reset.x + reset.w - G.textWidth(q))), reset.y + reset.h + 3)
    end
    if S and S.muted then G.label("w", "MUTED", 6, scene.h - 12) end
end

return BUI
