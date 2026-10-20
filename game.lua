-- The rules: the game's state and everything that changes it. Pure Lua, no
-- LÖVE, so the tests and the balance sim run it under plain luajit
-- (tests/run.lua). The screen reads the state and the events this leaves in
-- Game.events; it never changes the state except through these functions.

local C = require "config"
local N = require "num"

local floor, min, max = math.floor, math.min, math.max
local function clamp(x, a, b) return min(b, max(a, x)) end

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

-- The Dream shop: bought with Dream Points, kept across nights. Not in ITEMS,
-- which is the night's shop.
local DREAMS = {}
for _, d in ipairs(C.dreamShop) do
    local it = { kind = "dream", growth = 1 }
    for k, v in pairs(d) do it[k] = v end
    DREAMS[#DREAMS + 1] = it
    BY_ID[it.id] = it
end
Game.ITEMS, Game.BY_ID, Game.GENS, Game.DREAMS = ITEMS, BY_ID, GENS, DREAMS

local function freshOwned()
    local o = {}
    for _, it in ipairs(ITEMS) do o[it.id] = 0 end
    return o
end

local function freshDream()
    local o = {}
    for _, it in ipairs(DREAMS) do o[it.id] = 0 end
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
    s.autoIn = 0 -- seconds to the auto-buyers' next trip
    s.tapAcc = 0 -- Sleepwalking's taps, a fraction at a time
    s.lucidNight = false -- this night was short enough to go lucid
    return s
end

-- A new game: a run, and what lasts across runs.
function Game.fresh()
    return freshRun({
        version = 1,
        dreamPoints = 0, -- to spend in the Dream shop
        dreamEarned = 0, -- ever earned: the production bonus
        dreams = 0,
        dream = freshDream(), -- the Dream shop, owned
        lastNight = 0, -- how long the last night lasted, in seconds
        -- "nights" (counting sheep), or "lucid": past the first night
        -- shorter than C.lucid.under, the next phase (a placeholder for now).
        phase = "nights",
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
    for _, it in ipairs(DREAMS) do
        if it.mult then m = m * it.mult ^ s.dream[it.id] end
    end
    return m * (1 + C.prestige.bonusPerPoint * s.dreamEarned)
end

function Game.perSecond(s)
    local r = 0
    for _, g in ipairs(GENS) do r = r + g.rate * s.owned[g.id] end
    return N.mul(N.from(r), Game.globalMult(s))
end

-- Sleepwalking's taps a second.
function Game.autoTaps(s)
    return BY_ID.sleepwalk.taps * s.dream.sleepwalk
end

-- What the counter grows by a second: the helpers and Sleepwalking.
function Game.totalPerSecond(s)
    return N.add(Game.perSecond(s), N.mul(Game.tapValue(s), N.from(Game.autoTaps(s))))
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

-- How many of an item: this night's for the shop, forever's for the Dream shop.
local function have(s, it) return it.kind == "dream" and s.dream[it.id] or s.owned[it.id] end
function Game.have(s, id) return have(s, BY_ID[id]) end

local function capLeft(s, it)
    if it.max then return max(0, it.max - have(s, it)) end
    return math.huge
end

-- Dream shop items come one at a time, priced in Dream Points.
local function dreamQuote(s, it)
    if capLeft(s, it) == 0 then return { n = 0, cost = 0, ok = false, maxed = true } end
    local cost = floor(it.base * it.growth ^ s.dream[it.id] + 0.5)
    return { n = 1, cost = cost, ok = s.dreamPoints >= cost, maxed = false, dp = true }
end

-- What buying `mode` ("1", "10" or "max") of an item would mean now:
-- { n, cost, ok, maxed }. With max and nothing affordable, the price of one.
function Game.quote(s, id, mode)
    local it = BY_ID[id]
    if it.kind == "dream" then return dreamQuote(s, it) end
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
    if it.kind == "dream" then return s.dreams > 0 or s.dreamEarned > 0 end
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

-- `auto` marks a purchase the automation made, for the screen.
function Game.buy(s, id, mode, auto)
    if s.asleep or not Game.visible(s, id) then return nil end
    local q = Game.quote(s, id, mode)
    if not q.ok then return nil end
    local it = BY_ID[id]
    local first = have(s, it) == 0
    if it.kind == "dream" then
        s.dreamPoints = s.dreamPoints - q.cost
        s.dream[id] = s.dream[id] + 1
    else
        s.sheep = N.sub(s.sheep, q.cost)
        s.owned[id] = s.owned[id] + q.n
    end
    emit({ type = "bought", id = id, n = q.n, first = first, auto = auto })
    return q
end

-- What the auto-buyers look after: Night Shift's helpers (the first `tiers`
-- per level), Sleep Talking's tap upgrades, Tucked In's comforts.
function Game.automated(s, id)
    local it = BY_ID[id]
    if it.kind == "gen" then return it.index <= BY_ID.nightShift.tiers * s.dream.nightShift end
    if it.kind == "tap" then return s.dream.sleepTalk > 0 end
    if it.kind == "mult" then return s.dream.tuckedIn > 0 end
    return false
end

-- One shopping trip: comforts, then tap upgrades, then helpers from the
-- biggest down, as many of each as a share of the sheep pays for.
local ORDER = {}
for _, it in ipairs(ITEMS) do if it.kind == "mult" then ORDER[#ORDER + 1] = it end end
for _, it in ipairs(ITEMS) do if it.kind == "tap" then ORDER[#ORDER + 1] = it end end
for i = #GENS, 1, -1 do ORDER[#ORDER + 1] = GENS[i] end
function Game.autoBuy(s)
    for _, it in ipairs(ORDER) do
        if Game.automated(s, it.id) and capLeft(s, it) > 0 then
            local budget = N.toNumber(s.sheep) * C.auto.share
            local n = min(capLeft(s, it), N.maxAffordable(it.base, it.growth, s.owned[it.id], budget))
            if n > 0 then Game.buy(s, it.id, tostring(n), true) end
        end
    end
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

function Game.catchGolden(s, auto)
    if not s.golden or s.asleep then return nil end
    local v = Game.goldenReward(s)
    count(s, v)
    local gs = s.golden
    s.golden = nil
    emit({ type = "golden", value = v, at = gs, auto = auto })
    return v
end

-- `night` is a real step of the night, not an offline catch-up, so only it
-- can make a night short enough to turn lucid.
local function settle(s, night)
    local st = Game.stageOf(s)
    if st > s.stage then
        s.stage = st
        emit({ type = "stage", stage = st })
    end
    if not s.asleep and Game.drowsiness(s) >= 1 then
        s.asleep = true
        s.golden = nil
        s.lastNight = s.runTime
        emit({ type = "asleep" })
        if night and s.phase == "nights" and s.runTime < C.lucid.under then
            s.lucidNight = true
            emit({ type = "lucid" })
        end
    end
end

-- One fixed step of `dt` seconds. `rand` gives 0..1 (the tests pass seeded dice).
function Game.step(s, dt, rand)
    if s.asleep or s.phase ~= "nights" then return end
    rand = rand or math.random
    s.runTime = s.runTime + dt
    count(s, N.mul(Game.perSecond(s), N.from(dt)))
    -- The automation, bought with Dream Points.
    s.tapAcc = s.tapAcc + Game.autoTaps(s) * dt
    if s.tapAcc >= 1 then
        local n = floor(s.tapAcc)
        s.tapAcc = s.tapAcc - n
        count(s, N.mul(Game.tapValue(s), N.from(n)))
    end
    s.autoIn = s.autoIn - dt
    if s.autoIn <= 0 then
        s.autoIn = C.auto.buyEvery
        Game.autoBuy(s)
    end
    if s.golden and s.dream.goldenDreams > 0 and s.golden.t >= C.auto.goldenAfter then Game.catchGolden(s, true) end
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
    settle(s, true)
end

-- Away for `seconds`: up to the cap of production, counted at once.
function Game.offline(s, seconds)
    if s.asleep or s.phase ~= "nights" or seconds <= 0 then return nil end
    local cap = C.offline.maxHours * 3600
    local secs = min(seconds, cap)
    local gain = N.mul(Game.perSecond(s), N.from(secs))
    count(s, gain)
    settle(s)
    return { secs = secs, gain = gain, capped = seconds > cap }
end

-- How much quicker than a first night this one was: the Dream Point multiplier.
function Game.pace(s)
    local P = C.prestige
    return clamp((P.paceRef / max(s.runTime, 1)) ^ P.pacePower, 1, P.paceMax)
end

function Game.dreamPointsFor(s)
    local catchers = 1
    for _, it in ipairs(DREAMS) do
        if it.add then catchers = catchers + it.add * s.dream[it.id] end
    end
    return floor(N.toNumber(N.sqrt(N.div(s.runTotal, N.from(C.prestige.divisor)))) * catchers * Game.pace(s))
end

-- Fall asleep for real: Dream Points banked, and a new night.
function Game.dreamAgain(s)
    local gained = Game.dreamPointsFor(s)
    s.dreamPoints = s.dreamPoints + gained
    s.dreamEarned = s.dreamEarned + gained
    s.dreams = s.dreams + 1
    -- Warm Bed: a share of every helper stays for the new night.
    local keep = {}
    for _, g in ipairs(GENS) do keep[g.id] = floor(s.owned[g.id] * BY_ID.warmBed.keep * s.dream.warmBed) end
    freshRun(s)
    for id, n in pairs(keep) do s.owned[id] = n end
    return gained
end

-- After a lucid night: its Dream Points banked, and on to the next phase.
function Game.goLucid(s)
    local gained = Game.dreamAgain(s)
    s.phase = "lucid"
    return gained
end

-- Back from the lucid placeholder to counting, the Dream shop and all.
function Game.backToNights(s)
    s.phase = "nights"
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
        if k ~= "owned" and k ~= "dream" and o[k] ~= nil and type(o[k]) == type(v) then s[k] = o[k] end
    end
    if type(o.golden) == "table" and tonumber(o.golden.t) then s.golden = { t = o.golden.t, lane = tonumber(o.golden.lane) or 0.5 } end
    if type(o.owned) == "table" then
        for id in pairs(s.owned) do s.owned[id] = max(0, floor(tonumber(o.owned[id]) or 0)) end
    end
    if type(o.dream) == "table" then
        for _, it in ipairs(DREAMS) do
            s.dream[it.id] = clamp(floor(tonumber(o.dream[it.id]) or 0), 0, it.max or math.huge)
        end
    end
    -- Saves from before the Dream shop: every point held was earned.
    s.dreamEarned = max(s.dreamEarned, s.dreamPoints)
    s.sheep, s.runTotal, s.allTime = N.deserialize(o.sheep), N.deserialize(o.runTotal), N.deserialize(o.allTime)
    if s.buyMode ~= "1" and s.buyMode ~= "10" and s.buyMode ~= "max" then s.buyMode = "1" end
    if s.phase ~= "lucid" then s.phase = "nights" end
    s.stage = max(s.stage, Game.stageOf(s))
    return s
end

return Game
