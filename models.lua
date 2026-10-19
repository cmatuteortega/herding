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
-- a nightcap) or "gold", `graze` head down, `size` 1 or less.
function M.sheep(h, squash, leg, look, graze, size)
    local hs = M.step(h)
    squash, leg, look, size = squash or 0, leg or 0, look or "plain", size or 1
    return kept(("sheep%d.%d.%d.%s.%s.%s"):format(hs, squash, leg, look, graze and 1 or 0, size), function()
        local W = look == "gold" and RAMP.gold or RAMP.wool
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
        parts[#parts + 1] = ell(hx, hy, 0, 3.0, 2.7, 2.5, RAMP.face, 2)
        parts[#parts + 1] = ell(hx + 2.0, hy - 0.8, 0, 1.5, 1.6, 1.6, RAMP.face, 2)
        parts[#parts + 1] = ell(hx - 0.6, hy + 1.0, 2.8, 0.8, 1.0, 1.4, RAMP.face, 3)
        parts[#parts + 1] = ell(hx - 0.6, hy + 1.0, -2.8, 0.8, 1.0, 1.4, RAMP.face, 3)
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
        for _, l in ipairs(legs) do
            parts[#parts + 1] = ell(l[1] + l[3], 1.2 + l[4], l[2], 1.0, 1.7, 1.0, RAMP.face, 4)
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
