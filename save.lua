-- What the player has done, kept between runs: how far the fields are open,
-- and the calmest each was ever finished (hearts, 1..3). A few lines of text
-- in LÖVE's save directory, "unlocked 3" and "best 1 2", so nothing breaks
-- when a line is missing or a level is added.

local Save = { unlocked = 1, best = {} }

local FILE = "progress.txt"

function Save.load()
    if not love.filesystem.getInfo(FILE) then return end
    for line in love.filesystem.lines(FILE) do
        local u = line:match("^unlocked (%d+)$")
        if u then Save.unlocked = math.max(1, tonumber(u)) end
        local n, h = line:match("^best (%d+) (%d+)$")
        if n then Save.best[tonumber(n)] = tonumber(h) end
    end
end

local function write()
    local out = { "unlocked " .. Save.unlocked }
    for n, h in pairs(Save.best) do out[#out + 1] = ("best %d %d"):format(n, h) end
    love.filesystem.write(FILE, table.concat(out, "\n") .. "\n")
end

-- Scares (Flock.scares) to hearts: none at all is three.
function Save.hearts(scares)
    if scares == 0 then return 3 end
    if scares <= 4 then return 2 end
    return 1
end

-- Level n finished with `hearts` (nil when skipped): the next one opens.
function Save.record(n, hearts)
    Save.unlocked = math.max(Save.unlocked, n + 1)
    if hearts then Save.best[n] = math.max(Save.best[n] or 0, hearts) end
    write()
end

return Save
