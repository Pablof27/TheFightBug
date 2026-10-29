-- The morning map: three fights along the path, your marbles, the next rival's bet, the Swap Shop and your Jar.
-- (GDD §8, trimmed to a straight line.) After every fight it opens with a summary: the pot, the Bug Journal, tired bugs.

local Assets = require("client.assets")
local Paper = require("client.paper")
local Text = require("client.text")
local Audio = require("client.audio")
local Fx = require("client.fx")
local UI = require("client.ui")
local Run = require("sim.run")
local Shop = require("sim.shop")
local Encounters = require("data.encounters")
local Rivals = require("data.rivals")
local Rules = require("data.rules")
local Bugs = require("data.bugs")

local C = Paper.C
local Map = {}
Map.__index = Map

local NODE_POS = { { x = 330, y = 622 }, { x = 790, y = 548 }, { x = 1240, y = 300 } }
local GO = { x = 1220, y = 18, w = 356, h = 128 }
local BET = { x = 1016, y = 18, w = 190, h = 128 }
local SHOP = { x = 1220, y = 752, w = 356, h = 128 }

local LOSS_WHY = {
    wiped = "Your side ran out of bugs.",
    crumbs = "Their ants carried the crumbs home first.",
    sun = "The Sun clock ran out and they were ahead.",
}

local function encById(id)
    for _, e in ipairs(Encounters) do if e.id == id then return e end end
end

local function marble(x, y, size)
    love.graphics.setColor(1, 1, 1, 1)
    local mw, mh = Assets.ui:size("icon_marble")
    love.graphics.draw(Assets.ui.image, Assets.ui.quads.icon_marble, x, y, 0, size / mh, size / mh, mw / 2, mh / 2)
end

local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "S") end

function Map.new(app, params)
    local self = setmetatable({ app = app, time = 0, hover = nil }, Map)
    self.run = params.run or app.run
    app.run = self.run
    self.overlay = nil
    if params.sum then self.overlay = { kind = params.sum.won and "won" or "lost", sum = params.sum } end
    if params.intro then self.overlay = { kind = "intro" } end
    return self
end

function Map:enter()
    Audio.music("title")
    if self.overlay and self.overlay.kind == "won" then Audio.play("coin") end
end

function Map:enc() return encById(Run.NODES[self.run.node]) end

function Map:go()
    if not Run.canCover(self.run) then Audio.play("block"); return end
    Audio.play("ui_click")
    self.app.switch("fight", { enc = self:enc(), run = self.run })
end

function Map:openShop()
    if not Shop.isOpen(self.run) then Audio.play("block"); return end
    Audio.play("ui_click")
    self.app.switch("shop", { run = self.run })
end

function Map:update(dt) self.time = self.time + dt end

--- The bet panel: the next rival's fixed bet. You put up the same, so the pot is twice that.
function Map:drawBet()
    local run = self.run
    local bet = Run.bet(run)
    local rv = Rivals[self:enc().rival]
    Paper.panel(BET.x, BET.y, BET.w, BET.h, { fill = { 1, 0.86, 0.9 }, seed = 88, r = 18, rot = -0.006 })
    Text.display("THE BET", BET.x + BET.w / 2, BET.y + 12, 14, C.magentaDark, "center")
    marble(BET.x + 64, BET.y + 64, 40)
    Text.display(tostring(bet), BET.x + 92, BET.y + 42, 42, Run.canCover(run) and Text.INK or C.red, "left")
    Text.body(rv.name .. " bets " .. bet .. ", so do you. Pot: " .. (2 * bet) .. ".", BET.x + 12, BET.y + 92, 11, Text.INK, "center", BET.w - 24)
end

local function jarSlots(self, x, y)
    local run = self.run
    local w, h = 118, 88
    for i = 1, run.jarSlots do
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

    -- status band: your marbles are your stakes, and your money at the Swap Shop
    Paper.panel(24, 18, 440, 128, { fill = C.cream, seed = 81, r = 18, rot = -0.004, tape = true })
    marble(70, 66, 58)
    Text.display(plural(run.marbles, "MARBLE"), 112, 40, 30, Text.INK, "left", 330)
    Text.body("Every rival sets a bet. Can't cover it? Home you go.", 112, 84, 12.5, { 0.45, 0.25, 0.55 }, "left", 340)
    Text.body("Deck: " .. #run.deck .. " cards   ·   Fights won: " .. run.wins, 46, 118, 12.5, { 0.4, 0.25, 0.5 }, "left")

    -- mission
    local enc = self:enc()
    local rv = Rivals[enc.rival]
    local rule = Rules[enc.rule]
    Paper.panel(480, 18, 520, 128, { fill = { 1, 0.95, 0.7 }, seed = 82, r = 18, rot = 0.004 })
    Text.display("FIGHT " .. run.node .. " OF " .. #Run.NODES .. (enc.boss and " · THE BOSS" or ""), 504, 28, 14, C.magentaDark)
    Text.display(enc.name, 504, 56, 26, Text.INK, "left", 480)
    Text.body(rv.name .. ": \"" .. rv.line.start .. "\"", 504, 90, 14, { 0.4, 0.2, 0.45 }, "left", 480)
    Text.body("Rule: " .. rule.name .. " — " .. rule.short, 504, 112, 13, { 0.15, 0.5, 0.4 }, "left", 480)

    -- the bet for this fight
    self:drawBet()

    -- go button
    UI.button(GO, "GO FIGHT!", { hover = self.hover == "go" and not self.overlay, size = 34, seed = 83, fill = C.teal })

    -- the Swap Shop
    local open = Shop.isOpen(run)
    local hovShop = self.hover == "shop" and open and not self.overlay
    local lift = hovShop and -6 or 0
    Paper.panel(SHOP.x, SHOP.y + lift, SHOP.w, SHOP.h, { fill = open and C.orange or { 0.62, 0.6, 0.66 }, seed = 89, r = 22, rot = 0.008 })
    marble(SHOP.x + 58, SHOP.y + lift + 56, 64)
    Text.display("SWAP SHOP", SHOP.x + 104, SHOP.y + lift + 22, 32, { 1, 1, 1 }, "left", SHOP.w - 120)
    Text.body(open and "Cards and bugs for marbles. [S]" or "Opens after your first fight.", SHOP.x + 104, SHOP.y + lift + 70, 13.5, { 1, 1, 1 }, "left", SHOP.w - 120, 1)

    -- jar
    Paper.panel(24, 746, run.jarSlots * 124 + 40, 142, { fill = { 0.8, 0.95, 0.97 }, seed = 84, r = 18, rot = 0.003 })
    love.graphics.setColor(1, 1, 1, 1)
    local jw, jh = Assets.ui:size("icon_jar")
    love.graphics.draw(Assets.ui.image, Assets.ui.quads.icon_jar, 56, 770, 0, 40 / jh, 40 / jh, jw / 2, jh / 2)
    Text.display("YOUR JAR", 84, 758, 18, Text.INK, "left")
    Text.body("Lose a whole team in a fight and it comes back TIRED (half stamina). Tired twice: it runs away. A nap at the Swap Shop helps.", 250, 758, 11, { 0.15, 0.4, 0.45 }, "left", 540)
    jarSlots(self, 24, 746)
end

function Map:overlayRect() return { x = 360, y = 170, w = 880, h = 540 } end

function Map:overlayButtons()
    local o = self.overlay
    if not o then return {} end
    local P = self:overlayRect()
    local y = P.y + P.h - 100
    if o.kind == "intro" then return { { kind = "ok", label = "LET'S GO!", fill = C.teal, r = { x = P.x + 50, y = y, w = 300, h = 74 } } } end
    local list = { { kind = "ok", label = o.kind == "won" and "TO THE MAP" or "TRY AGAIN", fill = o.kind == "won" and C.teal or C.purpleLight, r = { x = P.x + 50, y = y, w = 300, h = 74 } } }
    if Shop.isOpen(self.run) then list[2] = { kind = "shop", label = "SWAP SHOP", fill = C.orange, r = { x = P.x + 380, y = y, w = 300, h = 74 } } end
    return list
end

--- The "NEW in your Bug Journal" page: the first species met today that you hadn't seen before.
local function journal(sum, x, y, w)
    Paper.panel(x, y, w, 150, { fill = { 0.8, 0.95, 0.97 }, seed = 93, r = 18, rot = -0.003 })
    Text.display("BUG JOURNAL", x + 22, y + 14, 16, Text.INK, "left")
    local sp = sum.newSpecies and sum.newSpecies[1]
    if not sp then
        Text.body("No new species this time. Next time you meet a new bug, a page appears here.", x + 22, y + 50, 14, Text.INK, "left", w - 44)
        return
    end
    love.graphics.setColor(1, 1, 1, 1)
    Assets.drawPortrait(sp, x + 60, y + 88, 78)
    Text.display("NEW: " .. Bugs[sp].name, x + 112, y + 40, 13, C.tealDark, "left", w - 130)
    Text.body(Bugs[sp].fact, x + 112, y + 62, 11.5, Text.INK, "left", w - 130)
    if #sum.newSpecies > 1 then Text.body("+" .. (#sum.newSpecies - 1) .. " more new entries", x + 112, y + 128, 11, { 0.4, 0.25, 0.5 }, "left") end
end

local function bugsAfter(sum, x, y, w)
    if #sum.tired > 0 then Text.body("Tired now: " .. table.concat(sum.tired, ", ") .. ".", x, y, 16, { 0.4, 0.2, 0.45 }, "left", w); y = y + 30 end
    if #sum.escaped > 0 then Text.body("Ran away for good: " .. table.concat(sum.escaped, ", ") .. ".", x, y, 16, C.magentaDark, "left", w); y = y + 30 end
    return y
end

function Map:drawOverlay()
    local o = self.overlay
    if not o then return end
    love.graphics.setColor(0.17, 0.07, 0.22, 0.55)
    love.graphics.rectangle("fill", 0, 0, 1600, 900)
    local P = self:overlayRect()
    Paper.panel(P.x, P.y, P.w, P.h, { fill = o.kind == "lost" and { 0.9, 0.85, 1 } or { 1, 0.95, 0.7 }, seed = 85, r = 26, rot = -0.005, tape = true })
    if o.kind == "intro" then
        Text.display("SATURDAY AT THE PARK", P.x + P.w / 2, P.y + 34, 36, C.magenta, "center")
        local x, w = P.x + 50, P.w - 100
        local y = P.y + 92
        local function para(str, size, color, width)
            Text.body(str, x, y, size, color or Text.INK, "left", width or w)
            y = y + Text.bodyHeight(str, size, width or w) + 10
        end
        para("You have a jar of bugs, " .. self.run.marbles .. " marbles and one afternoon before Mom calls you home for dinner.", 18)
        local bets = {}
        for i, id in ipairs(Run.NODES) do
            local rv = Rivals[encById(id).rival]
            bets[i] = rv.name:gsub("^The ", "the ") .. " bets " .. rv.bet
        end
        para("Every rival kid plays for marbles: " .. table.concat(bets, ", ") .. ". You put up the same, and the winner takes the pot. Can't cover a bet? Nobody will play with you.", 16, C.magentaDark)
        para("Between fights the SWAP SHOP sells cards and bugs for marbles. It never takes the marbles you need for the next bet.", 16)
        para("Bugs fight by instinct: you NEVER give orders. Your cards change the world around them, and a bug whose timer shows 0 acts on the next tick.", 16)
        para("Nothing is random in a fight. Hover everything. Use REWIND (Z) as often as you like.", 15, { 0.4, 0.2, 0.45 }, w - 200)
        Text.display("CONTROLS", x, y + 2, 14, C.tealDark, "left")
        Text.body("Click a card, then what it targets.  SPACE waits one tick.  Z rewinds.  TAB hides the arrows.  Right click cancels.  M mutes.", x, y + 22, 13.5, Text.INK, "left", w - 200)
        love.graphics.setColor(1, 1, 1, 1)
        Assets.bug.mantis:draw("idle1", P.x + P.w - 120, P.y + P.h - 24, 0, 0.62)
    elseif o.kind == "won" then
        local s = o.sum
        local rv = Rivals[s.rival]
        Text.display("YOU WON!", P.x + P.w / 2, P.y + 30, 44, C.magenta, "center")
        Text.body(rv.name .. " pays up: you take the pot.", P.x + 50, P.y + 96, 19, Text.INK, "left", P.w - 100)
        marble(P.x + 72, P.y + 148, 36)
        Text.display("+" .. plural(s.marbles, "MARBLE") .. "  ·  " .. self.run.marbles .. " IN YOUR POCKET", P.x + 100, P.y + 136, 24, C.tealDark, "left", P.w - 150)
        local y = bugsAfter(s, P.x + 50, P.y + 184, P.w - 100)
        journal(s, P.x + 40, math.max(P.y + 196, y + 4), P.w - 80)
    else
        local s = o.sum
        local rv = Rivals[s.rival]
        Text.display("OH NO!", P.x + P.w / 2, P.y + 34, 44, C.purple, "center")
        Text.body((LOSS_WHY[s.why] or "You lost the fight.") .. " " .. rv.name .. " keeps the pot.", P.x + 50, P.y + 110, 19, Text.INK, "left", P.w - 100)
        marble(P.x + 72, P.y + 172, 36)
        Text.display("LOST " .. plural(s.bet, "MARBLE") .. "  ·  " .. self.run.marbles .. " LEFT", P.x + 100, P.y + 160, 24, C.magentaDark, "left")
        local y = bugsAfter(s, P.x + 50, P.y + 214, P.w - 100)
        Text.body("Rematch! The same fight, the same rival, the same bugs: you only need a different idea." .. (Shop.isOpen(self.run) and " Or something new from the Swap Shop." or ""), P.x + 50, y + 10, 17, Text.INK, "left", P.w - 100)
    end
    for i, b in ipairs(self:overlayButtons()) do
        UI.button(b.r, b.label, { hover = self.hover == b.kind, size = 30, seed = 86 + i, fill = b.fill })
    end
end

function Map:mousemoved(x, y)
    self.hover = nil
    if self.overlay then
        for _, b in ipairs(self:overlayButtons()) do if UI.inside(b.r, x, y) then self.hover = b.kind end end
        return
    end
    self.hover = UI.inside(GO, x, y) and "go" or UI.inside(SHOP, x, y) and "shop" or nil
end

function Map:mousepressed(x, y, b)
    if b ~= 1 then return end
    if self.overlay then
        for _, bt in ipairs(self:overlayButtons()) do
            if UI.inside(bt.r, x, y) then
                if bt.kind == "shop" then self:openShop() else Audio.play("ui_click"); self.overlay = nil end
            end
        end
        return
    end
    if UI.inside(GO, x, y) then self:go()
    elseif UI.inside(SHOP, x, y) then self:openShop() end
end

function Map:keypressed(key)
    if key == "escape" then self.app.switch("title") return end
    if key == "space" or key == "return" then
        if self.overlay then self.overlay = nil; Audio.play("ui_click") else self:go() end
    elseif key == "s" and not (self.overlay and self.overlay.kind == "intro") then
        self:openShop()
    end
end

return Map
