-- Nightmares: the lucid phase's one hands-on moment, and herding's mechanic
-- (the prototype this repository started as). The flock scatters, a dark
-- cloud drifts after it, and you bring the sheep into the fold with the dog.
--
-- The dog never tells a sheep anything. Inside its flee radius a sheep wants
-- to be further away, more the nearer it is (`Nightmare.pressure`, the same
-- curve the screen dithers round the dog's feet). The flock is boids:
-- separation, cohesion, a slow wander. Inside the fold a sheep drifts to its
-- heart and stays; the cloud can't come in. A sheep the cloud sits on for
-- long enough is lost to the dream.
--
-- Pure Lua, no LÖVE: positions are field units on a W by H field.

local sqrt, min, max, cos, sin = math.sqrt, math.min, math.max, math.cos, math.sin
local TAU = 2 * math.pi

local Nightmare = {}

Nightmare.W, Nightmare.H = 240, 140

local CONFIG = {
    radius = 5,
    walkSpeed = 26, -- calm top speed, field units a second
    fleeSpeed = 70, -- at the dog's feet
    response = 3,
    viewRadius = 40,
    separationRadius = 12,
    separationWeight = 1.6,
    cohesionWeight = 0.5,
    wanderWeight = 0.25,
    fleeRadius = 52,
    fleeFalloff = 1.5,
    wall = 10, -- the field's edge pushes from this far in
    penR = 26, -- the fold, before Sheepfolds
    penPull = 0.6,
    dogSpeed = 120,
    dogFollow = 2.4, -- speed per unit to the point, so a short drag creeps
    dogAccel = 7,
    cloudSpeed = 11,
    cloudR = 16,
    fearTime = 1.6, -- seconds under the cloud before a sheep is lost
}
Nightmare.CONFIG = CONFIG

-- How hard the dog presses at distance d, 0..1.
function Nightmare.pressure(d)
    if d >= CONFIG.fleeRadius then return 0 end
    return (1 - d / CONFIG.fleeRadius) ^ CONFIG.fleeFalloff
end

-- A nightmare of `n` sheep and `seconds`; `penScale` widens the fold.
-- `rand` gives 0..1 (the tests pass seeded dice).
function Nightmare.new(n, seconds, penScale, rand)
    local W, H = Nightmare.W, Nightmare.H
    local nm = {
        t = 0, seconds = seconds, done = false, won = false,
        pen = { x = W - 34, y = H / 2, r = CONFIG.penR * (penScale or 1) },
        dog = { x = 30, y = H / 2, vx = 0, vy = 0 },
        cloud = { x = 18, y = 18 },
        target = nil, -- where the dog is going, while held
        sheep = {},
    }
    -- Scattered over the middle of the field, every which way.
    for i = 1, n do
        local a = rand() * TAU
        nm.sheep[i] = {
            x = W * (0.25 + rand() * 0.4), y = H * (0.2 + rand() * 0.6),
            vx = 0, vy = 0, wander = a, fear = 0, lost = false, inPen = false,
        }
    end
    return nm
end

-- Where the dog should go, in field units, or nil when let go.
function Nightmare.point(nm, x, y)
    if not x then nm.target = nil return end
    nm.target = { x = max(0, min(Nightmare.W, x)), y = max(0, min(Nightmare.H, y)) }
end

local function clampLen(x, y, m)
    local l = sqrt(x * x + y * y)
    if l > m then return x / l * m, y / l * m end
    return x, y
end

-- Counts: in the fold, lost, and all.
function Nightmare.counts(nm)
    local inPen, lost = 0, 0
    for _, s in ipairs(nm.sheep) do
        if s.lost then lost = lost + 1 elseif s.inPen then inPen = inPen + 1 end
    end
    return inPen, lost, #nm.sheep
end

-- The share of the flock saved, once it's over: in the fold over all.
function Nightmare.saved(nm)
    local inPen, _, n = Nightmare.counts(nm)
    return n > 0 and inPen / n or 0
end

function Nightmare.update(nm, dt, rand)
    if nm.done then return end
    local C, W, H = CONFIG, Nightmare.W, Nightmare.H
    nm.t = nm.t + dt
    -- The dog.
    local d = nm.dog
    local tx, ty = 0, 0
    if nm.target then
        local dx, dy = nm.target.x - d.x, nm.target.y - d.y
        local l = sqrt(dx * dx + dy * dy)
        if l > 1.5 then
            local sp = min(C.dogSpeed, l * C.dogFollow)
            tx, ty = dx / l * sp, dy / l * sp
        end
    end
    local k = min(1, C.dogAccel * dt)
    d.vx, d.vy = d.vx + (tx - d.vx) * k, d.vy + (ty - d.vy) * k
    d.x, d.y = max(4, min(W - 4, d.x + d.vx * dt)), max(4, min(H - 4, d.y + d.vy * dt))

    -- The cloud: after the nearest sheep still out in the open.
    local c, best, bd = nm.cloud, nil, math.huge
    for _, s in ipairs(nm.sheep) do
        if not s.lost and not s.inPen then
            local dd = (s.x - c.x) ^ 2 + (s.y - c.y) ^ 2
            if dd < bd then best, bd = s, dd end
        end
    end
    if best then
        local dx, dy = best.x - c.x, best.y - c.y
        local l = sqrt(dx * dx + dy * dy) + 1e-6
        c.x, c.y = c.x + dx / l * C.cloudSpeed * dt, c.y + dy / l * C.cloudSpeed * dt
    end
    -- It can't come into the fold.
    local p = nm.pen
    local px, py = c.x - p.x, c.y - p.y
    local pl = sqrt(px * px + py * py) + 1e-6
    if pl < p.r + C.cloudR * 0.5 then
        c.x, c.y = p.x + px / pl * (p.r + C.cloudR * 0.5), p.y + py / pl * (p.r + C.cloudR * 0.5)
    end

    -- The flock.
    local list = nm.sheep
    for i, s in ipairs(list) do
        if not s.lost then
            local cx, cy, count, sx, sy = 0, 0, 0, 0, 0
            for j, o in ipairs(list) do
                if j ~= i and not o.lost then
                    local dx, dy = o.x - s.x, o.y - s.y
                    local d2 = dx * dx + dy * dy
                    if d2 < C.viewRadius * C.viewRadius then
                        local dd = sqrt(d2) + 1e-6
                        cx, cy, count = cx + o.x, cy + o.y, count + 1
                        if dd < C.separationRadius then
                            local w = 1 - dd / C.separationRadius
                            sx, sy = sx - dx / dd * w, sy - dy / dd * w
                        end
                    end
                end
            end
            local wx, wy = 0, 0
            -- The dog's pressure: away from it, harder the nearer.
            local ddx, ddy = s.x - d.x, s.y - d.y
            local dl = sqrt(ddx * ddx + ddy * ddy) + 1e-6
            local press = Nightmare.pressure(dl)
            wx, wy = wx + ddx / dl * press * C.fleeSpeed, wy + ddy / dl * press * C.fleeSpeed
            -- Boids, and a wander when left alone.
            s.wander = s.wander + (rand() - 0.5) * 3 * dt
            local calm = 1 - press
            wx = wx + sx * C.separationWeight * C.walkSpeed + cos(s.wander) * C.wanderWeight * C.walkSpeed * calm
            wy = wy + sy * C.separationWeight * C.walkSpeed + sin(s.wander) * C.wanderWeight * C.walkSpeed * calm
            if count > 0 then
                wx = wx + (cx / count - s.x) * C.cohesionWeight * calm
                wy = wy + (cy / count - s.y) * C.cohesionWeight * calm
            end
            -- The field's edges push back in.
            if s.x < C.wall then wx = wx + (C.wall - s.x) * 4 end
            if s.x > W - C.wall then wx = wx - (s.x - W + C.wall) * 4 end
            if s.y < C.wall then wy = wy + (C.wall - s.y) * 4 end
            if s.y > H - C.wall then wy = wy - (s.y - H + C.wall) * 4 end
            -- Inside the fold: a drift to its heart, and it stays.
            local fx, fy = p.x - s.x, p.y - s.y
            local fl = sqrt(fx * fx + fy * fy)
            s.inPen = fl < p.r
            if s.inPen then
                wx, wy = wx * 0.3 + fx * C.penPull * 4, wy * 0.3 + fy * C.penPull * 4
            end
            wx, wy = clampLen(wx, wy, C.fleeSpeed)
            local r = min(1, C.response * dt)
            s.vx, s.vy = s.vx + (wx - s.vx) * r, s.vy + (wy - s.vy) * r
            s.x, s.y = max(2, min(W - 2, s.x + s.vx * dt)), max(2, min(H - 2, s.y + s.vy * dt))
            -- Under the cloud, out in the open, it frets; long enough and it's gone.
            local qx, qy = s.x - c.x, s.y - c.y
            if not s.inPen and qx * qx + qy * qy < C.cloudR * C.cloudR then
                s.fear = s.fear + dt / C.fearTime
                if s.fear >= 1 then s.lost = true end
            else
                s.fear = max(0, s.fear - dt / C.fearTime)
            end
        end
    end

    local inPen, lost, n = Nightmare.counts(nm)
    if inPen > 0 and inPen + lost == n then
        nm.done, nm.won = true, true
    elseif lost == n or nm.t >= nm.seconds then
        nm.done, nm.won = true, false
    end
end

return Nightmare
