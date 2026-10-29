-- The end of the demo: sunset (you release your bugs and Mom calls) or a lost run (you can't cover the next bet).

local Assets = require("client.assets")
local Paper = require("client.paper")
local Text = require("client.text")
local Audio = require("client.audio")
local Fx = require("client.fx")
local UI = require("client.ui")
local Run = require("sim.run")
local Bugs = require("data.bugs")
local Rivals = require("data.rivals")

local C = Paper.C
local Ending = {}
Ending.__index = Ending

local AGAIN = { x = 190, y = 760, w = 340, h = 96 }
local QUIT = { x = 560, y = 776, w = 200, h = 64 }
-- In a browser, quitting would only freeze the page: no QUIT there.
local CAN_QUIT = love.system.getOS() ~= "Web"

function Ending.new(app, params)
    local self = setmetatable({ app = app, time = 0, hover = nil }, Ending)
    self.run, self.won, self.sum = params.run, params.won, params.sum
    self.walkers = {}
    for i, e in ipairs(self.run.jar) do
        self.walkers[i] = { sp = e.species, x = 60 + (i - 1) * 118, phase = i * 1.3, delay = 1.5 + i * 0.5, tired = e.tired }
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
        Text.body("You beat all three rivals. Mom calls from across the lawn: dinner time!", 170, 150, 19, Text.INK, "left", 740)
        Text.body("You tip the jar over and let your bugs walk back into the grass. They'll still be here tomorrow.", 170, 205, 17, Text.INK, "left", 740)
    else
        Text.display("THE PARK CAN WAIT", 540, 70, 46, C.purple, "center")
        local rv = Rivals[Run.encounter(run).rival]
        Text.body("You have " .. run.marbles .. (run.marbles == 1 and " marble" or " marbles") .. " left, and " .. rv.name .. " won't play for less than " .. rv.bet .. ". Nobody plays with a kid who can't pay up, so everybody goes home early.", 170, 140, 18, Text.INK, "left", 740)
        Text.body("Try again: a new idea, a different card, a smarter buy at the Swap Shop. Nothing in a fight is random.", 170, 224, 16, Text.INK, "left", 740)
    end
    -- numbers
    local sx, sy = 170, 290
    local function stat(label, value, x, y, col)
        Text.display(value, x, y, 38, col or Text.INK, "left")
        Text.display(label, x, y + 52, 12, { 0.4, 0.25, 0.5 }, "left")
    end
    stat("FIGHTS WON", tostring(run.wins) .. "/3", sx, sy, C.tealDark)
    stat("MARBLES", tostring(run.marbles), sx + 240, sy, C.orange)
    stat("REWINDS USED", tostring(run.rewinds or 0), sx + 480, sy, C.purple)
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
    Text.body("Next in the full game: a whole park map, benches, wild events, bosses with real kid-sized rules, and the Bug Journal as a collection.", 170, 585, 14, Text.INK, "left", 740)

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
    self.app.switch("title")
end

function Ending:mousepressed(x, y, b)
    if b ~= 1 then return end
    if UI.inside(AGAIN, x, y) then self:again() elseif CAN_QUIT and UI.inside(QUIT, x, y) then love.event.quit() end
end

function Ending:keypressed(key)
    if key == "space" or key == "return" then self:again() elseif key == "escape" and CAN_QUIT then love.event.quit() end
end

return Ending
