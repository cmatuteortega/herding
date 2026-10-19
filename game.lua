-- The rules: the game's state and everything that changes it. Pure Lua, no
-- LÖVE, so the tests and the balance sim run it under plain luajit
-- (tests/run.lua). The screen reads the state and the events this leaves in
-- Game.events; it never changes the state except through these functions.

local C = require "config"
local N = require "num"

local floor, min, max = math.floor, math.min, math.max

local Game = {}

-- Every item in the shop, in shop order, each with its kind.
local ITEMS, BY_ID, GENS = {}, {}, {}
local function add(kind, def, index)
    local it = { kind = kind, growth = C.growth, index = index }
    for k, v in pairs(def) do it[k] = v end
    ITEMS[#ITEMS + 1] = it
    BY_ID[it.id] = it
    if kind == "gen" then GENS[#GENS + 1] = it end
end
for _, u in ipairs(C.tapUpgrades) do add("tap", u) end
for i, g in ipairs(C.generators) do add("gen", g, i) end
for _, m in ipairs(C.multipliers) do add("mult", m) end
Game.ITEMS, Game.BY_ID, Game.GENS = ITEMS, BY_ID, GENS

local function freshOwned()
    local o = {}
    for _, it in ipairs(ITEMS) do o[it.id] = 0 end
    return o
end

-- What a run starts with.
local function freshRun(s)
    s.sheep = N.zero()
    s.runTotal = N.zero()
    s.runTime = 0
    s.owned = freshOwned()
    s.goldenIn = C.golden.firstDelay
    s.golden = nil -- { t, lane } while one is crossing
    s.stage = 1
    s.asleep = false
    return s
end

-- A new game: a run, and what lasts across runs.
function Game.fresh()
    return freshRun({
        version = 1,
        dreamPoints = 0,
        dreams = 0,
        allTime = N.zero(),
        taps = 0,
        buyMode = "1",
        muted = false,
        reducedMotion = false,
        lastSeen = os.time(),
    })
end

-- What happened, for the screen and the sound: { type = ..., ... }.
Game.events = {}
local function emit(e) Game.events[#Game.events + 1] = e end

function Game.globalMult(s)
    local m = 1
    for _, it in ipairs(ITEMS) do
        if it.kind == "mult" then m = m * (1 + it.add * s.owned[it.id]) end
    end
    return m * (1 + C.prestige.bonusPerPoint * s.dreamPoints)
end

function Game.perSecond(s)
    local r = 0
    for _, g in ipairs(GENS) do r = r + g.rate * s.owned[g.id] end
    return N.mul(N.from(r), Game.globalMult(s))
end

function Game.genRate(s, id)
    return N.mul(N.from(BY_ID[id].rate * s.owned[id]), Game.globalMult(s))
end

function Game.tapValue(s)
    local v = C.tapBase
    for _, it in ipairs(ITEMS) do
        if it.kind == "tap" and it.add then v = v + it.add * s.owned[it.id] end
    end
    for _, it in ipairs(ITEMS) do
        if it.kind == "tap" and it.mult then v = v * it.mult ^ s.owned[it.id] end
    end
    return N.mul(N.from(v), Game.globalMult(s))
end

function Game.drowsiness(s)
    local share = N.toNumber(N.div(s.runTotal, N.from(C.drowsiness.target)))
    return min(1, max(0, share) ^ C.drowsiness.curve)
end

function Game.stageOf(s)
    local k = 1
    for i, st in ipairs(C.stages) do
        if N.gte(s.runTotal, N.from(st.at)) then k = i end
    end
    return k
end

local function capLeft(s, it)
    if it.max then return max(0, it.max - s.owned[it.id]) end
    return math.huge
end

-- What buying `mode` ("1", "10" or "max") of an item would mean now:
-- { n, cost, ok, maxed }. With max and nothing affordable, the price of one.
function Game.quote(s, id, mode)
    local it = BY_ID[id]
    local k = s.owned[id]
    local left = capLeft(s, it)
    if left == 0 then return { n = 0, cost = N.zero(), ok = false, maxed = true } end
    local n
    if mode == "max" then n = min(left, N.maxAffordable(it.base, it.growth, k, N.toNumber(s.sheep)))
    else n = min(left, tonumber(mode)) end
    local some = n > 0
    if not some then n = 1 end
    local cost = N.from(N.sumGeometric(it.base, it.growth, k, n))
    return { n = n, cost = cost, ok = some and N.gte(s.sheep, cost), maxed = false }
end

-- In the shop: generators one at a time (each once the one before is owned),
-- upgrades once the run has counted a share of their price.
function Game.visible(s, id)
    local it = BY_ID[id]
    if s.owned[id] > 0 then return true end
    if it.kind == "gen" then return it.index == 1 or s.owned[GENS[it.index - 1].id] > 0 end
    return N.gte(s.runTotal, N.from(it.base * C.revealAt))
end

-- The one generator shown as "???": the first not yet visible.
function Game.teaser(s)
    for _, g in ipairs(GENS) do
        if not Game.visible(s, g.id) then return g.id end
    end
end

local function count(s, v)
    s.sheep = N.add(s.sheep, v)
    s.runTotal = N.add(s.runTotal, v)
    s.allTime = N.add(s.allTime, v)
end

function Game.buy(s, id, mode)
    if s.asleep or not Game.visible(s, id) then return nil end
    local q = Game.quote(s, id, mode)
    if not q.ok then return nil end
    local first = s.owned[id] == 0
    s.sheep = N.sub(s.sheep, q.cost)
    s.owned[id] = s.owned[id] + q.n
    emit({ type = "bought", id = id, n = q.n, first = first })
    return q
end

function Game.tap(s)
    if s.asleep then return N.zero() end
    local v = Game.tapValue(s)
    count(s, v)
    s.taps = s.taps + 1
    return v
end

function Game.goldenReward(s)
    return N.max(N.mul(Game.perSecond(s), N.from(C.golden.rewardSeconds)),
        N.mul(Game.tapValue(s), N.from(C.golden.minTaps)))
end

function Game.catchGolden(s)
    if not s.golden or s.asleep then return nil end
    local v = Game.goldenReward(s)
    count(s, v)
    s.golden = nil
    emit({ type = "golden", value = v })
    return v
end

local function settle(s)
    local st = Game.stageOf(s)
    if st > s.stage then
        s.stage = st
        emit({ type = "stage", stage = st })
    end
    if not s.asleep and Game.drowsiness(s) >= 1 then
        s.asleep = true
        s.golden = nil
        emit({ type = "asleep" })
    end
end

-- One fixed step of `dt` seconds. `rand` gives 0..1 (the tests pass seeded dice).
function Game.step(s, dt, rand)
    if s.asleep then return end
    rand = rand or math.random
    s.runTime = s.runTime + dt
    count(s, N.mul(Game.perSecond(s), N.from(dt)))
    if s.golden then
        s.golden.t = s.golden.t + dt
        if s.golden.t >= C.golden.crossTime then s.golden = nil end
    else
        s.goldenIn = s.goldenIn - dt
        if s.goldenIn <= 0 then
            s.golden = { t = 0, lane = rand() }
            s.goldenIn = C.golden.minDelay + rand() * (C.golden.maxDelay - C.golden.minDelay)
            emit({ type = "goldenAppears" })
        end
    end
    settle(s)
end

-- Away for `seconds`: up to the cap of production, counted at once.
function Game.offline(s, seconds)
    if s.asleep or seconds <= 0 then return nil end
    local cap = C.offline.maxHours * 3600
    local secs = min(seconds, cap)
    local gain = N.mul(Game.perSecond(s), N.from(secs))
    count(s, gain)
    settle(s)
    return { secs = secs, gain = gain, capped = seconds > cap }
end

function Game.dreamPointsFor(s)
    return floor(N.toNumber(N.sqrt(N.div(s.runTotal, N.from(C.prestige.divisor)))))
end

-- Fall asleep for real: Dream Points banked, and a new night.
function Game.dreamAgain(s)
    local gained = Game.dreamPointsFor(s)
    s.dreamPoints = s.dreamPoints + gained
    s.dreams = s.dreams + 1
    freshRun(s)
    return gained
end

function Game.currentLine(s)
    local d = Game.drowsiness(s)
    local text = C.lines[1].text
    for _, l in ipairs(C.lines) do
        local ok = true
        if l.total and not N.gte(s.runTotal, N.from(l.total)) then ok = false end
        if l.own and s.owned[l.own] <= 0 then ok = false end
        if l.drowsy and d < l.drowsy then ok = false end
        if ok then text = l.text end
    end
    return text
end

-- Saves: a plain table for JSON, and back. Missing fields come back fresh and
-- unknown ones are dropped, so an old save still loads.
function Game.serialize(s)
    local o = {}
    for k, v in pairs(s) do o[k] = v end
    o.sheep, o.runTotal, o.allTime = N.serialize(s.sheep), N.serialize(s.runTotal), N.serialize(s.allTime)
    o.lastSeen = os.time()
    return o
end

function Game.deserialize(o)
    if type(o) ~= "table" then return nil end
    local s = Game.fresh()
    for k, v in pairs(s) do
        if k ~= "owned" and o[k] ~= nil and type(o[k]) == type(v) then s[k] = o[k] end
    end
    if type(o.golden) == "table" and tonumber(o.golden.t) then s.golden = { t = o.golden.t, lane = tonumber(o.golden.lane) or 0.5 } end
    if type(o.owned) == "table" then
        for id in pairs(s.owned) do s.owned[id] = max(0, floor(tonumber(o.owned[id]) or 0)) end
    end
    s.sheep, s.runTotal, s.allTime = N.deserialize(o.sheep), N.deserialize(o.runTotal), N.deserialize(o.allTime)
    if s.buyMode ~= "1" and s.buyMode ~= "10" and s.buyMode ~= "max" then s.buyMode = "1" end
    s.stage = max(s.stage, Game.stageOf(s))
    return s
end

return Game
