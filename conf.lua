function love.conf(t)
    t.identity = "thefightbug"
    t.version = "11.5"
    t.window.title = "TheFightBug - demo"
    t.window.icon = "resources/art/icon.png"
    t.window.width = 1280
    t.window.height = 720
    t.window.minwidth = 800
    t.window.minheight = 450
    t.window.resizable = true
    t.window.vsync = 1
    t.window.msaa = 4
    t.window.highdpi = true
    t.modules.physics = false
    t.modules.joystick = false
    t.modules.video = false
end
