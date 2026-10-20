-- The rules' tests and the balance sim, no LÖVE needed:
--   luajit tests/run.lua          the tests
--   luajit tests/run.lua sim      the sim: a greedy player at 3, 1.5 and 0.5 taps a second
io.stdout:setvbuf("line")
package.path = "./?.lua;./lib/?.lua;" .. package.path

local Game = require "game"
local N = require "num"
local C = require "config"

-- One night for a greedy player tapping `tapRate` a second, who catches every
-- golden sheep and buys the best value it can see (leaving what the
-- automation buys to the automation). With `s`, that state's night, quietly;
-- it returns the night's length in seconds.
local function sim(tapRate, dreamPoints, s)
    local quiet = s ~= nil
    s = s or Game.fresh()
    if not quiet then s.dreamPoints, s.dreamEarned = dreamPoints or 0, dreamPoints or 0 end
    local seed = 7
    local function rand() seed = (seed * 16807) % 2147483647 return seed / 2147483647 end
    local dt, t, acc = 1 / C.tickRate, 0, 0
    local firsts, stages, gaps, lastBuy, buys5 = {}, {}, 0, 0, 0
    local function value(id)
        local it = Game.BY_ID[id]
        local sps, tv = Game.perSecond(s), Game.tapValue(s)
        if it.kind == "gen" then return it.rate * Game.globalMult(s) end
        if it.kind == "tap" then
            s.owned[id] = s.owned[id] + 1
            local nv = Game.tapValue(s)
            s.owned[id] = s.owned[id] - 1
            return (nv - tv) * tapRate
        end
        return (sps + tv * tapRate) * it.add / (1 + it.add * s.owned[id])
    end
    while not s.asleep and t < 3600 do
        t = t + dt
        Game.step(s, dt, rand)
        acc = acc + tapRate * dt
        while acc >= 1 do acc = acc - 1; Game.tap(s) end
        if s.golden and s.golden.t > 2 then Game.catchGolden(s) end
        local best, bp = nil, math.huge
        for _, it in ipairs(Game.ITEMS) do
            if Game.visible(s, it.id) and not Game.automated(s, it.id) then
                local q = Game.quote(s, it.id, "1")
                local v = not q.maxed and value(it.id) or 0
                if v > 0 then
                    local p = q.cost / v + q.cost / math.max(1, Game.totalPerSecond(s) + Game.tapValue(s) * tapRate)
                    if p < bp then best, bp = it.id, p end
                end
            end
        end
        if best then
            local first = s.owned[best] == 0
            if Game.buy(s, best, "1") then
                if t < 300 then gaps = math.max(gaps, t - lastBuy); buys5 = buys5 + 1 end
                lastBuy = t
                if first then firsts[#firsts + 1] = ("%s@%ds"):format(best, t) end
            end
        end
        if not stages[s.stage] then stages[s.stage] = ("%.1fm"):format(t / 60) end
        Game.events = {}
    end
    if quiet then return t end
    print(("taps/s %.1f  asleep at %.1f min  total %s  DP %d"):format(tapRate, t / 60, N.format(s.runTotal), Game.dreamPointsFor(s)))
    print("  firsts: " .. table.concat(firsts, " "))
    print("  stages: " .. table.concat(stages, " "))
    print(("  first 5 min: %d purchases, longest wait %.1fs"):format(buys5, gaps))
end

-- Night after night: at each new night the Dream Points go on the cheapest
-- thing in the Dream shop, again and again, and the night is played. A
-- tapping player sleeps light, one who doesn't tap sleeps heavy, unless
-- `sleeps` says ("light" or "heavy"). With `restless`, each restless night is
-- played as soon as it opens.
local function nights(tapRate, n, restless, sleeps)
    local s = Game.fresh()
    sleeps = sleeps or (tapRate > 0 and "light" or "heavy")
    local way = sleeps == "light" and "heavySleeper" or "lightSleeper" -- the one not taken
    print(("night after night at %.1f taps a second, sleeping %s%s:"):format(tapRate, sleeps,
        restless and ", restless nights first" or ""))
    for k = 1, n do
        while true do
            local best, bc
            for _, it in ipairs(Game.DREAMS) do
                local q = Game.quote(s, it.id, "1")
                if it.id ~= way and Game.visible(s, it.id) and q.ok and (not bc or q.cost < bc) then best, bc = it.id, q.cost end
            end
            if not best then break end
            Game.buy(s, best, "1")
        end
        if restless then
            for _, c in ipairs(Game.CHALLENGES) do
                if not s.challenge and not Game.done(s, c.id) and Game.challengeOpen(s, c.id) then Game.startChallenge(s, c.id) end
            end
        end
        Game.events = {}
        local t = sim(tapRate, nil, s)
        local lv = {}
        for _, it in ipairs(Game.DREAMS) do lv[#lv + 1] = s.dream[it.id] end
        local lucid = s.lucidNight and "  LUCID" or ""
        local name = s.challenge and ("  " .. Game.CH[s.challenge].name:upper()) or ""
        if not s.asleep then name = name .. " (NOT ASLEEP)" end
        local gained = Game.dreamAgain(s)
        print(("  %2d  %7.1f s  +%-5d DP  x%-9s levels %s%s%s"):format(k, t, gained, N.format(Game.globalMult(s)),
            table.concat(lv, " "), lucid, name))
    end
end

if arg[1] == "nights" and arg[4] then
    nights(tonumber(arg[2]) or 1.5, tonumber(arg[3]) or 15, arg[5] == "restless", arg[4])
    return
end

if arg[1] == "nights" then
    nights(tonumber(arg[2]) or 1.5, tonumber(arg[3]) or 15)
    nights(0, tonumber(arg[3]) or 15)
    nights(tonumber(arg[2]) or 1.5, tonumber(arg[3]) or 15, true)
    return
end

-- Phase 2 for a greedy player who comes in with `dp` points and a legacy of
-- `earned`: every second it buys dimensions (half the sheep at most, top
-- down), then the building that pays best, on the cell where it does most,
-- and land when the town is full. It catches every golden sheep (frenzy, then
-- points, then warp, in turn) and herds every nightmare in, in 35 seconds.
-- It prints each new thing as it comes, and runs a second minute by minute.
local function lucidSim(minutes, dp, earned)
    local Lucid = require "lucid.game"
    local D = C.dream
    local L = Lucid.fresh({ dreamPoints = dp, dreamEarned = earned })
    L.intro = false
    local seed = 3
    local function rand() seed = (seed * 16807) % 2147483647 return seed / 2147483647 end
    local news, last, gaps, t = {}, 0, {}, 0
    local lastBuy, buyGap = 0, 0 -- any building, level or land: an improvement
    local function bought()
        if t <= 600 then buyGap = math.max(buyGap, t - lastBuy) end
        lastBuy = t
    end
    local function new(what)
        news[#news + 1] = ("%s@%ds"):format(what, t)
        if t <= 600 then gaps[#gaps + 1] = t - last end
        last = t
    end
    local gifts, g = { "frenzy", "points", "warp" }, 0
    local order = { "inn", "clock", "mill", "hut", "bakery", "plaza", "fold", "workshop", "fountain", "observatory" }
    local per = {}
    print(("phase 2, a greedy player bringing %d DP, legacy x%.2f:"):format(dp, L.legacy))
    local dt, nextBuy, flowAt = 1 / 30, 0, nil
    while t < minutes * 60 do
        t = t + dt
        Lucid.step(L, dt, rand)
        for _, e in ipairs(Lucid.events) do
            if e.type == "flow" then flowAt = t; new("FLOW") end
            if e.type == "goldenAppears" and not per.golden then per.golden = true; new("golden") end
            if e.type == "nightmare" and not per.nightmare then per.nightmare = true; new("nightmare") end
        end
        Lucid.events = {}
        if L.golden and L.golden.t > 1.5 then
            Lucid.catchGolden(L)
            g = g % 3 + 1
            Lucid.choose(L, gifts[g])
        end
        if L.nightmare and L.nightmare.t > 35 then
            for _, sh in ipairs(L.nightmare.sheep) do sh.x, sh.y = L.nightmare.pen.x, L.nightmare.pen.y end
        end
        if t >= nextBuy then
            nextBuy = t + 1
            local budget = L.sheep * 0.5
            for k = #L.dims, 1, -1 do
                if Lucid.dimVisible(L, k) and not Lucid.autoOn(L, k) then
                    local was = L.dims[k].bought
                    local n = Lucid.buyDim(L, k, "max", budget / L.sheep > 0 and 0.5 or 0)
                    if was == 0 and n > 0 then new("D" .. k) end
                end
            end
            -- The building that's cheapest in seconds of income, if it's useful.
            local best, bs
            for _, id in ipairs(order) do
                local b = Lucid.BY[id]
                if not (b.max and L.built[id] >= b.max) then
                    local p = Lucid.price(L, id)
                    local secs = math.max(p.dp / math.max(1e-9, Lucid.dpPerSecond(L)), p.sheep / math.max(1e-9, Lucid.sheepRate(L)))
                    local useful = true
                    if id == "inn" then useful = Lucid.sheepRate(L) / Lucid.need(L) < Lucid.cap(L) end
                    if id == "clock" then useful = Lucid.sheepRate(L) / Lucid.need(L) >= Lucid.cap(L) * 0.5 end
                    if useful and (not bs or secs < bs) then best, bs = id, secs end
                end
            end
            -- A full town: level up the building where that does most.
            local free = false
            for c in pairs(L.open) do if not L.grid[c] then free = true end end
            local land = false
            for c = 1, D.grid.w * D.grid.h do if Lucid.canOpen(L, c) then land = true end end
            local upFirst = best and L.built[best] > 0 and not free
                and (not land or Lucid.price(L, best).dp < Lucid.plotPrice(L))
            if (not free and not land) or upFirst then
                local up, uv
                for c, id in pairs(L.grid) do
                    if Lucid.canUpgrade(L, c) and (id == best or (not upFirst and (id == "clock" or id == "bakery" or id == "mill"))) then
                        local v = Lucid.strength(L, c) / L.level[c] / Lucid.price(L, id).dp
                        if not uv or v > uv then up, uv = c, v end
                    end
                end
                if up then
                    Lucid.upgrade(L, up)
                    bought()
                    if L.level[up] == 2 and not per.up then per.up = true; new("level-up") end
                end
                best = nil
            end
            if best and Lucid.canBuild(L, best) then
                local cell, cv
                for c in pairs(L.open) do
                    if not L.grid[c] then
                        L.grid[c] = best
                        local v = Lucid.strength(L, c)
                        for _, d in ipairs({ 1, -1, D.grid.w, -D.grid.w }) do
                            if L.grid[c + d] then v = v + Lucid.strength(L, c + d) end
                        end
                        L.grid[c] = nil
                        if not cv or v > cv then cell, cv = c, v end
                    end
                end
                if cell then
                    local first = L.built[best] == 0
                    Lucid.build(L, best, cell)
                    bought()
                    per[best] = (per[best] or 0) + 1
                    if first then new(best) end
                else
                    for c = 1, D.grid.w * D.grid.h do
                        if Lucid.canOpen(L, c) and Lucid.openPlot(L, c) then new("land"); bought() break end
                    end
                end
            end
            Lucid.events = {}
        end
        if math.abs(t / 60 - math.floor(t / 60 + 0.5)) < dt / 120 and t > 1 then
            if os.getenv("DIMS") then
                local ds = {}
                for k, d in ipairs(L.dims) do ds[#ds + 1] = ("D%d %d/%s x%s"):format(k, d.bought, N.format(d.amount), N.format(Lucid.dimRate(L, k), true)) end
                local bs = {}
                for id, n in pairs(L.built) do if n > 0 then bs[#bs + 1] = id .. n end end
                print("      " .. table.concat(ds, "  ") .. "  | " .. table.concat(bs, " "))
            end
            print(("  %2d min  %8.2f runs/s  cap %-6s  %s DP/s  %s sheep/s  DP %s"):format(math.floor(t / 60 + 0.5),
                Lucid.runsPerSecond(L), N.format(Lucid.cap(L)), N.format(Lucid.dpPerSecond(L), true),
                N.format(Lucid.sheepRate(L), true), N.format(L.dp)))
        end
    end
    print("  new: " .. table.concat(news, " "))
    local most = 0
    for _, gp in ipairs(gaps) do most = math.max(most, gp) end
    print(("  first 10 min: %d new things, longest wait %ds, longest without buying in the town %ds; flow at %s"):format(
        #gaps, most, buyGap, flowAt and ("%.1f min"):format(flowAt / 60) or "never"))
end

if arg[1] == "lucid" then
    lucidSim(tonumber(arg[2]) or 30, tonumber(arg[3]) or 750, tonumber(arg[4]) or 7000)
    return
end

if arg[1] == "sim" then
    for _, r in ipairs({ 3, 1.5, 0.5 }) do sim(r) end
    nights(1.5, 12)
    return
end

local passed, failed = 0, 0
local function test(name, f)
    local ok, err = pcall(f)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function eq(a, b) assert(a == b, ("expected %s, got %s"):format(tostring(b), tostring(a))) end

test("format", function()
    eq(N.format(0), "0"); eq(N.format(999), "999"); eq(N.format(1234), "1.2K")
    eq(N.format(3.4e6), "3.4M"); eq(N.format(678e9), "678B"); eq(N.format(5.6e12), "5.6E12")
    eq(N.format(999999), "999K"); eq(N.format(1.5, true), "1.5")
end)
test("geometric costs", function()
    eq(N.sumGeometric(15, 1.15, 0, 1), 15)
    local n = N.maxAffordable(15, 1.15, 3, 1000)
    assert(N.sumGeometric(15, 1.15, 3, n) <= 1000 and N.sumGeometric(15, 1.15, 3, n + 1) > 1000)
end)
test("tap and buy", function()
    local s = Game.fresh()
    for _ = 1, 15 do Game.tap(s) end
    eq(s.sheep, 15)
    assert(Game.buy(s, "dog", "1"))
    eq(s.owned.dog, 1); eq(s.sheep, 0)
    assert(not Game.buy(s, "dog", "1"), "cannot afford the second")
    assert(Game.visible(s, "meadow") and not Game.visible(s, "pen"))
    eq(Game.teaser(s), "pen")
end)
test("max and the lullaby cap", function()
    local s = Game.fresh()
    s.sheep, s.runTotal = 1e12, 1e12
    local q = Game.buy(s, "lullaby", "max")
    eq(q.n, 5)
    assert(Game.quote(s, "lullaby", "1").maxed)
end)
test("production and drowsiness", function()
    local s = Game.fresh()
    s.owned.dog = 10
    Game.step(s, 1)
    eq(s.sheep, 10)
    s.runTotal = C.drowsiness.target
    s.runTime = C.prestige.paceRef -- a first night's length: no pace bonus
    Game.step(s, 1 / 30)
    assert(s.asleep)
    local dp = Game.dreamAgain(s)
    eq(dp, math.floor(math.sqrt((C.drowsiness.target + 10 + 10 / 30) / C.prestige.divisor)))
    eq(s.owned.dog, 0); eq(s.dreamPoints, dp)
end)
test("offline cap", function()
    local s = Game.fresh()
    s.owned.dog = 1
    local r = Game.offline(s, 24 * 3600)
    assert(r.capped); eq(r.secs, 8 * 3600)
end)
test("golden", function()
    local s = Game.fresh()
    s.goldenIn = 0.01
    Game.step(s, 1 / 30, function() return 0.5 end)
    assert(s.golden)
    local v = Game.catchGolden(s)
    eq(v, C.golden.minTaps)
end)
test("save round trip", function()
    local s = Game.fresh()
    s.owned.dog, s.sheep, s.dreamPoints = 4, 123, 7
    local back = Game.deserialize(Game.serialize(s))
    eq(back.owned.dog, 4); eq(back.sheep, 123); eq(back.dreamPoints, 7)
    eq(Game.deserialize({ owned = { dog = "x" }, buyMode = "weird" }).buyMode, "1")
end)
test("the pace bonus", function()
    local s = Game.fresh()
    s.runTotal, s.runTime = 1.5e9, C.prestige.paceRef
    eq(Game.pace(s), 1)
    s.runTime = C.prestige.paceRef / 2 ^ (1 / C.prestige.pacePower)
    assert(math.abs(Game.pace(s) - 2) < 1e-9)
    s.runTime = 0.01 -- counted as a second
    eq(Game.pace(s), math.min(C.prestige.paceMax, C.prestige.paceRef ^ C.prestige.pacePower))
end)
test("the dream shop", function()
    local s = Game.fresh()
    assert(not Game.visible(s, "sleepwalk"), "hidden before the first dream")
    s.dreamPoints, s.dreamEarned, s.dreams = 10, 10, 1
    assert(Game.buy(s, "deepSleep", "max"))
    eq(s.dream.deepSleep, 1); eq(s.dreamPoints, 5)
    eq(Game.globalMult(s), 2 * (1 + 10 * C.prestige.bonusPerPoint))
    assert(not Game.buy(s, "dreamCatcher", "1"), "too dear")
    s.dreamPoints = 1e6
    for _ = 1, 9 do Game.buy(s, "sleepwalk", "1") end
    eq(s.dream.sleepwalk, 5)
    Game.dreamAgain(s)
    eq(s.dream.deepSleep, 1) -- kept across nights
end)
test("sleepwalking and the auto-buyers", function()
    local s = Game.fresh()
    s.dream.sleepwalk = 1
    for _ = 1, 31 do Game.step(s, 1 / 30) end -- a second, and a step for rounding
    eq(s.sheep, 2)
    s.dream.nightShift = 1
    s.sheep = 1000
    s.autoIn = 0
    Game.step(s, 1 / 30)
    assert(s.owned.dog > 0, "the dog is bought")
    eq(s.owned.pen, 0)
    assert(s.sheep >= 1000 * (1 - 2 * C.auto.share), "a trip spends a share at a time")
    assert(not Game.automated(s, "barn") and Game.automated(s, "meadow") and not Game.automated(s, "pen"))
end)
test("warm bed", function()
    local s = Game.fresh()
    s.owned.dog, s.owned.os, s.owned.barn = 10, 3, 4
    s.dream.warmBed = 2
    Game.dreamAgain(s)
    eq(s.owned.dog, 4); eq(s.owned.os, 1); eq(s.owned.barn, 0) -- helpers only
    s.owned.dog, s.dream.warmBed = 7, 5
    Game.dreamAgain(s)
    eq(s.owned.dog, 7)
    assert(Game.visible(s, "meadow"), "the next helper shows")
end)
test("golden dreams", function()
    local s = Game.fresh()
    s.dream.goldenDreams = 1
    s.golden = { t = C.auto.goldenAfter, lane = 0.5 }
    Game.step(s, 1 / 30)
    assert(not s.golden and s.sheep >= C.golden.minTaps)
end)
test("lucid", function()
    local s = Game.fresh()
    s.runTotal, s.runTime = C.drowsiness.target, C.lucid.under / 2
    s.dreamPoints, s.dreamEarned = 100, 999
    Game.step(s, 1 / 30)
    assert(s.asleep and s.lucidNight)
    local dp = Game.goLucid(s)
    assert(dp > 0 and s.phase == "lucid" and not s.lucidNight and s.dreams == 1)
    eq(s.lucid.dp, 100 + dp); eq(s.dreamPoints, 0) -- the points come along
    eq(s.lucid.legacy, 1 + math.log10(1 + 999 + dp) * C.dream.legacyPerDecade)
    Game.step(s, 1)
    eq(s.runTime, 0) -- the night doesn't count in the lucid phase
    s = Game.deserialize(Game.serialize(s))
    eq(s.phase, "lucid"); eq(s.lucid.dp, 100 + dp)
    local o = Game.fresh()
    o.runTotal, o.owned.dog = C.drowsiness.target - 1, 1
    Game.offline(o, 3600)
    assert(o.asleep and not o.lucidNight, "a night slept offline doesn't count")
    eq(Game.deserialize({ lucid = true, phase = "weird" }).phase, "nights")
end)
test("save versions", function()
    -- A version-1 save still counting: untouched, and saved as version 2.
    local v1 = { version = 1, dreamPoints = 30, dreamEarned = 90, owned = { dog = 3 }, sheep = 50, phase = "nights" }
    local s = Game.deserialize(v1)
    eq(s.owned.dog, 3); eq(s.dreamPoints, 30); eq(s.phase, "nights"); eq(s.lucid, nil)
    eq(Game.serialize(s).version, C.saveVersion)
    -- A version-1 save in the placeholder: phase 2 begins with its points.
    s = Game.deserialize({ version = 1, phase = "lucid", dreamPoints = 340, dreamEarned = 9800, dreams = 22 })
    eq(s.phase, "lucid"); eq(s.lucid.dp, 340); eq(s.dreamPoints, 0); eq(s.dreams, 22)
    -- No version at all is 1.
    eq(Game.deserialize({ phase = "lucid", dreamPoints = 5 }).lucid.dp, 5)
end)
test("old saves and the dream shop", function()
    local back = Game.deserialize({ dreamPoints = 40, dream = { sleepwalk = 99, deepSleep = 2 } })
    eq(back.dreamEarned, 40); eq(back.dream.sleepwalk, 5); eq(back.dream.deepSleep, 2); eq(back.dream.tuckedIn, 0)
    local s = Game.fresh()
    s.dream.nightShift, s.dreamEarned = 2, 9
    back = Game.deserialize(Game.serialize(s))
    eq(back.dream.nightShift, 2); eq(back.dreamEarned, 9)
end)
test("the chain", function()
    local s = Game.fresh()
    s.owned.os = 10
    Game.step(s, 1)
    assert(math.abs(s.made.drones - 10 * Game.BY_ID.os.builds) < 1e-9, "Sheep-OS builds drones")
    eq(Game.quote(s, "drones", "1").cost, Game.BY_ID.drones.base) -- built ones don't raise the price
    s.made.drones = 0
    local before = Game.perSecond(s)
    s.made.drones = 5
    eq(Game.perSecond(s), before + 5 * Game.BY_ID.drones.rate * Game.globalMult(s))
    s.dream.warmBed = 5
    Game.dreamAgain(s)
    eq(s.made.drones, 0); eq(s.owned.os, 10) -- built helpers don't stay the night
end)
test("ways of sleeping", function()
    local s = Game.fresh()
    s.dreams, s.dreamPoints, s.dreamEarned = 1, 100, 100
    assert(not Game.buy(s, "lightSleeper", "1"), "opens on the second night")
    s.dreams = 2
    assert(Game.buy(s, "lightSleeper", "1") and Game.buy(s, "lightSleeper", "1"))
    eq(s.dreamPoints, 100 - 6 - 18)
    s.owned.dog = 10
    local base = Game.baseTap(s)
    eq(Game.tapValue(s), base) -- Sleepwalking's taps: no share
    eq(Game.tapValue(s, true), base + Game.perSecond(s) * 0.4)
    -- Turning over: the points come back, light is gone, heavy is in.
    local q = Game.quote(s, "heavySleeper", "1")
    assert(q.ok and q.turn)
    assert(Game.buy(s, "heavySleeper", "1"))
    eq(s.dream.lightSleeper, 0); eq(s.dream.heavySleeper, 1); eq(s.dreamPoints, 100 - 6)
    eq(Game.perSecond(s), 10 * 1.4 * Game.globalMult(s))
    s.goldenIn = 0.01
    Game.step(s, 1)
    assert(not s.golden, "a heavy sleeper sees no golden sheep")
end)
test("restless nights", function()
    local s = Game.fresh()
    s.dreams = 1
    s.owned.dog = 5
    assert(not Game.startChallenge(s, "insomnia"), "not open yet")
    s.dreams = 2
    assert(Game.startChallenge(s, "insomnia"))
    eq(s.owned.dog, 0); eq(s.challenge, "insomnia") -- the night starts over
    eq(Game.target(s), C.drowsiness.target * 4)
    s.runTotal, s.runTime = Game.target(s), 0.5
    Game.step(s, 1 / 30)
    assert(s.asleep and not s.lucidNight, "a restless night never goes lucid")
    local _, won = Game.dreamAgain(s)
    eq(won, "insomnia"); assert(Game.done(s, "insomnia") and not s.challenge)
    eq(Game.target(s), C.drowsiness.target / 2)
    assert(not Game.startChallenge(s, "insomnia"), "once is enough")
    -- Under Wide Awake the Dream shop's automation sleeps; Cold Feet hides the comforts.
    s.dreams, s.dream.sleepwalk, s.dream.nightShift = 5, 3, 1
    assert(Game.startChallenge(s, "wideAwake"))
    eq(Game.autoTaps(s), 0); assert(not Game.automated(s, "dog"))
    assert(Game.giveUp(s) and not s.challenge and Game.autoTaps(s) == 6)
    assert(Game.startChallenge(s, "coldFeet"))
    s.runTotal = 1e9
    assert(not Game.visible(s, "barn"))
    assert(Game.startChallenge(s, "shortage"), "one restless night for another")
    eq(Game.growthOf(s, Game.BY_ID.dog), 1.3); eq(Game.growthOf(s, Game.BY_ID.barn), 4)
    s.done.shortage, s.done.wideAwake, s.done.coldFeet, s.challenge = true, true, true, nil
    eq(Game.growthOf(s, Game.BY_ID.dog), 1.13)
    s.dream.deepSleep = 2
    s.owned.barn = 1
    eq(Game.globalMult(s), 9 * 1.5 * (1 + C.prestige.bonusPerPoint * s.dreamEarned))
    local back = Game.deserialize(Game.serialize(s))
    assert(back.done.shortage and back.done.insomnia and not back.done.bogus)
    s.challenge, s.made.pen = "coldFeet", 2.5
    back = Game.deserialize(Game.serialize(s))
    eq(back.challenge, "coldFeet"); eq(back.made.pen, 2.5)
    eq(Game.deserialize({ challenge = "bogus" }).challenge, nil)
end)
-- Phase 2 ----------------------------------------------------------------------------
local Lucid = require "lucid.game"
local Nightmare = require "lucid.nightmare"
local D = C.dream
local function close(a, b, tol) assert(math.abs(a - b) <= (tol or 1e-9) * math.max(1, math.abs(b)), ("expected %s, got %s"):format(b, a)) end

test("auto-wake: runs in batches", function()
    local L = Lucid.fresh({ dreamPoints = 0, dreamEarned = 0 })
    eq(Lucid.runsPerSecond(L), 1 / D.sheepPerRun) -- one Dream Sheep: a run a minute
    for _ = 1, 30 * 61 do Lucid.step(L, 1 / 30, function() return 0.5 end) end
    eq(L.runs, 1)
    close(L.dp, D.dpPerRun * L.legacy)
    -- A huge rate is still one batch a step, capped.
    L.dims[1].amount = 1e9
    eq(Lucid.runsPerSecond(L), D.runCap)
    local before = L.runs
    Lucid.step(L, 10, function() return 0.5 end) -- ten seconds in one step
    eq(L.runs - before, 10 * D.runCap)
end)
test("dimensions: the chain, prices, the bonus", function()
    local L = Lucid.fresh()
    L.sheep = 1e6
    eq(Lucid.buyDim(L, 2, 1), 1)
    eq(L.sheep, 1e6 - D.dims[2].base)
    assert(Lucid.dimVisible(L, 3) and not Lucid.dimVisible(L, 4))
    Lucid.step(L, 1)
    close(L.dims[1].amount, 1 + D.dims[2].rate) -- the Cloud Flock makes Dream Sheep
    L.dims[1].bought = 10
    close(Lucid.dimRate(L, 1), D.dims[1].rate * D.bonus) -- ten bought: x2
    L.sheep = 1e6
    local n = Lucid.buyDim(L, 1, "max")
    assert(n > 0 and L.sheep >= 0 and L.sheep < Lucid.dimCost(L, 1))
end)
test("the town: building, land, neighbours", function()
    local L = Lucid.fresh()
    L.dp, L.sheep = 1e9, 1e12
    local c = Lucid.cell(3, 3)
    assert(Lucid.build(L, "clock", c))
    assert(not Lucid.build(L, "clock", c), "one to a cell")
    assert(not Lucid.build(L, "clock", Lucid.cell(1, 1)), "not on closed land")
    eq(Lucid.cap(L), D.runCap * 2 ^ Lucid.BY.clock.capPower)
    -- Beside its own district: +25%. Beside a Plaza: +50%.
    assert(Lucid.build(L, "inn", Lucid.cell(4, 3)))
    eq(Lucid.strength(L, c), 1.25)
    assert(Lucid.build(L, "plaza", Lucid.cell(3, 2)))
    eq(Lucid.strength(L, c), 1.75)
    eq(Lucid.sum(L, "plaza"), 1) -- a Plaza beside nothing of its own district
    -- Moving is free; a closed cell opens beside open land, for points.
    assert(Lucid.move(L, c, Lucid.cell(2, 4)))
    eq(Lucid.strength(L, Lucid.cell(2, 4)), 1)
    assert(not Lucid.openPlot(L, Lucid.cell(5, 5)), "not touching")
    local dp = L.dp
    assert(Lucid.openPlot(L, Lucid.cell(5, 3)))
    eq(L.dp, dp - D.grid.plotBase)
    -- Levels: one more time its effect, priced as another one.
    local c2 = Lucid.cell(2, 4)
    local price = Lucid.price(L, "clock")
    assert(Lucid.upgrade(L, c2))
    eq(Lucid.strength(L, c2), 2); eq(L.built.clock, 2)
    eq(Lucid.price(L, "clock").dp, price.dp * Lucid.BY.clock.growth)
    local back = Lucid.deserialize(Lucid.serialize(L))
    eq(back.level[c2], 2); eq(back.built.clock, 2)
    -- Caps and locks.
    assert(Lucid.build(L, "hut", Lucid.cell(5, 3)))
    assert(not Lucid.canBuild(L, "hut") and not Lucid.canBuild(L, "lighthouse"))
    assert(not Lucid.canUpgrade(L, Lucid.cell(5, 3)), "an auto-buyer has no levels")
    assert(Lucid.autoOn(L, 2) and not Lucid.autoOn(L, 3))
    Lucid.toggleAuto(L, 2)
    assert(not Lucid.autoOn(L, 2))
end)
test("the lucid golden sheep", function()
    local L = Lucid.fresh()
    L.intro = false
    L.goldenIn = 0.01
    Lucid.step(L, 1 / 30, function() return 0.5 end)
    assert(L.golden and Lucid.catchGolden(L) and L.choosing)
    local base = Lucid.dimMult(L)
    Lucid.choose(L, "frenzy")
    close(Lucid.dimMult(L), base * D.golden.frenzy.mult)
    L.effects.frenzy = nil
    L.choosing = true
    local v = Lucid.choose(L, "points")
    eq(v, D.golden.points.least) -- nothing a second yet: the least
    L.choosing = true
    Lucid.choose(L, "warp")
    local t, before = L.dims[1].amount, L.sheepTotal
    L.effects.frenzy = nil
    Lucid.step(L, 1)
    close(L.dims[1].amount, t) -- D1 isn't made by anything; but sheep come twice as fast:
    close(L.sheepTotal - before, Lucid.sheepRate(L) * D.golden.warp.mult)
end)
test("nightmares: herding into the fold", function()
    local seed = 11
    local function rand() seed = (seed * 16807) % 2147483647 return seed / 2147483647 end
    -- Left alone, it passes, and nothing is won.
    local nm = Nightmare.new(6, 20, 1, rand)
    for _ = 1, 30 * 21 do Nightmare.update(nm, 1 / 30, rand) end
    assert(nm.done and not nm.won)
    -- A dog that circles behind the flock and pushes it to the fold.
    nm = Nightmare.new(6, 120, 1.6, rand)
    nm.cloud.x, nm.cloud.y = -1000, -1000 -- no cloud for this one
    local t = 0
    while not nm.done and t < 120 do
        local cx, cy, k = 0, 0, 0
        for _, s in ipairs(nm.sheep) do
            if not s.inPen then cx, cy, k = cx + s.x, cy + s.y, k + 1 end
        end
        if k > 0 then
            cx, cy = cx / k, cy / k
            local dx, dy = nm.pen.x - cx, nm.pen.y - cy
            local l = math.sqrt(dx * dx + dy * dy)
            Nightmare.point(nm, cx - dx / l * 34, cy - dy / l * 34)
        end
        Nightmare.update(nm, 1 / 30, rand)
        t = t + 1 / 30
    end
    assert(nm.done and nm.won, "herded in " .. t)
    eq(Nightmare.saved(nm), 1)
    -- In the rules: half-speed runs while it's on, a reward when won.
    local L = Lucid.fresh()
    L.intro, L.nightmareIn = false, 0.01
    L.dims[1].amount = 60
    Lucid.step(L, 1 / 30, rand)
    assert(L.nightmare)
    eq(Lucid.runsPerSecond(L), 1 * D.nightmare.slow)
    L.nightmare.done, L.nightmare.won = true, true
    for _, s in ipairs(L.nightmare.sheep) do s.inPen = true end
    L.nightmare.done = false
    L.nightmare.t = 0
    -- Mark it won the way update would: everyone in.
    for _, s in ipairs(L.nightmare.sheep) do s.x, s.y = L.nightmare.pen.x, L.nightmare.pen.y end
    local dp = L.dp
    Lucid.step(L, 1 / 30, rand)
    assert(not L.nightmare and L.dp > dp)
end)
test("away in closed form matches stepping", function()
    local function setup()
        local L = Lucid.fresh({ dreamPoints = 0, dreamEarned = 50 })
        L.intro, L.goldenIn, L.nightmareIn = false, 1e9, 1e9
        L.dims[1].amount, L.dims[2].amount, L.dims[3].amount = 5, 2, 1
        L.dims[1].bought, L.dims[2].bought, L.dims[3].bought = 5, 2, 1
        return L
    end
    local a, b = setup(), setup()
    local r = Lucid.offline(a, 600)
    for _ = 1, 600 * 30 do Lucid.step(b, 1 / 30) end
    close(a.dims[1].amount, b.dims[1].amount, 0.05)
    close(a.sheepTotal, b.sheepTotal, 0.05)
    close(a.runs, b.runs, 0.05)
    assert(r.secs == 600 and not r.capped)
    eq(Lucid.offline(setup(), 30 * 3600).secs, C.offline.maxHours * 3600)
end)
test("lucid saves", function()
    local L = Lucid.fresh({ dreamPoints = 12, dreamEarned = 100 })
    L.dp, L.sheep = 1e6, 1e6
    Lucid.build(L, "mill", Lucid.cell(3, 3))
    Lucid.openPlot(L, Lucid.cell(5, 3))
    Lucid.buyDim(L, 2, 3)
    L.autoOff[2] = true
    L.effects.warp = 12
    local back = Lucid.deserialize(Lucid.serialize(L))
    eq(back.grid[Lucid.cell(3, 3)], "mill"); eq(back.built.mill, 1)
    assert(back.open[Lucid.cell(5, 3)]); eq(back.plots, 1)
    eq(back.dims[2].bought, 3); eq(back.dp, L.dp); eq(back.legacy, L.legacy)
    assert(back.autoOff[2]); eq(back.effects.warp, 12)
    local json = require "lib.json"
    back = Lucid.deserialize(json.decode(json.encode(Lucid.serialize(L))))
    eq(back.grid[Lucid.cell(3, 3)], "mill")
    eq(Lucid.deserialize({ grid = { ["1"] = "lighthouse", ["2"] = "nope" } }).built.lighthouse, 0)
end)
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
