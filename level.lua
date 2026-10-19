-- The three fields, what is in them, and the questions the flock and the dog
-- ask about them: what is solid here, which way is away from it, is this
-- inside the pen.
--
-- Field units are game pixels across; down the field they are foreshortened
-- by the camera (tracer.lua's SE) when drawn. z runs down the screen.
--
-- A fence is a segment, solid for FENCE_R either side. A pen is a rectangle of
-- fences with one gap in it (`gate`: the side, where along it 0..1, and how
-- wide). The field is fenced all round. A pond is a circle of water, as solid
-- as a rock to everything on four legs, but flat: painted into the ground.
--
-- A flock entry is a bunch: `n` sheep of `kind` (a ewe unless it says) round
-- (x, z), with `lambs` more that keep to them. `goal` is the share to pen.

local G = require "gfx"
local T = require "tracer"

local sqrt, floor, max, min = math.sqrt, math.floor, math.max, math.min

local Level = {}
Level.__index = Level

local FENCE_R = 1.5
local POST_GAP = 14

Level.DEFS = {
    {
        name = "OPEN FIELD",
        hint = "COME IN SLOWLY. THE FLOCK MOVES AWAY FROM YOU.",
        w = 340, h = 240,
        flock = { { x = 110, z = 150, n = 4, r = 22 }, { x = 160, z = 110, n = 4, r = 22 } },
        dog = { x = 36, z = 200 },
        pen = { x = 250, z = 40, w = 72, h = 80, side = "w", at = 0.5, gap = 42 },
        fences = {},
        rocks = {},
    },
    {
        name = "THE GATE",
        hint = "ONE GAP. TOO MANY AT ONCE AND THEY JAM.",
        w = 360, h = 250,
        flock = { { x = 70, z = 70, n = 4, r = 20 }, { x = 110, z = 170, n = 5, r = 24 }, { x = 140, z = 110, n = 3, r = 16 } },
        dog = { x = 30, z = 230 },
        pen = { x = 280, z = 82, w = 66, h = 86, side = "w", at = 0.5, gap = 26 },
        -- A fence across the field with one gate in it.
        fences = { { 200, 0, 200, 108 }, { 200, 140, 200, 250 } },
        rocks = { { 240, 60, 9 }, { 245, 196, 11 } },
    },
    {
        name = "THE LANE",
        hint = "AROUND THE ROCKS, DOWN THE LANE, UP INTO THE PEN.",
        w = 390, h = 260,
        flock = { { x = 60, z = 60, n = 5, r = 22 }, { x = 70, z = 200, n = 5, r = 22 }, { x = 120, z = 130, n = 6, r = 26 } },
        dog = { x = 24, z = 130 },
        pen = { x = 300, z = 20, w = 70, h = 82, side = "s", at = 0.5, gap = 24 },
        -- The only way east is a lane between two fences, past the rocks.
        fences = {
            { 180, 0, 180, 114 }, { 180, 146, 180, 260 },
            { 180, 114, 250, 114 }, { 180, 146, 250, 146 },
        },
        rocks = { { 120, 62, 13 }, { 96, 176, 11 }, { 150, 205, 8 }, { 290, 190, 15 }, { 318, 150, 9 }, { 236, 60, 10 } },
    },
    {
        name = "THE POND",
        hint = "LAMBS KEEP TO THEIR MOTHERS. MIND THE WATER.",
        w = 380, h = 260,
        flock = { { x = 80, z = 76, n = 4, r = 20, lambs = 3 }, { x = 92, z = 192, n = 3, r = 18, lambs = 2 } },
        dog = { x = 26, z = 132 },
        pen = { x = 290, z = 88, w = 70, h = 84, side = "w", at = 0.5, gap = 30 },
        fences = {},
        rocks = { { 150, 34, 8 }, { 236, 228, 9 } },
        ponds = { { 192, 130, 38 } },
    },
    {
        name = "THE BLACK SHEEP",
        hint = "SHE WON'T BUDGE FOR A LOOK. GET CLOSE, OR BARK.",
        w = 380, h = 250,
        goal = 1,
        flock = { { x = 76, z = 170, n = 5, r = 22 }, { x = 326, z = 204, n = 1, r = 0, kind = "black" } },
        dog = { x = 30, z = 224 },
        pen = { x = 150, z = 18, w = 80, h = 70, side = "s", at = 0.5, gap = 28 },
        -- She grazes behind a fence: the way out to her is round the top.
        fences = { { 270, 112, 270, 250 } },
        rocks = { { 96, 84, 10 }, { 316, 58, 9 }, { 196, 196, 11 } },
        ponds = { { 330, 150, 18 } },
    },
    {
        name = "HOME PASTURE",
        hint = "THE LONG WAY ROUND. TAKE YOUR TIME.",
        w = 480, h = 320,
        flock = {
            { x = 70, z = 70, n = 5, r = 22, lambs = 2 }, { x = 92, z = 150, n = 4, r = 20 },
            { x = 48, z = 292, n = 1, r = 0, kind = "black" },
        },
        dog = { x = 196, z = 40 },
        pen = { x = 380, z = 212, w = 80, h = 88, side = "n", at = 0.5, gap = 28 },
        -- Over the first fence, under the second, down into the pen.
        fences = { { 240, 196, 240, 320 }, { 330, 0, 330, 150 } },
        rocks = { { 200, 282, 10 }, { 420, 64, 12 }, { 286, 258, 9 }, { 160, 40, 8 } },
        ponds = { { 128, 232, 30 }, { 284, 92, 22 } },
    },
}

function Level.count() return #Level.DEFS end

function Level.new(n)
    local def = Level.DEFS[n]
    local L = setmetatable({ n = n, def = def, name = def.name, hint = def.hint, w = def.w, h = def.h }, Level)
    L.segs, L.rocks, L.posts = {}, {}, {}

    local function fence(x1, z1, x2, z2)
        L.segs[#L.segs + 1] = { x1, z1, x2, z2 }
    end
    -- Round the field.
    fence(0, 0, L.w, 0); fence(L.w, 0, L.w, L.h); fence(L.w, L.h, 0, L.h); fence(0, L.h, 0, 0)
    for _, f in ipairs(def.fences) do fence(f[1], f[2], f[3], f[4]) end

    -- The pen: four sides, one with the gate cut out of it.
    local p = def.pen
    L.pen = p
    local corners = {
        n = { p.x, p.z, p.x + p.w, p.z }, s = { p.x, p.z + p.h, p.x + p.w, p.z + p.h },
        w = { p.x, p.z, p.x, p.z + p.h }, e = { p.x + p.w, p.z, p.x + p.w, p.z + p.h },
    }
    for side, c in pairs(corners) do
        if side == p.side then
            local len = (side == "n" or side == "s") and p.w or p.h
            local mid, half = len * p.at, p.gap / 2
            local dx, dz = (c[3] - c[1]) / len, (c[4] - c[2]) / len
            fence(c[1], c[2], c[1] + dx * (mid - half), c[2] + dz * (mid - half))
            fence(c[1] + dx * (mid + half), c[2] + dz * (mid + half), c[3], c[4])
        else
            fence(c[1], c[2], c[3], c[4])
        end
    end

    for _, r in ipairs(def.rocks) do L.rocks[#L.rocks + 1] = { x = r[1], z = r[2], r = r[3] } end
    L.ponds = {}
    for _, r in ipairs(def.ponds or {}) do L.ponds[#L.ponds + 1] = { x = r[1], z = r[2], r = r[3] } end
    -- A hay bale at the back of the pen: something for the penned to stand by.
    local hx, hz = p.x + p.w / 2, p.z + 10
    if p.side == "n" then hz = p.z + p.h - 10 end
    L.hay = { x = hx, z = hz, r = 6 }
    L.rocks[#L.rocks + 1] = { x = hx, z = hz, r = 6, hay = true }

    -- Posts along every fence, and the rails between them as pieces, so a sheep
    -- can stand in front of one stretch of fence and behind the next.
    L.rails = {}
    for _, s in ipairs(L.segs) do
        local len = sqrt((s[3] - s[1]) ^ 2 + (s[4] - s[2]) ^ 2)
        local k = max(1, floor(len / POST_GAP + 0.5))
        local px, pz = s[1], s[2]
        L.posts[#L.posts + 1] = { x = px, z = pz }
        for i = 1, k do
            local x, z = s[1] + (s[3] - s[1]) * i / k, s[2] + (s[4] - s[2]) * i / k
            L.posts[#L.posts + 1] = { x = x, z = z }
            L.rails[#L.rails + 1] = { px, pz, x, z }
            px, pz = x, z
        end
    end
    L.ground = L:paintGround()
    return L
end

--- what the flock and the dog ask ------------------------------------------------

-- The nearest point of segment s to (x, z), and how far that is.
local function nearest(s, x, z)
    local ax, az, bx, bz = s[1], s[2], s[3], s[4]
    local dx, dz = bx - ax, bz - az
    local t = ((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz)
    t = max(0, min(1, t))
    local cx, cz = ax + dx * t, az + dz * t
    return cx, cz, sqrt((x - cx) ^ 2 + (z - cz) ^ 2)
end

-- Out of anything solid: a body of radius r at (x, z), put back where it fits.
function Level:collide(x, z, r)
    for _ = 1, 2 do
        for _, s in ipairs(self.segs) do
            local cx, cz, d = nearest(s, x, z)
            local need = r + FENCE_R
            if d < need and d > 1e-6 then
                x, z = cx + (x - cx) / d * need, cz + (z - cz) / d * need
            end
        end
        for _, list in ipairs({ self.rocks, self.ponds }) do
            for _, o in ipairs(list) do
                local dx, dz = x - o.x, z - o.z
                local d, need = sqrt(dx * dx + dz * dz), r + o.r
                if d < need and d > 1e-6 then x, z = o.x + dx / d * need, o.z + dz / d * need end
            end
        end
    end
    return max(r + FENCE_R, min(self.w - r - FENCE_R, x)), max(r + FENCE_R, min(self.h - r - FENCE_R, z))
end

-- Which way is away from what is solid near (x, z), within `range` of its
-- surface: a push straight off it, and a slide along it the way the body is
-- already going (vx, vz), so a flock flows round a rock rather than piling on it.
function Level:repel(x, z, vx, vz, range)
    local fx, fz = 0, 0
    local function add(nx, nz, gap)
        if gap >= range then return end
        local w = 1 - max(0, gap) / range
        w = w * w
        local tx, tz = -nz, nx
        if tx * vx + tz * vz < 0 then tx, tz = -tx, -tz end
        fx, fz = fx + (nx * 0.8 + tx * 0.6) * w, fz + (nz * 0.8 + tz * 0.6) * w
    end
    for _, s in ipairs(self.segs) do
        local cx, cz, d = nearest(s, x, z)
        if d > 1e-6 then add((x - cx) / d, (z - cz) / d, d - FENCE_R) end
    end
    for _, list in ipairs({ self.rocks, self.ponds }) do
        for _, o in ipairs(list) do
            local dx, dz = x - o.x, z - o.z
            local d = sqrt(dx * dx + dz * dz)
            if d > 1e-6 then add(dx / d, dz / d, d - o.r) end
        end
    end
    return fx, fz
end

function Level:inPen(x, z)
    local p = self.pen
    return x > p.x + 2 and x < p.x + p.w - 2 and z > p.z + 2 and z < p.z + p.h - 2
end

-- The middle of the pen, a little in from the gate: where the penned drift to.
function Level:penHeart()
    local p = self.pen
    return p.x + p.w / 2, p.z + p.h / 2
end

--- the picture of the ground -----------------------------------------------------

-- Painted once per level: grass with tufts and the odd flower, straw in the
-- pen, and a darker margin past the fence. One canvas, in field pixels across
-- and foreshortened ones down, with MARGIN to spare all round.
Level.MARGIN = 40

local function hash(x, y)
    local n = (x * 374761393 + y * 668265263) % 2147483647
    n = (n * (n % 1013 + 1009)) % 1000003
    return n / 1000003
end

-- Smooth noise: hashes on a coarse grid, eased between.
local function smooth(i, j, cw, ch, seed)
    local gi, gj = floor(i / cw), floor(j / ch)
    local fi, fj = i / cw - gi, j / ch - gj
    fi, fj = fi * fi * (3 - 2 * fi), fj * fj * (3 - 2 * fj)
    local a, b = hash(gi + seed, gj), hash(gi + 1 + seed, gj)
    local c, d = hash(gi + seed, gj + 1), hash(gi + 1 + seed, gj + 1)
    return (a + (b - a) * fi) * (1 - fj) + (c + (d - c) * fi) * fj
end

function Level:paintGround()
    local SE, M = T.SE, Level.MARGIN
    local w, h = self.w + M * 2, floor(self.h * SE) + M * 2
    local data = love.image.newImageData(w, h)
    local p = self.pen
    local C = G.C
    local function put(i, j, k)
        if i >= 0 and j >= 0 and i < w and j < h then
            local c = C[k]
            data:setPixel(i, j, c[1], c[2], c[3], 1)
        end
    end
    local function inside(i, j)
        local x, z = i - M, (j - M) / SE
        return x >= 2 and z >= 2 and x <= self.w - 2 and z <= self.h - 2
    end
    local function inPen(i, j)
        local x, z = i - M, (j - M) / SE
        return x > p.x and x < p.x + p.w and z > p.z and z < p.z + p.h
    end
    -- How far inside the nearest pond's shore (i, j) is: > 0 is wet.
    local function wet(i, j)
        local x, z, best = i - M, (j - M) / SE, -math.huge
        for _, o in ipairs(self.ponds) do
            best = max(best, o.r - sqrt((x - o.x) ^ 2 + (z - o.z) ^ 2))
        end
        return best
    end
    for j = 0, h - 1 do
        for i = 0, w - 1 do
            local k
            local n = smooth(i, j, 22, 16, self.n * 7)
            if not inside(i, j) then
                -- Past the fence: the hedge-dark rough, a little lighter in places.
                k = (n > 0.6 and G.dither(i, j, (n - 0.6) * 1.2)) and "g" or "t"
            elseif wet(i, j) > -2 then
                -- A pond: a sandy lip, a stony one, then water, lighter
                -- toward the middle, with the odd glint on it.
                local d = wet(i, j)
                if d <= 0 then k = "b"
                elseif d < 1.5 then k = "s"
                else
                    k = "t"
                    if d > 6 and G.dither(i, j, min(0.45, (d - 6) * 0.03)) then k = "g" end
                    if hash(i, j) < 0.012 then k = "m" end
                end
            elseif inPen(i, j) then
                local r = hash(i, j)
                k = r < 0.05 and "w" or (r < 0.08 and "s" or "b")
            else
                -- Grass, in soft lighter and darker drifts.
                k = "g"
                if n > 0.66 and G.dither(i, j, (n - 0.66) * 1.6) then k = "m"
                elseif n < 0.28 and G.dither(i, j, (0.28 - n) * 1.4) then k = "t" end
            end
            put(i, j, k)
        end
    end
    -- Tufts and the odd flower, laid on top as little shapes.
    local rnd = love.math.newRandomGenerator(self.n * 31 + 7)
    for _ = 1, floor(w * h / 260) do
        local i, j = rnd:random(0, w - 1), rnd:random(0, h - 1)
        if inside(i, j) and not inPen(i, j) and wet(i, j) < -3 then
            local r = rnd:random()
            if r < 0.82 then
                -- A tuft: two blades, lit tips, dark roots.
                put(i, j, "t"); put(i + 2, j, "t")
                put(i, j - 1, "m"); put(i + 2, j - 1, "m"); put(i + 1, j, "t"); put(i + 1, j - 2, "m")
            elseif r < 0.92 then
                put(i, j, "w"); put(i - 1, j, "w"); put(i + 1, j, "w"); put(i, j - 1, "w"); put(i, j + 1, "w")
                put(i, j, "b")
            else
                put(i, j, "p"); put(i + 1, j, "p"); put(i, j - 1, "p"); put(i + 1, j - 1, "s")
            end
        end
    end
    local img = love.graphics.newImage(data)
    img:setFilter("nearest", "nearest")
    return img
end

return Level
