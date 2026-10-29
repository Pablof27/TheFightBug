-- Application shell: window, scene stack, transitions (a cartoon iris wipe), global keys.

local Screen = require("client.screen")
local Assets = require("client.assets")
local Tween = require("client.tween")
local Audio = require("client.audio")
local Fx = require("client.fx")

-- debug: launched with --debug (love . --debug). New games then ask for the seed of their random generator.
local App = { scene = nil, time = 0, trans = nil, mouse = { x = 0, y = 0 }, cursor = true, debug = false }

local scenes = {}

local function hasFlag(args, flag)
    for _, a in ipairs(args or {}) do if a == flag then return true end end
    return false
end

function App.load(args)
    App.debug = hasFlag(args, "--debug")
    love.graphics.setBackgroundColor(0.17, 0.07, 0.22)
    love.mouse.setVisible(false)
    Screen.resize()
    local mx, my = Screen.toVirtual(love.mouse.getPosition())
    App.mouse.x, App.mouse.y = mx, my
    Assets.load()
    scenes.title = require("client.scenes.title")
    scenes.slots = require("client.scenes.slots")
    scenes.map = require("client.scenes.map")
    scenes.fight = require("client.scenes.fight")
    scenes.shop = require("client.scenes.shop")
    scenes.ending = require("client.scenes.ending")
    App.switch(hasFlag(args, "--fight") and "fight" or "title", {}, true)
end

--- Change scene with an iris wipe. params go to the new scene's enter().
function App.switch(name, params, instant)
    local function go()
        Tween.clear()
        Fx.clear()
        if App.scene and App.scene.leave then App.scene.leave(App.scene) end
        App.scene = scenes[name].new(App, params or {})
        App.sceneName = name
        if App.scene.enter then App.scene:enter() end
    end
    if instant or not App.scene then go(); App.trans = nil; return end
    if App.trans then return end
    App.trans = { phase = "close", r = 1, name = name, go = go }
    Tween.to(App.trans, { r = 0 }, 0.35, "inCubic", function()
        App.trans.go()
        App.trans.phase = "open"
        Tween.to(App.trans, { r = 1 }, 0.4, "outCubic", function() App.trans = nil end)
    end)
end

function App.resize(w, h) Screen.resize(w, h) end

function App.update(dt)
    dt = math.min(dt, 1 / 20)
    App.time = App.time + dt
    Tween.update(dt)
    Fx.update(dt)
    Audio.update(dt)
    if App.scene and App.scene.update and not (App.trans and App.trans.phase == "close" and App.trans.r < 0.05) then App.scene:update(dt) end
end

local function drawCursor()
    local scene = App.scene
    if scene and scene.drawCursor then scene:drawCursor(App.mouse.x, App.mouse.y, App.time); return end
    love.graphics.setColor(1, 1, 1, 1)
    Assets.people:draw("hand_point", App.mouse.x, App.mouse.y, 0, 0.32)
end

function App.draw()
    love.graphics.clear(0.17, 0.07, 0.22)
    Screen.begin()
    if App.scene then App.scene:draw() end
    Fx.draw()
    if App.scene and App.scene.drawOverlay then App.scene:drawOverlay() end
    if App.trans then
        local t = App.trans
        love.graphics.stencil(function()
            love.graphics.circle("fill", Screen.W / 2, Screen.H / 2, math.max(0.001, t.r * 1100), 64)
        end, "replace", 1)
        love.graphics.setStencilTest("notequal", 1)
        love.graphics.setColor(0.17, 0.07, 0.22, 1)
        love.graphics.rectangle("fill", 0, 0, Screen.W, Screen.H)
        love.graphics.setStencilTest()
    end
    if App.cursor then drawCursor() end
    Screen.finish()
    -- letterbox bars
    love.graphics.setColor(0.1, 0.03, 0.14, 1)
    local w, h = love.graphics.getDimensions()
    if Screen.ox > 0 then love.graphics.rectangle("fill", 0, 0, Screen.ox, h); love.graphics.rectangle("fill", w - Screen.ox, 0, Screen.ox, h) end
    if Screen.oy > 0 then love.graphics.rectangle("fill", 0, 0, w, Screen.oy); love.graphics.rectangle("fill", 0, h - Screen.oy, w, Screen.oy) end
end

local function blocked() return App.trans ~= nil end

function App.mousepressed(x, y, b)
    if blocked() then return end
    local vx, vy = Screen.toVirtual(x, y)
    if App.scene and App.scene.mousepressed then App.scene:mousepressed(vx, vy, b) end
end

function App.mousereleased(x, y, b)
    local vx, vy = Screen.toVirtual(x, y)
    if App.scene and App.scene.mousereleased then App.scene:mousereleased(vx, vy, b) end
end

function App.mousemoved(x, y)
    local vx, vy = Screen.toVirtual(x, y)
    App.mouse.x, App.mouse.y = vx, vy
    if App.scene and App.scene.mousemoved then App.scene:mousemoved(vx, vy) end
end

function App.wheelmoved(x, y) end

function App.keypressed(key, isrepeat)
    if key == "m" then Audio.toggleMute() return end
    if key == "f11" then love.window.setFullscreen(not love.window.getFullscreen()) return end
    if blocked() then return end
    if App.scene and App.scene.keypressed then App.scene:keypressed(key, isrepeat) end
end

--- Typed text (after the keyboard layout is applied), for scenes with a text field.
function App.textinput(t)
    if blocked() then return end
    if App.scene and App.scene.textinput then App.scene:textinput(t) end
end

return App
