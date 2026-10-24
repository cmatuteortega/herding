-- The rules: the game's state and everything that changes it. Pure Lua, no
-- LÖVE, so the tests and the balance sim run it under plain luajit
-- (tests/run.lua). The screen reads the state and the events this leaves in
-- Game.events; it never changes the state except through these functions.

local C = require "config"
local N = require "num"
local Lucid = require "lucid.game"
local Astral = require "astral.game"

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
-- Restless nights: challenges, by id too.
local CHALLENGES, CH = {}, {}
for _, c in ipairs(C.challenges) do
    CHALLENGES[#CHALLENGES + 1] = c
    CH[c.id] = c
end
Game.ITEMS, Game.BY_ID, Game.GENS, Game.DREAMS = ITEMS, BY_ID, GENS, DREAMS
Game.CHALLENGES, Game.CH = CHALLENGES, CH

local function freshOwned()
    local o = {}
    for _, it in ipairs(ITEMS) do o[it.id] = 0 end
    return o
end

local function freshMade()
    local o = {}
    for _, g in ipairs(GENS) do o[g.id] = 0 end
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
    s.made = freshMade() -- helpers the chain built this night, in fractions
    s.challenge = nil -- the restless night's id, while under one
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
        version = C.saveVersion,
        dreamPoints = 0, -- to spend in the Dream shop
        dreamEarned = 0, -- ever earned: the production bonus
        dreams = 0,
        dream = freshDream(), -- the Dream shop, owned
        done = {}, -- restless nights slept through: id = true
        lastNight = 0, -- how long the last night lasted, in seconds
        -- "nights" (counting sheep), or "lucid": past the first night
        -- shorter than C.lucid.under, phase 2 (lucid/game.lua), for good;
        -- "astral": past the Gate of Horn, phase 3 (astral/game.lua); or
        -- "beyond": past the cut cord, phase 4 (a placeholder).
        phase = "nights",
        lucid = nil, -- phase 2's state, from the moment you go lucid
        astral = nil, -- phase 3's, from the first time through the gate
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

-- Restless nights: the one you're under, and the ones slept through.
local function under(s, key)
    local c = s.challenge and CH[s.challenge]
    return c and c[key]
end
function Game.done(s, id) return s.done[id] == true end

-- What each Barn and Lullaby adds, after Cold Feet.
function Game.comfortAdd(s, it)
    return it.add * (Game.done(s, "coldFeet") and CH.coldFeet.rewardComforts or 1)
end

-- What each level of a Dream shop multiplier multiplies by, after Wide Awake.
function Game.dreamMult(s, it)
    if it.id == "deepSleep" and Game.done(s, "wideAwake") then return CH.wideAwake.rewardDeep end
    return it.mult
end

function Game.globalMult(s)
    local m = 1
    for _, it in ipairs(ITEMS) do
        if it.kind == "mult" then m = m * (1 + Game.comfortAdd(s, it) * s.owned[it.id]) end
    end
    for _, it in ipairs(DREAMS) do
        if it.mult then m = m * Game.dreamMult(s, it) ^ s.dream[it.id] end
    end
    return m * (1 + C.prestige.bonusPerPoint * s.dreamEarned)
end

-- How many of a helper count: bought, and built by the chain.
function Game.helpers(s, id)
    return s.owned[id] + s.made[id]
end

-- Heavy Sleeper's multiplier on the helpers.
function Game.helperMult(s)
    local it = BY_ID.heavySleeper
    return it.helperMult ^ s.dream.heavySleeper
end

function Game.perSecond(s)
    local r = 0
    for _, g in ipairs(GENS) do r = r + g.rate * Game.helpers(s, g.id) end
    return N.mul(N.from(r * Game.helperMult(s)), Game.globalMult(s))
end

-- Wide Awake: the Dream shop's automation sleeps through the night.
local function autoOn(s) return not under(s, "noAuto") end

-- Sleepwalking's taps a second.
function Game.autoTaps(s)
    if not autoOn(s) then return 0 end
    return BY_ID.sleepwalk.taps * s.dream.sleepwalk
end

-- What the counter grows by a second: the helpers and Sleepwalking.
function Game.totalPerSecond(s)
    return N.add(Game.perSecond(s), N.mul(Game.tapValue(s), N.from(Game.autoTaps(s))))
end

function Game.genRate(s, id)
    return N.mul(N.from(BY_ID[id].rate * Game.helpers(s, id) * Game.helperMult(s)), Game.globalMult(s))
end

-- What the chain builds of the helper before `id`, a second.
function Game.builds(s, id)
    local g = BY_ID[id]
    return (g.builds or 0) * Game.helpers(s, id)
end

-- A tap's worth. `own` is a tap of your own hand, which Light Sleeper pays
-- a share of a second's production on top (Sleepwalking's taps don't get it).
function Game.tapValue(s, own)
    local v = Game.baseTap(s)
    if own and s.dream.lightSleeper > 0 then
        v = N.add(v, N.mul(Game.perSecond(s), N.from(BY_ID.lightSleeper.tapShare * s.dream.lightSleeper)))
    end
    return v
end

function Game.baseTap(s)
    local v = C.tapBase
    for _, it in ipairs(ITEMS) do
        if it.kind == "tap" and it.add then v = v + it.add * s.owned[it.id] end
    end
    for _, it in ipairs(ITEMS) do
        if it.kind == "tap" and it.mult then v = v * it.mult ^ s.owned[it.id] end
    end
    return N.mul(N.from(v), Game.globalMult(s))
end

-- The sheep this night needs to fall asleep.
function Game.target(s)
    local t = C.drowsiness.target * (under(s, "target") or 1)
    if Game.done(s, "insomnia") then t = t * CH.insomnia.rewardTarget end
    return t
end

function Game.drowsiness(s)
    local share = N.toNumber(N.div(s.runTotal, N.from(Game.target(s))))
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

-- The price of a helper or anything else in the night's shop rises by this
-- much a copy: Sheep Shortage raises it for helpers, and lowers it once done.
function Game.growthOf(s, it)
    if it.kind ~= "gen" then return it.growth end
    return under(s, "growth") or (Game.done(s, "shortage") and CH.shortage.rewardGrowth) or it.growth
end

local function dreamCost(it, level) return floor(it.base * it.growth ^ level + 0.5) end

-- The Dream Points spent on the way of sleeping you'd turn over from.
local function refund(s, it)
    if not it.other then return 0 end
    local o = BY_ID[it.other]
    local r = 0
    for k = 0, s.dream[o.id] - 1 do r = r + dreamCost(o, k) end
    return r
end

-- Dream shop items come one at a time, priced in Dream Points. `turn` is
-- what turning over from the other way of sleeping gives back.
local function dreamQuote(s, it)
    if capLeft(s, it) == 0 then return { n = 0, cost = 0, ok = false, maxed = true } end
    local cost = dreamCost(it, s.dream[it.id])
    local turn = refund(s, it)
    return { n = 1, cost = cost, ok = s.dreamPoints + turn >= cost, maxed = false, dp = true,
        turn = turn > 0 or (it.other and s.dream[it.other] > 0) or nil }
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
    local g = Game.growthOf(s, it)
    if mode == "max" then n = min(left, N.maxAffordable(it.base, g, k, N.toNumber(s.sheep)))
    else n = min(left, tonumber(mode)) end
    local some = n > 0
    if not some then n = 1 end
    local cost = N.from(N.sumGeometric(it.base, g, k, n))
    return { n = n, cost = cost, ok = some and N.gte(s.sheep, cost), maxed = false }
end

-- In the shop: generators one at a time (each once the one before is owned),
-- upgrades once the run has counted a share of their price.
function Game.visible(s, id)
    local it = BY_ID[id]
    if it.kind == "dream" then
        if it.opens then return s.dreams >= it.opens end
        return s.dreams > 0 or s.dreamEarned > 0
    end
    if under(s, "noKind") == it.kind then return false end
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
        -- Turning over: the other way of sleeping, given back in points.
        if it.other then
            s.dreamPoints = s.dreamPoints + refund(s, it)
            s.dream[it.other] = 0
        end
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
    if not autoOn(s) then return false end
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
            local n = min(capLeft(s, it), N.maxAffordable(it.base, Game.growthOf(s, it), s.owned[it.id], budget))
            if n > 0 then Game.buy(s, it.id, tostring(n), true) end
        end
    end
end

function Game.tap(s)
    if s.asleep then return N.zero() end
    local v = Game.tapValue(s, true)
    count(s, v)
    s.taps = s.taps + 1
    return v
end

function Game.goldenReward(s)
    return N.max(N.mul(Game.perSecond(s), N.from(C.golden.rewardSeconds)),
        N.mul(Game.tapValue(s), N.from(C.golden.minTaps)))
end

-- Golden sheep: Light Sleeper sees them more often, Heavy Sleeper never.
function Game.goldenOn(s) return s.dream.heavySleeper == 0 end
local function goldenWait(s, d)
    if s.dream.lightSleeper > 0 then return d / BY_ID.lightSleeper.goldenFaster end
    return d
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
        if night and s.phase == "nights" and not s.challenge and s.runTime < C.lucid.under then
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
    -- The chain: each helper that builds makes the one before it.
    for i = #GENS, 2, -1 do
        local g = GENS[i]
        if g.builds then
            local below = GENS[i - 1].id
            s.made[below] = s.made[below] + Game.builds(s, g.id) * dt
        end
    end
    if s.golden and s.dream.goldenDreams > 0 and autoOn(s) and s.golden.t >= C.auto.goldenAfter then Game.catchGolden(s, true) end
    if not Game.goldenOn(s) then s.golden = nil end
    if s.golden then
        s.golden.t = s.golden.t + dt
        if s.golden.t >= C.golden.crossTime then s.golden = nil end
    else
        s.goldenIn = s.goldenIn - (Game.goldenOn(s) and dt or 0)
        if s.goldenIn <= 0 then
            s.golden = { t = 0, lane = rand() }
            s.goldenIn = goldenWait(s, C.golden.minDelay + rand() * (C.golden.maxDelay - C.golden.minDelay))
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

-- Fall asleep for real: Dream Points banked, and a new night. A restless
-- night slept through is done for good; the second value is its id.
function Game.dreamAgain(s)
    local gained = Game.dreamPointsFor(s)
    local won = s.asleep and s.challenge or nil
    if won then s.done[won] = true end
    s.dreamPoints = s.dreamPoints + gained
    s.dreamEarned = s.dreamEarned + gained
    s.dreams = s.dreams + 1
    -- Warm Bed: a share of every helper stays for the new night.
    local keep = {}
    for _, g in ipairs(GENS) do keep[g.id] = floor(s.owned[g.id] * BY_ID.warmBed.keep * s.dream.warmBed) end
    freshRun(s)
    for id, n in pairs(keep) do s.owned[id] = n end
    return gained, won
end

-- Restless nights open one a night, and each can be slept through once.
function Game.challengeOpen(s, id)
    return s.phase == "nights" and s.dreams >= CH[id].opens
end

-- Start a restless night: the night you're in ends, nothing kept, no points.
function Game.startChallenge(s, id)
    if not Game.challengeOpen(s, id) or Game.done(s, id) or s.challenge == id or s.asleep then return false end
    freshRun(s)
    s.challenge = id
    emit({ type = "challenge", id = id })
    return true
end

-- Give up a restless night: a plain night again, from nothing.
function Game.giveUp(s)
    if not s.challenge or s.asleep then return false end
    freshRun(s)
    return true
end

-- After a lucid night: its Dream Points banked, and on to phase 2 for good.
-- The points come along to spend; every point ever earned is its legacy.
-- Phase 1's state stays in the save as it was, and plays no more.
function Game.goLucid(s)
    local gained = Game.dreamAgain(s)
    s.phase = "lucid"
    s.lucid = Lucid.fresh(s)
    s.dreamPoints = 0
    return gained
end

-- Through the Gate of Horn: out of the dream, into astral projection (phase
-- 3). The lucid state stays in the save as it was, and waits: the gate stays
-- open both ways. The first time through, phase 3's state starts; every
-- time, the Akashic Library reads the records again.
function Game.goAstral(s)
    if s.phase ~= "lucid" or not (s.lucid and s.lucid.gate) then return false end
    s.phase = "astral"
    s.astral = s.astral or Astral.fresh(s)
    Astral.readRecords(s.astral, s)
    return true
end

-- Back through the gate from astral projection: the dream again, as it was.
function Game.backToDream(s)
    if s.phase ~= "astral" then return false end
    s.phase = "lucid"
    return true
end

-- The cord cut: on to phase 4, beyond.
function Game.goBeyond(s)
    if s.phase ~= "astral" or not (s.astral and s.astral.cut) then return false end
    s.phase = "beyond"
    return true
end

-- Back from beyond (phase 4 is a placeholder): the stars again, the cord
-- whole, as if it had never been cut.
function Game.backToStars(s)
    if s.phase ~= "beyond" then return false end
    s.phase = "astral"
    s.astral.cut = false
    return true
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
    o.lucid = s.lucid and Lucid.serialize(s.lucid) or nil
    o.astral = s.astral and Astral.serialize(s.astral) or nil
    o.version = C.saveVersion
    o.lastSeen = os.time()
    return o
end

-- What each save version needs to become the next, in order. A save without a
-- version is 1.
local MIGRATE = {
    -- 1 -> 2: phase 2 arrives. A save that went lucid in the placeholder gets
    -- its lucid state now, from its points; one still counting is untouched.
    [1] = function(o)
        if o.phase == "lucid" and type(o.lucid) ~= "table" then o.lucid = { fromV1 = true } end
        o.version = 2
    end,
    -- 2 -> 3: the roots, the bouncing sheep and the void. Nothing to move:
    -- they all start fresh in the lucid block.
    [2] = function(o) o.version = 3 end,
    -- 3 -> 4: the void placeholder becomes astral projection, from fresh.
    [3] = function(o)
        if o.phase == "void" then o.phase = "astral" end
        o.version = 4
    end,
}
Game.MIGRATE = MIGRATE

function Game.deserialize(o)
    if type(o) ~= "table" then return nil end
    local v = tonumber(o.version) or 1
    while MIGRATE[v] and v < C.saveVersion do
        MIGRATE[v](o)
        v = v + 1
    end
    local s = Game.fresh()
    for k, v in pairs(s) do
        if k ~= "owned" and k ~= "dream" and k ~= "made" and k ~= "done" and k ~= "version" and o[k] ~= nil and type(o[k]) == type(v) then s[k] = o[k] end
    end
    if type(o.golden) == "table" and tonumber(o.golden.t) then s.golden = { t = o.golden.t, lane = tonumber(o.golden.lane) or 0.5 } end
    if type(o.owned) == "table" then
        for id in pairs(s.owned) do s.owned[id] = max(0, floor(tonumber(o.owned[id]) or 0)) end
    end
    if type(o.made) == "table" then
        for id in pairs(s.made) do s.made[id] = max(0, tonumber(o.made[id]) or 0) end
    end
    if type(o.done) == "table" then
        for id in pairs(CH) do if o.done[id] == true then s.done[id] = true end end
    end
    if type(o.challenge) == "string" and CH[o.challenge] then s.challenge = o.challenge end
    if type(o.dream) == "table" then
        for _, it in ipairs(DREAMS) do
            s.dream[it.id] = clamp(floor(tonumber(o.dream[it.id]) or 0), 0, it.max or math.huge)
        end
    end
    -- Saves from before the Dream shop: every point held was earned.
    s.dreamEarned = max(s.dreamEarned, s.dreamPoints)
    s.sheep, s.runTotal, s.allTime = N.deserialize(o.sheep), N.deserialize(o.runTotal), N.deserialize(o.allTime)
    if s.buyMode ~= "1" and s.buyMode ~= "10" and s.buyMode ~= "max" then s.buyMode = "1" end
    local later = s.phase == "astral" or s.phase == "beyond"
    if s.phase ~= "lucid" and not later then s.phase = "nights" end
    if later and type(o.lucid) ~= "table" then s.phase, later = "nights", false end
    if s.phase == "lucid" or later then
        -- From the placeholder (v1): the points held come along, the same as going lucid.
        if type(o.lucid) == "table" and o.lucid.fromV1 then
            s.lucid = Lucid.fresh(s)
            s.dreamPoints = 0
        else
            s.lucid = Lucid.deserialize(o.lucid, s)
        end
    end
    -- Phase 3's state, from the first time through the gate (or the
    -- placeholder's save, coming in now).
    if type(o.astral) == "table" or later then
        s.astral = Astral.deserialize(o.astral, s)
    end
    if s.phase == "beyond" and not s.astral.cut then s.phase = "astral" end
    s.stage = max(s.stage, Game.stageOf(s))
    return s
end

return Game
