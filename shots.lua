-- Dev: `love . --shots` plays a few scripted moments of a night at a phone's
-- size and a computer's, writes each as a picture to the save directory, and
-- quits. The save is left alone.

local Game = require "game"
local Lucid = require "lucid.game"
local LUI = require "lucid.ui"
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

-- Phase 2, `minutes` in: dimensions bought, a town built round a Plaza.
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
    { "18-golden-choice", function()
        local s = lucidAt(5, false)
        s.lucid.choosing = true
        return s
    end, 0, "lucid" },
}

function Shots.run(UI, fit)
    UI.noSave = true
    local out = {}
    for _, size in ipairs({ { 1080, 2340, "phone" }, { 1280, 720, "desk" } }) do
        love.window.setMode(size[1], size[2], { resizable = true, highdpi = true, usedpiscale = false })
        local vw, vh = fit()
        local canvas = love.graphics.newCanvas(vw, vh)
        for _, m in ipairs(MOMENTS) do
            local s = m[2]()
            UI.setState(s)
            Scene.reset()
            Game.events = {}
            if m[4] == "away" then UI.away(os.difftime(os.time(), s.lastSeen)) end
            if m[4] == "enter" then LUI.setState(s); LUI.enter() end
            if s.phase == "lucid" and m[4] ~= "enter" then UI.showLucid() end
            if m[4] == "town" then LUI.show("town", Lucid.cell(2, 3)) end
            local r = UI.sceneRect()
            local frames = (m[4] == "sleep" or m[4] == "nightmare") and 400 or (m[4] == "enter" and 170 or 70)
            for i = 1, frames do
                local dt = 1 / 60
                if s.phase == "lucid" then
                    Lucid.step(s.lucid, dt, function() return 0.5 end)
                    -- The nightmare's dog, circling in behind the flock.
                    if m[4] == "nightmare" and s.lucid.nightmare then
                        Lucid.point(s.lucid, 60 + math.sin(i * 0.05) * 20, 70 + math.cos(i * 0.05) * 30)
                    end
                else
                    Game.step(s, dt)
                end
                if m[3] > 0 and i % 7 == 0 and i <= m[3] * 7 then UI.pressed(r.x + r.w / 2, r.y + r.h * 0.8, "shot") end
                if i == 2 and (m[4] == "dreams" or m[4] == "dreams-low") then UI.key("d") end
                if i == 4 and m[4] == "dreams-low" then UI.wheel(-40) end
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
    print(table.concat(out, "\n"))
    love.event.quit()
end

return Shots
