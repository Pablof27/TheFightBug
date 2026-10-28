-- After a win: pick ONE prize — a new card, the bug you bet for, or a nap for your tired bugs — and read what is new in the Bug Journal.

local Assets = require("client.assets")
local Paper = require("client.paper")
local Text = require("client.text")
local Audio = require("client.audio")
local Fx = require("client.fx")
local Tween = require("client.tween")
local UI = require("client.ui")
local HandView = require("client.fight.hand_view")
local Run = require("sim.run")
local Cards = require("data.cards")
local Bugs = require("data.bugs")

local C = Paper.C
local Reward = {}
Reward.__index = Reward

local CW, CH = 172, 236     -- prize size
local CARD_SCALE = 172 / 150

function Reward.new(app, params)
    local self = setmetatable({ app = app, time = 0, hover = nil, picked = nil }, Reward)
    self.run, self.enc, self.sum = params.run, params.enc, params.sum
    local r = Run.REWARDS[self.enc.id] or { cards = {}, bets = {} }
    self.options = {}
    for _, id in ipairs(r.cards or {}) do self.options[#self.options + 1] = { kind = "card", id = id } end
    for _, sp in ipairs(r.bets or {}) do self.options[#self.options + 1] = { kind = "bug", species = sp } end
    local anyTired = false
    for _, e in ipairs(self.run.jar) do if e.tired then anyTired = true end end
    self.options[#self.options + 1] = { kind = "rest", disabled = not anyTired }
    local n = #self.options
    local spacing = 204
    for i, o in ipairs(self.options) do
        o.x = 800 + (i - (n + 1) / 2) * spacing
        o.y = 360
        o.pop = 0
        if o.kind == "bug" and #self.run.jar >= Run.JAR_SLOTS then o.disabled = true; o.full = true end
    end
    return self
end

function Reward:enter()
    Audio.music("title")
    Audio.play("win", 0.6)
    for i, o in ipairs(self.options) do
        o.pop = 0
        Tween.after(0.1 * i, function() Tween.to(o, { pop = 1 }, 0.4, "outBack") end)
    end
end

function Reward:update(dt) self.time = self.time + dt end

function Reward:rect(o)
    return { x = o.x - CW / 2, y = o.y - CH / 2, w = CW, h = CH }
end

function Reward:take(o)
    if self.picked or o.disabled then return end
    self.picked = o
    Audio.play("coin")
    if o.kind == "card" then Run.addCard(self.run, o.id)
    elseif o.kind == "bug" then Run.addBug(self.run, o.species); self.run.seen[o.species] = true
    else Run.rest(self.run) end
    Fx.sparkle(o.x, o.y, 16, 80)
    Fx.text(o.kind == "card" and "NEW CARD!" or o.kind == "bug" and "NEW BUG!" or "ZZZ... REFRESHED!", o.x, o.y - 160, C.yellow, 34)
    Tween.to(o, { pop = 1.18 }, 0.25, "outBack")
    Tween.after(1.2, function() self.app.switch("map", { run = self.run }) end)
end

local function drawPrize(self, o)
    local k = o.pop
    if k <= 0.01 then return end
    local lift = (self.hover == o and not self.picked) and -10 or 0
    local dim = self.picked and self.picked ~= o
    love.graphics.push()
    love.graphics.translate(o.x, o.y + lift)
    love.graphics.scale(k, k)
    if dim then love.graphics.setColor(1, 1, 1, 0.35) end
    if o.kind == "card" then
        love.graphics.scale(CARD_SCALE, CARD_SCALE)
        love.graphics.setColor(1, 1, 1, dim and 0.35 or 1)
        HandView.drawCard(o.id, { glow = self.hover == o })
    elseif o.kind == "bug" then
        local sp = Bugs[o.species]
        Paper.panel(-CW / 2, -CH / 2, CW, CH, { fill = o.disabled and { 0.75, 0.73, 0.8 } or { 1, 0.86, 0.9 }, seed = 61, r = 16, line = 4, rot = 0.008 })
        love.graphics.setColor(1, 1, 1, 1)
        Paper.disc(0, -40, 58, C.magenta, { seed = 3, shadow = true, line = 4 })
        Paper.disc(0, -40, 50, C.cream, { seed = 4, line = 0 })
        love.graphics.setColor(1, 1, 1, 1)
        Assets.drawPortrait(o.species, 0, -40, 96)
        Text.display(sp.short, -CW / 2 + 8, 34, 17, Text.INK, "center", CW - 16)
        Text.body(sp.role, 0, 58, 12, { 0.4, 0.25, 0.5 }, "center")
        Text.body("Stamina " .. sp.hp .. "   Bite " .. sp.bite, 0, 80, 11.5, Text.INK, "center")
        Text.body("Timer " .. sp.timer .. "   Move " .. sp.move, 0, 98, 11.5, Text.INK, "center")
    else
        Paper.panel(-CW / 2, -CH / 2, CW, CH, { fill = o.disabled and { 0.75, 0.73, 0.8 } or { 0.8, 0.95, 0.97 }, seed = 62, r = 16, line = 4, rot = -0.008 })
        love.graphics.setColor(1, 1, 1, 1)
        Assets.ui:draw("fx_zzz", 0, -48, 0, 0.5)
        Text.display("A NAP", 0, 18, 26, Text.INK, "center")
        Text.body(o.disabled and "Nobody is tired." or "Tired bugs get their stamina back.", -CW / 2 + 14, 62, 13, Text.INK, "center", CW - 28)
    end
    love.graphics.pop()
end

function Reward:draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(Assets.backdrop.map, 0, 0)
    love.graphics.setColor(0.17, 0.07, 0.22, 0.45)
    love.graphics.rectangle("fill", 0, 0, 1600, 900)
    Paper.panel(120, 40, 1360, 730, { fill = { 1, 0.95, 0.7 }, seed = 91, r = 30, rot = -0.003, tape = true })
    Text.display("YOU WON!", 800, 66, 58, C.magenta, "center")
    local sum = self.sum
    Text.body("+" .. (sum.marbles or 0) .. " marbles.  Pick ONE prize:", 800, 140, 20, Text.INK, "center")
    -- group labels
    local groups = {}
    for _, o in ipairs(self.options) do
        local g = groups[o.kind]
        if not g then g = { x0 = o.x, x1 = o.x }; groups[o.kind] = g end
        g.x0, g.x1 = math.min(g.x0, o.x), math.max(g.x1, o.x)
    end
    local names = { card = "A NEW TRICK", bug = "THE BET: A BUG FOR YOUR JAR", rest = "OR JUST REST" }
    for kind, g in pairs(groups) do
        Text.display(names[kind], (g.x0 + g.x1) / 2, 200, 15, C.magentaDark, "center")
    end
    for _, o in ipairs(self.options) do drawPrize(self, o) end

    -- description of what you point at
    local o = self.hover
    local py = 520
    Paper.panel(160, py, 780, 160, { fill = C.cream, seed = 92, r = 18, rot = 0.003 })
    if o and o.kind == "card" then
        local def = Cards[o.id]
        Text.display(def.name, 186, py + 18, 24, Text.INK, "left")
        Text.display(def.type .. " card · costs " .. def.cost, 186, py + 52, 13, C.magentaDark, "left")
        Text.body(def.text, 186, py + 78, 16, Text.INK, "left", 730)
        Text.body('"' .. def.flavor .. '"', 186, py + 118, 13.5, { 0.4, 0.25, 0.5 }, "left", 730)
    elseif o and o.kind == "bug" then
        local sp = Bugs[o.species]
        Text.display(sp.name, 186, py + 16, 22, Text.INK, "left")
        Text.body(sp.latin .. " · " .. sp.role, 186, py + 48, 13, { 0.4, 0.25, 0.5 }, "left", 730)
        Text.body(sp.rules.action, 186, py + 72, 14.5, Text.INK, "left", 730)
        Text.body(sp.trait, 186, py + 112, 13.5, { 0.15, 0.5, 0.4 }, "left", 730)
        if o.full then Text.body("Your Jar is full!", 186, py + 136, 13, C.red, "left") end
    elseif o and o.kind == "rest" then
        Text.display("A NAP ON THE BENCH", 186, py + 18, 24, Text.INK, "left")
        Text.body("Bugs that came back Tired (half stamina) are healthy again. Only useful if some are tired.", 186, py + 62, 16, Text.INK, "left", 730)
    else
        Text.body("Point at a prize to read about it. Cards join your deck for the rest of the day; bugs join your Jar.", 186, py + 54, 16, { 0.4, 0.25, 0.5 }, "left", 730)
    end

    -- bug journal
    local jx = 980
    Paper.panel(jx, py, 460, 160, { fill = { 0.8, 0.95, 0.97 }, seed = 93, r = 18, rot = -0.003 })
    Text.display("BUG JOURNAL", jx + 22, py + 16, 16, Text.INK, "left")
    if sum.newSpecies and #sum.newSpecies > 0 then
        local sp = sum.newSpecies[1]
        love.graphics.setColor(1, 1, 1, 1)
        Assets.drawPortrait(sp, jx + 60, py + 90, 78)
        Text.display("NEW: " .. Bugs[sp].name, jx + 112, py + 44, 13, C.tealDark, "left")
        Text.body(Bugs[sp].fact, jx + 112, py + 66, 11.5, Text.INK, "left", 330)
        if #sum.newSpecies > 1 then Text.body("+" .. (#sum.newSpecies - 1) .. " more new entries", jx + 112, py + 138, 11, { 0.4, 0.25, 0.5 }, "left") end
    else
        Text.body("No new species this time. Next time you meet a new bug, a page appears here.", jx + 22, py + 54, 14, Text.INK, "left", 410)
    end

    local tired = (sum.tired and #sum.tired or 0)
    if tired > 0 then
        Text.body("Tired after this fight: " .. table.concat(sum.tired, ", "), 160, 700, 14, C.magentaDark, "left", 780)
    end
end

function Reward:mousemoved(x, y)
    self.hover = nil
    for _, o in ipairs(self.options) do
        if UI.inside(self:rect(o), x, y) then self.hover = o end
    end
end

function Reward:mousepressed(x, y, b)
    if b ~= 1 or self.picked then return end
    for _, o in ipairs(self.options) do
        if UI.inside(self:rect(o), x, y) then
            if o.disabled then Audio.play("block") else self:take(o) end
            return
        end
    end
end

function Reward:keypressed(key) end

return Reward
