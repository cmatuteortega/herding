-- The screen around the field: the counter, the Drowsiness bar, the shop, the
-- banners and the dialogs, all drawn into the one low-res canvas in the
-- palette's colours, underroot's way: flat fills inside a one-pixel ink edge,
-- the 3x5 face for every word, dithering where something has to fade. Tweens
-- (a card popping, a banner sliding in, a dialog rising) are flux's.
--
-- A phone held upright gets the field on top and the shop under the thumb; a
-- wide screen gets the field on the left and the shop down the right.

local G = require "gfx"
local Game = require "game"
local N = require "num"
local C = require "config"
local Scene = require "scene"
local Audio = require "audio"
local flux = require "lib.flux"
local lume = require "lib.lume"
local LUI = require "lucid.ui"
local AUI = require "astral.ui"
local BUI = require "beyond.ui"

local floor, min, max, sin = math.floor, math.min, math.max, math.sin

local UI = {}

local S -- the game's state
local vw, vh = 320, 240
local inset = { l = 0, t = 0, r = 0, b = 0 }
local R = {} -- the layout: rectangles by name
local t = 0
local reduced = false

local shown = 0 -- the counter, rolling up to the real number
local bump = { v = 0 }
local banner = { y = 1, text = nil, sub = nil, till = 0 }
local modal = nil -- { title, lines, big, button, onClose, night, y }
local endingWaits = false
local hintGone = { v = 0 }
local intro = nil -- the way in, a new game's first moments: { t }
local INTRO_FADE, INTRO_END = 4.2, 5.4 -- the words done, the night lifting; the field's

-- The shop: a row per card, laid out by layoutShop; the pixels it is scrolled.
local rows, contentH = {}, 0
local scroll, scrollV = 0, 0
local fxCards = {} -- per item: { pop, shake, reveal } tweened
local seen = {} -- items shown before, so a new one slides in
local restlessSeen = {} -- restless nights looked at in the Dream shop, so the DREAMS mark goes
local bits = {} -- confetti in screen pixels

local press = nil -- the pointer down: { x, y, id, inShop, moved, y0, scroll0 }

-- Which shop the panel shows: "night" (sheep) or "dream" (Dream Points).
local tab = "night"
local expanded = {} -- night-shop sections opened though all on auto, by kind

UI.cue = function(name, data) Audio.cue(name, data) end

-- Phase 2 has its own screen (lucid/ui.lua): once `phase` is "lucid", every
-- call below hands over to it.
local function lucid() return S and S.phase == "lucid" and S.lucid end
-- And phase 3 (astral/ui.lua), once `phase` is "astral"; and phase 4
-- (beyond/ui.lua), once it's "beyond".
local function astral() return S and S.phase == "astral" and S.astral end
local function beyond() return S and S.phase == "beyond" end
-- Either of the two after the dream: they take every call whole.
local function later() return astral() or beyond() end
local function laterUI() return astral() and AUI or BUI end
LUI.save = function() UI.save() end
LUI.setReducedAll = function(v) UI.setReduced(v) end
AUI.save = function() UI.save() end
AUI.setReducedAll = function(v) UI.setReduced(v) end
BUI.save = function() UI.save() end
BUI.setReducedAll = function(v) UI.setReduced(v) end
-- Through the Gate of Horn.
LUI.toAstral = function()
    if Game.goAstral(S) then
        UI.save()
        AUI.setState(S)
        AUI.enter()
    end
end
-- The cord cut: beyond, and back.
AUI.toBeyond = function()
    if Game.goBeyond(S) then
        UI.save()
        BUI.setState(S)
        BUI.enter()
    end
end
BUI.back = function()
    Audio.setBeyond(false)
    Game.backToStars(S)
    UI.save()
    UI.showAstral()
end
LUI.resetAll = function() UI.resetAll() end
AUI.resetAll = function() UI.resetAll() end
BUI.resetAll = function() UI.resetAll() end
UI.resetAll = function() end -- set by main: wipe the save, a new game
LUI.nextPhase = function() UI.nextPhase() end
AUI.nextPhase = function() UI.nextPhase() end
BUI.nextPhase = function() UI.nextPhase() end
UI.nextPhase = function() end -- set by main (dev): on to the next phase

function UI.setState(s)
    S = s
    if lucid() then LUI.setState(s) end
    if astral() then AUI.setState(s) end
    if beyond() then BUI.setState(s) end
    UI.setReduced(S.reducedMotion)
    shown = N.toNumber(S.sheep)
    modal, endingWaits, UI.endingIn, banner.text, scroll, intro = nil, false, nil, nil, 0, nil
    tab, expanded = "night", {}
    seen, restlessSeen = {}, {}
    for _, it in ipairs(Game.ITEMS) do if Game.visible(S, it.id) then seen[it.id] = true end end
end
function UI.state() return S end
function UI.setReduced(v) reduced = v; Scene.reduced = v; LUI.setReduced(v); AUI.setReduced(v); BUI.setReduced(v) end

--- layout -------------------------------------------------------------------------

local function rect(x, y, w, h) return { x = floor(x), y = floor(y), w = floor(w), h = floor(h) } end
local function inside(r, x, y) return r and x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h end

function UI.fit(w, h, ins)
    vw, vh = w, h
    inset = ins or inset
    local l, top, r, b = inset.l + 3, inset.t + 2, vw - inset.r - 3, vh - inset.b - 2
    R.top = rect(l, top, r - l, 13)
    R.mute = rect(r - 17, top, 17, 13)
    R.motion = rect(r - 37, top, 17, 13)
    R.reset = rect(r - 57, top, 17, 13)
    R.phase = rect(r - 77, top, 17, 13)
    R.dp = rect(l, top, 60, 13)
    local y = top + 16
    if vh >= vw * 1.15 then
        UI.portrait = true
        local sh = max(110, floor((b - y) * 0.45))
        R.scene = rect(l + 1, y, r - l - 2, sh)
        R.drowsy = rect(l, y + sh + 5, r - l, 9)
        R.mode = rect(l, R.drowsy.y + 14, r - l, 13)
        R.shop = rect(l, R.mode.y + 17, r - l, b - (R.mode.y + 17))
    else
        UI.portrait = false
        local shopW = lume.clamp(floor((r - l) * 0.4), 150, 220)
        local sx = r - shopW
        R.scene = rect(l + 1, y, sx - l - 7, b - y - 16)
        R.drowsy = rect(l, R.scene.y + R.scene.h + 5, sx - l - 5, 9)
        R.mode = rect(sx, y, shopW, 13)
        R.shop = rect(sx, y + 17, shopW, b - (y + 17))
    end
    Scene.resize(R.scene.w, R.scene.h)
    LUI.fit(w, h, inset)
    AUI.fit(w, h, inset)
    BUI.fit(w, h, inset)
end

function UI.sceneRect()
    if lucid() then return LUI.sceneRect() end
    if astral() then return AUI.sceneRect() end
    if beyond() then return BUI.sceneRect() end
    return R.scene
end

--- the shop's rows ------------------------------------------------------------------

local CARD_H = 30

-- The Dream shop shows once there are Dream Points to spend, or ever were.
local function dreamsOpen() return Game.visible(S, Game.DREAMS[1].id) end
local function dreamAffordable()
    for _, it in ipairs(Game.DREAMS) do if Game.quote(S, it.id, "1").ok then return true end end
    return false
end

-- The first restless night that's open and not slept through, and not the
-- one you're under: one waiting to be tried.
local function waitingRestless()
    if S.asleep then return nil end
    for _, c in ipairs(Game.CHALLENGES) do
        if Game.challengeOpen(S, c.id) and not Game.done(S, c.id) and S.challenge ~= c.id then return c end
    end
end

local function layoutShop()
    rows = {}
    local y = 0
    if tab == "dream" and not dreamsOpen() then tab = "night" end
    local waiting = waitingRestless()
    if tab == "dream" and waiting then restlessSeen[waiting.id] = true end
    local sections = {
        { kind = "tap", title = "TAPPING" },
        { kind = "gen", title = "HELPERS" },
        { kind = "mult", title = "COMFORTS" },
    }
    if tab == "dream" then
        sections = {
            { group = "auto", title = "WHILE YOU SLEEP" },
            { group = "boost", title = "DEEPER SLEEP" },
            { group = "path", title = "WAY OF SLEEPING: ONE OR THE OTHER" },
            { restless = true, title = "RESTLESS NIGHTS" },
        }
        -- One waiting to be tried: the restless nights go first, not last.
        if waiting then table.insert(sections, 1, table.remove(sections)) end
    end
    local tease = Game.teaser(S)
    for _, sec in ipairs(sections) do
        local list = {}
        if sec.restless then
            -- Each opens a night; the next one waits, dashed, saying when.
            for _, c in ipairs(Game.CHALLENGES) do
                if Game.challengeOpen(S, c.id) then list[#list + 1] = { challenge = c }
                else list[#list + 1] = { challenge = c, locked = true }; break end
            end
            if not Game.challengeOpen(S, Game.CHALLENGES[1].id) then list = {} end
        end
        for _, it in ipairs(sec.restless and {} or sec.group and Game.DREAMS or Game.ITEMS) do
            local mine = sec.group and it.group == sec.group or (not sec.group and it.kind == sec.kind)
            if mine and Game.visible(S, it.id) then list[#list + 1] = it end
        end
        if sec.kind == "gen" and tease then list[#list + 1] = { id = tease, teaser = true } end
        -- A section the automation buys all of folds into one row.
        local allAuto = sec.kind and #list > 0
        for _, it in ipairs(list) do
            if it.teaser or it.challenge or not Game.automated(S, it.id) then allAuto = false end
        end
        if allAuto and not expanded[sec.kind] then
            rows[#rows + 1] = { header = sec.title, y = y, h = 10 }
            rows[#rows + 1] = { fold = sec.kind, n = #list, y = y + 10, h = 14 }
            y = y + 28
        elseif #list > 0 then
            rows[#rows + 1] = { header = sec.title, y = y, h = 10, fold = allAuto and sec.kind or nil }
            y = y + 10
            for _, it in ipairs(list) do
                if it.challenge then
                    rows[#rows + 1] = { challenge = it.challenge, locked = it.locked, y = y, h = CARD_H }
                else
                    rows[#rows + 1] = { item = it, y = y, h = CARD_H }
                end
                if not it.teaser and not it.challenge and not seen[it.id] then
                    seen[it.id] = true
                    local f = fxCards[it.id] or {}
                    fxCards[it.id] = f
                    if not reduced then
                        f.reveal = 1
                        flux.to(f, 0.45, { reveal = 0 }):ease("backout")
                    end
                end
                y = y + CARD_H + 4
            end
            y = y + 2
        end
    end
    contentH = y
end

local function maxScroll() return max(0, contentH - R.shop.h) end

--- what happens ------------------------------------------------------------------------

function UI.banner(text, sub)
    banner.text, banner.sub, banner.till = text, sub, t + 2.8
    banner.y = 1
    flux.to(banner, reduced and 0.01 or 0.35, { y = 0 }):ease("backout")
end

local function closeModal(cancelled)
    local m = modal
    modal = nil
    if m and m.onClose and not cancelled then m.onClose() end
    if endingWaits then endingWaits = false; UI.showEnding() end
end

function UI.showModal(m)
    m.y = reduced and 0 or 24
    modal = m
    flux.to(m, 0.45, { y = 0 }):ease("backout")
end

local function duration(secs)
    if secs < 10 then return (("%.1fS"):format(floor(secs * 10) / 10):gsub("%.0S", "S")) end
    secs = floor(secs)
    local h, m, s = floor(secs / 3600), floor(secs % 3600 / 60), secs % 60
    if h > 0 then return ("%dH %dM"):format(h, m) end
    if m > 0 then return ("%dM %dS"):format(m, s) end
    return ("%dS"):format(s)
end

-- Back after `seconds` away: the sheep counted meanwhile, and a word about it.
function UI.away(seconds)
    if lucid() then return LUI.away(seconds) end
    if astral() then return AUI.away(seconds) end
    if beyond() then return end
    local r = Game.offline(S, seconds)
    if not r or seconds < C.offline.minSeconds or not N.gte(r.gain, N.from(1)) then return end
    UI.showModal({
        title = "WHILE YOU WERE DREAMING...",
        lines = { "YOUR HELPERS KEPT COUNTING FOR " .. duration(r.secs) .. "."
            .. (r.capped and (" (DREAMS LAST " .. C.offline.maxHours .. " HOURS AT MOST.)") or "") },
        big = "+" .. N.format(r.gain) .. " SHEEP",
        button = S.asleep and "OH..." or "WAKE UP GENTLY",
    })
end

function UI.showEnding()
    if not S.asleep then return end
    if modal then endingWaits = true return end
    local gain = Game.dreamPointsFor(S)
    local after = S.dreamEarned + gain
    local pct = floor(C.prestige.bonusPerPoint * 100 + 0.5)
    local lines = {
        "YOU COUNTED " .. N.format(S.runTotal) .. " SHEEP" .. (S.runTime > 0 and (" IN " .. duration(S.runTime)) or "") .. ".",
        "",
    }
    local pace = Game.pace(S)
    if pace >= 1.05 then
        lines[#lines + 1] = ("A QUICK NIGHT: X%.1f DREAM POINTS."):format(pace):gsub("%.0 ", " ")
    end
    lines[#lines + 1] = "SPEND THEM IN THE DREAM SHOP. EACH ONE EVER EARNED STILL MAKES EVERY SHEEP COUNT " .. pct
        .. "% MORE: +" .. floor(after * C.prestige.bonusPerPoint * 100 + 0.5) .. "%."
    local restless = S.challenge and Game.CH[S.challenge]
    if restless then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "RESTLESS NIGHT SLEPT THROUGH: " .. restless.name:upper() .. ". FOREVER: "
            .. restless.reward:upper() .. "."
    end
    local lucid = S.lucidNight
    if lucid then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "YOU FELL ASLEEP IN UNDER " .. (C.lucid.under == 1 and "A SECOND" or duration(C.lucid.under))
            .. ". THE DREAM TURNS LUCID: YOU KNOW YOU ARE DREAMING."
    end
    UI.showModal({
        night = true,
        title = lucid and "A LUCID DREAM." or (restless and "YOU SLEPT THROUGH IT." or "YOU FELL ASLEEP."),
        lines = lines,
        big = "+" .. gain .. " DREAM POINT" .. (gain == 1 and "" or "S"),
        button = lucid and "GO LUCID" or "DREAM AGAIN",
        onClose = function()
            if lucid then
                Game.goLucid(S)
                Scene.reset()
                shown, seen, scroll = 0, {}, 0
                LUI.setState(S)
                LUI.enter()
                UI.save()
                return
            end
            Game.dreamAgain(S)
            Audio.setAsleep(false)
            Audio.cue("dream")
            UI.newNight()
            UI.save()
            -- A restless night opened with this one: say so, and show it.
            local opened
            for _, c in ipairs(Game.CHALLENGES) do
                if c.opens == S.dreams and not Game.done(S, c.id) then opened = c end
            end
            if opened then
                tab = "dream"
                UI.banner("A RESTLESS NIGHT OPENS", opened.name:upper() .. ", IN THE DREAM SHOP")
            elseif dreamAffordable() then
                tab = "dream"
                UI.banner("A NEW NIGHT", "SPEND YOUR DREAM POINTS")
            else
                UI.banner("A NEW NIGHT", "THE SHEEP ARE WAITING")
            end
        end,
    })
end

-- The way in, phase 1: the night, the moon, a few words, then the field.
-- Called for a new game (nothing to come back to).
function UI.intro()
    if not S or S.phase ~= "nights" or S.asleep then return end
    intro = { t = reduced and INTRO_FADE or 0 }
    UI.cue("dream")
end

-- Coming back to a save in phase 3.
function UI.showAstral()
    if not astral() then return end
    AUI.setState(S)
    AUI.enter()
end

-- Coming back to a save in phase 4.
function UI.showBeyond()
    if not beyond() then return end
    BUI.setState(S)
    BUI.enter()
end

-- Coming back to a save in phase 2.
function UI.showLucid()
    if not lucid() then return end
    LUI.setState(S)
    LUI.resume()
end

-- A night starts over (a new one, or a restless one): the field and shop too.
function UI.newNight()
    Scene.reset()
    Audio.setLullabies(S.owned.lullaby)
    shown, seen, scroll = 0, {}, 0
end

-- A restless night's card: start it, give it up, or nothing once it's done.
local function restless(c)
    Audio.start()
    UI.cue("click")
    if Game.done(S, c.id) or S.asleep then return end
    if S.challenge == c.id then
        UI.showModal({
            title = "GIVE UP " .. c.name:upper() .. "?",
            lines = { "THIS NIGHT ENDS, WITH NO DREAM POINTS, AND INSTEAD...", "YOU CAN TRY AGAIN WHENEVER YOU LIKE." },
            big = "A PLAIN NIGHT",
            button = "GIVE UP", cancel = "KEEP GOING",
            onClose = function()
                Game.giveUp(S)
                UI.newNight()
                tab = "night"
                UI.save()
                UI.banner("A NEW NIGHT", "A PLAIN ONE")
            end,
        })
        return
    end
    UI.showModal({
        title = "RESTLESS NIGHT: " .. c.name:upper(),
        lines = { c.rule:upper() .. ". FALL ASLEEP ANYWAY, AND FOREVER:", "",
            "THE NIGHT YOU'RE IN ENDS: NOTHING KEPT, NO DREAM POINTS." },
        big = c.reward:upper(),
        button = "START", cancel = "NOT TONIGHT",
        onClose = function()
            if Game.startChallenge(S, c.id) then
                UI.newNight()
                tab = "night"
                UI.save()
            end
        end,
    })
end

-- For the shots: the restless night dialog for a challenge's id.
function UI.askRestless(id) restless(Game.CH[id]) end

-- Little squares of wool and lavender out of a price.
local function confetti(x, y)
    if reduced then return end
    local keys = { "w", "l", "y", "b" }
    for i = 1, 10 do
        local a = love.math.random() * math.pi * 2
        local v = 30 + love.math.random() * 40
        bits[#bits + 1] = { x = x, y = y, vx = math.cos(a) * v, vy = math.sin(a) * v - 30, t = 0,
            life = 0.5 + love.math.random() * 0.3, k = keys[(i - 1) % 4 + 1] }
    end
end

local function buy(id, row)
    Audio.start()
    local it = Game.BY_ID[id]
    local f = fxCards[id] or {}
    fxCards[id] = f
    local q = Game.buy(S, id, S.buyMode)
    if not q then
        UI.cue("nope")
        if not reduced then f.shake = 1; flux.to(f, 0.3, { shake = 0 }) end
        return
    end
    local tier = it.kind == "gen" and it.index or ((it.kind == "mult" or it.kind == "dream") and 3 or 1)
    UI.cue("buy", { tier = tier, first = q.n > 0 and Game.have(S, id) == q.n })
    Scene.bought(id)
    if not reduced then f.pop = 1; flux.to(f, 0.32, { pop = 0 }):ease("quadout") end
    if row then
        local x = R.shop.x + R.shop.w - 20
        confetti(x, R.shop.y + row.y - floor(scroll) + 12)
    end
    if S.owned[id] == q.n and it.kind == "gen" then UI.banner("NEW HELPER: " .. it.name:upper(), it.desc:upper()) end
    if it.kind == "dream" then UI.banner(it.name:upper(), it.desc:upper()) end
    if id == "lullaby" then Audio.setLullabies(S.owned.lullaby) end
end

-- The rules' events: banners and sounds.
function UI.drain()
    if lucid() then return LUI.drain() end
    if astral() then return AUI.drain() end
    if beyond() then return end
    local ev = Game.events
    Game.events = {}
    for _, e in ipairs(ev) do
        if e.type == "stage" then
            local st = C.stages[e.stage]
            UI.banner(st.name:upper(), st.title:upper())
            UI.cue("stage")
        elseif e.type == "goldenAppears" then
            UI.cue("goldenAppears")
        elseif e.type == "bought" and e.auto then
            -- The automation shops quietly; only something new gets a word.
            local it = Game.BY_ID[e.id]
            if e.first then
                Scene.bought(e.id)
                if it.kind == "gen" then
                    UI.banner("NEW HELPER: " .. it.name:upper(), it.desc:upper())
                    UI.cue("buy", { tier = it.index, first = true })
                end
            end
            if e.id == "lullaby" then Audio.setLullabies(S.owned.lullaby) end
        elseif e.type == "golden" and e.auto then
            Scene.goldenCaught(e.value, S, e.at)
            UI.cue("golden")
            bump.v = 1
            flux.to(bump, 0.2, { v = 0 })
        elseif e.type == "challenge" then
            local c = Game.CH[e.id]
            UI.banner("RESTLESS: " .. c.name:upper(), c.rule:upper())
            UI.cue("stage")
        elseif e.type == "lucid" then
            UI.cue("stage")
        elseif e.type == "asleep" then
            UI.cue("asleep")
            Audio.setAsleep(true)
            UI.save()
            UI.endingIn = reduced and 0.6 or 2.8
        end
    end
end

--- saving -----------------------------------------------------------------------------

local json = require "lib.json"
function UI.save()
    if UI.noSave then return end
    love.filesystem.write(C.save.file, json.encode(Game.serialize(S)))
end
function UI.load()
    local raw = love.filesystem.getInfo(C.save.file) and love.filesystem.read(C.save.file)
    if not raw then return nil end
    local ok, o = pcall(json.decode, raw)
    return ok and Game.deserialize(o) or nil
end

--- input --------------------------------------------------------------------------

local function tapField(x, y)
    Audio.start()
    if S.asleep then return end
    local gx, gy = x and x - R.scene.x, y and y - R.scene.y
    if gx and Scene.hitGolden(S, gx, gy) then
        local gs = S.golden
        local v = Game.catchGolden(S)
        Scene.goldenCaught(v, S, gs)
        Game.events = {}
        UI.cue("golden")
        bump.v = 1
        flux.to(bump, 0.2, { v = 0 })
        return
    end
    local v = Game.tap(S)
    Scene.tapped(v, S, gx)
    UI.cue("tap")
    if not reduced then bump.v = 1; flux.to(bump, 0.16, { v = 0 }) end
end

local function modalButton()
    local m = modal
    if not m then return nil end
    return m.buttonRect
end

function UI.pressed(x, y, id)
    if intro then intro = nil return end -- a tap lets the night lift at once
    if lucid() and not modal then return LUI.pressed(x, y, id) end
    if later() then return laterUI().pressed(x, y, id) end
    if modal then
        if inside(modalButton(), x, y) then Audio.start(); UI.cue("click"); closeModal()
        elseif inside(modal.cancelRect, x, y) then Audio.start(); UI.cue("click"); closeModal(true) end
        return
    end
    if inside(R.mute, x, y) then
        Audio.start()
        S.muted = not S.muted
        Audio.setMuted(S.muted)
        UI.cue("click")
        UI.save()
        return
    end
    if inside(R.motion, x, y) then
        Audio.start()
        S.reducedMotion = not S.reducedMotion
        UI.setReduced(S.reducedMotion)
        UI.banner(S.reducedMotion and "LESS MOTION" or "FULL MOTION", S.reducedMotion and "NO SHAKE, BLINKS OR BOUNCE" or nil)
        UI.cue("click")
        UI.save()
        return
    end
    if inside(R.reset, x, y) then
        Audio.start()
        UI.cue("click")
        UI.showModal({
            title = "RESET EVERYTHING?",
            lines = { "THE SAVE IS WIPED, AND A NEW GAME STARTS FROM THE FIRST NIGHT, FROM SCRATCH." },
            big = "ALL OF IT",
            button = "RESET", cancel = "KEEP COUNTING",
            onClose = function() UI.resetAll() end,
        })
        return
    end
    if inside(R.phase, x, y) then
        Audio.start()
        UI.cue("click")
        UI.nextPhase()
        return
    end
    if inside(R.mode, x, y) then
        local nb = dreamsOpen() and 4 or 3
        local k = lume.clamp(floor((x - R.mode.x) / (R.mode.w / nb)) + 1, 1, nb)
        if k == 4 then
            tab = tab == "dream" and "night" or "dream"
        else
            S.buyMode, tab = ({ "1", "10", "max" })[k], "night"
        end
        scroll = 0
        Audio.start()
        UI.cue("click")
        return
    end
    if inside(R.scene, x, y) then tapField(x, y) return end
    if inside(R.shop, x, y) then
        press = { x = x, y = y, id = id, y0 = y, scroll0 = scroll, moved = false, last = y }
        scrollV = 0
    end
end

function UI.moved(x, y, id)
    if lucid() then return LUI.moved(x, y, id) end
    if later() then return laterUI().moved(x, y, id) end
    if not press or press.id ~= id then return end
    if math.abs(y - press.y0) > 3 then press.moved = true end
    if press.moved then
        scroll = lume.clamp(press.scroll0 - (y - press.y0), 0, maxScroll())
        scrollV = (press.last - y) * 60
        press.last = y
    end
end

function UI.released(x, y, id)
    if lucid() then return LUI.released(x, y, id) end
    if later() then return laterUI().released(x, y, id) end
    if not press or press.id ~= id then return end
    local p = press
    press = nil
    if p.moved then return end
    for _, row in ipairs(rows) do
        local cy = R.shop.y + row.y - floor(scroll)
        local hit = y >= cy and y < cy + row.h and inside(R.shop, x, y)
        if hit and row.fold then
            expanded[row.fold] = not expanded[row.fold]
            Audio.start()
            UI.cue("click")
            return
        end
        if hit and row.item and not row.item.teaser then buy(row.item.id, row) return end
        if hit and row.challenge and not row.locked then restless(row.challenge) return end
    end
end

function UI.buy(id) return buy(id) end

function UI.wheel(dy)
    if lucid() then return LUI.wheel(dy) end
    if later() then return laterUI().wheel(dy) end
    scroll = lume.clamp(scroll - dy * 18, 0, maxScroll())
end

function UI.key(key)
    if intro then intro = nil return end
    if lucid() and not modal then return LUI.key(key) end
    if later() then return laterUI().key(key) end
    if modal then
        if key == "return" or key == "space" or key == "kpenter" then UI.cue("click"); closeModal()
        elseif modal.cancel and (key == "backspace" or key == "n") then UI.cue("click"); closeModal(true) end
        return
    end
    if key == "space" or key == "return" then tapField(nil, nil)
    elseif key == "m" then UI.pressed(R.mute.x + 1, R.mute.y + 1, "key")
    elseif key == "r" then UI.pressed(R.motion.x + 1, R.motion.y + 1, "key")
    elseif key == "1" then S.buyMode, tab = "1", "night"
    elseif key == "2" then S.buyMode, tab = "10", "night"
    elseif key == "3" then S.buyMode, tab = "max", "night"
    elseif key == "d" and dreamsOpen() then tab, scroll = tab == "dream" and "night" or "dream", 0
    elseif key == "down" or key == "pagedown" then UI.wheel(-2)
    elseif key == "up" or key == "pageup" then UI.wheel(2) end
end

--- each frame -------------------------------------------------------------------------

function UI.update(dt)
    t = t + dt
    if intro then
        intro.t = intro.t + dt
        if intro.t > INTRO_END then intro = nil end
    end
    if lucid() then return LUI.update(dt) end
    if later() then return laterUI().update(dt) end
    local real = N.toNumber(S.sheep)
    if real < shown then shown = real else shown = shown + (real - shown) * min(1, dt * 12) end
    if math.abs(real - shown) < 0.5 then shown = real end
    if not press then
        scroll = lume.clamp(scroll + scrollV * dt, 0, maxScroll())
        scrollV = scrollV * max(0, 1 - dt * 6)
    end
    for _, b in ipairs(bits) do
        b.t = b.t + dt
        b.x, b.y, b.vy = b.x + b.vx * dt, b.y + b.vy * dt, b.vy + 160 * dt
    end
    for i = #bits, 1, -1 do if bits[i].t > bits[i].life then table.remove(bits, i) end end
    if banner.text and t > banner.till and banner.y == 0 then
        flux.to(banner, reduced and 0.01 or 0.3, { y = 1 }):ease("quadin"):oncomplete(function() banner.text = nil end)
        banner.till = math.huge
    end
    if (S.taps >= 3 or S.dreams > 0) and hintGone.v == 0 then flux.to(hintGone, 0.4, { v = 1 }) end
    if UI.endingIn then
        UI.endingIn = UI.endingIn - dt
        if UI.endingIn <= 0 then UI.endingIn = nil; UI.showEnding() end
    end
    Audio.setDrowsy(Game.drowsiness(S))
    layoutShop()
    scroll = lume.clamp(scroll, 0, maxScroll())
end

--- drawing ------------------------------------------------------------------------

local function centred(k, s, cx, y, z, edge)
    local x = floor(cx - G.textWidth(s, z) / 2)
    if edge then G.label(k, s, x, y, z, nil, edge) else G.text(k, s, x, y, z) end
end

local function drawTop()
    local r = R.top
    centred("l", "COUNTING SHEEP", r.x + r.w / 2, r.y + 4)
    if S.dreamEarned > 0 then
        local s = "DP " .. S.dreamPoints .. " +" .. floor(S.dreamEarned * C.prestige.bonusPerPoint * 100 + 0.5) .. "%"
        local w = G.textWidth(s) + 6
        G.box(R.dp.x + 1, R.dp.y + 1, w, 11, "v", "i")
        G.text("y", s, R.dp.x + 4, R.dp.y + 4)
    end
    -- The mute button: a note, struck through when off.
    local m = R.mute
    G.box(m.x + 1, m.y + 1, m.w - 2, m.h - 2, "v", "i")
    G.art({ "...oo", "..olo", "..ol.", "..ol.", "oool.", "olll.", "ooo.." }, m.x + 6, m.y + 3)
    G.art({ "...ll", "..l.l", "..l..", "..l..", ".ll..", "lll..", ".l..." }, m.x + 6, m.y + 3)
    if S.muted then
        for i = 0, 8 do G.rect("y", m.x + 4 + i, m.y + 2 + i, 1, 1) end
    end
    -- The motion button: a wave, flat when motion is reduced.
    local mo = R.motion
    G.box(mo.x + 1, mo.y + 1, mo.w - 2, mo.h - 2, "v", "i")
    if S.reducedMotion then G.rect("l", mo.x + 4, mo.y + 6, 9, 1)
    else G.art({ ".ll...ll.", "l..l.l..l", "....l...." }, mo.x + 4, mo.y + 5) end
    -- The reset button: an arrow coming round.
    local re = R.reset
    G.box(re.x + 1, re.y + 1, re.w - 2, re.h - 2, "v", "i")
    G.art({ "..lll.l", ".l...ll", "l...lll", "l......", "l.....l", ".l...l.", "..lll.." }, re.x + 5, re.y + 3)
    -- The phase button (dev): on to the next phase.
    local ph = R.phase
    G.box(ph.x + 1, ph.y + 1, ph.w - 2, ph.h - 2, "v", "i")
    G.text("l", "1>2", ph.x + 3, ph.y + 4)
end

local function drawHud()
    local r = R.scene
    local cx = r.x + r.w / 2
    local z = (UI.portrait and r.w >= 200) and 3 or 2
    local up = floor(bump.v * 2 + 0.5)
    local y = r.y + 5
    centred("w", N.format(shown), cx, y - up, z, "o")
    y = y + 5 * z + 4
    centred("w", "SHEEP", cx, y, 1, "o")
    y = y + 8
    centred("l", N.format(Game.totalPerSecond(S), true) .. "/S   " .. N.format(Game.tapValue(S)) .. " A TAP", cx, y, 1, "o")
    y = y + 9
    -- Under a restless night, its rule takes the narrator's place, in gold.
    local c = S.challenge and Game.CH[S.challenge]
    local say = c and ("RESTLESS: " .. c.name .. ". " .. c.rule) or Game.currentLine(S)
    for i, line in ipairs(G.wrap(say:upper(), r.w - 12)) do
        if i <= 2 then centred(c and "y" or "w", line, cx, y, 1, "o"); y = y + 7 end
    end
    -- The first hint, bobbing until the first taps.
    if hintGone.v < 1 then
        local s = "TAP TO COUNT A SHEEP"
        local w = G.textWidth(s) + 8
        local bob = reduced and 0 or floor(sin(t * 4) * 1.5 + 0.5)
        local hy = r.y + r.h - 14 + bob + floor(hintGone.v * 20)
        if hy < r.y + r.h - 4 then
            G.box(floor(cx - w / 2), hy, w, 9, "w")
            G.rect("b", floor(cx - w / 2), hy + 8, w, 1)
            centred("o", s, cx, hy + 2)
        end
    end
    -- A banner across the middle of the field.
    if banner.text then
        local w = min(r.w - 10, max(G.textWidth(banner.text, 2), G.textWidth(banner.sub or "")) + 14)
        local h = banner.sub and 24 or 16
        local by = floor(r.y + r.h * 0.42 - h / 2 + banner.y * (r.h * 0.6))
        if by < r.y + r.h then
            local bx = floor(cx - w / 2)
            G.box(bx, by, w, h, "l")
            G.rect("i", bx, by + h - 2, w, 2)
            local tz = G.textWidth(banner.text, 2) <= w - 6 and 2 or 1
            centred("o", banner.text, cx, by + 3, tz)
            if banner.sub then centred("p", banner.sub, cx, by + 15) end
        end
    end
end

local function drawDrowsy()
    local r = R.drowsy
    local d = Game.drowsiness(S)
    G.text("l", "DROWSY", r.x, r.y + 2)
    local pct = floor(d * 100) .. "%"
    G.text("w", pct, r.x + r.w - G.textWidth(pct), r.y + 2)
    local bx, bw = r.x + 28, r.w - 28 - 20
    G.box(bx, r.y + 1, bw, 7, "v")
    local fill = floor(bw * d)
    if fill > 0 then
        G.rect("l", bx, r.y + 1, fill, 7)
        G.rect("w", bx, r.y + 1, fill, 1)
        for x = bx + 10, bx + fill - 1, 12 do G.rect("i", x, r.y + 1, 2, 7) end
        -- Heavy near the end: the bar itself breathes.
        if d > 0.85 and not reduced and sin(t * 2.6) > 0 then G.rect("i", bx, r.y + 6, fill, 2) end
    end
end

local function drawMode()
    local r = R.mode
    local buttons = { { "1", "X1" }, { "10", "X10" }, { "max", "MAX" } }
    if dreamsOpen() then buttons[4] = { "dream", "DREAMS" } end
    local nb = #buttons
    local w = floor((r.w - (nb - 1) * 2) / nb)
    for i, m in ipairs(buttons) do
        local x = r.x + (i - 1) * (w + 2)
        local on = (tab == "dream") == (m[1] == "dream") and (m[1] == "dream" or S.buyMode == m[1])
        if m[1] == "dream" then
            G.box(x + 1, r.y + 1, w - 2, r.h - 2, on and "y" or "v", on and "o" or "i")
            if on then G.rect("h", x + 1, r.y + r.h - 2, w - 2, 1) end
            centred(on and "o" or "y", m[2], x + w / 2, r.y + 4)
            -- Something to buy with Dream Points: a gold star in the corner.
            if not on and dreamAffordable() and (reduced or sin(t * 3.4) > -0.3) then
                G.art({ ".y.", "yyy", ".y." }, x + w - 6, r.y + 2)
            end
            -- A restless night waiting that you haven't looked at: a rose mark.
            local waiting = waitingRestless()
            if not on and waiting and not restlessSeen[waiting.id] and (reduced or sin(t * 4) > -0.5) then
                G.art({ "r", "r", "r", ".", "r" }, x + 4, r.y + 3)
            end
        else
            G.box(x + 1, r.y + 1, w - 2, r.h - 2, on and "l" or "v", on and "o" or "p")
            if on then G.rect("i", x + 1, r.y + r.h - 2, w - 2, 1) end
            centred(on and "o" or "l", m[2], x + w / 2, r.y + 4)
        end
    end
end

local function describeDream(it)
    local o = S.dream[it.id]
    local d = it.desc:upper()
    if it.id == "sleepwalk" then
        return o > 0 and ("TAPS " .. Game.autoTaps(S) .. " A SECOND FOR YOU. " .. o .. "/" .. it.max) or d
    elseif it.id == "nightShift" then
        if o == 0 then return d .. ", FROM THE DOG UP" end
        local top = Game.GENS[math.min(#Game.GENS, it.tiers * o)]
        return "BUYS HELPERS UP TO THE " .. top.name:upper() .. ". " .. o .. "/" .. it.max
    elseif it.id == "warmBed" then
        if o == 0 then return d end
        return "KEEPS " .. floor(it.keep * o * 100 + 0.5) .. "% OF YOUR HELPERS EACH NIGHT. " .. o .. "/" .. it.max
    elseif it.id == "lightSleeper" then
        if o == 0 then return d .. ". GOLDEN SHEEP TWICE AS OFTEN" end
        return "YOUR TAPS COUNT " .. floor(it.tapShare * o * 100 + 0.5) .. "% OF A SECOND. GOLDEN SHEEP X2. " .. o .. "/" .. it.max
    elseif it.id == "heavySleeper" then
        if o == 0 then return d end
        return "HELPERS X" .. (("%.2f"):format(Game.helperMult(S)):gsub("%.?0+$", "")) .. ". NO GOLDEN SHEEP. " .. o .. "/" .. it.max
    elseif it.mult then
        return d .. ". NOW X" .. N.format(Game.dreamMult(S, it) ^ o)
    elseif it.add then
        return d .. ". NOW X" .. (("%.2f"):format(1 + it.add * o):gsub("%.?0+$", ""))
    end
    return d
end

local function describe(it)
    if it.kind == "dream" then return describeDream(it) end
    local o = S.owned[it.id]
    if it.kind == "gen" then
        local each = N.mul(N.from(it.rate * Game.helperMult(S)), Game.globalMult(S))
        -- A helper on the chain says what it builds before what it counts.
        if o > 0 and it.builds then
            local below = Game.GENS[it.index - 1]
            return "BUILDS " .. N.format(Game.builds(S, it.id), true) .. " " .. below.name:upper() .. "/S. "
                .. N.format(Game.genRate(S, it.id), true) .. "/S"
        end
        if o > 0 then return "+" .. N.format(each, true) .. "/S EACH. " .. N.format(Game.genRate(S, it.id), true) .. "/S" end
        return it.desc:upper() .. ". +" .. N.format(each, true) .. "/S"
    elseif it.kind == "tap" then
        return it.desc:upper() .. ". NOW " .. N.format(Game.tapValue(S)) .. " A TAP"
    end
    if it.max then return it.desc:upper() .. ". " .. o .. "/" .. it.max end
    return it.desc:upper() .. ". NOW X" .. (("%.2f"):format(1 + Game.comfortAdd(S, it) * o):gsub("%.?0+$", ""))
end

local function drawCard(row, x, y, w)
    local it = row.item
    local h = row.h
    if it.teaser then
        G.box(x + 1, y + 1, w - 2, h - 2, "v", "p")
        for i = x + 1, x + w - 2, 4 do G.rect("n", i, y, 2, 1); G.rect("n", i, y + h - 1, 2, 1) end
        G.box(x + 4, y + 4, 28, h - 8, "o", "p")
        G.text("p", "?", x + 17, y + 12)
        G.text("s", "???", x + 37, y + 6)
        local prev = Game.GENS[Game.BY_ID[it.id].index - 1]
        G.text("s", ("OWN A " .. prev.name .. " TO FIND OUT"):upper(), x + 37, y + 15)
        return
    end
    local f = fxCards[it.id] or {}
    local q = Game.quote(S, it.id, S.buyMode)
    local afford = q.ok and not S.asleep
    local grow = floor((f.pop or 0) * 2 + 0.5)
    local dx = floor(sin((f.shake or 0) * 30) * 2 * (f.shake or 0) + 0.5) + floor((f.reveal or 0) * w)
    x, y, w, h = x - grow + dx, y - grow, w + grow * 2, h + grow * 2
    -- Affordable, it breathes: a lavender ring that comes and goes.
    if afford and not reduced and sin(t * 3.4 + (row.y or 0) * 0.05) > 0 then G.box(x, y, w, h, "l", "l") end
    local fill = afford and "w" or (q.maxed and "l" or "s")
    G.box(x + 1, y + 1, w - 2, h - 2, fill)
    G.rect(afford and "b" or "p", x + 1, y + h - 2, w - 2, 1)
    -- The picture, in its own box.
    G.box(x + 4, y + 4, 28, h - 8, afford and "l" or "b")
    love.graphics.push("all")
    love.graphics.intersectScissor(x + 4, y + 4, 28, h - 8)
    Scene.icon(it.id, x + 18, y + h / 2)
    love.graphics.pop()
    -- The price: gold when it can be paid.
    local cost = q.maxed and "DONE" or (N.format(q.cost) .. (q.dp and " DP" or ""))
    local qty = q.maxed and "" or (q.turn and "TURN OVER") or (q.dp and ("LV " .. Game.have(S, it.id) + 1) or ("X" .. q.n))
    local pw = max(G.textWidth(cost), G.textWidth(qty)) + 8
    local px = x + w - pw - 4
    G.box(px, y + 4, pw, h - 8, afford and "y" or (q.maxed and "l" or "b"))
    G.text("o", cost, px + pw - 4 - G.textWidth(cost), y + 7)
    G.text(afford and "h" or "p", qty, px + pw - 4 - G.textWidth(qty), y + 15)
    -- The name, how many, what it does.
    local ink = afford and "o" or "o"
    local tx = x + 37
    G.text(ink, it.name:upper(), tx, y + 5)
    local have = Game.have(S, it.id)
    local built = it.kind == "gen" and floor(S.made[it.id]) or 0
    if have > 0 and not (it.kind == "dream" and it.max == 1) then
        G.text("p", "X" .. have .. (built > 0 and ("+" .. N.format(built)) or ""), tx + G.textWidth(it.name) + 5, y + 5)
    end
    -- Bought by the Dream shop's automation: it says so.
    if Game.automated(S, it.id) then G.text("i", "AUTO", px - 4 - G.textWidth("AUTO"), y + 5) end
    local lines = G.wrap(describe(it), px - tx - 4)
    for i = 1, min(2, #lines) do G.text("p", lines[i], tx, y + 8 + i * 6) end
end

-- A restless night's card: what it asks, what it gives, and where you are with it.
local function drawRestless(row, x, y, w)
    local c, h = row.challenge, row.h
    if row.locked then
        G.box(x + 1, y + 1, w - 2, h - 2, "v", "p")
        for i = x + 1, x + w - 2, 4 do G.rect("n", i, y, 2, 1); G.rect("n", i, y + h - 1, 2, 1) end
        G.box(x + 4, y + 4, 28, h - 8, "o", "p")
        G.text("p", "?", x + 17, y + 12)
        G.text("s", "???", x + 37, y + 6)
        G.text("s", "OPENS AFTER NIGHT " .. c.opens, x + 37, y + 15)
        return
    end
    local done, on = Game.done(S, c.id), S.challenge == c.id
    G.box(x + 1, y + 1, w - 2, h - 2, done and "l" or (on and "y" or "w"))
    G.rect(on and "h" or "b", x + 1, y + h - 2, w - 2, 1)
    G.box(x + 4, y + 4, 28, h - 8, done and "b" or "l")
    love.graphics.push("all")
    love.graphics.intersectScissor(x + 4, y + 4, 28, h - 8)
    Scene.icon(c.id, x + 18, y + h / 2)
    love.graphics.pop()
    local label = done and "DONE" or (on and "GIVE UP" or "START")
    local pw = G.textWidth(label) + 8
    local px = x + w - pw - 4
    G.box(px, y + 4, pw, h - 8, done and "l" or (on and "l" or "y"))
    G.text("o", label, px + 4, y + 11)
    local tx = x + 37
    G.text("o", c.name:upper(), tx, y + 5)
    local say = (done and "YOURS: " .. c.reward or c.rule):upper()
    if on then say = "NOW. " .. say end
    local lines = G.wrap(say, px - tx - 4)
    for i = 1, min(2, #lines) do G.text("p", lines[i], tx, y + 8 + i * 6) end
end

local function drawShop()
    local r = R.shop
    love.graphics.push("all")
    love.graphics.setScissor(r.x - 3, r.y, r.w + 6, r.h)
    local oy = r.y - floor(scroll)
    for _, row in ipairs(rows) do
        local y = oy + row.y
        if y + (row.h or 10) >= r.y and y < r.y + r.h then
            if row.header then
                G.text("i", row.header, r.x + 2, y + 2)
                if row.fold then G.text("l", "HIDE", r.x + r.w - 2 - G.textWidth("HIDE"), y + 2) end
            elseif row.fold then
                G.box(r.x + 1, y + 1, r.w - 2, row.h - 2, "v", "i")
                G.text("l", "ALL " .. row.n .. " ON AUTO", r.x + 6, y + 5)
                G.text("y", "SHOW", r.x + r.w - 6 - G.textWidth("SHOW"), y + 5)
            elseif row.challenge then drawRestless(row, r.x, y, r.w)
            else drawCard(row, r.x, y, r.w) end
        end
    end
    love.graphics.pop()
    -- A scroll mark when there is more than fits.
    if maxScroll() > 0 then
        local th = max(10, floor(r.h * r.h / contentH))
        local ty = r.y + floor((r.h - th) * scroll / maxScroll())
        G.rect("p", r.x + r.w + 1, ty, 1, th)
    end
end

local DITHER -- a half-dark veil over everything under a dialog
local function veil()
    if not DITHER or DITHER:getWidth() ~= vw or DITHER:getHeight() ~= vh then
        local data = love.image.newImageData(vw, vh)
        local c = G.C.n
        for y = 0, vh - 1 do
            for x = 0, vw - 1 do if G.dither(x, y, 0.6) then data:setPixel(x, y, c[1], c[2], c[3], 1) end end
        end
        DITHER = love.graphics.newImage(data)
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(DITHER, 0, 0)
end

local function drawModal()
    local m = modal
    if m.night then
        -- The ending: the whole screen goes to night, and the stars come out.
        G.rect("n", 0, 0, vw, vh)
        local rnd = love.math.newRandomGenerator(5)
        for _ = 1, floor(vw * vh / 260) do
            local x, y, ph = rnd:random(0, vw - 1), rnd:random(0, vh - 1), rnd:random() * 6.3
            local tw = sin(t * 1.1 + ph)
            if tw > -0.6 then G.rect(tw > 0.5 and "w" or "i", x, y, 1, 1) end
        end
    else
        veil()
    end
    local w = min(vw - 16, 220)
    local inner = w - 16
    local lines = {}
    for _, l in ipairs(m.lines) do
        if l == "" then lines[#lines + 1] = "" else
            for _, s in ipairs(G.wrap(l, inner)) do lines[#lines + 1] = s end
        end
    end
    local tz = G.textWidth(m.title, 2) <= inner and 2 or 1
    local titleLines = G.wrap(m.title, inner, tz)
    local bz = G.textWidth(m.big, 2) <= inner and 2 or 1
    local h = 10 + #titleLines * (5 * tz + 4) + 4 + #lines * 7 + 6 + 5 * bz + 8 + 20
    local x, y = floor((vw - w) / 2), floor((vh - h) / 2 + m.y)
    local fill, ink, soft = m.night and "v" or "w", m.night and "l" or "o", m.night and "w" or "p"
    if m.night then
        -- The moon, and one sheep asleep on top of it all, breathing, Zzz rising.
        local Models = require "models"
        local function blit(sp, bx, by)
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(sp.img, floor(bx) - sp.oi, floor(by) - sp.oj)
        end
        blit(Models.moon(9), vw / 2 + 34, y - 34)
        blit(Models.sheep(math.pi - 0.35, (not reduced and sin(t * 1.2) > 0) and 1 or 0, 0, "pj", true), vw / 2 - 6, y - 1)
        if not reduced then
            for i = 0, 2 do
                local p = (t * 0.4 + i / 3) % 1
                G.label("l", "Z", floor(vw / 2 + 2 + p * 14 + sin(p * 9) * 2), floor(y - 20 - p * 22), p > 0.5 and 2 or 1,
                    1 - max(0, p - 0.7) / 0.3)
            end
        end
    end
    G.box(x, y, w, h, fill, m.night and "i" or "o")
    G.rect(m.night and "n" or "b", x, y + h - 2, w, 2)
    local cy = y + 8
    for _, s in ipairs(titleLines) do centred(ink, s, vw / 2, cy, tz); cy = cy + 5 * tz + 4 end
    cy = cy + 4
    -- The big number goes after the first line (what happened), before the rest.
    for i, s in ipairs(lines) do
        centred(soft, s, vw / 2, cy); cy = cy + 7
        if i == 1 then
            cy = cy + 4
            centred(m.night and "y" or "p", m.big, vw / 2, cy, bz)
            cy = cy + 5 * bz + 6
        end
    end
    local bw = G.textWidth(m.button) + 20
    local br = rect(vw / 2 - bw / 2, y + h - 22, bw, 14)
    -- With a way out: the two buttons side by side, the quiet one first.
    if m.cancel then
        local cw = G.textWidth(m.cancel) + 14
        local cx0 = floor(vw / 2 - (cw + bw + 6) / 2)
        local cr = rect(cx0, y + h - 22, cw, 14)
        G.box(cr.x, cr.y, cr.w, cr.h, m.night and "n" or "s", m.night and "i" or "p")
        centred(m.night and "l" or "o", m.cancel, cr.x + cr.w / 2, cr.y + 4)
        m.cancelRect = cr
        br = rect(cx0 + cw + 6, y + h - 22, bw, 14)
    end
    local pulse = (not reduced and sin(t * 3) > 0) and 1 or 0
    G.box(br.x - pulse, br.y - pulse, br.w + pulse * 2, br.h + pulse * 2, "y", "y")
    G.box(br.x + 1, br.y + 1, br.w - 2, br.h - 2, "l")
    G.rect("i", br.x + 1, br.y + br.h - 2, br.w - 2, 1)
    centred("o", m.button, br.x + br.w / 2, br.y + 4)
    m.buttonRect = br
end

-- The way in: the field under a night of stars and the moon, the words, then
-- the night lifts in dithered dust.
local function drawIntro()
    local p = intro.t
    local Models = require "models"
    if p < INTRO_FADE then
        G.rect("n", 0, 0, vw, vh)
        local rnd = love.math.newRandomGenerator(5)
        for _ = 1, floor(vw * vh / 260) do
            local x, y, ph = rnd:random(0, vw - 1), rnd:random(0, vh - 1), rnd:random() * 6.3
            local tw = sin(t * 1.1 + ph)
            if tw > -0.6 then G.rect(tw > 0.5 and "w" or "i", x, y, 1, 1) end
        end
        local m = Models.moon(9)
        local rise = lume.clamp(p / 1.6, 0, 1)
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(m.img, floor(vw / 2 + 34) - m.oi, floor(vh * 0.3 - (1 - rise) ^ 2 * 40) - m.oj)
        local sp = Models.sheep(math.pi - 0.35, (not reduced and sin(t * 1.2) > 0) and 1 or 0, 0, "pj", true)
        love.graphics.draw(sp.img, floor(vw / 2 - 6) - sp.oi, floor(vh * 0.3 + 30) - sp.oj)
        local function say(text, at, y, z, k)
            if p > at then
                local dens = lume.clamp((p - at) / 0.5, 0, 1)
                G.label(k, text, floor(vw / 2 - G.textWidth(text, z) / 2), y, z, reduced and 1 or dens, "o")
            end
        end
        say("YOU CAN'T SLEEP.", 1.0, floor(vh * 0.55), 1, "l")
        say("SO YOU COUNT SHEEP.", 1.9, floor(vh * 0.55) + 10, 1, "c")
        say("COUNTING SHEEP", 2.8, floor(vh * 0.55) + 26, 2, "y")
    else
        local pts = {}
        local d = 1 - (p - INTRO_FADE) / (INTRO_END - INTRO_FADE)
        for y = 0, vh - 1 do
            for x = 0, vw - 1 do if G.dither(x, y, d) then G.plot(pts, x, y) end end
        end
        G.points("n", pts)
    end
end

-- Draws everything but the field's own picture, which main lays first.
function UI.draw()
    UI.drawScreen()
    if intro then drawIntro() end
end

function UI.drawScreen()
    if lucid() and not modal then return LUI.draw() end
    if later() then return laterUI().draw() end
    local r = R.scene
    -- The field, in its frame.
    G.box(r.x, r.y, r.w, r.h, "n")
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(Scene.draw(S), r.x, r.y)
    G.rect("o", r.x, r.y + r.h, r.w, 2)
    drawTop()
    drawHud()
    drawDrowsy()
    drawMode()
    drawShop()
    for _, b in ipairs(bits) do G.box(floor(b.x), floor(b.y), 2, 2, b.k) end
    if modal then drawModal() end
end

return UI
