function love.conf(t)
    t.identity = "counting-sheep"
    -- The running engine, on purpose, as in underroot and herding: the field only
    -- decides whether LÖVE opens its "Compatibility Warning" box.
    t.version = love._version
    t.console = false

    t.window.title = "Counting Sheep"
    t.window.width = 1280
    t.window.height = 720
    t.window.minwidth = 320
    t.window.minheight = 240
    t.window.resizable = true
    -- Over the whole screen on a phone (the only way to have all of it); a
    -- window on a computer, F11 or alt+enter for fullscreen.
    t.window.fullscreentype = "desktop"
    t.window.vsync = 1
    -- Real pixels, not points: the zoom is picked off the short edge in pixels,
    -- and a game pixel must land on a whole number of them.
    t.window.highdpi = true
    t.window.usedpiscale = false

    -- Sound is made at load (audio.lua): no files, just these two modules.
    t.modules.audio = true
    t.modules.sound = true
    t.modules.physics = false
    t.modules.video = false
    t.modules.joystick = false
    t.modules.touch = true
end
