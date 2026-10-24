-- Astral projection's field, drawn into its own low-res canvas like the
-- other phases': the sky of the plane you're in (dithered, from the Etheric's
-- navy to the Edge's plum), far stars streaming past as you go out, the body
-- asleep in its bed far below (it sinks out of sight the further you go),
-- the silver cord from it up to the dreamer's sheep, shaking at a tug and
-- turning rose as it strains, the constellation you're lighting (the next
-- star pulsing), the dreamers dreaming with you (an orb each, out at the
-- sides), and now and then the comet. It only reads the rules' state; what
-- only looks (floats, rings, a flash, the sheep easing up and down) lives in
-- `fx`.

local G = require "gfx"
local Models = require "models"
local C = require "config"
local Astral = require "astral.game"

local floor, min, max, sin, cos, log10 = math.floor, math.min, math.max, math.sin, math.cos, math.log10
local A = C.astral

local AScene = { reduced = false }

local canvas, cw, ch = nil, 0, 0
local stars = {}
local t = 0

local fx = { floats = {}, rings = {}, flash = 0, up = 0, shake = 0, scroll = 0, snap = 0 }
AScene.fx = fx

function AScene.resize(w, h)
    if w == cw and h == ch and canvas then return end
    cw, ch = w, h
    canvas = love.graphics.newCanvas(cw, ch)
    canvas:setFilter("nearest", "nearest")
    local r = love.math.newRandomGenerator(cw * 13 + ch)
    stars = {}
    for _ = 1, floor(cw * ch / 90) do
        stars[#stars + 1] = { x = r:random(0, cw - 1), y = r:random() * ch, ph = r:random() * 6.283, z = r:random() }
    end
end

function AScene.reset()
    fx.floats, fx.rings, fx.flash, fx.shake, fx.snap = {}, {}, 0, 0, 0
end

function AScene.float(text, x, y, k) fx.floats[#fx.floats + 1] = { text = text, x = x, y = y, k = k, t = 0 } end
function AScene.flash() fx.flash = 1 end
function AScene.ring(x, y, k) fx.rings[#fx.rings + 1] = { x = x, y = y, t = 0, k = k or "e" } end
function AScene.tug() fx.shake = 1 end
function AScene.snapped() fx.snap = 1; fx.shake = 1.5 end

local function blit(sp, x, y)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(sp.img, floor(x + 0.5) - sp.oi, floor(y + 0.5) - sp.oj)
end

--- where things are ----------------------------------------------------------------

-- How far the body has sunk out of sight: 0 at home, 1 gone.
local function sunk(P) return min(1, log10(1 + P.dist) / 2.2) end

local function bodyX() return floor(cw * 0.3) end
local function bedY(P) return ch - 14 + sunk(P) * (ch * 0.6) end

-- Where the dreamer's sheep is: just over the bed at home, high out.
function AScene.sheepAt(P)
    local home = bedY(P) - 13
    local high = ch * 0.42
    local y = home + (high - home) * fx.up
    local bob = AScene.reduced and 0 or sin(t * 0.9) * 2 * (0.4 + fx.up)
    return bodyX(), y + bob
end

-- The constellation's box: the right of the field, under the words.
local function conBox()
    local w = floor(min(cw * 0.42, ch * 0.62))
    local h = floor(min(ch * 0.5, w * 0.8))
    return floor(cw * 0.94 - w), floor(max(30, ch * 0.3)), w, h
end

local function starAt(c, i)
    local x, y, w, h = conBox()
    local s = c.stars[i]
    return floor(x + s[1] * w), floor(y + s[2] * h)
end

-- The next star of the constellation in the sky, if (x, y) is on it.
function AScene.hitStar(P, x, y)
    local id = Astral.skyCon(P)
    local c = Astral.CONSTELLATIONS[Astral.CON[id]]
    local i = Astral.lit(P, id) + 1
    if i > #c.stars then return nil end
    local sx, sy = starAt(c, i)
    if (x - sx) ^ 2 + (y - sy) ^ 2 <= 10 ^ 2 then return id end
    return nil
end

local function cometAt(P)
    local p = P.comet.t / A.comet.crossTime
    return cw + 10 - p * (cw + 30), ch * (0.1 + P.comet.lane * 0.18) + p * 10
end

function AScene.hitComet(P, x, y)
    if not P.comet then return false end
    local cx, cy = cometAt(P)
    return (x - cx) ^ 2 + (y - cy) ^ 2 <= 14 ^ 2
end

--- each frame -------------------------------------------------------------------------

function AScene.update(dt, P)
    t = t + dt
    local want = P.out and 1 or 0
    fx.up = fx.up + (want - fx.up) * min(1, dt * (P.out and 2.5 or 6))
    -- The far stars stream down while out, the quicker the further.
    if P.out and not AScene.reduced then
        fx.scroll = fx.scroll + dt * (6 + Astral.speed(P) * 40)
    end
    fx.shake = max(0, fx.shake - dt * 2)
    fx.snap = max(0, fx.snap - dt * 1.2)
    fx.flash = max(0, fx.flash - dt * 2)
    for i = #fx.floats, 1, -1 do
        local f = fx.floats[i]
        f.t = f.t + dt
        if f.t > 1.4 then table.remove(fx.floats, i) end
    end
    for i = #fx.rings, 1, -1 do
        local r = fx.rings[i]
        r.t = r.t + dt
        if r.t > 1.2 then table.remove(fx.rings, i) end
    end
end

--- drawing ---------------------------------------------------------------------------

-- The sky: the plane's two colours, the lower dithered up into the upper,
-- and the next plane's showing through near its border.
local function sky(P)
    local k = Astral.plane(P)
    local pl = A.planes[k]
    G.rect(pl.sky[1], 0, 0, cw, ch)
    local pts = {}
    for y = 0, ch - 1 do
        local v = (y / ch) ^ 2 * 0.7
        for x = 0, cw - 1 do if G.dither(x, y, v) then G.plot(pts, x, y) end end
    end
    G.points(pl.sky[2], pts)
    local nxt = A.planes[k + 1]
    if nxt and P.out then
        -- How close the next plane is, in decades.
        local near = 1 - min(1, (log10(nxt.at) - log10(1 + P.dist)) / 0.7)
        if near > 0 then
            local top = {}
            for y = 0, floor(ch * 0.4) do
                local v = near * (1 - y / (ch * 0.4)) * 0.6
                for x = 0, cw - 1 do if G.dither(x + 1, y, v) then G.plot(top, x, y) end end
            end
            G.points(nxt.sky[1], top)
        end
    end
    -- The far stars: three depths, streaming down at their own speeds.
    local lists = { x = {}, l = {}, i = {} }
    for _, s in ipairs(stars) do
        local y = (s.y + fx.scroll * (0.2 + s.z)) % ch
        local tw = AScene.reduced and 1 or sin(t * (0.6 + s.z) + s.ph)
        if tw > -0.3 then G.plot(s.z > 0.85 and lists.x or (s.z > 0.45 and lists.l or lists.i), s.x, y) end
        -- Quick enough, a star is a streak.
        if P.out and s.z > 0.7 and Astral.speed(P) > 0.4 and not AScene.reduced then G.plot(lists.i, s.x, y - 1) end
    end
    G.points("i", lists.i)
    G.points("l", lists.l)
    G.points("x", lists.x)
end

-- The body asleep, far below: a bed, a blanket, the pajama'd sheep's head on
-- the pillow.
local function body(P)
    local x, y = bodyX(), floor(bedY(P))
    if y > ch + 20 then return end
    G.box(x - 16, y + 2, 32, 7, "p", "o")
    G.box(x - 15, y - 2, 6, 5, "w", "o") -- the pillow
    local sp = Models.sheep(math.pi, 0, 0, "pj", false, 0.55)
    blit(sp, x - 11, y + 1)
    G.box(x - 7, y - 1, 21, 5, "i", "o") -- the blanket
    for i = 0, 18, 3 do G.rect("l", x - 6 + i, y, 1, 1) end
    G.rect("o", x - 16, y + 9, 2, 3)
    G.rect("o", x + 14, y + 9, 2, 3)
    -- Zs, rising off the sleeper.
    if not AScene.reduced then
        for i = 0, 2 do
            local p = (t * 0.4 + i / 3) % 1
            if G.dither(i, floor(p * 10), 1 - p) then G.text("l", "Z", x - 8 + p * 6 + i * 2, y - 8 - p * 14) end
        end
    end
end

-- The silver cord, from the body (or the bottom, once it's sunk) up to the
-- sheep: a slow curve, shaking at a tug, rose and flickering as it strains.
local function cord(P)
    if fx.up < 0.05 and fx.snap <= 0 then return end
    local sx, sy = AScene.sheepAt(P)
    local bx, by = bodyX() + 2, min(ch + 4, bedY(P) - 2)
    local strain = Astral.strain(P)
    local pts, hot = {}, {}
    local n = floor(max(8, by - sy))
    for i = 0, n do
        local p = i / n
        local y = by + (sy + 6 - by) * p
        -- A slow S, swaying: wider the longer the cord on screen.
        local amp = (by - sy) * 0.16
        local sway = AScene.reduced and sin(p * math.pi) * amp
            or sin(p * math.pi) * amp * (0.6 + 0.4 * sin(t * 0.7 + p * 3)) - sin(p * math.pi * 2) * amp * 0.3 * cos(t * 0.5)
        local shake = (AScene.reduced and 0 or fx.shake * 3 * sin(t * 40 + p * 20))
        local x = bx + (sx - bx) * p + sway + shake
        -- A snapped cord: the bottom of it gone, thinning upwards.
        if fx.snap <= 0 or p > fx.snap or not G.dither(floor(x), floor(y), fx.snap) then
            local warm = strain > 0.6 and G.dither(floor(x), floor(y + t * 20), (strain - 0.6) * 2.4)
            G.plot(warm and hot or pts, x, y)
            if strain > 0.85 and not AScene.reduced and sin(t * 18 + p * 9) > 0.6 then G.plot(hot, x + 1, y) end
        end
    end
    G.points("e", pts)
    G.points("r", hot)
end

-- The constellation in the sky: its lines between lit stars, the stars lit
-- in starlight, the next one pulsing (gold when it can be lit), the rest
-- dim. Not open yet: faint, the stars only.
local function constellation(P)
    local id = Astral.skyCon(P)
    local c = Astral.CONSTELLATIONS[Astral.CON[id]]
    local n = Astral.lit(P, id)
    local open = Astral.conOpen(P, id)
    local lines = {}
    local function join(a, b)
        local ax, ay = starAt(c, a)
        local bx, by = starAt(c, b)
        local steps = max(1, math.abs(bx - ax), math.abs(by - ay))
        for s = 0, steps do
            G.plot(lines, ax + (bx - ax) * s / steps, ay + (by - ay) * s / steps)
        end
    end
    for i = 2, n do join(i - 1, i) end
    if c.join and n >= max(c.join[1], c.join[2]) then join(c.join[1], c.join[2]) end
    G.points("e", lines)
    for i, _ in ipairs(c.stars) do
        local x, y = starAt(c, i)
        if i <= n then
            G.rect("x", x - 1, y, 3, 1)
            G.rect("x", x, y - 1, 1, 3)
            if not AScene.reduced and sin(t * 2 + i) > 0.7 then G.rect("w", x, y, 1, 1) end
        elseif i == n + 1 and open then
            local can = Astral.canLight(P, id)
            local pulse = AScene.reduced or sin(t * 5) > -0.2
            local k = can and "y" or "i"
            G.rect(k, x - 1, y, 3, 1)
            G.rect(k, x, y - 1, 1, 3)
            if pulse then
                G.rect(k, x - 3, y, 1, 1); G.rect(k, x + 3, y, 1, 1)
                G.rect(k, x, y - 3, 1, 1); G.rect(k, x, y + 3, 1, 1)
            end
        else
            G.rect(open and "i" or "p", x, y, 1, 1)
        end
    end
    local name = c.name:upper()
    local x, y, w, h = conBox()
    local k = Astral.done(P, id) and "x" or (open and "l" or "p")
    G.label(k, name, floor(x + w / 2 - G.textWidth(name) / 2), y + h + 4, 1, nil, "o")
end

-- The dreamers dreaming with you: an orb a kind, at the far left, a Z each.
local function dreamers(P)
    local y = 34
    for k = 1, #Astral.DREAMERS do
        if P.dreamers[k] > 0 then
            local bob = AScene.reduced and 0 or sin(t * 0.7 + k) * 2
            local x = 9 + (k % 2) * 6
            G.disc(P.out and "l" or "i", x, y + bob, 3)
            G.rect(P.out and "x" or "c", x - 1, y + bob - 1, 1, 1)
            -- While out, a mote drifting from each towards the sheep.
            if P.out and not AScene.reduced then
                local sx, sy = AScene.sheepAt(P)
                local p = (t * 0.5 + k * 0.17) % 1
                G.rect("c", floor(x + (sx - x) * p), floor(y + (sy - y) * p), 1, 1)
            end
            y = y + 10
        end
    end
end

local function comet(P)
    if not P.comet then return end
    local x, y = cometAt(P)
    local tail = {}
    for i = 1, 16 do
        if G.dither(floor(x) + i, floor(y) - floor(i * 0.3), 1 - i / 17) then G.plot(tail, x + i, y - i * 0.3) end
    end
    G.points("h", tail)
    G.disc("y", x, y, 2)
    G.rect("w", floor(x), floor(y) - 1, 1, 1)
end

function AScene.draw(P)
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(G.C.n)
    sky(P)
    constellation(P)
    dreamers(P)
    body(P)
    cord(P)
    local sx, sy = AScene.sheepAt(P)
    local h = AScene.reduced and 0.3 or t * 0.35
    -- Out, it leans into the climb; at home, it sits over the sleeper.
    local sp = Models.sheep(P.out and -1.2 or h, 0, 0, "cloud", false, 1)
    blit(sp, sx, sy)
    comet(P)
    for _, r in ipairs(fx.rings) do
        local rr = r.t * 24
        local ring = {}
        for a = 0, 31 do
            local x, y = r.x + cos(a / 32 * 6.283) * rr, r.y + sin(a / 32 * 6.283) * rr
            if G.dither(floor(x), floor(y), 1 - r.t / 1.2) then G.plot(ring, x, y) end
        end
        G.points(r.k, ring)
    end
    for _, f in ipairs(fx.floats) do
        local dens = 1 - max(0, f.t / 1.4 - 0.5) * 2
        G.label(f.k or "y", f.text, floor(f.x - G.textWidth(f.text) / 2), floor(f.y - f.t * 12), 1, AScene.reduced and 1 or dens)
    end
    if fx.flash > 0 and not AScene.reduced then
        local pts = {}
        for y = 0, ch - 1 do
            for x = 0, cw - 1 do if G.dither(x, y, fx.flash * 0.4) then G.plot(pts, x, y) end end
        end
        G.points("x", pts)
    end
    love.graphics.pop()
    return canvas
end

-- A constellation, small, for its card: lit stars and lines in starlight,
-- the rest dim, in a box `s` across centred on (x, y).
function AScene.constellationIcon(P, id, x, y, s, dim)
    local c = Astral.CONSTELLATIONS[Astral.CON[id]]
    local n = Astral.lit(P, id)
    local function at(i) return floor(x - s / 2 + c.stars[i][1] * s), floor(y - s / 2 + c.stars[i][2] * s) end
    local pts = {}
    for i = 2, n do
        local ax, ay = at(i - 1)
        local bx, by = at(i)
        local steps = max(1, math.abs(bx - ax), math.abs(by - ay))
        for k = 0, steps do G.plot(pts, ax + (bx - ax) * k / steps, ay + (by - ay) * k / steps) end
    end
    G.points(dim and "p" or "e", pts)
    for i = 1, #c.stars do
        local sx, sy = at(i)
        G.rect(i <= n and (dim and "s" or "x") or (dim and "p" or "i"), sx, sy, 1, 1)
    end
end

-- A dreamer's picture, for its card: an orb with a Z.
function AScene.dreamerIcon(k, x, y, dim)
    G.disc(dim and "p" or "l", x, y, 6)
    G.disc(dim and "n" or "c", x - 1, y - 1, 3)
    G.text(dim and "p" or "u", "Z", floor(x) - 1, floor(y) - 2)
end

return AScene
