-- The rules of phase 3, astral projection. Pure Lua, no LÖVE, like game.lua
-- and lucid/game.lua.
--
-- The dreamer's sheep has left the body, tied to it by the silver cord. A
-- projection: out, the distance grows the faster the further it is, and so
-- does the Ether a second (times the plane it's in). The cord strains as it
-- goes, (distance / cord)^2, and now and then the body tugs at it. Come back
-- and the Ether gathered is banked, more for a close call; at a strain of 1
-- the cord snaps you back with half. Then a rest in the body, and out again.
-- The Silver Thread comes back by itself at a strain you set, the Trance goes
-- out again: the cord runs itself, as the night did in phase 2.
--
-- Ether buys upgrades kept for good, the dreamers (other sleepers found out
-- along the cord, each dreaming Ether a second into what it gathers while
-- you're out), and lights the
-- constellations a star at a time, each a reward for good. The Akashic
-- Library is every record of every phase, a multiplier on all Ether. Now
-- and then a comet crosses (the guide's gift: one of three). Light the
-- Sleeper, at the Edge, and the cord can be cut: the end of the phase.
--
-- Every amount of Ether is a Num and goes through num.lua; the distance, the
-- cord and the strain stay plain numbers (the cord is at most about 1E10).
-- The state is `s.astral`; phase 1's and phase 2's stay as they were.

local C = require "config"
local N = require "num"

local A = C.astral
local floor, min, max, log10 = math.floor, math.min, math.max, math.log10

local Astral = {}

-- The upgrades, by id and in order, and their sections.
local UPS, UP = {}, {}
for i, u in ipairs(A.ups) do
    local it = { index = i, growth = 1, max = 1 }
    for k, v in pairs(u) do it[k] = v end
    UPS[i], UP[it.id] = it, it
end
Astral.UPS, Astral.UP, Astral.SECTIONS = UPS, UP, A.sections

-- The dreamers and the constellations, by id too.
local DREAMERS, DR = A.dreamers, {}
for k, d in ipairs(DREAMERS) do DR[d.id] = k end
Astral.DREAMERS = DREAMERS
local STARS, CON = A.constellations, {}
for k, c in ipairs(STARS) do CON[c.id] = k end
Astral.CONSTELLATIONS, Astral.CON = STARS, CON
Astral.PLANES = A.planes

-- What happened, for the screen and the sound: { type = ..., ... }.
Astral.events = {}
local function emit(e) Astral.events[#Astral.events + 1] = e end

local function rank(P, id) return P.ups[id] or 0 end
Astral.rank = rank

-- What the Akashic Library reads: the records of the phases before, from
-- phase 1's state (and its `lucid`). Read again on every way in, so a
-- dream played on since counts.
function Astral.readRecords(P, s)
    local L = s and s.lucid
    local n = 0
    if L and L.done then for _ in pairs(L.done) do n = n + 1 end end
    P.rec = {
        sheep = s and N.toNumber(s.allTime) or 0,
        nights = s and s.dreams or 0,
        dream = L and N.toNumber(L.sheepTotal) or 0,
        runs = L and N.toNumber(L.runs) or 0,
        height = L and L.best or 0,
        lucidity = n,
    }
end

function Astral.fresh(s)
    local P = {
        ether = N.zero(), etherEarned = N.zero(),
        out = false, -- projecting
        dist = 0, -- how far out, now
        gathered = N.zero(), -- the Ether gathered this projection, not banked yet
        outFor = 0, -- seconds out, this projection
        tug = 0, tugLeft = 0, -- the strain a tug adds, and what's still to come of it
        tugIn = A.tugMin,
        rest = 0, -- seconds before the cord can go out again
        reach = 0, -- the farthest ever
        projections = 0, snaps = 0,
        best = N.zero(), -- the most banked at once
        cycleRate = 0, -- Ether a second the cord made, the last few projections (for away and the comet)
        ups = {}, -- id = ranks
        autoAt = A.autoAt, autoOff = false, -- the Silver Thread's strain, and the Trance paused
        dreamers = {}, -- k = how many
        lit = {}, -- constellation id = stars lit
        sky = nil, -- the constellation shown in the sky, by id (nil: the next to light)
        comet = nil, cometIn = A.comet.firstDelay, choosing = false,
        effects = {}, -- id = seconds left: slack, wind
        cut = false, -- the cord cut: the end of the phase
        paid = false, -- the cut paid for (back from beyond, it's free again)
        intro = true,
        time = 0,
        found = {}, -- dreamer id = true, once found (for the banner, once)
        planeSeen = 1, -- the deepest plane reached, for the banner
        rec = nil,
    }
    for k = 1, #DREAMERS do P.dreamers[k] = 0 end
    Astral.readRecords(P, s)
    return P
end

--- constellations ---------------------------------------------------------------

local function lit(P, id) return P.lit[id] or 0 end
Astral.lit = lit

function Astral.done(P, id)
    local c = STARS[CON[id]]
    return lit(P, id) >= #c.stars
end

-- Every constellation lit's reward `key` multiplied together (or the
-- default where none sets it).
local function reward(P, key, default)
    local v = default or 1
    for _, c in ipairs(STARS) do
        if c[key] and lit(P, c.id) >= #c.stars then v = v * c[key] end
    end
    return v
end
Astral.reward = reward

-- A constellation can be lit once your reach is into its plane and the one
-- before it is lit.
function Astral.conOpen(P, id)
    local k = CON[id]
    local c = STARS[k]
    if P.reach < A.planes[c.plane].at then return false end
    return k == 1 or Astral.done(P, STARS[k - 1].id)
end

-- The next star's price, or nil once it's lit.
function Astral.starPrice(P, id)
    local c = STARS[CON[id]]
    local i = lit(P, id)
    if i >= #c.stars then return nil end
    return N.from(c.star * A.starGrowth ^ i)
end

function Astral.canLight(P, id)
    local p = Astral.starPrice(P, id)
    return p ~= nil and Astral.conOpen(P, id) and N.gte(P.ether, p)
end

-- Light the next star of `id`.
function Astral.light(P, id)
    if not Astral.canLight(P, id) then return false end
    P.ether = N.sub(P.ether, Astral.starPrice(P, id))
    P.lit[id] = lit(P, id) + 1
    local c = STARS[CON[id]]
    local whole = P.lit[id] >= #c.stars
    emit({ type = "star", id = id, i = P.lit[id], whole = whole })
    if whole then
        emit({ type = "constellation", id = id })
        if P.sky == id then P.sky = nil end
    end
    return true
end

-- The constellation in the sky: the one picked, or the first not lit yet
-- (the last, once every one is).
function Astral.skyCon(P)
    if P.sky and CON[P.sky] then return P.sky end
    for _, c in ipairs(STARS) do if not Astral.done(P, c.id) then return c.id end end
    return STARS[#STARS].id
end

function Astral.litCount(P)
    local n = 0
    for _, c in ipairs(STARS) do if Astral.done(P, c.id) then n = n + 1 end end
    return n, #STARS
end

--- what everything comes to ------------------------------------------------------

local function effect(P, id) return P.effects[id] and P.effects[id] > 0 end

-- The Akashic Library's multiplier, and the decades it reads (for the screen).
function Astral.decades(P)
    local r = P.rec or {}
    local function d(v) return log10(1 + max(0, v or 0)) end
    return {
        { "SHEEP COUNTED", d(r.sheep), r.sheep or 0 },
        { "NIGHTS DREAMT", (r.nights or 0) / 5, r.nights or 0 },
        { "DREAM SHEEP", d(r.dream), r.dream or 0 },
        { "RUNS", 2 * d(r.runs), r.runs or 0 },
        { "LUCIDITY", r.lucidity or 0, r.lucidity or 0 },
        { "BEST HEIGHT", (r.height or 0) / 100, r.height or 0 },
        { "ETHER", 2 * d(N.toNumber(P.etherEarned)), N.toNumber(P.etherEarned) },
    }
end
function Astral.akashic(P)
    local sum = 0
    for _, row in ipairs(Astral.decades(P)) do sum = sum + row[2] end
    local per = A.akashic.per * (1 + UP.librarian.akashicAdd * rank(P, "librarian")) * reward(P, "akashicMult")
    return 1 + per * sum
end

-- Every multiplier on all Ether: the library, the Ether Lens, Aries.
function Astral.mult(P)
    return Astral.akashic(P) * (1 + UP.lens.etherAdd * rank(P, "lens")) * reward(P, "etherMult")
end

function Astral.cord(P)
    local m = UP.cord.cordMult ^ rank(P, "cord") * reward(P, "cordMult")
    if effect(P, "slack") then m = m * A.comet.slack.mult end
    return A.cord * m
end

function Astral.speed(P)
    local v = A.speed * (1 + UP.drift.speedAdd * rank(P, "drift")) * reward(P, "speedMult")
    if effect(P, "wind") then v = v * A.comet.wind.mult end
    return v
end

-- The plane at a distance: its index.
function Astral.planeAt(d)
    local k = 1
    for i, p in ipairs(A.planes) do if d >= p.at then k = i end end
    return k
end
function Astral.plane(P) return Astral.planeAt(P.dist) end

-- The strain on the cord: (distance / cord)^2 and any tug. 1 snaps it.
function Astral.strain(P)
    if not P.out then return 0 end
    return (P.dist / Astral.cord(P)) ^ 2 + P.tug
end

-- Ether a second while out, here.
function Astral.etherRate(P)
    if not P.out then return N.zero() end
    local plane = A.planes[Astral.plane(P)]
    return N.from(A.etherBase * (1 + P.dist) ^ A.etherPower * plane.mult * Astral.mult(P))
end

-- What a close call is worth: banked x(1 + this * strain^3).
function Astral.closeCall(P)
    return A.closeCall * (1 + UP.close.closeAdd * rank(P, "close")) * reward(P, "closeMult")
end

-- What coming back now would bank.
function Astral.bankValue(P)
    local s = min(1, Astral.strain(P))
    return N.mul(P.gathered, N.from(1 + Astral.closeCall(P) * s ^ 3))
end

function Astral.restTime(P)
    return A.rest * UP.light.restCut ^ rank(P, "light") * reward(P, "restMult")
end

--- the dreamers ---------------------------------------------------------------------

function Astral.found(P, k) return P.reach >= DREAMERS[k].at end

-- Every dreamer's multiplier: your reach, Far Sight, the Golden Fleece.
function Astral.dreamerMult(P)
    local per = A.reachPer * (1 + UP.farsight.reachAdd * rank(P, "farsight"))
    return (1 + per * log10(1 + P.reach)) * reward(P, "dreamerMult") * Astral.mult(P)
end

-- What one dreamer of kind k dreams a second.
function Astral.dreamerRate(P, k)
    local d = DREAMERS[k]
    return N.from(d.rate * 2 ^ floor(P.dreamers[k] / A.dreamerEvery) * Astral.dreamerMult(P))
end

-- Ether a second, from every dreamer.
function Astral.dreamRate(P)
    local v = N.zero()
    for k = 1, #DREAMERS do
        if P.dreamers[k] > 0 then v = N.add(v, N.mul(N.from(P.dreamers[k]), Astral.dreamerRate(P, k))) end
    end
    return v
end

function Astral.dreamerCost(P, k, n)
    local d = DREAMERS[k]
    return N.from(N.geoCost(d.base, d.growth, P.dreamers[k], n or 1))
end

-- Buy n dreamers of kind k (or "max"). Returns how many.
function Astral.buyDreamer(P, k, n)
    if not Astral.found(P, k) then return 0 end
    local d = DREAMERS[k]
    local can = N.geoMax(d.base, d.growth, P.dreamers[k], P.ether)
    n = n == "max" and can or min(n or 1, can)
    if n <= 0 then return 0 end
    P.ether = N.sub(P.ether, Astral.dreamerCost(P, k, n))
    P.dreamers[k] = P.dreamers[k] + n
    emit({ type = "dreamer", k = k, n = n, first = P.dreamers[k] == n })
    return n
end

-- Ether gathered a second while out: the distance's and the dreamers'.
-- The dreamers dream only while you're out there with them, into what the
-- cord brings back: a close call pays on it, and a snap loses it.
function Astral.gatherRate(P)
    if not P.out then return N.zero() end
    return N.add(Astral.etherRate(P), Astral.dreamRate(P))
end

-- What's coming in, a second, for the comet's Ether: the cord as it's been
-- running (at least the dreamers').
function Astral.income(P)
    return N.max(Astral.dreamRate(P), N.from(P.cycleRate))
end

--- the upgrades ---------------------------------------------------------------------

function Astral.upPrice(P, id)
    local u = UP[id]
    return N.from(u.ether * u.growth ^ rank(P, id))
end

-- "full", "open" (it can grow now), "poor" (not the Ether), "shut" (the one
-- before it hasn't a rank).
function Astral.upState(P, id)
    local u = UP[id]
    if rank(P, id) >= u.max then return "full" end
    if u.at and rank(P, u.at) == 0 then return "shut" end
    return N.gte(P.ether, Astral.upPrice(P, id)) and "open" or "poor"
end

function Astral.grow(P, id)
    if not UP[id] or Astral.upState(P, id) ~= "open" then return false end
    P.ether = N.sub(P.ether, Astral.upPrice(P, id))
    P.ups[id] = rank(P, id) + 1
    emit({ type = "grew", id = id, rank = P.ups[id] })
    return true
end

function Astral.upsGrown(P)
    local all, grown = 0, 0
    for _, u in ipairs(UPS) do all, grown = all + u.max, grown + rank(P, u.id) end
    return grown, all
end

-- The Silver Thread's strain: up or down a step.
function Astral.setAuto(P, v)
    P.autoAt = max(A.autoMin, min(A.autoMax, floor(v / A.autoStep + 0.5) * A.autoStep))
end
function Astral.threaded(P) return rank(P, "thread") > 0 end
function Astral.tranced(P) return rank(P, "trance") > 0 and not P.autoOff end

--- the cord ---------------------------------------------------------------------------

local function bank(P, value)
    P.ether, P.etherEarned = N.add(P.ether, value), N.add(P.etherEarned, value)
end

-- Out of the body.
function Astral.project(P)
    if P.out or P.rest > 0 or P.cut then return false end
    P.out, P.dist, P.gathered, P.outFor = true, 0, N.zero(), 0
    P.tug, P.tugLeft = 0, 0
    P.tugIn = A.tugMin
    P.projections = P.projections + 1
    emit({ type = "project" })
    return true
end

local function back(P, value, snapped)
    local secs = P.outFor + (snapped and A.snapRest or Astral.restTime(P))
    local rate = N.toNumber(value) / max(1, secs)
    P.cycleRate = P.cycleRate == 0 and rate or P.cycleRate * 0.7 + rate * 0.3
    if N.gt(value, P.best) then P.best = value end
    P.out, P.dist, P.gathered, P.tug, P.tugLeft = false, 0, N.zero(), 0, 0
end

-- Back in the body: the Ether gathered banked, the close call paid.
function Astral.reelIn(P, auto)
    if not P.out then return nil end
    local strain = Astral.strain(P)
    local v = Astral.bankValue(P)
    bank(P, v)
    local secs = P.outFor
    back(P, v, false)
    P.rest = Astral.restTime(P)
    emit({ type = "bank", value = v, strain = strain, auto = auto, secs = secs })
    return v
end

-- A breath: a tap on the dark, out, calms a tug.
function Astral.breathe(P)
    if not P.out or (P.tug <= 0 and P.tugLeft <= 0) then return false end
    local cut = min(0.9, A.steady + UP.breath.steadyAdd * rank(P, "breath"))
    P.tug, P.tugLeft = P.tug * (1 - cut), P.tugLeft * (1 - cut)
    emit({ type = "breath" })
    return true
end

local function snap(P)
    local keep = 1 - A.snapLoss
    keep = math.max(keep, reward(P, "snapKeep", 0))
    local v = N.mul(P.gathered, N.from(keep))
    bank(P, v)
    back(P, v, true)
    P.snaps = P.snaps + 1
    P.rest = A.snapRest * reward(P, "restMult")
    emit({ type = "snap", value = v, kept = keep })
end

local function tugWait(P, rand)
    return (A.tugMin + rand() * (A.tugMax - A.tugMin)) * reward(P, "tugEvery")
end

local function cord(P, dt, rand)
    if not P.out then
        if P.rest > 0 then
            P.rest = max(0, P.rest - dt)
            if P.rest == 0 then emit({ type = "rested" }) end
        end
        if P.rest <= 0 and Astral.tranced(P) and not P.intro and not P.choosing then Astral.project(P) end
        return
    end
    P.outFor = P.outFor + dt
    local before = Astral.plane(P)
    P.dist = P.dist + Astral.speed(P) * (P.dist + A.speedFrom) * dt
    P.gathered = N.add(P.gathered, N.mul(Astral.gatherRate(P), N.from(dt)))
    if P.dist > P.reach then
        local was = P.reach
        P.reach = P.dist
        for k, d in ipairs(DREAMERS) do
            if was < d.at and P.reach >= d.at and not P.found[d.id] then
                P.found[d.id] = true
                emit({ type = "found", k = k })
            end
        end
    end
    local now = Astral.plane(P)
    if now ~= before then
        emit({ type = "plane", k = now, first = now > P.planeSeen })
        P.planeSeen = max(P.planeSeen, now)
    end
    -- Tugs: half at once, half over tugRise seconds, draining.
    P.tugIn = P.tugIn - dt
    if P.tugIn <= 0 then
        local amp = (A.tugLow + rand() * (A.tugHigh - A.tugLow)) * UP.calm.calmCut ^ rank(P, "calm") * reward(P, "tugSoft")
        P.tug = P.tug + amp / 2
        P.tugLeft = P.tugLeft + amp / 2
        P.tugIn = tugWait(P, rand)
        emit({ type = "tug", amp = amp })
    end
    if P.tugLeft > 0 then
        local add = min(P.tugLeft, dt * (A.tugHigh / 2) / A.tugRise)
        P.tug, P.tugLeft = P.tug + add, P.tugLeft - add
    end
    P.tug = max(0, P.tug - A.tugDrain * dt)
    local strain = Astral.strain(P)
    if strain >= 1 then
        snap(P)
    elseif Astral.threaded(P) and strain >= P.autoAt then
        Astral.reelIn(P, true)
    end
end

--- the comet ---------------------------------------------------------------------------

function Astral.catchComet(P)
    if not P.comet or P.choosing then return false end
    P.comet, P.choosing = nil, true
    emit({ type = "cometCaught" })
    return true
end

-- What the comet's Ether would be.
function Astral.cometEther(P)
    local E = A.comet.ether
    return N.max(N.mul(Astral.income(P), N.from(E.seconds)), N.from(E.least))
end

-- One of three: "ether", "slack" or "wind".
function Astral.choose(P, id)
    if not P.choosing then return nil end
    P.choosing = false
    if id == "ether" then
        local v = Astral.cometEther(P)
        bank(P, v)
        emit({ type = "gift", id = id, value = v })
        return v
    end
    P.effects[id] = A.comet[id].seconds
    emit({ type = "gift", id = id })
    return true
end

--- the end -------------------------------------------------------------------------

-- The Sleeper lit: the cord can be cut, for Ether.
function Astral.canCut(P)
    local last = STARS[#STARS]
    return not P.cut and Astral.done(P, last.id) and (P.paid or N.gte(P.ether, N.from(A.cut)))
end

function Astral.cutCord(P)
    if not Astral.canCut(P) then return false end
    if P.out then Astral.reelIn(P) end
    if not P.paid then P.ether = N.sub(P.ether, N.from(A.cut)) end
    P.cut, P.paid = true, true
    emit({ type = "cut" })
    return true
end

--- each step ------------------------------------------------------------------------

function Astral.step(P, dt, rand)
    rand = rand or math.random
    P.time = P.time + dt
    cord(P, dt, rand)
    for id, left in pairs(P.effects) do
        P.effects[id] = left - dt
        if P.effects[id] <= 0 then P.effects[id] = nil; emit({ type = "giftOver", id = id }) end
    end
    if P.comet then
        P.comet.t = P.comet.t + dt
        if P.comet.t >= A.comet.crossTime then P.comet = nil end
    elseif not P.choosing and not P.intro then
        P.cometIn = P.cometIn - dt
        if P.cometIn <= 0 then
            local K = A.comet
            P.comet = { t = 0, lane = rand() }
            P.cometIn = K.minDelay + rand() * (K.maxDelay - K.minDelay)
            emit({ type = "comet" })
        end
    end
end

--- away ---------------------------------------------------------------------------------

-- Away `seconds`: with the Thread and the Trance, the cord runs on at
-- `awayShare` of the rate it was running at (the dreamers' Ether is in it).
-- Without them, the cord waits in the body. A projection under way is banked
-- as if come back.
function Astral.offline(P, seconds)
    if seconds <= 0 then return nil end
    local T = min(seconds, C.offline.maxHours * 3600)
    local before = P.ether
    if P.out then Astral.reelIn(P) end
    Astral.events = {}
    local v = N.zero()
    if Astral.threaded(P) and Astral.tranced(P) then v = N.from(P.cycleRate * T * A.awayShare) end
    bank(P, v)
    P.rest = 0
    P.time = P.time + T
    return { secs = T, capped = seconds > T, ether = N.sub(P.ether, before) }
end

--- saves ---------------------------------------------------------------------------------

local NUMS = { "ether", "etherEarned", "gathered", "best" }

function Astral.serialize(P)
    local o = {}
    for k, v in pairs(P) do o[k] = v end
    for _, k in ipairs(NUMS) do o[k] = N.serialize(P[k]) end
    o.comet, o.choosing = nil, nil -- a comet passes while you're away
    o.ups, o.lit, o.found, o.dreamers = {}, {}, {}, {}
    for id, n in pairs(P.ups) do o.ups[id] = n end
    for id, n in pairs(P.lit) do o.lit[id] = n end
    for id in pairs(P.found) do o.found[id] = true end
    for k, n in ipairs(P.dreamers) do o.dreamers[k] = n end
    return o
end

-- Back from a save; missing or odd fields come back fresh. The records are
-- read again from `s`.
function Astral.deserialize(o, s)
    local P = Astral.fresh(s)
    if type(o) ~= "table" then return P end
    for _, k in ipairs(NUMS) do if o[k] ~= nil then P[k] = N.deserialize(o[k]) end end
    for _, k in ipairs({ "dist", "outFor", "tug", "tugLeft", "tugIn", "rest", "reach", "projections", "snaps",
        "cycleRate", "autoAt", "cometIn", "time", "planeSeen" }) do
        if type(o[k]) == "number" then P[k] = o[k] end
    end
    for _, k in ipairs({ "out", "autoOff", "cut", "paid", "intro" }) do if type(o[k]) == "boolean" then P[k] = o[k] end end
    if type(o.ups) == "table" then
        for id, n in pairs(o.ups) do
            local u = UP[id]
            if u and tonumber(n) then P.ups[id] = max(0, min(u.max, floor(tonumber(n)))) end
        end
    end
    if type(o.lit) == "table" then
        for id, n in pairs(o.lit) do
            local k = CON[id]
            if k and tonumber(n) then P.lit[id] = max(0, min(#STARS[k].stars, floor(tonumber(n)))) end
        end
    end
    if type(o.found) == "table" then
        for id in pairs(o.found) do if DR[id] then P.found[id] = true end end
    end
    if type(o.dreamers) == "table" then
        for k = 1, #DREAMERS do P.dreamers[k] = max(0, floor(tonumber(o.dreamers[k]) or 0)) end
    end
    if type(o.sky) == "string" and CON[o.sky] then P.sky = o.sky end
    if type(o.effects) == "table" then
        for id, left in pairs(o.effects) do
            if (id == "slack" or id == "wind") and type(left) == "number" then P.effects[id] = left end
        end
    end
    Astral.setAuto(P, P.autoAt)
    P.planeSeen = max(1, min(#A.planes, floor(P.planeSeen)))
    return P
end

return Astral
