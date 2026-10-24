-- The rules of phase 2, lucid dreaming. Pure Lua, no LÖVE, like game.lua.
--
-- The night runs itself now (auto-wake): six dream layers, a dream within a
-- dream, count dream sheep, a run is over every `sheepPerRun` of them (no
-- faster than the run cap), and each run pays Dream Points. Runs are settled
-- in batches, never one reset a frame: a step adds runs a second * dt to a
-- fraction and pays for the whole runs in it. Dream Points rebuild phase 1's
-- farm, a grid where a building does more beside its own district and beside
-- a Haystack, and buy the upgrades kept for good (in the code still the
-- "roots"), a section for each of the dream's games, the dream challenges
-- after them and the Gate of Horn last; dream sheep buy sleepers for the
-- layers and the town's materials. A golden sheep offers a choice of three,
-- now and then a nightmare scatters a flock for the dog to herd
-- (nightmare.lua), a flock waits at the fence to be counted on the beat
-- (count.lua), and the bouncing sheep climbs when you hold the field
-- (bounce.lua).
--
-- In the code a layer is still a "dim": `L.dims[k]` is layer k, its
-- sleepers bought and its amount.
--
-- Every amount (sheep, points, layers, runs) is a Num and goes through
-- num.lua; counts of things bought and the multipliers stay plain numbers.
-- The state is `s.lucid`; game.lua's phase-1 fields stay as they were.

local C = require "config"
local N = require "num"
local Nightmare = require "lucid.nightmare"
local Bounce = require "lucid.bounce"
local Count = require "lucid.count"

local D = C.dream
local floor, min, max = math.floor, math.min, math.max

local Lucid = {}

-- The buildings, by id and in order.
local BUILD, BY = {}, {}
for i, b in ipairs(D.buildings) do
    local it = { index = i, growth = 1 }
    for k, v in pairs(b) do it[k] = v end
    BUILD[i], BY[it.id] = it, it
end
Lucid.BUILD, Lucid.BY = BUILD, BY

-- The upgrades (the roots), by id and in order, and their sections.
local ROOTS, ROOT = {}, {}
for i, r in ipairs(D.roots) do
    local it = { index = i, growth = 1, max = 1, kind = "up" }
    for k, v in pairs(r) do it[k] = v end
    ROOTS[i], ROOT[it.id] = it, it
end
Lucid.ROOTS, Lucid.ROOT = ROOTS, ROOT
Lucid.SECTIONS = D.sections

-- Dream challenges, by id too.
local CH = {}
for _, c in ipairs(D.challenges) do CH[c.id] = c end
Lucid.CHALLENGES, Lucid.CH = D.challenges, CH

-- What happened, for the screen and the sound: { type = ..., ... }.
Lucid.events = {}
local function emit(e) Lucid.events[#Lucid.events + 1] = e end

local GW, GH = D.grid.w, D.grid.h
local function cell(x, y) return (y - 1) * GW + x end
Lucid.cell = cell

-- The phase-2 state, started from phase 1's: the points you bring (spendable)
-- and the legacy of every point ever earned there.
function Lucid.fresh(s1)
    local L = {
        sheep = N.zero(), sheepTotal = N.zero(),
        dp = N.from(s1 and s1.dreamPoints or 0), dpEarned = N.zero(),
        runs = N.zero(), runAcc = 0,
        legacy = 1 + math.log10(1 + (s1 and s1.dreamEarned or 0)) * D.legacyPerDecade,
        dims = {},
        open = {}, -- land: cell = true
        plots = 0, -- land bought
        grid = {}, -- cell = building id
        level = {}, -- cell = its level (1 when built)
        built = {}, -- id = how many, every level counted
        autoOff = {}, -- layer index = true when its auto-buyer is paused
        time = 0, autoIn = 0,
        golden = nil, goldenIn = D.golden.firstDelay,
        effects = {}, -- id = seconds left: frenzy, warp
        choosing = false, -- a golden sheep caught, its three gifts on offer
        nightmare = nil, nightmareIn = D.nightmare.firstDelay,
        flow = false, -- runs too quick to see: the flow
        intro = true, -- the entrance still to show
        challenge = nil, -- the dream challenge under way
        done = {}, -- dream challenges met: id = true
        herded = 0, -- flocks brought home under Nightmare Season
        counted = N.zero(), -- dream sheep counted under the challenge
        climbed = 0, -- the highest climb under the challenge
        roots = {}, -- id = ranks grown
        gate = false, -- the Gate of Horn grown: the way out is open
        best = 0, -- the highest the bouncing sheep has climbed, ever
        bounce = Bounce.new(), -- not kept: a climb passes
        flock = nil, flockIn = D.count.firstDelay, -- a flock waiting at the fence: { t }
        song = nil, -- counting it: count.lua's song, not kept
        tuneMult = 1, -- what the last song's tune does to the run cap, while effects.tune lasts
    }
    for k = 1, #D.dims do
        L.dims[k] = { amount = N.from(D.startDims[k] or 0), bought = D.startDims[k] or 0 }
    end
    local o = floor((GW - D.grid.start) / 2)
    for y = 1, D.grid.start do
        for x = 1, D.grid.start do L.open[cell(o + x, o + y)] = true end
    end
    for _, b in ipairs(BUILD) do L.built[b.id] = 0 end
    return L
end

-- The dream challenge under way's rule, and the ones met.
local function under(L, key)
    local c = L.challenge and CH[L.challenge]
    return c and c[key]
end
function Lucid.met(L, id) return L.done[id] == true end

-- Ranks grown of a root.
local function rank(L, id) return L.roots[id] or 0 end
Lucid.rank = rank

--- the town ------------------------------------------------------------------------

-- Each building's effect, after its neighbours: its level alone, more beside
-- its own district and beside a Haystack (a Haystack does nothing on its own).
function Lucid.strength(L, c)
    local id = L.grid[c]
    if not id then return 0 end
    local b = BY[id]
    local x, y = (c - 1) % GW + 1, floor((c - 1) / GW) + 1
    local v = 1
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local nx, ny = x + d[1], y + d[2]
        if nx >= 1 and nx <= GW and ny >= 1 and ny <= GH and not under(L, "noNeighbours") then
            local o = L.grid[cell(nx, ny)]
            if o == "plaza" then v = v + D.adjacency.plaza end
            if o and o ~= "plaza" and BY[o].district == b.district then
                v = v + D.adjacency.sameDistrict * (Lucid.met(L, "emptySquares") and CH.emptySquares.rewardSame or 1)
            end
        end
    end
    return v * (L.level[c] or 1)
end

-- The sum of every building of `id`'s strength.
function Lucid.sum(L, id)
    local v = 0
    for c, b in pairs(L.grid) do if b == id then v = v + Lucid.strength(L, c) end end
    return v
end

-- What a building costs: { dp, sheep } as Num, both times growth^built.
function Lucid.price(L, id)
    local b = BY[id]
    local g = N.pow(N.from(b.growth), L.built[id])
    local wool = ROOT.market.woolCut ^ rank(L, "market")
    return { dp = N.mul(N.from(b.dp or 0), g), sheep = N.mul(N.from((b.sheep or 0) * wool), g) }
end

function Lucid.canBuild(L, id)
    local b = BY[id]
    if b.locked or (b.max and L.built[id] >= b.max) then return false end
    if (b.after and not Lucid.met(L, b.after)) or (b.gate and L.gate) then return false end
    local p = Lucid.price(L, id)
    return N.gte(L.dp, p.dp) and N.gte(L.sheep, p.sheep)
end

-- Build `id` on the open, empty cell `c`.
function Lucid.build(L, id, c)
    if BY[id].gate or not L.open[c] or L.grid[c] or not Lucid.canBuild(L, id) then return false end
    local p = Lucid.price(L, id)
    L.dp, L.sheep = N.sub(L.dp, p.dp), N.sub(L.sheep, p.sheep)
    L.grid[c], L.level[c] = id, 1
    L.built[id] = L.built[id] + 1
    emit({ type = "built", id = id, cell = c, first = L.built[id] == 1 })
    return true
end

-- Sheep-OS, the Gate of Horn: no plot, it's the way out. Bought, the gate
-- is open (`gate` is what's kept; the farm's count of it isn't saved).
function Lucid.openGate(L)
    if not Lucid.canBuild(L, "lighthouse") then return false end
    local p = Lucid.price(L, "lighthouse")
    L.dp, L.sheep = N.sub(L.dp, p.dp), N.sub(L.sheep, p.sheep)
    L.built.lighthouse = L.built.lighthouse + 1
    L.gate = true
    emit({ type = "gate" })
    return true
end

-- A level up for the building on `c`: it does one more time its effect, and
-- costs what another one would (the grid holds the town, not its growth).
-- Auto-buyers have nothing more to give.
function Lucid.canUpgrade(L, c)
    local id = L.grid[c]
    return id ~= nil and not BY[id].autoDims and Lucid.canBuild(L, id)
end

function Lucid.upgrade(L, c)
    if not Lucid.canUpgrade(L, c) then return false end
    local id = L.grid[c]
    local p = Lucid.price(L, id)
    L.dp, L.sheep = N.sub(L.dp, p.dp), N.sub(L.sheep, p.sheep)
    L.level[c] = L.level[c] + 1
    L.built[id] = L.built[id] + 1
    emit({ type = "upgraded", id = id, cell = c, level = L.level[c] })
    return true
end

-- Move a building to another open, empty cell, for nothing: try things out.
function Lucid.move(L, from, to)
    if not L.grid[from] or not L.open[to] or L.grid[to] then return false end
    L.grid[to], L.grid[from] = L.grid[from], nil
    L.level[to], L.level[from] = L.level[from], nil
    return true
end

-- Land: a closed cell beside open land, for Dream Points.
function Lucid.plotPrice(L)
    return N.from(D.grid.plotBase * D.grid.plotGrowth ^ L.plots * ROOT.surveyor.landCut ^ rank(L, "surveyor"))
end

function Lucid.canOpen(L, c)
    if L.open[c] then return false end
    local x, y = (c - 1) % GW + 1, floor((c - 1) / GW) + 1
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local nx, ny = x + d[1], y + d[2]
        if nx >= 1 and nx <= GW and ny >= 1 and ny <= GH and L.open[cell(nx, ny)] then return true end
    end
    return false
end

function Lucid.openPlot(L, c)
    if not Lucid.canOpen(L, c) or not N.gte(L.dp, Lucid.plotPrice(L)) then return false end
    L.dp = N.sub(L.dp, Lucid.plotPrice(L))
    L.open[c] = true
    L.plots = L.plots + 1
    emit({ type = "plot", cell = c })
    return true
end

--- what everything comes to -----------------------------------------------------------

local function effect(L, id) return L.effects[id] and L.effects[id] > 0 end

-- What the best height ever lifts every layer by.
function Lucid.recordMult(L)
    local per = D.bounce.recordPer * (1 + ROOT.moonpull.recordAdd * rank(L, "moonpull"))
        * (Lucid.met(L, "skyHigh") and CH.skyHigh.rewardRecord or 1)
    return 1 + per * L.best / 100
end

-- Every layer's multiplier: Dream Mills, the Dream Points earned (more with
-- the Deep Well), the best height, a frenzy, Falling mastered. Under a dream
-- challenge the dream forgets the points: only the town counts.
function Lucid.dimMult(L)
    local m = N.from((1 + BY.mill.dimAdd * Lucid.sum(L, "mill")) * Lucid.recordMult(L))
    if not L.challenge then
        local per = D.multPerRootDP * (1 + ROOT.well.wellAdd * rank(L, "well"))
        m = N.mul(m, N.add(N.one(), N.mul(N.sqrt(L.dpEarned), N.from(per))))
    end
    if Lucid.met(L, "falling") then m = N.mul(m, N.from(CH.falling.rewardLayers)) end
    if effect(L, "frenzy") then m = N.mul(m, N.from(D.golden.frenzy.mult)) end
    return m
end

-- How much faster time runs in a layer for every ten sleepers in it.
function Lucid.dilation(L)
    local base = Lucid.met(L, "onlyOne") and CH.onlyOne.rewardBonus or D.bonus
    return base + ROOT.dilation.bonusAdd * rank(L, "dilation")
end

-- Whether layer k dreams at all (Shallow Sleep keeps only the first three).
function Lucid.layerOn(L, k)
    local most = under(L, "layersMax")
    return not most or k <= most
end

-- What one sleeper of layer k makes a second (of the layer above it, or sheep).
function Lucid.dimRate(L, k)
    if not Lucid.layerOn(L, k) then return N.zero() end
    local d = L.dims[k]
    local shallow = (k <= CH.shallow.layersMax and Lucid.met(L, "shallow")) and CH.shallow.rewardShallow or 1
    return N.mul(Lucid.dimMult(L), N.from(D.dims[k].rate * shallow * Lucid.dilation(L) ^ floor(d.bought / D.bonusEvery)))
end

function Lucid.sheepRate(L)
    return N.mul(L.dims[1].amount, Lucid.dimRate(L, 1))
end

-- Dream sheep a run, after Dog Kennels.
function Lucid.need(L)
    return N.from(D.sheepPerRun / (1 + BY.inn.needDiv * Lucid.sum(L, "inn")))
end

-- The most runs a second, after Better Fences (and a song's tune).
function Lucid.cap(L)
    local power = BY.clock.capPower + (Lucid.met(L, "stoppedClocks") and CH.stoppedClocks.rewardCapPower or 0)
    local tune = effect(L, "tune") and L.tuneMult or 1
    return D.runCap * (1 + Lucid.sum(L, "clock") * (under(L, "clockMult") or 1)) ^ power * tune
end

-- Runs a second: what the sheep pay for, no more than the cap, half while a
-- nightmare is on. A plain number: the cap keeps it small.
function Lucid.runsPerSecond(L)
    local r = N.toNumber(N.min(N.from(Lucid.cap(L)), N.div(Lucid.sheepRate(L), Lucid.need(L))))
    if L.nightmare then r = r * D.nightmare.slow end
    return r
end

function Lucid.dpPerRun(L)
    local v = N.from(D.dpPerRun * L.legacy * (1 + BY.bakery.dpAdd * Lucid.sum(L, "bakery")))
    if effect(L, "frenzy") then v = N.mul(v, N.from(D.golden.frenzy.mult)) end
    return v
end

function Lucid.dpPerSecond(L)
    return N.mul(Lucid.dpPerRun(L), N.from(Lucid.runsPerSecond(L)))
end

--- the layers --------------------------------------------------------------------------

-- A sleeper's first price, after the Architect.
local function dimBase(L, k) return D.dims[k].base / (1 + ROOT.architect.costCut * rank(L, "architect")) end

function Lucid.dimCost(L, k, n)
    return N.from(N.geoCost(dimBase(L, k), D.dims[k].growth, L.dims[k].bought, n or 1))
end

-- Buy n sleepers for layer k (or "max"). `share` spends no more than that share of
-- the sheep (the auto-buyers). Returns how many.
function Lucid.buyDim(L, k, n, share, auto)
    local d, dim = D.dims[k], L.dims[k]
    local budget = share and N.mul(L.sheep, N.from(share)) or L.sheep
    local can = N.geoMax(dimBase(L, k), d.growth, dim.bought, budget)
    if not Lucid.layerOn(L, k) then can = 0 end
    local most = under(L, "dimMax")
    if most then can = min(can, max(0, most - dim.bought)) end
    n = n == "max" and can or min(n, can)
    if n <= 0 then return 0 end
    L.sheep = N.sub(L.sheep, Lucid.dimCost(L, k, n))
    dim.bought = dim.bought + n
    dim.amount = N.add(dim.amount, N.from(n))
    emit({ type = "dim", k = k, n = n, auto = auto, first = dim.bought == n })
    return n
end

-- A layer shows once the one before it has a sleeper bought (layer 1 always).
function Lucid.dimVisible(L, k)
    return k == 1 or L.dims[k - 1].bought > 0
end

-- Which layers the town's auto-buyers look after.
function Lucid.autoHas(L, k)
    for _, b in ipairs(BUILD) do
        if b.autoDims and L.built[b.id] > 0 then
            for _, j in ipairs(b.autoDims) do if j == k then return true end end
        end
    end
    return false
end

function Lucid.autoOn(L, k) return Lucid.autoHas(L, k) and not L.autoOff[k] and not under(L, "noAuto") end

-- The share of the sheep an auto-buyer trip spends on a layer.
function Lucid.autoShare(L) return D.autoShare + ROOT.bellows.shareAdd * rank(L, "bellows") end
function Lucid.toggleAuto(L, k) if Lucid.autoHas(L, k) then L.autoOff[k] = not L.autoOff[k] or nil end end

--- the golden sheep --------------------------------------------------------------------

local function goldenWait(L, d) return d / (1 + BY.fountain.goldenAdd * Lucid.sum(L, "fountain")) end

-- How long the golden sheep takes to cross, after Slow Gold.
function Lucid.crossTime(L) return D.golden.crossTime * (1 + ROOT.slowgold.crossAdd * rank(L, "slowgold")) end

-- Caught: the game keeps going while you choose.
function Lucid.catchGolden(L)
    if not L.golden or L.choosing then return false end
    L.golden, L.choosing = nil, true
    emit({ type = "goldenCaught" })
    return true
end

-- One of three: "frenzy", "points" or "warp".
function Lucid.choose(L, id)
    if not L.choosing then return nil end
    L.choosing = false
    local G = D.golden
    if id == "points" then
        local v = N.max(N.mul(Lucid.dpPerSecond(L), N.from(G.points.seconds)), N.from(G.points.least))
        L.dp, L.dpEarned = N.add(L.dp, v), N.add(L.dpEarned, v)
        emit({ type = "gift", id = id, value = v })
        return v
    end
    L.effects[id] = G[id].seconds * (1 + ROOT.totem.giftAdd * rank(L, "totem"))
    emit({ type = "gift", id = id })
    return true
end

--- nightmares --------------------------------------------------------------------------

function Lucid.penScale(L)
    return 1 + BY.fold.penAdd * Lucid.sum(L, "fold") + (Lucid.met(L, "season") and CH.season.rewardPen or 0)
end

-- What the upgrades do to the dog and the cloud.
function Lucid.nightmareOpts(L)
    return { dog = 1 + ROOT.quickdog.dogAdd * rank(L, "quickdog"), cloud = 1 / (1 + ROOT.nightlight.cloudCut * rank(L, "nightlight")) }
end

-- Where the dog goes (field units), or nil when let go.
function Lucid.point(L, x, y)
    if L.nightmare then Nightmare.point(L.nightmare, x, y) end
end

local function endNightmare(L)
    local nm = L.nightmare
    local share = Nightmare.saved(nm)
    local v = N.zero()
    if nm.won then
        local M = D.nightmare
        v = N.mul(N.max(N.mul(Lucid.dpPerSecond(L), N.from(M.rewardSeconds)), N.from(M.least)),
            N.from(share * (1 + BY.fold.rewardAdd * Lucid.sum(L, "fold"))
                * (Lucid.met(L, "season") and CH.season.rewardPay or 1) * (1 + ROOT.dog.herdAdd * rank(L, "dog"))))
        L.dp, L.dpEarned = N.add(L.dp, v), N.add(L.dpEarned, v)
        if L.challenge == "season" then L.herded = L.herded + 1 end
    end
    L.nightmare = nil
    local M = D.nightmare
    L.nightmareIn = under(L, "nightmareEvery") or (M.minDelay + (M.maxDelay - M.minDelay) * 0.5)
    emit({ type = "nightmareOver", won = nm.won, saved = share, value = v })
end

--- dream challenges ----------------------------------------------------------------------

function Lucid.mirror(L) return L.built.mirror > 0 end

-- How far the challenge under way has got: done, goal (both plain numbers).
function Lucid.progress(L)
    local c = L.challenge and CH[L.challenge]
    if not c then return nil end
    if c.goal == "herd" then return L.herded, c.herd end
    if c.goal == "height" then return min(floor(L.climbed), c.height), c.height end
    if c.goal == "sheep" then
        -- In decades, so the bar fills evenly: 10^n of 10^goal.
        return min(math.floor(N.log10(N.max(L.counted, N.one()))), math.floor(math.log10(c.sheep))), math.floor(math.log10(c.sheep))
    end
    return min(Lucid.runsPerSecond(L), c.runs), c.runs
end

-- Start one: the flock wakes (the layers and dream sheep back to the start,
-- the gifts and the golden sheep gone), the town and the points stay.
function Lucid.startChallenge(L, id)
    if not CH[id] or not Lucid.mirror(L) or Lucid.met(L, id) or L.challenge == id then return false end
    if not Lucid.ready(L, ROOT["c." .. id]) then return false end
    L.sheep, L.runAcc, L.flow = N.zero(), 0, false
    for k, d in ipairs(L.dims) do
        d.amount, d.bought = N.from(D.startDims[k] or 0), D.startDims[k] or 0
    end
    L.effects, L.golden, L.choosing, L.nightmare = {}, nil, false, nil
    L.flock, L.song = nil, nil
    L.challenge, L.herded, L.counted, L.climbed = id, 0, N.zero(), 0
    if L.bounce.on then Bounce.stop(L.bounce) end
    L.nightmareIn = CH[id].nightmareEvery or L.nightmareIn
    emit({ type = "challengeStart", id = id })
    return true
end

-- Give up: the rule lifts, and the dream goes on from where it is.
function Lucid.giveUp(L)
    if not L.challenge then return false end
    L.challenge, L.herded = nil, 0
    return true
end

local function checkChallenge(L)
    local have, goal = Lucid.progress(L)
    if have and have >= goal then
        local id = L.challenge
        L.done[id], L.challenge, L.herded = true, nil, 0
        emit({ type = "challengeDone", id = id })
    end
end

--- the upgrades (the roots) -------------------------------------------------------------

-- Whether what an upgrade opens after is there: the lake once the town has a
-- Mirror Lake; a challenge once mastered; anything else once it has a rank.
local function there(L, id)
    local r = ROOT[id]
    if r.kind == "lake" then return Lucid.mirror(L) end
    if r.kind == "challenge" then return Lucid.met(L, r.challenge) end
    if r.kind == "gate" then return L.gate end
    return rank(L, id) > 0
end
Lucid.there = there

-- Whether an upgrade can be grown (or its challenge started): the first of
-- its section always, any other once the one before it is there.
function Lucid.ready(L, r) return r ~= nil and (not r.at or there(L, r.at)) end

function Lucid.rootPrice(L, id)
    local r = ROOT[id]
    return N.from((r.dp or 0) * r.growth ^ rank(L, id))
end

-- Where an upgrade stands: "full" (grown all the way, or mastered), "on"
-- (its challenge under way), "open" (it can grow now), "poor" (not the
-- points for it), "shut" (the one before it isn't there yet).
function Lucid.rootState(L, id)
    local r = ROOT[id]
    if r.kind == "lake" then return Lucid.mirror(L) and "full" or "shut" end
    if r.kind == "challenge" then
        if Lucid.met(L, r.challenge) then return "full" end
        if L.challenge == r.challenge then return "on" end
        return (Lucid.ready(L, r) and Lucid.mirror(L)) and "open" or "shut"
    end
    if r.kind == "gate" then
        if L.gate then return "full" end
        return Lucid.ready(L, r) and "open" or "shut"
    end
    if r.kind == "up" and rank(L, id) >= r.max then return "full" end
    if not Lucid.ready(L, r) then return "shut" end
    return N.gte(L.dp, Lucid.rootPrice(L, id)) and "open" or "poor"
end

-- A rank more of an upgrade. (The Gate of Horn is bought on the farm:
-- Sheep-OS, Lucid.openGate.)
function Lucid.grow(L, id)
    local r = ROOT[id]
    if not r or r.kind ~= "up" or Lucid.rootState(L, id) ~= "open" then return false end
    L.dp = N.sub(L.dp, Lucid.rootPrice(L, id))
    L.roots[id] = rank(L, id) + 1
    emit({ type = "grew", id = id, rank = L.roots[id] })
    return true
end

-- How many ranks there are, and how many grown, over every upgrade.
function Lucid.rootsGrown(L)
    local all, grown = 0, 0
    for _, r in ipairs(ROOTS) do
        if r.kind == "up" then all, grown = all + r.max, grown + rank(L, r.id) end
    end
    return grown, all
end

--- counting sheep ------------------------------------------------------------------------

local CT = D.count

local function flockWait(L, d) return d / (1 + ROOT.bell.flockAdd * rank(L, "bell")) end

-- The flock at the fence, tapped: the song starts.
function Lucid.startSong(L)
    if not L.flock or L.song or L.nightmare then return false end
    L.flock = nil
    L.song = Count.new(1 + ROOT.slowsong.windowAdd * rank(L, "slowsong"))
    L.golden = nil
    if L.bounce.on then Bounce.stop(L.bounce) end
    emit({ type = "songStart" })
    return true
end

-- A tap on the beat. What it was: "perfect", "good" or "stray".
function Lucid.countTap(L)
    if not L.song then return nil end
    return Count.tap(L.song)
end

-- What a song pays at full marks.
function Lucid.songValue(L)
    return N.mul(N.max(N.mul(Lucid.dpPerSecond(L), N.from(CT.rewardSeconds)), N.from(CT.least)),
        N.from(1 + ROOT.lullaby.songAdd * rank(L, "lullaby")))
end

local function endSong(L)
    local song = L.song
    local share = Count.share(song)
    -- Paid before the tune lifts the cap, so the tune doesn't pay for itself.
    local v = N.mul(Lucid.songValue(L), N.from(share))
    L.dp, L.dpEarned = N.add(L.dp, v), N.add(L.dpEarned, v)
    L.song = nil
    L.flockIn = flockWait(L, CT.minDelay + (CT.maxDelay - CT.minDelay) * 0.5)
    if share > 0 then
        L.tuneMult = 1 + CT.tune.cap * share
        L.effects.tune = CT.tune.seconds * (1 + ROOT.encore.tuneAdd * rank(L, "encore"))
    end
    emit({ type = "songOver", share = share, value = v, best = song.best, perfect = song.perfect, n = #song.sheep })
end

local function counting(L, dt, rand)
    if L.song then
        Count.step(L.song, dt)
        local ev = L.song.events
        L.song.events = {}
        for _, e in ipairs(ev) do
            if e.type ~= "songOver" then emit({ type = "count", what = e.type, i = e.i, combo = e.combo }) end
        end
        if L.song.done then endSong(L) end
        return
    end
    if L.flock then
        L.flock.t = L.flock.t + dt
        if L.flock.t >= CT.wait or L.nightmare then
            L.flock = nil
            L.flockIn = flockWait(L, CT.minDelay + rand() * (CT.maxDelay - CT.minDelay))
            emit({ type = "flockGone" })
        end
        return
    end
    if L.intro or L.nightmare then return end
    L.flockIn = L.flockIn - dt
    if L.flockIn <= 0 then
        L.flock = { t = 0 }
        emit({ type = "flock" })
    end
end

--- the bouncing sheep -------------------------------------------------------------------

-- What the roots and the rule do to the climb.
function Lucid.bounceOpts(L)
    return {
        jump = 1 + ROOT.spring.jumpAdd * rank(L, "spring"),
        width = (1 + ROOT.steps.widthAdd * rank(L, "steps")) * (under(L, "widthMult") or 1),
    }
end

-- What a star pays.
function Lucid.starValue(L)
    local P = D.bounce
    return N.mul(N.max(N.mul(Lucid.dpPerSecond(L), N.from(P.starSeconds)), N.from(P.starLeast)),
        N.from((1 + ROOT.starbag.starAdd * rank(L, "starbag")) * (Lucid.met(L, "skyHigh") and CH.skyHigh.rewardStars or 1)))
end

-- The finger on the field, in field units across (0..bounce.w); nil when lifted.
function Lucid.hold(L, x)
    if L.nightmare or L.song then return end
    if x then Bounce.press(L.bounce, x) else Bounce.release(L.bounce) end
end
function Lucid.steer(L, x) Bounce.move(L.bounce, x) end

local function bounce(L, dt, rand)
    local B = L.bounce
    if L.nightmare or L.song then
        if B.on then Bounce.stop(B) end
        B.events = {}
        return
    end
    Bounce.step(B, dt, rand, Lucid.bounceOpts(L))
    if L.challenge == "skyHigh" then L.climbed = math.max(L.climbed, B.height) end
    -- The best counts as soon as it's passed, not only once the climb is over.
    B.before = B.before or L.best
    L.best = math.max(L.best, B.height)
    local ev = B.events
    B.events = {}
    for _, e in ipairs(ev) do
        if e.type == "star" then
            local v = Lucid.starValue(L)
            L.dp, L.dpEarned = N.add(L.dp, v), N.add(L.dpEarned, v)
            emit({ type = "star", value = v, x = e.x, y = e.y })
        elseif e.type == "moon" then
            if not L.choosing then L.choosing = true end
            emit({ type = "moon", x = e.x, y = e.y })
        elseif e.type == "fell" then
            local record = e.height > B.before
            B.before = nil
            emit({ type = "fell", height = e.height, stars = e.stars, record = record })
        else
            emit({ type = e.type, kind = e.kind })
        end
    end
end

--- each step --------------------------------------------------------------------------

-- Runs, sheep and the auto-buyers over `dt` seconds of dream time.
local function produce(L, dt)
    -- The chain: each layer dreams up the one above it; the first, sheep.
    for k = #L.dims, 2, -1 do
        local made = N.mul(N.mul(L.dims[k].amount, Lucid.dimRate(L, k)), N.from(dt))
        L.dims[k - 1].amount = N.add(L.dims[k - 1].amount, made)
    end
    local sheep = N.mul(Lucid.sheepRate(L), N.from(dt))
    L.sheep, L.sheepTotal = N.add(L.sheep, sheep), N.add(L.sheepTotal, sheep)
    if L.challenge then L.counted = N.add(L.counted, sheep) end
    -- Runs, in a batch: the whole ones in this step's share are paid for.
    local r = Lucid.runsPerSecond(L)
    local acc = L.runAcc + r * dt
    local whole = floor(acc)
    L.runAcc = acc - whole
    if whole > 0 then
        local pay = N.mul(Lucid.dpPerRun(L), N.from(whole))
        L.runs = N.add(L.runs, N.from(whole))
        L.dp, L.dpEarned = N.add(L.dp, pay), N.add(L.dpEarned, pay)
        emit({ type = "runs", n = whole, value = pay })
    end
    if not L.flow and r >= D.flowAt then
        L.flow = true
        emit({ type = "flow" })
    end
    L.autoIn = L.autoIn - dt
    if L.autoIn <= 0 then
        L.autoIn = D.autoEvery
        for k = #L.dims, 1, -1 do
            if Lucid.autoOn(L, k) and Lucid.dimVisible(L, k) then Lucid.buyDim(L, k, "max", Lucid.autoShare(L), true) end
        end
    end
end

-- One fixed step of `dt` real seconds. `rand` gives 0..1.
function Lucid.step(L, dt, rand)
    rand = rand or math.random
    L.time = L.time + dt
    local warp = effect(L, "warp") and D.golden.warp.mult or 1
    produce(L, dt * warp)
    for id, left in pairs(L.effects) do
        L.effects[id] = left - dt
        if L.effects[id] <= 0 then L.effects[id] = nil; emit({ type = "giftOver", id = id }) end
    end
    -- The golden sheep crosses, unless a nightmare is on.
    if L.golden then
        L.golden.t = L.golden.t + dt
        if L.golden.t >= Lucid.crossTime(L) then L.golden = nil end
    elseif not L.nightmare and not L.song and not L.choosing then
        L.goldenIn = L.goldenIn - dt
        if L.goldenIn <= 0 then
            L.golden = { t = 0, lane = rand() }
            L.goldenIn = goldenWait(L, D.golden.minDelay + rand() * (D.golden.maxDelay - D.golden.minDelay))
            emit({ type = "goldenAppears" })
        end
    end
    -- Nightmares.
    if L.nightmare then
        Nightmare.update(L.nightmare, dt, rand)
        if L.nightmare.done then endNightmare(L) end
    elseif not L.intro and not L.song and not L.flock then
        L.nightmareIn = L.nightmareIn - dt
        if L.nightmareIn <= 0 then
            local M = D.nightmare
            L.nightmare = Nightmare.new(M.sheep, M.seconds, Lucid.penScale(L), rand, Lucid.nightmareOpts(L))
            L.golden = nil
            L.nightmareIn = M.minDelay + rand() * (M.maxDelay - M.minDelay)
            emit({ type = "nightmare" })
        end
    end
    counting(L, dt, rand)
    bounce(L, dt, rand)
    if L.challenge then checkChallenge(L) end
end

--- away ---------------------------------------------------------------------------------

-- Away `seconds`: worked out in closed form, not step by step. With what's
-- bought held still, the chain is a polynomial in t: layer j adds
-- a_j * r_j * r_(j-1) ... r_(k+1) * t^(j-k) / (j-k)! to layer k, and
-- a_j * r_j ... r_1 * t^j / j! sheep. Runs a second follow the sheep rate up
-- to the cap: the time it's reached is found by halving (a few dozen
-- evaluations, not a simulation), and the runs are the rate's integral to
-- there plus the cap after. The points those runs earn lift the layers'
-- multiplier, so the time away is cut into `AWAY_PIECES` pieces, each in
-- closed form with the multiplier it starts with. No golden sheep, nightmares
-- or auto-buying while away; the auto-buyers shop once on the way back.
local AWAY_PIECES = 32
local function fact(n) local f = 1 for i = 2, n do f = f * i end return f end

-- The sheep rate at time t (Num), and the sheep counted from 0 to t (Num).
local function sheepAt(L, t)
    local n = #L.dims
    local rates = {}
    for k = 1, n do rates[k] = Lucid.dimRate(L, k) end
    local rate, total = N.zero(), N.zero()
    for j = 1, n do
        local a = L.dims[j].amount
        if not N.isZero(a) then
            local chain = N.one()
            for i = 1, j do chain = N.mul(chain, rates[i]) end
            local base = N.mul(a, chain)
            -- rate: a_j * chain * t^(j-1)/(j-1)!; total: a_j * chain * t^j / j!
            rate = N.add(rate, N.div(N.mul(base, N.pow(N.from(t), j - 1)), N.from(fact(j - 1))))
            total = N.add(total, N.div(N.mul(base, N.pow(N.from(t), j)), N.from(fact(j))))
        end
    end
    return rate, total
end

-- One piece of time away, `T` seconds, in closed form. Returns what it made.
local function advance(L, T)
    local need, cap = Lucid.need(L), N.from(Lucid.cap(L))
    local slow = L.nightmare and D.nightmare.slow or 1
    -- Runs: before the cap, the sheep counted / need; after, the cap.
    local function capped(t) return N.gte(N.div(sheepAt(L, t), need), cap) end
    local tc
    if capped(0) then tc = 0
    elseif not capped(T) then tc = T
    else
        local lo, hi = 0, T
        for _ = 1, 40 do
            local mid = (lo + hi) / 2
            if capped(mid) then hi = mid else lo = mid end
        end
        tc = hi
    end
    local _, before = sheepAt(L, tc)
    local runs = N.add(N.mul(N.add(N.div(before, need), N.mul(cap, N.from(T - tc))), N.from(slow)), N.from(L.runAcc))
    local whole = N.floor(runs)
    L.runAcc = N.toNumber(N.sub(runs, whole)) -- a fraction of a run, for the next piece
    runs = whole
    local _, sheep = sheepAt(L, T)
    -- The layers themselves move on too.
    local n = #L.dims
    local rates = {}
    for k = 1, n do rates[k] = Lucid.dimRate(L, k) end
    local new = {}
    for k = 1, n do
        local v = L.dims[k].amount
        for j = k + 1, n do
            local chain = L.dims[j].amount
            for i = k + 1, j do chain = N.mul(chain, rates[i]) end
            v = N.add(v, N.div(N.mul(chain, N.pow(N.from(T), j - k)), N.from(fact(j - k))))
        end
        new[k] = v
    end
    for k = 1, n do L.dims[k].amount = new[k] end
    local dp = N.mul(runs, Lucid.dpPerRun(L))
    L.sheep, L.sheepTotal = N.add(L.sheep, sheep), N.add(L.sheepTotal, sheep)
    L.runs = N.add(L.runs, runs)
    L.dp, L.dpEarned = N.add(L.dp, dp), N.add(L.dpEarned, dp)
    L.time = L.time + T
    return sheep, runs, dp
end

function Lucid.offline(L, seconds)
    if seconds <= 0 then return nil end
    local T = min(seconds, C.offline.maxHours * 3600)
    local sheep, runs, dp = N.zero(), N.zero(), N.zero()
    for _ = 1, AWAY_PIECES do
        local a, b, c = advance(L, T / AWAY_PIECES)
        sheep, runs, dp = N.add(sheep, a), N.add(runs, b), N.add(dp, c)
    end
    for k = #L.dims, 1, -1 do
        if Lucid.autoOn(L, k) and Lucid.dimVisible(L, k) then Lucid.buyDim(L, k, "max", Lucid.autoShare(L), true) end
    end
    return { secs = T, capped = seconds > T, sheep = sheep, runs = runs, dp = dp }
end

--- saves ---------------------------------------------------------------------------------

local NUMS = { "sheep", "sheepTotal", "dp", "dpEarned", "runs", "counted" }

function Lucid.serialize(L)
    local o = {}
    for k, v in pairs(L) do o[k] = v end
    for _, k in ipairs(NUMS) do o[k] = N.serialize(L[k]) end
    o.dims = {}
    for k, d in ipairs(L.dims) do o.dims[k] = { amount = N.serialize(d.amount), bought = d.bought } end
    -- Cells as strings: JSON objects can't have number keys.
    o.open, o.grid, o.level, o.autoOff = {}, {}, {}, {}
    for c in pairs(L.open) do o.open[tostring(c)] = true end
    for c, id in pairs(L.grid) do o.grid[tostring(c)] = id; o.level[tostring(c)] = L.level[c] end
    for k in pairs(L.autoOff) do o.autoOff[tostring(k)] = true end
    o.nightmare = nil -- a nightmare in progress isn't kept: it passes while you're away
    o.choosing = nil
    o.bounce = nil -- nor a climb
    o.flock, o.song = nil, nil -- nor a song, or a flock waiting
    o.roots = {}
    for id, n in pairs(L.roots) do o.roots[id] = n end
    return o
end

-- Back from a save; missing or odd fields come back fresh.
function Lucid.deserialize(o, s1)
    local L = Lucid.fresh(s1)
    if type(o) ~= "table" then return L end
    for _, k in ipairs(NUMS) do if o[k] ~= nil then L[k] = N.deserialize(o[k]) end end
    for _, k in ipairs({ "runAcc", "legacy", "plots", "time", "goldenIn", "nightmareIn", "herded", "best", "climbed", "flockIn", "tuneMult" }) do
        if type(o[k]) == "number" then L[k] = o[k] end
    end
    if type(o.roots) == "table" then
        for id, n in pairs(o.roots) do
            local r = ROOT[id]
            if r and r.kind == "up" and tonumber(n) then L.roots[id] = max(0, min(r.max, floor(tonumber(n)))) end
        end
    end
    for _, k in ipairs({ "flow", "intro", "gate" }) do if type(o[k]) == "boolean" then L[k] = o[k] end end
    if type(o.dims) == "table" then
        for k, d in ipairs(L.dims) do
            local od = o.dims[k]
            if type(od) == "table" then
                d.amount = N.deserialize(od.amount)
                d.bought = max(0, floor(tonumber(od.bought) or 0))
            end
        end
    end
    if type(o.open) == "table" then
        L.open = {}
        for c in pairs(o.open) do local n = tonumber(c) if n then L.open[n] = true end end
    end
    if type(o.grid) == "table" then
        for c, id in pairs(o.grid) do
            local n = tonumber(c)
            if n and BY[id] and not BY[id].locked and not BY[id].gate then
                L.grid[n] = id
                local lv = type(o.level) == "table" and tonumber(o.level[c]) or 1
                L.level[n] = BY[id].autoDims and 1 or max(1, floor(lv or 1))
            end
        end
    end
    for id in pairs(L.built) do L.built[id] = 0 end
    for c, id in pairs(L.grid) do L.built[id] = L.built[id] + L.level[c] end
    if type(o.autoOff) == "table" then
        for k in pairs(o.autoOff) do local n = tonumber(k) if n then L.autoOff[n] = true end end
    end
    if type(o.challenge) == "string" and CH[o.challenge] then L.challenge = o.challenge end
    if type(o.done) == "table" then
        for id in pairs(CH) do if o.done[id] == true then L.done[id] = true end end
    end
    if type(o.effects) == "table" then
        for id, left in pairs(o.effects) do
            if (D.golden[id] or id == "tune") and type(left) == "number" then L.effects[id] = left end
        end
    end
    return L
end

return Lucid
