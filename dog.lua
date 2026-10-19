-- The dog: the only thing you move. It walks where the stick, the keys or the
-- held pointer say, eases into and out of speed, and slinks low when it is
-- creeping (below the flock's panic threshold) the way a collie stalks.
--
-- Its pressure field is drawn here, dithered in mint round its feet, denser
-- where it presses harder (Flock.pressure, the same curve the sheep feel). It
-- goes cream when the dog is fast enough to panic them.

local Models = require "models"
local Flock = require "flock"
local G = require "gfx"
local T = require "tracer"

local sqrt, min, max, floor, atan2, pi = math.sqrt, math.min, math.max, math.floor, math.atan2, math.pi
local TAU = 2 * pi

local Dog = {}
Dog.__index = Dog

local CONFIG = {
    runSpeed = 112,      -- flat out, field units a second
    walk = 0.42,         -- keys without shift: a share of runSpeed, under the panic threshold
    accel = 6,           -- how quickly it takes up the speed it wants (1/s)
    follow = 2.2,        -- pointer: speed per unit of distance to the point, so a short drag creeps
    radius = 5,
    turnRate = 12,
}
Dog.CONFIG = CONFIG

function Dog.new(x, z)
    return setmetatable({ x = x, z = z, vx = 0, vz = 0, h = 0, gait = 0, speed = 0, radius = CONFIG.radius }, Dog)
end

-- `move` is what input.lua answers: { dir = true, x, z } for a stick or keys
-- (length 0..1), { point = true, x, z } for a field point to go to, or nil.
function Dog:update(dt, move, level)
    local tx, tz = 0, 0
    if move and move.dir then
        tx, tz = move.x * CONFIG.runSpeed, move.z * CONFIG.runSpeed
    elseif move and move.point then
        local dx, dz = move.x - self.x, move.z - self.z
        local d = sqrt(dx * dx + dz * dz)
        if d > 1.5 then
            local s = min(CONFIG.runSpeed, d * CONFIG.follow)
            tx, tz = dx / d * s, dz / d * s
        end
    end
    local k = min(1, CONFIG.accel * dt)
    self.vx, self.vz = self.vx + (tx - self.vx) * k, self.vz + (tz - self.vz) * k
    local ox, oz = self.x, self.z
    self.x, self.z = level:collide(self.x + self.vx * dt, self.z + self.vz * dt, CONFIG.radius)
    -- What it actually covered, so a dog pushing into a fence isn't "fast".
    if dt > 0 then
        local rx, rz = (self.x - ox) / dt, (self.z - oz) / dt
        self.vx, self.vz = self.vx + (rx - self.vx) * 0.5, self.vz + (rz - self.vz) * 0.5
    end
    self.speed = sqrt(self.vx * self.vx + self.vz * self.vz)
    if self.speed > 4 then
        local d = (atan2(self.vz, self.vx) - self.h + pi) % TAU - pi
        self.h = self.h + d * min(1, CONFIG.turnRate * dt)
    end
    self.gait = self.gait + self.speed * dt * 0.28
end

function Dog:panicky()
    return self.speed > Flock.CONFIG.panicThreshold
end

-- The field: every pixel inside the flee radius, on where the dither says.
function Dog:drawField(camx, camy)
    local SE, R = T.SE, Flock.CONFIG.fleeRadius
    local cx, cy = self.x - camx, self.z * SE - camy
    local inner, rim = {}, {}
    local i0, i1 = floor(cx - R), floor(cx + R) + 1
    local j0, j1 = floor(cy - R * SE), floor(cy + R * SE) + 1
    local ix, iy = floor(camx), floor(camy)
    for j = j0, j1 do
        local dz = (j + 0.5 - cy) / SE
        for i = i0, i1 do
            local dx = i + 0.5 - cx
            local d = sqrt(dx * dx + dz * dz)
            if d < R then
                -- Dither on the field's own pixels, so it doesn't crawl as the camera moves.
                local gx, gy = i + ix, j + iy
                if d > R - 1.2 then
                    if (gx + gy) % 2 == 0 then G.plot(rim, i, j) end
                elseif G.dither(gx, gy, 0.05 + Flock.pressure(d) * 0.32) then
                    G.plot(inner, i, j)
                end
            end
        end
    end
    local k = self:panicky() and "w" or "m"
    G.points(k, inner)
    G.points(k, rim)
end

function Dog:queue(into, camx, camy)
    local sx, sy = floor(self.x - camx + 0.5), floor(self.z * T.SE - camy + 0.5)
    local moving = self.speed > 5
    local gait = moving and floor(self.gait) % 4 or 0
    -- Low when creeping, up when standing or running.
    local crouch = (moving and not self:panicky()) and 2 or (self.speed > 2 and 1 or 0)
    local pic = Models.dog(self.h, gait, crouch)
    into[#into + 1] = { z = self.z, draw = function()
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(pic.img, sx - pic.oi, sy - pic.oj)
    end }
end

function Dog:shadow(camx, camy)
    G.ellipse("t", self.x - camx, self.z * T.SE - camy + 1, 6, 3)
end

return Dog
