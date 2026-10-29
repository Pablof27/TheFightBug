-- The Swap Shop: between fights, spend marbles on new cards (they join your deck) and bugs (they join your Jar).
-- Only the picture lives here: what is for sale, prices, "sold once" and the marbles you must keep for the next bet are
-- the rules of sim/shop.lua.

local Assets = require("client.assets")
local Paper = require("client.paper")
local Text = require("client.text")
local Audio = require("client.audio")
local Fx = require("client.fx")
local Tween = require("client.tween")
local UI = require("client.ui")
local HandView = require("client.fight.hand_view")
local Run = require("sim.run")
local Shop = require("sim.shop")
local Cards = require("data.cards")
local Bugs = require("data.bugs")
local Rivals = require("data.rivals")
local ShopData = require("data.shop")

local C = Paper.C
local INK = Text.INK
local Scene = {}
Scene.__index = Scene

local W, H = 150, 206                  -- every item is the size of a card
local ITEM_Y = 300
local INFO = { x = 100, y = 486, w = 980, h = 196 }
local BACK = { x = 1120, y = 520, w = 380, h = 110 }
local GROUP = { card = "NEW TRICKS", bug = "BUGS FOR YOUR JAR", nap = "ODDS AND ENDS", jar = "ODDS AND ENDS" }
local WEIGHT = { "Light", "Medium", "Heavy" }
local BOUGHT = { card = "NEW CARD!", bug = "NEW BUG!", jar = "MORE ROOM!", nap = "ZZZ... REFRESHED!" }
local WHY = {
    sold = "Sold! Each thing is sold once.",
    jar_full = "Your Jar is full. A bigger Jar would make room.",
    nobody_tired = "Nobody in your Jar is tired.",
    broke = "You don't have enough marbles.",
}

local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "S") end

local function marble(x, y, size)
    love.graphics.setColor(1, 1, 1, 1)
    local mw, mh = Assets.ui:size("icon_marble")
    love.graphics.draw(Assets.ui.image, Assets.ui.quads.icon_marble, x, y, 0, size / mh, size / mh, mw / 2, mh / 2)
end

function Scene.new(app, params)
    local self = setmetatable({ app = app, time = 0, hover = nil, lastBought = nil }, Scene)
    self.run = params.run or app.run
    self.items = Shop.stock(self.run)
    -- one row, grouped: cards, bugs, odds and ends
    local offsets, x, group = {}, 0, nil
    for i, it in ipairs(self.items) do
        it.group = GROUP[it.kind]
        if group and it.group ~= group then x = x + 26 end
        group = it.group
        offsets[i] = x
        x = x + W + 20
    end
    local span = x - 20
    for i, it in ipairs(self.items) do
        it.x, it.y = 800 - span / 2 + W / 2 + offsets[i], ITEM_Y
        it.pop, it.shake = 0, 0
    end
    return self
end

function Scene:enter()
    Audio.music("title")
    for i, it in ipairs(self.items) do
        Tween.after(0.05 * i, function() Tween.to(it, { pop = 1 }, 0.35, "outBack") end)
    end
end

function Scene:update(dt)
    self.time = self.time + dt
end

function Scene:nextRival() return Rivals[Run.encounter(self.run).rival] end

function Scene:reason(why)
    if why == "reserve" then
        return "You have to keep " .. Shop.reserve(self.run) .. " marbles for " .. self:nextRival().name .. "'s bet."
    end
    return WHY[why] or ""
end

--- An item and its price tag.
function Scene:rect(it) return { x = it.x - W / 2, y = it.y - H / 2, w = W, h = H + 52 } end

function Scene:back()
    Audio.play("ui_back")
    self.app.switch("map", { run = self.run })
end

function Scene:buy(it)
    local ok = Shop.buy(self.run, it)
    if not ok then
        -- the reason is already written in the info panel under the mouse
        Audio.play("block")
        it.shake = 1
        Tween.to(it, { shake = 0 }, 0.4, "outQuad")
        return
    end
    Audio.play("coin")
    self.lastBought = it
    Fx.sparkle(it.x, it.y, 14, 70)
    Fx.text(BOUGHT[it.kind], it.x, it.y - 20, C.yellow, 28)
    it.pop = 1.15
    Tween.to(it, { pop = 1 }, 0.3, "outBack")
end

--- What a bought item turned into, for the info panel.
function Scene:boughtLine(it)
    if it.kind == "card" then return "Yours! It's in your deck now (" .. #self.run.deck .. " cards)." end
    if it.kind == "bug" then return "Yours! It's waiting in your Jar." end
    if it.kind == "jar" then return "Yours! Your Jar has " .. self.run.jarSlots .. " slots now." end
    return "Everybody in your Jar is rested."
end

-- ───────────────────────── drawing ─────────────────────────
local function drawBug(sp)
    local d = Bugs[sp]
    Paper.panel(-W / 2, -H / 2, W, H, { fill = { 0.86, 0.97, 0.95 }, seed = 61, r = 14, line = 4, rot = 0.006 })
    Paper.disc(0, -44, 46, C.teal, { seed = 3, shadow = true, line = 4 })
    Paper.disc(0, -44, 39, C.cream, { seed = 4, line = 0 })
    love.graphics.setColor(1, 1, 1, 1)
    Assets.drawPortrait(sp, 0, -44, 76)
    Text.display(d.short, -W / 2 + 8, 14, 15, INK, "center", W - 16)
    Text.body(d.role .. (d.colony and (" · x" .. d.colony) or ""), 0, 36, 11, { 0.4, 0.25, 0.5 }, "center")
    Text.body("Stamina " .. d.hp .. "   Bite " .. d.bite, 0, 56, 10.5, INK, "center")
    Text.body("Timer " .. d.timer .. "   Move " .. d.move, 0, 72, 10.5, INK, "center")
end

local function drawExtra(kind)
    local d = ShopData.extras[kind]
    Paper.panel(-W / 2, -H / 2, W, H, { fill = kind == "nap" and { 0.8, 0.95, 0.97 } or { 0.9, 0.97, 0.8 }, seed = kind == "nap" and 62 or 63, r = 14, line = 4, rot = -0.006 })
    love.graphics.setColor(1, 1, 1, 1)
    Assets.ui:draw(d.icon, 0, -46, 0, kind == "nap" and 0.5 or 0.62)
    Text.display(d.short, -W / 2 + 8, 14, 20, INK, "center", W - 16)
    Text.body(d.text, -W / 2 + 12, 44, 11.5, INK, "center", W - 24)
end

local function priceTag(it, ok, sold)
    local y = H / 2 + 31
    Paper.panel(-40, y - 18, 80, 36, { fill = sold and { 0.75, 0.73, 0.8 } or ok and C.yellow or { 0.85, 0.83, 0.88 }, seed = 70, r = 14, line = 3, shadow = not sold })
    if sold then
        Text.display("SOLD", 0, y - 9, 18, C.red, "center")
    else
        marble(-16, y, 26)
        Text.display(tostring(it.price), 6, y - 11, 22, ok and INK or { 0.45, 0.42, 0.5 }, "left")
    end
end

function Scene:drawItem(it)
    local k = it.pop
    if k <= 0.01 then return end
    local ok, why = Shop.check(self.run, it)
    local sold = why == "sold"
    local hov = self.hover == it
    local lift = (hov and not sold) and -10 or 0
    local shake = math.sin(it.shake * 30) * it.shake * 8
    love.graphics.push()
    love.graphics.translate(it.x + shake, it.y + lift)
    love.graphics.scale(k, k)
    if it.kind == "card" then HandView.drawCard(it.id, { glow = hov and ok })
    elseif it.kind == "bug" then drawBug(it.id)
    else drawExtra(it.kind) end
    if not ok then
        -- a veil over whatever you can't buy right now
        love.graphics.setColor(C.ink[1], C.ink[2], C.ink[3], sold and 0.45 or 0.22)
        love.graphics.rectangle("fill", -W / 2, -H / 2, W, H, 14, 14)
    elseif hov and it.kind ~= "card" then
        love.graphics.setLineWidth(7)
        love.graphics.setColor(C.yellow[1], C.yellow[2], C.yellow[3], 0.95)
        love.graphics.rectangle("line", -W / 2 - 5, -H / 2 - 5, W + 10, H + 10, 18, 18)
    end
    priceTag(it, ok, sold)
    if sold then
        love.graphics.push()
        love.graphics.rotate(-0.25)
        Paper.panel(-62, -22, 124, 44, { fill = C.red, seed = 71, r = 10, line = 3 })
        Text.display("SOLD", 0, -12, 24, { 1, 1, 1 }, "center")
        love.graphics.pop()
    end
    love.graphics.pop()
end

function Scene:drawInfo()
    local P = INFO
    Paper.panel(P.x, P.y, P.w, P.h, { fill = C.cream, seed = 92, r = 18, rot = 0.003 })
    local it = self.hover ~= "back" and self.hover or nil
    local x, w = P.x + 26, P.w - 52
    local status, statusColor
    if it then
        local ok, why = Shop.check(self.run, it)
        if ok then
            local goes = it.kind == "card" and " It joins your deck." or it.kind == "bug" and " It joins your Jar." or ""
            status, statusColor = "Costs " .. it.price .. (it.price == 1 and " marble." or " marbles.") .. goes .. " Click to buy.", C.tealDark
        elseif why == "sold" and self.lastBought == it then
            status, statusColor = self:boughtLine(it), C.tealDark
        else
            status, statusColor = self:reason(why), C.red
        end
    end
    if it and it.kind == "card" then
        local d = Cards[it.id]
        Text.display(d.name, x, P.y + 18, 24, INK, "left", w)
        Text.display(d.type .. " card · takes " .. d.cost .. (d.cost == 1 and " tick" or " ticks") .. " to play", x, P.y + 52, 13, C.magentaDark, "left")
        Text.body(d.text, x, P.y + 76, 16, INK, "left", w)
        Text.body('"' .. d.flavor .. '"', x, P.y + 112, 13.5, { 0.4, 0.25, 0.5 }, "left", w)
    elseif it and it.kind == "bug" then
        local d = Bugs[it.id]
        Text.display(d.name, x, P.y + 16, 22, INK, "left", w)
        Text.body(d.latin .. " · " .. d.role .. " · " .. WEIGHT[d.weight] .. (d.colony and (" · a colony of " .. d.colony .. " in one Jar slot") or ""), x, P.y + 48, 13, { 0.4, 0.25, 0.5 }, "left", w)
        Text.body(d.rules.action, x, P.y + 72, 14.5, INK, "left", w)
        Text.body(d.trait, x, P.y + 110, 13.5, { 0.15, 0.5, 0.4 }, "left", w)
    elseif it then
        local d = ShopData.extras[it.kind]
        Text.display(d.name, x, P.y + 18, 24, INK, "left", w)
        Text.body(d.text, x, P.y + 58, 16, INK, "left", w)
        local line
        if it.kind == "jar" then
            line = "Your Jar has " .. self.run.jarSlots .. " slots, " .. #self.run.jar .. " of them full."
        else
            local tired = {}
            for _, e in ipairs(self.run.jar) do if e.tired then tired[#tired + 1] = Bugs[e.species].short end end
            line = #tired > 0 and ("Tired now: " .. table.concat(tired, ", ") .. ".") or "Nobody is tired right now."
        end
        Text.body(line, x, P.y + 92, 14, { 0.4, 0.25, 0.5 }, "left", w)
    else
        Text.display("POINT AT SOMETHING", x, P.y + 20, 22, INK, "left", w)
        Text.body("Cards join your deck for the rest of the day, bugs join your Jar. Buy as much as your marbles allow, but the marbles for the next bet stay in your pocket.", x, P.y + 58, 16, { 0.4, 0.25, 0.5 }, "left", w)
    end
    if status then Text.body(status, x, P.y + P.h - 34, 15, statusColor, "left", w) end
end

function Scene:drawJar()
    local run = self.run
    local y = 760
    Text.display("YOUR JAR", 104, y - 26, 16, INK, "left")
    Text.body(#run.jar .. "/" .. run.jarSlots, 104, y + 2, 13, { 0.4, 0.25, 0.5 }, "left")
    for i = 1, run.jarSlots do
        local e = run.jar[i]
        local cx = 250 + (i - 1) * 62
        Paper.disc(cx, y, 27, e and C.cream or { 1, 1, 1, 0.35 }, { seed = 20 + i, shadow = e ~= nil, line = e and 3 or 2 })
        if e then
            love.graphics.setColor(1, 1, 1, 1)
            Assets.drawPortrait(e.species, cx, y, 48)
            if e.tired then Assets.ui:draw("fx_zzz", cx + 20, y - 20, 0, 0.16) end
        end
    end
end

function Scene:draw()
    local run = self.run
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(Assets.backdrop.map, 0, 0)
    love.graphics.setColor(0.17, 0.07, 0.22, 0.45)
    love.graphics.rectangle("fill", 0, 0, 1600, 900)
    Paper.panel(60, 24, 1480, 800, { fill = { 1, 0.95, 0.7 }, seed = 91, r = 30, rot = -0.003, tape = true })
    Text.display("THE SWAP SHOP", 800, 48, 50, C.magenta, "center")
    Text.body("Kids trade marbles for cards and bugs here. Everything is sold once.", 800, 110, 17, INK, "center")
    -- your pocket, and what has to stay in it
    marble(134, 84, 56)
    Text.display(plural(run.marbles, "MARBLE"), 170, 58, 30, INK, "left", 330)
    Text.body("Keep " .. Shop.reserve(run) .. " for " .. self:nextRival().name .. "'s bet.", 170, 98, 13, C.magentaDark, "left", 330)
    Text.display("DECK " .. #run.deck .. " CARDS", 1496, 62, 18, C.tealDark, "right")
    -- group labels over the row of items
    local groups, order = {}, {}
    for _, it in ipairs(self.items) do
        local g = groups[it.group]
        if not g then g = { x0 = it.x, x1 = it.x }; groups[it.group] = g; order[#order + 1] = it.group end
        g.x0, g.x1 = math.min(g.x0, it.x), math.max(g.x1, it.x)
    end
    for _, name in ipairs(order) do
        local g = groups[name]
        Text.display(name, (g.x0 + g.x1) / 2, ITEM_Y - H / 2 - 34, 15, C.magentaDark, "center")
    end
    for _, it in ipairs(self.items) do self:drawItem(it) end
    self:drawInfo()
    self:drawJar()
    UI.button(BACK, "BACK TO THE MAP", { hover = self.hover == "back", size = 28, seed = 95, fill = C.teal })
    local enc = Run.encounter(run)
    Text.body("Next: " .. enc.name .. " against " .. self:nextRival().name .. ".   [Esc]", BACK.x + BACK.w / 2, BACK.y + BACK.h + 16, 13, { 0.4, 0.25, 0.5 }, "center")
end

-- ───────────────────────── input ─────────────────────────
function Scene:hitTest(x, y)
    if UI.inside(BACK, x, y) then return "back" end
    for _, it in ipairs(self.items) do
        if UI.inside(self:rect(it), x, y) then return it end
    end
    return nil
end

function Scene:mousemoved(x, y) self.hover = self:hitTest(x, y) end

function Scene:mousepressed(x, y, b)
    if b ~= 1 then return end
    local h = self:hitTest(x, y)
    if h == "back" then self:back() elseif h then self:buy(h) end
end

function Scene:keypressed(key)
    if key == "escape" or key == "space" or key == "return" or key == "backspace" or key == "s" then self:back() end
end

return Scene
