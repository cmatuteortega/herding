-- The bouncing sheep: phase 2's other hands-on moment, always in front of the
-- field. Left alone it hops on its own cloud at the bottom. Hold a finger on
-- the field and it climbs: each cloud it falls onto throws it up again, and
-- it drifts after the finger, doodle-jump style. The view follows it up. Let
-- go and the clouds stop holding it: it falls, and a sheep that falls off
-- the bottom of the view has ended its climb, and floats back down to its
-- cloud. Stars on the way pay Dream Points, a moon now and
-- then is a golden gift, and the best height ever is kept (lucid/game.lua).
--
-- Clouds: plain ones, springy ones (gold, a bigger bounce), dark ones (a
-- nightmare's: they hold once, then break) and, higher up, drifting ones.
--
-- Pure Lua, no LÖVE: field units, `w` across, heights up from the ground
-- cloud. `viewH` is how many units the screen shows up the way (the field
-- sets it from its own shape).

local C = require "config"

local min, max, abs = math.min, math.max, math.abs
local P = C.dream.bounce

local Bounce = { CONFIG = P }

function Bounce.new()
    return {
        on = false, -- climbing
        x = P.w / 2, y = 0, vx = 0, vy = 0,
        cam = 0, -- the view's bottom edge, a height
        viewH = 70,
        clouds = {}, items = {}, top = 0, nextMoon = P.moonEvery,
        aim = nil, held = false, -- where the finger is, while it's down
        height = 0, stars = 0, -- this climb
        squash = 0, -- a landing, for the picture
        events = {},
    }
end

local function emit(B, e) B.events[#B.events + 1] = e end

-- How high a jump goes: v^2 / 2g.
function Bounce.apex(jump) return (P.jump * (jump or 1)) ^ 2 / (2 * P.gravity) end

-- Clouds and what floats over them, up to a little past the top of the view.
-- `opts.width` widens (or narrows) the clouds.
local function grow(B, rand, opts)
    local w = P.cloudW * (opts.width or 1)
    -- Never further apart than most of a jump, whatever the springs.
    local reach = Bounce.apex(opts.jump) * 0.8
    while B.top < B.cam + B.viewH + 30 do
        local gap = P.gapMin + rand() * (P.gapMax - P.gapMin)
        B.top = B.top + min(gap, reach)
        local c = { x = w / 2 + rand() * (P.w - w), y = B.top, w = w, kind = "plain", vx = 0 }
        local r = rand()
        if r < P.springChance then c.kind = "spring"
        elseif B.top > P.darkFrom and r < P.springChance + P.darkChance then c.kind = "dark" end
        if B.top > P.moveFrom and rand() < 0.2 then c.vx = (rand() < 0.5 and -1 or 1) * (10 + rand() * 10) end
        B.clouds[#B.clouds + 1] = c
        if B.top >= B.nextMoon then
            B.items[#B.items + 1] = { x = c.x, y = B.top + 9, kind = "moon" }
            B.nextMoon = B.nextMoon + P.moonEvery
        elseif rand() < P.starChance then
            B.items[#B.items + 1] = { x = c.x, y = B.top + 7, kind = "star" }
        end
    end
end

-- The finger down at `x` (field units): a climb starts, or goes on steering.
function Bounce.press(B, x)
    B.held, B.aim = true, x
    if B.on then return end
    B.on, B.cam, B.top = true, 0, 0
    B.clouds, B.items, B.nextMoon = {}, {}, P.moonEvery
    B.height, B.stars = 0, 0
    B.vy = P.launch
    emit(B, { type = "climb" })
end

function Bounce.move(B, x) if B.held then B.aim = x end end
function Bounce.release(B) B.held, B.aim = false, nil end

-- The climb is over (fallen, or a nightmare came): back to the ground cloud.
function Bounce.stop(B)
    if B.on then emit(B, { type = "fell", height = B.height, stars = B.stars }) end
    B.on, B.cam, B.clouds, B.items = false, 0, {}, {}
    B.y, B.vy = B.viewH * 0.7, 0
    B.held, B.aim = false, nil
end

-- One step. `opts`: jump (a multiplier), width (a multiplier).
function Bounce.step(B, dt, rand, opts)
    opts = opts or {}
    rand = rand or math.random
    B.squash = max(0, B.squash - dt * 5)
    -- Sideways: after the finger, eased; nothing held, it slows.
    local want = 0
    if B.aim then want = max(-P.maxVx, min(P.maxVx, (B.aim - B.x) * P.follow)) end
    B.vx = B.vx + (want - B.vx) * min(1, dt * 8)
    B.x = max(2, min(P.w - 2, B.x + B.vx * dt))
    local prev = B.y
    B.vy = B.vy - P.gravity * dt
    B.y = B.y + B.vy * dt
    if not B.on then
        -- Hopping on the ground cloud.
        if B.y <= 0 and B.vy < 0 then
            B.y, B.vy, B.squash = 0, P.idleJump, 1
            emit(B, { type = "hop" })
        end
        return
    end
    for _, c in ipairs(B.clouds) do
        if c.vx ~= 0 then
            c.x = c.x + c.vx * dt
            if c.x < c.w / 2 or c.x > P.w - c.w / 2 then c.vx = -c.vx; c.x = max(c.w / 2, min(P.w - c.w / 2, c.x)) end
        end
    end
    if B.vy < 0 and B.held then
        -- The ground cloud is there until the view has left it.
        if B.cam <= 0 and prev >= 0 and B.y <= 0 then
            B.y, B.vy, B.squash = 0, P.jump * (opts.jump or 1), 1
            emit(B, { type = "boing", kind = "ground" })
        else
            for _, c in ipairs(B.clouds) do
                if not c.broken and prev >= c.y and B.y <= c.y and abs(B.x - c.x) <= c.w / 2 + 2 then
                    B.y, B.squash = c.y, 1
                    B.vy = P.jump * (opts.jump or 1) * (c.kind == "spring" and P.spring or 1)
                    if c.kind == "dark" then c.broken = true end
                    emit(B, { type = "boing", kind = c.kind })
                    break
                end
            end
        end
    end
    B.height = max(B.height, B.y)
    B.cam = max(B.cam, B.y - B.viewH * 0.45)
    for i = #B.items, 1, -1 do
        local it = B.items[i]
        if abs(B.x - it.x) < 6 and abs(B.y + 4 - it.y) < 7 then
            table.remove(B.items, i)
            if it.kind == "star" then B.stars = B.stars + 1 end
            emit(B, { type = it.kind, x = it.x, y = it.y })
        elseif it.y < B.cam - 10 then
            table.remove(B.items, i)
        end
    end
    for i = #B.clouds, 1, -1 do if B.clouds[i].y < B.cam - 10 then table.remove(B.clouds, i) end end
    grow(B, rand, opts)
    if B.y < B.cam - 8 then Bounce.stop(B) end
end

-- A simple player, for the tests and autoplay: on the way up, it heads for
-- the highest cloud it can reach; on the way down, for the one under it.
function Bounce.bot(B)
    local rise = B.vy > 0 and B.vy * B.vy / (2 * P.gravity) or 0 -- how much higher this jump goes
    local best
    for _, c in ipairs(B.clouds) do
        if not c.broken then
            local ok
            if B.vy > 0 then ok = c.y <= B.y + rise * 0.95
            else ok = c.y <= B.y end
            if ok and (not best or c.y > best.y) then best = c end
        end
    end
    return best and best.x or B.x
end

return Bounce
