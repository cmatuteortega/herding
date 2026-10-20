-- Dev: `love . --shots` plays a few scripted moments of a night at a phone's
-- size and a computer's, writes each as a picture to the save directory, and
-- quits. The save is left alone.

local Game = require "game"
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
        if k == "dream" then for id, n in pairs(v) do s.dream[id] = n end else s[k] = v end
    end
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
            dream = { sleepwalk = 2, nightShift = 1, deepSleep = 1 } })
    end, 0, "dreams" },
    { "8-automatic", function()
        return preset(4e7, { dog = 30, meadow = 25, pen = 15, mill = 8, tapPower = 15, betterFence = 3, barn = 3, lullaby = 2 },
            { dreams = 7, dreamPoints = 12, dreamEarned = 400, golden = { t = 0.5, lane = 0.5 },
                dream = { sleepwalk = 5, nightShift = 3, goldenDreams = 1, sleepTalk = 1, tuckedIn = 1, deepSleep = 3, dreamCatcher = 1 } })
    end, 0 },
    { "9-lucid", function()
        return preset(1.4999e9, { dog = 40, os = 6, lullaby = 5, drones = 10, mill = 10 },
            { runTime = 50, dreams = 8, dreamEarned = 600, dream = { sleepwalk = 5, deepSleep = 3 } })
    end, 0, "sleep" },
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
            local r = UI.sceneRect()
            local frames = m[4] == "sleep" and 400 or 70
            for i = 1, frames do
                local dt = 1 / 60
                Game.step(s, dt)
                if m[3] > 0 and i % 7 == 0 and i <= m[3] * 7 then UI.pressed(r.x + r.w / 2, r.y + r.h * 0.8, "shot") end
                if i == 2 and m[4] == "dreams" then UI.key("d") end
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
