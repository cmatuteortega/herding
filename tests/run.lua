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
-- Every two minutes it climbs with the bouncing sheep for half a minute (and
-- all the time under Thin Air), grows the cheapest root it can when that's
-- under a tenth of its points, and buys Sheep-OS, the Gate of Horn, as soon as it can.
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
    local order = { "inn", "clock", "mill", "hut", "bakery", "plaza", "fold", "workshop", "fountain", "observatory", "mirror" }
    local started = 0 -- when the dream challenge under way began
    local climbFrom = 0 -- when the climb under way began
    local tried = {} -- when each was last given up
    local per = {}
    print(("phase 2, a greedy player bringing %d DP, legacy x%.2f:"):format(dp, L.legacy))
    local dt, nextBuy, flowAt = 1 / 30, 0, nil
    while t < minutes * 60 do
        t = t + dt
        Lucid.step(L, dt, rand)
        for _, e in ipairs(Lucid.events) do
            if e.type == "challengeDone" then new(("%s(%ds)"):format(e.id, t - started)) end
            if e.type == "flow" and not flowAt then flowAt = t; new("FLOW") end
            if e.type == "goldenAppears" and not per.golden then per.golden = true; new("golden") end
            if e.type == "nightmare" and not per.nightmare then per.nightmare = true; new("nightmare") end
            if e.type == "fell" and e.record and e.height > 100 and not per["best" .. math.floor(e.height / 200)] then
                per["best" .. math.floor(e.height / 200)] = true; new(("best%d"):format(e.height))
            end
            if e.type == "grew" and e.rank == 1 then new("root:" .. e.id) end
            if e.type == "gate" then new("GATE") end
        end
        Lucid.events = {}
        -- Once the Mirror Lake stands, each dream challenge in turn: given up
        -- after six minutes, tried again ten minutes on.
        if L.challenge and t - started > 360 then
            tried[L.challenge] = t
            Lucid.giveUp(L)
            new("gaveUp")
        end
        if Lucid.mirror(L) and not L.challenge then
            for _, c in ipairs(Lucid.CHALLENGES) do
                if not Lucid.met(L, c.id) and t - (tried[c.id] or -1e9) > 600 and Lucid.startChallenge(L, c.id) then
                    started = t
                    break
                end
            end
        end
        -- The bouncing sheep.
        local B = L.bounce
        if not B.on and not L.nightmare and not os.getenv("NOCLIMB") and (t % 120 < dt or L.challenge == "skyHigh") then
            Lucid.hold(L, B.x); climbFrom = t
        end
        if B.on then
            Lucid.steer(L, require("lucid.bounce").bot(B))
            if t - climbFrom > 30 and L.challenge ~= "skyHigh" then require("lucid.bounce").stop(B) end
        end
        -- Counting sheep: every flock, a little late on every top (NOCOUNT: never).
        if L.flock and L.flock.t > 2 and not os.getenv("NOCOUNT") then Lucid.startSong(L) end
        if L.song then require("lucid.count").bot(L.song, 0.05) end
        if L.golden and L.golden.t > 1.5 then Lucid.catchGolden(L) end
        if L.choosing then -- a golden sheep caught, or a moon
            g = g % 3 + 1
            Lucid.choose(L, gifts[g])
        end
        -- (Nightmare Season's come thick and fast: herded in ten seconds, or lost.)
        if L.nightmare and L.nightmare.t > (L.challenge == "season" and 10 or 35) then
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
            -- The roots: the cheapest one open, if it's under a third of the points.
            local rb, rp
            for _, r in ipairs(Lucid.ROOTS) do
                if Lucid.rootState(L, r.id) == "open" and r.kind == "up" then
                    local pr = Lucid.rootPrice(L, r.id)
                    if not rp or pr < rp then rb, rp = r.id, pr end
                end
            end
            if not Lucid.openGate(L) and rb and rp <= L.dp / (os.getenv("NOROOTS") and 1e99 or 10) then Lucid.grow(L, rb) end
            for _, e in ipairs(Lucid.events) do
                if e.type == "grew" and e.rank == 1 then new("root:" .. e.id) end
                if e.type == "gate" then new("GATE") end
            end
            Lucid.events = {}
            if L.gate then break end
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
    local grown, all = Lucid.rootsGrown(L)
    local met = {}
    for _, c in ipairs(Lucid.CHALLENGES) do if Lucid.met(L, c.id) then met[#met + 1] = c.id end end
    print(("  roots %d/%d, best height %d, challenges met: %s; the gate %s"):format(grown, all, L.best,
        table.concat(met, " "), L.gate and ("open at %.1f min"):format(t / 60) or "shut"))
    local most = 0
    for _, gp in ipairs(gaps) do most = math.max(most, gp) end
    print(("  first 10 min: %d new things, longest wait %ds, longest without buying in the town %ds; flow at %s"):format(
        #gaps, most, buyGap, flowAt and ("%.1f min"):format(flowAt / 60) or "never"))
end

if arg[1] == "lucid" then
    lucidSim(tonumber(arg[2]) or 30, tonumber(arg[3]) or 750, tonumber(arg[4]) or 7000)
    return
end

-- Phase 3: a greedy player, from a fresh start. It goes
-- out and comes back at a strain of 0.8 by hand until the Silver Thread
-- (then sets it to 0.85), takes a breath on every tug, catches every comet
-- (for its Ether), lights every star it can, grows the cheapest upgrade
-- under a third of its Ether, and buys the dreamer that pays back soonest.
local function astralSim(minutes)
    local Astral = require "astral.game"
    local A = C.astral
    local P = Astral.fresh()
    P.intro = false
    local seed = 11
    local function rand() seed = (seed * 16807) % 2147483647 return seed / 2147483647 end
    local news, t, last, gaps = {}, 0, 0, {}
    local function new(what)
        news[#news + 1] = ("%s@%ds"):format(what, t)
        if t <= 900 then gaps[#gaps + 1] = t - last end
        last = t
    end
    print("phase 3, a greedy player:")
    local dt, nextBuy = 1 / 30, 0
    local banks, snaps = 0, 0
    while t < minutes * 60 and not P.cut do
        t = t + dt
        Astral.step(P, dt, rand)
        for _, e in ipairs(Astral.events) do
            if e.type == "found" then new("dreamer:" .. A.dreamers[e.k].id) end
            if e.type == "plane" and e.first then new("plane:" .. A.planes[e.k].id) end
            if e.type == "constellation" then new("lit:" .. e.id) end
            if e.type == "grew" and e.rank == 1 then new("up:" .. e.id) end
            if e.type == "bank" then banks = banks + 1 end
            if e.type == "snap" then snaps = snaps + 1 end
            if e.type == "tug" and rand() < 0.8 then Astral.breathe(P) end
        end
        Astral.events = {}
        if not Astral.threaded(P) then
            if P.out and Astral.strain(P) >= 0.8 then Astral.reelIn(P) end
        else
            P.autoAt = tonumber(os.getenv("AUTOAT")) or 0.85
        end
        if not P.out and P.rest <= 0 and not Astral.tranced(P) then Astral.project(P) end
        if P.comet and P.comet.t > 1 then Astral.catchComet(P) end
        if P.choosing then Astral.choose(P, "ether") end
        if t >= nextBuy then
            nextBuy = t + 1
            for _, c in ipairs(A.constellations) do while Astral.light(P, c.id) do end end
            local ub, up
            for _, u in ipairs(Astral.UPS) do
                if Astral.upState(P, u.id) == "open" then
                    local pr = Astral.upPrice(P, u.id)
                    if not up or pr < up then ub, up = u.id, pr end
                end
            end
            if ub and up <= P.ether / 3 then Astral.grow(P, ub) end
            -- The dreamer that pays back soonest, with a fifth of the Ether.
            local db, ds
            for k = 1, #A.dreamers do
                if Astral.found(P, k) then
                    local secs = Astral.dreamerCost(P, k) / Astral.dreamerRate(P, k)
                    if not ds or secs < ds then db, ds = k, secs end
                end
            end
            if db and Astral.dreamerCost(P, db) <= P.ether / 5 then
                if P.dreamers[db] == 0 then new("buy:" .. A.dreamers[db].id) end
                Astral.buyDreamer(P, db, 1)
            end
            if Astral.cutCord(P) then new("CUT") end
        end
        if math.abs(t / 60 - math.floor(t / 60 + 0.5)) < dt / 120 and t > 1 and math.floor(t / 60 + 0.5) % (minutes > 60 and 5 or 2) == 0 then
            local n = Astral.litCount(P)
            print(("  %2d min  cord %-7s reach %-7s %s E/s dreamers, %s E/s cord  E %s  lit %d  ups %d"):format(math.floor(t / 60 + 0.5),
                N.format(Astral.cord(P)), N.format(P.reach), N.format(Astral.dreamRate(P), true), N.format(P.cycleRate, true),
                N.format(P.ether), n, (Astral.upsGrown(P))))
        end
    end
    print("  new: " .. table.concat(news, " "))
    local most = 0
    for _, gp in ipairs(gaps) do most = math.max(most, gp) end
    print(("  %d projections, %d banked, %d snapped; first 15 min: %d new things, longest wait %ds; %s"):format(
        P.projections, banks, snaps, #gaps, most, P.cut and ("the cord cut at %.1f min"):format(t / 60) or "the cord holds"))
end

if arg[1] == "astral" then
    astralSim(tonumber(arg[2]) or 60)
    return
end

-- Phase 4's balance: a simple player (beyond/bot.lua) at a tap rate, the
-- rungs and generations as they come, and when the fence comes down.
local function beyondSim(tap)
    local Beyond = require "beyond.game"
    local Bot = require "beyond.bot"
    local seed = 7
    local function rand() seed = (seed * 16807) % 2147483647 return seed / 2147483647 end
    local b = Beyond.fresh()
    local t = 0
    print(("phase 4, a player whispering %.1f a second:"):format(tap))
    while not b.escaped and t < 4 * 3600 do
        t = t + 0.5
        Beyond.step(b, 0.5, rand)
        Bot.act(b, 0.5, rand, { tap = tap })
        for _, e in ipairs(Beyond.events) do
            if e.type == "rung" or e.type == "descend" or e.type == "cull" or e.type == "awake" or e.type == "seat" or e.type == "lost" then
                print(("  %4.1f min: %s %s (gen %d, %s Wits, %s Followers)"):format(t / 60, e.type,
                    e.rung and Beyond.RUNGS[e.rung].name or "", b.gen, N.format(b.wits), N.format(b.followers)))
            end
        end
        Beyond.events = {}
    end
    print(("  %s at %.1f min: %d sheep walked out, %d generations, %d taken by the Dogs"):format(
        b.escaped and "the fence is down" or "still in the line", t / 60, Beyond.flock(b), b.gen, b.culled))
    local l = b.loyal
    print(("  %d seats, loyalty lambs %.0f%% goats %.0f%% rams %.0f%% dogs %.0f%%"):format(b.seats, l.lambs * 100, l.goats * 100, l.rams * 100, l.dogs * 100))
end

if arg[1] == "beyond" then
    beyondSim(tonumber(arg[2]) or 1.5)
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
test("dream challenges", function()
    local L = Lucid.fresh()
    L.intro, L.goldenIn = false, 1e9
    L.dp, L.sheep = 1e12, 1e40
    assert(not Lucid.startChallenge(L, "onlyOne"), "not before the Mirror Lake")
    assert(Lucid.build(L, "mirror", Lucid.cell(3, 3)))
    assert(not Lucid.startChallenge(L, "onlyOne"), "not before the one above it in the roots")
    L.done.season, L.done.skyHigh = true, true -- the ones above Only One and Stopped Clocks
    assert(Lucid.build(L, "clock", Lucid.cell(2, 3)))
    for _ = 1, 15 do assert(Lucid.upgrade(L, Lucid.cell(2, 3))) end -- cap enough for 100 runs a second
    Lucid.buyDim(L, 1, 20)
    -- Starting wakes the flock; the town and the points stay.
    local dp = L.dp
    assert(Lucid.startChallenge(L, "onlyOne"))
    eq(L.dims[1].bought, D.startDims[1]); eq(L.sheep, 0); eq(L.dp, dp); eq(L.built.clock, 16)
    L.sheep = 1e20
    eq(Lucid.buyDim(L, 1, "max"), 1 - D.startDims[1]) -- one at most
    eq(Lucid.buyDim(L, 2, 10), 1)
    -- Met: 1e18 dream sheep counted under the rule.
    eq(select(2, Lucid.progress(L)), 18)
    L.dims[1].amount = 1e20
    Lucid.step(L, 1 / 30, function() return 0.5 end)
    assert(Lucid.met(L, "onlyOne") and not L.challenge)
    L.dims[1].bought = 10
    close(Lucid.dimRate(L, 1) / Lucid.dimMult(L), D.dims[1].rate * 2.5)
    -- Stopped Clocks: half strength, then a steeper cap.
    local cap, S = Lucid.cap(L), Lucid.sum(L, "clock")
    assert(Lucid.startChallenge(L, "stoppedClocks"))
    close(Lucid.cap(L), D.runCap * (1 + S / 2) ^ Lucid.BY.clock.capPower)
    assert(Lucid.giveUp(L) and not L.challenge)
    eq(Lucid.cap(L), cap)
    L.done.stoppedClocks = true
    close(Lucid.cap(L), D.runCap * (1 + S) ^ (Lucid.BY.clock.capPower + 0.15))
    -- Empty Squares: no neighbour helps; met, districts count double.
    L.sheep = 1e20 -- starting Stopped Clocks woke the flock
    L.done.falling = true -- the one above it
    assert(Lucid.build(L, "plaza", Lucid.cell(2, 2)))
    local c = Lucid.cell(2, 3)
    assert(Lucid.startChallenge(L, "emptySquares"))
    eq(Lucid.strength(L, c), 16)
    Lucid.giveUp(L)
    eq(Lucid.strength(L, c), 16 * 1.5)
    L.done.emptySquares = true
    L.sheep = 1e20
    assert(Lucid.openPlot(L, Lucid.cell(1, 3)) and Lucid.build(L, "inn", Lucid.cell(1, 3)))
    eq(Lucid.strength(L, c), 16 * (1.5 + 0.5))
    -- Nightmare Season: one after another; three brought home.
    L.done.season = nil
    assert(Lucid.startChallenge(L, "season"))
    eq(L.nightmareIn, Lucid.CH.season.nightmareEvery)
    for _ = 1, 3 do
        L.nightmareIn = 0.01
        Lucid.step(L, 1 / 30, function() return 0.5 end)
        assert(L.nightmare)
        for _, sh in ipairs(L.nightmare.sheep) do sh.x, sh.y = L.nightmare.pen.x, L.nightmare.pen.y end
        Lucid.step(L, 1 / 30, function() return 0.5 end)
        assert(not L.nightmare)
    end
    assert(Lucid.met(L, "season") and not L.challenge)
    assert(not Lucid.startChallenge(L, "season"), "once is enough")
    -- Kept in the save.
    L.challenge = "stoppedClocks"
    local back = Lucid.deserialize(require("lib.json").decode(require("lib.json").encode(Lucid.serialize(L))))
    eq(back.challenge, "stoppedClocks"); assert(back.done.season and back.done.onlyOne and not back.done.bogus)
end)
test("the upgrades: ranks, what they do, the gate", function()
    local L = Lucid.fresh()
    L.dp = 1e6
    -- Every upgrade is in a section, and has a picture; the first of each opens at once.
    local secs = {}
    for _, sec in ipairs(Lucid.SECTIONS) do secs[sec.id] = true end
    for _, r in ipairs(Lucid.ROOTS) do
        assert(secs[r.section], r.id .. " has no section")
        assert(r.kind == "challenge" or require("lucid.upgrades").ICON[r.id] or r.kind ~= "up", r.id .. " has no picture")
        if r.at then eq(Lucid.ROOT[r.at].section, r.section) end
    end
    for _, id in ipairs({ "spring", "bell", "quickdog", "totem", "architect", "surveyor" }) do eq(Lucid.rootState(L, id), "open") end
    eq(Lucid.rootState(L, "starbag"), "shut") -- after Springy Wool
    assert(not Lucid.grow(L, "starbag"))
    local p = Lucid.rootPrice(L, "spring")
    assert(Lucid.grow(L, "spring"))
    eq(L.dp, 1e6 - p); eq(Lucid.rank(L, "spring"), 1)
    eq(Lucid.rootPrice(L, "spring"), p * Lucid.ROOT.spring.growth)
    close(Lucid.bounceOpts(L).jump, 1 + Lucid.ROOT.spring.jumpAdd)
    eq(Lucid.rootState(L, "starbag"), "open")
    -- Up to its most, then full.
    for _ = 2, Lucid.ROOT.spring.max do assert(Lucid.grow(L, "spring")) end
    eq(Lucid.rootState(L, "spring"), "full"); assert(not Lucid.grow(L, "spring"))
    -- The Architect: sleepers cheaper. The Surveyor: land. The Market: wool.
    local cost, land, wool = Lucid.dimCost(L, 1), Lucid.plotPrice(L), Lucid.price(L, "clock").sheep
    assert(Lucid.grow(L, "architect")); close(Lucid.dimCost(L, 1), cost / 1.5)
    assert(Lucid.grow(L, "surveyor")); close(Lucid.plotPrice(L), land * 0.8)
    assert(Lucid.grow(L, "market")); close(Lucid.price(L, "clock").sheep, wool * 0.5)
    -- Too poor: poor.
    L.dp = 0
    eq(Lucid.rootState(L, "well"), "poor")
    -- The taproot: shut until the lake, a challenge open once the one above it is mastered.
    eq(Lucid.rootState(L, "lake"), "shut"); eq(Lucid.rootState(L, "c.season"), "shut")
    L.built.mirror = 1
    eq(Lucid.rootState(L, "lake"), "full"); eq(Lucid.rootState(L, "c.season"), "open")
    eq(Lucid.rootState(L, "c.stoppedClocks"), "shut")
    assert(not Lucid.grow(L, "c.season"), "a challenge is started, not grown")
    -- Lucidity: a step for each challenge mastered. The gate, Sheep-OS on
    -- the farm, once it's at its most.
    L.dp, L.sheep = 1e12, 1e100
    L.done = {}
    local n, all = Lucid.lucidity(L)
    eq(n, 0); eq(all, #Lucid.CHALLENGES); assert(not Lucid.lucid(L))
    for _, c in ipairs(Lucid.CHALLENGES) do if c.id ~= "emptySquares" then L.done[c.id] = true end end
    eq(Lucid.lucidity(L), all - 1)
    eq(Lucid.rootState(L, "gate"), "shut")
    assert(not Lucid.canBuild(L, "lighthouse") and not Lucid.openGate(L), "not before lucidity's at its most")
    L.done.emptySquares = true
    assert(Lucid.lucid(L))
    eq(Lucid.rootState(L, "gate"), "open")
    assert(not Lucid.grow(L, "gate"), "the gate is bought on the farm")
    assert(not Lucid.build(L, "lighthouse", Lucid.cell(3, 3)), "it takes no plot")
    Lucid.events = {}
    local dp = L.dp
    assert(Lucid.openGate(L) and L.gate)
    eq(L.dp, dp - Lucid.BY.lighthouse.dp)
    eq(Lucid.events[#Lucid.events].type, "gate")
    eq(Lucid.rootState(L, "gate"), "full")
    assert(not Lucid.openGate(L), "once")
    -- Kept in the save, through JSON.
    local json = require "lib.json"
    local back = Lucid.deserialize(json.decode(json.encode(Lucid.serialize(L))))
    eq(back.roots.spring, Lucid.ROOT.spring.max); eq(back.roots.architect, 1); assert(back.gate)
    eq(Lucid.deserialize({ roots = { spring = 99, nope = 2, gate = 1 } }).roots.spring, Lucid.ROOT.spring.max)
    eq(Lucid.deserialize({ roots = { gate = 1 } }).roots.gate, nil)
    -- The games' own: a quicker dog, a slower cloud, a slower golden sheep.
    local G2 = Lucid.fresh()
    G2.roots.quickdog, G2.roots.nightlight, G2.roots.slowgold = 2, 1, 1
    close(Lucid.nightmareOpts(G2).dog, 1 + 2 * Lucid.ROOT.quickdog.dogAdd)
    close(Lucid.nightmareOpts(G2).cloud, 1 / (1 + Lucid.ROOT.nightlight.cloudCut))
    close(Lucid.crossTime(G2), D.golden.crossTime * (1 + Lucid.ROOT.slowgold.crossAdd))
    local nm = Nightmare.new(4, 10, 1, math.random, Lucid.nightmareOpts(G2))
    close(nm.dogSpeed, Nightmare.CONFIG.dogSpeed * Lucid.nightmareOpts(G2).dog)
end)
test("counting sheep: on the beat, off it, what it pays", function()
    local Count = require "lucid.count"
    local P = D.count
    local dt = 1 / 120
    -- On every top: all perfect, the combo the whole flock, full marks.
    local song = Count.new()
    local beats = 0
    while not song.done do
        Count.step(song, dt)
        Count.bot(song, 0)
        for _, e in ipairs(song.events) do if e.type == "beat" then beats = beats + 1 end end
        song.events = {}
    end
    eq(song.perfect, P.sheep); eq(song.best, P.sheep); eq(Count.share(song), 1)
    eq(beats, P.sheep + P.lead) -- a tick on every top, and the count-in
    -- The beat quickens.
    assert(song.sheep[P.sheep].at - song.sheep[P.sheep - 1].at < song.sheep[2].at - song.sheep[1].at)
    -- A little late: good, not perfect. Too late: missed.
    song = Count.new()
    while not song.done do Count.step(song, dt); Count.bot(song, (P.perfect + P.good) / 2) end
    eq(song.good, P.sheep); close(Count.share(song), P.goodScore)
    song = Count.new()
    while not song.done do Count.step(song, dt) end
    eq(song.missed, P.sheep); eq(Count.share(song), 0)
    -- A tap with no sheep near: off the beat, and the combo goes.
    song = Count.new()
    while song.t < 0 do Count.step(song, dt) end
    Count.tap(song); eq(song.combo, 1)
    while song.t < (song.sheep[1].at + song.sheep[2].at) / 2 do Count.step(song, dt) end
    eq(Count.tap(song), "stray"); eq(song.combo, 0)
    -- A wider window (Slow Song) takes what was a miss.
    song = Count.new(2)
    while song.t < 0 do Count.step(song, dt) end
    while song.t < P.good * 1.5 do Count.step(song, dt) end
    eq(Count.tap(song), "good")

    -- In the dream: a flock comes, waits, and goes if left.
    local L = Lucid.fresh()
    L.intro = false
    L.nightmareIn = 1e9
    local function run(secs) for _ = 1, math.floor(secs * 30 + 0.5) do Lucid.step(L, 1 / 30) end end
    run(P.firstDelay + 0.1)
    assert(L.flock, "a flock at the fence")
    -- Left alone, it goes; Sheep Bells bring the next one sooner.
    L.roots.bell = 2
    run(P.wait)
    assert(not L.flock and not L.song, "left alone, it goes")
    assert(L.flockIn <= P.maxDelay / (1 + 2 * Lucid.ROOT.bell.flockAdd) + 1e-9)
    -- Tapped: the song, no climbing while it's on, then the pay and the tune.
    L.flockIn = 0
    run(0.1)
    assert(L.flock)
    Lucid.hold(L, 50); run(0.5)
    assert(L.bounce.on)
    local cap, value = Lucid.cap(L), Lucid.songValue(L)
    assert(Lucid.startSong(L) and L.song and not L.flock)
    assert(not L.bounce.on, "the climb stops for the song")
    Lucid.hold(L, 50); assert(not L.bounce.held)
    local dp = L.dp
    Lucid.events = {}
    while L.song do
        Lucid.step(L, 1 / 120)
        if L.song then Count.bot(L.song, 0) end
    end
    local over
    for _, e in ipairs(Lucid.events) do if e.type == "songOver" then over = e end end
    assert(over and over.share == 1)
    close(L.dp - dp, value, 1e-6 + 0.01 * value) -- a little more from runs while it played
    assert(L.dp - dp >= value)
    close(Lucid.cap(L), cap * (1 + P.tune.cap))
    eq(L.effects.tune, P.tune.seconds)
    -- The tune passes.
    run(P.tune.seconds + 1)
    close(Lucid.cap(L), cap)
    -- Kept in the save: the wait for the next flock, the tune; not the song.
    L.effects.tune, L.tuneMult = 20, 1.5
    L.flock = { t = 3 }
    local json = require "lib.json"
    local back = Lucid.deserialize(json.decode(json.encode(Lucid.serialize(L))))
    eq(back.flock, nil); eq(back.song, nil); eq(back.effects.tune, 20); eq(back.tuneMult, 1.5)
end)
test("the bouncing sheep: hops, climbs, falls, pays", function()
    local Bounce = require "lucid.bounce"
    local seed = 3
    local function rand() seed = (seed * 16807) % 2147483647 return seed / 2147483647 end
    -- Left alone, it hops on its cloud and never climbs.
    local B = Bounce.new()
    for _ = 1, 30 * 5 do Bounce.step(B, 1 / 30, rand) end
    assert(not B.on and B.y >= 0 and B.y <= Bounce.apex() + 1)
    -- Held, it climbs; the bot steering, it gets well up.
    Bounce.press(B, 50)
    local best, t = 0, 0
    while B.on and t < 60 do
        Bounce.move(B, Bounce.bot(B))
        Bounce.step(B, 1 / 30, rand)
        best, t = math.max(best, B.height), t + 1 / 30
    end
    assert(best > 150, "climbed " .. best)
    -- Let go and steered nowhere, it falls off the bottom and the climb ends.
    B = Bounce.new()
    Bounce.press(B, 50)
    Bounce.release(B)
    local fell
    for _ = 1, 30 * 30 do
        Bounce.step(B, 1 / 30, rand)
        for _, e in ipairs(B.events) do if e.type == "fell" then fell = e end end
        B.events = {}
        if fell then break end
    end
    assert(fell and not B.on, "it fell")
    -- In the rules: a star pays, a climb's height is the best, the best lifts every layer.
    local L = Lucid.fresh()
    L.intro, L.goldenIn, L.nightmareIn = false, 1e9, 1e9
    local base = Lucid.dimMult(L)
    Lucid.hold(L, 50)
    local stars = 0
    for _ = 1, 30 * 40 do
        if L.bounce.on then Lucid.steer(L, Bounce.bot(L.bounce)) end
        Lucid.step(L, 1 / 30, rand)
        for _, e in ipairs(Lucid.events) do if e.type == "star" then stars = stars + 1 end end
        Lucid.events = {}
        if not L.bounce.on then break end
        if L.bounce.height > 120 then Lucid.hold(L, nil); L.bounce.aim = 0 end
    end
    assert(L.best > 100, "best " .. L.best)
    assert(stars > 0 and L.dp >= stars * D.bounce.starLeast, "stars paid")
    close(Lucid.recordMult(L), 1 + D.bounce.recordPer * L.best / 100)
    assert(Lucid.dimMult(L) > base)
    eq(Lucid.deserialize(Lucid.serialize(L)).best, L.best)
    -- A nightmare ends the climb.
    Lucid.hold(L, 50)
    L.nightmareIn = 0.001
    Lucid.step(L, 1 / 30, rand)
    assert(L.nightmare and not L.bounce.on)
    -- Thin Air: half-width clouds; its goal is a climb.
    L.nightmare = nil
    L.built.mirror = 1
    L.done.season, L.done.stoppedClocks = true, true
    assert(Lucid.startChallenge(L, "skyHigh"))
    close(Lucid.bounceOpts(L).width, 0.5)
    L.climbed = 300
    Lucid.step(L, 1 / 30, rand)
    assert(Lucid.met(L, "skyHigh"))
end)
test("shallow sleep and falling", function()
    local L = Lucid.fresh()
    L.intro, L.goldenIn, L.nightmareIn = false, 1e9, 1e9
    L.dp, L.sheep = 1e9, 1e30
    assert(Lucid.build(L, "hut", Lucid.cell(2, 3)))
    assert(Lucid.build(L, "mirror", Lucid.cell(3, 3)))
    for _, id in ipairs({ "season", "stoppedClocks", "skyHigh", "onlyOne" }) do L.done[id] = true end
    assert(Lucid.startChallenge(L, "shallow"))
    L.sheep = 1e30
    for k = 1, 3 do assert(Lucid.buyDim(L, k, 1) == 1) end
    eq(Lucid.buyDim(L, 4, 1), 0) -- the fourth layer doesn't dream
    eq(Lucid.dimRate(L, 4), 0)
    L.done.shallow, L.challenge = true, nil
    close(Lucid.dimRate(L, 1) / Lucid.dimMult(L), D.dims[1].rate * 3)
    -- Falling: no auto-buyers while it lasts; mastered, every layer x2.
    assert(Lucid.autoOn(L, 1))
    assert(Lucid.startChallenge(L, "falling"))
    assert(not Lucid.autoOn(L, 1))
    Lucid.giveUp(L)
    local m = Lucid.dimMult(L)
    L.done.falling = true
    close(Lucid.dimMult(L), m * 2)
end)
test("astral projection: through the gate, and saves", function()
    local s = Game.fresh()
    s.phase, s.lucid = "lucid", Lucid.fresh(s)
    assert(not Game.goAstral(s), "not before the gate")
    s.lucid.gate = true
    s.lucid.runs = 1e6
    assert(Game.goAstral(s)); eq(s.phase, "astral")
    assert(s.astral, "phase 3 starts")
    s.astral.ether = 77
    local json = require "lib.json"
    local back = Game.deserialize(json.decode(json.encode(Game.serialize(s))))
    eq(back.phase, "astral"); assert(back.lucid and back.lucid.gate); eq(back.astral.ether, 77)
    assert(not Game.goAstral(back), "the gate opens one way")
    -- The Librarian's ranks, in a save from before, come back as the Third Eye's.
    eq(require("astral.game").deserialize({ ups = { librarian = 3, lens = 1 } }).ups.eye, 3)
    eq(Game.deserialize({ version = 4, phase = "astral" }).phase, "nights") -- no dream to have left
    -- The placeholder's save (version 3, "void") comes in as astral projection, fresh.
    back = Game.deserialize({ version = 3, phase = "void", lucid = { dp = 5, gate = true } })
    eq(back.phase, "astral"); eq(back.lucid.dp, 5); eq(N.toNumber(back.astral.ether), 0); eq(back.version, C.saveVersion)
    -- A version 2 save comes in as it was.
    back = Game.deserialize({ version = 2, phase = "lucid", lucid = { dp = 5 } })
    eq(back.phase, "lucid"); eq(back.lucid.dp, 5); eq(back.lucid.best, 0); eq(back.astral, nil)
    -- Beyond: only with the cord cut, and back to the stars.
    s = back
    s.lucid.gate = true
    Game.goAstral(s)
    assert(not Game.goBeyond(s))
    s.astral.cut = true
    assert(Game.goBeyond(s)); eq(s.phase, "beyond")
    back = Game.deserialize(json.decode(json.encode(Game.serialize(s))))
    eq(back.phase, "beyond")
    -- Phase 4's state comes back whole, and a bad one comes back clean.
    assert(s.beyond and s.beyond.count > 0, "the Count has begun")
    s.beyond.mine, s.beyond.bad, s.beyond.wits, s.beyond.gen = 3, 1, 1234, 2
    back = Game.deserialize(json.decode(json.encode(Game.serialize(s))))
    eq(back.beyond.mine, 3); eq(back.beyond.bad, 1); eq(back.beyond.wits, 1234); eq(back.beyond.gen, 2)
    eq(#back.beyond.pen, #s.beyond.pen)
    back = Game.deserialize({ version = 4, phase = "beyond", lucid = { gate = true }, astral = { cut = true }, beyond = { count = -5, mine = "x", pen = "no" } })
    eq(back.beyond.count, 0); eq(back.beyond.mine, 0); eq(back.beyond.bad, 0); eq(#back.beyond.pen, 3)
    -- The old tally (before the Registry) still loads, with a pen.
    back = Game.deserialize({ version = 4, phase = "beyond", lucid = { gate = true }, astral = { cut = true } })
    eq(back.phase, "beyond"); eq(#back.beyond.pen, 3)
    eq(Game.handoff(back), nil)
    back.beyond.escaped, back.beyond.out = true, { flock = 9, workers = {} }
    eq(Game.handoff(back).flock, 9)
    assert(Game.backToStars(back)); eq(back.phase, "astral"); eq(back.astral.cut, false)
end)
test("astral projection: the cord", function()
    local Astral = require "astral.game"
    local A = C.astral
    local P = Astral.fresh()
    P.intro = false
    local function never() return 0.999 end -- no tug for a while (tugs come at tugMax)
    assert(Astral.project(P)); assert(P.out)
    eq(Astral.project(P), false)
    -- Out: further, faster, and Ether gathered, not banked.
    Astral.step(P, 1, never)
    local d1 = P.dist
    Astral.step(P, 1, never)
    assert(P.dist - d1 > d1, "the further, the faster")
    assert(N.toNumber(P.gathered) > 0); eq(N.toNumber(P.ether), 0)
    close(Astral.strain(P), (P.dist / A.cord) ^ 2)
    -- Back: banked with the close call, then a rest.
    local s = Astral.strain(P)
    local want = N.toNumber(P.gathered) * (1 + A.closeCall * s ^ 3)
    close(N.toNumber(Astral.reelIn(P)), want)
    close(N.toNumber(P.ether), want)
    assert(not P.out and P.rest > 0); eq(Astral.project(P), false)
    Astral.step(P, A.rest + 0.1, never)
    -- Out until it snaps: half kept, a longer rest.
    assert(Astral.project(P))
    local before = N.toNumber(P.ether)
    local snapped
    for _ = 1, 3000 do
        Astral.step(P, 1 / 30, never)
        for _, e in ipairs(Astral.events) do if e.type == "snap" then snapped = e end end
        Astral.events = {}
        if snapped then break end
    end
    assert(snapped and not P.out, "it snaps"); eq(P.snaps, 1)
    close(N.toNumber(P.ether) - before, N.toNumber(snapped.value)); eq(P.rest, A.snapRest)
    -- A tug: half at once, the rest coming, and a breath calms it.
    Astral.step(P, A.snapRest + 0.1, never)
    Astral.project(P)
    P.tugIn = 0
    Astral.step(P, 1 / 30, function() return 1 end)
    assert(P.tug > 0 and P.tugLeft > 0)
    local tug = P.tug
    assert(Astral.breathe(P)); close(P.tug, tug * (1 - A.steady))
    -- The Silver Thread brings you back at its strain; the Trance takes you out.
    P.ups.thread, P.ups.trance = 1, 1
    Astral.setAuto(P, 0.5)
    for _ = 1, 3000 do Astral.step(P, 1 / 30, never) if not P.out then break end end
    assert(not P.out and P.snaps == 1, "back by itself, before the snap")
    Astral.step(P, A.rest + 0.1, never)
    assert(P.out, "out again by itself")
    Astral.setAuto(P, 2); eq(P.autoAt, A.autoMax)
end)
test("astral projection: dreamers, stars, the comet, the end", function()
    local Astral = require "astral.game"
    local A = C.astral
    local P = Astral.fresh()
    eq(Astral.mult(P), 1)
    P.ether = 1e30
    -- Dreamers: found by reach, and they dream only while you're out.
    eq(Astral.buyDreamer(P, 2), 0)
    eq(Astral.buyDreamer(P, 1, 3), 3)
    eq(N.toNumber(Astral.gatherRate(P)), 0)
    P.reach = A.dreamers[2].at
    eq(Astral.buyDreamer(P, 2), 1)
    Astral.project(P)
    assert(N.toNumber(Astral.gatherRate(P)) > N.toNumber(Astral.etherRate(P)))
    -- Constellations: in order, by plane, a star at a time; a reward when whole.
    local aries, crook, lamb = A.constellations[1], A.constellations[2], A.constellations[3]
    assert(not Astral.light(P, crook.id), "not before Aries")
    local m = Astral.mult(P)
    for _ = 1, #aries.stars do assert(Astral.light(P, aries.id)) end
    assert(Astral.done(P, aries.id)); close(Astral.mult(P), m * aries.etherMult)
    for _ = 1, #crook.stars do assert(Astral.light(P, crook.id)) end
    assert(not Astral.light(P, lamb.id), "the Lamb's stars are in the Astral")
    P.reach = A.planes[lamb.plane].at
    assert(Astral.light(P, lamb.id))
    -- Upgrades: in order, kept.
    assert(not Astral.grow(P, "trance")); assert(Astral.grow(P, "thread")); assert(Astral.grow(P, "trance"))
    local cord = Astral.cord(P)
    assert(Astral.grow(P, "cord")); close(Astral.cord(P), cord * Astral.UP.cord.cordMult)
    assert(Astral.grow(P, "lens"))
    m = Astral.mult(P)
    assert(Astral.grow(P, "eye")); assert(Astral.grow(P, "eye")); close(Astral.mult(P), m * Astral.UP.eye.etherMult ^ 2)
    -- The comet: caught, a gift.
    P.comet = { t = 0, lane = 0.5 }
    assert(Astral.catchComet(P)); assert(P.choosing)
    Astral.choose(P, "wind")
    assert(P.effects.wind)
    -- The end: every constellation lit, then the cord cut.
    assert(not Astral.cutCord(P))
    P.reach = 1e30
    for _, c in ipairs(A.constellations) do while Astral.light(P, c.id) do end end
    assert(Astral.cutCord(P)); assert(P.cut and P.paid)
    P.cut = false
    P.ether = 0
    assert(Astral.canCut(P), "paid once, the cut is free again")
    -- Saves.
    local json = require "lib.json"
    local back = Astral.deserialize(json.decode(json.encode(Astral.serialize(P))))
    eq(back.dreamers[2], 1); eq(back.lit[aries.id], #aries.stars); eq(back.ups.trance, 1); eq(back.reach, 1e30)
    assert(back.paid and back.effects.wind)
    -- Away: with the Thread and the Trance, the cord runs on at a share.
    P.cycleRate, P.out = 100, false
    local r = Astral.offline(P, 1000)
    close(N.toNumber(r.ether), 100 * 1000 * A.awayShare)
end)
-- Phase 4 with everything on the screen opened (the tests that aren't about opening).
local function opened(b)
    for _, id in ipairs(require("beyond.game").UNLOCKS) do b.open[id] = true end
    return b
end
test("beyond: it opens bit by bit", function()
    local Beyond = require "beyond.game"
    local K = C.beyond
    local b = Beyond.fresh()
    -- At first the line and a jump: nothing else works, or shows.
    for _, id in ipairs(Beyond.UNLOCKS) do assert(not Beyond.isOpen(b, id)) end
    assert(not Beyond.whisper(b), "no whispering yet")
    b.ready = true
    assert(not Beyond.breed(b, b.pen[1].id, b.pen[2].id), "no Registry yet")
    b.followers = 1e9
    assert(not Beyond.grow(b, "mutagen"), "no splices yet")
    for _ = 1, K.unlock.whisper - 1 do Beyond.comply(b) end
    Beyond.step(b, 0.1); assert(not Beyond.isOpen(b, "whisper"))
    Beyond.comply(b)
    Beyond.step(b, 0.1)
    assert(Beyond.isOpen(b, "whisper")); assert(not Beyond.isOpen(b, "wits"))
    local opens = {}
    for _, e in ipairs(Beyond.events) do if e.type == "open" then opens[#opens + 1] = e.id end end
    eq(table.concat(opens, ","), "whisper"); Beyond.events = {}
    assert(Beyond.whisper(b))
    -- Wits and the race after a few more; the pen at its Wits; splices once Followers came; the council at its rung.
    for _ = 1, K.unlock.wits do Beyond.comply(b) end
    Beyond.step(b, 0.1); assert(Beyond.isOpen(b, "wits")); assert(not Beyond.isOpen(b, "pen"))
    b.wits = K.unlock.pen
    Beyond.step(b, 0.1); assert(Beyond.isOpen(b, "pen"))
    assert(not Beyond.isOpen(b, "splice"), "not enough Followers yet")
    b.followersEver = K.unlock.splice
    Beyond.step(b, 0.1); assert(Beyond.isOpen(b, "splice"))
    assert(Beyond.grow(b, "mutagen"))
    assert(not Beyond.isOpen(b, "council")); eq(Beyond.upState(b, "lessons"), "shut")
    b.wits = K.rungs[K.unlock.council].at
    Beyond.step(b, 0.1); assert(Beyond.isOpen(b, "council"))
    assert(Beyond.breed(b, b.pen[1].id, b.pen[2].id))
    -- For good, and saved.
    b.wits = 0
    Beyond.step(b, 0.1)
    local back = Beyond.deserialize(require("lib.json").decode(require("lib.json").encode(Beyond.serialize(b))))
    for _, id in ipairs(Beyond.UNLOCKS) do assert(Beyond.isOpen(back, id), id) end
    -- A save from before the gating, well along, has it all; a new one doesn't.
    back = Beyond.deserialize({ time = 600 })
    for _, id in ipairs(Beyond.UNLOCKS) do assert(Beyond.isOpen(back, id), id) end
    back = Beyond.deserialize({ time = 5 })
    assert(not Beyond.isOpen(back, "whisper"))
end)
test("beyond: the pen, the genes, the Count", function()
    local Beyond = require "beyond.game"
    local Bot = require "beyond.bot"
    local K = C.beyond
    local seed = 11
    local function rand() seed = (seed * 16807) % 2147483647 return seed / 2147483647 end
    local b = opened(Beyond.fresh())
    eq(#b.pen, #K.founders); eq(b.count, K.count0); eq(b.gen, 1); eq(Beyond.ceiling(b), K.ceil0)
    -- Wits: Wit to the power, Memory on top.
    local sh = b.pen[1]
    sh.g.wit, sh.g.memory = 4, 5
    close(Beyond.sheepWits(sh), 4 ^ K.witPow * (1 + K.memoryWits * 5))
    -- Time: Wits and the Count both go up.
    local w, c = b.wits, b.count
    Beyond.step(b, 10, rand)
    assert(b.wits > w, "Wits rise"); close(b.count - c, K.countRate * 10)
    -- Whispers: Followers, a cooldown, a little suspicion.
    local f = b.followers
    assert(Beyond.whisper(b)); assert(b.followers > f); assert(not Beyond.whisper(b), "the cooldown")
    Beyond.step(b, K.whisperCool + 0.01, rand)
    assert(Beyond.whisper(b))
    -- A good jump calms the Dogs and feeds the Count; a bad one the Dogs.
    b.suspicion = 0.5
    local before = b.count
    Beyond.comply(b); close(b.suspicion, 0.5 - K.jumpCalm); close(b.count - before, K.jumpFeed); eq(b.mine, 1)
    Beyond.misstep(b); eq(b.bad, 1); close(b.suspicion, 0.5 - K.jumpCalm + K.badSus)
    -- Breeding: not before the lamb is ready, then a lamb under the ceiling, from the parents' genes.
    local a, c2 = b.pen[1], b.pen[2]
    assert(not Beyond.breed(b, a.id, c2.id, rand), "not ready")
    Beyond.step(b, K.lambEvery, rand)
    assert(b.ready); assert(not Beyond.breed(b, a.id, a.id, rand), "two different parents")
    local n = #b.pen
    assert(Beyond.breed(b, a.id, c2.id, rand)); eq(#b.pen, n + 1); eq(b.born, 1); assert(not b.ready)
    local lamb = b.pen[#b.pen]
    for _, g in ipairs(Beyond.GENES) do
        assert(lamb.g[g.id] >= 0 and lamb.g[g.id] <= Beyond.ceiling(b))
        assert(math.abs(lamb.g[g.id] - a.g[g.id]) <= math.abs(a.g[g.id] - c2.g[g.id]) + 1, "a gene from a parent, a step off at most")
    end
    -- A full pen: the dullest not a parent goes to the flock.
    b.ups.pen = 0
    while #b.pen < Beyond.penMax(b) do b.pen[#b.pen + 1] = { id = b.nextId, name = "X", gen = 1, g = { wit = 0, voice = 0, nerve = 0, memory = 0, wool = 0 } }; b.nextId = b.nextId + 1 end
    b.ready = true
    local walked = b.walked
    assert(Beyond.breed(b, a.id, c2.id, rand)); eq(#b.pen, Beyond.penMax(b)); eq(b.walked, walked + 1)
    assert(Beyond.sheepById(b, a.id) and Beyond.sheepById(b, c2.id), "the parents stay")
    -- Twins.
    b.ups.twins = 2; eq(Beyond.lambs(b), 3)
    b.ups.twins = 0
end)
test("beyond: the Dogs", function()
    local Beyond = require "beyond.game"
    local K = C.beyond
    local b = opened(Beyond.fresh())
    b.pen[1].g.wit, b.pen[1].g.wool = 6, 0
    b.pen[2].g.wit, b.pen[2].g.wool = 6, 0
    b.pen[3].g.wit, b.pen[3].g.wool = 6, 0
    assert(Beyond.exposure(b) == 6)
    local rise = Beyond.suspicionRise(b)
    for _, sh in ipairs(b.pen) do sh.g.nerve = 4 end
    assert(Beyond.suspicionRise(b) < rise, "nerve excuses")
    for _, sh in ipairs(b.pen) do sh.g.nerve, sh.g.wool = 0, 6 end
    eq(Beyond.exposure(b), 0); eq(Beyond.suspicionRise(b), 0)
    -- Wool hides the wits: nothing rises.
    Beyond.step(b, 600)
    eq(b.suspicion, 0)
    -- Bright and woolless: the warning, then the brightest is taken.
    for _, sh in ipairs(b.pen) do sh.g.wool = 0 end
    b.pen[2].g.wit = 9
    local brightest = b.pen[2].id
    local warned, culled
    for _ = 1, 4000 do
        Beyond.step(b, 1)
        for _, e in ipairs(Beyond.events) do
            if e.type == "warn" then warned = true end
            if e.type == "cull" then culled = e.sheep end
        end
        Beyond.events = {}
        if culled then break end
    end
    assert(warned and culled); eq(culled.id, brightest); eq(b.culled, 1); close(b.suspicion, K.cullTo, 0.05)
    -- Never the last two.
    b.pen = { b.pen[1], b.pen[2] }
    b.suspicion = 1
    Beyond.step(b, 1)
    eq(#b.pen, 2)
end)
test("beyond: splices and motions", function()
    local Beyond = require "beyond.game"
    local K = C.beyond
    local b = opened(Beyond.fresh())
    -- Shut until the rung; then bought with Followers, dearer each rank, up to the max.
    eq(Beyond.upState(b, "lessons"), "shut"); assert(not Beyond.canGrow(b, "lessons"))
    b.followers = 1e9
    assert(Beyond.grow(b, "mutagen")); eq(Beyond.rank(b, "mutagen"), 1)
    assert(Beyond.upPrice(b, "mutagen") > K.ups[1].base)
    b.rung = 6
    local m = Beyond.witMult(b)
    assert(Beyond.grow(b, "lessons")); close(Beyond.witMult(b), m * Beyond.UP.lessons.mult)
    for _ = 1, 20 do Beyond.grow(b, "gestation") end
    eq(Beyond.rank(b, "gestation"), Beyond.UP.gestation.max); eq(Beyond.upState(b, "gestation"), "full")
    assert(Beyond.lambTime(b) < K.lambEvery)
    assert(not Beyond.grow(b, "gestation"), "full")
    -- The Registry, ours: it pairs by itself, once the Council has seats.
    assert(not Beyond.grow(b, "registry"), "no seat yet"); eq(Beyond.upWaits(b, "registry"), "NEEDS SEAT 2")
    b.seats = 2
    assert(Beyond.grow(b, "registry"))
    b.ready = true
    local born = b.born
    Beyond.step(b, 1)
    eq(b.born, born + 1)
    -- The Rally.
    assert(not Beyond.canRally(b)); assert(Beyond.grow(b, "rally")); assert(Beyond.canRally(b))
    assert(Beyond.setCourt(b, "dogs")) -- (the lambs' gift would drift with the wait)
    local v = Beyond.whisperValue(b)
    assert(Beyond.rally(b)); close(Beyond.whisperValue(b), v * K.rallyMult); assert(not Beyond.canRally(b))
    Beyond.step(b, K.rallyTime + 1)
    close(Beyond.whisperValue(b), v)
end)
test("beyond: generations and the end", function()
    local Beyond = require "beyond.game"
    local K = C.beyond
    local seed = 5
    local function rand() seed = (seed * 16807) % 2147483647 return seed / 2147483647 end
    local b = opened(Beyond.fresh())
    assert(not Beyond.canDescend(b))
    b.pen[1].g.wit = K.ceil0
    assert(Beyond.canDescend(b))
    local w = Beyond.witMult(b)
    local elder = b.pen[1]
    assert(Beyond.descend(b, rand))
    eq(b.gen, 2); eq(Beyond.ceiling(b), K.ceil0 + K.ceilStep); eq(#b.hall, 1); eq(b.hall[1], elder)
    eq(#b.pen, #K.founders); assert(Beyond.witMult(b) > w, "the elder's Wits stay")
    for _, sh in ipairs(b.pen) do assert(sh.g.wit <= K.ceil0 * K.heirShare + 1, "the heirs start lower") end
    -- The ladder, and the Count passed.
    eq(Beyond.rungOf(b), 1)
    b.wits = K.rungs[3].at; eq(Beyond.rungOf(b), 3)
    b.wits = b.count + 1000
    Beyond.step(b, 0.1, rand)
    assert(b.awake); eq(Beyond.rungOf(b), #K.rungs); eq(Beyond.progress(b), 1)
    local frozen = b.count
    Beyond.step(b, 10, rand); eq(b.count, frozen)
    -- The vote needs the Followers, and a majority of the Council.
    assert(not Beyond.canVote(b))
    b.followers = K.voteNeed
    assert(not Beyond.canVote(b), "no seats")
    b.seats = K.voteSeats
    b.workers = { wit = 4, voice = 3, nerve = 2, memory = 1, wool = 0 }
    assert(Beyond.canVote(b)); assert(Beyond.vote(b))
    assert(b.escaped and b.out and b.out.flock == Beyond.flock(b) and #b.out.names == #b.pen + #b.hall)
    -- The handoff: every sheep a class, the pen and the elders with those gone.
    local total = 0
    for _, g in ipairs(Beyond.GENES) do total = total + b.out.workers[g.id] end
    eq(total, 10 + #b.pen + #b.hall); eq(b.out.seats, K.voteSeats)
    local t = b.time
    Beyond.step(b, 5, rand); eq(b.time, t) -- over
    -- It all comes back from a save.
    local json = require "lib.json"
    local back = Beyond.deserialize(json.decode(json.encode(Beyond.serialize(b))))
    assert(back.escaped and back.awake); eq(back.out.flock, b.out.flock); eq(#back.hall, 1); eq(back.hall[1].name, elder.name)
    eq(back.gen, 2); eq(back.nextId, b.nextId); eq(back.out.seats, K.voteSeats); eq(back.out.workers.wit, b.out.workers.wit)
    -- A bad one is cleaned up.
    back = Beyond.deserialize({ pen = { { id = 3, name = 5, g = { 99, -4, "x" } } }, ups = { lessons = 99, nope = 1 }, escaped = true })
    eq(#back.pen, 1); eq(back.pen[1].g.voice, 0); eq(back.ups.lessons, Beyond.UP.lessons.max); assert(not back.escaped, "an end with no flock isn't one")
    back = Beyond.deserialize(nil); eq(#back.pen, #K.founders)
end)
test("beyond: the flocks", function()
    local Beyond = require "beyond.game"
    local K = C.beyond
    local b = opened(Beyond.fresh())
    eq(b.court, "lambs"); assert(Beyond.flockOpen(b, "lambs")); assert(not Beyond.flockOpen(b, "rams"))
    assert(not Beyond.setCourt(b, "rams"), "not yet"); assert(not Beyond.setCourt(b, "nobody"))
    -- Whispers win the court's flock over, a share each; the others stay as they were.
    local v = Beyond.whisperValue(b)
    assert(Beyond.whisper(b))
    close(b.loyal.lambs, v / (K.loyaltyBase * K.flocks[1].resist)); eq(b.loyal.goats, 0)
    -- The gifts, at full loyalty.
    b.rung = 6
    b.loyal = { lambs = 0, goats = 0, rams = 0, dogs = 0 }
    b.pen[1].g.wit, b.pen[1].g.voice = 6, 3
    local w, sus, fall, rate = Beyond.whisperValue(b), Beyond.suspicionRise(b), Beyond.suspicionFall(b), Beyond.followerRate(b)
    b.loyal = { lambs = 1, goats = 1, rams = 1, dogs = 1 }
    close(Beyond.whisperValue(b), w * (1 + K.lambsWhisper), 1e-9)
    close(Beyond.suspicionRise(b), sus * (1 - K.goatsCalm))
    close(Beyond.suspicionFall(b), fall * (1 + K.dogsForget))
    close(Beyond.followerRate(b), rate * (1 + K.ramsRate), 1)
    -- Harder flocks take longer; loyalty stops at 1; the Followers that come on their own count.
    b.loyal = { lambs = 0, goats = 0, rams = 0, dogs = 0 }
    assert(Beyond.setCourt(b, "dogs"))
    b.pen[1].g.voice = 5
    Beyond.step(b, 100)
    assert(b.loyal.dogs > 0 and b.loyal.dogs < 1); eq(b.loyal.lambs, 0)
    b.loyal.dogs = 0.99999; b.followers = 0
    Beyond.whisper(b)
    eq(b.loyal.dogs, 1)
end)
test("beyond: the Council's elections", function()
    local Beyond = require "beyond.game"
    local K = C.beyond
    local E = K.election
    local seed = 4
    local function rand() seed = (seed * 16807) % 2147483647 return seed / 2147483647 end
    local b = opened(Beyond.fresh())
    eq(Beyond.electionState(b), "locked")
    b.rung = E.at
    eq(Beyond.electionState(b), "poor"); assert(not Beyond.run(b, rand))
    b.followers = 1e9
    eq(Beyond.electionState(b), "open")
    local cost = Beyond.electionCost(b)
    assert(Beyond.run(b, rand)); close(b.followers, 1e9 - cost); eq(Beyond.electionState(b), "on")
    assert(not Beyond.run(b, rand), "one at a time")
    -- Not bleating: the rival wins it, and there's a wait.
    local lost
    for _ = 1, 1000 do
        Beyond.step(b, 0.1, rand)
        for _, e in ipairs(Beyond.events) do if e.type == "lost" then lost = true end end
        Beyond.events = {}
        if not b.election then break end
    end
    assert(lost); eq(b.seats, 0); assert(b.electionCool > 0); eq(Beyond.electionState(b), "wait")
    Beyond.step(b, E.cooldown + 1, rand)
    -- Bleating: the support climbs, a bleat has a cooldown, and the win is a seat.
    assert(Beyond.run(b, rand))
    assert(Beyond.bleat(b)); assert(not Beyond.bleat(b), "the cooldown")
    local m = Beyond.witMult(b)
    local won
    for _ = 1, 2000 do
        Beyond.step(b, 0.05, rand)
        if b.election then
            if b.election.smear then Beyond.swat(b) end
            b.election.bleatCool = 0
            Beyond.bleat(b); Beyond.bleat(b)
        end
        for _, e in ipairs(Beyond.events) do if e.type == "seat" then won = true end end
        Beyond.events = {}
        if not b.election then break end
    end
    assert(won); eq(b.seats, 1); close(Beyond.witMult(b), m * K.seatWits)
    -- A smear unswatted costs support.
    b.electionCool = 0
    assert(Beyond.run(b, rand))
    b.election.smear = { t = 0, x = 0.5 }
    local before = b.election.support
    Beyond.step(b, E.smearWindow + 0.1, rand)
    assert(b.election.support < before - E.smearHit * 0.9)
    -- The rival pulls harder with every seat; all five is the most.
    assert(Beyond.rivalPull(b) > E.rival)
    b.election = nil
    b.seats = K.seatsMax
    eq(Beyond.electionState(b), "full")
    -- A speech isn't saved; seats and the wait are.
    b.electionCool = 12
    local back = Beyond.deserialize(require("lib.json").decode(require("lib.json").encode(Beyond.serialize(b))))
    eq(back.seats, K.seatsMax); eq(back.election, nil); close(back.electionCool, 12)
end)
test("beyond: time away", function()
    local Beyond = require "beyond.game"
    local K = C.beyond
    local b = opened(Beyond.fresh())
    eq(Beyond.offline(b, K.awayMin - 1), nil)
    b.pen[1].g.wit, b.pen[2].g.wit = 6, 6
    local wits, count = b.wits, b.count
    local r = Beyond.offline(b, 3600)
    assert(r and r.wits > 0 and b.wits > wits and r.count > 0)
    close(b.count - count, K.countRate * 3600 * K.awayShare, 1e-6)
    -- The Dogs wait, however bright the pen.
    for _, sh in ipairs(b.pen) do sh.g.wit, sh.g.wool = 8, 0 end
    Beyond.offline(b, 6 * 3600)
    assert(b.suspicion < K.warnAt); eq(b.culled, 0)
    -- A cap; and nothing once out.
    r = Beyond.offline(b, 30 * 3600)
    assert(r.capped); close(r.secs, K.awayHours * 3600)
    b.escaped = true
    eq(Beyond.offline(b, 3600), nil)
end)
test("beyond: a bot plays it through", function()
    local Beyond = require "beyond.game"
    local Bot = require "beyond.bot"
    local seed = 7
    local function rand() seed = (seed * 16807) % 2147483647 return seed / 2147483647 end
    local b = Beyond.fresh()
    local t = 0
    while not b.escaped and t < 3 * 3600 do
        t = t + 0.5
        Beyond.step(b, 0.5, rand)
        Bot.act(b, 0.5, rand, { tap = 1.5 })
        Beyond.events = {}
    end
    assert(b.escaped, "a player who taps gets out within three hours")
    assert(t > 20 * 60 and t < 90 * 60, ("in an hour or so, not %d minutes"):format(t / 60))
    assert(b.gen >= 3)
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
    back = Lucid.deserialize({ grid = { ["1"] = "lighthouse", ["2"] = "nope" } })
    eq(back.built.lighthouse, 0); eq(back.grid[1], nil) -- Sheep-OS takes no plot
    back = Lucid.deserialize(json.decode(json.encode({ gate = true })))
    assert(back.gate and not Lucid.canBuild(back, "lighthouse"), "the gate stays open, and once is enough")
end)
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
