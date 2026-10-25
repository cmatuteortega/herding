-- Astral projection's screen: everything round the field (astral/scene.lua)
-- in phase 3, drawn the way the other phases draw theirs (flat fills in a
-- one-pixel ink edge, the 3x5 face, dithers for anything soft).
--
-- On top, the Ether; under the field, the cord: its strain as a bar (the
-- Silver Thread's mark on it), and the button to go out or come back. Then
-- three tabs: CORD (every upgrade: the cord's, letting go (the Thread and
-- the Trance), and the Ether's), DREAMERS (the other sleepers, found out
-- along the cord) and STARS (the constellations, lit a star at a time, and
-- after the last, cutting the cord). On the field: tap the next star to light it, the comet to catch it, and the dark
-- while out to take a breath (it calms a tug), or at home to go out. The
-- comet's gift, the way in, the time away and the way out (the sheep count
-- you) are dialogs and banners.
--
-- ui.lua hands everything over to this once `phase` is "astral".

local G = require "gfx"
local N = require "num"
local C = require "config"
local Astral = require "astral.game"
local AScene = require "astral.scene"
local Models = require "models"
local Audio = require "audio"
local flux = require "lib.flux"
local lume = require "lib.lume"

local floor, min, max, sin, cos = math.floor, math.min, math.max, math.sin, math.cos
local A = C.astral

local AUI = {}
AUI.save = function() end -- set by ui.lua
AUI.resetAll = function() end -- set by ui.lua
AUI.nextPhase = function() end -- set by ui.lua (dev): on to phase 4
AUI.toBeyond = function() end -- set by ui.lua: past the cut cord

local S, P -- the game's state, and its astral part
local vw, vh = 320, 240
local R = {}
local t = 0
local reduced = false

local tab = "cord" -- or "dreamers", "stars"
local buyMax = false
local rows, contentH, scroll, scrollV = {}, 0, 0, 0
local press = nil
local banner = { y = 1, text = nil, sub = nil, till = 0 }
local modal = nil -- { title, lines, big, buttons = { { label, fn } }, y }
local ending = nil -- the way out: { t }
local endingSounds -- (below, with the way out)
local starSeen = 0 -- constellations lit when STARS was last looked at

function AUI.setState(s)
    S, P = s, s.astral
    modal, banner.text, scroll, ending = nil, nil, 0, nil
    tab = "cord"
    starSeen = Astral.litCount(P)
    AScene.reset()
end
function AUI.setReduced(v) reduced = v; AScene.reduced = v end

local function rect(x, y, w, h) return { x = floor(x), y = floor(y), w = floor(w), h = floor(h) } end
local function inside(r, x, y) return r and x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h end

function AUI.fit(w, h, inset)
    vw, vh = w, h
    local l, top, r, b = inset.l + 3, inset.t + 2, vw - inset.r - 3, vh - inset.b - 2
    R.top = rect(l, top, r - l, 13)
    R.mute = rect(r - 17, top, 17, 13)
    R.motion = rect(r - 37, top, 17, 13)
    R.reset = rect(r - 57, top, 17, 13)
    R.phase = rect(r - 77, top, 17, 13)
    local y = top + 16
    if vh >= vw * 1.15 then
        local sh = max(110, floor((b - y) * 0.42))
        R.scene = rect(l + 1, y, r - l - 2, sh)
        R.cord = rect(l, y + sh + 4, r - l, 13)
        R.tabs = rect(l, R.cord.y + 16, r - l, 13)
        R.panel = rect(l, R.tabs.y + 17, r - l, b - (R.tabs.y + 17))
    else
        local pw = lume.clamp(floor((r - l) * 0.42), 160, 230)
        local sx = r - pw
        R.scene = rect(l + 1, y, sx - l - 7, b - y - 18)
        R.cord = rect(l, R.scene.y + R.scene.h + 4, sx - l - 5, 13)
        R.tabs = rect(sx, y, pw, 13)
        R.panel = rect(sx, y + 17, pw, b - (y + 17))
    end
    local bw = G.textWidth("COME BACK") + 12
    R.go = rect(R.cord.x + R.cord.w - bw, R.cord.y, bw, 13)
    AScene.resize(R.scene.w, R.scene.h)
end

function AUI.sceneRect() return R.scene end

--- what happens --------------------------------------------------------------------------

local function cue(name, data) Audio.cue(name, data) end

function AUI.banner(text, sub)
    banner.text, banner.sub, banner.till = text, sub, t + 2.8
    banner.y = 1
    flux.to(banner, reduced and 0.01 or 0.35, { y = 0 }):ease("backout")
end

local function showModal(m)
    m.y = reduced and 0 or 24
    modal = m
    flux.to(m, 0.45, { y = 0 }):ease("backout")
end

local function closeModal(i)
    local m = modal
    modal = nil
    local b = m and m.buttons[i or 1]
    if b and b.fn then b.fn() end
end

local function duration(secs)
    secs = floor(secs)
    local h, m, s = floor(secs / 3600), floor(secs % 3600 / 60), secs % 60
    if h > 0 then return ("%dH %dM"):format(h, m) end
    if m > 0 then return ("%dM %dS"):format(m, s) end
    return ("%dS"):format(s)
end

local function pct(v) return floor(v * 100 + 0.5) .. "%" end

-- The comet's three gifts.
local function cometChoice()
    local K = A.comet
    showModal({
        title = "THE COMET",
        lines = { "YOUR GUIDE, PASSING. IT OFFERS ONE THING. CHOOSE:" },
        big = "ONE OF THREE",
        buttons = {
            { label = "+" .. N.format(Astral.cometEther(P)) .. " ETHER NOW", fn = function() Astral.choose(P, "ether") end },
            { label = "CORD X" .. K.slack.mult .. " FOR " .. K.slack.seconds .. "S", fn = function() Astral.choose(P, "slack") end },
            { label = "DRIFT X" .. K.wind.mult .. " FOR " .. K.wind.seconds .. "S", fn = function() Astral.choose(P, "wind") end },
        },
    })
end

-- What changed: shown on the way in (and again if you quit before).
local function explain()
    showModal({
        title = "ASTRAL PROJECTION",
        lines = {
            "YOU ARE OUT OF THE BODY, TIED TO IT BY A SILVER CORD. GO OUT AND YOU DRIFT, FASTER THE FURTHER, AND GATHER ETHER, MORE THE FURTHER.",
            "",
            "BUT THE CORD STRAINS. COME BACK IN TIME AND THE ETHER IS YOURS, MORE FOR A CLOSE CALL. LET IT SNAP AND YOU LOSE HALF. WHEN THE BODY TUGS, TAP THE DARK: BREATHE.",
            "",
            "FURTHER OUT: THE PLANES, OTHER DREAMERS, AND THE CONSTELLATIONS, LIT A STAR AT A TIME. LIGHT THE LAST AND THE CORD CAN BE CUT.",
        },
        big = "DON'T LET GO. YET.",
        buttons = { { label = "GO OUT", fn = function() P.intro = false; Astral.project(P); AUI.save() end } },
    })
end

-- The way in: from the lucid dream's outro, or a save, or the dev button.
function AUI.enter()
    Audio.setLucid(false)
    Audio.setBeyond(false)
    Audio.setAstral(true)
    AScene.reset()
    if P.intro then explain() end
end

function AUI.away(seconds)
    if P.intro or P.cut then return end
    local r = Astral.offline(P, seconds)
    Astral.events = {}
    if not r or seconds < C.offline.minSeconds then return end
    local auto = Astral.threaded(P) and Astral.tranced(P)
    showModal({
        title = "WHILE YOU WERE AWAY...",
        lines = {
            auto and ("THE CORD WENT OUT AND CAME BACK BY ITSELF FOR " .. duration(r.secs) .. (r.capped and (" (" .. C.offline.maxHours .. " HOURS AT MOST)") or "") .. ".")
                or "THE CORD WAITED IN THE BODY. THE SILVER THREAD AND THE TRANCE WOULD KEEP IT GOING.",
        },
        big = "+" .. N.format(r.ether) .. " ETHER",
        buttons = { { label = "OUT AGAIN" } },
    })
end

-- The rules' events: banners, sounds, the field's effects.
function AUI.drain()
    local ev = Astral.events
    Astral.events = {}
    for _, e in ipairs(ev) do
        if e.type == "project" then
            cue("project")
        elseif e.type == "bank" then
            local x, y = AScene.sheepAt(P)
            AScene.float("+" .. N.format(e.value) .. " E", x, y - 14, "x")
            if not e.auto or e.strain > 0.9 then cue("bank") end
            if e.strain >= 0.9 and not e.auto then AUI.banner("A CLOSE CALL", pct(e.strain) .. " STRAIN: +" .. N.format(e.value) .. " ETHER") end
        elseif e.type == "snap" then
            AScene.snapped()
            cue("snap")
            AUI.banner("THE CORD SNAPPED", "BACK IN THE BODY WITH " .. pct(e.kept) .. ": +" .. N.format(e.value) .. " E")
        elseif e.type == "tug" then
            AScene.tug()
            cue("tug")
        elseif e.type == "breath" then
            local x, y = AScene.sheepAt(P)
            AScene.ring(x, y, "e")
            cue("breath")
        elseif e.type == "plane" then
            if e.first then
                local pl = A.planes[e.k]
                AUI.banner(pl.name:upper(), "ETHER X" .. pl.mult .. " OUT HERE")
                cue("stage")
                AScene.flash()
            end
        elseif e.type == "found" then
            local d = Astral.DREAMERS[e.k]
            AUI.banner("A DREAMER: " .. d.name:upper(), "ON DREAMERS, TO DREAM WITH YOU")
            cue("first")
        elseif e.type == "dreamer" and e.first then
            cue("buy", { tier = e.k, first = true })
        elseif e.type == "star" then
            cue("star")
        elseif e.type == "constellation" then
            local c = Astral.CONSTELLATIONS[Astral.CON[e.id]]
            AUI.banner(c.name:upper(), c.reward:upper() .. ", FOR GOOD")
            cue("safe")
            AScene.flash()
        elseif e.type == "grew" then
            if e.rank == 1 then
                local u = Astral.UP[e.id]
                AUI.banner(u.name:upper(), u.desc:upper())
            end
        elseif e.type == "comet" then
            cue("goldenAppears")
        elseif e.type == "gift" then
            cue("gift")
            AScene.flash()
            local K = A.comet
            if e.id == "ether" then AUI.banner("+" .. N.format(e.value) .. " ETHER", "THE COMET'S GIFT")
            elseif e.id == "slack" then AUI.banner("THE CORD X" .. K.slack.mult, "FOR " .. K.slack.seconds .. " SECONDS")
            else AUI.banner("DRIFT X" .. K.wind.mult, "FOR " .. K.wind.seconds .. " SECONDS") end
        elseif e.type == "cut" then
            AUI.leave()
        end
    end
end

--- the panel's rows --------------------------------------------------------------------

local CARD_H = 30

local function layout()
    rows = {}
    local y = 0
    local function add(row, h, gap)
        row.y, row.h = y, h
        rows[#rows + 1] = row
        y = y + h + (gap or 4)
    end
    local function section(id)
        for _, sec in ipairs(Astral.SECTIONS) do
            if sec.id == id then add({ header = sec.name .. (sec.how and (": " .. sec.how) or "") }, 10, 0) end
        end
        for _, u in ipairs(Astral.UPS) do
            if u.section == id then add({ up = u }, CARD_H) end
        end
        y = y + 2
    end
    if tab == "cord" then
        add({ summary = true }, 31)
        section("cord")
        section("auto")
        section("ether")
    elseif tab == "dreamers" then
        add({ header = "THEY DREAM WITH YOU, WHILE YOU'RE OUT", buy = true }, 10, 0)
        for k = 1, #Astral.DREAMERS do
            if Astral.found(P, k) then
                add({ dreamer = k }, CARD_H)
            else
                add({ dreamer = k, teaser = true }, CARD_H)
                break
            end
        end
    elseif tab == "stars" then
        local n, all = Astral.litCount(P)
        add({ header = ("CONSTELLATIONS %d/%d: TAP ONE, THEN ITS STAR"):format(n, all) }, 10, 0)
        for _, c in ipairs(Astral.CONSTELLATIONS) do add({ con = c }, CARD_H) end
        y = y + 2
        add({ header = "THE SILVER CORD" }, 10, 0)
        add({ cut = true }, CARD_H)
    end
    contentH = y
end

local function maxScroll() return max(0, contentH - R.panel.h) end

-- The summary's buttons, in panel content coordinates: { label, fn, ok, x, w }.
local function summaryButtons(w)
    local list = {}
    if Astral.threaded(P) then
        list[#list + 1] = { label = "-", ok = P.autoAt > A.autoMin, fn = function() Astral.setAuto(P, P.autoAt - A.autoStep) end }
        list[#list + 1] = { label = "+", ok = P.autoAt < A.autoMax, fn = function() Astral.setAuto(P, P.autoAt + A.autoStep) end }
    end
    if Astral.rank(P, "trance") > 0 then
        list[#list + 1] = { label = P.autoOff and "TRANCE OFF" or "TRANCE ON", ok = true, on = not P.autoOff,
            fn = function() P.autoOff = not P.autoOff end }
    end
    local x = w - 3
    for i = #list, 1, -1 do
        local b = list[i]
        b.w = G.textWidth(b.label) + 8
        x = x - b.w
        b.x = x
        x = x - 2
    end
    return list
end

--- input ----------------------------------------------------------------------------------

-- Out, or back: the button under the field, Space, or a tap on the dark at home.
local function goOrBack()
    if P.out then
        Astral.reelIn(P)
    elseif not Astral.project(P) then
        cue("nope")
    end
end

local function tapStarCard(c)
    P.sky = c.id
    if Astral.done(P, c.id) then cue("click") return end
    if not Astral.conOpen(P, c.id) then cue("nope") return end
    if not Astral.light(P, c.id) then cue("nope") end
end

local function upAction(u)
    local st = Astral.upState(P, u.id)
    if st == "full" then return u.max == 1 and "YOURS" or "ALL GROWN", false end
    return N.format(Astral.upPrice(P, u.id)) .. " E", st == "open", function()
        if Astral.grow(P, u.id) then cue("buy", { tier = 4, first = Astral.rank(P, u.id) == 1 }); AUI.save() else cue("nope") end
    end
end

local function tapRow(row, x)
    if row.up then
        local _, ok, fn = upAction(row.up)
        if ok and fn then fn() else cue("nope") end
    elseif row.dreamer and not row.teaser then
        if Astral.buyDreamer(P, row.dreamer, buyMax and "max" or 1) > 0 then cue("buy", { tier = row.dreamer }) else cue("nope") end
    elseif row.buy then
        buyMax = not buyMax
        cue("click")
    elseif row.con then
        tapStarCard(row.con)
    elseif row.summary then
        for _, b in ipairs(summaryButtons(R.panel.w)) do
            if x >= b.x and x < b.x + b.w then
                if b.ok then b.fn(); cue("click") else cue("nope") end
                return
            end
        end
    elseif row.cut then
        if P.cut then AUI.leave() return end
        if not Astral.canCut(P) then cue("nope") return end
        showModal({
            title = "CUT THE CORD?",
            lines = { "THE SLEEPER IS LIT. THE BODY IS VERY FAR BELOW, AND VERY SMALL, AND QUITE ALL RIGHT." },
            big = "LET GO",
            buttons = { { label = "CUT IT", fn = function() Astral.cutCord(P) end }, { label = "NOT YET" } },
        })
    end
end

function AUI.pressed(x, y, id)
    Audio.start()
    if ending then return end
    if modal then
        for i, b in ipairs(modal.buttons) do
            if inside(b.rect, x, y) then cue("click"); closeModal(i) return end
        end
        return
    end
    if inside(R.mute, x, y) then
        S.muted = not S.muted
        Audio.setMuted(S.muted)
        cue("click")
        AUI.save()
        return
    end
    if inside(R.motion, x, y) then
        S.reducedMotion = not S.reducedMotion
        AUI.setReducedAll(S.reducedMotion)
        AUI.banner(S.reducedMotion and "LESS MOTION" or "FULL MOTION")
        cue("click")
        AUI.save()
        return
    end
    if inside(R.reset, x, y) then
        cue("click")
        showModal({
            title = "RESET EVERYTHING?",
            lines = { "THE SAVE IS WIPED, AND A NEW GAME STARTS FROM THE FIRST NIGHT, FROM SCRATCH." },
            big = "ALL OF IT",
            buttons = { { label = "RESET", fn = function() AUI.resetAll() end }, { label = "KEEP PROJECTING" } },
        })
        return
    end
    if inside(R.phase, x, y) then
        cue("click")
        AUI.nextPhase()
        return
    end
    if inside(R.go, x, y) then
        cue("click")
        goOrBack()
        return
    end
    if inside(R.tabs, x, y) then
        local k = lume.clamp(floor((x - R.tabs.x) / (R.tabs.w / 3)) + 1, 1, 3)
        local want = ({ "cord", "dreamers", "stars" })[k]
        if want ~= tab then tab, scroll = want, 0 end
        if want == "stars" then starSeen = Astral.litCount(P) end
        cue("click")
        return
    end
    if inside(R.scene, x, y) then
        local sx, sy = x - R.scene.x, y - R.scene.y
        if AScene.hitComet(P, sx, sy) and Astral.catchComet(P) then
            cue("golden")
        elseif AScene.hitStar(P, sx, sy) then
            if not Astral.light(P, AScene.hitStar(P, sx, sy)) then cue("nope") end
        elseif P.out then
            -- A breath: it calms a tug (and is a ring on the dark, whatever).
            AScene.ring(sx, sy, "l")
            Astral.breathe(P)
        else
            AScene.ring(sx, sy, "l")
            goOrBack()
        end
        return
    end
    if inside(R.panel, x, y) then
        press = { id = id, y0 = y, scroll0 = scroll, moved = false, last = y }
        scrollV = 0
    end
end

function AUI.moved(x, y, id)
    if not press or press.id ~= id then return end
    if math.abs(y - press.y0) > 3 then press.moved = true end
    if press.moved then
        scroll = lume.clamp(press.scroll0 - (y - press.y0), 0, maxScroll())
        scrollV = (press.last - y) * 60
        press.last = y
    end
end

function AUI.released(x, y, id)
    if not press or press.id ~= id then return end
    local p = press
    press = nil
    if p.moved or not inside(R.panel, x, y) then return end
    local cy = y - R.panel.y + floor(scroll)
    for _, row in ipairs(rows) do
        if cy >= row.y and cy < row.y + row.h then tapRow(row, x - R.panel.x, cy - row.y) return end
    end
end

function AUI.wheel(dy) scroll = lume.clamp(scroll - dy * 18, 0, maxScroll()) end

function AUI.key(key)
    if ending then return end
    if modal then
        local n = tonumber(key)
        if n and modal.buttons[n] then cue("click"); closeModal(n)
        elseif key == "return" or key == "space" or key == "kpenter" then cue("click"); closeModal(1) end
        return
    end
    if key == "m" then AUI.pressed(R.mute.x + 1, R.mute.y + 1, "key")
    elseif key == "r" then AUI.pressed(R.motion.x + 1, R.motion.y + 1, "key")
    elseif key == "1" or key == "2" or key == "3" then
        AUI.pressed(R.tabs.x + (tonumber(key) - 0.5) * R.tabs.w / 3, R.tabs.y + 2, "key")
    elseif key == "space" or key == "return" then
        if P.comet and Astral.catchComet(P) then cue("golden") else goOrBack() end
    elseif key == "b" then Astral.breathe(P)
    elseif key == "down" or key == "pagedown" then AUI.wheel(-2)
    elseif key == "up" or key == "pageup" then AUI.wheel(2) end
end

--- each frame ------------------------------------------------------------------------------

function AUI.update(dt)
    t = t + dt
    if ending then
        local from = ending.t
        ending.t = ending.t + dt
        endingSounds(from, ending.t)
        if ending.t > A.ending then
            ending = nil
            AUI.toBeyond()
        end
        return
    end
    if P.choosing and not modal then cometChoice() end
    if not press then
        scroll = lume.clamp(scroll + scrollV * dt, 0, maxScroll())
        scrollV = scrollV * max(0, 1 - dt * 6)
    end
    if banner.text and t > banner.till and banner.y == 0 then
        flux.to(banner, reduced and 0.01 or 0.3, { y = 1 }):ease("quadin"):oncomplete(function() banner.text = nil end)
        banner.till = math.huge
    end
    AScene.update(dt, P)
    layout()
    scroll = lume.clamp(scroll, 0, maxScroll())
end

--- drawing ----------------------------------------------------------------------------------

local function centred(k, s, cx, y, z, edge)
    local x = floor(cx - G.textWidth(s, z) / 2)
    if edge then G.label(k, s, x, y, z, nil, edge) else G.text(k, s, x, y, z) end
end

local RESET_ART = { "..lll.l", ".l...ll", "l...lll", "l......", "l.....l", ".l...l.", "..lll.." }

local function drawTop()
    local r = R.top
    centred("e", "ASTRAL PROJECTION", r.x + r.w / 2, r.y + 4)
    local s = "E " .. N.format(P.ether)
    G.box(r.x + 1, r.y + 1, G.textWidth(s) + 6, 11, "k", "e")
    G.text("x", s, r.x + 4, r.y + 4)
    local m = R.mute
    G.box(m.x + 1, m.y + 1, m.w - 2, m.h - 2, "k", "e")
    G.art({ "...ll", "..l.l", "..l..", "..l..", ".ll..", "lll..", ".l..." }, m.x + 6, m.y + 3)
    if S.muted then for i = 0, 8 do G.rect("y", m.x + 4 + i, m.y + 2 + i, 1, 1) end end
    local mo = R.motion
    G.box(mo.x + 1, mo.y + 1, mo.w - 2, mo.h - 2, "k", "e")
    if S.reducedMotion then G.rect("l", mo.x + 4, mo.y + 6, 9, 1)
    else G.art({ ".ll...ll.", "l..l.l..l", "....l...." }, mo.x + 4, mo.y + 5) end
    local re = R.reset
    G.box(re.x + 1, re.y + 1, re.w - 2, re.h - 2, "k", "e")
    G.art(RESET_ART, re.x + 5, re.y + 3)
    -- The phase button (dev): on to phase 4.
    local ph = R.phase
    G.box(ph.x + 1, ph.y + 1, ph.w - 2, ph.h - 2, "k", "e")
    G.text("l", "3>4", ph.x + 3, ph.y + 4)
end

local function drawHud()
    local r = R.scene
    local cx = r.x + r.w / 2
    local y = r.y + 5
    local plane = A.planes[Astral.plane(P)]
    if P.out then
        centred("x", N.format(P.dist) .. " OUT", cx, y, 2, "o")
        y = y + 14
        centred("e", plane.name:upper() .. (plane.mult > 1 and ("  ETHER X" .. plane.mult) or ""), cx, y, 1, "o")
        y = y + 8
        centred("y", "+" .. N.format(Astral.bankValue(P)) .. " E   " .. N.format(Astral.gatherRate(P), true) .. "/S", cx, y, 1, "o")
    else
        centred("c", "IN THE BODY", cx, y, 2, "o")
        y = y + 14
        local s = P.rest > 0 and ("RESTING " .. math.ceil(P.rest) .. "S") or (Astral.tranced(P) and "GOING OUT..." or "TAP TO GO OUT")
        centred("l", s, cx, y, 1, "o")
        y = y + 8
        centred("e", "REACH " .. N.format(P.reach) .. "   CORD " .. N.format(Astral.cord(P)), cx, y, 1, "o")
    end
    -- The comet's gifts, while they last.
    local chips = {}
    for id, left in pairs(P.effects) do
        chips[#chips + 1] = (id == "slack" and "CORD X" .. A.comet.slack.mult or "DRIFT X" .. A.comet.wind.mult) .. " " .. math.ceil(left) .. "S"
    end
    table.sort(chips)
    y = y + 9
    for _, c in ipairs(chips) do
        local w = G.textWidth(c) + 6
        G.box(floor(cx - w / 2), y, w, 8, "y", "h")
        centred("o", c, cx, y + 2)
        y = y + 10
    end
    -- What the constellation in the sky waits on.
    local id = Astral.skyCon(P)
    local by = r.y + r.h - 9
    if not Astral.conOpen(P, id) then
        local c = Astral.CONSTELLATIONS[Astral.CON[id]]
        local s = "ITS STARS SHOW IN " .. A.planes[c.plane].name:upper()
        G.label("i", s, r.x + r.w - 4 - G.textWidth(s), by)
    elseif not Astral.done(P, id) then
        local s = "NEXT STAR " .. N.format(Astral.starPrice(P, id)) .. " E"
        G.label(Astral.canLight(P, id) and "y" or "l", s, r.x + r.w - 4 - G.textWidth(s), by)
    end
    if P.comet then
        local s = "THE COMET! TAP IT"
        if reduced or floor(t * 2) % 3 ~= 0 then G.label("y", s, r.x + 4, by - 10) end
    end
    if banner.text then
        local w = min(r.w - 10, max(G.textWidth(banner.text, 2), G.textWidth(banner.sub or "")) + 14)
        local h = banner.sub and 24 or 16
        local bny = floor(r.y + r.h * 0.5 - h / 2 + banner.y * (r.h * 0.6))
        if bny < r.y + r.h then
            local bx = floor(cx - w / 2)
            G.box(bx, bny, w, h, "x")
            G.rect("e", bx, bny + h - 2, w, 2)
            local tz = G.textWidth(banner.text, 2) <= w - 6 and 2 or 1
            centred("k", banner.text, cx, bny + 3, tz)
            if banner.sub then centred("p", banner.sub, cx, bny + 15) end
        end
    end
end

-- The cord's bar: the strain (silver, rose past 60%, the tug still coming
-- shown pale), the Silver Thread's mark, and the button.
local function drawCord()
    local r = R.cord
    G.text("e", "CORD", r.x, r.y + 4)
    local strain = Astral.strain(P)
    local bx, bw = r.x + 20, R.go.x - r.x - 24
    if bw > 10 then
        G.box(bx, r.y + 3, bw, 7, "k", "o")
        local fill = floor(bw * min(1, strain))
        local coming = floor(bw * min(1, strain + P.tugLeft))
        if coming > fill then G.rect("i", bx + fill, r.y + 3, coming - fill, 7) end
        if fill > 0 then
            local k = strain > 0.85 and ((reduced or sin(t * 14) > 0) and "r" or "y") or (strain > 0.6 and "r" or "e")
            G.rect(k, bx, r.y + 3, fill, 7)
            G.rect("x", bx, r.y + 3, fill, 1)
        end
        if Astral.threaded(P) then
            local mx = bx + floor(bw * P.autoAt)
            G.rect("y", mx, r.y + 1, 1, 11)
        end
        local s = pct(min(1, strain))
        if not P.out then s = P.rest > 0 and "REST" or "HOME" end
        G.label("w", s, bx + 3, r.y + 4, 1, nil, "o")
    end
    local g = R.go
    local label = P.out and "COME BACK" or (P.rest > 0 and ("REST " .. math.ceil(P.rest)) or "GO OUT")
    local ok = P.out or P.rest <= 0
    local pulse = ok and not reduced and (P.out and strain > 0.75 or not P.out) and sin(t * 5) > 0
    G.box(g.x + 1, g.y + 1, g.w - 2, g.h - 2, ok and (P.out and "r" or "y") or "s", pulse and "w" or "o")
    centred("o", label, g.x + g.w / 2, g.y + 4)
end

local function drawTabs()
    local r = R.tabs
    local buttons = { { "CORD", tab == "cord" }, { "DREAMERS", tab == "dreamers" }, { "STARS", tab == "stars" } }
    local w = floor((r.w - 2 * (#buttons - 1)) / #buttons)
    for i, b in ipairs(buttons) do
        local x = r.x + (i - 1) * (w + 2)
        local on = b[2]
        G.box(x + 1, r.y + 1, w - 2, r.h - 2, on and "x" or "k", on and "o" or "e")
        if on then G.rect("e", x + 1, r.y + r.h - 2, w - 2, 1) end
        local s = b[1]
        if G.textWidth(s) > w - 4 then s = s:sub(1, 5) end
        centred(on and "k" or "l", s, x + w / 2, r.y + 4)
        -- Something to find there, a rose mark on STARS: a star that can be
        -- lit, or the cord that can be cut.
        local mark = i == 3 and (Astral.canLight(P, Astral.skyCon(P)) and Astral.litCount(P) == starSeen
            or Astral.canCut(P))
        if not on and mark and (reduced or sin(t * 4) > -0.5) then G.art({ "r", "r", "r", ".", "r" }, x + 4, r.y + 3) end
    end
end

local function drawSummary(x, y, w)
    G.box(x + 1, y + 1, w - 2, 29, "k", "e")
    G.text("x", "CORD " .. N.format(Astral.cord(P)) .. "  DRIFT X" .. N.format(Astral.speed(P) / A.speed, true) .. "  REACH " .. N.format(P.reach), x + 5, y + 4)
    G.text("l", "CLOSE CALL +" .. pct(Astral.closeCall(P)) .. " AT THE LIMIT. REST " .. N.format(Astral.restTime(P), true) .. "S", x + 5, y + 11)
    local buttons = summaryButtons(w)
    local room = (buttons[1] and buttons[1].x or w) - 8
    local s = "BACK IN TIME: THE BUTTON, OR SPACE"
    if Astral.threaded(P) then
        s = "THE THREAD BRINGS YOU BACK AT " .. pct(P.autoAt)
        if G.textWidth(s) > room then s = "THREAD: BACK AT " .. pct(P.autoAt) end
        if G.textWidth(s) > room then s = "BACK AT " .. pct(P.autoAt) end
    end
    G.text("e", s, x + 5, y + 20)
    for _, b in ipairs(buttons) do
        G.box(x + b.x, y + 18, b.w, 9, b.ok and (b.on == false and "s" or "y") or "s", "o")
        centred("o", b.label, x + b.x + b.w / 2, y + 20)
    end
end

-- An upgrade's card: a picture, its name and rank, what it does (or what it
-- waits on), its price.
local function drawUp(row, x, y, w)
    local u, h = row.up, row.h
    local st = Astral.upState(P, u.id)
    local label, ok = upAction(u)
    local shut, full = st == "shut", st == "full"
    if ok and not reduced and sin(t * 3.4 + row.y * 0.05) > 0 then G.box(x, y, w, h, "x", "x") end
    G.box(x + 1, y + 1, w - 2, h - 2, shut and "k" or (ok and "x" or (full and "e" or "s")), shut and "i" or nil)
    G.box(x + 4, y + 4, 28, h - 8, shut and "n" or "k", shut and "i" or nil)
    -- The picture: the cord's ones a curl of silver; the rest a star.
    if u.section == "cord" then
        for i = 0, 15 do G.rect(shut and "p" or "e", x + 10 + i, floor(y + h / 2 + sin(i * 0.6) * 4), 1, 1) end
    elseif u.section == "auto" then
        local sp = Models.sheep(-1.2, 0, 0, "cloud", false, 0.45)
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(sp.img, floor(x + 18) - sp.oi, floor(y + h / 2 + 3) - sp.oj)
    else
        local k = shut and "p" or "x"
        G.rect(k, x + 14, y + h / 2, 9, 1); G.rect(k, x + 18, y + h / 2 - 4, 1, 9)
        G.rect(shut and "p" or "y", x + 18, y + h / 2, 1, 1)
    end
    local pw = G.textWidth(label) + 8
    local px = x + w - pw - 4
    G.box(px, y + 4, pw, h - 8, ok and "y" or "b")
    G.text("o", label, px + pw - 4 - G.textWidth(label), y + 7)
    if u.max > 1 then
        local s = Astral.rank(P, u.id) .. "/" .. u.max
        G.text(ok and "h" or "p", s, px + pw - 4 - G.textWidth(s), y + 15)
    end
    local tx = x + 37
    G.text(shut and "s" or "o", u.name:upper(), tx, y + 5)
    local say = shut and ("AFTER " .. Astral.UP[u.at].name:upper()) or u.desc:upper()
    local lines = G.wrap(say, px - tx - 4)
    for i = 1, min(2, #lines) do G.text(shut and "s" or "p", lines[i], tx, y + 8 + i * 6) end
end

local function drawDreamer(row, x, y, w)
    local k, h = row.dreamer, row.h
    local d = Astral.DREAMERS[k]
    if row.teaser then
        G.box(x + 1, y + 1, w - 2, h - 2, "k", "i")
        G.box(x + 4, y + 4, 28, h - 8, "n", "i")
        AScene.dreamerIcon(k, x + 18, y + h / 2, true)
        G.text("s", "???", x + 37, y + 6)
        G.text("s", "SOMEONE ASLEEP, " .. N.format(d.at) .. " OUT", x + 37, y + 15)
        return
    end
    local n = buyMax and max(1, N.geoMax(d.base, d.growth, P.dreamers[k], P.ether)) or 1
    local cost = Astral.dreamerCost(P, k, n)
    local ok = N.gte(P.ether, cost)
    if ok and not reduced and sin(t * 3.4 + row.y * 0.05) > 0 then G.box(x, y, w, h, "x", "x") end
    G.box(x + 1, y + 1, w - 2, h - 2, ok and "x" or "s")
    G.box(x + 4, y + 4, 28, h - 8, "k")
    AScene.dreamerIcon(k, x + 18, y + h / 2)
    local price, qty = N.format(cost) .. " E", "X" .. n
    local pw = max(G.textWidth(price), G.textWidth(qty)) + 8
    local px = x + w - pw - 4
    G.box(px, y + 4, pw, h - 8, ok and "y" or "b")
    G.text("o", price, px + pw - 4 - G.textWidth(price), y + 7)
    G.text(ok and "h" or "p", qty, px + pw - 4 - G.textWidth(qty), y + 15)
    local tx = x + 37
    G.text("o", d.name:upper() .. (P.dreamers[k] > 0 and (" X" .. P.dreamers[k]) or ""), tx, y + 5)
    local lines = G.wrap(d.desc:upper(), px - tx - 4)
    G.text("p", lines[1] or "", tx, y + 12)
    local tens = floor(P.dreamers[k] / A.dreamerEvery)
    G.text("p", "+" .. N.format(Astral.dreamerRate(P, k), true) .. " E/S EACH" .. (tens > 0 and ("  X" .. 2 ^ tens) or ""), tx, y + 19)
end

local function drawCon(row, x, y, w)
    local c, h = row.con, row.h
    local done, open = Astral.done(P, c.id), Astral.conOpen(P, c.id)
    local can = Astral.canLight(P, c.id)
    local picked = Astral.skyCon(P) == c.id
    if can and not reduced and sin(t * 3.4 + row.y * 0.05) > 0 then G.box(x, y, w, h, "x", "x") end
    G.box(x + 1, y + 1, w - 2, h - 2, not open and not done and "k" or (done and "e" or (can and "x" or "s")),
        picked and "y" or (open and "o" or "i"))
    G.box(x + 4, y + 4, 28, h - 8, "n", open and "o" or "i")
    AScene.constellationIcon(P, c.id, x + 18, y + h / 2, 20, not open and not done)
    local label = done and "LIT" or (open and (N.format(Astral.starPrice(P, c.id)) .. " E") or "LOCKED")
    local pw = G.textWidth(label) + 8
    local px = x + w - pw - 4
    G.box(px, y + 4, pw, h - 8, can and "y" or "b")
    G.text("o", label, px + pw - 4 - G.textWidth(label), y + 7)
    local s = Astral.lit(P, c.id) .. "/" .. #c.stars
    G.text(can and "h" or "p", s, px + pw - 4 - G.textWidth(s), y + 15)
    local tx = x + 37
    G.text(open and "o" or "s", c.name:upper(), tx, y + 5)
    local say
    if done or open then say = (done and "YOURS: " or "") .. c.reward:upper()
    else
        local k = Astral.CON[c.id]
        local before = Astral.CONSTELLATIONS[k - 1]
        say = P.reach < A.planes[c.plane].at and ("REACH " .. A.planes[c.plane].name:upper())
            or ("LIGHT " .. (before and before.name:upper() or "") .. " FIRST")
    end
    local lines = G.wrap(say, px - tx - 4)
    for i = 1, min(2, #lines) do G.text(open and "p" or "s", lines[i], tx, y + 8 + i * 6) end
end

local function drawCut(row, x, y, w)
    local h = row.h
    local last = Astral.CONSTELLATIONS[#Astral.CONSTELLATIONS]
    local ok = Astral.canCut(P)
    if ok and not reduced and sin(t * 3.4) > 0 then G.box(x, y, w, h, "y", "y") end
    G.box(x + 1, y + 1, w - 2, h - 2, ok and "x" or "k", ok and "o" or "i")
    G.box(x + 4, y + 4, 28, h - 8, "n")
    for i = 0, 10 do G.rect(ok and "e" or "p", x + 12 + i, floor(y + h / 2 + sin(i * 0.8) * 3), 1, 1) end
    G.rect(ok and "r" or "p", x + 18, y + 8, 1, h - 16)
    local label = P.cut and "LET GO" or (Astral.done(P, last.id) and (N.format(A.cut) .. " E") or "LOCKED")
    local pw = G.textWidth(label) + 8
    local px = x + w - pw - 4
    G.box(px, y + 4, pw, h - 8, ok and "y" or "b")
    G.text("o", label, px + pw - 4 - G.textWidth(label), y + 7)
    G.text(ok and "o" or "l", "CUT THE CORD", x + 37, y + 5)
    local say = Astral.done(P, last.id) and "AND LET GO. THE END OF ASTRAL PROJECTION." or ("LIGHT " .. last.name:upper() .. ", AT THE EDGE, FIRST")
    local lines = G.wrap(say, px - x - 41)
    for i = 1, min(2, #lines) do G.text(ok and "p" or "i", lines[i], x + 37, y + 8 + i * 6) end
end

local function drawPanel()
    local r = R.panel
    love.graphics.push("all")
    love.graphics.setScissor(r.x - 3, r.y, r.w + 6, r.h)
    local oy = r.y - floor(scroll)
    for _, row in ipairs(rows) do
        local y = oy + row.y
        if y + row.h >= r.y and y < r.y + r.h then
            if row.header then
                G.text("e", row.header, r.x + 2, y + 2)
                if row.buy then
                    local s = buyMax and "MAX" or "X1"
                    G.box(r.x + r.w - G.textWidth(s) - 8, y, G.textWidth(s) + 6, 9, buyMax and "y" or "k", "e")
                    G.text(buyMax and "o" or "l", s, r.x + r.w - G.textWidth(s) - 5, y + 2)
                end
            elseif row.summary then drawSummary(r.x, y, r.w)
            elseif row.up then drawUp(row, r.x, y, r.w)
            elseif row.dreamer then drawDreamer(row, r.x, y, r.w)
            elseif row.con then drawCon(row, r.x, y, r.w)
            elseif row.cut then drawCut(row, r.x, y, r.w) end
        end
    end
    love.graphics.pop()
    if maxScroll() > 0 then
        local th = max(10, floor(r.h * r.h / contentH))
        local ty = r.y + floor((r.h - th) * scroll / maxScroll())
        G.rect("e", r.x + r.w + 1, ty, 1, th)
    end
end

local function drawModal()
    local m = modal
    G.rect("n", 0, 0, vw, vh)
    local rnd = love.math.newRandomGenerator(9)
    for _ = 1, floor(vw * vh / 200) do
        local x, y, ph = rnd:random(0, vw - 1), rnd:random(0, vh - 1), rnd:random() * 6.3
        local tw = reduced and 1 or sin(t * 1.1 + ph)
        if tw > -0.6 then G.rect(tw > 0.5 and "x" or "e", x, y, 1, 1) end
    end
    local w = min(vw - 16, 230)
    local inner = w - 16
    local lines, first = {}, 0
    for i, l in ipairs(m.lines) do
        if l == "" then lines[#lines + 1] = "" else
            for _, s in ipairs(G.wrap(l, inner)) do lines[#lines + 1] = s end
        end
        if i == 1 then first = #lines end
    end
    local tz = G.textWidth(m.title, 2) <= inner and 2 or 1
    local bz = G.textWidth(m.big, 2) <= inner and 2 or 1
    local nb = #m.buttons
    local h = 10 + (5 * tz + 4) + 4 + #lines * 7 + 6 + 5 * bz + 8 + nb * 17 + 4
    local x, y = floor((vw - w) / 2), floor((vh - h) / 2 + m.y)
    G.box(x, y, w, h, "k", "e")
    G.rect("n", x, y + h - 2, w, 2)
    local cy = y + 8
    centred("x", m.title, vw / 2, cy, tz)
    cy = cy + 5 * tz + 8
    for i, s in ipairs(lines) do
        centred("l", s, vw / 2, cy); cy = cy + 7
        if i == first then
            cy = cy + 4
            centred("y", m.big, vw / 2, cy, bz)
            cy = cy + 5 * bz + 6
        end
    end
    local by = y + h - nb * 17 - 4
    for i, b in ipairs(m.buttons) do
        local bw = min(inner, G.textWidth(b.label) + 24)
        local br = rect(vw / 2 - bw / 2, by + (i - 1) * 17, bw, 14)
        local pulse = (i == 1 and not reduced and sin(t * 3) > 0) and 1 or 0
        G.box(br.x - pulse, br.y - pulse, br.w + pulse * 2, br.h + pulse * 2, "y", "y")
        G.box(br.x + 1, br.y + 1, br.w - 2, br.h - 2, nb > 1 and "x" or "e")
        G.rect("e", br.x + 1, br.y + br.h - 2, br.w - 2, 1)
        centred("o", b.label, vw / 2, br.y + 4)
        b.rect = br
    end
end

--- the way out: the sheep count you -------------------------------------------------------

-- The cord cut: it falls away below, the dark settles, the stars you lit
-- brighten, and the sheep come, one by one, round the dreamer's sheep, each
-- with a number: they're counting you. Then the light, from the middle out,
-- and phase 4.
local THIN, GATHER, COUNT_AT, LIGHT_AT = 2.0, 3.2, 4.2, 10.6
local COUNTED = 12 -- sheep that come to count

function AUI.leave()
    if ending then return end
    modal = nil
    ending = { t = reduced and LIGHT_AT - 0.5 or 0 }
    cue("snap")
    AUI.save()
end

local function countAt(i) return COUNT_AT + (i - 1) * 0.5 end

function endingSounds(from, to)
    for i = 1, COUNTED do
        local at = countAt(i)
        if from < at and to >= at then cue("tap" .. min(10, i)) end
    end
    if from < LIGHT_AT and to >= LIGHT_AT then cue("void") end
end

local function drawEnding()
    local p = ending.t
    local cx, cy = vw / 2, vh * 0.5
    G.rect("n", 0, 0, vw, vh)
    -- The stars you lit, brightening.
    local rnd = love.math.newRandomGenerator(4)
    local glow = lume.clamp((p - 1) / 2, 0, 1)
    for _ = 1, floor(vw * vh / 150) do
        local x, y, ph = rnd:random(0, vw - 1), rnd:random(0, vh - 1), rnd:random() * 6.3
        local tw = reduced and 1 or sin(t * 1.3 + ph)
        if tw > 0.2 - glow then G.rect(tw > 0.6 and "x" or "e", x, y, 1, 1) end
    end
    -- The cord, cut, falling away and thinning.
    if p < THIN then
        local f = p / THIN
        local pts = {}
        for y = floor(cy + 14), vh do
            local x = cx + sin((y - cy) * 0.08) * 6 + f * (y - cy) * 0.3
            if not G.dither(floor(x), y, f) then G.plot(pts, x, y + f * 30) end
        end
        G.points("e", pts)
    end
    -- The sheep, round the dreamer: each comes in at its moment, hops, and
    -- its number rises over it.
    local bob = reduced and 0 or sin(t * 0.8) * 2
    local sp = Models.sheep(t * 0.25, 0, 0, "cloud", false, 1.6)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(sp.img, floor(cx - sp.oi), floor(cy + bob - sp.oj))
    local rad = min(vw * 0.4, vh * 0.34)
    for i = 1, COUNTED do
        local at = countAt(i)
        if p > GATHER + (i - 1) * 0.08 then
            local a = (i - 1) / COUNTED * 6.283 - 1.57
            local come = lume.clamp((p - GATHER - (i - 1) * 0.08) / 1.2, 0, 1)
            local r = rad * (2 - come)
            local x, y = cx + cos(a) * r, cy + sin(a) * r * 0.7
            local hop = (p > at and p < at + 0.4 and not reduced) and -sin((p - at) / 0.4 * math.pi) * 6 or 0
            local face = math.atan2(cy - y, cx - x)
            local s = Models.sheep(face, 0, hop < 0 and 2 or 0, i == COUNTED and "gold" or "plain", false, 1)
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(s.img, floor(x - s.oi), floor(y + hop - s.oj))
            if p > at then
                local dens = lume.clamp((p - at) / 0.3, 0, 1) * lume.clamp((at + 1.6 - p) / 0.6, 0, 1)
                local n = tostring(i)
                G.label("y", n, floor(x - G.textWidth(n, 2) / 2), floor(y - 22 - (p - at) * 6), 2, reduced and 1 or dens, "o")
            end
        end
    end
    local function say(text, at, y, z, k)
        if p > at then
            local dens = lume.clamp((p - at) / 0.6, 0, 1)
            G.label(k, text, floor(cx - G.textWidth(text, z) / 2), floor(y), z, reduced and 1 or dens, "o")
        end
    end
    say("THE CORD IS CUT.", 0.4, vh * 0.12, 1, "e")
    say("THE SHEEP COUNT YOU.", COUNT_AT, vh * 0.12 + 10, 2, "x")
    -- The light, from the middle out, cream over everything; the words in it.
    if p > LIGHT_AT then
        local f = lume.clamp((p - LIGHT_AT) / 2.4, 0, 1)
        local far = math.sqrt(cx * cx + cy * cy)
        local pts = {}
        for y = 0, vh - 1 do
            for x = 0, vw - 1 do
                local d = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2) / far
                if G.dither(x, y, (f * 1.6 - d) * 2) then G.plot(pts, x, y) end
            end
        end
        G.points("w", pts)
        if p > LIGHT_AT + 1.6 then
            local dens = lume.clamp((p - LIGHT_AT - 1.6) / 0.6, 0, 1)
            local s = "GOODNIGHT."
            G.text("o", s, floor(cx - G.textWidth(s, 2) / 2), floor(cy - 5), 2, reduced and 1 or dens)
        end
    end
end

function AUI.draw()
    if ending then drawEnding() return end
    local r = R.scene
    G.box(r.x, r.y, r.w, r.h, "n")
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(AScene.draw(P), r.x, r.y)
    G.rect("o", r.x, r.y + r.h, r.w, 2)
    drawTop()
    drawHud()
    drawCord()
    drawTabs()
    drawPanel()
    if modal then drawModal() end
end

-- Set by ui.lua, which owns the motion setting for every phase.
AUI.setReducedAll = function(v) AUI.setReduced(v) end

-- For the shots: open a tab, and scroll it.
function AUI.show(which, at) tab = which or tab; scroll = at or 0 end

return AUI
