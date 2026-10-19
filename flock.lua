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
-- A bark is a shove at a distance: everything in `barkRadius` is pushed off
-- the dog at once and jumps a little, but not into a panic unless it was
-- already half there. It is how a grazing black sheep is got moving.
--
-- Not every sheep is the same (`KINDS`): a lamb is small, frets easily and
-- keeps to its mother; a black sheep is stubborn, feels the dog less and would
-- rather graze.
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

    -- the bark
    barkRadius = 74,
    barkPush = 70,           -- velocity kicked into a sheep at the dog's feet
    barkPanic = 0.32,        -- panic added at the dog's feet: alone, not enough to scare
    barkCooldown = 1.1,

    -- the calm count: a sheep crossing this is one scare (and the panic mark over it)
    scareLevel = 0.55,
}
Flock.CONFIG = CONFIG

-- What each kind changes. flee and panic scale the dog's pull on it; graze
-- scales grazeChance; hold is the pressure it takes to lift its head.
local KINDS = {
    ewe = { radius = 5.5, flee = 1, panic = 1, response = 1, graze = 1, hold = 0.05, speed = 1 },
    lamb = { radius = 3.8, flee = 1.1, panic = 1.6, response = 1.3, graze = 0.6, hold = 0.05, speed = 0.95,
        follow = 0.9 },
    black = { radius = 5.5, flee = 0.55, panic = 0.45, response = 0.6, graze = 3, hold = 0.4, speed = 0.85 },
}
Flock.KINDS = KINDS

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

-- Sheep in little bunches round each spawn point, facing every which way. A
-- bunch may say `kind` for all of it, or bring `lambs` along with its ewes.
function Flock.new(level)
    local self = setmetatable({ list = {}, level = level, scares = 0 }, Flock)
    local function add(x, z, kind)
        local h = random() * TAU
        local K = KINDS[kind]
        local s = {
            x = x, z = z, kind = kind, K = K, r = K.radius,
            vx = 0, vz = 0, h = h, wander = h,
            panic = 0, graze = random() < 0.5 and random() * 4 or 0,
            bob = random() * TAU, breath = random() * TAU, crowd = 0, speed = 0,
        }
        if kind == "black" then s.graze = 6 end
        self.list[#self.list + 1] = s
        return s
    end
    for _, b in ipairs(level.def.flock) do
        local ewes = {}
        for _ = 1, b.n do
            local a, r = random() * TAU, sqrt(random()) * b.r
            ewes[#ewes + 1] = add(b.x + cos(a) * r, b.z + sin(a) * r, b.kind or "ewe")
        end
        for k = 1, b.lambs or 0 do
            local mum = ewes[(k - 1) % #ewes + 1]
            local l = add(mum.x + random() * 8 - 4, mum.z + random() * 8 - 4, "lamb")
            l.mum = mum
        end
    end
    for _, s in ipairs(self.list) do s.x, s.z = level:collide(s.x, s.z, s.r) end
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
        local K = s.K
        local press = Flock.pressure(dd)
        local fx, fz = ddx / dd * press * C.fleeStrength * K.flee, ddz / dd * press * C.fleeStrength * K.flee

        -- A bark: a kick off the dog now, and a start.
        if dog.barked and dd < C.barkRadius then
            local b = 1 - dd / C.barkRadius
            s.vx, s.vz = s.vx + ddx / dd * C.barkPush * b, s.vz + ddz / dd * C.barkPush * b
            s.panic = s.panic + C.barkPanic * b * K.panic
            s.graze = 0
        end

        -- Panic: built by a dog rushing in, caught off neighbours, and from
        -- being squeezed; it wears off on its own.
        local p = s.panic
        p = p + overspeed * press * C.panicGain * dt * 2 * K.panic
        if count > 0 then
            local lift = nbPanic / count * C.panicSpread
            if lift > p then p = p + (lift - p) * min(1, dt * 1.5) end
        end
        if crowd > 3 then p = p + (crowd - 3) * C.crowdStress * dt end
        p = p - C.panicDecay * dt
        s.panic = max(0, min(1, p))
        if s.panic > C.scareLevel and not s.scared then
            s.scared = true
            self.scares = self.scares + 1
        elseif s.panic < 0.2 then
            s.scared = false
        end
        local calm = 1 - s.panic

        -- Grazing: a calm, idle sheep puts its head down for a while.
        local speed = sqrt(s.vx * s.vx + s.vz * s.vz)
        if s.graze > 0 then
            s.graze = s.graze - dt
            if press > K.hold or s.panic > 0.15 then s.graze = 0 end
        elseif press <= K.hold and s.panic < 0.05 and speed < C.walkSpeed * 0.4
            and random() < C.grazeChance * K.graze * dt then
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

        -- A lamb keeps to its mother, and wanders less for it.
        if s.mum then
            local dx, dz = s.mum.x - s.x, s.mum.z - s.z
            local d = sqrt(dx * dx + dz * dz) + 1e-6
            if d > 10 then
                local w = min(1.5, (d - 10) / 30) * K.follow
                kx, kz = kx + dx / d * w, kz + dz / d * w
            end
            wx, wz = wx * 0.4, wz * 0.4
        end

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

        local top = (C.walkSpeed * 1.5 + (C.panicSpeed - C.walkSpeed * 1.5) * s.panic) * K.speed
        local tvx, tvz = clampLen(dx * C.walkSpeed, dz * C.walkSpeed, top)
        local k = min(1, (C.response + (C.panicResponse - C.response) * s.panic) * K.response * dt)
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
    for i = 1, n do
        local a = list[i]
        for j = i + 1, n do
            local b = list[j]
            local dx, dz = b.x - a.x, b.z - a.z
            local d2 = dx * dx + dz * dz
            local R2 = a.r + b.r
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
        local need = a.r + dog.radius
        if d < need and d > 1e-6 then a.x, a.z = dog.x + dx / d * need, dog.z + dz / d * need end
    end
    for _, s in ipairs(list) do s.x, s.z = L:collide(s.x, s.z, s.r) end
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
        local pic = Models.sheep(s.h, squash, s.graze > 0, leg, s.kind ~= "ewe" and s.kind or nil)
        into[#into + 1] = { z = s.z, draw = function()
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(pic.img, sx - pic.oi, sy - pic.oj - lift)
            if s.panic > CONFIG.scareLevel then
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
        local big = s.kind ~= "lamb"
        G.ellipse(k, s.x - camx, s.z * SE - camy + 1, big and 6 or 4, big and 3 or 2)
    end
end

return Flock
