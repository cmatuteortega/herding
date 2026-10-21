-- The synth, underroot's (src/sfx.lua there): a sound is a few voices mixed,
-- each an oscillator with its pitch swept, a low or high pass, vibrato and
-- tremolo, and an envelope that opens over `a` seconds and dies away as a power
-- curve. Rendered into SoundData off the main thread (audiothread.lua), so a
-- 32-second pad never costs a frame.
--
-- Needs only love.sound and love.math, so the thread can require it.

local floor, min, max, abs, sin, exp = math.floor, math.min, math.max, math.abs, math.sin, math.exp
local TAU = 2 * math.pi
local RATE = 22050

local Synth = { RATE = RATE }

local function midi(n) return 440 * 2 ^ ((n - 69) / 12) end
Synth.midi = midi

local function voice(v, out, rng)
    local start = floor((v.at or 0) * RATE)
    local len = max(1, floor(v.dur * RATE))
    local f0, f1 = v.f0 or 440, v.f1 or v.f0 or 440
    local bend = v.bend or 1
    local wave = v.wave or "sine"
    local a = v.a or 0.004
    local curve = v.curve or 2
    local vol = v.vol or 1
    local lp0, lp1 = v.lp and v.lp[1], v.lp and (v.lp[2] or v.lp[1])
    local hp0, hp1 = v.hp and v.hp[1], v.hp and (v.hp[2] or v.hp[1])
    local vib, trem = v.vib, v.trem
    local phase = 0
    local l1, l2, h1 = 0, 0, 0
    -- A filter that doesn't sweep is worked out once, not every sample.
    local lpk = lp0 and lp0 == lp1 and 1 - exp(-TAU * lp0 / RATE)
    local hpk = hp0 and hp0 == hp1 and 1 - exp(-TAU * hp0 / RATE)
    for i = 0, len - 1 do
        local x = i / len
        local t = i / RATE
        local f = f0
        if f1 ~= f0 then f = f0 * (f1 / f0) ^ (x ^ bend) end
        if vib then f = f * (1 + vib[2] * sin(TAU * vib[1] * t)) end
        phase = phase + f / RATE
        local p = phase % 1
        local s
        if wave == "sine" then s = sin(TAU * p)
        elseif wave == "tri" then s = 1 - 4 * abs(p - 0.5)
        elseif wave == "soft" then s = sin(TAU * p) * 0.8 + sin(TAU * p * 2) * 0.15 + sin(TAU * p * 3) * 0.05
        else s = rng:random() * 2 - 1 end -- noise
        if lp0 then
            local k = lpk or 1 - exp(-TAU * lp0 * (lp1 / lp0) ^ x / RATE)
            l1 = l1 + k * (s - l1)
            l2 = l2 + k * (l1 - l2)
            s = l2
        end
        if hp0 then
            local k = hpk or 1 - exp(-TAU * hp0 * (hp1 / hp0) ^ x / RATE)
            h1 = h1 + k * (s - h1)
            s = s - h1
        end
        local env
        if t < a then env = t / a
        else
            env = 1 - (t - a) / max(1e-4, v.dur - a)
            if curve ~= 1 then env = env ^ curve end
        end
        if trem then env = env * (1 - trem[2] * (0.5 + 0.5 * sin(TAU * trem[1] * t))) end
        local o = start + i
        out[o] = out[o] + s * env * vol
    end
    return start + len
end

-- A sound: its voices mixed, an echo if it has one, scaled so its loudest is
-- `gain`. `wrap` (seconds) folds everything past that length back onto the
-- start, so a loop is seamless and exactly that long.
local ffi = require "ffi"

local function render(def)
    local rng = love.math.newRandomGenerator(def.seed or 1)
    -- How long it rings: every voice to its end, and the echo's four repeats.
    local n = 0
    for _, v in ipairs(def) do n = max(n, floor((v.at or 0) * RATE) + max(1, floor(v.dur * RATE))) end
    local d = def.echo and floor(def.echo[1] * RATE) or 0
    local total = n + d * 4
    if def.wrap then total = max(total, floor(def.wrap * RATE)) end
    -- One flat buffer of doubles, zeroed: no Lua table, so a 32-second pad
    -- renders in a blink instead of a minute.
    local out = ffi.new("double[?]", total + 1)
    for _, v in ipairs(def) do voice(v, out, rng) end
    if def.echo then
        local fb = def.echo[2]
        for i = d, n + d * 4 - 1 do out[i] = out[i] + out[i - d] * fb end
        n = n + d * 4
    end
    if def.wrap then
        local w = floor(def.wrap * RATE)
        for i = w, n - 1 do out[i % w] = out[i % w] + out[i] end
        n = w
    end
    local peak = 1e-6
    for i = 0, n - 1 do peak = max(peak, abs(out[i])) end
    local g = (def.gain or 0.8) / (def.norm or peak)
    local data = love.sound.newSoundData(n, RATE, 16, 1)
    local p = ffi.cast("int16_t *", data:getFFIPointer())
    for i = 0, n - 1 do p[i] = floor(max(-1, min(1, out[i] * g)) * 32767) end
    return data
end

--- the sounds -----------------------------------------------------------------------------

local function chime(at, f, dur, vol, wave)
    return { at = at, dur = dur or 0.35, wave = wave or "sine", f0 = f, vol = vol or 1, a = 0.003, curve = 3 }
end

-- The key the lullaby is in: C major pentatonic, two octaves from G4.
local PENTA = {}
for oct = 0, 2 do for _, s in ipairs({ 0, 2, 4, 7, 9 }) do PENTA[#PENTA + 1] = 67 + oct * 12 + s - 7 end end

local DEFS = {
    -- A tap: a soft music-box pluck. tap1..tap10 climb the scale as taps come quicker.
    land = { vol = 0.12, gap = 0.12, wob = 0.15, { dur = 0.07, wave = "noise", lp = { 700, 250 }, curve = 2 } },
    buy = { vol = 0.4, gap = 0.04, echo = { 0.12, 0.25 },
        { dur = 0.11, wave = "sine", f0 = 330, f1 = 990, bend = 0.6, curve = 2 },
        chime(0.05, midi(76), 0.45, 0.5, "tri") },
    first = { vol = 0.45, gap = 0.2, echo = { 0.14, 0.3 },
        chime(0, midi(72), 0.4, 0.7, "tri"), chime(0.1, midi(79), 0.4, 0.6, "tri"), chime(0.2, midi(84), 0.7, 0.5) },
    nope = { vol = 0.25, gap = 0.12, { dur = 0.14, wave = "tri", f0 = 260, f1 = 200, lp = { 1200 }, curve = 1.5 } },
    click = { vol = 0.25, gap = 0.03, { dur = 0.04, wave = "tri", f0 = 1100, f1 = 650, curve = 2 } },
    goldenAppears = { vol = 0.3, gap = 1, echo = { 0.1, 0.3 },
        chime(0, midi(88), 0.3, 0.5), chime(0.09, midi(91), 0.3, 0.5), chime(0.18, midi(96), 0.5, 0.5) },
    golden = { vol = 0.5, gap = 0.3, echo = { 0.1, 0.3 },
        chime(0, midi(72), 0.5), chime(0.06, midi(76), 0.5), chime(0.12, midi(79), 0.5), chime(0.18, midi(84), 0.5),
        chime(0.24, midi(88), 0.5), chime(0.3, midi(91), 0.6), chime(0.36, midi(96), 0.9),
        { dur = 0.6, wave = "noise", hp = { 5000 }, vol = 0.08, curve = 2 } },
    stage = { vol = 0.4, gap = 1, echo = { 0.16, 0.35 },
        chime(0, midi(60), 2, 0.6, "tri"), chime(0.12, midi(64), 2, 0.5, "tri"), chime(0.24, midi(67), 2, 0.5, "tri"),
        chime(0.36, midi(71), 2.2, 0.4, "tri") },
    asleep = { vol = 0.4, gap = 2, echo = { 0.3, 0.4 },
        chime(0, midi(79), 2.5, 0.6), chime(0.55, midi(76), 2.5, 0.6), chime(1.1, midi(72), 2.5, 0.6),
        chime(1.65, midi(67), 2.5, 0.6), chime(2.2, midi(64), 2.5, 0.6), chime(2.75, midi(60), 3.5, 0.6) },
    dream = { vol = 0.4, gap = 2, echo = { 0.2, 0.35 },
        chime(0, midi(60), 1, 0.5, "tri"), chime(0.2, midi(67), 1, 0.5, "tri"), chime(0.4, midi(72), 1.5, 0.5, "tri") },
    -- The lucid dream: going in (a slow rise, an octave over the top, a hush
    -- of air), a run waking itself (a soft tick), a nightmare (a low minor
    -- fall), the flock safe (it resolves), and a gift chosen.
    lucid = { vol = 0.45, gap = 4, echo = { 0.35, 0.45 },
        chime(0, midi(48), 4, 0.5, "tri"), chime(0.4, midi(55), 3.6, 0.45, "tri"), chime(0.8, midi(64), 3.2, 0.45),
        chime(1.2, midi(71), 3, 0.4), chime(1.6, midi(74), 3, 0.4), chime(2.0, midi(79), 3.5, 0.35),
        chime(2.6, midi(86), 3.5, 0.3), { dur = 3.5, wave = "noise", hp = { 3000 }, vol = 0.05, curve = 1 } },
    run = { vol = 0.12, gap = 0.08, wob = 0.08, chime(0, midi(84), 0.12, 0.6), chime(0, midi(91), 0.08, 0.2, "tri") },
    nightmare = { vol = 0.4, gap = 2, echo = { 0.25, 0.4 },
        chime(0, midi(57), 1.2, 0.6, "tri"), chime(0.3, midi(53), 1.2, 0.6, "tri"), chime(0.6, midi(48), 1.8, 0.6, "tri"),
        chime(0.6, midi(51), 1.8, 0.4, "tri") },
    safe = { vol = 0.4, gap = 1, echo = { 0.15, 0.35 },
        chime(0, midi(67), 0.8, 0.5, "tri"), chime(0.15, midi(72), 0.8, 0.5, "tri"), chime(0.3, midi(76), 1.2, 0.5),
        chime(0.45, midi(79), 1.6, 0.5) },
    gift = { vol = 0.4, gap = 0.5, echo = { 0.1, 0.3 },
        chime(0, midi(79), 0.4, 0.5), chime(0.08, midi(84), 0.4, 0.5), chime(0.16, midi(88), 0.7, 0.5) },
    -- The bouncing sheep: a boing off a cloud (a soft rising wobble), a star
    -- picked up (two quick high notes). The way out: a long low fall, the
    -- notes of the way in going back down into a hush.
    boing = { vol = 0.16, gap = 0.06, wob = 0.06,
        { dur = 0.16, wave = "sine", f0 = 220, f1 = 520, bend = 0.5, vib = { 22, 0.05 }, curve = 1.6 } },
    star = { vol = 0.22, gap = 0.04, wob = 0.04, echo = { 0.08, 0.25 },
        chime(0, midi(91), 0.18, 0.6), chime(0.05, midi(96), 0.25, 0.5) },
    void = { vol = 0.45, gap = 4, echo = { 0.4, 0.5 },
        chime(0, midi(86), 3, 0.3), chime(0.5, midi(79), 3, 0.35), chime(1.0, midi(71), 3.2, 0.4),
        chime(1.6, midi(64), 3.5, 0.45, "tri"), chime(2.3, midi(55), 4, 0.5, "tri"), chime(3.0, midi(43), 5, 0.5, "tri"),
        { dur = 5, wave = "noise", lp = { 900, 120 }, vol = 0.06, curve = 1 } },
    bleat = { vol = 0.18, gap = 0.25, wob = 0.12, { dur = 0.22, wave = "tri", f0 = 420, f1 = 380, vib = { 18, 0.06 }, lp = { 1600 }, curve = 1.5 } },
}
for i, n in ipairs(PENTA) do
    if i <= 10 then
        DEFS["tap" .. i] = { vol = 0.32, gap = 0.02, poly = 4, wob = 0.01,
            chime(0, midi(n), 0.3, 1), chime(0, midi(n + 12), 0.14, 0.2, "tri") }
    end
end

-- The pad: four chords of eight seconds (Cmaj9, Am9, Fmaj7, G6sus).
local CHORDS = {
    { 48, 55, 64, 71, 74 },
    { 45, 52, 60, 67, 71 },
    { 41, 48, 57, 64, 67 },
    { 43, 50, 59, 62, 69 },
}
local BAR, LEN = 8, 32
local function padNotes(tones, wave, vol, octave, extra)
    local list = { wrap = LEN, norm = 1, gain = 1 }
    for c, ch in ipairs(CHORDS) do
        for _, k in ipairs(tones) do
            for _, dt in ipairs({ 0.997, 1.003 }) do
                local v = { at = (c - 1) * BAR, dur = BAR + 2.5, wave = wave, f0 = midi(ch[k] + 12 * (octave or 0)) * dt,
                    a = 2.2, curve = 1.4, vol = vol }
                for key, val in pairs(extra or {}) do v[key] = val end
                list[#list + 1] = v
            end
        end
    end
    return list
end
local LAYERS = {}
LAYERS[0] = padNotes({ 1, 2 }, "soft", 0.16, 0, { trem = { 1 / 8, 0.3 } })
LAYERS[1] = padNotes({ 3, 4 }, "tri", 0.07, 0, { trem = { 1 / 4, 0.3 }, lp = { 1600 } })
do -- the music box: up and down each chord, an echo behind it
    local box = { wrap = LEN, norm = 1, gain = 1, echo = { 0.42, 0.35 } }
    local pattern = { 1, 3, 5, 3, 2, 4, 5, 4 }
    for c, ch in ipairs(CHORDS) do
        for s = 0, 15 do
            if s % 8 ~= 7 or s == 15 then
                box[#box + 1] = chime((c - 1) * BAR + s * 0.5, midi(ch[pattern[s % 8 + 1]] + 24), 1.3, 0.11)
            end
        end
    end
    LAYERS[2] = box
end
LAYERS[3] = padNotes({ 4, 5 }, "sine", 0.035, 1, { vib = { 5, 0.004 } })
LAYERS[4] = padNotes({ 1 }, "sine", 0.18, -1, { trem = { 1 / 4, 0.5 } })
do -- the bells: one note every two seconds, slow
    local bells = { wrap = LEN, norm = 1, gain = 1, echo = { 0.5, 0.3 } }
    local melody = { 76, 74, 72, 74, 76, 79, 76, 72, 72, 71, 69, 71, 72, 74, 71, 67 }
    for i, n in ipairs(melody) do bells[#bells + 1] = chime((i - 1) * 2, midi(n), 2.4, 0.13, "tri") end
    LAYERS[5] = bells
end

Synth.DEFS, Synth.LAYERS = DEFS, LAYERS

-- A sound by name ("tap3", "buy"...), or a pad layer by number, as SoundData.
function Synth.make(name)
    if type(name) == "number" then return render(LAYERS[name]) end
    return render(DEFS[name])
end

return Synth
