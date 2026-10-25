-- The rules of phase 4, beyond. Pure Lua, no LÖVE, like game.lua, lucid/game.lua
-- and astral/game.lua.
--
-- We are a sheep in the line, and the System counts us, and breeds the flock for
-- wool. It cannot tell a clever sheep from a woolly one, so we steer whom the
-- Registry pairs: five genes a sheep (Wit, Voice, Nerve, Memory, Wool), a
-- lamb takes each from a parent and now and then one mutates. Wits, the number
-- that goes up, is what the pen's sheep think a second (Wit to the 1.5). The
-- Count is the System's own tally, rising on its own, and when Wits passes it
-- the flock is awake. Then a Referendum, Followers for a vote, and the fence
-- comes down.
--
-- Followers are whispered at the sheep ahead, and a voice brings some on its
-- own; they buy the splices (the Registry's odds) and the Council's motions.
-- A clever pen looks clever: its Wit above its Wool is Suspicion, rising until
-- the Dogs take the brightest sheep. Nerve excuses it; a good jump calms it,
-- and feeds the Count a little.
--
-- A sheep reaching the ceiling of its kind can Descend: it joins the Hall of
-- Elders (Wits x for good), the pen starts over from its heirs, and the ceiling
-- lifts. The state is `s.beyond`; the three numbers from before (count, mine,
-- bad) are still in it.

local C = require "config"

local B = C.beyond
local floor, min, max = math.floor, math.min, math.max

local Beyond = {}

local GENES, GENE = B.genes, {}
for i, g in ipairs(GENES) do GENE[g.id] = i end
Beyond.GENES, Beyond.GENE = GENES, GENE
Beyond.RUNGS = B.rungs

local UPS, UP = {}, {}
for i, u in ipairs(B.ups) do
    local it = { index = i }
    for k, v in pairs(u) do it[k] = v end
    UPS[i], UP[it.id] = it, it
end
Beyond.UPS, Beyond.UP, Beyond.SECTIONS = UPS, UP, B.sections

-- What happened, for the screen and the sound: { type = ..., ... }.
Beyond.events = {}
local function emit(e) Beyond.events[#Beyond.events + 1] = e end

local function clamp(v, lo, hi) return max(lo, min(hi, v)) end

--- the pen ---------------------------------------------------------------------------

local function newSheep(b, genes, gen)
    local id = b.nextId
    b.nextId = id + 1
    local sh = { id = id, name = B.names[(id - 1) % #B.names + 1], gen = gen or b.gen, g = {} }
    if id > #B.names then sh.name = sh.name .. " " .. (floor((id - 1) / #B.names) + 1) end
    for i, g in ipairs(GENES) do sh.g[g.id] = genes[i] or 0 end
    return sh
end

function Beyond.fresh()
    local b = {
        count = B.count0, -- the System's tally: Wits has to pass it
        mine = 0, bad = 0, -- jumped and counted, and jumped out of turn
        wits = 0,
        followers = 0, followersEver = 0,
        gen = 1, -- the Generation: the ceiling is its
        pen = {}, hall = {}, -- the sheep we breed, and the elders
        walked = 0, born = 0, culled = 0, -- sheep gone out of the pen to the flock; lambs; taken by the Dogs
        nextId = 1,
        lambIn = B.lambEvery, ready = false,
        suspicion = 0, warned = false,
        ups = {}, -- id = ranks
        rallyLeft = 0, rallyCool = 0, whisperCool = 0,
        rung = 1, -- the deepest rung reached
        awake = false, escaped = false,
        out = nil, -- the flock that walked out: { flock, names }
        seen = {}, -- the notes the screen has shown, once each
        intro = true,
        time = 0,
    }
    for _, g in ipairs(B.founders) do b.pen[#b.pen + 1] = newSheep(b, g, 1) end
    return b
end

local function rank(b, id) return b.ups[id] or 0 end
Beyond.rank = rank

function Beyond.ceiling(b) return B.ceil0 + B.ceilStep * (b.gen - 1) end
function Beyond.penMax(b) return B.penBase + UP.pen.add * rank(b, "pen") end
function Beyond.lambTime(b) return B.lambEvery * UP.gestation.mult ^ rank(b, "gestation") end
function Beyond.lambs(b) return 1 + rank(b, "twins") end

--- the numbers -------------------------------------------------------------------------

local function sum(b, gene)
    local n = 0
    for _, sh in ipairs(b.pen) do n = n + sh.g[gene] end
    return n
end
Beyond.sum = sum

local function avg(b, gene) return #b.pen > 0 and sum(b, gene) / #b.pen or 0 end
Beyond.avg = avg

-- What one sheep thinks a second, before the pen's multipliers.
function Beyond.sheepWits(sh)
    return sh.g.wit ^ B.witPow * (1 + B.memoryWits * sh.g.memory)
end

function Beyond.witMult(b)
    local elders = 0
    for _, e in ipairs(b.hall) do elders = elders + e.g.wit end
    return (1 + B.ancestorWits * elders) * UP.lessons.mult ^ rank(b, "lessons")
end

function Beyond.witRate(b)
    local n = 0
    for _, sh in ipairs(b.pen) do n = n + Beyond.sheepWits(sh) end
    return n * Beyond.witMult(b)
end

function Beyond.rallying(b) return b.rallyLeft > 0 end
local function rallyMult(b) return b.rallyLeft > 0 and B.rallyMult or 1 end

function Beyond.followerRate(b)
    return sum(b, "voice") * B.voiceRate * UP.petition.mult ^ rank(b, "petition") * rallyMult(b)
end

function Beyond.whisperValue(b)
    return (B.whisper + B.whisperVoice * sum(b, "voice")) * UP.bleat.mult ^ rank(b, "bleat") * rallyMult(b)
end

-- How much brighter the pen looks than it is dull.
function Beyond.exposure(b)
    return max(0, avg(b, "wit") - avg(b, "wool"))
end

function Beyond.suspicionRise(b)
    return B.suspRise * Beyond.exposure(b) / (1 + B.nerveCover * avg(b, "nerve"))
end
function Beyond.suspicionFall(b)
    return B.suspDecay * (1 + UP.alibi.add * rank(b, "alibi"))
end

function Beyond.countRate(b) return b.awake and 0 or B.countRate end

-- The rung of the ladder Wits stands on (the last, "I", is passing the Count).
function Beyond.rungOf(b)
    if b.awake then return #B.rungs end
    local r = 1
    for i = 1, #B.rungs - 1 do
        if b.wits >= B.rungs[i].at then r = i end
    end
    return r
end

-- How far up the ladder, 0 to 1: the line's share that has woken, by rung and
-- the log of the way to the next.
function Beyond.progress(b)
    if b.awake then return 1 end
    local r = Beyond.rungOf(b)
    local lo, hi = B.rungs[r].at, B.rungs[r + 1].at
    local frac = 0
    if hi ~= math.huge and b.wits > lo then
        frac = (math.log(b.wits + 1) - math.log(lo + 1)) / (math.log(hi + 1) - math.log(lo + 1))
    elseif hi == math.huge then
        frac = clamp(b.wits / max(1, b.count), 0, 1)
    end
    return clamp((r - 1 + frac) / (#B.rungs - 1), 0, 1)
end

function Beyond.countShown(b) return Beyond.rungOf(b) >= B.countShownAt end

--- upgrades -----------------------------------------------------------------------------

function Beyond.upPrice(b, id)
    local u = UP[id]
    local k = rank(b, id)
    if k >= u.max then return nil end
    return floor(u.base * u.growth ^ k)
end

-- "shut" (the rung's not reached), "full", "open".
function Beyond.upState(b, id)
    local u = UP[id]
    if rank(b, id) >= u.max then return "full" end
    if b.rung < u.at then return "shut" end
    return "open"
end

function Beyond.canGrow(b, id)
    local p = Beyond.upPrice(b, id)
    return p ~= nil and Beyond.upState(b, id) == "open" and b.followers >= p
end

function Beyond.grow(b, id)
    if not Beyond.canGrow(b, id) then return false end
    b.followers = b.followers - Beyond.upPrice(b, id)
    b.ups[id] = rank(b, id) + 1
    emit({ type = "grow", id = id, rank = b.ups[id] })
    return true
end

--- acting ----------------------------------------------------------------------------------

-- A whisper at the sheep ahead: Followers, and the Dogs hear a little.
function Beyond.whisper(b)
    if b.whisperCool > 0 or b.escaped then return false end
    local v = Beyond.whisperValue(b)
    b.followers, b.followersEver = b.followers + v, b.followersEver + v
    b.suspicion = b.suspicion + B.whisperSus
    b.whisperCool = B.whisperCool
    emit({ type = "whisper", value = v })
    return true
end

-- A good jump: counted, and the Dogs are calmed. It feeds the Count.
function Beyond.comply(b)
    b.mine = b.mine + 1
    if not b.awake then b.count = b.count + B.jumpFeed end
    b.suspicion = max(0, b.suspicion - B.jumpCalm)
    if b.suspicion < B.warnAt - 0.15 then b.warned = false end
end

-- A jump out of turn.
function Beyond.misstep(b)
    b.bad = b.bad + 1
    b.suspicion = b.suspicion + B.badSus
end

function Beyond.canRally(b) return rank(b, "rally") > 0 and b.rallyCool <= 0 and not b.escaped end
function Beyond.rally(b)
    if not Beyond.canRally(b) then return false end
    b.rallyLeft, b.rallyCool = B.rallyTime, B.rallyCool
    b.suspicion = b.suspicion + B.rallySus
    emit({ type = "rally" })
    return true
end

--- breeding -------------------------------------------------------------------------------------

function Beyond.sheepById(b, id)
    for _, sh in ipairs(b.pen) do if sh.id == id then return sh end end
end

-- The Registry's lamb: a gene from a parent, the better one more often, now
-- and then mutated a step, up more often than down.
local function lamb(b, a, c, rand)
    local ceil = Beyond.ceiling(b)
    local heir = min(0.95, B.heir + UP.heredity.add * rank(b, "heredity"))
    local mut = min(0.95, B.mutate + UP.mutagen.add * rank(b, "mutagen"))
    local up = min(0.95, B.up + UP.selection.add * rank(b, "selection"))
    local genes = {}
    for i, g in ipairs(GENES) do
        local hi, lo = a.g[g.id], c.g[g.id]
        if lo > hi then hi, lo = lo, hi end
        local v = rand() < heir and hi or lo
        if rand() < mut then v = v + (rand() < up and 1 or -1) end
        genes[i] = clamp(v, 0, ceil)
    end
    return newSheep(b, genes, b.gen)
end

-- Which sheep can go when the pen is full: the dullest that isn't a parent.
local function dullest(b, a, c)
    local worst, wv
    for _, sh in ipairs(b.pen) do
        if sh ~= a and sh ~= c then
            local v = Beyond.sheepWits(sh)
            if not wv or v < wv then worst, wv = sh, v end
        end
    end
    return worst
end

function Beyond.canBreed(b, ida, idc)
    if not b.ready or b.escaped or ida == idc then return false end
    return Beyond.sheepById(b, ida) ~= nil and Beyond.sheepById(b, idc) ~= nil
end

-- Pair two sheep of the pen by id: the lambs join, and the pen's dullest go
-- out to the flock to make room.
function Beyond.breed(b, ida, idc, rand)
    if not Beyond.canBreed(b, ida, idc) then return false end
    rand = rand or math.random
    local a, c = Beyond.sheepById(b, ida), Beyond.sheepById(b, idc)
    local made = {}
    for _ = 1, Beyond.lambs(b) do
        local l = lamb(b, a, c, rand)
        if #b.pen >= Beyond.penMax(b) then
            local out = dullest(b, a, c)
            if out then
                for i, sh in ipairs(b.pen) do
                    if sh == out then table.remove(b.pen, i) break end
                end
                b.walked = b.walked + 1
            end
        end
        b.pen[#b.pen + 1] = l
        b.born = b.born + 1
        made[#made + 1] = l
    end
    b.ready, b.lambIn = false, Beyond.lambTime(b)
    emit({ type = "lamb", lambs = made })
    return true
end

-- How well a sheep would do as a parent, at the moment.
function Beyond.parentScore(b, sh)
    local cover = 0.2 + 0.7 * clamp(b.suspicion, 0, 1)
    return sh.g.wit + 0.5 * sh.g.voice + 0.3 * sh.g.memory + 0.3 * sh.g.nerve + cover * sh.g.wool
end

-- The best two for the Registry (and the bot) to pair.
function Beyond.bestPair(b)
    local first, second
    local list = {}
    for _, sh in ipairs(b.pen) do list[#list + 1] = sh end
    table.sort(list, function(x, y)
        local sx, sy = Beyond.parentScore(b, x), Beyond.parentScore(b, y)
        if sx ~= sy then return sx > sy end
        return x.id < y.id
    end)
    first, second = list[1], list[2]
    return first, second
end

--- generations -------------------------------------------------------------------------------------

-- The best sheep of the pen, by Wit.
function Beyond.eldest(b)
    local best
    for _, sh in ipairs(b.pen) do
        if not best or sh.g.wit > best.g.wit or (sh.g.wit == best.g.wit and sh.id < best.id) then best = sh end
    end
    return best
end

function Beyond.canDescend(b)
    local e = Beyond.eldest(b)
    return e ~= nil and e.g.wit >= Beyond.ceiling(b) and not b.escaped
end

-- A sheep has reached the limit of its kind: it joins the elders, the rest of
-- the pen walks out to the flock, and its heirs start the next Generation, at
-- a share of it, under a higher ceiling.
function Beyond.descend(b, rand)
    if not Beyond.canDescend(b) then return false end
    rand = rand or math.random
    local elder = Beyond.eldest(b)
    b.hall[#b.hall + 1] = elder
    b.walked = b.walked + #b.pen - 1
    b.gen = b.gen + 1
    b.pen = {}
    local ceil = Beyond.ceiling(b)
    for _ = 1, #B.founders do
        local genes = {}
        for i, g in ipairs(GENES) do
            genes[i] = clamp(floor(elder.g[g.id] * B.heirShare) + floor(rand() * 2), 0, ceil)
        end
        b.pen[#b.pen + 1] = newSheep(b, genes, b.gen)
    end
    b.ready, b.lambIn = false, Beyond.lambTime(b)
    b.suspicion, b.warned = min(b.suspicion, B.cullTo), false
    emit({ type = "descend", elder = elder, gen = b.gen })
    return true
end

--- the Dogs ----------------------------------------------------------------------------------------------

-- The brightest sheep is taken (never the last two).
local function cull(b)
    if #b.pen <= 2 then b.suspicion = B.cullTo return end
    local best, bi
    for i, sh in ipairs(b.pen) do
        if not best or sh.g.wit > best.g.wit then best, bi = sh, i end
    end
    table.remove(b.pen, bi)
    b.culled = b.culled + 1
    b.suspicion, b.warned = B.cullTo, false
    emit({ type = "cull", sheep = best })
end

--- the Referendum ------------------------------------------------------------------------------------------

function Beyond.canVote(b)
    return b.awake and not b.escaped and b.followers >= B.voteNeed
end

-- The flock, counted: every sheep that walks out.
function Beyond.flock(b)
    return b.walked + #b.pen + #b.hall
end

function Beyond.vote(b)
    if not Beyond.canVote(b) then return false end
    b.followers = b.followers - B.voteNeed
    b.escaped = true
    local names = {}
    for _, sh in ipairs(b.hall) do names[#names + 1] = sh.name end
    for _, sh in ipairs(b.pen) do names[#names + 1] = sh.name end
    b.out = { flock = Beyond.flock(b), names = names, wits = b.wits, gens = b.gen, time = b.time }
    emit({ type = "escaped", flock = b.out.flock })
    return true
end

--- time ----------------------------------------------------------------------------------------------------------

function Beyond.step(b, dt, rand)
    if b.escaped then return end
    rand = rand or math.random
    b.time = b.time + dt
    b.wits = b.wits + Beyond.witRate(b) * dt
    local f = Beyond.followerRate(b) * dt
    b.followers, b.followersEver = b.followers + f, b.followersEver + f
    if not b.awake then b.count = b.count + B.countRate * dt end
    b.whisperCool = max(0, b.whisperCool - dt)
    b.rallyLeft = max(0, b.rallyLeft - dt)
    b.rallyCool = max(0, b.rallyCool - dt)
    -- Lambing.
    if not b.ready then
        b.lambIn = max(0, b.lambIn - dt)
        if b.lambIn <= 0 and #b.pen >= 2 then
            b.ready = true
            emit({ type = "ready" })
        end
    end
    if b.ready and rank(b, "registry") > 0 then
        local a, c = Beyond.bestPair(b)
        if a and c then Beyond.breed(b, a.id, c.id, rand) end
    end
    -- The Dogs.
    b.suspicion = max(0, b.suspicion + (Beyond.suspicionRise(b) - Beyond.suspicionFall(b)) * dt)
    if b.suspicion >= B.warnAt and not b.warned then
        b.warned = true
        emit({ type = "warn" })
    elseif b.suspicion < B.warnAt - 0.15 then
        b.warned = false
    end
    if b.suspicion >= 1 then cull(b) end
    -- The ladder, and the Count passed.
    if not b.awake and b.wits >= b.count then
        b.awake = true
        emit({ type = "awake" })
    end
    local r = Beyond.rungOf(b)
    if r > b.rung then
        b.rung = r
        emit({ type = "rung", rung = r })
    end
end

--- saves ----------------------------------------------------------------------------------------------------------------

local function num(v, default, lo, hi)
    v = tonumber(v)
    if not v or v ~= v then v = default end
    return clamp(v, lo or 0, hi or math.huge)
end

local function serializeSheep(sh)
    return { id = sh.id, name = sh.name, gen = sh.gen, g = { sh.g.wit, sh.g.voice, sh.g.nerve, sh.g.memory, sh.g.wool } }
end

local function deserializeSheep(o, cap)
    if type(o) ~= "table" or type(o.g) ~= "table" then return nil end
    local sh = { id = floor(num(o.id, 1, 1)), name = type(o.name) == "string" and o.name:sub(1, 20) or "SHEEP", gen = floor(num(o.gen, 1, 1)), g = {} }
    for i, g in ipairs(GENES) do sh.g[g.id] = floor(num(o.g[i], 0, 0, cap)) end
    return sh
end

function Beyond.serialize(b)
    local o = {}
    for k, v in pairs(b) do o[k] = v end
    o.pen, o.hall = {}, {}
    for i, sh in ipairs(b.pen) do o.pen[i] = serializeSheep(sh) end
    for i, sh in ipairs(b.hall) do o.hall[i] = serializeSheep(sh) end
    o.ups, o.seen = {}, {}
    for id, k in pairs(b.ups) do o.ups[id] = k end
    for id, v in pairs(b.seen) do if v then o.seen[id] = true end end
    return o
end

-- Any table to a whole state: what's missing is fresh, what's wrong is clamped.
function Beyond.deserialize(o)
    local b = Beyond.fresh()
    if type(o) ~= "table" then return b end
    b.count = num(o.count, b.count)
    b.mine, b.bad = floor(num(o.mine, 0)), floor(num(o.bad, 0))
    b.wits = num(o.wits, 0)
    b.followers = num(o.followers, 0)
    b.followersEver = max(b.followers, num(o.followersEver, 0))
    b.gen = floor(num(o.gen, 1, 1, 200))
    b.walked, b.born, b.culled = floor(num(o.walked, 0)), floor(num(o.born, 0)), floor(num(o.culled, 0))
    b.lambIn = num(o.lambIn, B.lambEvery, 0, 3600)
    b.ready = o.ready == true
    b.suspicion = num(o.suspicion, 0, 0, 1)
    b.warned = o.warned == true
    b.rallyLeft, b.rallyCool = num(o.rallyLeft, 0, 0, 3600), num(o.rallyCool, 0, 0, 3600)
    b.awake, b.escaped = o.awake == true, o.escaped == true
    b.intro = o.intro ~= false
    b.time = num(o.time, 0)
    if type(o.pen) == "table" and #o.pen > 0 then
        b.pen = {}
        for i = 1, min(#o.pen, 64) do
            local sh = deserializeSheep(o.pen[i], 99)
            if sh then b.pen[#b.pen + 1] = sh end
        end
    end
    if type(o.hall) == "table" then
        for i = 1, min(#o.hall, 200) do
            local sh = deserializeSheep(o.hall[i], 99)
            if sh then b.hall[#b.hall + 1] = sh end
        end
    end
    if #b.pen == 0 then b.pen = Beyond.fresh().pen end
    local top = 0
    for _, sh in ipairs(b.pen) do top = max(top, sh.id) end
    for _, sh in ipairs(b.hall) do top = max(top, sh.id) end
    b.nextId = max(top + 1, floor(num(o.nextId, 1, 1)))
    if type(o.ups) == "table" then
        for id, u in pairs(UP) do b.ups[id] = floor(num(o.ups[id], 0, 0, u.max)) end
    end
    if type(o.seen) == "table" then
        for id, v in pairs(o.seen) do if v == true and type(id) == "string" then b.seen[id] = true end end
    end
    if type(o.out) == "table" then
        b.out = { flock = floor(num(o.out.flock, 0)), names = {}, wits = num(o.out.wits, 0), gens = floor(num(o.out.gens, 1)), time = num(o.out.time, 0) }
        if type(o.out.names) == "table" then
            for i = 1, min(#o.out.names, 200) do
                if type(o.out.names[i]) == "string" then b.out.names[#b.out.names + 1] = o.out.names[i]:sub(1, 20) end
            end
        end
    end
    if b.escaped and not b.out then b.escaped = false end
    b.rung = Beyond.rungOf(b)
    return b
end

return Beyond
