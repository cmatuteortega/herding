-- The palette, and the few ways a pixel gets onto the canvas.
--
-- herding's rule, from underroot and Survive School: a short list of colours,
-- and nothing drawn outside it. No alpha and no blending anywhere, so a soft
-- thing (the dusk sky, night falling over the grass, a number fading out) is
-- dithered, never translucent. Each key also names the key one step darker.

local G = {}

local floor, sqrt = math.floor, math.sqrt

local function hex(s)
    return { tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255, 1 }
end

-- key, colour, the key one step darker. herding's eight, the night's six, then
-- the lucid dream's four: deep violet, rose, aurora green and cloud.
G.LIST = {
    { "o", "37364e", "n" }, -- ink: outlines
    { "t", "355d69", "o" }, -- deep teal: grass in shadow
    { "g", "6aae9d", "t" }, -- grass
    { "m", "b9d4b4", "g" }, -- mint: lit grass
    { "w", "f4e9d4", "b" }, -- cream: wool, glints, panels
    { "b", "d0baa9", "s" }, -- beige: wool in shade, the dusk horizon
    { "s", "9e8e91", "p" }, -- mauve grey: stone, wood
    { "p", "5b4a68", "o" }, -- plum: faces, legs
    { "n", "1c1e38", "n" }, -- deep navy: the night sky, the page
    { "v", "2a2c50", "n" }, -- midnight: panels at night
    { "l", "b7a8dc", "i" }, -- lavender
    { "i", "8577b0", "p" }, -- lilac
    { "y", "f0cf7a", "h" }, -- gold
    { "h", "c0904e", "p" }, -- gold in shade
    { "u", "3b2d6e", "n" }, -- deep violet: the dream's sky
    { "r", "e5a3c8", "i" }, -- rose: aurora, warmth
    { "a", "86d9bd", "g" }, -- aurora green
    { "c", "e4def5", "l" }, -- cloud: wool that's turning to sky
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

-- 4x4 ordered dither: pixel (x, y) is "on" at density v (0..1).
local BAYER = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }
function G.dither(x, y, v)
    return v * 16 > BAYER[(y % 4) * 4 + (x % 4) + 1] + 0.5
end

-- Points as a flat list of pixel coordinates; plotted at pixel centres.
function G.plot(list, x, y)
    list[#list + 1] = floor(x) + 0.5
    list[#list + 1] = floor(y) + 0.5
end
function G.points(k, list)
    if #list == 0 then return end
    G.set(k)
    love.graphics.points(list)
end

-- A filled disc as rows of whole pixels, dithered away below density 1.
function G.disc(k, cx, cy, r, dens)
    cx, cy = floor(cx + 0.5), floor(cy + 0.5)
    if not dens or dens >= 1 then
        G.set(k)
        for dy = -r, r do
            local hw = floor(sqrt(math.max(0, r * r - dy * dy)) + 0.5)
            love.graphics.rectangle("fill", cx - hw, cy + dy, hw * 2 + 1, 1)
        end
        return
    end
    local pts = {}
    for dy = -r, r do
        local hw = floor(sqrt(math.max(0, r * r - dy * dy)) + 0.5)
        for dx = -hw, hw do
            if G.dither(cx + dx, cy + dy, dens) then G.plot(pts, cx + dx, cy + dy) end
        end
    end
    G.points(k, pts)
end

-- A box, underroot's: a fill inside a one-pixel ink edge.
function G.box(x, y, w, h, fill, edge)
    G.rect(edge or "o", x - 1, y - 1, w + 2, h + 2)
    G.rect(fill, x, y, w, h)
end

--- the 3x5 face, Survive School's by way of underroot and herding -------------

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
    ["("] = { ".#.", "#..", "#..", "#..", ".#." }, [")"] = { ".#.", "..#", "..#", "..#", ".#." },
    ["="] = { "...", "###", "...", "###", "..." }, ["*"] = { "...", "#.#", ".#.", "#.#", "..." },
    ["#"] = { "#.#", "###", "#.#", "###", "#.#" }, [">"] = { "#..", ".#.", "..#", ".#.", "#.." },
}
local ADVANCE = 4
G.LINE = 7 -- a line of text and the gap under it

function G.textWidth(s, z) return math.max(0, #s * ADVANCE - 1) * (z or 1) end

-- `s` at (x, y), each font pixel z by z, dithered away below density `dens`.
function G.text(k, s, x, y, z, dens)
    z = z or 1
    local pts, big = {}, {}
    x, y = floor(x), floor(y)
    s = s:upper()
    for n = 1, #s do
        local g = GLYPHS[s:sub(n, n)]
        if g then
            for r = 1, 5 do
                local row = g[r]
                for c = 1, 3 do
                    if row:byte(c) == 35 then
                        local px, py = x + (c - 1) * z, y + (r - 1) * z
                        if not dens or dens >= 1 or G.dither(px, py, dens) then
                            if z == 1 then G.plot(pts, px, py) else big[#big + 1] = { px, py } end
                        end
                    end
                end
            end
        end
        x = x + ADVANCE * z
    end
    if z == 1 then G.points(k, pts) return end
    G.set(k)
    for _, p in ipairs(big) do love.graphics.rectangle("fill", p[1], p[2], z, z) end
end

-- One glyph's pixels added to a point list, for drawing many in one colour.
function G.glyph(list, ch, x, y)
    local g = GLYPHS[ch]
    if not g then return end
    for r = 1, 5 do
        local row = g[r]
        for c = 1, 3 do
            if row:byte(c) == 35 then G.plot(list, x + c - 1, y + r - 1) end
        end
    end
end

-- Text with an ink edge, for reading over the field.
local RING = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { 1, 1 } }
local RING8 = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }
function G.label(k, s, x, y, z, dens, edge)
    for _, d in ipairs((z or 1) > 1 and RING8 or RING) do G.text(edge or "o", s, x + d[1], y + d[2], z, dens) end
    G.text(k, s, x, y, z, dens)
end

-- Words broken into lines no wider than w.
function G.wrap(s, w, z)
    local lines, line = {}, ""
    for word in s:gmatch("%S+") do
        local try = line == "" and word or line .. " " .. word
        if G.textWidth(try, z) > w and line ~= "" then
            lines[#lines + 1] = line
            line = word
        else
            line = try
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

-- Pixel art from rows of palette keys ('.' is clear).
function G.art(rows, x, y)
    for r, row in ipairs(rows) do
        for c = 1, #row do
            local k = row:sub(c, c)
            if k ~= "." then G.rect(k, x + c - 1, y + r - 1, 1, 1) end
        end
    end
end

return G
