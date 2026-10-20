-- The lucid dream's field, drawn into its own low-res canvas like scene.lua:
-- a violet sky with an aurora, the moon, and the flock turning to cloud the
-- higher the dimension (Dream Sheep graze the hill, Auroras drift up top).
-- Runs hop the fence one by one until there are too many to see, and then
-- they're one stream: the flow. A golden sheep crosses the sky. In a
-- nightmare the field becomes herding's: the dog, its pressure field, the
-- flock, the fold, and the cloud.
--
-- It only reads the rules' state; what only looks lives in `fx`.

local G = require "gfx"
local Models = require "models"
local N = require "num"
local C = require "config"
local Nightmare = require "lucid.nightmare"

local floor, min, max, sin, cos, sqrt, atan2 = math.floor, math.min, math.max, math.sin, math.cos, math.sqrt, math.atan2
local TAU = 2 * math.pi
local D = C.dream

local LScene = { reduced = false }

local canvas, cw, ch = nil, 0, 0
local bg -- the sky and hill that don't move, kept per size
local stars = {}
local t = 0
local rng = love.math.newRandomGenerator(7)
local function rand() return rng:random() end

local fx = { hoppers = {}, floats = {}, stream = {}, puffs = {}, flash = 0 }
LScene.fx = fx

local function horizon() return floor(ch * 0.62) end
local function fenceX() return floor(cw * 0.5) end

function LScene.resize(w, h)
    if w == cw and h == ch and canvas then return end
    cw, ch = w, h
    canvas = love.graphics.newCanvas(cw, ch)
    canvas:setFilter("nearest", "nearest")
    bg = nil
    local r = love.math.newRandomGenerator(cw * 7 + ch)
    stars = {}
    for _ = 1, floor(cw * ch / 120) do
        stars[#stars + 1] = { x = r:random(0, cw - 1), y = r:random(0, max(1, horizon() - 10)), ph = r:random() * TAU }
    end
end

function LScene.reset()
    fx.hoppers, fx.floats, fx.stream, fx.puffs, fx.flash = {}, {}, {}, {}, 0
end

local function blit(sp, x, y)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(sp.img, floor(x + 0.5) - sp.oi, floor(y + 0.5) - sp.oj)
end

-- The sky, dithered from deep violet into lilac at the horizon, and the hill.
local function backdrop()
    local data = love.image.newImageData(cw, ch)
    local hz = horizon()
    local function put(x, y, k)
        local c = G.C[k]
        data:setPixel(x, y, c[1], c[2], c[3], 1)
    end
    for y = 0, ch - 1 do
        for x = 0, cw - 1 do
            local k
            if y < hz then
                local v = y / hz
                k = G.dither(x, y, v * 1.2) and (G.dither(x + 1, y, (v - 0.6) * 2.5) and "i" or "u") or "n"
            else
                local hy = hz + floor(2 * sin(x * 0.045) + 1.5 * sin(x * 0.11 + 1))
                if y < hy then
                    k = "u"
                elseif y == hy then
                    k = "l"
                else
                    k = G.dither(x, y, (y - hy) / (ch - hy) * 0.8) and "p" or "i"
                end
            end
            put(x, y, k)
        end
    end
    return love.graphics.newImage(data)
end

--- what the rules ask for -----------------------------------------------------------------

-- Runs: while you can still see them, a sheep hops the fence for some.
function LScene.runs(n, value, flow)
    if flow then return end
    if #fx.hoppers < 10 then
        fx.hoppers[#fx.hoppers + 1] = { x = fenceX() - 30, ph = 0, look = rand() < 0.5 and "cloud" or "plain" }
    end
    if #fx.floats < 8 then
        fx.floats[#fx.floats + 1] = { text = "+" .. N.format(value) .. " DP", x = fenceX(), y = horizon() - 6, t = 0 }
    end
end

function LScene.float(text, x, y, k)
    fx.floats[#fx.floats + 1] = { text = text, x = x or floor(cw / 2), y = y or floor(ch * 0.4), t = 0, k = k, life = 2 }
end

function LScene.flash() fx.flash = 1 end

-- Where the golden sheep is, `g.t` into its crossing.
local function goldenPos(g)
    local p = g.t / D.golden.crossTime
    return -12 + p * (cw + 24), floor(ch * 0.18 + g.lane * ch * 0.25 + sin(g.t * 2.2) * 3)
end

function LScene.hitGolden(L, x, y)
    if not L.golden then return false end
    local gx, gy = goldenPos(L.golden)
    return (x - gx) ^ 2 + (y - gy + 5) ^ 2 < 18 * 18
end

-- The nightmare's field to the canvas: one scale both ways, centred.
local function fit()
    local k = min(cw / Nightmare.W, ch / Nightmare.H)
    return k, (cw - Nightmare.W * k) / 2, (ch - Nightmare.H * k) / 2
end

function LScene.toField(x, y)
    local k, ox, oy = fit()
    return (x - ox) / k, (y - oy) / k
end

function LScene.update(dt, L)
    t = t + dt
    fx.flash = max(0, fx.flash - dt * 2)
    local fxX = fenceX()
    for i = #fx.hoppers, 1, -1 do
        local h = fx.hoppers[i]
        h.x = h.x + dt * 70
        if h.x > cw + 12 then table.remove(fx.hoppers, i) end
    end
    for i = #fx.floats, 1, -1 do
        local f = fx.floats[i]
        f.t = f.t + dt
        if f.t > (f.life or 1.2) then table.remove(fx.floats, i) end
    end
    -- The flow: wool streaming over the fence, too many runs to tell apart.
    if L.flow and not L.nightmare then
        local want = LScene.reduced and 12 or 40
        while #fx.stream < want do
            fx.stream[#fx.stream + 1] = { x = rand() * cw, y = rand(), v = 40 + rand() * 60, sheep = rand() < 0.15 }
        end
        for _, s in ipairs(fx.stream) do
            s.x = s.x + s.v * dt
            if s.x > cw + 10 then s.x, s.y = -10, rand() end
        end
    else
        fx.stream = {}
    end
    for i = #fx.puffs, 1, -1 do
        local p = fx.puffs[i]
        p.t = p.t + dt
        if p.t > 0.6 then table.remove(fx.puffs, i) end
    end
    LScene.fenceX = fxX
end

--- drawing -------------------------------------------------------------------------------

local function aurora()
    local tt = LScene.reduced and 0 or t
    local pts = { a = {}, r = {}, c = {} }
    local top = floor(ch * 0.08)
    for x = 0, cw - 1 do
        local y0 = top + floor(sin(x * 0.035 + tt * 0.35) * 6 + sin(x * 0.11 - tt * 0.6) * 2)
        local h = 10 + floor(4 * sin(x * 0.07 + tt * 0.5))
        for dy = 0, h do
            local v = (1 - dy / h) * (0.55 + 0.25 * sin(x * 0.05 + tt))
            if G.dither(x, y0 + dy, v) then
                local k = dy < h * 0.4 and "a" or (dy < h * 0.75 and "c" or "r")
                G.plot(pts[k], x, y0 + dy)
            end
        end
    end
    G.points("a", pts.a)
    G.points("c", pts.c)
    G.points("r", pts.r)
end

-- The flock, by dimension: the first two on the hill, the rest as cloud,
-- higher and smaller the higher the dimension.
local function flock(L)
    local hz = horizon()
    for k = 1, #L.dims do
        local n = L.dims[k].bought
        if n > 0 then
            local count = min(k <= 2 and 5 or 3, 1 + floor(n / 8))
            for i = 1, count do
                local seed = k * 31 + i * 7
                local drift = LScene.reduced and 0 or t * (6 + k)
                if k <= 2 then
                    local x = (seed * 37 + drift * 0.4) % (cw + 20) - 10
                    local y = hz + 5 + (seed % 3) * 3 + (k - 1) * 2
                    blit(Models.sheep(x % 2 > 1 and 0.3 or math.pi - 0.3, 0, 0, k == 1 and "plain" or "cloud", true, 0.65), x, y)
                else
                    local x = (seed * 53 + drift) % (cw + 30) - 15
                    local band = (6 - k) / 4 -- Auroras highest
                    local y = floor(ch * 0.2 + band * hz * 0.5 + sin(t * 0.8 + seed) * (LScene.reduced and 0 or 2))
                    blit(Models.sheep(0.2, 0, 0, "cloud", false, 0.75 - (k - 3) * 0.1), x, y)
                end
            end
        end
    end
end

local function drawField(L)
    if not bg then bg = backdrop() end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(bg, 0, 0)
    -- Stars, twinkling.
    for _, st in ipairs(stars) do
        local tw = LScene.reduced and 1 or sin(t * 1.3 + st.ph)
        if tw > -0.7 then G.rect(tw > 0.6 and "w" or "l", st.x, st.y, 1, 1) end
    end
    aurora()
    blit(Models.moon(9), cw - max(18, cw * 0.15), floor(ch * 0.3))
    flock(L)
    local hz = horizon()
    blit(Models.fence(1, 0), fenceX(), hz + 12)
    -- The flow: lines of wool, and now and then a sheep in it.
    for _, s in ipairs(fx.stream) do
        local y = floor(hz - 4 + s.y * 14)
        if s.sheep then
            blit(Models.sheep(0, -1, 2, "cloud", false, 0.6), s.x, y)
        else
            G.rect(s.y < 0.5 and "c" or "l", s.x, y, 4, 1)
        end
    end
    -- Runs you can still see: a sheep over the fence each.
    for _, h in ipairs(fx.hoppers) do
        local d = (h.x - fenceX()) / 30
        local lift = d > -1 and d < 1 and (1 - d * d) * 16 or 0
        blit(Models.sheep(0, lift > 2 and -1 or 0, lift > 2 and 2 or (floor(h.x / 6) % 2), h.look), h.x, hz + 10 - lift)
    end
    -- The golden sheep, sparkling.
    if L.golden then
        local gx, gy = goldenPos(L.golden)
        blit(Models.sheep(0, -1, 2, "gold"), gx, gy)
        if floor(t * 8) % 2 == 0 then
            G.rect("y", gx - 9, gy - 12, 1, 1); G.rect("w", gx + 8, gy - 3, 1, 1); G.rect("y", gx + 2, gy - 15, 1, 1)
        end
    end
end

-- herding's field, for a nightmare.
local function drawNightmare(L)
    local nm = L.nightmare
    local k, ox, oy = fit()
    local function sx(x) return ox + x * k end
    local function sy(y) return oy + y * k end
    -- The ground: night grass, dithered.
    local pts = {}
    G.rect("n", 0, 0, cw, ch)
    for y = 0, ch - 1, 1 do
        for x = (y % 2), cw - 1, 3 do
            if G.dither(x, y, 0.35) then G.plot(pts, x, y) end
        end
    end
    G.points("v", pts)
    -- The fold: posts round it, a gap facing the field.
    local p = nm.pen
    local r = p.r * k
    for i = 0, 23 do
        local a = i / 24 * TAU
        if cos(a) > -0.85 then
            local x, y = sx(p.x) + cos(a) * r, sy(p.y) + sin(a) * r * 0.9
            G.rect("b", x, y - 3, 1, 4)
            G.rect("s", x, y, 1, 1)
        end
    end
    -- The dog's pressure field, dithered in aurora green: what the sheep feel.
    local d = nm.dog
    local R = Nightmare.CONFIG.fleeRadius
    local fieldPts = {}
    local cx, cy = sx(d.x), sy(d.y)
    local rr = R * k
    for y = floor(cy - rr), floor(cy + rr) do
        for x = floor(cx - rr), floor(cx + rr) do
            local dist = sqrt((x - cx) ^ 2 + (y - cy) ^ 2) / k
            local pr = Nightmare.pressure(dist)
            if pr > 0 and G.dither(x, y, pr * 0.5) then G.plot(fieldPts, x, y) end
        end
    end
    G.points("t", fieldPts)
    -- The cloud: a dark puff with two rose eyes, wobbling.
    local c = nm.cloud
    local wob = LScene.reduced and 0 or sin(t * 3) * 1.5
    local cr = floor(Nightmare.CONFIG.cloudR * k)
    G.disc("p", sx(c.x), sy(c.y), cr + 1, 0.6)
    G.disc("o", sx(c.x), sy(c.y) + wob, cr - 2)
    G.disc("o", sx(c.x) - cr * 0.6, sy(c.y) + 2, floor(cr * 0.6))
    G.disc("o", sx(c.x) + cr * 0.6, sy(c.y) + 2 - wob, floor(cr * 0.6))
    G.rect("r", sx(c.x) - 3, sy(c.y) - 1 + wob, 2, 1)
    G.rect("r", sx(c.x) + 2, sy(c.y) - 1 + wob, 2, 1)
    -- The flock, back to front; a lost one is gone, a frightened one says so.
    local order = {}
    for _, s in ipairs(nm.sheep) do if not s.lost then order[#order + 1] = s end end
    order[#order + 1] = { dog = true, x = d.x, y = d.y }
    table.sort(order, function(a, b) return a.y < b.y end)
    for _, s in ipairs(order) do
        if s.dog then
            local moving = d.vx * d.vx + d.vy * d.vy > 16
            blit(Models.dog(atan2(d.vy, d.vx), moving and floor(t * 10) % 4 or 0), sx(d.x), sy(d.y) + 3)
        else
            local sp = s.vx * s.vx + s.vy * s.vy
            blit(Models.sheep(atan2(s.vy, s.vx), 0, sp > 9 and floor(t * 8) % 2 or 0, s.inPen and "cloud" or "plain", false, 0.6),
                sx(s.x), sy(s.y) + 3)
            if s.fear > 0.3 and floor(t * 6) % 2 == 0 then G.text("r", "!", sx(s.x) - 1, sy(s.y) - 12) end
        end
    end
end

function LScene.draw(L)
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(G.C.n)
    if L.nightmare then drawNightmare(L) else drawField(L) end
    for _, f in ipairs(fx.floats) do
        local life = f.life or 1.2
        local dens = 1 - max(0, f.t / life - 0.5) * 2
        G.label(f.k or "y", f.text, floor(f.x - G.textWidth(f.text) / 2), floor(f.y - f.t * 12), 1,
            LScene.reduced and 1 or dens)
    end
    if fx.flash > 0 and not LScene.reduced then
        local pts = {}
        for y = 0, ch - 1 do
            for x = 0, cw - 1 do if G.dither(x, y, fx.flash * 0.5) then G.plot(pts, x, y) end end
        end
        G.points("y", pts)
    end
    love.graphics.pop()
    return canvas
end

--- the town's buildings, small ---------------------------------------------------------

local ART = {
    clock = { "...ooo...", "..owwwo..", ".owywiwo.", ".owwywwo.", ".owwwwwo.", "..owwwo..", "...ooo...",
        "..oyyyo..", "..oyyyo..", "..oyyyo..", ".ooooooo." },
    inn = { "....o....", "...oro...", "..orrro..", ".orrrrro.", "ooooooooo", ".olcllco.", ".olylllo.",
        ".ollllyo.", ".olcolco.", ".olloolo.", "ooooooooo" },
    bakery = { "..ooooo..", ".owwwwwo.", "owwcwcwwo", "owwwwwwwo", ".ooooooo.", ".ohhyhho.", ".ohyyyho.",
        ".ohhhhho.", ".ohoooho.", ".ohoyoho.", "ooooooooo" },
    hut = { "....o....", "...oio...", "..oiiio..", ".oiiiiio.", "ooooooooo", ".obbbbbo.", ".obobbbo.",
        ".obobwbo.", ".obbbbbo.", "ooooooooo" },
    workshop = { "o..o.....", "oo.oo....", "ooooooooo", "oiiiiiiio", "oiwwiwwio", "oiwwiwwio", "oiiiiiiio",
        "oiicciiio", "oiicciiio", "ooooooooo" },
    observatory = { "...ooo...", "..ouuuo..", ".ouuyuuo.", ".ouuuuuo.", "ooooooooo", ".oiiiiio.", ".oiiciio.",
        ".oiiiiio.", ".oiiiiio.", "ooooooooo" },
    mill = { "o...o...o", ".o..o..o.", "..o.o.o..", "...ooo...", "oooo.oooo", "...ooo...", "..oiiio..",
        ".oiiiiio.", ".oiicciio", ".oiicciio", "ooooooooo" },
    plaza = { ".........", ".aaaaaaa.", ".a.....a.", ".a.ooo.a.", ".a.oco.a.", ".a.ooo.a.", ".a.....a.",
        ".aaaaaaa.", "........." },
    fountain = { "....c....", "...c.c...", "..c.c.c..", "...ccc...", "....o....", "ooooooooo", "occcaccco",
        "ooooooooo", ".ooooooo." },
    fold = { "o.o.o.o.o", "ooooooooo", "o.......o", "o..ww...o", "o.wwwo..o", "o..w.w..o", "ooooooooo",
        "o.o.o.o.o" },
    lighthouse = { "...oyo...", "...ooo...", "...olo...", "...owo...", "...olo...", "..owwwo..", "..olllo..",
        "..owwwo..", ".ooooooo." },
    mirror = { ".........", "..ooooo..", ".occccco.", "occacccco", "occcccaco", ".occccco.", "..ooooo..",
        "........." },
    gate = { "ooooooooo", "o.o...o.o", "o.o...o.o", "o.o...o.o", "o.o...o.o", "o.o...o.o", "ooooooooo" },
}
LScene.ART = ART

-- A building's picture with its middle at (x, y); `dim` greys it (locked).
function LScene.building(id, x, y, dim)
    local rows = ART[id]
    if not rows then return end
    local w, h = #rows[1], #rows
    if dim then
        local grey = {}
        for i, row in ipairs(rows) do grey[i] = row:gsub("[^%.o]", "s") end
        rows = grey
    end
    G.art(rows, floor(x - w / 2), floor(y - h / 2))
end

-- A dimension's picture: sheep on the ground for the first two, then cloud.
function LScene.dimension(k, x, y)
    if k == 1 then blit(Models.sheep(0.35, 0, 0, "plain", false, 0.7), x, y + 7)
    elseif k == 2 then blit(Models.sheep(0.35, 0, 0, "cloud", false, 0.7), x, y + 7)
    else
        blit(Models.sheep(0.35, 0, 0, "cloud", false, 0.85 - (k - 3) * 0.12), x, y + 5)
        for i = 1, k - 2 do G.rect(k >= 6 and "a" or "c", x - 10 + i * 3, y - 9, 2, 1) end
    end
end

return LScene
