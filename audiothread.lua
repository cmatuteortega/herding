-- The sound worker: renders every sound and pad layer it is asked for (synth.lua)
-- and hands the SoundData back, so the main thread never waits on the synth.
require "love.sound"
require "love.math"
require "love.timer"
local Synth = require "synth"

local jobs, done = love.thread.getChannel("synth.jobs"), love.thread.getChannel("synth.done")
while true do
    local name = jobs:demand()
    if name == "quit" then return end
    local t0 = love.timer.getTime()
    done:push({ name = name, data = Synth.make(name), took = love.timer.getTime() - t0 })
end
