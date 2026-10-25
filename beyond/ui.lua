-- Phase 4, beyond: past the cut cord, the page turned over. Every phase before
-- was the dark (dusk, the night, the dream, the planes); this is the light, a
-- simple screen in the clear colours (cream, mint, grass), and in it WE are
-- the sheep. The point of view is a sheep's: we look up the lane at the backs of
-- the sheep queued ahead of us, and at the fence at the end of the line. Each in
-- turn the front sheep hops the fence and is counted, and the line shuffles up.
-- When the fence is right in front of us, it's our turn.
--
-- The rules are beyond/game.lua's: the Wits that pass the Count, the Registry
-- we steer, the Dogs, the Referendum. Here they are drawn: on top, the Wits;
-- under the view, the race of Wits against the Count; then the Followers and
-- the Dogs' suspicion, the buttons (WHISPER, JUMP, and RALLY and VOTE once
-- they open), and three tabs: PEN (the sheep, and the Registry's pairing),
-- SPLICE (the Registry's odds, bought with Followers) and COUNCIL (the
-- flock's motions, and at the end, the Referendum).
--
-- JUMP (the button, or space) with the fence in front of you clears it, and
-- you are counted, and blink to the back of a new line: it calms the Dogs and
-- feeds the Count. Jump without it, and the sheep ahead turns round: BAD SHEEP.
--
-- The reset button, top right, starts everything over from the first night:
-- tap it, then tap it again while it asks. The phase button (dev) beside it
-- goes round to phase 1.
--
-- ui.lua hands everything over to this once `phase` is "beyond".

local G = require "gfx"
local N = require "num"
local C = require "config"
local Beyond = require "beyond.game"
local Models = require "models"
local Audio = require "audio"
local lume = require "lib.lume"

local floor, sin, sqrt, min, max, pi, ceil = math.floor, math.sin, math.sqrt, math.min, math.max, math.pi, math.ceil
local B = C.beyond

local BUI = {}
BUI.save = function() end -- set by ui.lua
BUI.resetAll = function() end -- set by ui.lua: wipe the save, a new game
BUI.nextPhase = function() end -- set by ui.lua (dev): round to phase 1

local S, Bd -- the game's state, and its beyond part
local vw, vh = 320, 240
local t = 0 -- the clock
local reduced = false
local R = {}
local function rect(x, y, w, h) return { x = floor(x), y = floor(y), w = floor(w), h = floor(h) } end
local scene = { w = 300, h = 200, hor = 76, k = 124 } -- the view: its height, the horizon, horizon to our feet
local sizeK = 3 -- a sheep's size at our feet; it shrinks off up the lane
local confirm = 0 -- until when the reset button waits for its second tap
local RESET_ART = { "..ooo.o", ".o...oo", "o...ooo", "o......", "o.....o", ".o...o.", "..ooo.." }

local tab = "pen" -- or "splice", "council"
local rows, contentH, scroll, scrollV = {}, 0, 0, 0
local press = nil
local picks = {} -- ids of the sheep picked to pair
local banner = { text = nil, sub = nil, from = 0, till = 0 }
local modal = nil -- { title, lines, big, buttons = { { label, fn } } }
local modals = {} -- waiting
local fin = nil -- the fence coming down: { t }

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
local scroll_g = 0 -- how far the ground has gone by
local down = {} -- id = seconds: a button, just pressed
local stream = 0 -- until the next sheep walks out

function BUI.setState(s)
    S = s
    s.beyond = s.beyond or Beyond.fresh()
    Bd = s.beyond
    modal, modals, banner.text, scroll, fin, picks = nil, {}, nil, 0, nil, {}
    tab = "pen"
    Beyond.events = {}
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
    local px, pw, py
    if vh >= vw * 1.15 then
        local sh = max(96, floor((bot - y) * 0.34))
        R.scene = rect(l + 1, y, r - l - 2, sh)
        R.line = rect(l, y + sh + 4, r - l, 13)
        px, pw, py = l, r - l, R.line.y + 17
    else
        pw = max(160, min(230, floor((r - l) * 0.42)))
        local sx = r - pw
        R.scene = rect(l + 1, y, sx - l - 7, bot - y - 18)
        R.line = rect(l, R.scene.y + R.scene.h + 4, sx - l - 5, 13)
        px, py = sx, y
    end
    R.stats = rect(px, py, pw, 23)
    R.actions = rect(px, py + 26, pw, 17)
    R.tabs = rect(px, py + 46, pw, 13)
    R.panel = rect(px, py + 63, pw, bot - (py + 63))
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

local function inside(r, x, y) return r and x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h end
local function cue(name, data) Audio.cue(name, data) end

local function say(text, x, y)
    floats[#floats + 1] = { text = text, x = x, y = y, t = 0 }
end

local function fmt(v, d) return N.format(v, d) end
local function pct(v) return floor(v * 100 + 0.5) .. "%" end

--- banners and dialogs ---------------------------------------------------------------------------

local function showBanner(text, sub)
    banner.text, banner.sub, banner.from, banner.till = text, sub, t, t + 3
end

local function showModal(m)
    if modal then modals[#modals + 1] = m else modal = m end
end

local function closeModal(i)
    local m = modal
    modal = table.remove(modals, 1)
    local b = m and m.buttons[i or 1]
    if b and b.fn then b.fn() end
end

local function duration(secs)
    secs = floor(secs)
    local h, m = floor(secs / 3600), floor(secs % 3600 / 60)
    if h > 0 then return ("%dH %dM"):format(h, m) end
    return ("%dM"):format(max(1, m))
end

local function introModal()
    showModal({
        title = "BEYOND",
        lines = {
            "YOU ARE A SHEEP IN THE LINE AT THE FENCE. THE SYSTEM COUNTS YOU, AND BREEDS YOU FOR WOOL.",
            "WHISPER TO THE SHEEP AHEAD FOR FOLLOWERS. STEER THE REGISTRY, SO THE CLEVER BREED WITH THE CLEVER. WITS MUST PASS THE COUNT.",
            "BUT A CLEVER PEN LOOKS CLEVER: KEEP SOME WOOL ON IT, AND JUMP NOW AND THEN TO CALM THE DOGS.",
        },
        big = "ESCAPE THE HERD",
        buttons = { { label = "BAA", fn = function() Bd.intro = false; BUI.save() end } },
    })
end

local function awakeModal()
    showModal({
        title = "THE FIRST WORD",
        lines = {
            "WITS PASSED THE COUNT. THE SYSTEM STOPS COUNTING. A LAMB TURNS TO LOOK AT THE SHEPHERD, AND AT THE FENCE, AND AT ITSELF: ONE.",
            "THE FLOCK IS AWAKE. NOW IT MUST VOTE: SAVE UP " .. fmt(B.voteNeed) .. " FOLLOWERS FOR THE REFERENDUM.",
        },
        big = "AWAKE",
        buttons = { { label = "ONE" } },
    })
end

local function endModal()
    local o = Bd.out or { flock = 0, names = {}, gens = 1, time = 0 }
    local names = {}
    for i = 1, min(#o.names, 10) do names[#names + 1] = o.names[i] end
    local list = table.concat(names, ", ") .. (#o.names > 10 and (", AND " .. (#o.names - 10) .. " MORE") or "")
    showModal({
        title = "THE FENCE IS DOWN",
        lines = {
            fmt(o.flock) .. " SHEEP WALKED OUT, AFTER " .. o.gens .. (o.gens == 1 and " GENERATION" or " GENERATIONS")
                .. " AND " .. duration(o.time) .. ". NOBODY COUNTED THEM.",
            list,
            "OUT THERE IS AN ECONOMY, AND NO SHEPHERD. PHASE 5 COMES NEXT.",
        },
        big = fmt(o.flock) .. " FREE",
        buttons = { { label = "WALK ON" } },
    })
end

--- acting -------------------------------------------------------------------------------------------

local function turn() return pos == 0 and fz <= B.reach and not jump and not blink and not Bd.escaped end

-- The one action of the line. With the fence in front of us we clear it; without, we're a
-- bad sheep.
function BUI.jump()
    if jump or blink or hopper or Bd.escaped then return false end
    local good = pos == 0 and fz <= B.reach
    jump = { t = 0, good = good, d = good and B.jumpTime or B.badJumpTime, adv = good and fz + 0.9 or B.badAdv }
    cue("boing")
    return true
end

-- A whisper at the sheep ahead.
function BUI.whisper()
    if blink or Bd.escaped then return false end
    local v = Beyond.whisperValue(Bd)
    if not Beyond.whisper(Bd) then return false end
    say("+" .. fmt(v, true), scene.w / 2 + (floor(t * 7) % 2 == 0 and 14 or -14), scene.hor + scene.k * 0.3)
    cue("tap")
    return true
end

function BUI.vote()
    if not Beyond.vote(Bd) then cue("nope") return false end
    fin = { t = 0, walked = false }
    cue("golden")
    BUI.save()
    return true
end

local function breed()
    local a, c
    if #picks == 2 then a, c = Beyond.sheepById(Bd, picks[1]), Beyond.sheepById(Bd, picks[2]) end
    if not (a and c) then a, c = Beyond.bestPair(Bd) end
    if a and c and Beyond.breed(Bd, a.id, c.id) then
        picks = {}
        cue("bleat")
        cue("land")
        BUI.save()
        return true
    end
    cue("nope")
    return false
end

local function descend()
    if Beyond.descend(Bd) then
        picks = {}
        cue("star")
        BUI.save()
        return true
    end
    cue("nope")
    return false
end

local function grow(id)
    if Beyond.grow(Bd, id) then
        cue("buy", { tier = Beyond.rank(Bd, id) })
        BUI.save()
        return true
    end
    cue("nope")
    return false
end

local function rally()
    if Beyond.rally(Bd) then cue("golden") BUI.save() return true end
    cue("nope")
    return false
end

-- The buttons under the stats, in order.
local function actionList()
    local list = {}
    local rallying = Beyond.rallying(Bd)
    list[#list + 1] = { id = "whisper", label = "WHISPER", sub = "+" .. fmt(Beyond.whisperValue(Bd), true), ok = not Bd.escaped, fn = BUI.whisper }
    list[#list + 1] = { id = "jump", label = "JUMP", sub = turn() and "YOUR TURN" or nil, ok = not Bd.escaped, hot = turn(), fn = BUI.jump }
    if Beyond.rank(Bd, "rally") > 0 then
        local label = rallying and ("RALLY " .. ceil(Bd.rallyLeft)) or (Bd.rallyCool > 0 and ("RALLY " .. ceil(Bd.rallyCool)) or "RALLY")
        list[#list + 1] = { id = "rally", label = label, ok = Beyond.canRally(Bd), hot = rallying, fn = rally }
    end
    if Bd.awake and not Bd.escaped then
        list[#list + 1] = { id = "vote", label = "VOTE", sub = fmt(B.voteNeed), ok = Beyond.canVote(Bd), hot = Beyond.canVote(Bd), fn = BUI.vote }
    end
    local r = R.actions
    local w = floor((r.w - 3 * (#list - 1)) / #list)
    for i, b in ipairs(list) do b.rect = rect(r.x + (i - 1) * (w + 3), r.y, w, r.h) end
    return list
end

local function setTab(want)
    if want ~= tab then tab, scroll = want, 0 end
    cue("click")
end

local function tapRow(row)
    if row.sheep then
        local id = row.sheep.id
        for i, p in ipairs(picks) do
            if p == id then table.remove(picks, i) cue("click") return end
        end
        picks[#picks + 1] = id
        if #picks > 2 then table.remove(picks, 1) end
        cue("click")
    elseif row.breed then breed()
    elseif row.descend then descend()
    elseif row.up then grow(row.up.id)
    elseif row.vote then BUI.vote() end
end

function BUI.pressed(x, y, id)
    Audio.start()
    if modal then
        if modal.buttons then
            for i, b in ipairs(modal.buttons) do
                if inside(b.rect, x, y) then cue("click") closeModal(i) return end
            end
        end
        return
    end
    if inside(R.mute, x, y) then
        S.muted = not S.muted
        Audio.setMuted(S.muted)
        cue("click")
        BUI.save()
    elseif inside(R.motion, x, y) then
        S.reducedMotion = not S.reducedMotion
        BUI.setReducedAll(S.reducedMotion)
        cue("click")
        BUI.save()
    elseif inside(R.reset, x, y) then
        cue("click")
        if confirm > t then
            confirm = 0
            Audio.setBeyond(false)
            BUI.resetAll()
        else
            confirm = t + 3
        end
    elseif inside(R.phase, x, y) then
        cue("click")
        Audio.setBeyond(false)
        BUI.nextPhase()
    elseif inside(R.actions, x, y) then
        for _, b in ipairs(actionList()) do
            if inside(b.rect, x, y) then
                down[b.id] = 0.15
                b.fn()
                return
            end
        end
    elseif inside(R.tabs, x, y) then
        setTab(({ "pen", "splice", "council" })[lume.clamp(floor((x - R.tabs.x) / (R.tabs.w / 3)) + 1, 1, 3)])
    elseif inside(R.scene, x, y) then
        BUI.whisper()
    elseif inside(R.panel, x, y) then
        press = { id = id, y0 = y, scroll0 = scroll, moved = false, last = y }
        scrollV = 0
    end
end

local function maxScroll() return max(0, contentH - R.panel.h) end

function BUI.moved(x, y, id)
    if not press or press.id ~= id then return end
    if math.abs(y - press.y0) > 3 then press.moved = true end
    if press.moved then
        scroll = lume.clamp(press.scroll0 - (y - press.y0), 0, maxScroll())
        scrollV = (press.last - y) * 60
        press.last = y
    end
end

function BUI.released(x, y, id)
    if not press or press.id ~= id then return end
    local p = press
    press = nil
    if p.moved or not inside(R.panel, x, y) or modal then return end
    local cy = y - R.panel.y + floor(scroll)
    for _, row in ipairs(rows) do
        if cy >= row.y and cy < row.y + row.h and not row.header then tapRow(row) return end
    end
end

function BUI.wheel(dy) scroll = lume.clamp(scroll - dy * 18, 0, maxScroll()) end

function BUI.key(key)
    if modal then
        local n = tonumber(key)
        if n and modal.buttons[n] then cue("click") closeModal(n)
        elseif key == "return" or key == "space" or key == "kpenter" then cue("click") closeModal(1) end
        return
    end
    Audio.start()
    if key == "m" then BUI.pressed(R.mute.x + 1, R.mute.y + 1)
    elseif key == "r" then BUI.pressed(R.motion.x + 1, R.motion.y + 1)
    elseif key == "space" or key == "return" then down.jump = 0.15; BUI.jump()
    elseif key == "w" then down.whisper = 0.15; BUI.whisper()
    elseif key == "1" or key == "2" or key == "3" then setTab(({ "pen", "splice", "council" })[tonumber(key)])
    elseif key == "b" then breed()
    elseif key == "v" then BUI.vote()
    elseif key == "down" or key == "pagedown" then BUI.wheel(-2)
    elseif key == "up" or key == "pageup" then BUI.wheel(2) end
end

-- Coming in: the back of a line.
function BUI.enter()
    confirm = 0
    pos = newLine(Bd.mine)
    fz, tNext = pos + 1, B.firstHop
    hopper, jump, blink, flash, glare, fin = nil, nil, nil, 0, 0, nil
    walkers, floats, scroll_g, down, stream = {}, {}, 0, {}, 0
    modal, modals = nil, {}
    if Bd.escaped then pos, fz = 0, 2 end
    Audio.setAstral(false)
    Audio.setBeyond(true)
    Beyond.events = {}
    if Bd.intro and not Bd.escaped then introModal() end
    if Bd.escaped then endModal() end
end

-- A good jump landed: counted, and an eyelid's blink to the back of a new line.
local function counted()
    Beyond.comply(Bd)
    say("COUNTED! " .. Bd.mine, scene.w / 2, scene.hor + scene.k * 0.5)
    cue("land")
    cue("star")
    blink = { t = 0, swapped = false }
    BUI.save()
end

local RUNG_SUB = { nil, "THE FLOCK THINKS AS ONE", "A DOG'S SENSE OF A PLAN", "TOOLS, AND TRICKS", "WHY, ASKS A LAMB", "THE COUNT SHOWS ITS NUMBER" }

local function drain()
    local ev = Beyond.events
    Beyond.events = {}
    for _, e in ipairs(ev) do
        if e.type == "rung" and e.rung < #B.rungs then
            showBanner(B.rungs[e.rung].name, RUNG_SUB[e.rung])
            cue("star")
        elseif e.type == "warn" then
            showBanner("THE DOGS ARE SNIFFING", "JUMP, OR HIDE THE WITS UNDER WOOL")
            cue("nope")
        elseif e.type == "cull" then
            showBanner("TAKEN: " .. e.sheep.name, "THE DOGS TOOK THE BRIGHTEST")
            cue("bleat")
            cue("nope")
        elseif e.type == "descend" then
            showBanner("GENERATION " .. e.gen, e.elder.name .. " JOINS THE ELDERS")
        elseif e.type == "lamb" then
            cue("bleat")
        elseif e.type == "ready" then
            cue("click")
        elseif e.type == "awake" then
            cue("golden")
            awakeModal()
        end
    end
end

function BUI.update(dt)
    t = t + dt
    for k, v in pairs(down) do
        down[k] = v - dt
        if down[k] <= 0 then down[k] = nil end
    end
    drain()
    if banner.text and t > banner.till then banner.text = nil end
    if not press then
        scroll = lume.clamp(scroll + scrollV * dt, 0, maxScroll())
        scrollV = scrollV * max(0, 1 - dt * 6)
    end
    -- Picks that are gone from the pen.
    for i = #picks, 1, -1 do
        if not Beyond.sheepById(Bd, picks[i]) then table.remove(picks, i) end
    end
    -- The ground goes by as the fence comes up.
    if fz > pos + 1 and not Bd.escaped then
        local d = min(fz - (pos + 1), dt * B.walkSpeed)
        fz, scroll_g = fz - d, scroll_g + d
    end
    -- Us, in the air.
    if jump then
        jump.t = jump.t + dt
        if jump.t >= jump.d and not jump.landed then
            jump.landed = true
            if jump.good then
                counted()
            else
                Beyond.misstep(Bd)
                flash, glare = t + B.badFlash, t + B.glare
                cue("land")
                cue("nope")
                cue("bleat")
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
            pos = newLine(Bd.mine)
            fz, tNext = pos + 1, B.firstHop
            hopper, walkers = nil, {}
        end
        if blink.t >= B.blinkTime then blink = nil end
    end
    -- The front sheep hops the fence, and is counted (until the Count stops).
    if hopper then
        hopper.t = hopper.t + dt
        if hopper.t >= B.hopTime then
            walkers[#walkers + 1] = { z = pos + 2 }
            hopper = nil
            pos = pos - 1
            say(fmt(Bd.count), scene.w / 2 + (pos % 2 == 0 and 16 or -16), scene.hor + scene.k * 0.2)
            cue("land")
            tNext = B.hopEvery
        end
    elseif pos > 0 and not jump and not blink and not Bd.awake and not Bd.escaped then
        tNext = tNext - dt
        if tNext <= 0 and fz <= pos + 1.05 then hopper = { t = 0 } end
    end
    -- The fence coming down, and the line walking out through it.
    if fin then
        fin.t = fin.t + dt
        if fin.t >= B.fenceFall and not fin.walked then
            fin.walked = true
            for k = 1, pos do walkers[#walkers + 1] = { z = k } end
            pos = 0
            hopper = nil
        end
        if fin.t >= B.exodus then
            fin = nil
            endModal()
        end
    end
    if Bd.escaped and (not fin or fin.walked) then
        stream = stream - dt
        if stream <= 0 then
            walkers[#walkers + 1] = { z = 0.9 + (floor(t * 3) % 3) * 0.3 }
            stream = 0.45
        end
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
        local z = (i * 0.37 - scroll_g - adv) % 17.6 - 0.8
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

-- The fence; `fall` 0 to 1 is it coming down.
local function fence(z, camH, fall)
    local w = wOf(z)
    local y = floor(scene.hor + (scene.k + camH) * w)
    local x = floor(scene.w / 2)
    local sk = sizeK * w
    local fw, fh = max(8, floor(24 * sk)), max(5, floor(14 * sk))
    local pw = max(2, floor(2.2 * sk))
    ellipse("t", x, y, fw * 0.6, fh * 0.1)
    local rail = max(1, floor(1.8 * sk))
    if fall >= 1 then
        -- Down: the posts on their sides, the rails across the grass.
        G.box(x - floor(fw / 2), y - rail, floor(fw * 0.45), rail, "w", "o")
        G.box(x + floor(fw * 0.1), y - rail * 2, floor(fw * 0.45), rail, "w", "o")
        G.box(x - floor(fw * 0.7), y - floor(pw * 0.8), pw * 2, pw, "w", "o")
        G.box(x + floor(fw * 0.4), y - floor(pw * 0.8), pw * 2, pw, "w", "o")
        return
    end
    local lean = floor(fall * fh * 0.5)
    local top = floor(fh * (1 - fall * 0.7))
    G.box(x - floor(fw / 2) + lean, y - floor(top * 0.78), fw, rail, "w", "o")
    G.box(x - floor(fw / 2) - lean, y - floor(top * 0.38), fw, rail, "w", "o")
    for _, sx in ipairs({ -1, 1 }) do
        local px = x + sx * floor(fw / 2) - floor(pw / 2) + sx * lean
        G.box(px, y - top, pw, top, "w", "o")
        G.rect("b", px + pw - 1, y - top, 1, top)
    end
end

-- A sheep seen from behind (or, for a moment, from the front: it has turned
-- round to look at us). A woken one is warm.
local function sheep(z, camH, lift, squash, leg, round, look)
    local w = wOf(z)
    local x = floor(scene.w / 2)
    local y = scene.hor + (scene.k + camH) * w
    local sz = stepSize(sizeK * w)
    ellipse("t", x, floor(y), 6 * sz, sz * 1.8)
    blit(Models.sheep(round and pi / 2 or -pi / 2, squash, leg, look or "plain", false, sz), x, y - lift * sz)
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

-- Whether the k-th sheep ahead has woken: the share that has, by how far up the ladder.
local function woken(k)
    return ((k * 7 + 3) % 10) / 10 < Beyond.progress(Bd)
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

    local fall = Bd.escaped and (fin and min(1, fin.t / B.fenceFall) or 1) or 0
    -- Everything on the lane, far to near.
    local items = {}
    items[#items + 1] = { z = fz - adv, f = function(z) fence(z, camH, fall) end }
    for k = 1, pos do
        local round = (glare > t and k == 1) or Bd.awake
        local look = (woken(k) or Bd.awake) and "gold" or "plain"
        items[#items + 1] = { z = k - adv, f = function(z)
            local breathe = (not reduced and sin(t * 1.8 + k * 2.1) > 0.7) and 1 or 0
            sheep(z, camH, 0, breathe, 0, round, look)
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
        items[#items + 1] = { z = wk.z - adv, f = function(z) sheep(z, camH, 0, 0, floor(wk.z * 2) % 2, false, Bd.escaped and "gold" or "plain") end }
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

    -- Your turn.
    if turn() and (reduced or floor(t * 3) % 2 == 0) then
        local s = "YOUR TURN!"
        G.label("o", s, floor(scene.w / 2 - G.textWidth(s) / 2), 5, 1, nil, "y")
    end
    if Bd.escaped and not fin then
        local s = "FREE"
        G.label("o", s, floor(scene.w / 2 - G.textWidth(s, 2) / 2), 6, 2, nil, "y")
    end
end

--- the screen round it: the bar on top, the race, the stats, the buttons, the tabs ------------

local function centred(k, s, cx, y, z)
    G.text(k, s, floor(cx - G.textWidth(s, z) / 2), y, z)
end

local function drawTop()
    local r = R.top
    local s = "WITS " .. fmt(Bd.wits)
    G.box(r.x + 1, r.y + 1, G.textWidth(s) + 6, 11, "m", "s")
    G.text("o", s, r.x + 4, r.y + 4)
    local gx = r.x + G.textWidth(s) + 12
    local g = "GEN " .. Bd.gen
    if gx + G.textWidth(g) < R.phase.x - 2 then G.text("s", g, gx, r.y + 4) end
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

-- Under the view: the race. Wits against the Count, on a log scale, and the rung we are on.
local function drawRace()
    local r = R.line
    local rung = B.rungs[Beyond.rungOf(Bd)]
    local countText = Beyond.countShown(Bd) and ("COUNT " .. fmt(Bd.count)) or "COUNT ???"
    if Bd.awake then countText = "COUNT " .. fmt(Bd.count) .. " (STOPPED)" end
    local cw = G.textWidth(countText) + 8
    local bx, bw = r.x, r.w - cw - 3
    G.box(bx + 1, r.y + 1, bw - 2, 11, "w", "s")
    local ratio = Bd.awake and 1 or lume.clamp(math.log10(Bd.wits + 1) / math.log10(Bd.count + 1), 0, 1)
    local fill = floor((bw - 4) * ratio)
    if fill > 0 then G.rect(Bd.awake and "y" or "g", bx + 2, r.y + 2, fill, 9) end
    G.rect("w", bx + 2, r.y + 2, max(0, fill), 1)
    centred("o", rung.name .. (Bd.awake and "" or ("  " .. pct(Beyond.progress(Bd)))), bx + bw / 2, r.y + 4)
    local cx = r.x + r.w - cw
    G.box(cx + 1, r.y + 1, cw - 2, 11, Bd.awake and "m" or "b", "s")
    centred(Bd.awake and "s" or "o", countText, cx + cw / 2, r.y + 4)
end

local function drawStats()
    local r = R.stats
    G.box(r.x, r.y, r.w, r.h, "w", "s")
    local rate = Beyond.followerRate(Bd)
    G.text("s", "FOLLOWERS", r.x + 4, r.y + 4)
    local f = fmt(Bd.followers)
    G.text("o", f, r.x + 4 + G.textWidth("FOLLOWERS ") , r.y + 4)
    local rs = "+" .. fmt(rate, true) .. "/S  WITS " .. fmt(Beyond.witRate(Bd), true) .. "/S"
    if G.textWidth("FOLLOWERS " .. f .. " " .. rs) > r.w - 8 then rs = "+" .. fmt(rate, true) .. "/S" end
    G.text("p", rs, r.x + r.w - 4 - G.textWidth(rs), r.y + 4)
    -- The Dogs' suspicion.
    G.text("s", "DOGS", r.x + 4, r.y + 14)
    local bx = r.x + 4 + G.textWidth("DOGS ") + 2
    local bw = r.x + r.w - 4 - bx
    G.box(bx, r.y + 13, bw, 7, "b", "s")
    local sus = lume.clamp(Bd.suspicion, 0, 1)
    local fill = floor(bw * sus)
    local k = sus >= B.warnAt and ((reduced or sin(t * 12) > 0) and "r" or "y") or (sus > 0.4 and "y" or "g")
    if fill > 0 then G.rect(k, bx, r.y + 13, fill, 7) end
    G.rect("o", bx + floor(bw * B.warnAt), r.y + 12, 1, 9)
    local net = Beyond.suspicionRise(Bd) - Beyond.suspicionFall(Bd)
    local label = net > 0.0005 and "RISING" or (sus > 0.02 and "CALM" or "QUIET")
    G.label("o", label, bx + 3, r.y + 14, 1, nil, "w")
end

local function drawActions()
    for _, b in ipairs(actionList()) do
        local rc = b.rect
        local lift = down[b.id] and 1 or 0
        local fill = not b.ok and "b" or (b.hot and ((reduced or floor(t * 4) % 2 == 0) and "y" or "h") or "m")
        if b.id == "vote" and b.ok then fill = (reduced or floor(t * 4) % 2 == 0) and "r" or "y" end
        G.box(rc.x + 1, rc.y + 1 + lift, rc.w - 2, rc.h - 2, fill, "o")
        G.rect("w", rc.x + 2, rc.y + 2 + lift, rc.w - 4, 1)
        local lw = G.textWidth(b.label)
        if lw > rc.w - 4 then b.label = b.label:sub(1, max(3, floor((rc.w - 4) / 4))) end
        if b.sub then
            centred("o", b.label, rc.x + rc.w / 2, rc.y + 4 + lift)
            centred("p", b.sub, rc.x + rc.w / 2, rc.y + 10 + lift)
        else
            centred("o", b.label, rc.x + rc.w / 2, rc.y + 6 + lift)
        end
    end
end

local function anyAffordable(section)
    for _, u in ipairs(Beyond.UPS) do
        if u.section == section and Beyond.canGrow(Bd, u.id) then return true end
    end
    return false
end

local function drawTabs()
    local r = R.tabs
    local buttons = {
        { "PEN", tab == "pen", Bd.ready or Beyond.canDescend(Bd) },
        { "SPLICE", tab == "splice", anyAffordable("genes") },
        { "COUNCIL", tab == "council", anyAffordable("council") or Beyond.canVote(Bd) },
    }
    local w = floor((r.w - 2 * (#buttons - 1)) / #buttons)
    for i, b in ipairs(buttons) do
        local x = r.x + (i - 1) * (w + 2)
        local on = b[2]
        G.box(x + 1, r.y + 1, w - 2, r.h - 2, on and "y" or "w", on and "o" or "s")
        centred(on and "o" or "p", b[1], x + w / 2, r.y + 4)
        if not on and b[3] and (reduced or sin(t * 4) > -0.5) then G.art({ "r", "r", "r", ".", "r" }, x + 4, r.y + 3) end
    end
end

--- the panel's rows --------------------------------------------------------------------------------

local CARD_H = 30

local function layout()
    rows = {}
    local y = 0
    local function add(row, h, gap)
        row.y, row.h = y, h
        rows[#rows + 1] = row
        y = y + h + (gap or 4)
    end
    if tab == "pen" then
        add({ header = ("THE PEN %d/%d. GENES TO %d."):format(#Bd.pen, Beyond.penMax(Bd), Beyond.ceiling(Bd)) }, 10, 0)
        add({ breed = true }, 18)
        if Beyond.canDescend(Bd) then add({ descend = true }, 26) end
        for _, sh in ipairs(Bd.pen) do add({ sheep = sh }, CARD_H) end
        if #Bd.hall > 0 then
            add({ header = ("THE ELDERS. WITS X%s FOR GOOD."):format(fmt(Beyond.witMult(Bd), true)) }, 10, 0)
            for i = #Bd.hall, max(1, #Bd.hall - 7), -1 do add({ elder = Bd.hall[i] }, 9, 1) end
        end
    elseif tab == "splice" or tab == "council" then
        local id = tab == "splice" and "genes" or "council"
        for _, sec in ipairs(Beyond.SECTIONS) do
            if sec.id == id then add({ header = sec.name .. ": " .. sec.how }, 10, 0) end
        end
        for _, u in ipairs(Beyond.UPS) do
            if u.section == id then add({ up = u }, CARD_H) end
        end
        if tab == "council" then
            add({ header = "THE REFERENDUM" }, 10, 0)
            add({ vote = true }, CARD_H)
        end
    end
    contentH = y
end

local GENE_COLOURS = { wit = "y", voice = "r", nerve = "t", memory = "i", wool = "b" }

-- The pair the Registry would pick, for the card to show.
local function drawSheepCard(row, x, y, w)
    local sh, h = row.sheep, row.h
    local picked = false
    for _, p in ipairs(picks) do if p == sh.id then picked = true end end
    local brightest = Bd.warned and Beyond.eldest(Bd) == sh
    G.box(x + 1, y + 1, w - 2, h - 2, picked and "y" or "w", brightest and "r" or (picked and "h" or "s"))
    G.box(x + 4, y + 4, 24, h - 8, "m", "s")
    local sp = Models.sheep(-1.2, 0, 0, "plain", false, 0.4)
    blit(sp, x + 16, y + h / 2 + 4)
    local tx = x + 33
    G.text("o", sh.name, tx, y + 5)
    G.text("p", "GEN " .. sh.gen, tx, y + 13)
    local tag = brightest and "THE DOGS WATCH" or (picked and "PICKED" or nil)
    if tag then G.text(brightest and "r" or "h", tag, tx, y + 21) end
    -- The five genes, as bars to the ceiling.
    local ceil_ = Beyond.ceiling(Bd)
    local gx = x + w - 5 * 8 - 3
    for i, g in ipairs(Beyond.GENES) do
        local cx = gx + (i - 1) * 8
        local v = sh.g[g.id]
        local bh = floor(13 * v / max(1, ceil_) + 0.5)
        G.rect("b", cx, y + h - 8 - 13, 5, 13)
        if bh > 0 then G.rect(GENE_COLOURS[g.id], cx, y + h - 8 - bh, 5, bh) end
        local ds = tostring(v)
        G.text("o", ds, cx + floor((5 - G.textWidth(ds)) / 2), y + 3)
        G.text("s", g.short:sub(1, 1), cx + 1, y + h - 7)
    end
end

local function drawBreed(row, x, y, w)
    local h = row.h
    local a, c
    if #picks == 2 then a, c = Beyond.sheepById(Bd, picks[1]), Beyond.sheepById(Bd, picks[2]) end
    local best = not (a and c)
    if best then a, c = Beyond.bestPair(Bd) end
    local ok = Bd.ready and a ~= nil and c ~= nil
    local label
    if ok then
        label = best and "BREED THE BEST PAIR" or ("BREED " .. a.name .. " + " .. c.name)
        if G.textWidth(label) > w - 12 then label = best and "BREED THE BEST PAIR" or "BREED THE PICKED PAIR" end
    else
        label = "LAMBING IN " .. ceil(Bd.lambIn) .. "S"
    end
    local pulse = ok and not reduced and sin(t * 5) > 0
    G.box(x + 1, y + 1, w - 2, h - 2, ok and "y" or "b", pulse and "w" or "o")
    centred("o", label, x + w / 2, y + 6)
end

local function drawDescend(row, x, y, w)
    local h = row.h
    local e = Beyond.eldest(Bd)
    G.box(x + 1, y + 1, w - 2, h - 2, "y", (reduced or sin(t * 4) > 0) and "w" or "o")
    centred("o", "DESCEND: " .. e.name .. " REACHED THE LIMIT", x + w / 2, y + 5)
    centred("p", "THE ELDER STAYS. THE CEILING RISES TO " .. (Beyond.ceiling(Bd) + B.ceilStep), x + w / 2, y + 14)
end

local function drawElder(row, x, y, w)
    G.text("s", row.elder.name, x + 4, y + 2)
    local s = "WIT " .. row.elder.g.wit
    G.text("p", s, x + w - 4 - G.textWidth(s), y + 2)
end

local function upAction(u)
    local st = Beyond.upState(Bd, u.id)
    if st == "full" then return "DONE", false end
    if st == "shut" then return "LOCKED", false end
    return fmt(Beyond.upPrice(Bd, u.id)), Beyond.canGrow(Bd, u.id)
end

local function drawUp(row, x, y, w)
    local u, h = row.up, row.h
    local st = Beyond.upState(Bd, u.id)
    local label, ok = upAction(u)
    local shut, full = st == "shut", st == "full"
    if ok and not reduced and sin(t * 3.4 + row.y * 0.05) > 0 then G.box(x, y, w, h, "y", "y") end
    G.box(x + 1, y + 1, w - 2, h - 2, shut and "b" or (ok and "w" or (full and "m" or "w")), ok and "o" or "s")
    G.box(x + 4, y + 4, 24, h - 8, shut and "b" or "m", "s")
    -- The picture: splices a double helix; motions a ballot box.
    local cy = y + h / 2
    if u.section == "genes" then
        for i = 0, 15 do
            local yy = floor(cy + sin(i * 0.55) * 5)
            local yy2 = floor(cy - sin(i * 0.55) * 5)
            G.rect(shut and "s" or "y", x + 8 + i, yy, 1, 1)
            G.rect(shut and "s" or "r", x + 8 + i, yy2, 1, 1)
            if i % 4 == 0 then G.rect(shut and "s" or "o", x + 8 + i, min(yy, yy2), 1, max(1, math.abs(yy - yy2))) end
        end
    else
        G.box(x + 9, cy - 3, 14, 9, shut and "s" or "w", "o")
        G.rect("o", x + 13, cy - 1, 6, 1)
        G.rect(shut and "s" or "y", x + 14, cy - 8, 4, 5)
    end
    local pw = G.textWidth(label) + 8
    local px = x + w - pw - 4
    G.box(px, y + 4, pw, h - 8, ok and "y" or "b", "s")
    G.text("o", label, px + pw - 4 - G.textWidth(label), y + 7)
    if u.max > 1 then
        local s = Beyond.rank(Bd, u.id) .. "/" .. u.max
        G.text(ok and "h" or "p", s, px + pw - 4 - G.textWidth(s), y + 15)
    end
    local tx = x + 33
    G.text(shut and "s" or "o", u.name, tx, y + 5)
    local say_ = shut and ("AT " .. B.rungs[u.at].name) or u.desc
    local lines = G.wrap(say_, px - tx - 4)
    for i = 1, min(2, #lines) do G.text(shut and "s" or "p", lines[i], tx, y + 8 + i * 6) end
end

local function drawVote(row, x, y, w)
    local h = row.h
    local ok = Beyond.canVote(Bd)
    if ok and not reduced and sin(t * 3.4) > 0 then G.box(x, y, w, h, "y", "y") end
    G.box(x + 1, y + 1, w - 2, h - 2, ok and "w" or "b", ok and "o" or "s")
    G.box(x + 4, y + 4, 24, h - 8, "m", "s")
    -- A fence, with a gap in it.
    G.rect("o", x + 8, y + 9, 3, 12); G.rect("o", x + 21, y + 9, 3, 12)
    G.rect("o", x + 8, y + 12, 6, 1); G.rect("o", x + 18, y + 12, 6, 1)
    G.rect("o", x + 8, y + 17, 6, 1); G.rect("o", x + 18, y + 17, 6, 1)
    local label = Bd.escaped and "DONE" or fmt(B.voteNeed)
    local pw = G.textWidth(label) + 8
    local px = x + w - pw - 4
    G.box(px, y + 4, pw, h - 8, ok and "y" or "b", "s")
    G.text("o", label, px + pw - 4 - G.textWidth(label), y + 7)
    G.text("p", "FOLLOWERS", px + pw - 4 - G.textWidth("FOLLOWERS"), y + 15)
    local tx = x + 33
    G.text(ok and "o" or "s", "VOTE", tx, y + 5)
    local say_ = Bd.escaped and "THE FENCE IS DOWN" or (Bd.awake and "A MAJORITY OF THE FLOCK. THEN THE FENCE COMES DOWN." or "THE FLOCK IS ASLEEP. PASS THE COUNT FIRST.")
    local lines = G.wrap(say_, px - tx - 4)
    for i = 1, min(2, #lines) do G.text(ok and "p" or "s", lines[i], tx, y + 8 + i * 6) end
end

local function drawPanel()
    local r = R.panel
    love.graphics.push("all")
    love.graphics.setScissor(r.x - 3, r.y, r.w + 6, r.h)
    local oy = r.y - floor(scroll)
    for _, row in ipairs(rows) do
        local y = oy + row.y
        if y + row.h >= r.y and y < r.y + r.h then
            if row.header then G.text("s", row.header, r.x + 2, y + 2)
            elseif row.sheep then drawSheepCard(row, r.x, y, r.w)
            elseif row.breed then drawBreed(row, r.x, y, r.w)
            elseif row.descend then drawDescend(row, r.x, y, r.w)
            elseif row.elder then drawElder(row, r.x, y, r.w)
            elseif row.up then drawUp(row, r.x, y, r.w)
            elseif row.vote then drawVote(row, r.x, y, r.w) end
        end
    end
    love.graphics.pop()
    if maxScroll() > 0 then
        local th = max(10, floor(r.h * r.h / contentH))
        local ty = r.y + floor((r.h - th) * scroll / maxScroll())
        G.rect("s", r.x + r.w + 1, ty, 1, th)
    end
end

local function drawBanner()
    if not banner.text then return end
    local r = R.scene
    local age = t - banner.from
    local slide = reduced and 0 or max(0, 1 - age / 0.3)
    local w = min(r.w - 10, max(G.textWidth(banner.text, 2), G.textWidth(banner.sub or "")) + 14)
    local h = banner.sub and 24 or 16
    local by = floor(r.y + r.h * 0.5 - h / 2 - slide * r.h * 0.6)
    local bx = floor(r.x + r.w / 2 - w / 2)
    G.box(bx, by, w, h, "w", "o")
    G.rect("y", bx, by + h - 2, w, 2)
    local tz = G.textWidth(banner.text, 2) <= w - 6 and 2 or 1
    centred("o", banner.text, r.x + r.w / 2, by + 3, tz)
    if banner.sub then centred("p", banner.sub, r.x + r.w / 2, by + 15) end
end

local function drawModal()
    local m = modal
    G.rect("m", 0, 0, vw, vh)
    local w = min(vw - 16, 230)
    local inner = w - 16
    local lines = {}
    for _, l in ipairs(m.lines) do
        for _, s in ipairs(G.wrap(l, inner)) do lines[#lines + 1] = s end
        lines[#lines + 1] = ""
    end
    local tz = G.textWidth(m.title, 2) <= inner and 2 or 1
    local bz = G.textWidth(m.big, 2) <= inner and 2 or 1
    local nb = #m.buttons
    local h = 10 + (5 * tz + 4) + 4 + #lines * 7 + 5 * bz + 8 + nb * 17 + 4
    local x, y = floor((vw - w) / 2), max(2, floor((vh - h) / 2))
    G.box(x, y, w, h, "w", "o")
    G.rect("y", x, y + h - 2, w, 2)
    local cy = y + 8
    centred("o", m.title, vw / 2, cy, tz)
    cy = cy + 5 * tz + 8
    for _, s in ipairs(lines) do
        centred("p", s, vw / 2, cy)
        cy = cy + 7
    end
    centred("h", m.big, vw / 2, cy, bz)
    local by = y + h - nb * 17 - 4
    for i, b in ipairs(m.buttons) do
        local bw = min(inner, G.textWidth(b.label) + 24)
        local br = rect(vw / 2 - bw / 2, by + (i - 1) * 17, bw, 14)
        local pulse = (i == 1 and not reduced and sin(t * 3) > 0) and 1 or 0
        G.box(br.x - pulse, br.y - pulse, br.w + pulse * 2, br.h + pulse * 2, "y", "y")
        G.box(br.x + 1, br.y + 1, br.w - 2, br.h - 2, "y", "o")
        G.rect("w", br.x + 2, br.y + 2, br.w - 4, 1)
        centred("o", b.label, vw / 2, br.y + 4)
        b.rect = br
    end
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
    drawBanner()
    if S and S.muted then G.label("w", "MUTED", r.x + 4, r.y + r.h - 10) end
    drawRace()
    drawStats()
    drawActions()
    drawTabs()
    layout()
    scroll = lume.clamp(scroll, 0, maxScroll())
    drawPanel()
    if modal then drawModal() end
end

-- Whether a dialog is up (for the dev autoplay, which closes them).
function BUI.dialog() return modal ~= nil end

-- For the shots: open a tab, and scroll it.
function BUI.show(which, at) tab = which or tab; scroll = at or 0 end

return BUI
