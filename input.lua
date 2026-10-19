-- One way to move the dog, however it was asked for.
--
-- Desktop: WASD / arrows walk (shift runs), or hold the left mouse button and
--          the dog goes to the cursor -- a short way off creeps, far off runs.
-- Gamepad: the left stick, analogue, so a light push is a creep.
-- Touch:   hold a finger down and the dog goes to it, as the mouse does. That
--          is the whole control: a herding dog only needs a place to be.
--
-- Bark:    space, the right mouse button, a gamepad's A or X, or a second
--          finger put down while the first is held.
--
-- Everything is reported in canvas pixels, never window pixels (Survive
-- School's rule), and main.lua turns those into field units.

local Input = {}

local scale, offX, offY = 1, 0, 0
local touchId
Input.pointer = nil  -- canvas pixel the mouse or finger is at
Input.held = false
Input.lastMouse = -10
Input.usingTouch = false
Input.tapped = false -- any press this frame, for "continue"
Input.barked = false -- a bark asked for this frame
Input.clicked = nil  -- canvas pixel of a left click or a first finger this frame, for menus

local OS = love.system.getOS()
Input.MOBILE = OS == "Android" or OS == "iOS"

local DEAD = 0.2

function Input.setTransform(s, ox, oy) scale, offX, offY = s, ox, oy end

local function toCanvas(x, y) return (x - offX) / scale, (y - offY) / scale end

function Input.mousepressed(x, y, b, istouch)
    if istouch then return end
    Input.tapped = true
    Input.usingTouch = false
    if b == 1 then
        Input.held = true
        Input.pointer = { toCanvas(x, y) }
        Input.clicked = { toCanvas(x, y) }
    elseif b == 2 then
        Input.barked = true
    end
end

function Input.mousereleased(_, _, b, istouch)
    if istouch then return end
    if b == 1 then Input.held = false end
end

function Input.mousemoved(x, y, _, _, istouch)
    if istouch then return end
    Input.pointer = { toCanvas(x, y) }
    Input.lastMouse = love.timer.getTime()
    Input.usingTouch = false
end

function Input.touchpressed(id, x, y)
    Input.tapped = true
    Input.usingTouch = true
    if not touchId then
        touchId = id
        Input.held = true
        Input.pointer = { toCanvas(x, y) }
        Input.clicked = { toCanvas(x, y) }
    else
        Input.barked = true
    end
end

function Input.touchmoved(id, x, y)
    if id == touchId then Input.pointer = { toCanvas(x, y) } end
end

function Input.touchreleased(id)
    if id == touchId then
        touchId = nil
        Input.held = false
    end
end

-- Backgrounding swallows the release: nothing stays held.
function Input.releaseAll()
    touchId = nil
    Input.held = false
end

local function gamepad()
    for _, j in ipairs(love.joystick.getJoysticks()) do
        if j:isGamepad() then
            local x, z = j:getGamepadAxis("leftx"), j:getGamepadAxis("lefty")
            if j:isGamepadDown("dpleft") then x = -1 end
            if j:isGamepadDown("dpright") then x = 1 end
            if j:isGamepadDown("dpup") then z = -1 end
            if j:isGamepadDown("dpdown") then z = 1 end
            local l = math.sqrt(x * x + z * z)
            if l > DEAD then
                -- Rescaled past the dead zone, so the gentlest push is a creep.
                local m = math.min(1, (l - DEAD) / (1 - DEAD))
                return x / l * m, z / l * m
            end
        end
    end
end

-- What the dog should do this frame (see Dog:update), in canvas pixels for a point.
function Input.move()
    local k = love.keyboard.isDown
    local x, z = 0, 0
    if k("a", "left") then x = x - 1 end
    if k("d", "right") then x = x + 1 end
    if k("w", "up") then z = z - 1 end
    if k("s", "down") then z = z + 1 end
    if x ~= 0 or z ~= 0 then
        local l = math.sqrt(x * x + z * z)
        local m = k("lshift", "rshift") and 1 or require("dog").CONFIG.walk
        return { dir = true, x = x / l * m, z = z / l * m }
    end
    local gx, gz = gamepad()
    if gx then return { dir = true, x = gx, z = gz } end
    if Input.held and Input.pointer then
        return { point = true, x = Input.pointer[1], y = Input.pointer[2] }
    end
end

function Input.gamepadpressed(_, b)
    Input.tapped = true
    if b == "a" or b == "x" then Input.barked = true end
end

function Input.keypressed(key)
    Input.tapped = true
    if key == "space" then Input.barked = true end
end

-- Called at the end of every frame: the one-frame flags drop.
function Input.endFrame()
    Input.tapped, Input.barked, Input.clicked = false, false, nil
end

return Input
