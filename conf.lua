function love.conf(t)
    t.identity = "herding"
    -- The running engine, on purpose, as in underroot and Survive School: the
    -- field only decides whether LÖVE opens its "Compatibility Warning" box,
    -- and a game that ships on 11.x desktop and 12.0 Android must not box one.
    t.version = love._version
    t.console = false

    t.window.title = "Herding"
    t.window.width = 1280
    t.window.height = 720
    t.window.minwidth = 320
    t.window.minheight = 180
    t.window.resizable = true
    -- Over the whole screen everywhere; F11 / alt+enter drops back to a window.
    -- "desktop" keeps the display's own mode, so the zoom is picked off real pixels.
    t.window.fullscreen = true
    t.window.fullscreentype = "desktop"
    t.window.vsync = 1
    -- No DPI scaling: a game pixel must land on a whole number of screen pixels.
    t.window.highdpi = false
    t.window.usedpiscale = false

    t.modules.audio = false
    t.modules.sound = false
    t.modules.physics = false
    t.modules.video = false
    t.modules.joystick = true
    t.modules.touch = true
end
