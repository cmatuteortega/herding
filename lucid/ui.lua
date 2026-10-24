-- The lucid dream's screen: everything round the field (lucid/scene.lua) in
-- phase 2, drawn the way ui.lua draws phase 1 (flat fills in a one-pixel ink
-- edge, the 3x5 face, dithers for anything soft).
--
-- On top, the Dream Points; under the field, auto-wake: how fast the night
-- runs itself, until it runs too fast to see. Then three tabs: LAYERS (the
-- six dream layers, a dream within a dream), FARM (the city builder: a grid
-- of land, buildings placed, moved and levelled up, the next plot bought; it
-- rebuilds phase 1's barn and field on the dream's hill) and UPGRADES (kept
-- for good, in sections like the farm's: one for each of the dream's games,
-- then the layers and the farm, then the dream challenges and the Gate of
-- Horn). The field also holds the dream's games: hold it and the bouncing
-- sheep climbs; tap a flock waiting at the fence and count it over on the
-- beat. The golden sheep's choice, the nightmares, the way in, the way out
-- and the time away are dialogs and banners.
--
-- ui.lua hands everything over to this once `phase` is "lucid".

local G = require "gfx"
local N = require "num"
local C = require "config"
local Lucid = require "lucid.game"
local LScene = require "lucid.scene"
local Models = require "models"
local Upgrades = require "lucid.upgrades"
local Audio = require "audio"
local flux = require "lib.flux"
local lume = require "lib.lume"

local floor, min, max, sin = math.floor, math.min, math.max, math.sin
local D = C.dream

local LUI = {}
LUI.save = function() end -- set by ui.lua
LUI.resetAll = function() end -- set by ui.lua

local S, L -- the game's state, and its lucid part
local vw, vh = 320, 240
local R = {}
local t = 0
local reduced = false
local portrait = true

local tab = "layers" -- or "town", "upgrades"
local buyMax = false
local rows, contentH, scroll, scrollV = {}, 0, 0, 0
local press = nil
local dogHeld = nil -- the pointer herding the dog
local bounceHeld = nil -- the pointer steering the bouncing sheep
local banner = { y = 1, text = nil, sub = nil, till = 0 }
local modal = nil -- { title, lines, big, buttons = { { label, fn } }, night, y }
local sel, place, moving = nil, nil, nil -- the town: a cell picked, a building to put down, one being moved
local intro = nil -- the way in: { t }
local outro = nil -- the way out, through the Gate of Horn: { t }
local challengeSeen = {} -- dream challenges looked at on UPGRADES, so the tab's mark goes
local runQuiet = 0 -- the run chime: not again until then, so it isn't constant

function LUI.setState(s)
    S, L = s, s.lucid
    modal, banner.text, scroll, sel, place, moving, intro, outro = nil, nil, 0, nil, nil, nil, nil, nil
    dogHeld, bounceHeld = nil, nil
    challengeSeen = {}
    tab = "layers"
    LScene.reset()
end
function LUI.setReduced(v) reduced = v; LScene.reduced = v end

local function rect(x, y, w, h) return { x = floor(x), y = floor(y), w = floor(w), h = floor(h) } end
local function inside(r, x, y) return r and x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h end

function LUI.fit(w, h, inset)
    vw, vh = w, h
    local l, top, r, b = inset.l + 3, inset.t + 2, vw - inset.r - 3, vh - inset.b - 2
    R.top = rect(l, top, r - l, 13)
    R.mute = rect(r - 17, top, 17, 13)
    R.motion = rect(r - 37, top, 17, 13)
    R.reset = rect(r - 57, top, 17, 13)
    local y = top + 16
    if vh >= vw * 1.15 then
        portrait = true
        local sh = max(110, floor((b - y) * 0.42))
        R.scene = rect(l + 1, y, r - l - 2, sh)
        R.wake = rect(l, y + sh + 5, r - l, 9)
        R.tabs = rect(l, R.wake.y + 14, r - l, 13)
        R.panel = rect(l, R.tabs.y + 17, r - l, b - (R.tabs.y + 17))
    else
        portrait = false
        local pw = lume.clamp(floor((r - l) * 0.42), 160, 230)
        local sx = r - pw
        R.scene = rect(l + 1, y, sx - l - 7, b - y - 16)
        R.wake = rect(l, R.scene.y + R.scene.h + 5, sx - l - 5, 9)
        R.tabs = rect(sx, y, pw, 13)
        R.panel = rect(sx, y + 17, pw, b - (y + 17))
    end
    LScene.resize(R.scene.w, R.scene.h)
end

function LUI.sceneRect() return R.scene end

--- what happens --------------------------------------------------------------------------

local function cue(name, data) Audio.cue(name, data) end
local RUN_GAP = 6 -- seconds between run chimes, at the least

function LUI.banner(text, sub)
    banner.text, banner.sub, banner.till = text, sub, t + 2.8
    banner.y = 1
    flux.to(banner, reduced and 0.01 or 0.35, { y = 0 }):ease("backout")
end

local function showModal(m)
    m.y = reduced and 0 or 24
    modal = m
    flux.to(m, 0.45, { y = 0 }):ease("backout")
end

local function closeModal(i)
    local m = modal
    modal = nil
    local b = m and m.buttons[i or 1]
    if b and b.fn then b.fn() end
end

local function duration(secs)
    secs = floor(secs)
    local h, m, s = floor(secs / 3600), floor(secs % 3600 / 60), secs % 60
    if h > 0 then return ("%dH %dM"):format(h, m) end
    if m > 0 then return ("%dM %dS"):format(m, s) end
    return ("%dS"):format(s)
end

-- The golden sheep's three gifts.
local function giftChoice()
    local G0 = D.golden
    local pts = N.max(N.mul(Lucid.dpPerSecond(L), N.from(G0.points.seconds)), N.from(G0.points.least))
    showModal({
        title = "A GOLDEN DREAM",
        lines = { "THE GOLDEN SHEEP OFFERS YOU ONE THING. CHOOSE:" },
        big = "ONE OF THREE",
        buttons = {
            { label = "X" .. G0.frenzy.mult .. " FOR " .. G0.frenzy.seconds .. "S", fn = function() Lucid.choose(L, "frenzy") end },
            { label = "+" .. N.format(pts) .. " DP NOW", fn = function() Lucid.choose(L, "points") end },
            { label = "TIME X" .. G0.warp.mult .. " FOR " .. G0.warp.seconds .. "S", fn = function() Lucid.choose(L, "warp") end },
        },
    })
end

-- The way in: phase 1's last night closes, the dream opens violet, a word,
-- then what's new. Called right after Game.goLucid.
function LUI.enter()
    Audio.setAsleep(false)
    Audio.setLucid(true)
    cue("lucid")
    LScene.reset()
    intro = { t = 0 }
    if reduced then intro.t = 3.2 end
end

-- What changed: shown once the way in is over (and again if you quit before).
local function explain()
    showModal({
        night = true,
        title = "LUCID DREAMING",
        lines = {
            "YOU KNOW YOU ARE DREAMING NOW, SO THE NIGHT RUNS ITSELF: EACH TIME THE DREAM SHEEP COUNT ENOUGH, YOU WAKE, AND DREAM AGAIN.",
            "",
            "LAYERS: A DREAM WITHIN A DREAM, SIX DEEP. EACH LAYER DREAMS UP THE SLEEPERS OF THE ONE ABOVE IT, AND DEEPER DOWN TIME RUNS FASTER.",
            "",
            "FARM: REBUILD THE FIELD AND THE BARN YOU DREAMT OF, WITH YOUR DREAM POINTS. WHERE EACH PIECE STANDS MATTERS. UPGRADES: WHAT YOU KEEP FOR GOOD.",
            "",
            "HOLD THE FIELD AND THE SHEEP IN FRONT CLIMBS. WHEN A FLOCK WAITS AT THE FENCE, TAP IT AND COUNT THEM OVER ON THE BEAT. AND IF A NIGHTMARE COMES, THE DOG KNOWS WHAT TO DO.",
        },
        big = "YOU DREAM THEM",
        buttons = { { label = "DREAM", fn = function() L.intro = false; LUI.save() end } },
    })
end

-- The way out: the Gate of Horn opens, the dream drains away, the void.
-- Then ui.lua hands over (LUI.toVoid).
function LUI.leave()
    if outro or S.phase ~= "lucid" then return end
    modal, dogHeld, bounceHeld = nil, nil, nil
    Lucid.hold(L, nil)
    outro = { t = reduced and C.void.outro - 2.5 or 0 }
    cue("void")
    LUI.save()
end
LUI.toVoid = function() end -- set by ui.lua

-- Coming back to a lucid save.
function LUI.resume()
    Audio.setLucid(true)
    if L.intro then explain() end
end

function LUI.away(seconds)
    if L.intro then return end
    local r = Lucid.offline(L, seconds)
    Lucid.events = {}
    if not r or seconds < C.offline.minSeconds then return end
    showModal({
        title = "WHILE YOU WERE DREAMING...",
        lines = {
            "THE NIGHT RAN ITSELF FOR " .. duration(r.secs) .. (r.capped and (" (" .. C.offline.maxHours .. " HOURS AT MOST)") or "") .. ".",
            N.format(r.runs) .. " RUNS AND " .. N.format(r.sheep) .. " DREAM SHEEP.",
        },
        big = "+" .. N.format(r.dp) .. " DP",
        buttons = { { label = "BACK TO THE DREAM" } },
    })
end

-- The rules' events: banners, sounds, the field's effects.
function LUI.drain()
    local ev = Lucid.events
    Lucid.events = {}
    for _, e in ipairs(ev) do
        if e.type == "runs" then
            -- While a song is on, the fence is the song's.
            if not L.song then
                LScene.runs(e.n, e.value, L.flow)
                if not L.flow and t >= runQuiet then cue("run"); runQuiet = t + RUN_GAP end
            end
        elseif e.type == "flow" then
            LUI.banner("NO NIGHT. ONLY DREAM.", "THE RUNS ARE TOO QUICK TO SEE")
            cue("stage")
        elseif e.type == "dim" and e.first then
            if e.k > 1 then LUI.banner("LAYER " .. e.k .. ": " .. D.dims[e.k].name:upper(), "A DREAM WITHIN A DREAM") end
            cue("buy", { tier = e.k, first = true })
        elseif e.type == "built" then
            LScene.built(e.cell)
            if e.id == "mirror" then
                LUI.banner("THE DREAM CHALLENGES OPEN", "ON UPGRADES, AT THE BOTTOM")
            elseif e.first then
                local b = Lucid.BY[e.id]
                LUI.banner("NEW: " .. b.name:upper(), b.desc:upper())
            end
        elseif e.type == "upgraded" then
            LScene.upgraded(e.cell)
        elseif e.type == "grew" then
            if e.rank == 1 then
                local r = Lucid.ROOT[e.id]
                LUI.banner(r.name:upper(), r.desc:upper())
            end
        elseif e.type == "gate" then
            LUI.leave()
        elseif e.type == "star" then
            local x, y = LScene.bounceAt(L)
            LScene.float("+" .. N.format(e.value) .. " DP", x, y - 10, "y")
            cue("star")
        elseif e.type == "moon" then
            cue("goldenAppears")
            LScene.flash()
        elseif e.type == "boing" then
            cue("boing")
        elseif e.type == "fell" then
            bounceHeld = nil
            if e.record and e.height >= 10 then
                LUI.banner("NEW BEST: " .. floor(e.height) .. " HIGH", "EVERY LAYER X" .. N.format(Lucid.recordMult(L), true) .. ", FOR GOOD")
                cue("safe")
            end
        elseif e.type == "goldenAppears" then
            cue("goldenAppears")
        elseif e.type == "gift" then
            cue("gift")
            LScene.flash()
            local G0 = D.golden
            if e.id == "points" then LUI.banner("+" .. N.format(e.value) .. " DREAM POINTS", "A GOLDEN DREAM")
            elseif e.id == "frenzy" then LUI.banner("EVERYTHING X" .. G0.frenzy.mult, "FOR " .. G0.frenzy.seconds .. " SECONDS")
            else LUI.banner("TIME X" .. G0.warp.mult, "FOR " .. G0.warp.seconds .. " SECONDS") end
        elseif e.type == "challengeStart" then
            local c = Lucid.CH[e.id]
            LUI.banner("DREAM: " .. c.name:upper(), c.rule:upper())
            cue("stage")
        elseif e.type == "challengeDone" then
            local c = Lucid.CH[e.id]
            LUI.banner("MASTERED: " .. c.name:upper(), c.reward:upper())
            cue("safe")
            LScene.flash()
        elseif e.type == "flock" then
            LUI.banner("SHEEP AT THE FENCE", "TAP THEM: COUNT THEM OVER")
            cue("bleat")
        elseif e.type == "songStart" then
            bounceHeld = nil
            LScene.fx.hoppers = {}
            LUI.banner("COUNTING SHEEP", "TAP AS EACH ONE TOPS THE FENCE")
        elseif e.type == "count" then
            if e.what == "beat" then cue("beat")
            elseif e.what == "perfect" or e.what == "good" then
                cue("tap" .. min(10, e.combo))
                LScene.counted(e.what)
            else
                cue("bleat")
                LScene.counted(e.what)
            end
        elseif e.type == "songOver" then
            local T = D.count.tune
            if e.share > 0 then
                LUI.banner(("COUNTED: %d%%"):format(floor(e.share * 100 + 0.5)),
                    "+" .. N.format(e.value) .. " DP. RUNS CAP X" .. N.format(L.tuneMult, true) .. " FOR A WHILE")
                cue("safe")
                LScene.flash()
            else
                LUI.banner("THEY WANDERED OFF", "NONE COUNTED. THEY'LL BE BACK")
            end
        elseif e.type == "nightmare" then
            LUI.banner("A NIGHTMARE!", "DRAG THE DOG: HERD THEM INTO THE FOLD")
            cue("nightmare")
        elseif e.type == "nightmareOver" then
            dogHeld = nil
            if e.won then
                LUI.banner("THE FLOCK IS SAFE", "+" .. N.format(e.value) .. " DREAM POINTS")
                cue("safe")
            else
                LUI.banner("THE NIGHTMARE PASSED", "THE FLOCK WILL COME HOME")
            end
        end
    end
end

--- the panel's rows --------------------------------------------------------------------

local CARD_H = 30
local GW, GH = D.grid.w, D.grid.h

-- The town grid's size in the panel.
local function gridGeom()
    local cs = min(30, floor((R.panel.w - 8) / GW))
    local w = cs * GW
    return cs, floor((R.panel.w - w) / 2)
end

local function layout()
    rows = {}
    local y = 0
    if tab == "layers" then
        rows[#rows + 1] = { summary = true, y = y, h = 24 }
        y = y + 28
        rows[#rows + 1] = { header = "INCEPTION: EACH LAYER DREAMS THE ONE ABOVE", y = y, h = 10 }
        y = y + 10
        for k = 1, #L.dims do
            if Lucid.dimVisible(L, k) then
                rows[#rows + 1] = { dim = k, y = y, h = CARD_H }
                y = y + CARD_H + 4
            else
                rows[#rows + 1] = { dim = k, teaser = true, y = y, h = CARD_H }
                y = y + CARD_H + 4
                break
            end
        end
    elseif tab == "upgrades" then
        for _, sec in ipairs(Lucid.SECTIONS) do
            rows[#rows + 1] = { header = sec.name .. (sec.how and (": " .. sec.how) or ""), y = y, h = 10 }
            y = y + 10
            for _, r in ipairs(Lucid.ROOTS) do
                if r.section == sec.id then
                    rows[#rows + 1] = { upgrade = r, y = y, h = CARD_H }
                    y = y + CARD_H + 4
                end
            end
            y = y + 2
        end
    else
        local cs = gridGeom()
        rows[#rows + 1] = { grid = true, y = y, h = cs * GH + 2 }
        y = y + cs * GH + 6
        rows[#rows + 1] = { info = true, y = y, h = 24 }
        y = y + 28
        local districts = {
            { "speed", "SPEED: THE RUNS" }, { "auto", "AUTOMATION" }, { "park", "PASTURE" }, { "lucid", "LUCIDITY" },
        }
        -- The Mirror Lake in reach: lucidity goes first, where it's seen.
        if not Lucid.mirror(L) and Lucid.canBuild(L, "mirror") then table.insert(districts, 1, table.remove(districts)) end
        for _, d in ipairs(districts) do
            rows[#rows + 1] = { header = d[2], y = y, h = 10 }
            y = y + 10
            for _, b in ipairs(Lucid.BUILD) do
                if b.district == d[1] then
                    rows[#rows + 1] = { building = b, y = y, h = CARD_H }
                    y = y + CARD_H + 4
                end
            end
            y = y + 2
        end
    end
    contentH = y
end

local function maxScroll() return max(0, contentH - R.panel.h) end

-- The info row's buttons, in panel content coordinates: { label, fn, ok }.
local function infoButtons()
    local list = {}
    if moving or place then
        list[1] = { label = "CANCEL", ok = true, fn = function() moving, place = nil, nil end }
    elseif sel and L.grid[sel] then
        local id = L.grid[sel]
        if not Lucid.BY[id].autoDims then
            local p = Lucid.price(L, id)
            list[#list + 1] = { label = "LEVEL UP " .. N.format(p.dp) .. " DP", ok = Lucid.canUpgrade(L, sel),
                fn = function()
                    if Lucid.upgrade(L, sel) then cue("buy", { tier = 3 }) else cue("nope") end
                end }
        end
        list[#list + 1] = { label = "MOVE", ok = true, fn = function() moving = sel end }
    elseif sel and Lucid.canOpen(L, sel) then
        local p = Lucid.plotPrice(L)
        list[1] = { label = "BUY LAND " .. N.format(p) .. " DP", ok = N.gte(L.dp, p), fn = function()
            if Lucid.openPlot(L, sel) then cue("buy", { tier = 2, first = true }); sel = nil else cue("nope") end
        end }
    end
    -- Laid right to left along the row.
    local x = R.panel.w - 2
    for _, b in ipairs(list) do
        b.w = G.textWidth(b.label) + 10
        x = x - b.w
        b.x = x
        x = x - 3
    end
    return list
end

local function infoText()
    if moving then return "MOVING: TAP AN EMPTY PLOT. MOVING IS FREE." end
    if place then return "PLACE A " .. Lucid.BY[place].name:upper() .. ": TAP AN EMPTY PLOT" end
    if sel and L.grid[sel] then
        local b = Lucid.BY[L.grid[sel]]
        return b.name:upper() .. " LV " .. L.level[sel] .. ". WORKS X" .. (("%.2f"):format(Lucid.strength(L, sel)):gsub("%.?0+$", ""))
    end
    if sel and Lucid.canOpen(L, sel) then return "NEW LAND, BESIDE YOURS" end
    return "PICK A BUILDING BELOW, OR TAP ONE ON THE FARM"
end

--- input -------------------------------------------------------------------------------

local function tapTown(c)
    if moving then
        if Lucid.move(L, moving, c) then cue("click"); sel = c else cue("nope") end
        moving = nil
        return
    end
    if place and L.open[c] and not L.grid[c] then
        if Lucid.build(L, place, c) then
            cue("buy", { tier = 3, first = L.built[place] == 1 })
            sel = c
            if not Lucid.canBuild(L, place) then place = nil end
        else
            cue("nope")
        end
        return
    end
    place = nil
    sel = (sel ~= c) and c or nil
    cue("click")
end

-- A dream challenge's card: start it (after a word), give it up, or nothing.
local function tapChallenge(c)
    if Lucid.met(L, c.id) then cue("click") return end
    if L.challenge == c.id then
        showModal({
            title = "GIVE UP " .. c.name:upper() .. "?",
            lines = { "THE RULE LIFTS AND THE DREAM GOES ON FROM HERE. YOU CAN TRY AGAIN WHENEVER YOU LIKE." },
            big = "WAKE FROM IT",
            buttons = { { label = "GIVE UP", fn = function() Lucid.giveUp(L); LUI.save() end }, { label = "KEEP DREAMING" } },
        })
        return
    end
    showModal({
        title = "DREAM CHALLENGE: " .. c.name:upper(),
        lines = { c.rule:upper() .. ". GOAL: " .. LUI.goal(c) .. ". MEET IT AND, FOREVER:", "",
            "THE FLOCK WAKES: THE LAYERS AND DREAM SHEEP START OVER. THE FARM, THE UPGRADES AND YOUR POINTS STAY, BUT WHILE IT LASTS YOUR POINTS DON'T LIFT THE LAYERS." },
        big = c.reward:upper(),
        buttons = {
            { label = L.challenge and "SWITCH TO IT" or "START", fn = function()
                if Lucid.startChallenge(L, c.id) then LScene.reset(); LUI.save() end
            end },
            { label = "NOT NOW" },
        },
    })
end

-- What a challenge asks, in words.
function LUI.goal(c)
    if c.goal == "herd" then return "BRING " .. c.herd .. " FLOCKS HOME" end
    if c.goal == "sheep" then return "COUNT " .. N.format(c.sheep) .. " DREAM SHEEP" end
    if c.goal == "height" then return "CLIMB " .. c.height .. " HIGH" end
    return "REACH " .. c.runs .. " RUNS/S"
end

--- the upgrades -------------------------------------------------------------------------

-- What tapping upgrade `r`'s card does, what its price box says, and
-- whether it can be done now: label, ok, fn.
local function upgradeAction(r)
    local st = Lucid.rootState(L, r.id)
    if r.kind == "lake" then
        if st == "full" then return "BUILT", false end
        return "TO THE FARM", true, function()
            tab, scroll = "town", 0
            if Lucid.canBuild(L, "mirror") then place = "mirror" end
        end
    end
    if r.kind == "challenge" then
        local c = Lucid.CH[r.challenge]
        if st == "full" then return "MASTERED", false end
        if st == "on" then return "GIVE UP", true, function() tapChallenge(c) end end
        if st == "open" then return "START", true, function() tapChallenge(c) end end
        return "LOCKED", false
    end
    if r.kind == "gate" and st == "full" then return "GO THROUGH", S.phase == "lucid", function() LUI.leave() end end
    if st == "full" then return "ALL GROWN", false end
    return N.format(Lucid.rootPrice(L, r.id)) .. " DP", st == "open", function()
        if Lucid.grow(L, r.id) then cue("buy", { tier = 4, first = Lucid.rank(L, r.id) == 1 }); LUI.save() else cue("nope") end
    end
end

-- What the card says under the name.
local function upgradeSay(r)
    local st = Lucid.rootState(L, r.id)
    local from = r.at and Lucid.ROOT[r.at]
    if r.kind == "challenge" then
        local c = Lucid.CH[r.challenge]
        if st == "full" then return "YOURS FOR GOOD: " .. c.reward:upper() end
        if st == "on" then return "UNDER WAY. " .. LUI.goal(c) end
        if st == "shut" then
            return Lucid.mirror(L) and ("MASTER " .. Upgrades.name(from):upper() .. " FIRST") or "BUILD THE MIRROR LAKE FIRST"
        end
        return c.rule:upper() .. ". " .. LUI.goal(c)
    end
    if st == "shut" and from then
        if from.kind == "challenge" then return "MASTER " .. Upgrades.name(from):upper() .. " FIRST" end
        return "AFTER " .. Upgrades.name(from):upper()
    end
    return r.desc:upper()
end

-- The first dream challenge that can be started now.
local function waitingChallenge()
    if not Lucid.mirror(L) then return nil end
    for _, rt in ipairs(Lucid.ROOTS) do
        if rt.kind == "challenge" and Lucid.rootState(L, rt.id) == "open" then return rt end
    end
end

-- To the UPGRADES tab. A dream challenge waiting that you haven't looked at
-- is scrolled to.
local function openUpgrades()
    tab, scroll = "upgrades", 0
    local w = waitingChallenge()
    if w and not challengeSeen[w.id] then
        challengeSeen[w.id] = true
        layout()
        for _, row in ipairs(rows) do
            if row.upgrade == w then scroll = max(0, row.y - floor(R.panel.h / 3)) end
        end
    end
end

local function tapRow(row, x, y)
    if row.upgrade then
        local _, ok, fn = upgradeAction(row.upgrade)
        if ok and fn then fn() else cue("nope") end
        return
    end
    if row.dim and not row.teaser then
        local k = row.dim
        -- The AUTO pill toggles the auto-buyer; the rest of the card buys.
        if row.pill and x >= row.pill.x and x < row.pill.x + row.pill.w then
            Lucid.toggleAuto(L, k)
            cue("click")
            return
        end
        if Lucid.buyDim(L, k, buyMax and "max" or 1) > 0 then cue("buy", { tier = k }) else cue("nope") end
    elseif row.grid then
        local cs, gx = gridGeom()
        local cx, cy = floor((x - gx) / cs) + 1, floor((y - 1) / cs) + 1
        if cx >= 1 and cx <= GW and cy >= 1 and cy <= GH then tapTown(Lucid.cell(cx, cy)) end
    elseif row.info then
        for _, b in ipairs(infoButtons()) do
            if x >= b.x and x < b.x + b.w then
                if b.ok then b.fn() else cue("nope") end
                return
            end
        end
    elseif row.building then
        local b = row.building
        if b.locked then cue("nope") return end
        if b.max and L.built[b.id] >= b.max then cue("nope") return end
        place, moving, sel = b.id, nil, nil
        cue("click")
    end
end

function LUI.pressed(x, y, id)
    Audio.start()
    if intro or outro then return end
    if modal then
        for i, b in ipairs(modal.buttons) do
            if inside(b.rect, x, y) then cue("click"); closeModal(i) return end
        end
        return
    end
    if inside(R.mute, x, y) then
        S.muted = not S.muted
        Audio.setMuted(S.muted)
        cue("click")
        LUI.save()
        return
    end
    if inside(R.motion, x, y) then
        S.reducedMotion = not S.reducedMotion
        LUI.setReducedAll(S.reducedMotion)
        LUI.banner(S.reducedMotion and "LESS MOTION" or "FULL MOTION")
        cue("click")
        LUI.save()
        return
    end
    if inside(R.reset, x, y) then
        cue("click")
        showModal({
            title = "RESET EVERYTHING?",
            lines = { "THE SAVE IS WIPED, AND A NEW GAME STARTS FROM THE FIRST NIGHT, FROM SCRATCH." },
            big = "ALL OF IT",
            buttons = { { label = "RESET", fn = function() LUI.resetAll() end }, { label = "KEEP DREAMING" } },
        })
        return
    end
    if inside(R.tabs, x, y) then
        local k = lume.clamp(floor((x - R.tabs.x) / (R.tabs.w / 4)) + 1, 1, 4)
        if k == 4 then buyMax = not buyMax
        else
            local was, want = tab, ({ "layers", "town", "upgrades" })[k]
            if want ~= was then
                if want == "upgrades" then openUpgrades() else tab, scroll = want, 0 end
            end
        end
        cue("click")
        return
    end
    if inside(R.scene, x, y) then
        local sx, sy = x - R.scene.x, y - R.scene.y
        if L.nightmare then
            dogHeld = id
            Lucid.point(L, LScene.toField(sx, sy))
        elseif L.song then
            -- Counting: anywhere on the field is a tap on the beat.
            Lucid.countTap(L)
        elseif LScene.hitGolden(L, sx, sy) and Lucid.catchGolden(L) then
            cue("golden")
        elseif LScene.hitFlock(L, sx, sy) and Lucid.startSong(L) then
            cue("click")
        else
            -- The bouncing sheep: held, it climbs after the finger.
            bounceHeld = id
            Lucid.hold(L, LScene.toBounce(sx))
        end
        return
    end
    if inside(R.panel, x, y) then
        press = { id = id, y0 = y, scroll0 = scroll, moved = false, last = y }
        scrollV = 0
    end
end

function LUI.moved(x, y, id)
    if dogHeld == id and L.nightmare then
        Lucid.point(L, LScene.toField(x - R.scene.x, y - R.scene.y))
        return
    end
    if bounceHeld == id then
        Lucid.steer(L, LScene.toBounce(x - R.scene.x))
        return
    end
    if not press or press.id ~= id then return end
    if math.abs(y - press.y0) > 3 then press.moved = true end
    if press.moved then
        scroll = lume.clamp(press.scroll0 - (y - press.y0), 0, maxScroll())
        scrollV = (press.last - y) * 60
        press.last = y
    end
end

function LUI.released(x, y, id)
    if dogHeld == id then
        dogHeld = nil
        Lucid.point(L, nil)
        return
    end
    if bounceHeld == id then
        bounceHeld = nil
        Lucid.hold(L, nil)
        return
    end
    if not press or press.id ~= id then return end
    local p = press
    press = nil
    if p.moved or not inside(R.panel, x, y) then return end
    local cy = y - R.panel.y + floor(scroll)
    for _, row in ipairs(rows) do
        if cy >= row.y and cy < row.y + row.h then tapRow(row, x - R.panel.x, cy - row.y) return end
    end
end

function LUI.wheel(dy) scroll = lume.clamp(scroll - dy * 18, 0, maxScroll()) end

function LUI.key(key)
    if modal then
        local n = tonumber(key)
        if n and modal.buttons[n] then cue("click"); closeModal(n)
        elseif key == "return" or key == "space" or key == "kpenter" then cue("click"); closeModal(1) end
        return
    end
    if key == "m" then LUI.pressed(R.mute.x + 1, R.mute.y + 1, "key")
    elseif key == "r" then LUI.pressed(R.motion.x + 1, R.motion.y + 1, "key")
    elseif key == "1" then tab, scroll = "layers", 0
    elseif key == "2" then tab, scroll = "town", 0
    elseif key == "3" then
        if tab ~= "upgrades" then openUpgrades() end
    elseif key == "4" then buyMax = not buyMax
    elseif key == "escape" or key == "backspace" then sel, place, moving = nil, nil, nil
    elseif key == "space" and L.song then Lucid.countTap(L)
    elseif key == "space" and L.golden and Lucid.catchGolden(L) then cue("golden")
    elseif (key == "space" or key == "c") and L.flock and Lucid.startSong(L) then cue("click")
    elseif key == "down" or key == "pagedown" then LUI.wheel(-2)
    elseif key == "up" or key == "pageup" then LUI.wheel(2) end
end

--- each frame ------------------------------------------------------------------------------

function LUI.update(dt)
    t = t + dt
    if intro then
        intro.t = intro.t + dt
        if intro.t > 3.6 then intro = nil; explain() end
    end
    if outro then
        outro.t = outro.t + dt
        if outro.t > C.void.outro then
            outro = nil
            LUI.toVoid()
            return
        end
    end
    if L.choosing and not modal then giftChoice() end
    if not press then
        scroll = lume.clamp(scroll + scrollV * dt, 0, maxScroll())
        scrollV = scrollV * max(0, 1 - dt * 6)
    end
    if banner.text and t > banner.till and banner.y == 0 then
        flux.to(banner, reduced and 0.01 or 0.3, { y = 1 }):ease("quadin"):oncomplete(function() banner.text = nil end)
        banner.till = math.huge
    end
    LScene.update(dt, L)
    layout()
    scroll = lume.clamp(scroll, 0, maxScroll())
end

--- drawing ----------------------------------------------------------------------------------

local function centred(k, s, cx, y, z, edge)
    local x = floor(cx - G.textWidth(s, z) / 2)
    if edge then G.label(k, s, x, y, z, nil, edge) else G.text(k, s, x, y, z) end
end

-- The reset button (dev): an arrow coming round.
local RESET_ART = { "..lll.l", ".l...ll", "l...lll", "l......", "l.....l", ".l...l.", "..lll.." }

local function drawTop()
    local r = R.top
    centred("l", "LUCID DREAMING", r.x + r.w / 2, r.y + 4)
    local s = "DP " .. N.format(L.dp)
    G.box(r.x + 1, r.y + 1, G.textWidth(s) + 6, 11, "u", "i")
    G.text("y", s, r.x + 4, r.y + 4)
    local m = R.mute
    G.box(m.x + 1, m.y + 1, m.w - 2, m.h - 2, "u", "i")
    G.art({ "...ll", "..l.l", "..l..", "..l..", ".ll..", "lll..", ".l..." }, m.x + 6, m.y + 3)
    if S.muted then for i = 0, 8 do G.rect("y", m.x + 4 + i, m.y + 2 + i, 1, 1) end end
    local mo = R.motion
    G.box(mo.x + 1, mo.y + 1, mo.w - 2, mo.h - 2, "u", "i")
    if S.reducedMotion then G.rect("l", mo.x + 4, mo.y + 6, 9, 1)
    else G.art({ ".ll...ll.", "l..l.l..l", "....l...." }, mo.x + 4, mo.y + 5) end
    local re = R.reset
    G.box(re.x + 1, re.y + 1, re.w - 2, re.h - 2, "u", "i")
    G.art(RESET_ART, re.x + 5, re.y + 3)
end

local function drawHud()
    local r = R.scene
    local cx = r.x + r.w / 2
    local y = r.y + 5
    if L.nightmare then
        local Nightmare = require "lucid.nightmare"
        local inPen, lost, n = Nightmare.counts(L.nightmare)
        centred("r", "NIGHTMARE", cx, y, 2, "o")
        y = y + 14
        centred("w", "DRAG THE DOG: HERD THEM INTO THE FOLD", cx, y, 1, "o")
        y = y + 8
        local left = max(0, floor(L.nightmare.seconds - L.nightmare.t))
        centred("l", ("IN THE FOLD %d/%d   LOST %d   %dS"):format(inPen, n, lost, left), cx, y, 1, "o")
        if L.challenge == "season" then
            y = y + 8
            centred("y", ("NIGHTMARE SEASON: %d/%d FLOCKS HOME"):format(L.herded, Lucid.CH.season.herd), cx, y, 1, "o")
        end
    elseif L.song then
        local song = L.song
        local counted = song.perfect + song.good
        centred("w", "COUNTING SHEEP", cx, y, 2, "o")
        y = y + 14
        centred("c", song.t < 0 and "READY..." or "TAP ANYWHERE AS EACH ONE TOPS THE FENCE", cx, y, 1, "o")
        y = y + 8
        centred("l", ("COUNTED %d/%d   COMBO %d"):format(counted, #song.sheep, song.combo), cx, y, 1, "o")
    else
        local z = (portrait and r.w >= 200) and 3 or 2
        centred("w", N.format(L.sheep), cx, y, z, "o")
        y = y + 5 * z + 4
        centred("c", "DREAM SHEEP", cx, y, 1, "o")
        y = y + 8
        centred("l", N.format(Lucid.sheepRate(L), true) .. "/S   +" .. N.format(Lucid.dpPerSecond(L), true) .. " DP/S", cx, y, 1, "o")
        -- Under a dream challenge: its rule and how far, in gold.
        local c = L.challenge and Lucid.CH[L.challenge]
        if c then
            y = y + 9
            centred("y", (c.name .. ": " .. c.rule):upper(), cx, y, 1, "o")
            y = y + 8
            local have, goal = Lucid.progress(L)
            local done = c.goal == "sheep" and ("1E" .. have .. " OF " .. N.format(c.sheep)) or (N.format(have, true) .. "/" .. goal)
            centred("y", LUI.goal(c) .. ": " .. done, cx, y, 1, "o")
        end
        -- What the golden sheep gave, while it lasts.
        local chips = {}
        for id, left in pairs(L.effects) do
            local G0 = D.golden[id]
            local what = id == "tune" and ("CAP X" .. N.format(L.tuneMult, true))
                or (id == "frenzy" and ("X" .. G0.mult) or ("TIME X" .. G0.mult))
            chips[#chips + 1] = what .. " " .. math.ceil(left) .. "S"
        end
        table.sort(chips)
        y = y + 9
        for _, c in ipairs(chips) do
            local w = G.textWidth(c) + 6
            G.box(floor(cx - w / 2), y, w, 8, "y", "h")
            centred("o", c, cx, y + 2)
            y = y + 10
        end
    end
    -- The bouncing sheep: how high, while it climbs; how to, before the first.
    local B = L.bounce
    if L.flock and not L.nightmare then
        -- A flock waiting: what to do, and how long it waits.
        local s = ("TAP THE FLOCK AT THE FENCE: COUNT THEM (%dS)"):format(math.ceil(D.count.wait - L.flock.t))
        if G.textWidth(s) > r.w - 8 then s = ("TAP THE FLOCK: COUNT THEM (%dS)"):format(math.ceil(D.count.wait - L.flock.t)) end
        if reduced or floor(t * 2) % 3 ~= 0 then G.label("y", s, floor(cx - G.textWidth(s) / 2), r.y + r.h - 9) end
    elseif not L.nightmare and not L.song then
        local by = r.y + r.h - 9
        if B.on then
            local s = ("HEIGHT %d   BEST %d"):format(floor(B.height), floor(L.best))
            G.label("w", s, r.x + 4, by)
            if B.stars > 0 then
                local st = "*" .. B.stars
                G.label("y", st, r.x + r.w - 4 - G.textWidth(st), by)
            end
        elseif L.best < 10 then
            local s = "HOLD THE FIELD: THE SHEEP CLIMBS"
            if reduced or floor(t * 1.5) % 4 ~= 0 then G.label("c", s, floor(cx - G.textWidth(s) / 2), by - 28) end
        elseif L.best > 0 then
            G.label("l", ("BEST %d: LAYERS X%s"):format(floor(L.best), N.format(Lucid.recordMult(L), true)), r.x + 4, by)
        end
    end
    if banner.text then
        local w = min(r.w - 10, max(G.textWidth(banner.text, 2), G.textWidth(banner.sub or "")) + 14)
        local h = banner.sub and 24 or 16
        local by = floor(r.y + r.h * 0.5 - h / 2 + banner.y * (r.h * 0.6))
        if by < r.y + r.h then
            local bx = floor(cx - w / 2)
            G.box(bx, by, w, h, "c")
            G.rect("i", bx, by + h - 2, w, 2)
            local tz = G.textWidth(banner.text, 2) <= w - 6 and 2 or 1
            centred("u", banner.text, cx, by + 3, tz)
            if banner.sub then centred("p", banner.sub, cx, by + 15) end
        end
    end
end

-- Auto-wake: a bar that fills once a run, until it can't keep up, then the flow.
local function drawWake()
    local r = R.wake
    local rps = Lucid.runsPerSecond(L)
    G.text("l", "AUTO-WAKE", r.x, r.y + 2)
    local label
    if L.flow then label = "NO NIGHT. ONLY DREAM."
    elseif rps <= 0 then label = "ASLEEP"
    elseif rps < 1 then label = "1 RUN / " .. floor(1 / rps + 0.5) .. "S"
    else label = N.format(rps, true) .. " RUNS/S" end
    G.text(L.flow and "a" or "w", label, r.x + r.w - G.textWidth(label), r.y + 2)
    local bx = r.x + 40
    local bw = r.w - 44 - G.textWidth(label)
    if bw < 10 then return end
    G.box(bx, r.y + 1, bw, 7, "u")
    if L.flow or rps >= 4 then
        -- Too quick for a bar: it shimmers.
        for x = 0, bw - 1 do
            local k = (floor(x + t * 40) % 6 < 3) and "a" or "c"
            if reduced then k = "a" end
            G.rect(k, bx + x, r.y + 1, 1, 7)
        end
    else
        local fill = floor(bw * L.runAcc)
        if fill > 0 then G.rect("l", bx, r.y + 1, fill, 7); G.rect("w", bx, r.y + 1, fill, 1) end
    end
end

local function drawTabs()
    local r = R.tabs
    local buttons = { { "LAYERS", tab == "layers" }, { "FARM", tab == "town" }, { "UPGRADES", tab == "upgrades" },
        { buyMax and "MAX" or "X1", buyMax } }
    local w = floor((r.w - 4) / 4)
    for i, b in ipairs(buttons) do
        local x = r.x + (i - 1) * (w + 2)
        local on = b[2]
        G.box(x + 1, r.y + 1, w - 2, r.h - 2, on and "c" or "u", on and "o" or "i")
        if on then G.rect("i", x + 1, r.y + r.h - 2, w - 2, 1) end
        centred(on and "u" or "l", b[1], x + w / 2, r.y + 4)
        -- Something to find there, a rose mark: on FARM while the Mirror Lake
        -- is in reach and not built, on UPGRADES until you look at a dream
        -- challenge waiting.
        local wc = i == 3 and waitingChallenge()
        local mark = (i == 2 and not Lucid.mirror(L) and Lucid.canBuild(L, "mirror"))
            or (wc and not challengeSeen[wc.id])
        if not on and mark and (reduced or sin(t * 4) > -0.5) then
            G.art({ "r", "r", "r", ".", "r" }, x + 4, r.y + 3)
        end
    end
end

local DISTRICT = { speed = "y", auto = "i", park = "a", lucid = "s" }

local function drawSummary(x, y, w)
    G.box(x + 1, y + 1, w - 2, 22, "u", "i")
    G.text("l", "A RUN: " .. N.format(Lucid.need(L)) .. " SHEEP, +" .. N.format(Lucid.dpPerRun(L), true) .. " DP", x + 5, y + 4)
    G.text("c", "AT MOST " .. N.format(Lucid.cap(L), true) .. " RUNS/S. RUNS: " .. N.format(L.runs), x + 5, y + 11)
    local s = "EVERY LAYER X" .. N.format(Lucid.dimMult(L), true) .. ". TIME X" .. N.format(Lucid.dilation(L), true) .. " A TEN"
    if G.textWidth(s) > w - 10 then s = "LAYERS X" .. N.format(Lucid.dimMult(L), true) .. ", TIME X" .. N.format(Lucid.dilation(L), true) .. "/10" end
    G.text("i", s, x + 5, y + 17)
end

local function drawDim(row, x, y, w)
    local k = row.dim
    local h = row.h
    local d = D.dims[k]
    if row.teaser then
        G.box(x + 1, y + 1, w - 2, h - 2, "u", "p")
        G.box(x + 4, y + 4, 28, h - 8, "n", "p")
        G.text("p", "?", x + 17, y + 12)
        G.text("s", "???", x + 37, y + 6)
        G.text("s", ("A SLEEPER IN " .. D.dims[k - 1].name .. " DREAMS IT UP"):upper(), x + 37, y + 15)
        return
    end
    local dim = L.dims[k]
    local n = buyMax and max(1, N.geoMax(d.base, d.growth, dim.bought, L.sheep)) or 1
    local cost = Lucid.dimCost(L, k, n)
    local ok = N.gte(L.sheep, cost)
    local breathe = ok and not reduced and sin(t * 3.4 + row.y * 0.05) > 0
    if breathe then G.box(x, y, w, h, "c", "c") end
    G.box(x + 1, y + 1, w - 2, h - 2, ok and "w" or "s")
    G.rect(ok and "b" or "p", x + 1, y + h - 2, w - 2, 1)
    G.box(x + 4, y + 4, 28, h - 8, ok and "l" or "i")
    love.graphics.push("all")
    love.graphics.intersectScissor(x + 4, y + 4, 28, h - 8)
    LScene.dimension(k, x + 18, y + h / 2)
    love.graphics.pop()
    local price = N.format(cost)
    local qty = "X" .. n
    local pw = max(G.textWidth(price), G.textWidth(qty)) + 8
    local px = x + w - pw - 4
    G.box(px, y + 4, pw, h - 8, ok and "y" or "b")
    G.text("o", price, px + pw - 4 - G.textWidth(price), y + 7)
    G.text(ok and "h" or "p", qty, px + pw - 4 - G.textWidth(qty), y + 15)
    local tx = x + 37
    G.text("o", ("LAYER " .. k .. ": " .. d.name):upper(), tx, y + 5)
    local asleep = not Lucid.layerOn(L, k)
    G.text("p", N.format(dim.amount) .. " " .. d.sleeper:upper() .. (asleep and " (STILL)" or ""), tx, y + 13)
    local made = k == 1 and "SHEEP" or D.dims[k - 1].sleeper:upper()
    local tens = floor(dim.bought / D.bonusEvery)
    local time = tens > 0 and ("  TIME X" .. N.format(Lucid.dilation(L) ^ tens, true)) or ""
    local line = "+" .. N.format(Lucid.dimRate(L, k), true) .. " " .. made .. "/S" .. time
    if G.textWidth(line) > px - tx - 3 then line = "+" .. N.format(Lucid.dimRate(L, k), true) .. "/S EACH" .. time end
    G.text("p", line, tx, y + 19)
    row.pill = nil
    if Lucid.autoHas(L, k) then
        local on = Lucid.autoOn(L, k)
        local s = on and "AUTO" or "OFF"
        local bw = G.textWidth(s) + 6
        row.pill = { x = px - bw - 4 - x, w = bw + 4 }
        G.box(px - bw - 3, y + 4, bw, 9, on and "a" or "s", "o")
        G.text("o", s, px - bw, y + 6)
    end
end

local function drawGrid(x, y)
    local cs, gx = gridGeom()
    for gy = 1, GH do
        for gxi = 1, GW do
            local c = Lucid.cell(gxi, gy)
            local cx, cy = x + gx + (gxi - 1) * cs, y + 1 + (gy - 1) * cs
            if L.open[c] then
                local id = L.grid[c]
                local fill = id and "i" or "p"
                if place and not id then fill = (floor(t * 3) % 2 == 0 or reduced) and "l" or "p" end
                if moving and not id then fill = "l" end
                G.box(cx + 1, cy + 1, cs - 2, cs - 2, fill, sel == c and "y" or "o")
                if id then
                    local b = Lucid.BY[id]
                    G.rect(DISTRICT[b.district], cx + 1, cy + cs - 3, cs - 2, 2)
                    LScene.building(id, cx + cs / 2, cy + cs / 2 - 1)
                    if L.level[c] > 1 then G.label("w", tostring(L.level[c]), cx + 2, cy + 2) end
                    if moving == c and floor(t * 4) % 2 == 0 then G.rect("y", cx + 1, cy + 1, cs - 2, 1) end
                end
            elseif Lucid.canOpen(L, c) then
                G.box(cx + 1, cy + 1, cs - 2, cs - 2, "n", sel == c and "y" or "p")
                for i = cx + 2, cx + cs - 3, 3 do G.rect("i", i, cy + 1, 1, 1); G.rect("i", i, cy + cs - 2, 1, 1) end
                centred("i", "+", cx + cs / 2, cy + cs / 2 - 2)
            else
                G.rect("n", cx + 1, cy + 1, cs - 2, cs - 2)
            end
        end
    end
end

local function drawInfo(x, y, w)
    G.box(x + 1, y + 1, w - 2, 22, "u", "i")
    local buttons = infoButtons()
    local left = buttons[#buttons] and buttons[#buttons].x or w
    local lines = G.wrap(infoText(), left - 8)
    for i = 1, min(2, #lines) do G.text("c", lines[i], x + 5, y + 4 + (i - 1) * 7) end
    for _, b in ipairs(buttons) do
        G.box(x + b.x, y + 5, b.w, 13, b.ok and "y" or "s", "o")
        centred("o", b.label, x + b.x + b.w / 2, y + 9)
    end
end

local function drawBuilding(row, x, y, w)
    local b, h = row.building, row.h
    if b.locked then
        G.box(x + 1, y + 1, w - 2, h - 2, "u", "p")
        G.box(x + 4, y + 4, 28, h - 8, "n", "p")
        LScene.building(b.id, x + 18, y + h / 2, true)
        G.text("s", b.name:upper(), x + 37, y + 6)
        G.text("s", b.desc:upper(), x + 37, y + 15)
        return
    end
    local full = b.max and L.built[b.id] >= b.max
    local ok = not full and Lucid.canBuild(L, b.id)
    local on = place == b.id
    if ok and not reduced and sin(t * 3.4 + row.y * 0.05) > 0 then G.box(x, y, w, h, "c", "c") end
    G.box(x + 1, y + 1, w - 2, h - 2, on and "y" or (ok and "w" or (full and "l" or "s")))
    G.rect(DISTRICT[b.district], x + 1, y + h - 3, w - 2, 2)
    G.box(x + 4, y + 4, 28, h - 8, ok and "l" or "i")
    LScene.building(b.id, x + 18, y + h / 2)
    if not full then
        local p = Lucid.price(L, b.id)
        local price = N.format(p.dp) .. " DP"
        local wool = N.format(p.sheep)
        local pw = max(G.textWidth(price), G.textWidth(wool)) + 8
        local px = x + w - pw - 4
        G.box(px, y + 4, pw, h - 8, ok and "y" or "b")
        G.text("o", price, px + pw - 4 - G.textWidth(price), y + 7)
        G.text(ok and "h" or "p", wool, px + pw - 4 - G.textWidth(wool), y + 15)
        local tx = x + 37
        G.text("o", b.name:upper(), tx, y + 5)
        if L.built[b.id] > 0 then G.text("p", "X" .. L.built[b.id], tx + G.textWidth(b.name) + 5, y + 5) end
        local lines = G.wrap(b.desc:upper(), px - tx - 4)
        for i = 1, min(2, #lines) do G.text("p", lines[i], tx, y + 8 + i * 6) end
        return
    end
    G.text("o", b.name:upper(), x + 37, y + 5)
    G.text("p", "ALL BUILT. " .. b.desc:upper(), x + 37, y + 14)
end

-- An upgrade's card: its picture, its name and rank, what it does (or what
-- it waits on), and its price or what tapping does.
local function drawUpgrade(row, x, y, w)
    local r, h = row.upgrade, row.h
    local st = Lucid.rootState(L, r.id)
    local label, ok = upgradeAction(r)
    local shut, full = st == "shut", st == "full"
    if ok and not reduced and sin(t * 3.4 + row.y * 0.05) > 0 then G.box(x, y, w, h, "c", "c") end
    G.box(x + 1, y + 1, w - 2, h - 2, shut and "u" or (st == "on" and "y" or (ok and "w" or (full and "l" or "s"))), shut and "p" or nil)
    G.box(x + 4, y + 4, 28, h - 8, shut and "n" or (ok and "l" or "i"), shut and "p" or nil)
    Upgrades.icon(r.id, x + 18, y + h / 2, shut and "p" or Upgrades.tint(r), shut and "p" or "w")
    local pw = G.textWidth(label) + 8
    local px = x + w - pw - 4
    G.box(px, y + 4, pw, h - 8, ok and "y" or "b")
    G.text("o", label, px + pw - 4 - G.textWidth(label), y + 7)
    if r.kind == "up" then
        local s = Lucid.rank(L, r.id) .. "/" .. r.max
        G.text(ok and "h" or "p", s, px + pw - 4 - G.textWidth(s), y + 15)
    end
    local tx = x + 37
    G.text(shut and "s" or "o", Upgrades.name(r):upper(), tx, y + 5)
    local lines = G.wrap(upgradeSay(r), px - tx - 4)
    for i = 1, min(2, #lines) do G.text(shut and "s" or "p", lines[i], tx, y + 8 + i * 6) end
end

local function drawPanel()
    local r = R.panel
    love.graphics.push("all")
    love.graphics.setScissor(r.x - 3, r.y, r.w + 6, r.h)
    local oy = r.y - floor(scroll)
    for _, row in ipairs(rows) do
        local y = oy + row.y
        if y + row.h >= r.y and y < r.y + r.h then
            if row.header then G.text("i", row.header, r.x + 2, y + 2)
            elseif row.summary then drawSummary(r.x, y, r.w)
            elseif row.dim then drawDim(row, r.x, y, r.w)
            elseif row.grid then drawGrid(r.x, y)
            elseif row.info then drawInfo(r.x, y, r.w)
            elseif row.building then drawBuilding(row, r.x, y, r.w)
            elseif row.upgrade then drawUpgrade(row, r.x, y, r.w) end
        end
    end
    love.graphics.pop()
    if maxScroll() > 0 then
        local th = max(10, floor(r.h * r.h / contentH))
        local ty = r.y + floor((r.h - th) * scroll / maxScroll())
        G.rect("i", r.x + r.w + 1, ty, 1, th)
    end
end

local function drawModal()
    local m = modal
    G.rect("n", 0, 0, vw, vh)
    local rnd = love.math.newRandomGenerator(9)
    for _ = 1, floor(vw * vh / 200) do
        local x, y, ph = rnd:random(0, vw - 1), rnd:random(0, vh - 1), rnd:random() * 6.3
        local tw = reduced and 1 or sin(t * 1.1 + ph)
        if tw > -0.6 then G.rect(tw > 0.5 and "c" or "a", x, y, 1, 1) end
    end
    local w = min(vw - 16, 230)
    local inner = w - 16
    -- The big line goes after the first paragraph (what it's about), however
    -- many lines that wraps to.
    local lines, first = {}, 0
    for i, l in ipairs(m.lines) do
        if l == "" then lines[#lines + 1] = "" else
            for _, s in ipairs(G.wrap(l, inner)) do lines[#lines + 1] = s end
        end
        if i == 1 then first = #lines end
    end
    local tz = G.textWidth(m.title, 2) <= inner and 2 or 1
    local bz = G.textWidth(m.big, 2) <= inner and 2 or 1
    local nb = #m.buttons
    local h = 10 + (5 * tz + 4) + 4 + #lines * 7 + 6 + 5 * bz + 8 + nb * 17 + 4
    local x, y = floor((vw - w) / 2), floor((vh - h) / 2 + m.y)
    G.box(x, y, w, h, "u", "i")
    G.rect("n", x, y + h - 2, w, 2)
    local cy = y + 8
    centred("c", m.title, vw / 2, cy, tz)
    cy = cy + 5 * tz + 8
    for i, s in ipairs(lines) do
        centred("l", s, vw / 2, cy); cy = cy + 7
        if i == first then
            cy = cy + 4
            centred("y", m.big, vw / 2, cy, bz)
            cy = cy + 5 * bz + 6
        end
    end
    local by = y + h - nb * 17 - 4
    for i, b in ipairs(m.buttons) do
        local bw = min(inner, G.textWidth(b.label) + 24)
        local br = rect(vw / 2 - bw / 2, by + (i - 1) * 17, bw, 14)
        local pulse = (i == 1 and not reduced and sin(t * 3) > 0) and 1 or 0
        G.box(br.x - pulse, br.y - pulse, br.w + pulse * 2, br.h + pulse * 2, "y", "y")
        G.box(br.x + 1, br.y + 1, br.w - 2, br.h - 2, nb > 1 and "c" or "l")
        G.rect("i", br.x + 1, br.y + br.h - 2, br.w - 2, 1)
        centred("o", b.label, vw / 2, br.y + 4)
        b.rect = br
    end
end

-- The way in: the night closes over phase 1, the violet opens, the words.
local function drawIntro()
    local p = intro.t
    G.rect("n", 0, 0, vw, vh)
    -- The dream opening from the middle: a dithered violet ring growing.
    local open = lume.clamp((p - 0.8) / 1.6, 0, 1)
    if open > 0 then
        local pts, apts = {}, {}
        local cx, cy = vw / 2, vh / 2
        local rmax = math.sqrt(cx * cx + cy * cy)
        for yy = 0, vh - 1, 1 do
            for xx = 0, vw - 1 do
                local d = math.sqrt((xx - cx) ^ 2 + (yy - cy) ^ 2) / rmax
                local v = (open - d) * 2
                if v > 0 and G.dither(xx, yy, min(1, v)) then
                    if G.dither(xx + 2, yy + 1, (open - d) * 1.2 - 0.3) then G.plot(apts, xx, yy) else G.plot(pts, xx, yy) end
                end
            end
        end
        G.points("u", pts)
        G.points("i", apts)
    end
    local function say(text, at, y, z, k)
        if p > at then
            local dens = lume.clamp((p - at) / 0.5, 0, 1)
            local x = floor(vw / 2 - G.textWidth(text, z) / 2)
            G.label(k, text, x, y, z, reduced and 1 or dens, "u")
        end
    end
    say("YOU STOP COUNTING SHEEP.", 1.0, floor(vh * 0.38), 1, "l")
    say("YOU START DREAMING THEM.", 1.8, floor(vh * 0.38) + 10, 1, "c")
    say("LUCID DREAMING", 2.5, floor(vh * 0.38) + 26, 2, "y")
end

-- The way out: the Gate of Horn opens in the middle of the dream, the dream
-- drains away round it into ink, a last sheep drifts up into nothing, and
-- the words.
local function drawOutro()
    local p = outro.t
    local T = C.void.outro
    -- The dark coming in from the edges, then over everything.
    local dark = lume.clamp(p / 2.6, 0, 1)
    local cx, cy = vw / 2, vh / 2
    local rmax = math.sqrt(cx * cx + cy * cy)
    local pts, deep = {}, {}
    for yy = 0, vh - 1 do
        for xx = 0, vw - 1 do
            local d = math.sqrt((xx - cx) ^ 2 + (yy - cy) ^ 2) / rmax
            local v = (dark * 1.6 - (1 - d)) * 2
            if v > 0 and G.dither(xx, yy, min(1, v)) then
                if G.dither(xx + 1, yy + 2, (v - 1) * 0.8) then G.plot(deep, xx, yy) else G.plot(pts, xx, yy) end
            end
        end
    end
    G.points("o", pts)
    G.points("n", deep)
    -- The gate: two horn-white posts and a lintel, opening.
    local open = lume.clamp((p - 1.2) / 2, 0, 1)
    local gh = floor(min(vh * 0.4, 70))
    local gw = floor(gh * 0.6)
    local gx, gy = floor(cx - gw / 2), floor(cy - gh / 2)
    if p > 0.6 and p < T - 0.8 then
        G.rect("w", gx - 2, gy - 3, gw + 4, 3)
        G.rect("w", gx - 2, gy, 3, gh)
        G.rect("w", gx + gw - 1, gy, 3, gh)
        -- Inside it: the void, widening from a line.
        local iw = floor((gw - 4) * open)
        G.rect("o", floor(cx - iw / 2), gy, iw, gh)
        for i = 0, 6 do
            local sx = floor(cx - iw / 2 + (i * 13 + floor(p * 9)) % max(1, iw))
            if iw > 2 then G.rect(i % 2 == 0 and "l" or "i", sx, gy + (i * 17) % gh, 1, 1) end
        end
    end
    -- A sheep drifting up into it, turning to cloud.
    if p > 2 and p < T - 1 then
        local f = (p - 2) / (T - 3)
        local sp = Models.sheep(0.25, 0, 0, f < 0.5 and "plain" or "cloud", false, 0.8)
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(sp.img, floor(cx - sp.oi), floor(cy + gh * 0.4 - f * gh * 0.8 - sp.oj))
    end
    local function say(text, at, y, z, k)
        if p > at then
            local dens = lume.clamp((p - at) / 0.6, 0, 1) * lume.clamp((T - 0.3 - p) / 0.6, 0, 1)
            G.label(k, text, floor(cx - G.textWidth(text, z) / 2), y, z, reduced and 1 or dens, "o")
        end
    end
    say("THE GATE OF HORN OPENS.", 1.4, gy + gh + 10, 1, "w")
    say("PAST THE FIELD. PAST THE DREAM.", 2.8, gy + gh + 20, 1, "l")
    say("THE VOID", 4.2, gy - 20, 2, "c")
end

function LUI.draw()
    if outro and outro.t >= 2.6 then drawOutro() return end
    if intro then drawIntro() return end
    local r = R.scene
    G.box(r.x, r.y, r.w, r.h, "n")
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(LScene.draw(L), r.x, r.y)
    G.rect("o", r.x, r.y + r.h, r.w, 2)
    drawTop()
    drawHud()
    drawWake()
    drawTabs()
    drawPanel()
    if modal then drawModal() end
    if outro then drawOutro() end
end

-- Set by ui.lua, which owns the motion setting for both phases.
LUI.setReducedAll = function(v) LUI.setReduced(v) end

-- For the shots: a dream challenge's card tapped.
function LUI.askChallenge(id) tapChallenge(Lucid.CH[id]) end

-- For the shots: open a tab, pick a cell; or scroll the panel.
function LUI.show(which, cell, at) tab = which or tab; sel = cell; scroll = at or 0 end

return LUI
