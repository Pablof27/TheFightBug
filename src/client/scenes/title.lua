-- Title screen: sunset park, the logo, a parade of bugs marching past the grass.

local Assets = require("client.assets")
local Paper = require("client.paper")
local Text = require("client.text")
local Audio = require("client.audio")
local Fx = require("client.fx")
local Tween = require("client.tween")
local UI = require("client.ui")
local Run = require("sim.run")

local C = Paper.C
local Title = {}
Title.__index = Title

local ORDER = { "ant", "pillbug", "stag", "cricket", "wasp", "mantis", "redant", "spider", "hercules" }
local PLAY = { x = 352, y = 560, w = 400, h = 110 }
local QUIT = { x = 432, y = 700, w = 240, h = 70 }

function Title.new(app, params)
    local self = setmetatable({ app = app, time = 0, hover = nil, logoPop = 0 }, Title)
    self.parade = {}
    for i, sp in ipairs(ORDER) do
        self.parade[i] = { sp = sp, x = -150 - (i - 1) * 260, speed = 62 + (i * 37 % 29), lane = i % 3, phase = i * 1.7 }
    end
    return self
end

function Title:enter()
    Audio.music("title")
    self.logoScale = 0.1
    Tween.to(self, { logoScale = 0.72 }, 0.9, "outBack")
end

function Title:start()
    Audio.play("ui_click")
    Audio.play("win", 0.4)
    self.app.run = Run.new(7)
    self.app.switch("map", { run = self.app.run, intro = true })
end

function Title:update(dt)
    self.time = self.time + dt
    for _, p in ipairs(self.parade) do
        p.x = p.x + p.speed * dt
        if p.x > 1800 then p.x = -200 end
    end
end

function Title:draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(Assets.backdrop.title, 0, 0)
    -- logo with a gentle bob
    local s = self.logoScale or 0.72
    local bob = math.sin(self.time * 1.6) * 6
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(Assets.logo, 552, 280 + bob, math.sin(self.time * 1.1) * 0.012, s, s, 600, 340)
    -- parade (back lanes first)
    local list = {}
    for _, p in ipairs(self.parade) do list[#list + 1] = p end
    table.sort(list, function(a, b) return a.lane < b.lane end)
    for _, p in ipairs(list) do
        local atlas = Assets.bug[p.sp]
        local frame = Assets.animFrame(p.sp, "walk", math.floor(self.time * 9 + p.phase) % 4 + 1)
        local y = 846 + p.lane * 22
        local hop = math.abs(math.sin(self.time * 9 + p.phase)) * 5
        local fly = p.sp == "wasp" and (40 + math.sin(self.time * 3 + p.phase) * 14) or 0
        love.graphics.setColor(Paper.C.ink[1], Paper.C.ink[2], Paper.C.ink[3], 0.3)
        love.graphics.ellipse("fill", p.x, y, 46, 12)
        love.graphics.setColor(1, 1, 1, 1)
        atlas:draw(frame, p.x, y - hop - fly, 0, 0.62, 0.62)
    end
    -- buttons
    UI.button(PLAY, "PLAY!", { hover = self.hover == "play", size = 54, seed = 71, fill = C.teal })
    UI.button(QUIT, "QUIT", { hover = self.hover == "quit", size = 26, seed = 72, fill = C.orange })
    Text.body("Press SPACE to play  ·  M mutes  ·  F11 fullscreen", 552, 790, 14, { 1, 1, 1 }, "center", nil, 2)
    Text.body("A first playable demo.  All art and sound are hand-made by the project's own HTML/JS workshop tools.", 800, 876, 12.5, { 1, 0.95, 0.85 }, "center", nil, 2)
end

function Title:mousemoved(x, y)
    self.hover = UI.inside(PLAY, x, y) and "play" or UI.inside(QUIT, x, y) and "quit" or nil
end

function Title:mousepressed(x, y, b)
    if b ~= 1 then return end
    if UI.inside(PLAY, x, y) then self:start() elseif UI.inside(QUIT, x, y) then love.event.quit() end
end

function Title:keypressed(key)
    if key == "space" or key == "return" then self:start() elseif key == "escape" then love.event.quit() end
end

return Title
