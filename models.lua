-- The bodies, built of ellipsoids for tracer.lua: herding's sheep, dog and
-- fence post, and the few the bedtime needs (pajamas, a golden fleece, drones,
-- the moon). Survive School's lesson, kept: a pose is *numbers*, not a held
-- picture. Each model is a function from a few small numbers to a list of
-- parts, painted the first time those numbers are asked for and kept under
-- them, so forty sheep cost what one does.
--
-- Model front is +x; a heading h turns it to face (cos h, sin h) on the field,
-- positive towards the viewer.

local T = require "tracer"
local G = require "gfx"
local A = T.A

local floor, sin, pi = math.floor, math.sin, math.pi
local TAU = 2 * pi
local ell, ramp = T.ell, T.ramp

local M = {}

M.HEADINGS = 16

local RAMP = {
    wool = ramp("w", "w", "b", "s"),
    gold = ramp("w", "y", "y", "h"),
    pj = ramp("w", "l", "l", "i"),
    face = ramp("b", "s", "p", "o"),
    coat = ramp("b", "s", "p", "o"),
    white = ramp("w", "w", "b", "s"),
    wood = ramp("w", "b", "s", "p"),
    goldWood = ramp("w", "y", "h", "p"),
    metal = ramp("w", "b", "s", "p"),
    moon = ramp("w", "l", "i", "p"),
    cloud = ramp("w", "c", "c", "l"),
    dreamFace = ramp("c", "l", "i", "u"),
}

local cache = {}
local function kept(key, build)
    local p = cache[key]
    if not p then
        p = T.paint(build())
        cache[key] = p
    end
    return p
end

-- A heading to the nearest of M.HEADINGS steps, and back to an angle.
function M.step(h)
    return floor(((h % TAU) / TAU) * M.HEADINGS + 0.5) % M.HEADINGS
end
local function angle(step) return step / M.HEADINGS * TAU end

--- the sheep ----------------------------------------------------------------------

-- `squash` -2..3 (below 0 stretched in the air, above it flattened landing),
-- `leg` 0/1 trotting or 2 leaping, `look` "plain", "pj" (striped pajamas and
-- a nightcap), "gold" or "cloud" (the lucid dream's: wool turning to sky, no
-- legs, it floats), `graze` head down, `size` 1 or less.
function M.sheep(h, squash, leg, look, graze, size)
    local hs = M.step(h)
    squash, leg, look, size = squash or 0, leg or 0, look or "plain", size or 1
    return kept(("sheep%d.%d.%d.%s.%s.%s"):format(hs, squash, leg, look, graze and 1 or 0, size), function()
        local W = look == "gold" and RAMP.gold or (look == "cloud" and RAMP.cloud or RAMP.wool)
        local F = look == "cloud" and RAMP.dreamFace or RAMP.face
        -- A cloud of wool: one material, so neighbouring puffs crease into
        -- each other, but each its own part, so a puff in front is inked.
        local function puff(x, y, z, rx, ry, rz, id)
            local p = ell(x, y, z, rx, ry, rz, W, id)
            p.mat = 1
            if look == "pj" then
                -- Lavender stripes across the wool in room height, so they run
                -- on from puff to puff.
                p.print = function(_, uy, _, lv)
                    if floor((y + uy * ry) / 1.7) % 2 == 1 or lv == 1 then return nil end
                    return lv >= 4 and "i" or "l"
                end
            end
            return p
        end
        local parts = {
            puff(-0.4, 5.0, 0, 6.0, 4.2, 4.8, 1),
            puff(-3.0, 7.0, 1.8, 3.4, 3.0, 3.0, 11),
            puff(-2.8, 7.0, -2.0, 3.3, 3.0, 3.0, 12),
            puff(1.0, 7.6, 1.6, 3.3, 3.0, 3.0, 13),
            puff(1.0, 7.5, -1.8, 3.3, 3.0, 3.0, 14),
            puff(-5.4, 5.6, 0, 2.6, 2.6, 2.8, 15),
        }
        local hx, hy = 6.4, 6.6
        if graze then hx, hy = 7.2, 2.8 end
        parts[#parts + 1] = ell(hx, hy, 0, 3.0, 2.7, 2.5, F, 2)
        parts[#parts + 1] = ell(hx + 2.0, hy - 0.8, 0, 1.5, 1.6, 1.6, F, 2)
        parts[#parts + 1] = ell(hx - 0.6, hy + 1.0, 2.8, 0.8, 1.0, 1.4, F, 3)
        parts[#parts + 1] = ell(hx - 0.6, hy + 1.0, -2.8, 0.8, 1.0, 1.4, F, 3)
        if look == "pj" then
            -- A nightcap tipped back, a cream cuff, a bobble.
            local cap = ell(hx - 1.4, hy + 3.0, 0, 2.2, 1.6, 2.2, RAMP.pj, 16)
            cap.print = function(_, uy) return uy < -0.4 and "w" or nil end
            parts[#parts + 1] = cap
            parts[#parts + 1] = ell(hx - 3.6, hy + 4.2, 0, 1.4, 1.2, 1.4, RAMP.pj, 17)
            parts[#parts + 1] = ell(hx - 5.0, hy + 4.0, 0, 1.0, 1.0, 1.0, RAMP.white, 18)
        else
            parts[#parts + 1] = puff(hx - 1.6, hy + 2.2, 0, 2.0, 1.4, 1.8, 16) -- the topknot
        end
        local legs
        if leg == 2 then -- mid-leap: fronts reaching forward, backs kicked back
            legs = { { 3.4, 2.4, 1.8, 0.6 }, { 3.4, -2.4, 1.8, 0.6 }, { -3.4, 2.4, -1.8, 0.6 }, { -3.4, -2.4, -1.8, 0.6 } }
        else
            local s = leg == 1 and 0.9 or -0.9
            legs = { { 3.4, 2.4, s, 0 }, { 3.4, -2.4, -s, 0 }, { -3.4, 2.4, -s, 0 }, { -3.4, -2.4, s, 0 } }
        end
        if look ~= "cloud" then
            for _, l in ipairs(legs) do
                parts[#parts + 1] = ell(l[1] + l[3], 1.2 + l[4], l[2], 1.0, 1.7, 1.0, RAMP.face, 4)
            end
        end
        local q = squash * 0.07
        return T.place(parts, A.mul(A.scale(size, size, size), A.rotY(-angle(hs)), A.scale(1 + q, 1 - q * 1.6, 1 + q)))
    end)
end

--- the dog ------------------------------------------------------------------------

-- herding's collie: dark coat, cream chest, muzzle and tail tip. `gait` 0..3
-- is where the legs are in the stride.
function M.dog(h, gait)
    local hs = M.step(h)
    return kept(("dog%d.%d"):format(hs, gait), function()
        local C, Wt = RAMP.coat, RAMP.white
        local hy = 9.4
        local parts = {
            ell(0, 6.4, 0, 6.2, 3.6, 3.4, C, 1),
            ell(4.2, 6.4, 0, 2.8, 3.2, 3.0, Wt, 2), -- the white chest and ruff
            ell(7.2, hy, 0, 3.1, 2.9, 2.8, C, 3),
            ell(9.8, hy - 1.0, 0, 2.0, 1.4, 1.5, Wt, 4), -- muzzle
            ell(10.9, hy - 0.6, 0, 0.7, 0.6, 0.7, C, 9), -- nose
            ell(6.4, hy + 2.6, 1.6, 0.8, 1.6, 0.9, C, 5),
            ell(6.4, hy + 2.6, -1.6, 0.8, 1.6, 0.9, C, 5),
            ell(-7.0, 7.2, 0, 3.0, 1.7, 1.6, C, 6), -- a brush of a tail
            ell(-9.6, 7.8, 0, 1.6, 1.4, 1.3, Wt, 7),
        }
        local swing = sin(gait / 4 * TAU) * 1.8
        for _, l in ipairs({ { 3.8, 2.0, 1 }, { 3.8, -2.0, -1 }, { -3.8, 2.0, -1 }, { -3.8, -2.0, 1 } }) do
            parts[#parts + 1] = ell(l[1] + swing * l[3], 1.6, l[2], 1.1, 2.0, 1.1, l[1] > 0 and Wt or C, 8)
        end
        return T.place(parts, A.mul(A.scale(0.8, 0.8, 0.8), A.rotY(-angle(hs))))
    end)
end

--- the field ------------------------------------------------------------------

-- The fence the sheep hop: herding's posts, two of them, and two rails. Wood,
-- then a white picket with the first Better Fence, gold caps from the third.
-- `squash` 0..2 is the bounce a tap gives it.
function M.fence(level, squash)
    local look = level >= 3 and 2 or (level >= 1 and 1 or 0)
    return kept(("fence%d.%d"):format(look, squash), function()
        local W = look >= 1 and RAMP.white or RAMP.wood
        local cap = look == 2 and RAMP.goldWood or W
        local parts = {}
        for _, x in ipairs({ -7.5, 7.5 }) do
            parts[#parts + 1] = ell(x, 6, 0, 1.6, 6.4, 1.6, W, 1)
            parts[#parts + 1] = ell(x, 12.6, 0, 1.8, 1.1, 1.8, cap, 2)
        end
        parts[#parts + 1] = ell(0, 9.2, 0.6, 9.4, 1.1, 1.0, W, 3)
        parts[#parts + 1] = ell(0, 4.8, 0.6, 9.4, 1.1, 1.0, W, 4)
        local q = squash * 0.06
        return T.place(parts, A.scale(1.25 + q * 0.5, 1.25 - q, 1.25))
    end)
end

-- A post on its own, for the Breeding Pen.
function M.post()
    return kept("post", function()
        return T.place({ ell(0, 5, 0, 1.5, 5.5, 1.5, RAMP.wood, 1), ell(0, 10.4, 0, 1.7, 0.9, 1.7, RAMP.wood, 2) },
            A.scale(0.6, 0.6, 0.6))
    end)
end

-- A counting drone: a body, a lens, four rotors. `tilt` -1..1 leans it into its flight.
function M.drone(tilt)
    return kept("drone" .. tilt, function()
        return T.place({
            ell(0, 0, 0, 3.2, 1.6, 3.2, RAMP.metal, 1),
            ell(0, -1.2, 0, 1.4, 1.0, 1.4, RAMP.moon, 5),
            ell(-4, 1.2, -3, 2.0, 0.4, 2.0, RAMP.white, 2),
            ell(4, 1.2, -3, 2.0, 0.4, 2.0, RAMP.white, 3),
            ell(-4, 1.2, 3, 2.0, 0.4, 2.0, RAMP.white, 4),
            ell(4, 1.2, 3, 2.0, 0.4, 2.0, RAMP.white, 6),
        }, A.rotZ(tilt * 0.12))
    end)
end

--- the dream's farm -----------------------------------------------------------------

-- Phase 2's farm on the hill, built of the same parts as the sheep: boxes for
-- walls (the crease pass draws their corners), boxes turned 45 degrees for
-- roofs, balls for trees, hay and stones. Doors and windows are printed on
-- the faces. Keyed by the old town's ids (lucid/scene.lua's ART). Each is
-- painted at a size (`size`, about pixels a unit), turned a little to show
-- two sides (`turn`, radians), and dithered towards the horizon's lilac by
-- `haze` (0..1), all kept.
local FARM = {
    barn = ramp("w", "r", "r", "i"),
    roof = ramp("l", "i", "p", "o"),
    rose = ramp("w", "r", "i", "p"),
    plank = ramp("w", "b", "s", "p"),
    wall = ramp("w", "c", "l", "i"),
    leaf = ramp("m", "g", "g", "t"),
    bark = ramp("b", "h", "h", "p"),
    hay = ramp("w", "y", "y", "h"),
    stone = ramp("w", "s", "s", "p"),
    water = ramp("w", "c", "l", "i"),
    well = ramp("a", "u", "u", "n"),
    grass = ramp("m", "g", "t", "t"),
}

-- A gable roof along x: a box turned 45 degrees about its ridge, then
-- squashed to `h` high and `d` deep (each half), `len` long (half).
local function roof(x, y, z, len, d, h, r, id)
    local p = ell(0, 0, 0, 1, 1, 1, r, id)
    p.box = true
    local k = 1 / math.sqrt(2)
    p.at = A.mul(A.move(x, y, z), A.scale(1, h / d, 1), A.rotX(pi / 4), A.scale(len, d * k, d * k))
    return p
end
local function box(...) return T.box(...) end

-- What each one is made of. `foot` is the ground, y up, z towards you.
local BUILD = {
    -- Barn: rose boards, a cream-framed door with its brace, the hayloft lit.
    mill = function()
        local walls = box(0, 5, 0, 7, 5, 5, FARM.barn, 1)
        walls.print = function(ux, uy, uz)
            if uz < 0.98 then return nil end
            local ax = math.abs(ux)
            if ax < 0.42 and uy < 0.3 then
                if ax > 0.34 or uy > 0.2 then return "w" end
                if math.abs(math.abs(ux) - (uy + 1) / 1.3 * 0.34) < 0.06 then return "w" end
                return "p"
            end
            if ax < 0.14 and uy > 0.5 and uy < 0.85 then return "y" end
        end
        return { walls, roof(0, 10, 0, 7.8, 6, 4.5, FARM.roof, 2) }
    end,
    -- Dog Kennel: plank walls, a rose roof, the dark door.
    inn = function()
        local walls = box(0, 2.8, 0, 4, 2.8, 3.2, FARM.plank, 1)
        walls.print = function(ux, uy, uz)
            if uz > 0.98 and math.abs(ux) < 0.4 and uy < 0.45 then return "o" end
        end
        return { walls, roof(0, 5.6, 0, 4.6, 3.9, 3, FARM.rose, 2), ell(5.6, 0.3, 2, 1.2, 0.5, 1.2, FARM.stone, 3) }
    end,
    -- Better Fence: white pickets, gold caps, two rails.
    clock = function()
        local parts = {}
        for i, x in ipairs({ -7, -2.3, 2.3, 7 }) do
            parts[#parts + 1] = box(x, 3.6, 0, 0.9, 3.6, 0.9, RAMP.white, 1)
            parts[#parts + 1] = ell(x, 7.6, 0, 1.1, 0.9, 1.1, RAMP.goldWood, 2)
        end
        parts[#parts + 1] = box(0, 2, 0.9, 8.2, 0.7, 0.45, RAMP.white, 3)
        parts[#parts + 1] = box(0, 5, 0.9, 8.2, 0.7, 0.45, RAMP.white, 4)
        return parts
    end,
    -- Meadow: a round tree on a green mound, flowers in the grass.
    bakery = function()
        local parts = {
            ell(0, 0, 0, 7.5, 0.9, 4.5, FARM.grass, 1),
            ell(2.5, 3.5, -0.5, 1.2, 3.5, 1.2, FARM.bark, 2),
            ell(2.5, 9.5, -0.5, 5, 4.2, 4.4, FARM.leaf, 3),
            ell(0.6, 11.4, 1, 3, 2.6, 2.8, FARM.leaf, 4),
            ell(5.6, 10.2, 1.2, 2.6, 2.4, 2.6, FARM.leaf, 5),
        }
        parts[1].above = true
        local keys = { RAMP.gold, FARM.rose, RAMP.white, RAMP.gold, FARM.rose }
        for i = 1, 5 do parts[#parts + 1] = ell(-6 + i * 1.6, 1.3, 1.5 + (i % 2) * 1.2, 0.6, 0.5, 0.6, keys[i], 5 + i) end
        return parts
    end,
    -- Breeding Pen: a ring of posts (the lamb is the scene's, it bounces).
    hut = function()
        local parts = {}
        for i = 0, 9 do
            local a = i / 10 * TAU
            parts[#parts + 1] = box(math.cos(a) * 7, 2.4, math.sin(a) * 4.2, 0.75, 2.4, 0.75, FARM.plank, i + 1)
            parts[#parts + 1] = ell(math.cos(a) * 7, 5, math.sin(a) * 4.2, 0.9, 0.5, 0.9, FARM.plank, i + 11)
        end
        parts[#parts + 1] = ell(0, 0, 0, 7.5, 0.6, 4.6, FARM.grass, 30)
        parts[#parts].above = true
        return parts
    end,
    -- Wool Mill: a lilac workshop, its window lit, a chimney, a spinning wheel.
    workshop = function()
        local walls = box(-1.5, 4, 0, 5, 4, 4, FARM.wall, 1)
        walls.print = function(ux, uy, uz)
            if uz < 0.98 then return nil end
            if ux > -0.75 and ux < -0.25 and uy > 0 and uy < 0.45 then return "y" end
            if ux > 0.15 and ux < 0.55 and uy < 0.1 then return "p" end
        end
        return {
            walls, roof(-1.5, 8, 0, 5.6, 4.8, 3.4, FARM.roof, 2),
            box(-4, 10, -1, 0.8, 2, 0.8, FARM.stone, 3),
            ell(6, 4.2, 1.5, 3, 3, 0.45, FARM.plank, 4),
            ell(6, 4.2, 2.1, 0.8, 0.8, 0.4, RAMP.goldWood, 5),
            box(6, 1, 1.5, 0.5, 1, 0.5, FARM.plank, 6),
        }
    end,
    -- Counting Drones: a mast on a plinth, a dish (the drone is the scene's).
    observatory = function()
        local dish = ell(0, 13.5, 0.8, 3.6, 1, 3.6, RAMP.metal, 3)
        dish.at = A.mul(A.move(0, 13.5, 0.8), A.rotX(0.6), A.scale(3.6, 1.1, 3.6))
        return {
            box(0, 1, 0, 3.4, 1, 3.4, FARM.stone, 1),
            box(0, 7, 0, 0.9, 6, 0.9, RAMP.metal, 2),
            box(0, 7, 0, 2, 0.4, 2, RAMP.metal, 4),
            dish,
        }
    end,
    -- Haystack: a gold dome on the ground, a smaller one beside it.
    plaza = function()
        local a = ell(0, 0, 0, 5, 6.5, 4.5, FARM.hay, 1)
        local b = ell(4.6, 0, 2, 2.6, 3.2, 2.4, FARM.hay, 2)
        a.above, b.above = true, true
        return { a, b }
    end,
    -- Wishing Well: a stone ring, dark water, two posts and a little roof.
    fountain = function()
        local ring = ell(0, 0, 0, 3.8, 3, 3.8, FARM.stone, 1)
        ring.above = true
        return {
            ring, ell(0, 3, 0, 2.8, 0.15, 2.8, FARM.well, 2),
            box(-3.2, 5, 0, 0.4, 2.6, 0.4, FARM.bark, 3), box(3.2, 5, 0, 0.4, 2.6, 0.4, FARM.bark, 4),
            roof(0, 8, 0, 4.4, 2.8, 2.2, FARM.roof, 5),
            ell(0, 5.2, 0, 0.7, 0.8, 0.7, RAMP.metal, 6),
        }
    end,
    -- Sheepfold: a low ring of stones (the sheep in it is the scene's).
    fold = function()
        local parts = {}
        for i = 0, 9 do
            local a = i / 10 * TAU
            parts[#parts + 1] = ell(math.cos(a) * 6.5, 1, math.sin(a) * 3.6, 1.6, 1.4, 1.3, FARM.stone, i + 1)
        end
        return parts
    end,
    -- Mirror Lake: flat water lying in the grass, a rim of reeds.
    mirror = function()
        local water = ell(0, 0.6, 0, 8.5, 0.2, 4.2, FARM.water, 1)
        water.print = function(ux, _, uz)
            if math.abs(uz + ux * 0.3) < 0.08 then return "a" end
            if math.abs(uz - 0.4 + ux * 0.2) < 0.05 then return "w" end
        end
        local parts = { ell(0, 0, 0, 9.5, 0.6, 5, FARM.grass, 2), water }
        parts[1].above = true
        for i = 0, 4 do parts[#parts + 1] = ell(-8 + i * 0.9, 1.4, -2 + i * 0.5, 0.3, 1.6, 0.3, FARM.leaf, 3 + i) end
        return parts
    end,
}
M.FARM_BUILDS = BUILD

function M.building(id, size, turn, haze)
    local make = BUILD[id]
    if not make then return nil end
    size, turn, haze = size or 1, turn or 0, haze or 0
    local key = ("farm.%s.%.2f.%.2f.%.2f"):format(id, size, turn, haze)
    local p = cache[key]
    if not p then
        local parts = T.place(make(), A.mul(A.scale(size, size, size), A.rotY(turn)))
        p = T.paint(parts, nil, haze > 0 and function(k, i, j)
            return G.dither(i, j, haze) and "i" or k
        end or nil)
        cache[key] = p
    end
    return p
end

-- The moon, a few craters printed a shade down.
function M.moon(r)
    return kept("moon" .. r, function()
        local p = ell(0, 0, 0, r, r, r, RAMP.moon, 1)
        local craters = { { 0.3, 0.4, 0.86 }, { -0.5, -0.1, 0.86 }, { 0.1, -0.55, 0.83 } }
        p.print = function(ux, uy, uz, lv)
            for _, c in ipairs(craters) do
                if (ux - c[1]) ^ 2 + (uy - c[2]) ^ 2 + (uz - c[3]) ^ 2 < 0.05 then return lv >= 3 and "p" or "i" end
            end
        end
        return { p }
    end)
end

return M
