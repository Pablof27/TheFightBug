-- TheFightBug - LÖVE entry point.   Run:  love /path/to/TheFightBug
-- All the game lives in src/: sim/ (pure simulation), data/ (content), client/ (what you see and hear).

love.filesystem.setRequirePath("src/?.lua;src/?/init.lua;lib/?.lua;lib/knife/?.lua;" .. love.filesystem.getRequirePath())

local App = require("client.app")

function love.load(args) App.load(args) end
function love.update(dt) App.update(dt) end
function love.draw() App.draw() end
function love.resize(w, h) App.resize(w, h) end
function love.mousepressed(x, y, b, istouch) App.mousepressed(x, y, b) end
function love.mousereleased(x, y, b, istouch) App.mousereleased(x, y, b) end
function love.mousemoved(x, y, dx, dy) App.mousemoved(x, y) end
function love.wheelmoved(x, y) App.wheelmoved(x, y) end
function love.keypressed(key, scancode, isrepeat) App.keypressed(key, isrepeat) end
function love.textinput(t) end

-- Dev only: TFB_HARNESS=tests.harness love .   loads a script that can drive the game and take screenshots.
local harness = os.getenv("TFB_HARNESS")
if harness and harness ~= "" then require(harness) end
