-- Phase 4, beyond: past the cut cord, the page turned over (laid out like the
-- phases before it: a bar on top, the view in its frame, the line, and the
-- panel with its one button under it). Every phase before
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
BUI.resetAll = function() end -- set by ui.lua: wipe the save, a new game
BUI.nextPhase = function() end -- set by ui.lua (dev): round to phase 1

local S
local vw, vh = 320, 240
local t = 0 -- the clock
local reduced = false
local R = {}
local function rect(x, y, w, h) return { x = floor(x), y = floor(y), w = floor(w), h = floor(h) } end
local scene = { w = 300, h = 200, hor = 76, k = 124 } -- the view: its height, the horizon, horizon to our feet
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
BUI.setReducedAll = function(v) BUI.setReduced(v) end -- set by ui.lua, which owns the setting

function BUI.fit(w, h, inset)
    vw, vh = w, h
    local l, top, r, bot = inset.l + 3, inset.t + 2, vw - inset.r - 3, vh - inset.b - 2
    R.top = rect(l, top, r - l, 13)
    R.mute = rect(r - 17, top, 17, 13)
    R.motion = rect(r - 37, top, 17, 13)
    R.reset = rect(r - 57, top, 17, 13)
    R.phase = rect(r - 77, top, 17, 13)
    local y = top + 16
    if vh >= vw * 1.15 then
        local sh = max(110, floor((bot - y) * 0.5))
        R.scene = rect(l + 1, y, r - l - 2, sh)
        R.line = rect(l, y + sh + 4, r - l, 13)
        R.panel = rect(l, R.line.y + 17, r - l, bot - (R.line.y + 17))
    else
        local pw = max(160, min(230, floor((r - l) * 0.42)))
        local sx = r - pw
        R.scene = rect(l + 1, y, sx - l - 7, bot - y - 18)
        R.line = rect(l, R.scene.y + R.scene.h + 4, sx - l - 5, 13)
        R.panel = rect(sx, y + 17, pw, bot - (y + 17))
    end
    -- In the panel: the tally, and under it the one button.
    R.tally = rect(R.panel.x, R.panel.y, R.panel.w, 31)
    R.jump = rect(R.panel.x, R.tally.y + R.tally.h + 4, R.panel.w, min(44, max(24, R.panel.h - R.tally.h - 4)))
    scene.w, scene.h = R.scene.w, R.scene.h
    scene.hor = floor(scene.h * 0.38)
    scene.k = scene.h - scene.hor
    sizeK = max(1.6, min(scene.w / 30, scene.h / 38))
end

function BUI.sceneRect() return R.scene end

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
    if inside(R.jump, x, y) then
        down = 0.15
        BUI.jump()
    elseif inside(R.mute, x, y) then
        S.muted = not S.muted
        Audio.setMuted(S.muted)
        Audio.cue("click")
        BUI.save()
    elseif inside(R.motion, x, y) then
        S.reducedMotion = not S.reducedMotion
        BUI.setReducedAll(S.reducedMotion)
        Audio.cue("click")
        BUI.save()
    elseif inside(R.reset, x, y) then
        Audio.cue("click")
        if confirm > t then
            confirm = 0
            Audio.setBeyond(false)
            BUI.resetAll()
        else
            confirm = t + 3
        end
    elseif inside(R.phase, x, y) then
        Audio.cue("click")
        Audio.setBeyond(false)
        BUI.nextPhase()
    end
end
function BUI.moved() end
function BUI.released() end
function BUI.wheel() end

function BUI.key(key)
    if key == "m" then BUI.pressed(R.mute.x + 1, R.mute.y + 1)
    elseif key == "r" then BUI.pressed(R.motion.x + 1, R.motion.y + 1)
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
    say("COUNTED! " .. b.mine, scene.w / 2, scene.hor + scene.k * 0.5)
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
            say(tostring(S.beyond.count), scene.w / 2 + (pos % 2 == 0 and 16 or -16), scene.hor + scene.k * 0.2)
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
    G.rect("c", 0, 0, scene.w, hor + 1)
    -- Haze toward the horizon.
    local pts = {}
    local band = min(hor, 46)
    for y = hor - band, hor do
        local d = (y - (hor - band)) / band
        for x = 0, scene.w - 1 do
            if G.dither(x, y, d * 0.9) then G.plot(pts, x, y) end
        end
    end
    G.points("w", pts)
    -- The sun, and clouds drifting.
    G.disc("y", floor(scene.w * 0.78), floor(hor * 0.38), max(5, floor(sizeK * 3)))
    local drift = reduced and 0 or t * 2
    for i, c in ipairs({ { 0.2, 0.3 }, { 0.55, 0.18 }, { 0.9, 0.5 } }) do
        local x = floor((c[1] * scene.w + drift * (0.6 + i * 0.2)) % (scene.w + 60) - 30)
        local y, r = floor(hor * c[2]), 4 + i
        G.disc("w", x, y, r)
        G.disc("w", x + r, y + 1, r - 1)
        G.disc("w", x - r, y + 2, r - 2)
    end
    -- Far hills.
    for x = 0, scene.w - 1, 2 do
        local hh = 5 + floor(4 * sin(x * 0.035) + 3 * sin(x * 0.09 + 1))
        G.rect("g", x, hor - hh, 2, hh + 1)
    end
end

local function ground(adv, camH)
    local hor, k = scene.hor, scene.k
    G.rect("m", 0, hor + 1, scene.w, scene.h - hor)
    -- The lane, a worn path widening toward us.
    local cx = scene.w / 2
    for y = hor + 1, scene.h - 1 do
        local hw = floor(scene.w * (0.05 + 0.30 * (y - hor) / (k + camH)))
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
            local x = floor(cx + (hx - 0.5) * scene.w * (0.4 + 1.6 * w))
            for j = 0, max(1, floor(3 * sizeK * w)) - 1 do G.plot(i % 3 == 0 and dark or light, x, y - j) end
        end
    end
    G.points("g", dark)
    G.points("g", light)
end

local function fence(z, camH)
    local w = wOf(z)
    local y = floor(scene.hor + (scene.k + camH) * w)
    local x = floor(scene.w / 2)
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
    local x = floor(scene.w / 2)
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
        local x = floor(scene.w / 2 + sx * min(scene.w * 0.16, 26))
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
    G.rect("w", 0, 0, scene.w, lid)
    G.rect("b", 0, lid - 1, scene.w, 1)
    G.rect("w", 0, scene.h - lid, scene.w, lid)
    G.rect("b", 0, scene.h - lid, scene.w, 1)
end

local function drawScene()
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

    -- BAD SHEEP.
    if flash > t then
        local bob = reduced and 0 or floor(sin(t * 14) * 1.5)
        local s1, s2 = "BAD SHEEP!", "WAIT YOUR TURN"
        local bw = G.textWidth(s1, 2) + 16
        local bx, by = floor(scene.w / 2 - bw / 2), floor(scene.hor + scene.k * 0.25) + bob
        G.box(bx, by, bw, 32, "r", "o")
        G.text("o", s1, floor(scene.w / 2 - G.textWidth(s1, 2) / 2), by + 5, 2)
        G.text("p", s2, floor(scene.w / 2 - G.textWidth(s2) / 2), by + 21)
    end

    -- Numbers rising.
    for _, f in ipairs(floats) do
        G.label("o", f.text, floor(f.x - G.textWidth(f.text) / 2), floor(f.y - f.t * 14), 1, f.t > 1 and (1.4 - f.t) / 0.4 or 1, "w")
    end
end

--- the screen round it: the bar on top, the line, the panel and its button -----------

local function centred(k, s, cx, y, z)
    G.text(k, s, floor(cx - G.textWidth(s, z) / 2), y, z)
end

local function turn() return pos == 0 and fz <= B.reach and not jump and not blink end

local function drawTop()
    local r = R.top
    centred("s", "BEYOND", r.x + r.w / 2, r.y + 4)
    local s = "COUNTED " .. S.beyond.count
    G.box(r.x + 1, r.y + 1, G.textWidth(s) + 6, 11, "m", "s")
    G.text("o", s, r.x + 4, r.y + 4)
    local m = R.mute
    G.box(m.x + 1, m.y + 1, m.w - 2, m.h - 2, "w", "s")
    G.art({ "...oo", "..o.o", "..o..", "..o..", ".oo..", "ooo..", ".o..." }, m.x + 6, m.y + 3)
    if S.muted then for i = 0, 8 do G.rect("r", m.x + 4 + i, m.y + 2 + i, 1, 1) end end
    local mo = R.motion
    G.box(mo.x + 1, mo.y + 1, mo.w - 2, mo.h - 2, "w", "s")
    if S.reducedMotion then G.rect("o", mo.x + 4, mo.y + 6, 9, 1)
    else G.art({ ".oo...oo.", "o..o.o..o", "....o...." }, mo.x + 4, mo.y + 5) end
    -- The reset button: an arrow coming round, and its question while it waits.
    local re = R.reset
    G.box(re.x + 1, re.y + 1, re.w - 2, re.h - 2, "w", confirm > t and "h" or "s")
    G.art(RESET_ART, re.x + 5, re.y + 3)
    -- The phase button (dev): round to phase 1, a new game.
    local ph = R.phase
    G.box(ph.x + 1, ph.y + 1, ph.w - 2, ph.h - 2, "w", "s")
    G.text("o", "4>1", ph.x + 3, ph.y + 4)
    if confirm > t then
        local q = "TAP AGAIN TO RESET ALL"
        G.label("h", q, floor(max(4, re.x + re.w - G.textWidth(q))), re.y + re.h + 3)
    end
end

-- Under the view: where we stand in the line.
local function drawLine()
    local r = R.line
    G.text("s", "LINE", r.x, r.y + 4)
    local text = turn() and "YOUR TURN!" or (pos == 0 and "ALMOST THERE" or (pos .. (pos == 1 and " SHEEP AHEAD" or " SHEEP AHEAD")))
    local bx = r.x + 24
    local bw = r.x + r.w - bx
    G.box(bx, r.y + 1, bw, 11, turn() and "y" or "w", "s")
    centred("o", text, bx + bw / 2, r.y + 4)
end

local function drawPanel()
    -- The tally.
    local r = R.tally
    G.box(r.x, r.y, r.w, r.h, "w", "s")
    local b = S.beyond
    G.text("s", "SHEEP COUNTED", r.x + 5, r.y + 5)
    G.text("o", tostring(b.count), r.x + r.w - 5 - G.textWidth(tostring(b.count)), r.y + 5)
    G.text("s", "JUMPED, AND COUNTED", r.x + 5, r.y + 13)
    G.text("o", tostring(b.mine), r.x + r.w - 5 - G.textWidth(tostring(b.mine)), r.y + 13)
    G.text("s", "BAD SHEEP", r.x + 5, r.y + 21)
    G.text(b.bad > 0 and "p" or "o", tostring(b.bad), r.x + r.w - 5 - G.textWidth(tostring(b.bad)), r.y + 21)
    -- The one button.
    local bt = R.jump
    local lift = down > 0 and 1 or 0
    local fill = turn() and ((reduced or floor(t * 4) % 2 == 0) and "y" or "h") or "m"
    G.box(bt.x + 1, bt.y + 1 + lift, bt.w - 2, bt.h - 2, fill, "o")
    G.rect("w", bt.x + 2, bt.y + 2 + lift, bt.w - 4, 1)
    centred("o", "JUMP", bt.x + bt.w / 2, bt.y + floor(bt.h / 2) - 4 + lift, 2)
end

function BUI.draw()
    G.rect("w", 0, 0, vw, vh)
    drawTop()
    -- The view, in its frame.
    local r = R.scene
    G.box(r.x, r.y, r.w, r.h, "c")
    love.graphics.push("all")
    love.graphics.setScissor(r.x, r.y, r.w, r.h)
    love.graphics.translate(r.x, r.y)
    drawScene()
    love.graphics.pop()
    G.rect("o", r.x, r.y + r.h, r.w, 2)
    drawLine()
    drawPanel()
    if S and S.muted then G.label("w", "MUTED", r.x + 4, r.y + r.h - 10) end
end

return BUI
