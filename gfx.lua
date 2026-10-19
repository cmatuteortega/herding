-- The palette, and the few ways a pixel gets onto the canvas.
--
-- The rule from underroot and Survive School, kept: eight colours, and nothing
-- is drawn outside them. No alpha and no blending anywhere, so a "soft" thing
-- (the dog's pressure field) is dithered, never translucent. Each key also
-- names the key one step darker, for shadows.

local G = {}

local floor, sqrt = math.floor, math.sqrt

local function hex(s)
    return { tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255, 1 }
end

-- key, colour, the key one step darker.
G.LIST = {
    { "o", "37364e", "o" }, -- ink: outlines, the darkest thing there is
    { "t", "355d69", "o" }, -- deep teal: grass in shadow, shadows
    { "g", "6aae9d", "t" }, -- grass
    { "m", "b9d4b4", "g" }, -- mint: lit grass, the pressure field
    { "w", "f4e9d4", "b" }, -- cream: wool, glints, panels
    { "b", "d0baa9", "s" }, -- beige: wool in shade, straw, rails
    { "s", "9e8e91", "p" }, -- mauve grey: stone, wood, wool underside
    { "p", "5b4a68", "o" }, -- plum: the dog, sheep faces and legs
}
G.C, G.DARKER = {}, {}
for _, row in ipairs(G.LIST) do
    G.C[row[1]] = hex(row[2])
    G.DARKER[row[1]] = row[3]
end

function G.set(k) love.graphics.setColor(G.C[k]) end

function G.rect(k, x, y, w, h)
    G.set(k)
    love.graphics.rectangle("fill", floor(x), floor(y), w, h)
end

-- Points as a flat list of pixel coordinates; plotted at pixel centres.
function G.points(k, list)
    if #list == 0 then return end
    G.set(k)
    love.graphics.points(list)
end

function G.plot(list, x, y)
    list[#list + 1] = floor(x) + 0.5
    list[#list + 1] = floor(y) + 0.5
end

-- Bresenham, so a line is whole pixels and nothing else.
function G.line(k, x0, y0, x1, y1)
    x0, y0, x1, y1 = floor(x0 + 0.5), floor(y0 + 0.5), floor(x1 + 0.5), floor(y1 + 0.5)
    local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
    local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
    local err, pts = dx + dy, {}
    while true do
        pts[#pts + 1], pts[#pts + 2] = x0 + 0.5, y0 + 0.5
        if x0 == x1 and y0 == y1 then break end
        local e2 = 2 * err
        if e2 >= dy then err, x0 = err + dy, x0 + sx end
        if e2 <= dx then err, y0 = err + dx, y0 + sy end
    end
    G.points(k, pts)
end

-- A filled ellipse as rows of whole pixels.
function G.ellipse(k, cx, cy, rx, ry)
    G.set(k)
    cx, cy = floor(cx + 0.5), floor(cy + 0.5)
    for dy = -ry, ry do
        local hw = floor(rx * sqrt(math.max(0, 1 - (dy / (ry + 0.5)) ^ 2)) + 0.5)
        if hw > 0 then love.graphics.rectangle("fill", cx - hw, cy + dy, hw * 2, 1) end
    end
end

-- 4x4 ordered dither: a pixel is "on" at density v (0..1) where v beats this.
local BAYER = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }
function G.dither(x, y, v)
    return v * 16 > BAYER[(y % 4) * 4 + (x % 4) + 1] + 0.5
end

--- the 3x5 face, Survive School's by way of underroot ---------------------------

local GLYPHS = {
    A = { ".#.", "#.#", "###", "#.#", "#.#" }, B = { "##.", "#.#", "##.", "#.#", "##." },
    C = { ".##", "#..", "#..", "#..", ".##" }, D = { "##.", "#.#", "#.#", "#.#", "##." },
    E = { "###", "#..", "##.", "#..", "###" }, F = { "###", "#..", "##.", "#..", "#.." },
    G = { ".##", "#..", "#.#", "#.#", ".##" }, H = { "#.#", "#.#", "###", "#.#", "#.#" },
    I = { "###", ".#.", ".#.", ".#.", "###" }, J = { "..#", "..#", "..#", "#.#", ".#." },
    K = { "#.#", "##.", "#..", "##.", "#.#" }, L = { "#..", "#..", "#..", "#..", "###" },
    M = { "#.#", "###", "###", "#.#", "#.#" }, N = { "#.#", "##.", "###", ".##", "#.#" },
    O = { ".#.", "#.#", "#.#", "#.#", ".#." }, P = { "##.", "#.#", "##.", "#..", "#.." },
    Q = { ".#.", "#.#", "#.#", "##.", ".##" }, R = { "##.", "#.#", "##.", "#.#", "#.#" },
    S = { ".##", "#..", ".#.", "..#", "##." }, T = { "###", ".#.", ".#.", ".#.", ".#." },
    U = { "#.#", "#.#", "#.#", "#.#", "###" }, V = { "#.#", "#.#", "#.#", "#.#", ".#." },
    W = { "#.#", "#.#", "###", "###", "#.#" }, X = { "#.#", "#.#", ".#.", "#.#", "#.#" },
    Y = { "#.#", "#.#", ".#.", ".#.", ".#." }, Z = { "###", "..#", ".#.", "#..", "###" },
    ["0"] = { "###", "#.#", "#.#", "#.#", "###" }, ["1"] = { ".#.", "##.", ".#.", ".#.", "###" },
    ["2"] = { "##.", "..#", ".#.", "#..", "###" }, ["3"] = { "##.", "..#", ".#.", "..#", "##." },
    ["4"] = { "#.#", "#.#", "###", "..#", "..#" }, ["5"] = { "###", "#..", "##.", "..#", "##." },
    ["6"] = { ".##", "#..", "###", "#.#", "###" }, ["7"] = { "###", "..#", ".#.", ".#.", ".#." },
    ["8"] = { "###", "#.#", "###", "#.#", "###" }, ["9"] = { "###", "#.#", "###", "..#", "##." },
    [":"] = { "...", ".#.", "...", ".#.", "..." }, ["."] = { "...", "...", "...", "...", ".#." },
    ["-"] = { "...", "...", "###", "...", "..." }, ["/"] = { "..#", "..#", ".#.", "#..", "#.." },
    ["!"] = { ".#.", ".#.", ".#.", "...", ".#." }, ["?"] = { "##.", "..#", ".#.", "...", ".#." },
    ["+"] = { "...", ".#.", "###", ".#.", "..." }, [","] = { "...", "...", "...", ".#.", "#.." },
    ["'"] = { ".#.", ".#.", "...", "...", "..." }, ["%"] = { "#.#", "..#", ".#.", "#..", "#.#" },
    [">"] = { "#..", ".#.", "..#", ".#.", "#.." }, ["<"] = { "..#", ".#.", "#..", ".#.", "..#" },
}
local ADVANCE = 4

function G.textWidth(s) return #s * ADVANCE - 1 end

function G.text(k, s, x, y)
    local pts = {}
    x, y = floor(x), floor(y)
    s = s:upper()
    for n = 1, #s do
        local g = GLYPHS[s:sub(n, n)]
        if g then
            for r = 1, 5 do
                local row = g[r]
                for c = 1, 3 do
                    if row:byte(c) == 35 then G.plot(pts, x + c - 1, y + r - 1) end
                end
            end
        end
        x = x + ADVANCE
    end
    G.points(k, pts)
end

-- Text blown up `sc` times, as rectangles: points don't scale.
function G.bigText(k, s, x, y, sc)
    G.set(k)
    x, y = floor(x), floor(y)
    s = s:upper()
    for n = 1, #s do
        local g = GLYPHS[s:sub(n, n)]
        if g then
            for r = 1, 5 do
                for c = 1, 3 do
                    if g[r]:byte(c) == 35 then
                        love.graphics.rectangle("fill", x + (c - 1) * sc, y + (r - 1) * sc, sc, sc)
                    end
                end
            end
        end
        x = x + ADVANCE * sc
    end
end

function G.bigWidth(s, sc) return (#s * ADVANCE - 1) * sc end

-- A little picture from rows of "#", with an ink edge when `edge` is set.
function G.sprite(k, rows, x, y, edge)
    x, y = floor(x), floor(y)
    local function put(key, ox, oy)
        local pts = {}
        for r, row in ipairs(rows) do
            for c = 1, #row do
                if row:byte(c) == 35 then G.plot(pts, x + c - 1 + ox, y + r - 1 + oy) end
            end
        end
        G.points(key, pts)
    end
    if edge then
        for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do put("o", d[1], d[2]) end
    end
    put(k, 0, 0)
end

G.HEART = { "##.##", "#####", ".###.", "..#.." }
G.LOCK = { ".#.", "#.#", "###", "###" }

-- Text with a one-pixel ink edge, for reading over grass.
function G.label(k, s, x, y)
    for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do G.text("o", s, x + d[1], y + d[2]) end
    G.text(k, s, x, y)
end

return G
