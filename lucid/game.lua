-- The rules of phase 2, lucid dreaming. Pure Lua, no LÖVE, like game.lua.
--
-- The night runs itself now (auto-wake): the six dream dimensions count dream
-- sheep, a run is over every `sheepPerRun` of them (no faster than the run
-- cap), and each run pays Dream Points. Runs are settled in batches, never one
-- reset a frame: a step adds runs a second * dt to a fraction and pays for the
-- whole runs in it. Dream Points build the town, a grid where a building does
-- more beside its own district and beside a Plaza; dream sheep buy dimensions
-- and the town's materials. A golden sheep offers a choice of three, and now
-- and then a nightmare scatters a flock for the dog to herd (nightmare.lua).
--
-- Every amount (sheep, points, dimensions, runs) is a Num and goes through
-- num.lua; counts of things bought and the multipliers stay plain numbers.
-- The state is `s.lucid`; game.lua's phase-1 fields stay as they were.

local C = require "config"
local N = require "num"
local Nightmare = require "lucid.nightmare"

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
        autoOff = {}, -- dimension index = true when its auto-buyer is paused
        time = 0, autoIn = 0,
        golden = nil, goldenIn = D.golden.firstDelay,
        effects = {}, -- id = seconds left: frenzy, warp
        choosing = false, -- a golden sheep caught, its three gifts on offer
        nightmare = nil, nightmareIn = D.nightmare.firstDelay,
        flow = false, -- runs too quick to see: the flow
        intro = true, -- the entrance still to show
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

--- the town ------------------------------------------------------------------------

-- Each building's effect, after its neighbours: its level alone, more beside
-- its own district and beside a Plaza (a Plaza does nothing on its own).
function Lucid.strength(L, c)
    local id = L.grid[c]
    if not id then return 0 end
    local b = BY[id]
    local x, y = (c - 1) % GW + 1, floor((c - 1) / GW) + 1
    local v = 1
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local nx, ny = x + d[1], y + d[2]
        if nx >= 1 and nx <= GW and ny >= 1 and ny <= GH then
            local o = L.grid[cell(nx, ny)]
            if o == "plaza" then v = v + D.adjacency.plaza end
            if o and o ~= "plaza" and BY[o].district == b.district then v = v + D.adjacency.sameDistrict end
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
    return { dp = N.mul(N.from(b.dp or 0), g), sheep = N.mul(N.from(b.sheep or 0), g) }
end

function Lucid.canBuild(L, id)
    local b = BY[id]
    if b.locked or (b.max and L.built[id] >= b.max) then return false end
    local p = Lucid.price(L, id)
    return N.gte(L.dp, p.dp) and N.gte(L.sheep, p.sheep)
end

-- Build `id` on the open, empty cell `c`.
function Lucid.build(L, id, c)
    if not L.open[c] or L.grid[c] or not Lucid.canBuild(L, id) then return false end
    local p = Lucid.price(L, id)
    L.dp, L.sheep = N.sub(L.dp, p.dp), N.sub(L.sheep, p.sheep)
    L.grid[c], L.level[c] = id, 1
    L.built[id] = L.built[id] + 1
    emit({ type = "built", id = id, cell = c, first = L.built[id] == 1 })
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
    return N.from(D.grid.plotBase * D.grid.plotGrowth ^ L.plots)
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

-- Every dimension's multiplier: Dream Mills, the Dream Points earned, a frenzy.
function Lucid.dimMult(L)
    local m = 1 + BY.mill.dimAdd * Lucid.sum(L, "mill")
    m = N.mul(N.from(m), N.add(N.one(), N.mul(N.sqrt(L.dpEarned), N.from(D.multPerRootDP))))
    if effect(L, "frenzy") then m = N.mul(m, N.from(D.golden.frenzy.mult)) end
    return m
end

-- What one of dimension k makes a second (of the one before it, or sheep).
function Lucid.dimRate(L, k)
    local d = L.dims[k]
    return N.mul(Lucid.dimMult(L), N.from(D.dims[k].rate * D.bonus ^ floor(d.bought / D.bonusEvery)))
end

function Lucid.sheepRate(L)
    return N.mul(L.dims[1].amount, Lucid.dimRate(L, 1))
end

-- Dream sheep a run, after Dream Inns.
function Lucid.need(L)
    return N.from(D.sheepPerRun / (1 + BY.inn.needDiv * Lucid.sum(L, "inn")))
end

-- The most runs a second, after Clock Towers.
function Lucid.cap(L)
    return D.runCap * (1 + Lucid.sum(L, "clock")) ^ BY.clock.capPower
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

--- dimensions --------------------------------------------------------------------------

function Lucid.dimCost(L, k, n)
    local d = D.dims[k]
    return N.from(N.geoCost(d.base, d.growth, L.dims[k].bought, n or 1))
end

-- Buy n of dimension k (or "max"). `share` spends no more than that share of
-- the sheep (the auto-buyers). Returns how many.
function Lucid.buyDim(L, k, n, share, auto)
    local d, dim = D.dims[k], L.dims[k]
    local budget = share and N.mul(L.sheep, N.from(share)) or L.sheep
    local can = N.geoMax(d.base, d.growth, dim.bought, budget)
    n = n == "max" and can or min(n, can)
    if n <= 0 then return 0 end
    L.sheep = N.sub(L.sheep, Lucid.dimCost(L, k, n))
    dim.bought = dim.bought + n
    dim.amount = N.add(dim.amount, N.from(n))
    emit({ type = "dim", k = k, n = n, auto = auto, first = dim.bought == n })
    return n
end

-- A dimension shows once the one before it is bought (D1 always).
function Lucid.dimVisible(L, k)
    return k == 1 or L.dims[k - 1].bought > 0
end

-- Which dimensions the town's auto-buyers look after.
function Lucid.autoHas(L, k)
    for _, b in ipairs(BUILD) do
        if b.autoDims and L.built[b.id] > 0 then
            for _, j in ipairs(b.autoDims) do if j == k then return true end end
        end
    end
    return false
end

function Lucid.autoOn(L, k) return Lucid.autoHas(L, k) and not L.autoOff[k] end
function Lucid.toggleAuto(L, k) if Lucid.autoHas(L, k) then L.autoOff[k] = not L.autoOff[k] or nil end end

--- the golden sheep --------------------------------------------------------------------

local function goldenWait(L, d) return d / (1 + BY.fountain.goldenAdd * Lucid.sum(L, "fountain")) end

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
    L.effects[id] = G[id].seconds
    emit({ type = "gift", id = id })
    return true
end

--- nightmares --------------------------------------------------------------------------

function Lucid.penScale(L) return 1 + BY.fold.penAdd * Lucid.sum(L, "fold") end

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
            N.from(share * (1 + BY.fold.rewardAdd * Lucid.sum(L, "fold"))))
        L.dp, L.dpEarned = N.add(L.dp, v), N.add(L.dpEarned, v)
    end
    L.nightmare = nil
    local M = D.nightmare
    L.nightmareIn = M.minDelay + (M.maxDelay - M.minDelay) * 0.5
    emit({ type = "nightmareOver", won = nm.won, saved = share, value = v })
end

--- each step --------------------------------------------------------------------------

-- Runs, sheep and the auto-buyers over `dt` seconds of dream time.
local function produce(L, dt)
    -- The chain: each dimension makes the one before it; the first, sheep.
    for k = #L.dims, 2, -1 do
        local made = N.mul(N.mul(L.dims[k].amount, Lucid.dimRate(L, k)), N.from(dt))
        L.dims[k - 1].amount = N.add(L.dims[k - 1].amount, made)
    end
    local sheep = N.mul(Lucid.sheepRate(L), N.from(dt))
    L.sheep, L.sheepTotal = N.add(L.sheep, sheep), N.add(L.sheepTotal, sheep)
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
            if Lucid.autoOn(L, k) and Lucid.dimVisible(L, k) then Lucid.buyDim(L, k, "max", D.autoShare, true) end
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
        if L.golden.t >= D.golden.crossTime then L.golden = nil end
    elseif not L.nightmare and not L.choosing then
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
    elseif not L.intro then
        L.nightmareIn = L.nightmareIn - dt
        if L.nightmareIn <= 0 then
            local M = D.nightmare
            L.nightmare = Nightmare.new(M.sheep, M.seconds, Lucid.penScale(L), rand)
            L.golden = nil
            L.nightmareIn = M.minDelay + rand() * (M.maxDelay - M.minDelay)
            emit({ type = "nightmare" })
        end
    end
end

--- away ---------------------------------------------------------------------------------

-- Away `seconds`: worked out in closed form, not step by step. With what's
-- bought held still, the chain is a polynomial in t: dimension j adds
-- a_j * r_j * r_(j-1) ... r_(k+1) * t^(j-k) / (j-k)! to dimension k, and
-- a_j * r_j ... r_1 * t^j / j! sheep. Runs a second follow the sheep rate up
-- to the cap: the time it's reached is found by halving (a few dozen
-- evaluations, not a simulation), and the runs are the rate's integral to
-- there plus the cap after. The points those runs earn lift the dimensions'
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
    -- The dimensions themselves move on too.
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
        if Lucid.autoOn(L, k) and Lucid.dimVisible(L, k) then Lucid.buyDim(L, k, "max", D.autoShare, true) end
    end
    return { secs = T, capped = seconds > T, sheep = sheep, runs = runs, dp = dp }
end

--- saves ---------------------------------------------------------------------------------

local NUMS = { "sheep", "sheepTotal", "dp", "dpEarned", "runs" }

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
    return o
end

-- Back from a save; missing or odd fields come back fresh.
function Lucid.deserialize(o, s1)
    local L = Lucid.fresh(s1)
    if type(o) ~= "table" then return L end
    for _, k in ipairs(NUMS) do if o[k] ~= nil then L[k] = N.deserialize(o[k]) end end
    for _, k in ipairs({ "runAcc", "legacy", "plots", "time", "goldenIn", "nightmareIn" }) do
        if type(o[k]) == "number" then L[k] = o[k] end
    end
    for _, k in ipairs({ "flow", "intro" }) do if type(o[k]) == "boolean" then L[k] = o[k] end end
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
            if n and BY[id] and not BY[id].locked then
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
    if type(o.effects) == "table" then
        for id, left in pairs(o.effects) do
            if D.golden[id] and type(left) == "number" then L.effects[id] = left end
        end
    end
    return L
end

return Lucid
