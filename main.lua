-- Herding: a small dog, a flock of sheep, a pen. No timer and no fail screen;
-- a mistake only means nudging again.
--
-- Everything renders into a low-res canvas blown up by a whole number, so a
-- game pixel is always an exact block of screen pixels (Survive School's
-- main.lua): the zoom is picked off the window's short edge and the canvas made
-- as many game pixels as it takes to cover the window, so nothing is
-- letterboxed or stretched and a phone may turn. The bodies are ellipsoids,
-- ray-traced a pose at a time and kept (tracer.lua, models.lua).
--
-- The rules are in flock.lua (the sheep, and the one table of numbers worth
-- tuning), dog.lua (the dog and its pressure field) and level.lua (the
-- fields). This file runs the frame, the camera and the level flow.

local G = require "gfx"
local T = require "tracer"
local Models = require "models"
local Level = require "level"
local Flock = require "flock"
local Dog = require "dog"
local Input = require "input"

local floor, max, min = math.floor, math.max, math.min

local BASE_H = 180  -- the short edge on a phone, in game pixels
local DESK_H = 216  -- ... and on a computer, a little more field for a bigger screen
local BASE_W = 320  -- never narrower than this down the long edge

local canvas
local vw, vh = 320, 180
local scale, offX, offY = 1, 0, 0
local inset = { l = 0, t = 0, r = 0, b = 0 }

local game = {
    n = 1,           -- level number
    state = "play",  -- "play", then "won" over the still-moving field
    t = 0,           -- seconds into the level
    hold = 0,        -- how long enough sheep have been in the pen
    camx = 0, camy = 0,
}
local shots -- dev: --shot writes pictures and quits

local function fit()
    local w, h = love.graphics.getDimensions()
    local short, long = min(w, h), max(w, h)
    local design = Input.MOBILE and BASE_H or DESK_H
    scale = max(1, min(floor(short / design), floor(long / BASE_W)))
    local cw, ch = math.ceil(w / scale), math.ceil(h / scale)
    if cw ~= vw or ch ~= vh or not canvas then
        vw, vh = cw, ch
        if canvas then canvas:release() end
        canvas = love.graphics.newCanvas(vw, vh)
        canvas:setFilter("nearest", "nearest")
    end
    offX, offY = floor((w - vw * scale) / 2), floor((h - vh * scale) / 2)
    Input.setTransform(scale, offX, offY)
    -- Notches and gesture bars: a margin off each edge for the HUD.
    if love.window.getSafeArea then
        local sx, sy, sw, sh = love.window.getSafeArea()
        local l, t = (sx - offX) / scale, (sy - offY) / scale
        inset.l, inset.t = max(0, floor(l)), max(0, floor(t))
        inset.r, inset.b = max(0, math.ceil(vw - (l + sw / scale))), max(0, math.ceil(vh - (t + sh / scale)))
    end
end

local function start(n)
    game.n = (n - 1) % Level.count() + 1
    game.level = Level.new(game.n)
    game.flock = Flock.new(game.level)
    local d = game.level.def.dog
    game.dog = Dog.new(d.x, d.z)
    game.need = math.ceil(#game.flock.list * (game.level.def.goal or 0.8))
    game.state, game.t, game.hold = "play", 0, 0
    game.camx, game.camy = nil, nil
end

-- The camera: the whole field when it fits, else following the dog, held to
-- the field and its margin. Top keeps room for the HUD strip.
local TOP, SIDE = 16, 8
local function camTarget()
    local L, SE = game.level, T.SE
    local fw, fh = L.w, L.h * SE
    local tx, ty
    if fw + SIDE * 2 <= vw then tx = (fw - vw) / 2
    else tx = max(-SIDE, min(fw + SIDE - vw, game.dog.x - vw / 2)) end
    if fh + TOP + SIDE <= vh then ty = (fh - vh) / 2 - (TOP - SIDE) / 2
    else ty = max(-TOP, min(fh + SIDE - vh, game.dog.z * SE - vh / 2)) end
    return tx, ty
end

function love.load(args)
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setLineStyle("rough")
    love.graphics.setPointSize(1)
    if Input.MOBILE then
        love.window.setFullscreen(true, "desktop")
        Input.usingTouch = true
    else
        -- The pointer is drawn into the canvas: the system's arrow is the one
        -- thing that would be at the wrong scale and off the palette.
        love.mouse.setVisible(false)
    end
    local first = 1
    for k, a in ipairs(args or {}) do
        if a == "--level" then first = tonumber(args[k + 1]) or 1 end
        if a == "--shot" then shots = { at = {}, t = 0 } end
        if a == "--window" then love.window.setMode(1280, 720, { resizable = true }) end
    end
    if shots then
        for k, a in ipairs(args) do
            local s = a:match("^%-%-at=(.+)$")
            if s then for v in s:gmatch("[^,]+") do shots.at[#shots.at + 1] = tonumber(v) end end
        end
        if #shots.at == 0 then shots.at = { 3 } end
    end
    fit()
    start(first)
end

function love.resize() fit() end

function love.focus(f)
    if not f then Input.releaseAll() end
end

function love.update(dt)
    -- A hitched frame can't throw a sheep through a fence.
    dt = min(dt, 1 / 30)
    if shots then dt = 1 / 60 end
    game.t = game.t + dt

    local move
    move = Input.move()
    if move and move.point then
        -- Canvas pixel to field point.
        move = { point = true, x = move.x + game.camx, z = (move.y + game.camy) / T.SE }
    end
    game.dog:update(dt, move, game.level)
    game.flock:update(dt, game.dog)

    game.penned = game.flock:penned()
    if game.state == "play" then
        if game.penned >= game.need then game.hold = game.hold + dt else game.hold = 0 end
        if game.hold > 1 then
            game.state, game.wonAt, game.saved = "won", game.t, game.penned
        end
    elseif game.state == "won" then
        -- The count keeps up with stragglers that wander in while you read it.
        game.saved = max(game.saved, game.penned)
        if Input.tapped and game.t - game.wonAt > 0.8 then start(game.n + 1) end
    end
    Input.tapped = false

    local tx, ty = camTarget()
    if not game.camx then game.camx, game.camy = tx, ty end
    local e = 1 - math.exp(-dt * 5)
    game.camx, game.camy = game.camx + (tx - game.camx) * e, game.camy + (ty - game.camy) * e

    if shots then
        shots.t = shots.t + dt
        if shots.t >= shots.at[1] then
            shots.want = true
        end
    end
end

--- drawing --------------------------------------------------------------------

local function drawField()
    local L, cx, cy = game.level, floor(game.camx), floor(game.camy)
    G.rect("t", 0, 0, vw, vh)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(L.ground, -Level.MARGIN - cx, -Level.MARGIN - cy)
    game.dog:drawField(cx, cy)
    game.flock:shadows(cx, cy)
    game.dog:shadow(cx, cy)

    local SE = T.SE
    local q = {}
    game.flock:queue(q, cx, cy)
    game.dog:queue(q, cx, cy)
    for _, r in ipairs(L.rocks) do
        local pic = r.hay and Models.hay() or Models.rock(r.r, floor(r.x + r.z))
        local sx, sy = floor(r.x - cx + 0.5), floor(r.z * SE - cy + 0.5)
        q[#q + 1] = { z = r.z, draw = function()
            G.ellipse("t", sx, sy + 1, r.r + 1, floor(r.r * 0.55))
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(pic.img, sx - pic.oi, sy - pic.oj)
        end }
    end
    -- Rails between posts, at two heights, lit on top; each stretch sorted on
    -- its nearer end, posts on their own.
    local CE = T.CE
    for _, r in ipairs(L.rails) do
        local x1, y1, x2, y2 = r[1] - cx, r[2] * SE - cy, r[3] - cx, r[4] * SE - cy
        q[#q + 1] = { z = max(r[2], r[4]) - 0.5, draw = function()
            for _, hgt in ipairs({ 4, 8 }) do
                local d = hgt * CE
                G.line("o", x1, y1 - d + 1, x2, y2 - d + 1)
                G.line("b", x1, y1 - d, x2, y2 - d)
            end
        end }
    end
    local post = Models.post()
    for _, p in ipairs(L.posts) do
        local sx, sy = floor(p.x - cx + 0.5), floor(p.z * SE - cy + 0.5)
        q[#q + 1] = { z = p.z, draw = function()
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(post.img, sx - post.oi, sy - post.oj)
        end }
    end
    table.sort(q, function(a, b) return a.z < b.z end)
    for _, d in ipairs(q) do d.draw() end
end

-- A row of little sheep, filled in for each one penned, and a notch at the goal.
local function drawHud()
    local x, y = inset.l + 4, inset.t + 4
    G.label("w", game.n .. " " .. game.level.name, x, y)
    local list = game.flock.list
    local rx = vw - inset.r - 4 - #list * 5
    for k = 1, #list do
        local px = rx + (k - 1) * 5
        G.rect("o", px - 1, y - 1, 6, 7)
        G.rect(k <= game.penned and "w" or "t", px, y, 4, 5)
        if k == game.need then G.rect("w", px + 4, y + 7, 1, 2) end
    end
    local count = game.penned .. "/" .. #list
    G.label("w", count, rx - 4 - G.textWidth(count), y)

    if game.state == "play" and game.t < 8 then
        local hint = game.level.hint
        local how = Input.usingTouch and "HOLD A FINGER DOWN AND THE DOG GOES TO IT"
            or "WASD OR HOLD THE MOUSE. SHIFT RUNS. R RESTARTS"
        local by = vh - inset.b - 16
        G.label("w", hint, floor((vw - G.textWidth(hint)) / 2), by)
        G.label("m", how, floor((vw - G.textWidth(how)) / 2), by + 8)
    end
end

local function panel(w, h)
    local x, y = floor((vw - w) / 2), floor((vh - h) / 2)
    G.rect("o", x - 1, y - 1, w + 2, h + 2)
    G.rect("w", x, y, w, h)
    G.rect("b", x, y + h - 2, w, 2)
    return x, y
end

local function centred(k, s, y) G.text(k, s, floor((vw - G.textWidth(s)) / 2), y) end

local function drawWon()
    local last = game.n == Level.count()
    local x, y = panel(132, last and 60 or 52)
    centred("p", last and "EVERY FLOCK IS HOME" or "LEVEL COMPLETE", y + 7)
    centred("t", "SHEEP SAVED " .. game.saved .. "/" .. #game.flock.list, y + 19)
    -- One little sheep per sheep saved.
    local n = #game.flock.list
    local sx = floor((vw - n * 5) / 2)
    for k = 1, n do G.rect(k <= game.saved and "s" or "b", sx + (k - 1) * 5, y + 29, 4, 4) end
    if game.t - game.wonAt > 0.8 then
        centred("p", last and "PRESS TO START AGAIN" or "PRESS TO CONTINUE", y + (last and 46 or 40))
    end
end

local function drawPointer()
    if Input.usingTouch or not Input.pointer or love.timer.getTime() - Input.lastMouse > 3 then return end
    local x, y = floor(Input.pointer[1]), floor(Input.pointer[2])
    G.rect("o", x - 1, y - 3, 3, 7)
    G.rect("o", x - 3, y - 1, 7, 3)
    local k = Input.held and "w" or "m"
    G.rect(k, x, y - 2, 1, 5)
    G.rect(k, x - 2, y, 5, 1)
end

function love.draw()
    love.graphics.setCanvas(canvas)
    drawField()
    drawHud()
    if game.state == "won" then drawWon() end
    drawPointer()
    love.graphics.setCanvas()

    G.rect("o", 0, 0, love.graphics.getDimensions())
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas, offX, offY, 0, scale, scale)

    if shots and shots.want then
        shots.want = false
        local name = ("shot-%d-%02d.png"):format(game.n, floor(shots.t))
        canvas:newImageData():encode("png", name)
        print("wrote " .. love.filesystem.getSaveDirectory() .. "/" .. name)
        table.remove(shots.at, 1)
        if #shots.at == 0 then love.event.quit() end
    end
end

function love.keypressed(key)
    Input.keypressed(key)
    if key == "f11" or (key == "return" and love.keyboard.isDown("lalt", "ralt")) then
        love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
        fit()
    elseif key == "r" then
        start(game.n)
    elseif key == "n" then
        start(game.n + 1)
    elseif key == "escape" and not Input.MOBILE then
        love.event.quit()
    end
end

for _, name in ipairs({ "mousepressed", "mousereleased", "mousemoved", "touchpressed", "touchmoved",
    "touchreleased", "gamepadpressed" }) do
    love[name] = Input[name]
end
