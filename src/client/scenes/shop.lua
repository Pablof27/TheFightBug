-- The Ice-Cream Van (GDD §8.9): it comes once per part of the day, after the kid's duel, and stays until you face the
-- Gang leader. Cards join your deck, bugs your Jar, pocket items your pockets; odds and ends: throw a card away, a
-- bigger Jar, an ice cream that wakes everybody up. Only the picture lives here: stock, prices and what you may buy
-- are the rules of sim/shop.lua.

local Assets = require("client.assets")
local Paper = require("client.paper")
local Text = require("client.text")
local Audio = require("client.audio")
local Fx = require("client.fx")
local Tween = require("client.tween")
local UI = require("client.ui")
local HandView = require("client.fight.hand_view")
local Saves = require("client.saves")
local Flow = require("client.flow")
local Run = require("sim.run")
local Shop = require("sim.shop")
local Cards = require("data.cards")
local Bugs = require("data.bugs")
local Items = require("data.items")
local ShopData = require("data.shop")
local PD = require("data.park")

local C = Paper.C
local INK = Text.INK
local SOFT = UI.SOFT
local Scene = {}
Scene.__index = Scene

local W, H = 150, 206                  -- every item is the size of a card
local ROWS = { { kinds = { card = true, bug = true }, y = 300 }, { kinds = { item = true, remove = true, jar = true, icecream = true }, y = 612 } }
local INFO = { x = 1148, y = 150, w = 376, h = 450 }
local RESTOCK = { x = 1148, y = 616, w = 376, h = 82 }
local BACK = { x = 1148, y = 712, w = 376, h = 100 }
local GROUP = { card = "NEW TRICKS", bug = "BUGS FOR YOUR JAR", item = "POCKET ITEMS", remove = "ODDS AND ENDS", jar = "ODDS AND ENDS", icecream = "ODDS AND ENDS" }
local WEIGHT = { "Light", "Medium", "Heavy" }
local BOUGHT = { card = "NEW CARD!", bug = "NEW BUG!", item = "IN YOUR POCKET!", jar = "MORE ROOM!", icecream = "EVERYBODY'S UP!", remove = "GONE!" }
local WHY = {
    closed = "The van has gone.",
    sold = "Sold! Each thing is sold once per visit.",
    owned = "You already have one.",
    jar_full = "Your Jar is full. A bigger Jar would make room.",
    nobody_napping = "Nobody in your Jar is napping.",
    deck_small = "Your deck is as small as it gets.",
    broke = "You don't have enough marbles.",
    last = "The van never takes your last marble: with none left, nobody plays with you.",
}
local ACT_TINT = { { 1, 1, 1, 0 }, { 1, 0.78, 0.35, 0.13 }, { 0.42, 0.16, 0.5, 0.3 } }

function Scene.new(app, params)
    local self = setmetatable({ app = app, time = 0, hits = {}, hover = nil, lastBought = nil }, Scene)
    self.run = params.run or app.run
    app.run = self.run
    self.mouse = { x = app.mouse.x, y = app.mouse.y }
    self:layout()
    return self
end

--- Lay the stock out in its two rows, grouped.
function Scene:layout()
    self.items = Shop.stock(self.run)
    for _, row in ipairs(ROWS) do
        local list = {}
        for _, it in ipairs(self.items) do if row.kinds[it.kind] then list[#list + 1] = it end end
        local offsets, x, group = {}, 0, nil
        for i, it in ipairs(list) do
            it.group = GROUP[it.kind]
            if group and it.group ~= group then x = x + 30 end
            group = it.group
            offsets[i] = x
            x = x + W + 16
        end
        local span = x - 16
        for i, it in ipairs(list) do
            it.x, it.y = 600 - span / 2 + W / 2 + offsets[i], row.y
            it.pop, it.shake = it.pop or 0, 0
        end
    end
end

function Scene:popIn()
    for i, it in ipairs(self.items) do
        it.pop = 0
        Tween.after(0.04 * i, function() Tween.to(it, { pop = 1 }, 0.35, "outBack") end)
    end
end

function Scene:enter()
    Audio.music("title")
    self:popIn()
end

function Scene:update(dt)
    self.time = self.time + dt
end

function Scene:reason(why) return WHY[why] or "" end

--- An item and its price tag.
function Scene:rect(it) return { x = it.x - W / 2, y = it.y - H / 2, w = W, h = H + 52 } end

-- ───────────────────────── drawing the stock ─────────────────────────
local function drawBug(it)
    local sp = it.id
    local d = Bugs[sp]
    Paper.panel(-W / 2, -H / 2, W, H, { fill = { 0.86, 0.97, 0.95 }, seed = 61, r = 14, line = 4, rot = 0.006 })
    UI.bugDisc(sp, 0, -44, 46, { seed = 3 })
    Text.display(d.short, -W / 2 + 8, 14, 15, INK, "center", W - 16)
    Text.body(d.role .. (d.colony and (" · x" .. d.colony) or ""), 0, 36, 11, SOFT, "center")
    Text.body("Stamina " .. d.hp .. "   Bite " .. d.bite, 0, 56, 10.5, INK, "center")
    Text.body("Timer " .. d.timer .. "   Move " .. d.move, 0, 72, 10.5, INK, "center")
    if it.exotic then UI.tag("PET SHOP", 0, -H / 2 - 12, 10, C.magenta, { align = "center", seed = 64, rot = -0.05 }) end
end

local function drawPocket(id)
    local d = Items[id]
    Paper.panel(-W / 2, -H / 2, W, H, { fill = { 1, 0.93, 0.75 }, seed = 65, r = 14, line = 4, rot = -0.006 })
    Paper.disc(0, -48, 44, C.yellow, { seed = 66, shadow = true, line = 3.5 })
    UI.icon(d.icon, 0, -48, 66)
    Text.display(d.name, -W / 2 + 8, 6, 15, INK, "center", W - 16)
    Text.body(d.text, -W / 2 + 10, 30, 10.5, INK, "center", W - 20)
end

local function drawExtra(kind)
    local d = ShopData.extras[kind]
    Paper.panel(-W / 2, -H / 2, W, H, { fill = kind == "icecream" and { 1, 0.9, 0.95 } or { 0.9, 0.97, 0.8 }, seed = 62, r = 14, line = 4, rot = -0.006 })
    UI.icon(d.icon, 0, -46, 84)
    Text.display(d.short, -W / 2 + 8, 14, 17, INK, "center", W - 16)
    Text.body(d.text, -W / 2 + 12, 42, 11, INK, "center", W - 24)
end

local function priceTag(it, ok, sold)
    local y = H / 2 + 31
    Paper.panel(-40, y - 18, 80, 36, { fill = sold and { 0.75, 0.73, 0.8 } or ok and C.yellow or { 0.85, 0.83, 0.88 }, seed = 70, r = 14, line = 3, shadow = not sold })
    if sold then
        Text.display("SOLD", 0, y - 9, 18, C.red, "center")
    else
        UI.marble(-16, y, 26)
        Text.display(tostring(it.price), 6, y - 11, 22, ok and INK or { 0.45, 0.42, 0.5 }, "left")
    end
end

function Scene:drawItem(it)
    local k = it.pop
    if k <= 0.01 then return end
    local ok, why = Shop.check(self.run, it)
    local sold = why == "sold"
    local hov = self.hover == it.key
    local lift = (hov and not sold) and -10 or 0
    local shake = math.sin(it.shake * 30) * it.shake * 8
    love.graphics.push()
    love.graphics.translate(it.x + shake, it.y + lift)
    love.graphics.scale(k, k)
    if it.kind == "card" then HandView.drawCard(it.id, { glow = hov and ok })
    elseif it.kind == "bug" then drawBug(it)
    elseif it.kind == "item" then drawPocket(it.id)
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
    UI.hit(self.hits, self:rect(it), it.key, { item = it })
end

-- ───────────────────────── info, jar, picker ─────────────────────────

--- What a bought item turned into, for the info panel.
function Scene:boughtLine(it)
    local run = self.run
    if it.kind == "card" then return "Yours! It's in your deck now (" .. #run.deck .. " cards)." end
    if it.kind == "bug" then return "Yours! It's waiting in your Jar." end
    if it.kind == "item" then return "Yours! It's in your pocket for the rest of the day." end
    if it.kind == "jar" then return "Yours! Your Jar has " .. run.jarSlots .. " slots now." end
    if it.kind == "remove" then return "Gone. Your deck has " .. #run.deck .. " cards now." end
    return "Everybody in your Jar is awake."
end

function Scene:drawInfo()
    local run = self.run
    local P = INFO
    Paper.panel(P.x, P.y, P.w, P.h, { fill = C.cream, seed = 92, r = 18, rot = 0.003 })
    local h = self.hover and UI.hitAt(self.hits, self.mouse.x, self.mouse.y)
    local it = h and h.data and h.data.item
    local x, w = P.x + 22, P.w - 44
    local status, statusColor
    if it then
        local ok, why = Shop.check(run, it)
        if ok then
            local goes = it.kind == "card" and " It joins your deck." or it.kind == "bug" and " It joins your Jar." or it.kind == "remove" and " Then pick the card." or ""
            status, statusColor = "Costs " .. UI.plural(it.price, "marble"):lower() .. "." .. goes .. " Click to buy.", C.tealDark
        elseif why == "sold" and self.lastBought == it.key then
            status, statusColor = self:boughtLine(it), C.tealDark
        else
            status, statusColor = self:reason(why), C.red
        end
    end
    if it and it.kind == "card" then
        local d = Cards[it.id]
        Text.display(d.name, x, P.y + 20, 26, INK, "left", w)
        Text.display(d.type .. " card · " .. d.cost .. (d.cost == 1 and " tick" or " ticks"), x, P.y + 58, 13, C.magentaDark, "left", w)
        Text.body(d.text, x, P.y + 84, 15, INK, "left", w)
        Text.body('"' .. d.flavor .. '"', x, P.y + 84 + Text.bodyHeight(d.text, 15, w) + 12, 13, SOFT, "left", w)
    elseif it and it.kind == "bug" then
        local d = Bugs[it.id]
        Text.display(d.name, x, P.y + 20, 22, INK, "left", w)
        local line = d.latin .. " · " .. d.role .. " · " .. WEIGHT[d.weight] .. (d.colony and (" · a colony of " .. d.colony .. " in one Jar slot") or "")
        Text.body(line, x, P.y + 54, 12.5, SOFT, "left", w)
        local y = P.y + 54 + Text.bodyHeight(line, 12.5, w) + 10
        Text.body(d.rules.action, x, y, 14, INK, "left", w)
        y = y + Text.bodyHeight(d.rules.action, 14, w) + 10
        Text.body(d.trait, x, y, 13, C.tealDark, "left", w)
    elseif it and it.kind == "item" then
        local d = Items[it.id]
        Text.display(d.name, x, P.y + 20, 26, INK, "left", w)
        Text.display("POCKET ITEM · ALL DAY", x, P.y + 58, 13, C.magentaDark, "left", w)
        Text.body(d.text, x, P.y + 86, 16, INK, "left", w)
    elseif it then
        local d = ShopData.extras[it.kind]
        Text.display(d.name, x, P.y + 20, 24, INK, "left", w)
        Text.body(d.text, x, P.y + 60, 16, INK, "left", w)
        local line
        if it.kind == "jar" then line = "Your Jar has " .. run.jarSlots .. " slots, " .. #run.jar .. " of them full."
        elseif it.kind == "remove" then line = "Your deck has " .. #run.deck .. " cards."
        else
            local naps = {}
            for _, e in ipairs(run.jar) do if e.nap then naps[#naps + 1] = Bugs[e.species].short end end
            line = #naps > 0 and ("Napping now: " .. table.concat(naps, ", ") .. ".") or "Nobody is napping right now."
        end
        Text.body(line, x, P.y + 130, 14, SOFT, "left", w)
    else
        Text.display("POINT AT SOMETHING", x, P.y + 22, 22, INK, "left", w)
        Text.body("Cards join your deck for the rest of the day, bugs join your Jar, pocket items stay in your pocket. Everything costs more as the day goes on.", x, P.y + 60, 15, SOFT, "left", w)
        Text.body("The van stays until you challenge the Gang leader.", x, P.y + 200, 14, C.tealDark, "left", w)
    end
    if status then
        local sh = Text.bodyHeight(status, 14, w)
        Text.body(status, x, P.y + P.h - 22 - sh, 14, statusColor, "left", w)
    end
end

function Scene:drawJar()
    local run = self.run
    local y = 842
    Text.display("YOUR JAR", 104, y - 20, 16, INK, "left")
    Text.body(#run.jar .. "/" .. run.jarSlots, 104, y + 4, 13, SOFT, "left")
    for i = 1, math.max(run.jarSlots, #run.jar) do
        local e = run.jar[i]
        local cx = 250 + (i - 1) * 62
        Paper.disc(cx, y, 27, e and C.cream or { 1, 1, 1, 0.35 }, { seed = 20 + i, shadow = e ~= nil, line = e and 3 or 2 })
        if e then
            love.graphics.setColor(1, 1, 1, e.nap and 0.5 or 1)
            Assets.drawPortrait(e.species, cx, y, 48)
            if e.nap then UI.icon("fx_zzz", cx + 20, y - 20, 22) end
        end
    end
    Text.display("DECK " .. #run.deck .. " CARDS", 1096, y - 12, 16, C.tealDark, "right")
end

function Scene:drawPicker()
    local run = self.run
    UI.veil(0.55)
    local P = { x = 70, y = 40, w = 1460, h = 820 }
    Paper.panel(P.x, P.y, P.w, P.h, { fill = C.cream, seed = 97, r = 26, rot = -0.003, tape = true })
    Text.display("THROW A CARD AWAY", 800, P.y + 24, 36, C.magenta, "center")
    Text.body("Click the card you want gone. It costs " .. self.picking.price .. " marbles.", 800, P.y + 74, 15, SOFT, "center")
    local n = #run.deck
    local cols = math.max(8, math.ceil(n / 3))
    local k = math.min(0.72, (P.w - 80) / (cols * 156))
    local cw, ch = 150 * k, 206 * k
    local gx = (P.w - 80 - cols * cw) / math.max(1, cols - 1)
    for i, id in ipairs(run.deck) do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        local cx = P.x + 40 + cw / 2 + col * (cw + gx)
        local cy = P.y + 130 + ch / 2 + row * (ch + 22)
        local key = "card" .. i
        local hov = self.hover == key
        love.graphics.push()
        love.graphics.translate(cx, cy - (hov and 10 or 0))
        love.graphics.scale(k * (hov and 1.06 or 1), k * (hov and 1.06 or 1))
        HandView.drawCard(id, { glow = hov })
        love.graphics.pop()
        UI.hit(self.hits, { x = cx - cw / 2, y = cy - ch / 2, w = cw, h = ch }, key, { index = i })
    end
    local r = { x = 800 - 150, y = P.y + P.h - 92, w = 300, h = 66 }
    UI.button(r, "CANCEL", { hover = self.hover == "cancel", size = 26, fill = C.cream2, color = INK, seed = 98 })
    UI.hit(self.hits, r, "cancel", {})
end

function Scene:draw()
    self.hits = {}
    local run = self.run
    love.graphics.setColor(1, 1, 1, 1)
    local z = run.zone and PD.zones[run.zone]
    love.graphics.draw(Assets.backdrop[z and z.backdrop or "map"], 0, 0)
    local t = ACT_TINT[run.act] or ACT_TINT[1]
    if t[4] > 0 then love.graphics.setColor(t); love.graphics.rectangle("fill", 0, 0, 1600, 900) end
    UI.veil(0.45)
    Paper.panel(40, 16, 1520, 868, { fill = { 1, 0.95, 0.7 }, seed = 91, r = 30, rot = -0.002, tape = true })
    Text.display("THE ICE-CREAM VAN", 800, 36, 46, C.magenta, "center")
    Text.body("Cards, bugs and pocket items, for marbles. It never takes your last marble.", 800, 92, 16, INK, "center")
    UI.marble(110, 72, 52)
    Text.display(UI.plural(run.marbles, "MARBLE"), 146, 48, 28, INK, "left", 300)
    Text.body("Prices x" .. Run.prices(run) .. " in the " .. Run.actDef(run).name:lower(), 146, 86, 13, C.magentaDark, "left", 300)
    -- group labels over the rows of items
    local groups, order = {}, {}
    for _, it in ipairs(self.items) do
        local g = groups[it.group]
        if not g then g = { x0 = it.x, x1 = it.x, y = it.y }; groups[it.group] = g; order[#order + 1] = it.group end
        g.x0, g.x1 = math.min(g.x0, it.x), math.max(g.x1, it.x)
    end
    for _, name in ipairs(order) do
        local g = groups[name]
        Text.display(name, (g.x0 + g.x1) / 2, g.y - H / 2 - 30, 15, C.magentaDark, "center")
    end
    for _, it in ipairs(self.items) do self:drawItem(it) end
    self:drawInfo()
    local rp = Shop.restockPrice(run)
    local canRestock = run.marbles - rp >= 1
    UI.button(RESTOCK, "RESTOCK (" .. rp .. ")", { hover = self.hover == "restock" and canRestock, size = 24, seed = 94, fill = C.orange, disabled = not canRestock })
    UI.hit(self.hits, RESTOCK, "restock", { disabled = not canRestock, tip = { "RESTOCK", "Everything not bought is swapped for something new, for " .. UI.plural(rp, "marble"):lower() .. "." } })
    UI.button(BACK, "BACK TO THE PARK", { hover = self.hover == "back", size = 28, seed = 95, fill = C.teal })
    UI.hit(self.hits, BACK, "back", {})
    self:drawJar()
    if self.picking then
        self.hits = {}
        self:drawPicker()
    end
    local h = UI.hitAt(self.hits, self.mouse.x, self.mouse.y)
    self.hover = h and h.key or nil
    if h and h.data and h.data.tip and not h.data.item then UI.tooltip(self.mouse.x, self.mouse.y, h.data.tip[1], h.data.tip[2]) end
end

-- ───────────────────────── input ─────────────────────────

function Scene:back()
    Audio.play("ui_back")
    Flow.go(self.app, self.run)
end

function Scene:bought(it)
    Audio.play("coin")
    Saves.store(self.run)
    self.lastBought = it.key
    Fx.sparkle(it.x, it.y, 14, 70)
    Fx.text(BOUGHT[it.kind] or "YOURS!", it.x, it.y - 20, C.yellow, 26)
    it.pop = 1.15
    Tween.to(it, { pop = 1 }, 0.3, "outBack")
end

function Scene:buy(it)
    local ok, why = Shop.check(self.run, it)
    if not ok then
        -- the reason is already written in the info panel under the mouse
        Audio.play("block")
        it.shake = 1
        Tween.to(it, { shake = 0 }, 0.4, "outQuad")
        return
    end
    if it.kind == "remove" then
        Audio.play("ui_click")
        self.picking = it
        return
    end
    Shop.buy(self.run, it)
    self:bought(it)
end

function Scene:restock()
    if not Shop.restock(self.run) then Audio.play("block"); return end
    Saves.store(self.run)
    Audio.play("coin")
    Fx.puff(600, 450, 10, 0.5)
    self:layout()
    self:popIn()
end

function Scene:mousemoved(x, y) self.mouse.x, self.mouse.y = x, y end

function Scene:mousepressed(x, y, b)
    self.mouse.x, self.mouse.y = x, y
    if b == 2 and self.picking then self.picking = nil; Audio.play("ui_back"); return end
    if b ~= 1 then return end
    local h = UI.hitAt(self.hits, x, y)
    if not h then return end
    if self.picking then
        if h.key == "cancel" then self.picking = nil; Audio.play("ui_back")
        elseif h.data.index then
            local it = self.picking
            self.picking = nil
            if Shop.buy(self.run, it, h.data.index) then self:bought(it) else Audio.play("block") end
        end
        return
    end
    if h.data and h.data.disabled then Audio.play("block"); return end
    if h.key == "back" then self:back()
    elseif h.key == "restock" then self:restock()
    elseif h.data and h.data.item then self:buy(h.data.item) end
end

function Scene:keypressed(key)
    if self.picking then
        if key == "escape" then self.picking = nil; Audio.play("ui_back") end
        return
    end
    if key == "escape" or key == "space" or key == "return" or key == "backspace" then self:back() end
end

return Scene
