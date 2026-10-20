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
    Game.step(s, 1 / 30)
    assert(s.asleep and s.lucidNight)
    local dp = Game.goLucid(s)
    assert(dp > 0 and s.phase == "lucid" and not s.lucidNight and s.dreams == 1)
    Game.step(s, 1)
    eq(s.runTime, 0) -- nothing counts in the lucid phase
    s = Game.deserialize(Game.serialize(s))
    eq(s.phase, "lucid")
    Game.backToNights(s)
    s.runTotal, s.runTime = C.drowsiness.target, C.lucid.under / 2
    Game.step(s, 1 / 30)
    assert(s.lucidNight, "every short night goes lucid again until you go")
    local o = Game.fresh()
    o.runTotal, o.owned.dog = C.drowsiness.target - 1, 1
    Game.offline(o, 3600)
    assert(o.asleep and not o.lucidNight, "a night slept offline doesn't count")
    eq(Game.deserialize({ lucid = true, phase = "weird" }).phase, "nights")
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
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
