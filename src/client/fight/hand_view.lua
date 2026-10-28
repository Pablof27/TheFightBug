-- The kid's hand: a fan of paper cards that rise when hovered and fly in from the deck when drawn.

local Assets = require("client.assets")
local Paper = require("client.paper")
local Text = require("client.text")
local L = require("client.fight.layout")
local Cards = require("data.cards")

local HandView = {}
HandView.__index = HandView

local C = Paper.C
local CW, CH = L.hand.w, L.hand.h

local TINT = {
    lure = { 1.0, 0.86, 0.62 }, terrain = { 0.78, 0.94, 0.83 }, nudge = { 0.8, 0.89, 1.0 },
    timing = { 0.89, 0.84, 1.0 }, jar = { 0.79, 0.95, 0.95 },
}
local TYPE_COLOR = { lure = C.orange, terrain = C.green, nudge = C.blue, timing = C.purpleLight, jar = C.teal }

local function seedOf(id) local n = 0; for i = 1, #id do n = n + id:byte(i) * i end return n end

--- Draws one card centred on (0, 0) in the current transform.
function HandView.drawCard(id, o)
    o = o or {}
    local def = Cards[id]
    local w, h = CW, CH
    local tint = TINT[def.type] or C.cream
    Paper.panel(-w / 2, -h / 2, w, h, { fill = tint, seed = seedOf(id), r = 14, line = 4, jitter = 1.6, shadow = o.shadow ~= false })
    if o.glow then
        love.graphics.setLineWidth(7)
        love.graphics.setColor(C.yellow[1], C.yellow[2], C.yellow[3], 0.95)
        love.graphics.rectangle("line", -w / 2 - 5, -h / 2 - 5, w + 10, h + 10, 18, 18)
    end
    -- art on a coloured splotch
    love.graphics.setColor(1, 1, 1, 1)
    local aw, ah = Assets.ui:size("card_" .. def.art)
    local s = 104 / math.max(aw, ah)
    love.graphics.draw(Assets.ui.image, Assets.ui.quads["card_" .. def.art], 0, -h / 2 + 82, 0, s, s, aw / 2, ah / 2)
    -- name (beside the cost bubble)
    Text.display(def.name, -w / 2 + 46, -h / 2 + 14, 16, Text.INK, "center", w - 46 - 18)
    -- text
    Text.body(def.text, -w / 2 + 12, -h / 2 + 138, 11.5, Text.INK, "left", w - 24)
    -- cost bubble (inside the corner, so overlapping neighbours never hide it)
    local tc = TYPE_COLOR[def.type] or C.orange
    Paper.disc(-w / 2 + 21, -h / 2 + 21, 19, C.orange, { seed = 5, shadow = true, line = 3.5 })
    love.graphics.setColor(1, 1, 1, 1)
    local iw, ih = Assets.ui:size("icon_hourglass")
    love.graphics.draw(Assets.ui.image, Assets.ui.quads.icon_hourglass, -w / 2 + 12, -h / 2 + 33, 0, 14 / ih, 14 / ih, iw / 2, ih / 2)
    Text.display(tostring(def.cost), -w / 2 + 25, -h / 2 + 9, 17, { 1, 1, 1 }, "center")
    -- type tag
    Paper.panel(w / 2 - 66, h / 2 - 8, 58, 18, { fill = tc, seed = 7, r = 8, line = 2.5, shadow = false })
    Text.display(def.type, w / 2 - 37, h / 2 - 3, 9, { 1, 1, 1 }, "center")
end

function HandView.new()
    return setmetatable({ cards = {}, flying = {} }, HandView)
end

--- Reconcile with the real hand. New cards start at the deck (right of the hand) unless `immediate`.
function HandView:sync(hand, immediate)
    local old = self.cards
    local used = {}
    local list = {}
    for i, id in ipairs(hand) do
        local found
        for j, c in ipairs(old) do
            if not used[j] and c.id == id then found = j break end
        end
        if found then
            used[found] = true
            list[i] = old[found]
        else
            list[i] = { id = id, x = immediate and L.hand.cx or 1500, y = immediate and L.hand.top + CH / 2 + 80 or 900, rot = 0.3, scale = 0.8 }
        end
    end
    -- played cards leave: remember them so the scene can fly them out
    for j, c in ipairs(old) do
        if not used[j] then self.flying[#self.flying + 1] = { id = c.id, x = c.x, y = c.y, rot = c.rot, scale = c.scale, t = 0 } end
    end
    self.cards = list
end

function HandView:targets(hoverIndex, armedIndex)
    local n = #self.cards
    local spacing = math.min(146, 690 / math.max(1, n))
    local base = n <= 5 and 1 or math.max(0.7, 1 - (n - 5) * 0.11)
    local mid = (n + 1) / 2
    for i, c in ipairs(self.cards) do
        local d = i - mid
        c.tx = L.hand.cx + d * spacing
        c.ty = L.hand.top + CH / 2 + math.abs(d) ^ 1.5 * 3 + 2 + CH * (1 - base) * 0.5
        c.trot = d * 0.035
        c.tscale = base
        if i == hoverIndex then c.ty = L.hand.top + CH / 2 - 52; c.trot = 0; c.tscale = 1.1 end
        if i == armedIndex then c.ty = L.hand.top + CH / 2 - 36; c.trot = 0; c.tscale = 1.1 end
    end
end

function HandView:update(dt, hoverIndex, armedIndex)
    self:targets(hoverIndex, armedIndex)
    local k = math.min(1, dt * 12)
    for _, c in ipairs(self.cards) do
        c.x = c.x + (c.tx - c.x) * k
        c.y = c.y + (c.ty - c.y) * k
        c.rot = c.rot + (c.trot - c.rot) * k
        c.scale = c.scale + (c.tscale - c.scale) * k
    end
    for i = #self.flying, 1, -1 do
        local f = self.flying[i]
        f.t = f.t + dt
        f.y = f.y - dt * 220
        f.scale = f.scale * (1 + dt * 0.4)
        if f.t > 0.4 then table.remove(self.flying, i) end
    end
end

function HandView:draw(hoverIndex, armedIndex)
    for _, f in ipairs(self.flying) do
        love.graphics.push()
        love.graphics.translate(f.x, f.y)
        love.graphics.rotate(f.rot)
        love.graphics.scale(f.scale, f.scale)
        love.graphics.setColor(1, 1, 1, 1 - f.t / 0.4)
        HandView.drawCard(f.id, { shadow = false })
        love.graphics.pop()
    end
    for i, c in ipairs(self.cards) do
        if i ~= hoverIndex and i ~= armedIndex then
            love.graphics.push()
            love.graphics.translate(c.x, c.y)
            love.graphics.rotate(c.rot)
            love.graphics.scale(c.scale, c.scale)
            love.graphics.setColor(1, 1, 1, 1)
            HandView.drawCard(c.id)
            love.graphics.pop()
        end
    end
    for _, i in ipairs(self:topOrder(hoverIndex, armedIndex)) do
        local c = self.cards[i]
        if c then
            love.graphics.push()
            love.graphics.translate(c.x, c.y)
            love.graphics.rotate(c.rot)
            love.graphics.scale(c.scale, c.scale)
            love.graphics.setColor(1, 1, 1, 1)
            HandView.drawCard(c.id, { glow = (i == armedIndex) })
            love.graphics.pop()
        end
    end
end

-- hovered first, armed on top (a plain {a, b} list would stop at a nil)
function HandView:topOrder(hoverIndex, armedIndex)
    local out = {}
    if hoverIndex and hoverIndex ~= armedIndex then out[#out + 1] = hoverIndex end
    if armedIndex then out[#out + 1] = armedIndex end
    return out
end

--- Which card is under the mouse? (the last one drawn wins)
function HandView:hit(mx, my)
    for i = #self.cards, 1, -1 do
        local c = self.cards[i]
        local w, h = CW * c.scale, CH * c.scale
        if math.abs(mx - c.x) <= w / 2 and math.abs(my - c.y) <= h / 2 then return i end
    end
    return nil
end

return HandView
