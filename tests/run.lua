-- The rules' tests and the balance sim, no LÖVE needed:
--   luajit tests/run.lua          the tests
--   luajit tests/run.lua sim      the sim: a greedy player at 3, 1.5 and 0.5 taps a second
package.path = "./?.lua;./lib/?.lua;" .. package.path

local Game = require "game"
local N = require "num"
local C = require "config"

local function sim(tapRate, dreamPoints)
    local s = Game.fresh()
    s.dreamPoints = dreamPoints or 0
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
            if Game.visible(s, it.id) then
                local q = Game.quote(s, it.id, "1")
                local v = not q.maxed and value(it.id) or 0
                if v > 0 then
                    local p = q.cost / v + q.cost / math.max(1, Game.perSecond(s) + Game.tapValue(s) * tapRate)
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
    print(("taps/s %.1f  asleep at %.1f min  total %s  DP %d"):format(tapRate, t / 60, N.format(s.runTotal), Game.dreamPointsFor(s)))
    print("  firsts: " .. table.concat(firsts, " "))
    print("  stages: " .. table.concat(stages, " "))
    print(("  first 5 min: %d purchases, longest wait %.1fs"):format(buys5, gaps))
end

if arg[1] == "sim" then
    for _, r in ipairs({ 3, 1.5, 0.5 }) do sim(r) end
    print("second night, with the first night's Dream Points:")
    sim(1.5, 122)
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
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
