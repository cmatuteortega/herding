-- Phase 3, the void: past the Gate of Horn, out of the dream. Not built yet:
-- this is the way in and a place to stand. The field went first, then the
-- dream; what's left is the dark, a few far motes falling slowly in towards
-- the middle, and one sheep floating there, turning. A tap rings out over
-- the dark. BACK TO THE DREAM goes back through the gate (it stays open).
--
-- ui.lua hands everything over to this once `phase` is "void".

local G = require "gfx"
local Models = require "models"
local Audio = require "audio"
local lume = require "lib.lume"

local floor, sin, cos, sqrt = math.floor, math.sin, math.cos, math.sqrt

local VUI = {}
VUI.save = function() end -- set by ui.lua
VUI.back = function() end -- set by ui.lua: back through the gate

local S
local vw, vh = 320, 240
local t, since = 0, 0 -- the clock, and time since coming in
local reduced = false
local motes, rings = {}, {}
local button

function VUI.setState(s) S = s end
function VUI.setReduced(v) reduced = v end

function VUI.fit(w, h, inset)
    vw, vh = w, h
    local bw = G.textWidth("BACK TO THE DREAM") + 24
    button = { x = floor(vw / 2 - bw / 2), y = vh - inset.b - 26, w = bw, h = 14 }
    local r = love.math.newRandomGenerator(5)
    motes = {}
    for _ = 1, floor(vw * vh / 260) do
        motes[#motes + 1] = { a = r:random() * 6.283, d = r:random(), v = 0.01 + r:random() * 0.03, k = r:random() < 0.15 and "l" or "v" }
    end
end

-- Coming in: the pad goes down to its sub bass, and the words come up again.
function VUI.enter()
    since = 0
    rings = {}
    Audio.setLucid(false)
    Audio.setVoid(true)
end

local function inside(r, x, y) return r and x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h end

function VUI.pressed(x, y)
    Audio.start()
    if inside(button, x, y) then
        Audio.cue("click")
        Audio.setVoid(false)
        VUI.back()
        return
    end
    if #rings < 6 then rings[#rings + 1] = { x = x, y = y, t = 0 } end
    Audio.cue("star")
end
function VUI.moved() end
function VUI.released() end
function VUI.wheel() end

function VUI.key(key)
    if key == "m" then
        S.muted = not S.muted
        Audio.setMuted(S.muted)
        VUI.save()
    elseif key == "space" or key == "return" then
        VUI.pressed(vw / 2, vh / 2)
    end
end

function VUI.update(dt)
    t, since = t + dt, since + dt
    for _, m in ipairs(motes) do
        if not reduced then m.d = m.d - m.v * dt end
        if m.d <= 0.02 then m.d = 1 end
    end
    for i = #rings, 1, -1 do
        rings[i].t = rings[i].t + dt
        if rings[i].t > 2 then table.remove(rings, i) end
    end
end

function VUI.draw()
    G.rect("n", 0, 0, vw, vh)
    local cx, cy = vw / 2, vh * 0.48
    local far = sqrt(cx * cx + cy * cy)
    -- The motes, falling in towards the middle, fading as they go.
    local pts = { v = {}, l = {} }
    for i, m in ipairs(motes) do
        local x, y = cx + cos(m.a + m.d * 0.6) * m.d * far, cy + sin(m.a + m.d * 0.6) * m.d * far
        if G.dither(i, i * 3, m.d * 1.4) then G.plot(pts[m.k], x, y) end
    end
    G.points("v", pts.v)
    G.points("l", pts.l)
    -- Rings, where a finger touched the dark.
    for _, r in ipairs(rings) do
        local rr = r.t * 40
        local ring = {}
        for a = 0, 47 do
            local x, y = r.x + cos(a / 48 * 6.283) * rr, r.y + sin(a / 48 * 6.283) * rr
            if G.dither(x, y, 1 - r.t / 2) then G.plot(ring, x, y) end
        end
        G.points("i", ring)
    end
    -- The sheep, floating, turning slowly.
    local bob = reduced and 0 or sin(t * 0.8) * 3
    local h = reduced and 0.3 or t * 0.25
    local sp = Models.sheep(h, 0, 0, "cloud", false, 0.9)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(sp.img, floor(cx - sp.oi), floor(cy + bob - sp.oj))
    -- The words, coming up one after the other.
    local function say(text, at, y, z, k)
        local dens = reduced and 1 or lume.clamp((since - at) / 0.8, 0, 1)
        if dens > 0 then G.label(k, text, floor(cx - G.textWidth(text, z) / 2), floor(y), z, dens, "o") end
    end
    say("THE VOID", 0.3, vh * 0.2, 2, "c")
    say("NO FIELD. NO DREAM. NOTHING TO COUNT.", 1.2, vh * 0.2 + 16, 1, "l")
    say("PHASE 3 BEGINS HERE. IT ISN'T BUILT YET.", 2.2, cy + 26, 1, "i")
    say("TAP THE DARK.", 3.2, cy + 36, 1, "i")
    if since > 2.5 then
        local b = button
        G.box(b.x, b.y, b.w, b.h, "v", "i")
        local s = "BACK TO THE DREAM"
        G.text("l", s, floor(b.x + b.w / 2 - G.textWidth(s) / 2), b.y + 4)
    end
    if S and S.muted then G.text("i", "MUTED", vw - 26, 4) end
end

return VUI
