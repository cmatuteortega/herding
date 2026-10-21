-- Every sound, made at load from nothing: no sample files. The sounds and
-- the synth that makes them are synth.lua (underroot's synth); a worker thread
-- renders them (audiothread.lua) and this side plays them, each from a small
-- pool with a little pitch wobble, so a hundred taps aren't one tap a hundred
-- times.
--
-- Under it all runs the pad: a 32-second lullaby (four chords, eight seconds
-- each) in six layers, every layer the same length and started together, so
-- they stay in step. The base plays from the first tap; each Lullaby bought
-- brings in the next layer:
--   1 the third and the seventh of each chord
--   2 a music box through an echo
--   3 a high shimmer
--   4 a breathing sub bass
--   5 a slow bell melody over the top
-- As you get drowsy the whole pad sinks a little in pitch and quietens.
--
-- Nothing plays until the first tap.

local Synth = require "synth"

local floor, min, max = math.floor, math.min, math.max
local RATE = Synth.RATE

local Audio = { on = false, muted = false, started = false }

local pools, last = {}, {}
local layers = {} -- [0..5] = { src, vol }
local clock = 0
local combo, lastTap = 0, -1
local lullabies, drowsy, asleep, lucid, void = 0, 0, false, false, false
local jobs, done

-- Gets ready to make every sound; nothing at all if there's no audio device.
-- The effects are asked for first, the taps before anything, the pad last.
function Audio.init()
    if not (love.audio and love.sound and love.thread) then return false end
    local ok = pcall(function()
        love.audio.newSource(love.sound.newSoundData(1, RATE, 16, 1), "static")
    end)
    if not ok then return false end
    jobs, done = love.thread.getChannel("synth.jobs"), love.thread.getChannel("synth.done")
    local names = {}
    for name in pairs(Synth.DEFS) do names[#names + 1] = name end
    table.sort(names, function(a, b)
        local ta, tb = a:sub(1, 3) == "tap", b:sub(1, 3) == "tap"
        if ta ~= tb then return ta end
        return a < b
    end)
    for _, name in ipairs(names) do pools[name] = { def = Synth.DEFS[name] }; jobs:push(name) end
    for i = 0, 5 do layers[i] = { vol = 0 }; jobs:push(i) end
    love.thread.newThread("audiothread.lua"):start()
    Audio.on = true
    return true
end

-- Quitting: the worker is told to stop.
function Audio.stop()
    if jobs then jobs:clear(); jobs:push("quit") end
end

-- What the worker has finished, turned into sources.
local function collect()
    local job = done:pop()
    while job do
        local src = love.audio.newSource(job.data, "static")
        if type(job.name) == "number" then
            src:setLooping(true)
            src:setVolume(0)
            layers[job.name].src = src
        else
            pools[job.name].srcs, pools[job.name].next = { src }, 1
        end
        job = done:pop()
    end
end

local function ready()
    for i = 0, 5 do if not layers[i].src then return false end end
    return true
end

function Audio.play(name, pitch, vol)
    if not Audio.on or Audio.muted or not Audio.started then return end
    local p = pools[name]
    if not p or not p.srcs then return end -- not rendered yet: silence beats a stall
    local def = p.def
    if last[name] and clock - last[name] < (def.gap or 0.03) then return end
    last[name] = clock
    local src
    for _, s in ipairs(p.srcs) do if not s:isPlaying() then src = s break end end
    if not src then
        if #p.srcs < (def.poly or 2) then
            src = p.srcs[1]:clone()
            p.srcs[#p.srcs + 1] = src
        else
            src = p.srcs[p.next]
            p.next = p.next % #p.srcs + 1
            src:stop()
        end
    end
    local wob = def.wob or 0.03
    src:setPitch((pitch or 1) * (1 + (love.math.random() * 2 - 1) * wob))
    src:setVolume(max(0, min(1, (def.vol or 0.5) * (vol or 1))))
    src:play()
end

-- The game's cues, by name.
function Audio.cue(name, data)
    if name == "tap" then
        combo = clock - lastTap < 0.45 and min(combo + 1, 9) or 0
        lastTap = clock
        Audio.play("tap" .. (combo + 1))
    elseif name == "buy" then
        Audio.play("buy", 1 + (data and data.tier or 0) * 0.06)
        if data and data.first then Audio.play("first") end
    else
        Audio.play(name)
    end
end

-- The first tap: from now on there is sound.
function Audio.start() Audio.started = true end

function Audio.setMuted(m) Audio.muted = m end
function Audio.setLullabies(n) lullabies = n end
function Audio.setDrowsy(d) drowsy = d end
function Audio.setAsleep(a) asleep = a end
-- The lucid dream: the chords, the music box and the shimmer only, quieter
-- and a little lower, whatever the Lullabies were.
function Audio.setLucid(on) lucid = on end
-- The void: only the breathing sub bass and the lowest chord tones, low and far.
function Audio.setVoid(on) void = on end

-- Each frame: the layers ease toward where they should be.
function Audio.update(dt)
    clock = clock + dt
    if Audio.on then collect() end
    if not Audio.on or not Audio.started or not ready() then return end
    local master = Audio.muted and 0 or 1
    for i = 0, 5 do
        local l = layers[i]
        local want = (not asleep and i <= lullabies) and master * (0.7 - drowsy * 0.2) or 0
        if lucid then want = (i <= 3 and i ~= 1) and master * 0.4 or 0 end
        if void then want = (i == 0 or i == 4) and master * 0.3 or 0 end
        local speed = asleep and 0.4 or 0.8
        l.vol = l.vol + (want - l.vol) * min(1, dt * speed)
        if not l.src:isPlaying() then
            -- Every layer starts at once, so they stay in step.
            for k = 0, 5 do layers[k].src:play() end
        end
        l.src:setVolume(l.vol)
        -- Sleepier, lower: the whole pad together, so it stays in tune with itself.
        l.src:setPitch(void and 0.84 or (lucid and 0.94 or (1 - drowsy * 0.06)))
    end
end

-- The game out of sight: everything stops where it is, and picks up after.
local held
function Audio.hide(away)
    if not Audio.on or away == Audio.away then return end
    Audio.away = away
    if away then held = love.audio.pause()
    elseif held then love.audio.play(held); held = nil end
end

-- How far the worker has got: sounds ready, layers ready, and whether the pad plays.
function Audio.status()
    local n, l = 0, 0
    for _, p in pairs(pools) do if p.srcs then n = n + 1 end end
    for i = 0, 5 do if layers[i] and layers[i].src then l = l + 1 end end
    return n, l, l == 6 and layers[0].src:isPlaying()
end

-- Dev: every sound and every layer of the pad written as a .wav into the
-- save directory (sounds/), to listen to.
function Audio.dump()
    local function u32(v) return string.char(v % 256, floor(v / 256) % 256, floor(v / 65536) % 256, floor(v / 16777216) % 256) end
    local function u16(v) return string.char(v % 256, floor(v / 256) % 256) end
    local function wav(data)
        local n = data:getSampleCount()
        return "RIFF" .. u32(36 + n * 2) .. "WAVEfmt " .. u32(16) .. u16(1) .. u16(1) .. u32(RATE) .. u32(RATE * 2)
            .. u16(2) .. u16(16) .. "data" .. u32(n * 2) .. data:getString()
    end
    love.filesystem.createDirectory("sounds")
    for name in pairs(Synth.DEFS) do love.filesystem.write("sounds/" .. name .. ".wav", wav(Synth.make(name))) end
    for i = 0, 5 do love.filesystem.write("sounds/pad-" .. i .. ".wav", wav(Synth.make(i))) end
    return love.filesystem.getSaveDirectory() .. "/sounds"
end

return Audio
