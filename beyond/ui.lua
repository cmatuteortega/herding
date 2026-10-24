-- Phase 4, beyond: past the cut cord. Not built yet: a placeholder, a place
-- to stand, and a suggestion of what comes. Every phase before was the dark
-- (dusk, the night, the dream, the planes); this is the light, the page
-- turned over: cream, with ink. No sheep, no counting, no one counting. One
-- point in the middle, breathing, and whatever you tap ripples out in beige
-- and is gone. It may be the void, or enlightenment: we'll see.
--
-- BACK TO THE STARS goes back to astral projection, the cord whole again.
-- The reset button, top right, starts everything over from the first night:
-- tap it, then tap it again while it asks.
--
-- ui.lua hands everything over to this once `phase` is "beyond".

local G = require "gfx"
local Audio = require "audio"
local lume = require "lib.lume"

local floor, sin, cos = math.floor, math.sin, math.cos

local BUI = {}
BUI.save = function() end -- set by ui.lua
BUI.back = function() end -- set by ui.lua: back to the stars
BUI.resetAll = function() end -- set by ui.lua: wipe the save, a new game
BUI.nextPhase = function() end -- set by ui.lua (dev): round to phase 1

local S
local vw, vh = 320, 240
local t, since = 0, 0 -- the clock, and time since coming in
local reduced = false
local ripples = {}
local button, reset, phase
local confirm = 0 -- until when the reset button waits for its second tap
local RESET_ART = { "..ooo.o", ".o...oo", "o...ooo", "o......", "o.....o", ".o...o.", "..ooo.." }

function BUI.setState(s) S = s end
function BUI.setReduced(v) reduced = v end

function BUI.fit(w, h, inset)
    vw, vh = w, h
    local bw = G.textWidth("BACK TO THE STARS") + 24
    button = { x = floor(vw / 2 - bw / 2), y = vh - inset.b - 26, w = bw, h = 14 }
    reset = { x = vw - inset.r - 3 - 17, y = inset.t + 2, w = 17, h = 13 }
    phase = { x = reset.x - 20, y = reset.y, w = 17, h = 13 }
end

-- Coming in: only the high shimmer of the pad, and the words come up.
function BUI.enter()
    since, confirm = 0, 0
    ripples = {}
    Audio.setAstral(false)
    Audio.setBeyond(true)
end

local function inside(r, x, y) return r and x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h end

function BUI.pressed(x, y)
    Audio.start()
    if inside(button, x, y) and since > 4 then
        Audio.cue("click")
        BUI.back()
        return
    end
    if inside(reset, x, y) then
        Audio.cue("click")
        if confirm > t then
            confirm = 0
            Audio.setBeyond(false)
            BUI.resetAll()
        else
            confirm = t + 3
        end
        return
    end
    if inside(phase, x, y) then
        Audio.cue("click")
        Audio.setBeyond(false)
        BUI.nextPhase()
        return
    end
    if #ripples < 5 then ripples[#ripples + 1] = { x = x, y = y, t = 0 } end
    Audio.cue("breath")
end
function BUI.moved() end
function BUI.released() end
function BUI.wheel() end

function BUI.key(key)
    if key == "m" then
        S.muted = not S.muted
        Audio.setMuted(S.muted)
        BUI.save()
    elseif key == "space" or key == "return" then
        BUI.pressed(vw / 2, vh / 2)
    end
end

function BUI.update(dt)
    t, since = t + dt, since + dt
    for i = #ripples, 1, -1 do
        ripples[i].t = ripples[i].t + dt
        if ripples[i].t > 3 then table.remove(ripples, i) end
    end
end

function BUI.draw()
    G.rect("w", 0, 0, vw, vh)
    local cx, cy = vw / 2, vh * 0.48
    -- Ripples, where a finger touched the light: slow, and gone.
    for _, r in ipairs(ripples) do
        local rr = r.t * 30
        local ring = {}
        for a = 0, 63 do
            local x, y = r.x + cos(a / 64 * 6.283) * rr, r.y + sin(a / 64 * 6.283) * rr
            if G.dither(floor(x), floor(y), 1 - r.t / 3) then G.plot(ring, x, y) end
        end
        G.points("b", ring)
    end
    -- The point, breathing: a ring opening round it and closing.
    local b = reduced and 0.5 or (sin(t * 0.6) + 1) / 2
    G.rect("o", floor(cx), floor(cy), 1, 1)
    local ring = {}
    local rr = 3 + b * 8
    for a = 0, 47 do
        local x, y = cx + cos(a / 48 * 6.283) * rr, cy + sin(a / 48 * 6.283) * rr
        if G.dither(floor(x), floor(y), 0.8 - b * 0.6) then G.plot(ring, x, y) end
    end
    G.points("s", ring)
    -- The words, coming up one after the other.
    local function say(text, at, y, z, k)
        local dens = reduced and 1 or lume.clamp((since - at) / 1.2, 0, 1)
        if dens > 0 then G.text(k, text, floor(cx - G.textWidth(text, z) / 2), floor(y), z, dens) end
    end
    say("BEYOND", 0.6, vh * 0.2, 2, "o")
    say("NO SHEEP. NO COUNTING. NO ONE COUNTING.", 1.8, vh * 0.2 + 16, 1, "p")
    say("PHASE 4: THE VOID, OR ENLIGHTENMENT.", 3.0, cy + 24, 1, "s")
    say("IT ISN'T BUILT YET.", 3.6, cy + 32, 1, "s")
    if since > 4 then
        local bt = button
        G.box(bt.x, bt.y, bt.w, bt.h, "b", "o")
        local s = "BACK TO THE STARS"
        G.text("o", s, floor(bt.x + bt.w / 2 - G.textWidth(s) / 2), bt.y + 4)
    end
    -- The reset button: an arrow coming round, and its question while it waits.
    G.box(reset.x + 1, reset.y + 1, reset.w - 2, reset.h - 2, "w", confirm > t and "h" or "s")
    G.art(RESET_ART, reset.x + 5, reset.y + 3)
    -- The phase button (dev): round to phase 1, a new game.
    G.box(phase.x + 1, phase.y + 1, phase.w - 2, phase.h - 2, "w", "s")
    G.text("o", "4>1", phase.x + 3, phase.y + 4)
    if confirm > t then
        local q = "TAP AGAIN TO RESET ALL"
        G.text("h", q, floor(math.max(4, reset.x + reset.w - G.textWidth(q))), reset.y + reset.h + 3)
    end
    if S and S.muted then G.text("s", "MUTED", 4, 4) end
end

return BUI
