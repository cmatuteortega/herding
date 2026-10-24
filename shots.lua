-- Dev: `love . --shots` plays a few scripted moments of a night at a phone's
-- size and a computer's, writes each as a picture to the save directory, and
-- quits. The save is left alone.

local Game = require "game"
local Lucid = require "lucid.game"
local LUI = require "lucid.ui"
local Astral = require "astral.game"
local AUI = require "astral.ui"
local Scene = require "scene"
local flux = require "lib.flux"

local Shots = {}

local function preset(total, owned, extra)
    local s = Game.fresh()
    s.runTotal, s.allTime, s.sheep = total, total, total / 3
    for k, v in pairs(owned or {}) do s.owned[k] = v end
    s.stage = Game.stageOf(s)
    s.taps = 50
    s.muted = true
    for k, v in pairs(extra or {}) do
        if k == "dream" or k == "made" or k == "done" then for id, n in pairs(v) do s[k][id] = n end else s[k] = v end
    end
    return s
end

-- Phase 2, `minutes` in: dimensions bought, a farm built round a Haystack.
local function lucidAt(minutes, flow)
    local s = preset(0, {}, { dreams = 19, dreamPoints = 750, dreamEarned = 7000 })
    s.phase = "lucid"
    s.lucid = Lucid.fresh(s)
    s.dreamPoints = 0
    local L = s.lucid
    L.intro, L.flow, L.goldenIn, L.nightmareIn = false, flow, 1e9, 1e9
    L.dp, L.sheep = 1e3 * minutes ^ 3, 1e4 * 10 ^ minutes
    for k = 1, math.min(6, minutes + 1) do
        L.dims[k].bought = math.floor(math.max(1, 22 - k * 3) * minutes / 2) + 1
        L.dims[k].amount = L.dims[k].bought * 10 ^ (6 - k)
    end
    local town = { { 3, 3, "plaza" }, { 2, 3, "clock" }, { 4, 3, "clock" }, { 3, 2, "inn" }, { 3, 4, "bakery" },
        { 2, 2, "hut" }, { 4, 2, "mill" }, { 2, 4, "fold" }, { 4, 4, "fountain" } }
    for i = 1, math.min(#town, minutes + 2) do
        local b = town[i]
        L.grid[Lucid.cell(b[1], b[2])], L.level[Lucid.cell(b[1], b[2])] = b[3], 1
        L.built[b[3]] = L.built[b[3]] + 1
    end
    if minutes >= 5 then
        L.open[Lucid.cell(3, 1)], L.open[Lucid.cell(1, 3)] = true, true
        L.plots = 2
        L.level[Lucid.cell(2, 3)] = 3
        L.built.clock = L.built.clock + 2
    end
    L.runAcc = 0.6
    return s
end

-- Phase 3, `stage` along (0 to 5): the cord longer, some dreamers, stars lit,
-- upgrades grown. `out`: projecting.
local function astralAt(stage, out)
    local s = lucidAt(8, true)
    local L = s.lucid
    L.gate, L.sheepTotal, L.runs, L.best = true, 1e90, 2e6, 900
    for _, c in ipairs(Lucid.CHALLENGES) do L.done[c.id] = true end
    s.allTime = 3e14
    Game.goAstral(s)
    local P = s.astral
    P.intro, P.cometIn = false, 1e9
    P.ether = 50 * 30 ^ stage
    P.reach = ({ 0, 400, 2e4, 7e5, 8e6, 2e7 })[stage + 1]
    P.planeSeen = Astral.planeAt(P.reach)
    for i, n in ipairs({ { cord = 0 }, { cord = 4, drift = 2, thread = 1, lens = 2 },
        { cord = 9, drift = 4, thread = 1, trance = 1, close = 2, lens = 4, calm = 1 },
        { cord = 14, drift = 6, thread = 1, trance = 1, close = 3, lens = 6, calm = 2, librarian = 2 },
        { cord = 19, drift = 8, thread = 1, trance = 1, close = 4, lens = 8, calm = 3, librarian = 3, farsight = 1 },
        { cord = 24, drift = 10, thread = 1, trance = 1, close = 5, lens = 10, calm = 4, librarian = 4, farsight = 2 } }) do
        if i == stage + 1 then for id, r in pairs(n) do P.ups[id] = r end end
    end
    for k, d in ipairs(Astral.DREAMERS) do
        if P.reach >= d.at then P.dreamers[k] = math.max(0, 30 - k * 4 - (5 - stage) * 3) end
    end
    for k, c in ipairs(Astral.CONSTELLATIONS) do
        if k <= stage + 1 then P.lit[c.id] = #c.stars end
        if k == stage + 2 then P.lit[c.id] = 2 end
    end
    if stage >= 5 then for _, c in ipairs(Astral.CONSTELLATIONS) do P.lit[c.id] = #c.stars end end
    P.autoOff = true
    if out then Astral.project(P) end
    return s
end

local MOMENTS = {
    { "1-dusk", function() local s = Game.fresh(); s.muted = true; return s end, 6 },
    { "2-field", function() return preset(2e4, { dog = 8, meadow = 6, pen = 2, tapPower = 6, betterFence = 1, barn = 1 }) end, 4 },
    { "3-factory", function() return preset(5e6, { dog = 20, meadow = 15, pen = 10, mill = 5, betterFence = 3, tapPower = 20, barn = 2, lullaby = 1 }) end, 4 },
    { "4-orbit", function()
        return preset(8e8, { dog = 40, meadow = 40, pen = 30, mill = 20, drones = 12, os = 4, betterFence = 6, tapPower = 60, barn = 6, lullaby = 4 },
            { golden = { t = 3, lane = 0.4 }, dreamPoints = 12 })
    end, 3 },
    { "5-offline", function() return preset(1e5, { dog = 10, meadow = 5 }, { lastSeen = os.time() - 3 * 3600 }) end, 0, "away" },
    { "6-asleep", function() return preset(1.4999e9, { dog = 40, os = 6, lullaby = 5, drones = 10, mill = 10 }, { runTime = 600 }) end, 0, "sleep" },
    { "7-dreams", function()
        return preset(3e3, { dog = 3, tapPower = 2 }, { dreams = 3, dreamPoints = 26, dreamEarned = 90,
            dream = { sleepwalk = 2, nightShift = 1, deepSleep = 1, warmBed = 1 } })
    end, 0, "dreams" },
    { "8-automatic", function()
        return preset(4e7, { dog = 30, meadow = 25, pen = 15, mill = 8, tapPower = 15, betterFence = 3, barn = 3, lullaby = 2 },
            { dreams = 7, dreamPoints = 12, dreamEarned = 400, golden = { t = 0.5, lane = 0.5 },
                dream = { sleepwalk = 5, nightShift = 3, goldenDreams = 1, sleepTalk = 1, tuckedIn = 1, deepSleep = 3, dreamCatcher = 1 } })
    end, 0 },
    { "9-lucid", function()
        return preset(1.4999e9, { dog = 40, os = 6, lullaby = 5, drones = 10, mill = 10 },
            { runTime = 0.8, dreams = 21, dreamEarned = 9000, dream = { sleepwalk = 5, deepSleep = 5 } })
    end, 0, "sleep" },
    { "10-lucid-enter", function()
        local s = preset(0, {}, { dreams = 19, dreamPoints = 750, dreamEarned = 7000 })
        Game.goLucid(s)
        return s
    end, 0, "enter" },
    { "11-ways", function()
        return preset(3e3, { dog = 3, tapPower = 2 }, { dreams = 5, dreamPoints = 40, dreamEarned = 160,
            dream = { sleepwalk = 3, nightShift = 2, deepSleep = 2, warmBed = 1, lightSleeper = 2 }, done = { insomnia = true } })
    end, 0, "dreams-low" },
    { "12-restless", function()
        return preset(6e7, { dog = 30, meadow = 25, pen = 12, mill = 8, drones = 4, tapPower = 15, betterFence = 3, barn = 3 },
            { dreams = 5, dreamEarned = 160, challenge = "shortage", made = { pen = 14.5, mill = 2.2 },
                dream = { sleepwalk = 3, nightShift = 2, deepSleep = 2, heavySleeper = 2 }, done = { insomnia = true } })
    end, 2 },
    { "13-start-restless", function()
        return preset(3e3, { dog = 3 }, { dreams = 5, dreamEarned = 160, done = { insomnia = true } })
    end, 0, "ask" },
    { "14-lucid-dreams", function() return lucidAt(2, false) end, 0, "lucid" },
    { "15-lucid-town", function() return lucidAt(5, false) end, 0, "town" },
    { "16-lucid-flow", function()
        local s = lucidAt(8, true)
        s.lucid.golden = { t = 4, lane = 0.3 }
        s.lucid.effects.frenzy = 18
        return s
    end, 0, "lucid" },
    { "17-nightmare", function()
        local s = lucidAt(5, false)
        s.lucid.nightmareIn = 0.01
        return s
    end, 0, "nightmare" },
    { "19-dream-challenge", function()
        local s = lucidAt(8, true)
        local L = s.lucid
        L.grid[Lucid.cell(3, 1)], L.level[Lucid.cell(3, 1)], L.built.mirror = "mirror", 1, 1
        L.done.stoppedClocks = true
        L.dp, L.sheep = 1e9, 1e40
        Lucid.startChallenge(L, "onlyOne")
        L.counted = 3e9
        return s
    end, 0, "lucid-low" },
    { "20-challenge-ask", function()
        local s = lucidAt(8, true)
        local L = s.lucid
        L.grid[Lucid.cell(3, 1)], L.level[Lucid.cell(3, 1)], L.built.mirror = "mirror", 1, 1
        return s
    end, 0, "challenge-ask" },
    { "21-upgrades", function()
        local s = lucidAt(8, true)
        local L = s.lucid
        L.grid[Lucid.cell(3, 1)], L.level[Lucid.cell(3, 1)], L.built.mirror = "mirror", 1, 1
        L.roots = { spring = 3, starbag = 1, bell = 2, architect = 2, well = 1, surveyor = 1, totem = 1, quickdog = 1 }
        L.done.season, L.done.stoppedClocks = true, true
        L.dp = 2e4
        return s
    end, 0, "upgrades" },
    { "21b-upgrades-dreams", function()
        local s = lucidAt(8, true)
        local L = s.lucid
        L.grid[Lucid.cell(3, 1)], L.level[Lucid.cell(3, 1)], L.built.mirror = "mirror", 1, 1
        L.done.season, L.done.stoppedClocks = true, true
        L.dp = 2e4
        return s
    end, 0, "upgrades-end" },
    { "25-flock", function()
        local s = lucidAt(5, false)
        s.lucid.flockIn = 0.01
        return s
    end, 0, "lucid" },
    { "26-counting", function()
        local s = lucidAt(5, false)
        s.lucid.flock = { t = 0 }
        Lucid.startSong(s.lucid)
        return s
    end, 0, "count" },
    { "22-climb", function()
        local s = lucidAt(5, false)
        s.lucid.best = 340
        return s
    end, 0, "climb" },
    { "22a-lucidity", function()
        local s = lucidAt(8, true)
        local L = s.lucid
        L.grid[Lucid.cell(3, 1)], L.level[Lucid.cell(3, 1)], L.built.mirror = "mirror", 1, 1
        L.done.season, L.done.stoppedClocks, L.done.skyHigh = true, true, true
        L.dp, L.sheep = 4e8, 1e95
        return s
    end, 0, "town-end" },
    { "22b-sheep-os", function()
        local s = lucidAt(8, true)
        local L = s.lucid
        L.grid[Lucid.cell(3, 1)], L.level[Lucid.cell(3, 1)], L.built.mirror = "mirror", 1, 1
        for _, c in ipairs(Lucid.CHALLENGES) do L.done[c.id] = true end
        L.dp, L.sheep = 4e8, 1e95
        return s
    end, 0, "town" },
    { "23-gate", function()
        local s = lucidAt(8, true)
        s.lucid.gate = true
        return s
    end, 0, "gate" },
    { "23b-rain", function()
        local s = lucidAt(8, true)
        s.lucid.gate = true
        return s
    end, 0, "gate-rain" },
    { "23c-astral", function()
        local s = lucidAt(8, true)
        s.lucid.gate = true
        return s
    end, 0, "gate-astral" },
    { "32-astral-home", function() return astralAt(0) end, 0, "astral" },
    { "33-astral-out", function() return astralAt(2, true) end, 0, "astral-out" },
    { "34-astral-stars", function() return astralAt(3, true) end, 0, "astral-stars" },
    { "35-astral-dreamers", function() return astralAt(3) end, 0, "astral-dreamers" },
    { "36-astral-library", function() return astralAt(4) end, 0, "astral-library" },
    { "37-astral-strain", function() return astralAt(4, true) end, 0, "astral-strain" },
    { "37b-astral-snap", function() return astralAt(3, true) end, 0, "astral-snap" },
    { "38-astral-count", function() return astralAt(5) end, 0, "astral-count" },
    { "23d-into-astral", function()
        local s = lucidAt(8, true)
        s.lucid.gate = true
        return s
    end, 0, "gate-through" },
    { "38b-into-beyond", function() return astralAt(5) end, 0, "astral-through" },
    { "39-beyond", function()
        local s = astralAt(5)
        s.astral.cut = true
        Game.goBeyond(s)
        return s
    end, 0, "beyond" },
    { "18-golden-choice", function()
        local s = lucidAt(5, false)
        s.lucid.choosing = true
        return s
    end, 0, "lucid" },
}

-- Seeded dice, for the climb: the same clouds every time.
local seed = 5
local function dice() seed = (seed * 16807) % 2147483647 return seed / 2147483647 end

function Shots.run(UI, fit)
    UI.noSave = true
    local out = {}
    for _, size in ipairs({ { 1080, 2340, "phone" }, { 1280, 720, "desk" } }) do
        love.window.setMode(size[1], size[2], { resizable = true, highdpi = true, usedpiscale = false })
        local vw, vh = fit()
        local canvas = love.graphics.newCanvas(vw, vh)
        for _, m in ipairs(MOMENTS) do
          -- SHOTS=astral: only the moments whose name has that in it.
          if not os.getenv("SHOTS") or m[1]:find(os.getenv("SHOTS"), 1, true) then
            local s = m[2]()
            UI.setState(s)
            Scene.reset()
            Game.events = {}
            if m[4] == "away" then UI.away(os.difftime(os.time(), s.lastSeen)) end
            if m[4] == "enter" then LUI.setState(s); LUI.enter() end
            if s.phase == "lucid" and m[4] ~= "enter" then UI.showLucid() end
            if s.phase == "astral" then UI.showAstral() end
            if s.phase == "beyond" then UI.showBeyond() end
            if m[4] == "astral-stars" then AUI.show("stars") end
            if m[4] == "astral-dreamers" then AUI.show("dreamers") end
            if m[4] == "astral-library" then AUI.show("library") end
            if m[4] == "astral-count" then AUI.leave() end
            if m[4] == "astral-through" then s.astral.paid = true; Astral.cutCord(s.astral) end
            if m[4] == "town" then LUI.show("town", Lucid.cell(2, 3)) end
            if m[4] == "upgrades" then LUI.show("upgrades") end
            if m[4] == "town-end" then LUI.show("town", nil, 1e9) end
            if m[4] == "upgrades-end" then LUI.show("upgrades", nil, 1e9) end
            if m[4] == "climb" then Lucid.hold(s.lucid, 50) end
            if m[4] and m[4]:sub(1, 4) == "gate" then LUI.leave() end
            if m[4] == "challenge-ask" then LUI.askChallenge("season") end
            local r = UI.sceneRect()
            local frames = (m[4] == "sleep" or m[4] == "nightmare") and 400 or (m[4] == "enter" and 170 or 70)
            if m[4] == "climb" then frames = 360 end
            if m[4] == "count" then frames = 250 end
            if m[4] == "gate" then frames = 290 end
            if m[4] == "gate-rain" then frames = 380 end
            if m[4] == "gate-astral" then frames = 545 end
            if m[4] and m[4]:sub(1, 6) == "astral" then frames = 120 end
            if m[4] == "astral-out" or m[4] == "astral-strain" then frames = 260 end
            if m[4] == "astral-snap" then frames = 180 end
            if m[4] == "astral-count" then frames = 560 end
            if m[4] == "beyond" then frames = 330 end
            if m[4] == "gate-through" then frames = 700 end
            if m[4] == "astral-through" then frames = 1100 end
            for i = 1, frames do
                local dt = 1 / 60
                if s.phase == "astral" then
                    Astral.step(s.astral, dt, function() return 0.5 end)
                    if m[4] == "astral-strain" and s.astral.out and i == 200 then s.astral.tug = 0.25 end
                    -- A tug past the limit: the cord snaps, and falls away.
                    if m[4] == "astral-snap" and s.astral.out and i == 150 then s.astral.tug = 2 end
                elseif s.phase == "lucid" then
                    Lucid.step(s.lucid, dt, m[4] == "climb" and dice or function() return 0.5 end)
                    -- The nightmare's dog, circling in behind the flock.
                    if m[4] == "nightmare" and s.lucid.nightmare then
                        Lucid.point(s.lucid, 60 + math.sin(i * 0.05) * 20, 70 + math.cos(i * 0.05) * 30)
                    end
                    -- Counting: on the beat, but for the fourth sheep, let past.
                    local song = s.lucid.song
                    if m[4] == "count" and song then
                        local nxt
                        for _, sh in ipairs(song.sheep) do if not sh.judged then nxt = sh break end end
                        if nxt ~= song.sheep[4] then require("lucid.count").bot(song, 0.03) end
                    end
                    if m[4] == "climb" and s.lucid.bounce.on then
                        Lucid.steer(s.lucid, require("lucid.bounce").bot(s.lucid.bounce))
                    end
                else
                    Game.step(s, dt)
                end
                if m[3] > 0 and i % 7 == 0 and i <= m[3] * 7 then UI.pressed(r.x + r.w / 2, r.y + r.h * 0.8, "shot") end
                if i == 2 and (m[4] == "dreams" or m[4] == "dreams-low") then UI.key("d") end
                -- To the end of FARM, once it's laid out (the scroll stops at the content).
                if i == 3 and m[4] == "town-end" then LUI.show("town", nil, 1e9) end
                if i == 4 and (m[4] == "dreams-low" or m[4] == "lucid-low") then UI.wheel(-40) end
                if i == 2 and m[4] == "ask" then UI.askRestless("wideAwake") end
                if i == 50 and m[4] == nil then
                    -- A purchase, for the pop: the first card that can be paid for.
                    UI.key("1")
                end
                UI.drain()
                Scene.update(dt, s)
                UI.update(dt)
                flux.update(dt)
            end
            love.graphics.setCanvas(canvas)
            love.graphics.clear(require("gfx").C.n)
            UI.draw()
            love.graphics.setCanvas()
            local name = ("shot-%s-%s.png"):format(size[3], m[1])
            canvas:newImageData():encode("png", name)
            out[#out + 1] = love.filesystem.getSaveDirectory() .. "/" .. name
          end
        end
    end
    print(table.concat(out, "\n"))
    love.event.quit()
end

return Shots
