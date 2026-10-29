-- Dev-only screenshot / scripting harness. Not part of the game.
--   TFB_HARNESS=tests.harness TFB_SCENARIO=/abs/path/scenario.lua love .
-- A scenario is a Lua file returning function(H) that uses H.wait(frames), H.shot(name), H.click(x, y), H.move(x, y),
-- H.key(k), H.text(t), H.call(fn), H.quit(). Coordinates are virtual (1600x900). Screenshots land in the save directory.

local App = require("client.app")
local Screen = require("client.screen")

local H = { frame = 0 }

love.errorhandler = function(msg)
    print("RUNTIME ERROR: " .. tostring(msg))
    print(debug.traceback("", 2))
    os.exit(1)
end

-- only the scenario drives the game: real mouse / keyboard events are dropped
love.mousemoved, love.mousepressed, love.mousereleased, love.keypressed = function() end, function() end, function() end, function() end
love.textinput = function() end

local function toWindow(x, y) return x * Screen.scale + Screen.ox, y * Screen.scale + Screen.oy end

function H.wait(n) for _ = 1, n or 1 do coroutine.yield() end end
function H.move(x, y) local px, py = toWindow(x, y); App.mousemoved(px, py) end
function H.click(x, y, b)
    H.move(x, y)
    H.wait(2)
    local px, py = toWindow(x, y)
    App.mousepressed(px, py, b or 1)
    H.wait(1)
    App.mousereleased(px, py, b or 1)
    H.wait(1)
end
function H.key(k) App.keypressed(k, false); H.wait(1) end
function H.text(t) App.textinput(t); H.wait(1) end
function H.call(fn) return fn(App) end
function H.scene() return App.scene end
function H.quit() love.event.quit() end

local pending = 0
function H.shot(name)
    H.wait(3)
    pending = pending + 1
    love.graphics.captureScreenshot(function(img)
        img:encode("png", name .. ".png")
        pending = pending - 1
        print("SHOT " .. love.filesystem.getSaveDirectory() .. "/" .. name .. ".png")
    end)
    H.wait(3)
end

function H.log(...) print("LOG", ...) end

local co
local function start()
    local path = os.getenv("TFB_SCENARIO")
    local fn = assert(loadfile(path))()
    co = coroutine.create(function() fn(H) end)
end

local origUpdate = love.update
love.update = function(dt)
    origUpdate(dt)
    H.frame = H.frame + 1
    if H.frame == 5 and not co then start() end
    if co and coroutine.status(co) ~= "dead" then
        local ok, err = coroutine.resume(co)
        if not ok then
            print("SCENARIO ERROR: " .. tostring(err))
            print(debug.traceback(co))
            os.exit(1)
        end
    end
end

return H
