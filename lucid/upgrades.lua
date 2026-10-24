-- The upgrades' pictures: 7 by 7 icons for their cards on the UPGRADES tab
-- (lucid/ui.lua), '#' in the section's colour, '+' an accent, drawn two
-- pixels to one. In the code the upgrades are still the "roots".

local G = require "gfx"
local Lucid = require "lucid.game"

local Upgrades = {}

-- Each section's colour.
local TINT = { sky = "a", count = "w", nightmare = "r", gold = "y", layers = "l", town = "y", dream = "c" }
function Upgrades.tint(r)
    if r.kind == "gate" then return "y" end
    return TINT[r.section] or "c"
end

-- Each upgrade's picture.
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
    -- New with the sections: counting sheep, the dog and the cloud, slow gold.
    bell = { "...+...", "..###..", ".#####.", ".#####.", ".#####.", "#######", "...+..." },
    slowsong = { "....##.", "....#.#", "....#..", "....#..", ".###...", "####...", ".##...." },
    lullaby = { "..#...#", "..##..#", "..#.#.#", "..#..##", "###..#.", "##..###", "....##." },
    encore = { "+..#..+", "...#...", ".#####.", "...#...", "...#...", "+.....+", "...#..." },
    quickdog = { "#......", ".#..##.", "..#####", "#.####.", ".#.#.#.", "..#...#", "......." },
    nightlight = { "...+...", "..###..", ".##+##.", "..###..", "...#...", "..###..", ".#####." },
    slowgold = { ".#####.", "..+++..", "...+...", "...#...", "..#.#..", ".#...#.", ".#####." },
}
Upgrades.ICON = ICON

-- Upgrade `id`'s picture with its middle at (x, y), `z` pixels to one.
function Upgrades.icon(id, x, y, k, accent, z)
    local rows = ICON[id]
    if not rows then return end
    z = z or 2
    local ox, oy = math.floor(x - 3.5 * z), math.floor(y - 3.5 * z)
    for r, row in ipairs(rows) do
        for c = 1, #row do
            local ch = row:sub(c, c)
            if ch == "#" then G.rect(k, ox + (c - 1) * z, oy + (r - 1) * z, z, z)
            elseif ch == "+" then G.rect(accent, ox + (c - 1) * z, oy + (r - 1) * z, z, z) end
        end
    end
end

-- An upgrade's name, a challenge's from its challenge.
function Upgrades.name(r)
    if r.kind == "challenge" then return Lucid.CH[r.challenge].name end
    return r.name
end

return Upgrades
