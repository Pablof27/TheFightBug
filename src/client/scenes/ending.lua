-- The end of the day: sunset (you got past all three Gang leaders: you release your bugs and Mom calls) or home early
-- (out of marbles, and Big Sister has already helped once).

local Assets = require("client.assets")
local Paper = require("client.paper")
local Text = require("client.text")
local Audio = require("client.audio")
local Fx = require("client.fx")
local UI = require("client.ui")
local Run = require("sim.run")
local Bugs = require("data.bugs")

local C = Paper.C
local Ending = {}
Ending.__index = Ending

local AGAIN = { x = 190, y = 760, w = 340, h = 96 }
local QUIT = { x = 560, y = 776, w = 200, h = 64 }
-- In a browser, quitting would only freeze the page: no QUIT there.
local CAN_QUIT = love.system.getOS() ~= "Web"

function Ending.new(app, params)
    local self = setmetatable({ app = app, time = 0, hover = nil }, Ending)
    self.run = params.run
    self.won = params.won
    if self.won == nil then self.won = self.run.result and self.run.result.won or false end
    self.walkers = {}
    for i, e in ipairs(self.run.jar) do
        self.walkers[i] = { sp = e.species, x = 60 + (i - 1) * 118, phase = i * 1.3, delay = 1.5 + i * 0.5 }
    end
    return self
end

function Ending:enter()
    Audio.music("title")
    Audio.play(self.won and "win" or "lose")
    if self.won then for i = 1, 6 do Fx.sparkle(200 + i * 200, 200, 3, 60) end end
end

function Ending:update(dt)
    self.time = self.time + dt
    for _, w in ipairs(self.walkers) do
        if self.won and self.time > w.delay then w.x = w.x + 120 * dt end
    end
end

function Ending:draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(Assets.backdrop.title, 0, 0)
    local run = self.run
    Paper.panel(120, 40, 840, 620, { fill = self.won and { 1, 0.95, 0.7 } or { 0.9, 0.85, 1 }, seed = 95, r = 28, rot = -0.004, tape = true })
    if self.won then
        Text.display("SUNSET AT THE PARK", 540, 70, 46, C.magenta, "center")
        local a = "You got past all three Gang leaders. Mom calls from across the lawn: dinner time!"
        Text.body(a, 170, 140, 19, Text.INK, "left", 740)
        Text.body("You tip the jar over and let your bugs walk back into the grass. They'll still be here tomorrow.", 170, 140 + Text.bodyHeight(a, 19, 740) + 12, 17, Text.INK, "left", 740)
    else
        Text.display("HOME EARLY", 540, 70, 46, C.purple, "center")
        local a = "Out of marbles in the " .. Run.actDef(run).name:lower() .. ". Nobody plays with a kid with empty pockets, and Big Sister has already helped once today. You walk home with your jar."
        Text.body(a, 170, 136, 18, Text.INK, "left", 740)
        Text.body("Try again: another corner of the park, other hunts, a smarter buy at the van. Nothing in a fight is random.", 170, 136 + Text.bodyHeight(a, 18, 740) + 12, 16, Text.INK, "left", 740)
    end
    -- numbers
    local sx, sy = 170, 290
    local function stat(label, value, x, y, col)
        Text.display(value, x, y, 38, col or Text.INK, "left")
        Text.display(label, x, y + 52, 12, { 0.4, 0.25, 0.5 }, "left")
    end
    stat("KIDS BROKE", tostring(run.broke or 0), sx, sy, C.tealDark)
    stat("BUGS CAUGHT", tostring(run.caught or 0), sx + 190, sy, C.green)
    stat("MARBLES", tostring(run.marbles), sx + 380, sy, C.orange)
    stat("REWINDS", tostring(run.rewinds or 0), sx + 570, sy, C.purple)
    -- journal
    Text.display("BUG JOURNAL", 170, 400, 16, C.tealDark, "left")
    local seen = {}
    for id in pairs(run.seen) do seen[#seen + 1] = id end
    table.sort(seen)
    for i, id in ipairs(seen) do
        local x = 200 + (i - 1) * 84
        Paper.disc(x, 482, 36, C.cream, { seed = i, shadow = true, line = 3.5 })
        love.graphics.setColor(1, 1, 1, 1)
        Assets.drawPortrait(id, x, 482, 62)
    end
    Text.body(#seen .. " of 9 species met in this demo. The full game has 30+ to meet, catch and learn about.", 170, 545, 14, { 0.4, 0.25, 0.5 }, "left", 740)
    Text.body("Next in the full game: more corners of the park and more games, weather, Big Kids, bugs that come out at dusk, and new things to unlock between days.", 170, 585, 14, Text.INK, "left", 740)

    -- walkers go home
    for _, w in ipairs(self.walkers) do
        local atlas = Assets.bug[w.sp]
        local frame = Assets.animFrame(w.sp, "walk", math.floor(self.time * 9 + w.phase) % 4 + 1)
        local moving = self.won and self.time > w.delay
        if not moving then frame = Assets.animFrame(w.sp, "idle", math.floor(self.time * 3 + w.phase) % 3 + 1) end
        local y = 740 - 0
        local hop = moving and math.abs(math.sin(self.time * 9 + w.phase)) * 5 or 0
        love.graphics.setColor(Paper.C.ink[1], Paper.C.ink[2], Paper.C.ink[3], 0.3)
        love.graphics.ellipse("fill", w.x + 380, y, 40, 10)
        love.graphics.setColor(1, 1, 1, 1)
        if w.x + 380 < 1750 and (y > 0) then atlas:draw(frame, w.x + 380, y - hop - (w.sp == "wasp" and 36 or 0), 0, 0.5, 0.5) end
    end

    UI.button(AGAIN, self.won and "PLAY AGAIN" or "TRY AGAIN", { hover = self.hover == "again", size = 38, seed = 96, fill = self.won and C.teal or C.orange })
    if CAN_QUIT then UI.button(QUIT, "QUIT", { hover = self.hover == "quit", size = 24, seed = 97, fill = C.purpleLight }) end
end

function Ending:mousemoved(x, y)
    self.hover = UI.inside(AGAIN, x, y) and "again" or CAN_QUIT and UI.inside(QUIT, x, y) and "quit" or nil
end

function Ending:again()
    Audio.play("ui_click")
    self.app.switch("slots")
end

function Ending:mousepressed(x, y, b)
    if b ~= 1 then return end
    if UI.inside(AGAIN, x, y) then self:again() elseif CAN_QUIT and UI.inside(QUIT, x, y) then love.event.quit() end
end

function Ending:keypressed(key)
    if key == "space" or key == "return" then self:again() elseif key == "escape" and CAN_QUIT then love.event.quit() end
end

return Ending
