-- The flock: boids (separation, cohesion, alignment), a slow wander and
-- grazing so it is alive when left alone, and the dog's pressure on top.
--
-- The dog never tells a sheep anything. Inside the flee radius a sheep wants
-- to be further away, more the nearer it is (`Flock.pressure`, which the dog's
-- field is drawn with too, so what you see is what they feel). Come in faster
-- than `panicThreshold` and the sheep near you panic: they run faster, hold
-- together less, jitter, and pass it on to their neighbours, and it takes a
-- few seconds to wear off. Squeezed too hard in a gap, they fret too, so a gate
-- rushed is a gate jammed.
--
-- Every number worth turning is in CONFIG.

local Models = require "models"
local G = require "gfx"
local T = require "tracer"

local sqrt, max, min, abs, sin, cos, atan2, floor, random = math.sqrt, math.max, math.min, math.abs, math.sin, math.cos,
    math.atan2, math.floor, love.math.random
local TAU = 2 * math.pi

local Flock = {}
Flock.__index = Flock

local CONFIG = {
    -- the body
    radius = 5.5,            -- a sheep, for bumping into things and each other
    walkSpeed = 30,          -- calm top speed, field units a second
    panicSpeed = 84,         -- top speed at full panic
    response = 2.6,          -- how quickly a calm sheep takes up a new velocity (1/s)
    panicResponse = 6.0,     -- ... and a panicked one
    turnRate = 7,            -- heading follows velocity at this rate (1/s)

    -- boids
    viewRadius = 46,         -- neighbours within this are the flock
    separationRadius = 14,   -- closer than this, give each other room
    separationWeight = 1.7,
    cohesionWeight = 0.6,    -- the main thing panic takes away
    alignmentWeight = 0.5,

    -- left alone
    wanderWeight = 0.28,
    wanderTurn = 1.8,        -- how fast the wander direction drifts (rad/s)
    grazeChance = 0.18,      -- a calm, slow sheep starts grazing this often (1/s)
    grazeTime = { 2, 6 },    -- seconds, at random between

    -- the dog
    fleeRadius = 58,         -- the pressure field's reach
    fleeStrength = 3.0,      -- desired speed at the dog's feet, in walkSpeeds
    fleeFalloff = 1.6,       -- pressure = (1 - d / fleeRadius) ^ this
    panicThreshold = 58,     -- dog speed above which nearby sheep start to panic
    panicGain = 2.4,         -- how fast panic builds at full overspeed, point blank
    panicDecay = 0.3,        -- how fast it wears off (1/s)
    panicSpread = 0.7,       -- a sheep is lifted toward this share of its neighbours' panic
    crowdStress = 0.22,      -- panic a second for each neighbour pressed against it past three

    -- the world
    obstacleRange = 14,      -- fences and rocks start pushing this far off their surface
    obstacleWeight = 2.2,
    penPull = 0.35,          -- inside the pen, a gentle drift toward its heart
}
Flock.CONFIG = CONFIG

-- How hard the dog presses at distance d, 0..1.
function Flock.pressure(d)
    if d >= CONFIG.fleeRadius then return 0 end
    return (1 - d / CONFIG.fleeRadius) ^ CONFIG.fleeFalloff
end

local function clampLen(x, z, m)
    local l = sqrt(x * x + z * z)
    if l > m then return x / l * m, z / l * m end
    return x, z
end

-- Sheep in little bunches round each spawn point, facing every which way.
function Flock.new(level)
    local self = setmetatable({ list = {}, level = level }, Flock)
    for _, s in ipairs(level.def.flock) do
        for _ = 1, s.n do
            local a, r = random() * TAU, sqrt(random()) * s.r
            local h = random() * TAU
            self.list[#self.list + 1] = {
                x = s.x + cos(a) * r, z = s.z + sin(a) * r,
                vx = 0, vz = 0, h = h, wander = h,
                panic = 0, graze = random() < 0.5 and random() * 4 or 0,
                bob = random() * TAU, breath = random() * TAU, crowd = 0,
            }
        end
    end
    for _, s in ipairs(self.list) do s.x, s.z = level:collide(s.x, s.z, CONFIG.radius) end
    return self
end

function Flock:update(dt, dog)
    local C, L, list = CONFIG, self.level, self.list
    local n = #list
    local hx, hz = L:penHeart()
    local dogSpeed = sqrt(dog.vx * dog.vx + dog.vz * dog.vz)
    local overspeed = max(0, dogSpeed - C.panicThreshold) / C.panicThreshold

    for i = 1, n do
        local s = list[i]
        local cx, cz, ax, az, sx, sz, count, nbPanic, crowd = 0, 0, 0, 0, 0, 0, 0, 0, 0
        for j = 1, n do
            if j ~= i then
                local o = list[j]
                local dx, dz = o.x - s.x, o.z - s.z
                local d2 = dx * dx + dz * dz
                if d2 < C.viewRadius * C.viewRadius then
                    local d = sqrt(d2) + 1e-6
                    cx, cz, count = cx + o.x, cz + o.z, count + 1
                    ax, az = ax + o.vx, az + o.vz
                    nbPanic = nbPanic + o.panic
                    if d < C.separationRadius then
                        local w = 1 - d / C.separationRadius
                        sx, sz = sx - dx / d * w, sz - dz / d * w
                    end
                    if d < C.radius * 2.3 then crowd = crowd + 1 end
                end
            end
        end
        s.crowd = crowd

        -- The dog.
        local ddx, ddz = s.x - dog.x, s.z - dog.z
        local dd = sqrt(ddx * ddx + ddz * ddz) + 1e-6
        local press = Flock.pressure(dd)
        local fx, fz = ddx / dd * press * C.fleeStrength, ddz / dd * press * C.fleeStrength

        -- Panic: built by a dog rushing in, caught off neighbours, and from
        -- being squeezed; it wears off on its own.
        local p = s.panic
        p = p + overspeed * press * C.panicGain * dt * 2
        if count > 0 then
            local lift = nbPanic / count * C.panicSpread
            if lift > p then p = p + (lift - p) * min(1, dt * 1.5) end
        end
        if crowd > 3 then p = p + (crowd - 3) * C.crowdStress * dt end
        p = p - C.panicDecay * dt
        s.panic = max(0, min(1, p))
        local calm = 1 - s.panic

        -- Grazing: a calm, idle sheep puts its head down for a while.
        local speed = sqrt(s.vx * s.vx + s.vz * s.vz)
        if s.graze > 0 then
            s.graze = s.graze - dt
            if press > 0.05 or s.panic > 0.15 then s.graze = 0 end
        elseif press == 0 and s.panic < 0.05 and speed < C.walkSpeed * 0.4 and random() < C.grazeChance * dt then
            s.graze = C.grazeTime[1] + random() * (C.grazeTime[2] - C.grazeTime[1])
        end

        -- The wander: a direction that drifts slowly, followed only gently.
        s.wander = s.wander + (random() - 0.5) * 2 * C.wanderTurn * dt * 2
        local ww = s.graze > 0 and 0 or C.wanderWeight * calm
        local wx, wz = cos(s.wander) * ww, sin(s.wander) * ww

        -- Boids.
        local kx, kz, gx, gz = 0, 0, 0, 0
        if count > 0 then
            local mx, mz = cx / count - s.x, cz / count - s.z
            local ml = sqrt(mx * mx + mz * mz) + 1e-6
            local pull = min(1, ml / C.viewRadius) * C.cohesionWeight * (0.15 + 0.85 * calm)
            kx, kz = mx / ml * pull, mz / ml * pull
            gx, gz = clampLen(ax / count / C.walkSpeed, az / count / C.walkSpeed, 1)
            gx, gz = gx * C.alignmentWeight * (0.4 + 0.6 * calm), gz * C.alignmentWeight * (0.4 + 0.6 * calm)
        end
        sx, sz = clampLen(sx, sz, 2)
        local sepW = C.separationWeight * (1 + s.panic)

        local ox, oz = L:repel(s.x, s.z, s.vx, s.vz, C.obstacleRange)

        local px, pz = 0, 0
        if L:inPen(s.x, s.z) then
            local dx, dz = hx - s.x, hz - s.z
            local d = sqrt(dx * dx + dz * dz) + 1e-6
            if d > 14 then px, pz = dx / d * C.penPull, dz / d * C.penPull end
            wx, wz = wx * 0.4, wz * 0.4
        end

        -- A panicked sheep is a jittery one.
        local jx, jz = (random() - 0.5) * 2 * s.panic, (random() - 0.5) * 2 * s.panic

        local dx = sx * sepW + kx + gx + wx + fx + ox * C.obstacleWeight + px + jx
        local dz = sz * sepW + kz + gz + wz + fz + oz * C.obstacleWeight + pz + jz
        if s.graze > 0 then dx, dz = sx * sepW + fx + ox * C.obstacleWeight, sz * sepW + fz + oz * C.obstacleWeight end

        local top = C.walkSpeed * 1.5 + (C.panicSpeed - C.walkSpeed * 1.5) * s.panic
        local tvx, tvz = clampLen(dx * C.walkSpeed, dz * C.walkSpeed, top)
        local k = min(1, (C.response + (C.panicResponse - C.response) * s.panic) * dt)
        s.nvx, s.nvz = s.vx + (tvx - s.vx) * k, s.vz + (tvz - s.vz) * k
    end

    for i = 1, n do
        local s = list[i]
        s.vx, s.vz = s.nvx, s.nvz
        s.x, s.z = s.x + s.vx * dt, s.z + s.vz * dt
        local speed = sqrt(s.vx * s.vx + s.vz * s.vz)
        if speed > 3 then
            local want = atan2(s.vz, s.vx)
            local d = (want - s.h + math.pi) % TAU - math.pi
            s.h = s.h + d * min(1, C.turnRate * dt * min(1, speed / 10))
        end
        -- A hop a stride; the faster, the quicker.
        s.bob = s.bob + speed * dt * 0.42
        s.breath = s.breath + dt * 2.2
        s.speed = speed
    end

    -- Bodies don't overlap: each pair pushed apart, so a gap takes only so many.
    local R2 = CONFIG.radius * 2
    for i = 1, n do
        local a = list[i]
        for j = i + 1, n do
            local b = list[j]
            local dx, dz = b.x - a.x, b.z - a.z
            local d2 = dx * dx + dz * dz
            if d2 < R2 * R2 and d2 > 1e-8 then
                local d = sqrt(d2)
                local push = (R2 - d) / 2
                dx, dz = dx / d * push, dz / d * push
                a.x, a.z, b.x, b.z = a.x - dx, a.z - dz, b.x + dx, b.z + dz
            end
        end
        -- And the dog is solid to them.
        local dx, dz = a.x - dog.x, a.z - dog.z
        local d = sqrt(dx * dx + dz * dz)
        local need = CONFIG.radius + dog.radius
        if d < need and d > 1e-6 then a.x, a.z = dog.x + dx / d * need, dog.z + dz / d * need end
    end
    for _, s in ipairs(list) do s.x, s.z = L:collide(s.x, s.z, CONFIG.radius) end
end

function Flock:penned()
    local k = 0
    for _, s in ipairs(self.list) do
        if self.level:inPen(s.x, s.z) then k = k + 1 end
    end
    return k
end

--- drawing ----------------------------------------------------------------------

-- Each sheep's shadow (stays on the ground) and body (bobs over it), queued as
-- drawables sorted with the rest of the field by z.
function Flock:queue(into, camx, camy)
    local SE = T.SE
    for _, s in ipairs(self.list) do
        local sx, sy = floor(s.x - camx + 0.5), floor(s.z * SE - camy + 0.5)
        local moving = s.speed > 4
        local hop = moving and abs(sin(s.bob)) or 0
        local lift = floor(hop * (1.6 + s.panic * 1.6) + 0.5)
        -- Squash as it lands; breathe when it stands still.
        local squash
        if moving then
            squash = hop < 0.3 and 3 or (hop < 0.6 and 1 or 0)
        else
            squash = sin(s.breath) > 0.6 and 1 or 0
        end
        local leg = moving and (floor(s.bob / math.pi) % 2) or 0
        local pic = Models.sheep(s.h, squash, s.graze > 0, leg)
        into[#into + 1] = { z = s.z, draw = function()
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(pic.img, sx - pic.oi, sy - pic.oj - lift)
            if s.panic > 0.55 then
                G.rect("o", sx - 1, sy - pic.oj - lift - 6, 3, 6)
                G.rect("w", sx, sy - pic.oj - lift - 5, 1, 2)
                G.rect("w", sx, sy - pic.oj - lift - 2, 1, 1)
            end
        end }
    end
end

function Flock:shadows(camx, camy)
    local SE = T.SE
    for _, s in ipairs(self.list) do
        local k = self.level:inPen(s.x, s.z) and "s" or "t"
        G.ellipse(k, s.x - camx, s.z * SE - camy + 1, 6, 3)
    end
end

return Flock
