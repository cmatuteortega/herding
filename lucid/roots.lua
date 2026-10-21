-- The roots, drawn: underroot's network (Mycelio's Spore Bank) under the
-- dream's field. The dreamer sleeps on the ground at the top, under a strip
-- of night, and every root of `C.dream.roots` is dug down into the soil
-- under it, joined to the one it grows from by a hypha: dotted where it
-- could grow, faint where it waits on something, lit once grown, with
-- nutrients running down it now and then. A rank grown runs its thread down
-- from the one above, a white tip at its end, and rings out from the node.
--
-- Four branches hang off the dreamer (the sky, the layers, the town, the
-- golden sheep and the dog) and down the middle the taproot: the Mirror Lake,
-- the dream challenges one under the other, and the Gate of Horn at the
-- bottom, the way out.
--
-- It only draws and says what was hit; lucid/ui.lua does the rest.

local G = require "gfx"
local Models = require "models"
local Lucid = require "lucid.game"
local lume = require "lib.lume"

local floor, min, max, abs, sin = math.floor, math.min, math.max, math.abs, math.sin

local Roots = {}

Roots.TOP = 18 -- the night strip and the ground, over the soil
Roots.ROW = 32 -- a depth down
Roots.R = 7 -- a node's radius
Roots.GROW_TIME = 0.7

Roots.grew = {} -- id = when it last grew: its thread runs down from then

-- Each branch's colour, and the taproot's.
local BRANCH = { sky = "a", layers = "l", town = "y", gold = "r" }
local function tint(r)
    if r.kind == "challenge" or r.kind == "lake" then return "c" end
    if r.kind == "gate" then return "y" end
    return BRANCH[r.branch] or "c"
end

-- Each root's picture, 7 by 7: '#' its colour, '+' an accent.
local ICON = {
    spring = { "..###..", "....#..", "..###..", "..#....", "..###..", "....#..", ".#####." },
    starbag = { "...+...", "...+...", "+++#+++", ".+###+.", "..###..", ".##.##.", ".#...#." },
    steps = { ".....##", "....###", ".......", "..##...", ".####..", ".......", "###...." },
    moonpull = { "..###..", ".##....", "##.....", "##.....", "##...+.", ".##....", "..###.." },
    architect = { "#######", "#.....#", "#.###.#", "#.#+#.#", "#.###.#", "#.....#", "#######" },
    well = { "...+...", "..+.+..", "#######", "#.....#", "#.###.#", "#.###.#", "#######" },
    dilation = { "#######", ".#...#.", "..#+#..", "...#...", "..#.#..", ".#+++#.", "#######" },
    surveyor = { ".#++...", ".#+++..", ".#++...", ".#.....", ".#.....", ".#.....", "###...." },
    market = { "...#...", "..###..", ".#####.", "#######", ".#+.+#.", ".#+.+#.", ".#####." },
    bellows = { "#.....#", ".#...#.", "..#.#..", "...+...", "..#.#..", ".#...#.", "#.....#" },
    totem = { "...#...", "..###..", ".#####.", "#######", ".##+##.", "..###..", "...#..." },
    dog = { ".#...#.", "##...##", ".......", "...#...", "..###..", ".#####.", "..###.." },
    lake = { ".......", "..###..", ".#####.", "##+####", "####+##", ".#####.", "..###.." },
    gate = { "#######", "#.....#", "#.###.#", "#.#+#.#", "#.#.#.#", "#.#.#.#", "###.###" },
    ["c.season"] = { "..###..", ".#####.", "##+#+##", "#######", ".#####.", ".......", "......." },
    ["c.stoppedClocks"] = { "..###..", ".#...#.", "#..+..#", "#..+..#", "#.....#", ".#...#.", "..###.." },
    ["c.skyHigh"] = { "...#...", "..###..", ".#.#.#.", "...#...", "...#...", ".+.#.+.", "...#..." },
    ["c.onlyOne"] = { "...#...", "..##...", "...#...", "...#...", "...#...", "...#...", "..###.." },
    ["c.shallow"] = { "#######", ".......", "#######", ".......", "#######", ".......", ".+.+.+." },
    ["c.falling"] = { "...#...", ".+.#.+.", "...#...", "...#...", ".#.#.#.", "..###..", "...#..." },
    ["c.emptySquares"] = { "#######", "#.....#", "#.....#", "#..+..#", "#.....#", "#.....#", "#######" },
}
Roots.ICON = ICON

--- where everything is -------------------------------------------------------------------

local function colW(w) return min(48, floor((w - 16) / 5)) end

-- A root's middle, in the panel's content pixels, `w` wide.
function Roots.at(r, w)
    return floor(w / 2 + r.x * colW(w)), Roots.TOP + r.depth * Roots.ROW + 4
end

function Roots.height()
    local deepest = 0
    for _, r in ipairs(Lucid.ROOTS) do deepest = max(deepest, r.depth) end
    return Roots.TOP + deepest * Roots.ROW + 24
end

-- The root under (x, y), in content pixels.
function Roots.hit(x, y, w)
    for _, r in ipairs(Lucid.ROOTS) do
        local nx, ny = Roots.at(r, w)
        if (x - nx) ^ 2 + (y - ny) ^ 2 <= (Roots.R + 4) ^ 2 then return r.id end
    end
    return nil
end

--- drawing ---------------------------------------------------------------------------------

-- A point `t` of the way along the hypha from (x0, y0) down to (x1, y1):
-- a root's curve, leaving the one it grows from heading down and a little
-- out, and coming into the next heading down (underroot's).
local function along(x0, y0, x1, y1, t)
    local k, dx = (y1 - y0) * 0.6, (x1 - x0) * 0.2
    local u = 1 - t
    local a, b, c, d = u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t
    return x0 * a + (x0 + dx) * b + (x1 - dx) * c + x1 * d, y0 * a + (y0 + k) * b + (y1 - k) * c + y1 * d
end

-- The hypha as far as `upto` (0 to 1), dotted or not, two pixels deep if
-- `thick`; where it got to.
local function thread(k, x0, y0, x1, y1, upto, dotted, thick)
    local len = abs(x1 - x0) + abs(y1 - y0)
    local steps = max(4, floor(len))
    local pts, px, py = {}, x0, y0
    for s = 0, steps do
        local f = s / steps
        if f > upto + 1e-6 then break end
        px, py = along(x0, y0, x1, y1, f)
        if not dotted or floor(s / 2) % 2 == 0 then
            G.plot(pts, px, py)
            if thick then G.plot(pts, px + 1, py) end
        end
    end
    G.points(k, pts)
    return px, py
end

-- The dreamer's ground: a strip of night, the dreamer asleep on it, the soil
-- under, a few stones in it.
local function ground(x, y, w, h, t, reduced)
    G.rect("n", x, y, w, Roots.TOP)
    for i = 0, floor(w / 9) do
        local sx = x + (i * 37) % w
        local sy = y + 2 + (i * 13) % (Roots.TOP - 8)
        if reduced or sin(t * 1.3 + i) > -0.5 then G.rect(i % 3 == 0 and "w" or "l", sx, sy, 1, 1) end
    end
    G.rect("u", x, y + Roots.TOP, w, h - Roots.TOP)
    for i = 0, floor(w * h / 500) do
        local v = (i * 73856093) % 9973
        local sx, sy = x + v % w, y + Roots.TOP + 4 + floor(v / 7) % max(1, h - Roots.TOP - 6)
        G.rect(v % 5 == 0 and "i" or "p", sx, sy, v % 3 + 1, 1)
    end
    G.rect("i", x, y + Roots.TOP, w, 1)
    G.rect("l", x, y + Roots.TOP - 1, w, 1)
end

local function icon(id, x, y, k, accent)
    local rows = ICON[id]
    if not rows then return end
    for r, row in ipairs(rows) do
        for c = 1, #row do
            local ch = row:sub(c, c)
            if ch == "#" then G.rect(k, x - 3 + c - 1, y - 3 + r - 1, 1, 1)
            elseif ch == "+" then G.rect(accent, x - 3 + c - 1, y - 3 + r - 1, 1, 1) end
        end
    end
end

-- The whole network into the panel at (x, y), `w` wide; `sel` the root picked.
function Roots.draw(L, x, y, w, sel, now, reduced)
    local h = Roots.height()
    ground(x, y, w, h, now, reduced)
    local states = {}
    for _, r in ipairs(Lucid.ROOTS) do states[r.id] = Lucid.rootState(L, r.id) end
    local function pos(r) local nx, ny = Roots.at(r, w) return x + nx, y + ny end
    -- The threads, the dim ones under the lit.
    for pass = 1, 2 do
        for i, r in ipairs(Lucid.ROOTS) do
            if r.at then
                local p = Lucid.ROOT[r.at]
                local x0, y0 = pos(p)
                local x1, y1 = pos(r)
                local st = states[r.id]
                local lit = Lucid.there(L, r.id) or st == "on"
                if not lit and pass == 1 then
                    thread((st == "open" or st == "poor") and "i" or "p", x0, y0, x1, y1, 1, true)
                elseif lit and pass == 2 then
                    local grew = Roots.grew[r.id]
                    local upto = (grew and not reduced) and min(1, (now - grew) / Roots.GROW_TIME) or 1
                    if upto < 1 then thread("i", x0, y0, x1, y1, 1, true) end
                    local k = st == "full" and tint(r) or "c"
                    if st == "on" then k = "y" end
                    local tx, ty = thread(k, x0, y0, x1, y1, upto, false, r.depth <= 2)
                    if upto < 1 then
                        G.rect("w", floor(tx) - 1, floor(ty) - 1, 3, 3)
                    elseif not reduced then
                        -- Nutrients running down it, now and then.
                        local f = (now * 0.45 + i * 0.37) % 1.6
                        if f < 1 then
                            local px, py = along(x0, y0, x1, y1, f)
                            G.rect("w", floor(px), floor(py), 1, 1)
                        end
                    end
                end
            end
        end
    end
    -- The nodes.
    local blink = reduced or floor(now * 2.5) % 2 == 0
    for _, r in ipairs(Lucid.ROOTS) do
        local nx, ny = pos(r)
        local st = states[r.id]
        if r.kind == "root" then
            love.graphics.setColor(1, 1, 1)
            local sp = Models.sheep(0.3, 0, 0, "plain", true, 0.7)
            love.graphics.draw(sp.img, nx - sp.oi, y + Roots.TOP - 1 - sp.oj)
            if not reduced and floor(now * 1.2) % 3 ~= 0 then G.text("l", "Z", nx + 7, y + 4 + floor(now * 1.2) % 3) end
        else
            local R = Roots.R
            local edge, fill, k, accent
            local tk = tint(r)
            if st == "full" then edge, fill, k, accent = tk, "u", "w", tk
            elseif st == "on" then edge, fill, k, accent = blink and "y" or "h", "u", "y", "w"
            elseif st == "open" then edge, fill, k, accent = blink and "y" or tk, "u", "c", tk
            elseif st == "poor" then edge, fill, k, accent = "i", "n", "l", "i"
            else edge, fill, k, accent = "p", "n", "p", "p" end
            if Lucid.rank(L, r.id) > 0 and st ~= "full" then edge, k = blink and st == "open" and "y" or tk, "w" end
            if sel == r.id then G.disc("w", nx, ny, R + 2) end
            local grew = Roots.grew[r.id]
            if grew and now - grew < 0.5 and not reduced then
                local rr = floor(R + 2 + (now - grew) * 16)
                local pts = {}
                for a = 0, 31 do G.plot(pts, nx + math.cos(a / 32 * 6.283) * rr, ny + math.sin(a / 32 * 6.283) * rr) end
                G.points(tk, pts)
            end
            G.disc("o", nx, ny, R + 1)
            G.disc(edge, nx, ny, R)
            if st == "full" and r.kind ~= "lake" then
                G.disc("o", nx, ny, R - 1)
                G.disc(fill, nx, ny, R - 2)
            else
                G.disc(fill, nx, ny, R - 1)
            end
            icon(r.id, nx, ny, k, accent)
            -- A pip a rank grown, and a dark one for the next.
            if r.kind == "up" and r.max > 1 then
                local n = Lucid.rank(L, r.id)
                local shown = min(r.max, n + 1)
                local pw = shown * 2 - 1
                for j = 1, shown do
                    G.rect(j <= n and "w" or "p", nx - floor(pw / 2) + (j - 1) * 2, ny + R + 3, 1, 1)
                end
            end
        end
    end
    -- The one picked, named over it.
    local r = sel and Lucid.ROOT[sel]
    if r and r.kind ~= "root" then
        local nx, ny = pos(r)
        local s = Roots.name(r):upper()
        local tw = G.textWidth(s)
        local tx = floor(lume.clamp(nx - tw / 2, x + 2, x + w - tw - 2))
        G.box(tx - 1, ny - Roots.R - 10, tw + 2, 7, "o", "o")
        G.text("w", s, tx, ny - Roots.R - 9)
    end
end

-- A root's name and what it does, a challenge's from its challenge.
function Roots.name(r)
    if r.kind == "challenge" then return Lucid.CH[r.challenge].name end
    return r.name
end

return Roots
