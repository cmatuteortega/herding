-- Counting sheep: phase 2's rhythm game, the oldest way to fall asleep.
-- Now and then a flock lines up at the fence and waits (lucid/game.lua);
-- tap the fence and they jump it one after another, on a beat that
-- quickens. Tap as each one is at the top of its jump: spot on is perfect,
-- near enough is good. A sheep let past, or a tap with no sheep near it,
-- breaks the count. What a song pays, and the tune it leaves, are the
-- game's.
--
-- The beat is heard as well as seen: a tick on every top, two to count you in.
--
-- Pure Lua, no LÖVE: times in seconds from the first sheep's top (the
-- count-in before it is negative).

local C = require "config"

local min, abs = math.min, math.abs
local P = C.dream.count

local Count = { CONFIG = P }

-- A song: `n` sheep, the beat going from `beat` to `beatEnd` seconds.
-- `window` widens what counts as perfect and good (a multiplier).
function Count.new(window)
    local song = {
        t = -P.lead * P.beat, window = window or 1,
        sheep = {}, -- { at = its top, judged = nil, "perfect", "good" or "miss" }
        nextBeat = 1 - P.lead, -- the next tick, as a sheep's index (the count-in is 0 and below)
        combo = 0, best = 0, score = 0, perfect = 0, good = 0, missed = 0,
        done = false, events = {},
    }
    local at = 0
    for i = 1, P.sheep do
        song.sheep[i] = { at = at }
        at = at + P.beat + (P.beatEnd - P.beat) * (i - 1) / (P.sheep - 1)
    end
    return song
end

local function emit(song, e) song.events[#song.events + 1] = e end

-- How near a top counts, perfect and good, in seconds.
function Count.windows(song) return P.perfect * song.window, P.good * song.window end

-- When tick `i` comes: a sheep's top, or the count-in a beat apart before
-- the first (0 a beat before it, -1 two).
local function tickAt(song, i)
    if i >= 1 then return song.sheep[i].at end
    return (i - 1) * P.beat
end

local function judge(song, s, how)
    s.judged = how
    if how == "miss" then
        song.combo, song.missed = 0, song.missed + 1
    else
        song.combo = song.combo + 1
        song.best = math.max(song.best, song.combo)
        song[how] = song[how] + 1
        song.score = song.score + (how == "perfect" and 1 or P.goodScore)
    end
end

-- A tap: the nearest sheep not yet counted, if it's near its top.
function Count.tap(song)
    if song.done then return nil end
    local best, bd
    for _, s in ipairs(song.sheep) do
        if not s.judged then
            local d = abs(song.t - s.at)
            if not bd or d < bd then best, bd = s, d end
        end
    end
    local perfect, good = Count.windows(song)
    if best and bd <= good then
        local how = bd <= perfect and "perfect" or "good"
        judge(song, best, how)
        emit(song, { type = how, combo = song.combo, early = song.t < best.at })
        return how
    end
    song.combo = 0
    emit(song, { type = "stray" })
    return "stray"
end

function Count.step(song, dt)
    if song.done then return end
    song.t = song.t + dt
    -- The ticks: the count-in, then every top.
    while song.nextBeat <= #song.sheep and song.t >= tickAt(song, song.nextBeat) do
        emit(song, { type = "beat", i = song.nextBeat })
        song.nextBeat = song.nextBeat + 1
    end
    -- A sheep past its top and out of reach: missed.
    local _, good = Count.windows(song)
    for _, s in ipairs(song.sheep) do
        if not s.judged and song.t > s.at + good then
            judge(song, s, "miss")
            emit(song, { type = "miss" })
        end
    end
    local last = song.sheep[#song.sheep]
    if last.judged and song.t > last.at + P.beatEnd then
        song.done = true
        emit(song, { type = "songOver" })
    end
end

-- How well it went, 0..1: perfects count whole, goods `goodScore`.
function Count.share(song) return min(1, song.score / #song.sheep) end

-- Where sheep `s` is in its jump, -1 (waiting its turn) .. 0 (the top) ..
-- 1 (landed and gone); a beat each side of the top.
function Count.phase(song, s) return (song.t - s.at) / P.beat end

-- A simple player, for the tests and autoplay: taps on every top, `late`
-- seconds out. Call it every step; it returns true when it tapped.
function Count.bot(song, late)
    for _, s in ipairs(song.sheep) do
        if not s.judged and song.t >= s.at + (late or 0) then
            Count.tap(song)
            return true
        end
    end
    return false
end

return Count
