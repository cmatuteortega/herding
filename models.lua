-- The bodies, built of ellipsoids for tracer.lua. Survive School's lesson: a
-- pose is *numbers*, not a held picture. Each model is a function from a few
-- small numbers (a heading step, a squash step, a leg step) to a list of parts,
-- and its picture is painted the first time those numbers are asked for and
-- kept under them. Thirty sheep cost what one does: they look the same handful
-- of pictures up.
--
-- Model front is +x; a heading h turns it to face (cos h, sin h) on the field.

local T = require "tracer"
local A = T.A

local floor, sin, cos, pi = math.floor, math.sin, math.cos, math.pi
local TAU = 2 * pi
local ell, ramp = T.ell, T.ramp

local M = {}

M.HEADINGS = 16

local RAMP = {
    wool = ramp("w", "w", "b", "s"),
    face = ramp("b", "s", "p", "o"),
    coat = ramp("b", "s", "p", "o"),
    white = ramp("w", "w", "b", "s"),
    rock = ramp("w", "m", "s", "t"),
    wood = ramp("w", "b", "s", "p"),
    hay = ramp("w", "w", "b", "s"),
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

-- `squash` 0..3 (flattened as it lands from a hop), `graze` true with its head
-- down in the grass, `leg` 0..1 (which pair is forward).
function M.sheep(h, squash, graze, leg)
    local hs = M.step(h)
    return kept(("sheep%d.%d.%s.%d"):format(hs, squash, graze and 1 or 0, leg), function()
        local W = RAMP.wool
        -- A cloud of wool: one material, so neighbouring puffs crease into
        -- each other, but each its own part, so a puff in front is inked.
        local function puff(x, y, z, rx, ry, rz, id)
            local p = ell(x, y, z, rx, ry, rz, W, id)
            p.mat = 1
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
        parts[#parts + 1] = ell(hx, hy, 0, 3.0, 2.7, 2.5, RAMP.face, 2)
        parts[#parts + 1] = ell(hx + 2.0, hy - 0.8, 0, 1.5, 1.6, 1.6, RAMP.face, 2)
        parts[#parts + 1] = ell(hx - 0.6, hy + 1.0, 2.8, 0.8, 1.0, 1.4, RAMP.face, 3)
        parts[#parts + 1] = ell(hx - 0.6, hy + 1.0, -2.8, 0.8, 1.0, 1.4, RAMP.face, 3)
        parts[#parts + 1] = puff(hx - 1.6, hy + 2.2, 0, 2.0, 1.4, 1.8, 16) -- the topknot
        local s = leg == 1 and 0.9 or -0.9
        for _, l in ipairs({ { 3.4, 2.4, s }, { 3.4, -2.4, -s }, { -3.4, 2.4, -s }, { -3.4, -2.4, s } }) do
            parts[#parts + 1] = ell(l[1] + l[3], 1.2, l[2], 1.0, 1.7, 1.0, RAMP.face, 4)
        end
        local q = squash * 0.06
        return T.place(parts, A.mul(A.rotY(-angle(hs)), A.scale(1 + q, 1 - q * 1.6, 1 + q)))
    end)
end

--- the dog ------------------------------------------------------------------------

-- A small collie: dark coat, cream chest, muzzle and tail tip. `gait` 0..3 is
-- where the legs are in the stride; `crouch` 0..2 is how low it slinks (the
-- stalk a herding dog does when it is creeping up on a flock).
function M.dog(h, gait, crouch)
    local hs = M.step(h)
    return kept(("dog%d.%d.%d"):format(hs, gait, crouch), function()
        local C, Wt = RAMP.coat, RAMP.white
        local lo = crouch * 1.2
        local hy = 9.4 - lo * 1.5
        local parts = {
            ell(0, 6.4 - lo, 0, 6.2, 3.6, 3.4, C, 1),
            ell(4.2, 6.4 - lo, 0, 2.8, 3.2, 3.0, Wt, 2),     -- the white chest and ruff
            ell(7.2, hy, 0, 3.1, 2.9, 2.8, C, 3),
            ell(9.8, hy - 1.0, 0, 2.0, 1.4, 1.5, Wt, 4),     -- muzzle
            ell(10.9, hy - 0.6, 0, 0.7, 0.6, 0.7, C, 9),     -- nose
            ell(6.4, hy + 2.6, 1.6, 0.8, 1.6, 0.9, C, 5),
            ell(6.4, hy + 2.6, -1.6, 0.8, 1.6, 0.9, C, 5),
            ell(-7.0, 7.2 - lo, 0, 3.0, 1.7, 1.6, C, 6),     -- a brush of a tail
            ell(-9.6, 7.8 - lo * 1.2, 0, 1.6, 1.4, 1.3, Wt, 7),
        }
        local swing = sin(gait / 4 * TAU) * 1.8
        for _, l in ipairs({ { 3.8, 2.0, 1 }, { 3.8, -2.0, -1 }, { -3.8, 2.0, -1 }, { -3.8, -2.0, 1 } }) do
            parts[#parts + 1] = ell(l[1] + swing * l[3], 1.6, l[2], 1.1, 2.0 - lo * 0.3, 1.1,
                l[1] > 0 and Wt or C, 8)
        end
        return T.place(parts, A.rotY(-angle(hs)))
    end)
end

--- the field ------------------------------------------------------------------

function M.post()
    return kept("post", function()
        return { ell(0, 5, 0, 1.5, 5.5, 1.5, RAMP.wood, 1), ell(0, 10.4, 0, 1.7, 0.9, 1.7, RAMP.wood, 2) }
    end)
end

-- A rock of radius r: a few lumps, a different few for each seed.
function M.rock(r, seed)
    r = floor(r + 0.5)
    return kept(("rock%d.%d"):format(r, seed % 4), function()
        local parts, rnd = {}, love.math.newRandomGenerator(seed % 4 + 1)
        parts[1] = ell(0, r * 0.45, 0, r, r * 0.75, r * 0.9, RAMP.rock, 1)
        for n = 1, 3 do
            local a = rnd:random() * TAU
            local s = r * (0.45 + rnd:random() * 0.2)
            parts[#parts + 1] = ell(cos(a) * r * 0.55, s * 0.6, sin(a) * r * 0.5, s, s * 0.8, s, RAMP.rock, 1 + n)
        end
        return parts
    end)
end

function M.hay()
    return kept("hay", function()
        return { ell(0, 4, 0, 7, 4.5, 4.5, RAMP.hay, 1), ell(0, 4.6, 0, 5.5, 4.4, 4.7, RAMP.hay, 1) }
    end)
end

return M
