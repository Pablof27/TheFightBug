-- The morning map: three fights along the path, your Spirit, marbles and Jar. (GDD §8, trimmed to a straight line.)

local Assets = require("client.assets")
local Paper = require("client.paper")
local Text = require("client.text")
local Audio = require("client.audio")
local Fx = require("client.fx")
local UI = require("client.ui")
local Run = require("sim.run")
local Encounters = require("data.encounters")
local Rivals = require("data.rivals")
local Rules = require("data.rules")
local Bugs = require("data.bugs")

local C = Paper.C
local Map = {}
Map.__index = Map

local NODE_POS = { { x = 330, y = 622 }, { x = 790, y = 548 }, { x = 1240, y = 300 } }
local GO = { x = 1220, y = 18, w = 356, h = 128 }

local function encById(id)
    for _, e in ipairs(Encounters) do if e.id == id then return e end end
end

function Map.new(app, params)
    local self = setmetatable({ app = app, time = 0, hover = nil }, Map)
    self.run = params.run or app.run
    app.run = self.run
    self.overlay = nil
    if params.sum and not params.sum.won then self.overlay = { kind = "lost", sum = params.sum } end
    if params.intro then self.overlay = { kind = "intro" } end
    return self
end

function Map:enter()
    Audio.music("title")
end

function Map:enc() return encById(Run.NODES[self.run.node]) end

function Map:go()
    Audio.play("ui_click")
    self.app.switch("fight", { enc = self:enc(), run = self.run })
end

function Map:update(dt) self.time = self.time + dt end

local function jarSlots(self, x, y)
    local run = self.run
    local w, h = 118, 88
    for i = 1, Run.JAR_SLOTS do
        local e = run.jar[i]
        local sx = x + 14 + (i - 1) * (w + 6)
        local sy = y + 46
        Paper.panel(sx, sy, w, h, { fill = e and C.cream or { 0.8, 0.95, 0.97, 0.5 }, seed = 90 + i, r = 12, line = e and 3 or 2, shadow = e ~= nil, rot = (i % 2 == 0) and 0.012 or -0.012 })
        if e then
            love.graphics.setColor(1, 1, 1, 1)
            Assets.bug[e.species]:draw("idle1", sx + w / 2, sy + 50, 0, 0.26)
            local name = Bugs[e.species].short
            Text.body(name, sx + 4, sy + 56, 9, Text.INK, "center", w - 8)
            if e.tired then
                love.graphics.setColor(1, 1, 1, 1)
                Assets.ui:draw("fx_zzz", sx + w - 22, sy + 20, 0, 0.2)
            end
        end
    end
end

function Map:draw()
    local run = self.run
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(Assets.backdrop.map, 0, 0)

    -- nodes
    for i, pos in ipairs(NODE_POS) do
        local state = i < run.node and "done" or i == run.node and "current" or "locked"
        local enc = encById(Run.NODES[i])
        local bob = state == "current" and math.sin(self.time * 3) * 4 or 0
        local r = state == "current" and 52 or 44
        local fill = state == "done" and C.green or state == "current" and C.yellow or { 0.72, 0.7, 0.78 }
        Paper.disc(pos.x, pos.y + bob, r, fill, { seed = i * 3, shadow = true, line = 5 })
        love.graphics.setColor(1, 1, 1, 1)
        if state == "done" then
            love.graphics.setLineWidth(10)
            love.graphics.setColor(Paper.C.ink[1], Paper.C.ink[2], Paper.C.ink[3], 1)
            love.graphics.line(pos.x - 20, pos.y + bob + 2, pos.x - 6, pos.y + bob + 18, pos.x + 22, pos.y + bob - 16)
            love.graphics.setLineWidth(5)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.line(pos.x - 20, pos.y + bob + 2, pos.x - 6, pos.y + bob + 18, pos.x + 22, pos.y + bob - 16)
        else
            Text.display(tostring(i), pos.x, pos.y + bob - 18, 36, state == "current" and Text.INK or { 1, 1, 1 }, "center")
        end
        -- name tag
        local tw = math.max(150, Text.displayWidth(enc.name, 17) + 36)
        local ty = pos.y + r + 14
        Paper.panel(pos.x - tw / 2, ty, tw, 56, { fill = state == "current" and C.cream or { 0.95, 0.93, 0.98 }, seed = 40 + i, r = 12, line = 3, rot = (i % 2 == 0) and 0.01 or -0.01 })
        Text.display(enc.name, pos.x, ty + 9, 17, Text.INK, "center")
        Text.body(enc.place, pos.x, ty + 34, 10.5, { 0.4, 0.25, 0.5 }, "center")
        if state == "current" then
            local rv = Rivals[enc.rival]
            Paper.disc(pos.x, pos.y - 118 + bob, 62, C.magenta, { seed = 9, shadow = true, line = 4 })
            Paper.disc(pos.x, pos.y - 118 + bob, 54, { 1, 0.84, 0.55 }, { seed = 10, line = 0 })
            love.graphics.setColor(1, 1, 1, 1)
            Assets.drawKid(rv.portrait, "neutral", pos.x, pos.y - 114 + bob, 140)
            -- the hand that points at where you go next
            love.graphics.setColor(1, 1, 1, 1)
            Assets.people:draw("hand_point", pos.x + 70, pos.y + 6 + math.sin(self.time * 4) * 6, 0.5, 0.3)
        end
    end

    -- status band
    Paper.panel(24, 18, 440, 128, { fill = C.cream, seed = 81, r = 18, rot = -0.004, tape = true })
    Text.display("SPIRIT", 46, 36, 16, { 0.45, 0.25, 0.55 })
    for i = 1, run.maxSpirit do
        Paper.heart(196 + (i - 1) * 25, 48, 10, nil, i > run.spirit)
    end
    love.graphics.setColor(1, 1, 1, 1)
    local mw, mh = Assets.ui:size("icon_marble")
    love.graphics.draw(Assets.ui.image, Assets.ui.quads.icon_marble, 62, 98, 0, 44 / mh, 44 / mh, mw / 2, mh / 2)
    Text.display(tostring(run.marbles) .. " MARBLES", 94, 86, 20, Text.INK, "left")
    Text.body("Deck: " .. #run.deck .. " cards   ·   Fights won: " .. run.wins, 46, 118, 12.5, { 0.4, 0.25, 0.5 }, "left")

    -- mission
    local enc = self:enc()
    local rv = Rivals[enc.rival]
    local rule = Rules[enc.rule]
    Paper.panel(480, 18, 724, 128, { fill = { 1, 0.95, 0.7 }, seed = 82, r = 18, rot = 0.004 })
    Text.display("FIGHT " .. run.node .. " OF " .. #Run.NODES .. (enc.boss and " · THE BOSS" or ""), 504, 28, 14, C.magentaDark)
    Text.display(enc.name, 504, 56, 26, Text.INK, "left")
    Text.body(rv.name .. ": \"" .. rv.line.start .. "\"", 504, 90, 14, { 0.4, 0.2, 0.45 }, "left", 680)
    Text.body("Rule: " .. rule.name .. " — " .. rule.short, 504, 112, 13, { 0.15, 0.5, 0.4 }, "left", 680)

    -- go button
    UI.button(GO, "GO FIGHT!", { hover = self.hover == "go" and not self.overlay, size = 34, seed = 83, fill = C.teal })

    -- jar
    Paper.panel(24, 746, 6 * 124 + 40, 142, { fill = { 0.8, 0.95, 0.97 }, seed = 84, r = 18, rot = 0.003 })
    love.graphics.setColor(1, 1, 1, 1)
    local jw, jh = Assets.ui:size("icon_jar")
    love.graphics.draw(Assets.ui.image, Assets.ui.quads.icon_jar, 56, 770, 0, 40 / jh, 40 / jh, jw / 2, jh / 2)
    Text.display("YOUR JAR", 84, 758, 18, Text.INK, "left")
    Text.body("Lose a whole team in a fight and it comes back TIRED (half stamina). Tired twice: it runs away.", 250, 764, 11, { 0.15, 0.4, 0.45 }, "left", 540)
    jarSlots(self, 24, 746)
end

function Map:overlayRect() return { x = 360, y = 170, w = 880, h = 540 } end

function Map:drawOverlay()
    local o = self.overlay
    if not o then return end
    love.graphics.setColor(0.17, 0.07, 0.22, 0.55)
    love.graphics.rectangle("fill", 0, 0, 1600, 900)
    local P = self:overlayRect()
    Paper.panel(P.x, P.y, P.w, P.h, { fill = o.kind == "lost" and { 0.9, 0.85, 1 } or { 1, 0.95, 0.7 }, seed = 85, r = 26, rot = -0.005, tape = true })
    if o.kind == "intro" then
        Text.display("SATURDAY AT THE PARK", P.x + P.w / 2, P.y + 34, 36, C.magenta, "center")
        Text.body("You have a jar of bugs, 10 Spirit and one afternoon before Mom calls you home for dinner.", P.x + 50, P.y + 100, 19, Text.INK, "left", P.w - 100)
        Text.body("Three kids want to fight. Bugs fight by instinct: you NEVER give orders. You play cards that change the world around them, and every bug follows its own nature when its timer hits zero.", P.x + 50, P.y + 170, 17, Text.INK, "left", P.w - 100)
        Text.body("Nothing is random in a fight. Hover everything. Use REWIND (Z) as often as you like: tiny changes make wildly different futures.", P.x + 50, P.y + 262, 17, { 0.4, 0.2, 0.45 }, "left", P.w - 300)
        love.graphics.setColor(1, 1, 1, 1)
        Text.display("CONTROLS", P.x + 50, P.y + 326, 14, C.tealDark, "left")
        Text.body("Click a card, then what it targets.  SPACE waits one tick.  Z rewinds.  TAB hides the arrows.  Right click cancels.  M mutes.", P.x + 50, P.y + 350, 14.5, Text.INK, "left", P.w - 300)
        Assets.bug.mantis:draw("idle1", P.x + P.w - 120, P.y + P.h - 24, 0, 0.62)
        UI.button({ x = P.x + 50, y = P.y + P.h - 100, w = 300, h = 74 }, "LET'S GO!", { hover = self.hover == "ok", size = 30, seed = 86 })
    else
        local s = o.sum
        Text.display("OH NO!", P.x + P.w / 2, P.y + 34, 44, C.purple, "center")
        Text.body("Your side ran out of bugs. You lose " .. math.abs(s.spirit) .. " Spirit (" .. self.run.spirit .. " left).", P.x + 50, P.y + 120, 19, Text.INK, "left", P.w - 100)
        local y = P.y + 180
        if #s.tired > 0 then Text.body("Tired now: " .. table.concat(s.tired, ", ") .. ".", P.x + 50, y, 16, { 0.4, 0.2, 0.45 }, "left", P.w - 100); y = y + 30 end
        if #s.escaped > 0 then Text.body("Ran away for good: " .. table.concat(s.escaped, ", ") .. ".", P.x + 50, y, 16, C.magentaDark, "left", P.w - 100); y = y + 30 end
        Text.body("Rematch! The same fight, the same rival, the same bugs: you only need a different idea.", P.x + 50, y + 10, 17, Text.INK, "left", P.w - 100)
        UI.button({ x = P.x + 50, y = P.y + P.h - 100, w = 300, h = 74 }, "TRY AGAIN", { hover = self.hover == "ok", size = 30, seed = 87, fill = C.orange })
    end
end

function Map:okRect()
    local P = self:overlayRect()
    return { x = P.x + 50, y = P.y + P.h - 100, w = 300, h = 74 }
end

function Map:mousemoved(x, y)
    if self.overlay then self.hover = UI.inside(self:okRect(), x, y) and "ok" or nil; return end
    self.hover = UI.inside(GO, x, y) and "go" or nil
end

function Map:mousepressed(x, y, b)
    if b ~= 1 then return end
    if self.overlay then
        if UI.inside(self:okRect(), x, y) then Audio.play("ui_click"); self.overlay = nil end
        return
    end
    if UI.inside(GO, x, y) then self:go() end
end

function Map:keypressed(key)
    if key == "escape" then self.app.switch("title") return end
    if key == "space" or key == "return" then
        if self.overlay then self.overlay = nil; Audio.play("ui_click") else self:go() end
    end
end

return Map
