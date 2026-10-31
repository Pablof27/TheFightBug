-- The park (GDD §8.4): the hub of a day. It shows whatever the run's phase needs:
--   prologue  the day's intro and the warm-up offer       zone    pick 1 of 2 zones (each with its Gang leader)
--   free      free time: Bug Hunts, the kids or the Gang leader, the van, the bench, events, the Jar
--   reward    the act is won: pick a pocket item
-- Only the picture lives here; every rule is in sim/run.lua, sim/hunt.lua, sim/duel.lua, sim/park.lua.

local Assets = require("client.assets")
local Paper = require("client.paper")
local Text = require("client.text")
local Audio = require("client.audio")
local Fx = require("client.fx")
local Tween = require("client.tween")
local UI = require("client.ui")
local Saves = require("client.saves")
local Flow = require("client.flow")
local HandView = require("client.fight.hand_view")
local Run = require("sim.run")
local Duel = require("sim.duel")
local Hunt = require("sim.hunt")
local ParkSim = require("sim.park")
local Shop = require("sim.shop")
local PD = require("data.park")
local Rivals = require("data.rivals")
local Bugs = require("data.bugs")
local Cards = require("data.cards")
local Items = require("data.items")
local RuleData = require("data.rules")

local C = Paper.C
local INK = Text.INK
local SOFT = UI.SOFT

local Scene = {}
Scene.__index = Scene

-- what the time of day does to the light
local ACT_TINT = { { 1, 1, 1, 0 }, { 1, 0.78, 0.35, 0.13 }, { 0.42, 0.16, 0.5, 0.3 } }
local BUZZ_COL = { C.green, C.yellow, C.orange, { 1, 0.45, 0.3 }, C.red }

local TOP_Y, TOP_H = 12, 100
local HUNTS = { x = 24, y = 124, w = 936, h = 620 }
local RIVALS = { x = 976, y = 124, w = 600, h = 452 }
local SIDE = { x = 976, y = 588, w = 600, h = 156 }
local JAR = { x = 24, y = 756, w = 1552, h = 132 }

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function ruleName(id) return RuleData[id] and RuleData[id].name or id end

local function rulesLine(rv)
    if rv.rules[1] == "random" then return "Picks a random game every round." end
    return "Plays " .. ruleName(rv.rules[1]) .. (rv.rules[2] and (", then " .. ruleName(rv.rules[2])) or "") .. "."
end

--- The bug's entry stats as they would be in a fight (a big one has 1 more stamina, or 1 more ant).
local function entryLine(e)
    local sp = Bugs[e.species]
    if sp.colony then return "A colony of " .. (sp.colony + (e.big and 1 or 0)) .. " ants" end
    return "Stamina " .. (sp.hp + (e.big and 1 or 0)) .. "  ·  Bite " .. sp.bite .. "  ·  Timer " .. sp.timer
end

function Scene.new(app, params)
    local self = setmetatable({ app = app, time = 0, hits = {}, hover = nil, pop = 0 }, Scene)
    self.run = params.run or app.run
    app.run = self.run
    self.mouse = { x = app.mouse.x, y = app.mouse.y }
    if params.hunt then self.dialog = { kind = "hunt", sum = params.hunt }
    elseif params.note then self.dialog = { kind = "note", title = params.note.title, text = params.note.text } end
    self:autoDialog()
    return self
end

--- Things that can't wait: a Jar over its slots, an event going on.
function Scene:autoDialog()
    local run = self.run
    if self.dialog or run.phase ~= "free" then return end
    if Run.overflow(run) > 0 then self.dialog = { kind = "overflow" }
    elseif run.event then self.dialog = { kind = "event" } end
end

function Scene:enter()
    Audio.music("title")
    Tween.to(self, { pop = 1 }, 0.45, "outBack")
    if self.dialog and self.dialog.kind == "hunt" and #self.dialog.sum.caught > 0 then Audio.play("coin") end
end

function Scene:actDef() return Run.actDef(self.run) end

-- ───────────────────────── shared pieces ─────────────────────────

function Scene:backdrop(id, veil)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(Assets.backdrop[id], 0, 0)
    local t = ACT_TINT[self.run.act] or ACT_TINT[1]
    if t[4] > 0 then
        love.graphics.setColor(t)
        love.graphics.rectangle("fill", 0, 0, 1600, 900)
    end
    if veil then UI.veil(veil) end
end

--- A button that registers itself. o: as UI.button + disabled, tip = { title, body }
function Scene:button(r, key, label, o, data)
    o = o or {}
    o.hover = self.hover == key
    UI.button(r, label, o)
    if not o.disabled or o.tip then UI.hit(self.hits, r, key, { disabled = o.disabled, tip = o.tip, data = data }) end
end

function Scene:tipArea(r, title, body)
    UI.hit(self.hits, r, "tip", { tip = { title, body } })
end

-- ───────────────────────── prologue ─────────────────────────

function Scene:drawPrologue()
    self:backdrop("map", 0.35)
    local P = { x = 170, y = 40, w = 1260, h = 820 }
    Paper.panel(P.x, P.y, P.w, P.h, { fill = { 1, 0.95, 0.7 }, seed = 401, r = 28, rot = -0.003, tape = true })
    Text.display("SATURDAY AT THE PARK", 800, P.y + 36, 48, C.magenta, "center")
    Text.body("One summer day, from breakfast to dinner.", 800, P.y + 98, 18, SOFT, "center")
    local x, w, y = P.x + 60, 760, P.y + 150
    local function para(head, body)
        Text.display(head, x, y, 15, C.tealDark, "left")
        y = y + 22
        Text.body(body, x, y, 15.5, INK, "left", w)
        y = y + Text.bodyHeight(body, 15.5, w) + 16
    end
    para("MARBLES ARE EVERYTHING", "You start with " .. PD.START_MARBLES .. " marbles and a jar of bugs. Run out of marbles and you go home. Big Sister bails you out once.")
    para("THREE PARTS OF THE DAY", "Morning, Afternoon and Dusk. Each time you pick a corner of the park, beat one kid in a duel, then the kid who runs that corner: the Gang leader. Beat all three Gang leaders before sunset.")
    para("DUELS", "Both sides bet the smaller of the two stacks, so whoever has less is ALL IN. The winner takes the bet. Up to 3 rounds, the last one a Showdown where every hit moves a marble.")
    para("BUG HUNTS", "Between duels, lay your jar on its side and catch wild bugs. No marbles at stake, but your bugs can run off. Every hunt stirs the zone up: the Buzz.")
    para("NAPPING", "A bug knocked out in a fight takes a nap: it sits out the next duel round, then it's back.")
    -- the team
    local bx = P.x + P.w - 300
    Paper.panel(bx - 20, P.y + 150, 300, 420, { fill = { 0.8, 0.95, 0.97 }, seed = 402, r = 20, rot = 0.01 })
    Text.display("YOUR JAR", bx + 130, P.y + 172, 18, INK, "center")
    for i, e in ipairs(self.run.jar) do
        local cy = P.y + 250 + (i - 1) * 64
        UI.bugDisc(e.species, bx + 40, cy, 27, { seed = 410 + i })
        Text.display(Bugs[e.species].short, bx + 80, cy - 16, 15, INK, "left", 180)
        Text.body(Bugs[e.species].role, bx + 80, cy + 4, 11.5, SOFT, "left", 180)
    end
    local by = P.y + P.h - 132
    self:button({ x = P.x + 60, y = by, w = 520, h = 96 }, "warmup", "WARM-UP FIRST", { size = 32, fill = C.teal, seed = 403 })
    Text.body("A practice fight with hints. No marbles at stake.", P.x + 320, by + 104, 13, SOFT, "center")
    self:button({ x = P.x + 640, y = by, w = 520, h = 96 }, "skip", "STRAIGHT TO THE PARK", { size = 30, fill = C.orange, seed = 404 })
    Text.body("You know how bugs fight already.", P.x + 900, by + 104, 13, SOFT, "center")
end

-- ───────────────────────── zone choice ─────────────────────────

function Scene:drawZoneCard(i, o, r)
    local run = self.run
    local z = PD.zones[o.zone]
    local rv = Rivals[o.leader]
    local hov = self.hover == "zone" .. i
    local lift = hov and -8 or 0
    r = { x = r.x, y = r.y + lift, w = r.w, h = r.h }
    Paper.panel(r.x, r.y, r.w, r.h, { fill = C.cream, seed = 420 + i, r = 24, rot = (i == 1) and -0.006 or 0.006, tape = true })
    -- a window onto the zone
    local wx, wy, ww, wh = r.x + 22, r.y + 22, r.w - 44, 150
    love.graphics.stencil(function() love.graphics.rectangle("fill", wx, wy, ww, wh, 16, 16) end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(Assets.backdrop[z.backdrop], wx, wy - 120, 0, ww / 1600, ww / 1600)
    love.graphics.setStencilTest()
    love.graphics.setLineWidth(4)
    love.graphics.setColor(INK)
    love.graphics.rectangle("line", wx, wy, ww, wh, 16, 16)
    Text.display(z.name, r.x + 30, r.y + 190, 34, INK, "left", r.w - 60)
    Text.body(z.text, r.x + 30, r.y + 236, 15, SOFT, "left", r.w - 60)
    -- the hunt spots, with their first prize
    Text.display("BUG HUNTS", r.x + 30, r.y + 290, 13, C.tealDark, "left")
    for k, id in ipairs(z.spots) do
        local sx = r.x + 30 + (k - 1) * ((r.w - 60) / 3)
        UI.bugDisc(Hunt.prizeAt(id, 0), sx + 26, r.y + 344, 24, { ring = C.yellow, seed = 430 + k })
        Text.body(PD.spots[id].name, sx + 58, r.y + 328, 12.5, INK, "left", (r.w - 60) / 3 - 62)
    end
    -- the Gang leader
    local ly = r.y + 396
    Text.display("THE GANG LEADER", r.x + 30, ly, 13, C.magentaDark, "left")
    UI.kidDisc(rv.portrait, "neutral", r.x + 90, ly + 92, 58, 440 + i)
    Text.display(rv.name, r.x + 166, ly + 30, 24, INK, "left", r.w - 196)
    UI.marble(r.x + 180, ly + 76, 26)
    Text.display(Run.stackOf(run, o.leader, true) .. " MARBLES", r.x + 198, ly + 66, 18, INK, "left")
    if rv.house then
        Text.body('"' .. rv.house.name .. '"', r.x + 166, ly + 98, 14.5, C.magentaDark, "left", r.w - 196)
        Text.body(rv.house.text, r.x + 166, ly + 122, 13, INK, "left", r.w - 196)
    end
    Text.body(rulesLine(rv), r.x + 166, ly + 146, 13, SOFT, "left", r.w - 196)
    self:button({ x = r.x + 30, y = r.y + r.h - 96, w = r.w - 60, h = 72 }, "zone" .. i, "PLAY HERE", { size = 30, fill = C.teal, seed = 450 + i })
end

function Scene:drawZones()
    local run = self.run
    local act = self:actDef()
    self:backdrop("map", 0.25)
    Paper.panel(170, 16, 1260, 124, { fill = { 1, 0.95, 0.7 }, seed = 460, r = 22, rot = -0.003 })
    Text.display(act.name, 200, 32, 44, C.magenta, "left")
    Text.display("PART " .. run.act .. " OF " .. Run.ACTS .. " OF THE DAY", 200, 88, 15, C.magentaDark, "left")
    Text.body(act.text, 620, 36, 17, INK, "left", 520)
    Text.body("Where to? Each corner of the park has its own Gang leader.", 620, 92, 14, SOFT, "left", 520)
    UI.marble(1222, 64, 46)
    Text.display(tostring(run.marbles), 1252, 44, 38, INK, "left")
    Text.body("marbles", 1252, 90, 13, SOFT, "left")
    for i, o in ipairs(run.offer or {}) do
        self:drawZoneCard(i, o, { x = 110 + (i - 1) * 710, y = 162, w = 670, h = 716 })
    end
end

-- ───────────────────────── reward ─────────────────────────

function Scene:drawReward()
    local run = self.run
    self:backdrop("map", 0.4)
    Paper.panel(200, 60, 1200, 780, { fill = { 1, 0.95, 0.7 }, seed = 470, r = 28, rot = -0.004, tape = true })
    Text.display("THE GANG LEADER IS BEATEN!", 800, 96, 46, C.magenta, "center")
    Text.body("The " .. self:actDef().name:lower() .. " is yours. Pick a pocket item: you keep it for the rest of the day. Your Jar also gets 1 more slot.", 300, 160, 18, INK, "center", 1000)
    for i, id in ipairs(run.rewardOffer or {}) do
        local it = Items[id]
        local r = { x = 260 + (i - 1) * 370, y = 250, w = 340, h = 500 }
        local hov = self.hover == "reward" .. i
        local lift = hov and -8 or 0
        Paper.panel(r.x, r.y + lift, r.w, r.h, { fill = C.cream, seed = 480 + i, r = 22, rot = (i - 2) * 0.01 })
        Paper.disc(r.x + r.w / 2, r.y + lift + 110, 76, C.yellow, { seed = 490 + i, shadow = true, line = 4 })
        UI.icon(it.icon, r.x + r.w / 2, r.y + lift + 110, 110)
        Text.display(it.name, r.x + 20, r.y + lift + 206, 26, INK, "center", r.w - 40)
        Text.body(it.text, r.x + 28, r.y + lift + 252, 16, INK, "center", r.w - 56)
        self:button({ x = r.x + 30, y = r.y + r.h - 96, w = r.w - 60, h = 70 }, "reward" .. i, "TAKE IT", { size = 28, fill = C.teal, seed = 495 + i })
    end
    Text.body("Jar after this: " .. (run.jarSlots + 1) .. " slots.  ·  Marbles: " .. run.marbles .. ".", 800, 790, 14, SOFT, "center")
end

-- ───────────────────────── free time ─────────────────────────

function Scene:guidance()
    local run = self.run
    if Run.overflow(run) > 0 then return "Your Jar is too full: let a bug go before anything else." end
    if #Run.available(run) == 0 then return "Every bug of yours is napping! The bench or an ice cream wakes them up." end
    if run.window == 1 then
        return "Hunt as much as you like (each hunt stirs the zone up), then challenge one of the two kids."
    end
    return "The Ice-Cream Van is here. Hunt some more if you like, then face the Gang leader: " .. Rivals[run.leader].name .. "."
end

function Scene:drawTop()
    local run = self.run
    local act = self:actDef()
    -- the time of day: the sun climbs and sets with the acts
    local P = { x = 24, y = TOP_Y, w = 340, h = TOP_H }
    Paper.panel(P.x, P.y, P.w, P.h, { fill = { 1, 0.92, 0.62 }, seed = 501, r = 18, rot = -0.004 })
    love.graphics.setLineWidth(3)
    love.graphics.setColor(C.ink[1], C.ink[2], C.ink[3], 0.35)
    love.graphics.arc("line", "open", P.x + 64, P.y + 86, 48, math.pi, 2 * math.pi, 16)
    local a = math.pi + (run.act - 0.5) / Run.ACTS * math.pi
    UI.icon("icon_sun", P.x + 64 + math.cos(a) * 48, P.y + 86 + math.sin(a) * 48, 40)
    Text.display(act.name, P.x + 128, P.y + 16, 30, INK, "left", P.w - 140)
    Text.display("PART " .. run.act .. " OF " .. Run.ACTS .. "  ·  " .. PD.zones[run.zone].short, P.x + 128, P.y + 58, 12, C.magentaDark, "left", P.w - 140)
    -- marbles
    P = { x = 380, y = TOP_Y, w = 330, h = TOP_H }
    Paper.panel(P.x, P.y, P.w, P.h, { fill = C.cream, seed = 502, r = 18, rot = 0.004, tape = true })
    UI.marble(P.x + 44, P.y + 46, 52)
    Text.display(UI.plural(run.marbles, "MARBLE"), P.x + 82, P.y + 20, 28, INK, "left", P.w - 96)
    Text.body(run.bigSister and "Big Sister can bail you out once." or "Big Sister already helped you today.", P.x + 82, P.y + 60, 12, run.bigSister and SOFT or C.magentaDark, "left", P.w - 96)
    self:tipArea(P, "MARBLES", "Your stake in every duel and your money at the van. Run out and you go home. Once a day, Big Sister drags you away from a lost duel and slips you " .. PD.BIG_SISTER .. " marbles.")
    -- the bag: deck and pocket items
    P = { x = 726, y = TOP_Y, w = 450, h = TOP_H }
    Paper.panel(P.x, P.y, P.w, P.h, { fill = C.cream, seed = 503, r = 18, rot = -0.003 })
    local dr = { x = P.x + 12, y = P.y + 10, w = 150, h = 80 }
    local dh = self.hover == "deck"
    Paper.panel(dr.x, dr.y + (dh and -4 or 0), dr.w, dr.h, { fill = dh and C.yellow or { 0.8, 0.89, 1.0 }, seed = 504, r = 14, line = 3 })
    Text.display("DECK", dr.x + dr.w / 2, dr.y + 12 + (dh and -4 or 0), 14, C.tealDark, "center")
    Text.display(#run.deck .. " CARDS", dr.x + dr.w / 2, dr.y + 38 + (dh and -4 or 0), 20, INK, "center")
    UI.hit(self.hits, dr, "deck", { tip = { "YOUR DECK", "Click to see every card. The bench and the van can throw cards away." } })
    Text.display("POCKETS", P.x + 180, P.y + 14, 13, C.magentaDark, "left")
    if #run.items == 0 then
        Text.body("Nothing yet. Gang leaders and the van have pocket items.", P.x + 180, P.y + 38, 12, SOFT, "left", P.w - 196)
    end
    for i, id in ipairs(run.items) do
        local it = Items[id]
        local cx, cy = P.x + 200 + (i - 1) * 46, P.y + 62
        Paper.disc(cx, cy, 21, C.yellow, { seed = 505 + i, shadow = true, line = 3 })
        UI.icon(it.icon, cx, cy, 34)
        UI.hit(self.hits, { x = cx - 21, y = cy - 21, w = 42, h = 42 }, "tip", { tip = { it.name, it.text } })
    end
    -- what now?
    P = { x = 1192, y = TOP_Y, w = 384, h = TOP_H }
    Paper.panel(P.x, P.y, P.w, P.h, { fill = { 0.88, 0.97, 0.92 }, seed = 506, r = 18, rot = 0.004 })
    Text.display("WHAT NOW?", P.x + 18, P.y + 12, 14, C.tealDark, "left")
    Text.body(self:guidance(), P.x + 18, P.y + 34, 12.5, INK, "left", P.w - 36)
end

--- A short line about what the Buzz does to this group.
local function groupLine(grp)
    local parts = {}
    if grp.timer > 0 then parts[#parts + 1] = "They start 1 tick slower." end
    if grp.timer < 0 then parts[#parts + 1] = "They start 1 tick sooner." end
    if grp.bite > 0 then parts[#parts + 1] = "They bite 1 harder." end
    if #parts == 0 then return "They are on their guard." end
    return table.concat(parts, " ")
end

function Scene:drawSpot(i, id, r)
    local run = self.run
    local spot = PD.spots[id]
    local grp = Hunt.group(run, id)
    local can = Hunt.can(run)
    local hov = self.hover == "hunt" .. i and can
    local lift = hov and -6 or 0
    r = { x = r.x, y = r.y + lift, w = r.w, h = r.h }
    Paper.panel(r.x, r.y, r.w, r.h, { fill = hov and { 1, 0.98, 0.9 } or C.cream, seed = 510 + i, r = 18, rot = (i - 2) * 0.005 })
    local cx = r.x + r.w / 2
    Text.display(spot.name, r.x + 14, r.y + 16, 18, INK, "center", r.w - 28)
    Text.body(spot.text, r.x + 18, r.y + 44, 11.5, SOFT, "center", r.w - 36)
    -- the prize
    local py = r.y + 184
    UI.tag("PRIZE", cx, py - 88, 12, C.orange, { align = "center", seed = 511 + i })
    UI.bugDisc(grp.prize, cx, py, 58, { ring = C.yellow, seed = 512 + i })
    if not run.seen[grp.prize] then UI.tag("NEW!", cx + 40, py - 62, 11, C.magenta, { seed = 513 + i, rot = 0.12 }) end
    for _, e in ipairs(run.jar) do
        if e.species == grp.prize and not e.big then UI.tag("GROWS!", cx + 34, py + 30, 11, C.green, { seed = 514 + i, rot = -0.1 }); break end
    end
    Text.display(Bugs[grp.prize].name, r.x + 14, py + 68, 16, INK, "center", r.w - 28)
    self:tipArea({ x = cx - 60, y = py - 60, w = 120, h = 120 }, Bugs[grp.prize].name, Bugs[grp.prize].role .. ". " .. Bugs[grp.prize].rules.action .. "\n\nCatch one you already have and yours grows bigger (+1 stamina, or +1 ant).")
    -- who comes with it
    local wy = r.y + 304
    Text.display("WITH", r.x + 16, wy - 7, 12, SOFT, "left")
    local list = {}
    for _, sp in ipairs(grp.common) do list[#list + 1] = { sp = sp } end
    for _, sp in ipairs(grp.guards) do list[#list + 1] = { sp = sp, mark = "guard" } end
    for _, sp in ipairs(grp.nest) do list[#list + 1] = { sp = sp, mark = "nest" } end
    for k, e in ipairs(list) do
        local x = r.x + 84 + (k - 1) * 46
        UI.bugDisc(e.sp, x, wy, 20, { ring = e.mark and C.red or C.magenta, seed = 520 + k, shadow = false })
        local why = e.mark == "guard" and "A guard: the Buzz brought it." or e.mark == "nest" and "The nest joined in!" or "Lives here."
        self:tipArea({ x = x - 20, y = wy - 20, w = 40, h = 40 }, Bugs[e.sp].name, why .. " " .. Bugs[e.sp].rules.action)
    end
    Text.body(groupLine(grp), r.x + 16, r.y + 334, 12, C.magentaDark, "left", r.w - 32)
    -- nature
    local nat = PD.natures[spot.nature]
    local ny = r.y + 386
    Paper.disc(r.x + 34, ny, 18, { 0.8, 0.95, 0.97 }, { seed = 530 + i, line = 2.5 })
    UI.icon(nat.icon, r.x + 34, ny, 26)
    Text.display(nat.sig.name, r.x + 60, ny - 16, 13, INK, "left", r.w - 76)
    Text.body(nat.sig.once and ("Arrives in " .. nat.sig.timer .. " ticks.") or ("Every " .. nat.sig.timer .. " ticks."), r.x + 60, ny + 2, 11.5, SOFT, "left", r.w - 76)
    self:tipArea({ x = r.x + 10, y = ny - 22, w = r.w - 20, h = 44 }, nat.name, nat.sig.text)
    -- the button
    local why
    if not can then why = Run.overflow(run) > 0 and "Your Jar is too full." or "All your bugs are napping." end
    self:button({ x = r.x + 16, y = r.y + r.h - 64, w = r.w - 32, h = 50 }, "hunt" .. i, "HUNT HERE", { size = 22, fill = C.green, seed = 540 + i, disabled = not can, tip = why and { "NOT NOW", why } or nil }, { spot = id })
    local key, nxt = Hunt.nextPrize(id, run.buzz or 0)
    if key then Text.body("At Buzz " .. key .. ": " .. Bugs[nxt].name, cx, r.y + r.h - 86, 11, SOFT, "center") end
end

function Scene:drawHunts()
    local run = self.run
    local P = HUNTS
    Paper.panel(P.x, P.y, P.w, P.h, { fill = { 0.86, 0.96, 0.84 }, seed = 550, r = 22, rot = -0.002 })
    Text.display("BUG HUNTS", P.x + 24, P.y + 18, 28, INK, "left")
    Text.body("No marbles at stake. Take up to " .. PD.HUNT_PARTY .. " bugs and your jar: wild bugs that walk into it are yours. Knocked-out bugs of yours run loose: get them back into the jar!", P.x + 24, P.y + 54, 12.5, INK, "left", P.w - 420)
    -- the Buzz
    local bx, by, bw, bh = P.x + P.w - 372, P.y + 12, 356, 94
    Paper.panel(bx, by, bw, bh, { fill = C.cream, seed = 551, r = 14, line = 3 })
    local buzz = run.buzz or 0
    local info = PD.buzz[buzz]
    Text.display("THE BUZZ: " .. info.name, bx + 14, by + 10, 15, INK, "left", 190)
    for k = 0, PD.BUZZ_MAX do
        local col = k <= buzz and BUZZ_COL[k + 1] or { 1, 1, 1, 0.5 }
        Paper.disc(bx + 220 + k * 28, by + 18, 10, col, { seed = 552 + k, line = 2.5, shadow = k <= buzz })
    end
    UI.icon("icon_bee", bx + 220 + buzz * 28, by + 18, 22)
    Text.body(info.text, bx + 14, by + 40, 11.5, SOFT, "left", bw - 28)
    self:tipArea({ x = bx, y = by, w = bw, h = bh }, "THE BUZZ", "Every hunt stirs the zone up a little more (up to 4): wild groups get guards, bite harder and start sooner, and the prizes get rarer. A duel calms the park down again.")
    for i, id in ipairs(PD.zones[run.zone].spots) do
        self:drawSpot(i, id, { x = P.x + 16 + (i - 1) * 306, y = P.y + 112, w = 292, h = 492 })
    end
end

function Scene:drawKidCard(i, id, r)
    local run = self.run
    local rv = Rivals[id]
    local stack = run.stacks[id] or 0
    local hov = self.hover == "duel" .. i
    local lift = hov and -6 or 0
    r = { x = r.x, y = r.y + lift, w = r.w, h = r.h }
    Paper.panel(r.x, r.y, r.w, r.h, { fill = C.cream, seed = 560 + i, r = 18, rot = (i == 1) and -0.006 or 0.006 })
    UI.kidDisc(rv.portrait, "neutral", r.x + 62, r.y + 64, 48, 561 + i)
    Text.display(rv.name, r.x + 120, r.y + 18, 17, INK, "left", r.w - 132)
    Text.body(rv.short, r.x + 120, r.y + 44, 11.5, SOFT, "left", r.w - 132)
    UI.marble(r.x + 30, r.y + 140, 30)
    Text.display(UI.plural(stack, "MARBLE"), r.x + 52, r.y + 128, 20, INK, "left", r.w - 64)
    local stake = math.min(run.marbles, stack)
    local mine = run.marbles <= stack
    Text.body("Round 1: both bet " .. stake .. ".", r.x + 18, r.y + 162, 12, INK, "left", r.w - 36)
    UI.tag(mine and "YOU: ALL IN" or "THEM: ALL IN", r.x + r.w - 14, r.y + 158, 10, mine and C.red or C.green, { align = "right", seed = 562 + i })
    Text.body(rulesLine(rv), r.x + 18, r.y + 186, 12, C.tealDark, "left", r.w - 36)
    for k = 1, math.min(rv.field or 4, #rv.roster) do
        UI.bugDisc(rv.roster[k], r.x + 30 + (k - 1) * 34, r.y + 258, 15, { ring = C.magenta, seed = 563 + k, shadow = false })
    end
    local blocked = Run.overflow(run) > 0
    self:button({ x = r.x + r.w - 124, y = r.y + 234, w = 112, h = 48 }, "duel" .. i, "DUEL!", { size = 22, fill = C.magenta, seed = 570 + i, disabled = blocked }, { rival = id })
end

function Scene:drawLeaderCard(r)
    local run = self.run
    local id = run.leader
    local rv = Rivals[id]
    local stack = run.stacks[id] or 0
    local hov = self.hover == "duel1"
    Paper.panel(r.x, r.y + (hov and -6 or 0), r.w, r.h, { fill = C.cream, seed = 580, r = 18, rot = -0.004, tape = true })
    local y = r.y + (hov and -6 or 0)
    UI.kidDisc(rv.portrait, "neutral", r.x + 92, y + 94, 72, 581)
    Text.display(rv.name, r.x + 184, y + 18, 24, INK, "left", r.w - 200)
    Text.body(rv.short, r.x + 184, y + 50, 12, SOFT, "left", r.w - 200)
    UI.marble(r.x + 198, y + 96, 30)
    Text.display(UI.plural(stack, "MARBLE"), r.x + 220, y + 84, 22, INK, "left", 200)
    if run.fed then
        Text.body("(+" .. run.fed.marbles .. " from " .. Rivals[run.fed.kid].name .. ", who lost to them)", r.x + 184, y + 112, 11.5, C.magentaDark, "left", r.w - 200)
    end
    local stake = math.min(run.marbles, stack)
    Text.body("Round 1: you both bet " .. stake .. ".", r.x + 184, y + 132, 12, INK, "left", 200)
    UI.tag(run.marbles <= stack and "YOU'RE ALL IN" or "THEY'RE ALL IN", r.x + 380, y + 128, 10, run.marbles <= stack and C.red or C.green, { seed = 582 })
    if rv.house then
        Paper.panel(r.x + 184, y + 160, r.w - 200, 74, { fill = { 1, 0.9, 0.95 }, seed = 583, r = 12, line = 2.5, shadow = false })
        Text.display("HOUSE RULE", r.x + 198, y + 168, 11, C.magentaDark, "left")
        Text.body('"' .. rv.house.name .. '" ' .. rv.house.text, r.x + 198, y + 186, 12, INK, "left", r.w - 228)
    end
    Text.body(rulesLine(rv), r.x + 184, y + 244, 12, C.tealDark, "left", r.w - 200)
    for k = 1, math.min(rv.field or 4, #rv.roster) do
        UI.bugDisc(rv.roster[k], r.x + 198 + (k - 1) * 38, y + 282, 16, { ring = C.magenta, seed = 584 + k, shadow = false })
    end
    self:button({ x = r.x + 20, y = r.y + 196, w = 148, h = 60 }, "duel1", "DUEL!", { size = 26, fill = C.magenta, seed = 590, disabled = Run.overflow(run) > 0 }, { rival = id })
end

function Scene:drawRivals()
    local run = self.run
    local P = RIVALS
    Paper.panel(P.x, P.y, P.w, P.h, { fill = { 1, 0.9, 0.93 }, seed = 595, r = 22, rot = 0.002 })
    if run.window == 1 then
        Text.display("CHALLENGE A KID", P.x + 22, P.y + 18, 26, INK, "left")
        local other = "The other one goes to play " .. Rivals[run.leader].name .. " instead, and loses: their marbles join the Gang leader's stack."
        Text.body("Pick one for a duel. " .. other, P.x + 22, P.y + 54, 12, INK, "left", P.w - 44)
        for i, id in ipairs(run.kids or {}) do self:drawKidCard(i, id, { x = P.x + 12 + (i - 1) * 294, y = P.y + 110, w = 282, h = 296 }) end
        local rv = Rivals[run.leader]
        Text.body("Then the Gang leader: " .. rv.name .. " (" .. (run.stacks[run.leader] or 0) .. " marbles, more after your duel).", P.x + 22, P.y + P.h - 32, 12, C.magentaDark, "left", P.w - 44)
    else
        Text.display("THE GANG LEADER", P.x + 22, P.y + 18, 26, INK, "left")
        Text.body("Beat them and this part of the day is yours: you pick a pocket item and your Jar grows.", P.x + 22, P.y + 54, 12, INK, "left", P.w - 44)
        self:drawLeaderCard({ x = P.x + 12, y = P.y + 98, w = P.w - 24, h = 340 })
    end
end

function Scene:sideButton(i, key, iconName, label, sub, o)
    local r = { x = SIDE.x + (i - 1) * 206, y = SIDE.y, w = 188, h = SIDE.h }
    local hov = self.hover == key and not o.disabled
    local y = r.y + (hov and -6 or 0)
    Paper.panel(r.x, y, r.w, r.h, { fill = o.disabled and { 0.78, 0.76, 0.82 } or o.fill, seed = 600 + i, r = 18, rot = (i - 2) * 0.01 })
    UI.icon(iconName, r.x + r.w / 2, y + 42, 62, o.disabled and 0.45 or 1)
    if o.badge then UI.tag(o.badge, r.x + r.w - 30, y + 6, 11, C.magenta, { seed = 605 + i, rot = 0.15 }) end
    Text.display(label, r.x + 10, y + 80, 18, o.disabled and { 0.4, 0.38, 0.45 } or INK, "center", r.w - 20)
    Text.body(sub, r.x + 12, y + 104, 11, o.disabled and { 0.4, 0.38, 0.45 } or SOFT, "center", r.w - 24)
    UI.hit(self.hits, r, key, { disabled = o.disabled, tip = o.tip })
end

function Scene:drawSide()
    local run = self.run
    local van = Shop.isOpen(run)
    self:sideButton(1, "van", "icon_icecream", "THE VAN", van and "Cards, bugs and pocket items." or "Comes after your duel.",
        { fill = C.orange, disabled = not van })
    local benchFree = not run.bench
    self:sideButton(2, "bench", "icon_bench", "THE BENCH", benchFree and "Rest, or sort your deck. Once." or "Used this part of the day.",
        { fill = { 0.8, 0.89, 1.0 }, disabled = not benchFree })
    local ev = run.event
    self:sideButton(3, "event", "icon_question", ev and "SOMETHING'S UP!" or "ALL QUIET", ev and PD.events[ev.kind].name or "Nothing going on right now.",
        { fill = C.yellow, disabled = not ev, badge = ev and "!" or nil })
end

function Scene:drawJar()
    local run = self.run
    local P = JAR
    Paper.panel(P.x, P.y, P.w, P.h, { fill = { 0.8, 0.95, 0.97 }, seed = 610, r = 20, rot = 0.002 })
    UI.icon("icon_jar", P.x + 40, P.y + 44, 52)
    Text.display("YOUR JAR", P.x + 74, P.y + 22, 18, INK, "left")
    local over = Run.overflow(run) > 0
    Text.display(#run.jar .. "/" .. run.jarSlots, P.x + 74, P.y + 48, 22, over and C.red or C.tealDark, "left")
    local bandaid = Run.has(run, "bandaid")
    if bandaid then
        local line = run.bandaid and "Band-Aid used." or "Band-Aid: click a napping bug."
        Text.body(line, P.x + 18, P.y + 92, 11.5, run.bandaid and SOFT or C.magentaDark, "left", 210)
    else
        Text.body("Hover a bug to read it.", P.x + 18, P.y + 92, 11.5, SOFT, "left", 210)
    end
    local n = math.max(run.jarSlots, #run.jar)
    local x0 = P.x + 240
    local sw = math.min(160, math.floor((P.x + P.w - 12 - x0) / n) - 8)
    for i = 1, n do
        local e = run.jar[i]
        local r = { x = x0 + (i - 1) * (sw + 8), y = P.y + 12, w = sw, h = P.h - 24 }
        if e then
            local key = "jar" .. i
            local hov = self.hover == key
            local extra = i > run.jarSlots
            Paper.panel(r.x, r.y + (hov and -4 or 0), r.w, r.h, { fill = hov and { 1, 1, 1 } or C.cream, seed = 611 + i, r = 14, line = extra and 5 or 3, rot = (i % 2 == 0) and 0.01 or -0.01 })
            local y = r.y + (hov and -4 or 0)
            UI.bugDisc(e.species, r.x + r.w / 2, y + 40, 30, { seed = 620 + i, alpha = e.nap and 0.55 or 1, ring = e.nap and { 0.62, 0.6, 0.7 } or C.teal })
            Text.display(Bugs[e.species].short, r.x + 6, y + 78, 13, INK, "center", r.w - 12)
            if e.nap then
                UI.icon("fx_zzz", r.x + r.w - 22, y + 18, 30)
                Text.body("napping", r.x + r.w / 2, y + 94, 10.5, C.purple, "center")
            elseif e.big then
                UI.tag("BIG", r.x + r.w - 34, y + 4, 10, C.green, { seed = 630 + i, rot = 0.12 })
            end
            local status = e.nap and "\n\nNapping: it sits out the next duel round, then wakes up. The bench or an ice cream wakes it sooner." or ""
            if e.big then status = status .. "\n\nBIG: it grew when you caught another one." end
            local act = Bugs[e.species].rules.action
            UI.hit(self.hits, r, key, { tip = { Bugs[e.species].name, entryLine(e) .. "\n" .. act .. status .. "\n\nClick to let it go." }, data = { uid = e.uid } })
        else
            Paper.panel(r.x, r.y, r.w, r.h, { fill = { 1, 1, 1, 0.35 }, seed = 640 + i, r = 14, line = 2, shadow = false })
        end
    end
end

function Scene:drawFree()
    self:backdrop(PD.zones[self.run.zone].backdrop, 0.18)
    self:drawTop()
    self:drawHunts()
    self:drawRivals()
    self:drawSide()
    self:drawJar()
end

-- ───────────────────────── dialogs ─────────────────────────

local function dialogPanel(x, y, w, h, fill, seed)
    UI.veil(0.55)
    Paper.panel(x, y, w, h, { fill = fill or { 1, 0.95, 0.7 }, seed = seed or 700, r = 26, rot = -0.004, tape = true })
end

function Scene:drawHuntSum()
    local run = self.run
    local sum = self.dialog.sum
    local P = { x = 280, y = 90, w = 1040, h = 720 }
    dialogPanel(P.x, P.y, P.w, P.h, nil, 701)
    local got = #sum.caught
    Text.display(got > 0 and "WHAT A HUNT!" or "NOTHING IN THE JAR", 800, P.y + 32, 44, got > 0 and C.magenta or C.purple, "center")
    Text.body(PD.spots[sum.spot].name .. ", " .. PD.zones[run.zone].name, 800, P.y + 90, 16, SOFT, "center")
    local y = P.y + 132
    if got > 0 then
        local w = math.min(220, (P.w - 80) / got)
        local x0 = 800 - w * got / 2
        for i, c in ipairs(sum.caught) do
            local cx = x0 + (i - 0.5) * w
            UI.bugDisc(c.species, cx, y + 64, 56, { ring = c.prize and C.yellow or C.teal, seed = 710 + i })
            if c.prize then UI.tag("PRIZE!", cx, y - 4, 12, C.orange, { align = "center", seed = 711 + i }) end
            Text.display(Bugs[c.species].short, cx - w / 2 + 8, y + 132, 17, INK, "center", w - 16)
            local how = c.how == "merged" and "GREW BIGGER!" or "NEW BUG!"
            UI.tag(how, cx, y + 160, 11, c.how == "merged" and C.green or C.teal, { align = "center", seed = 712 + i })
        end
        y = y + 210
    else
        Text.body("Not one bug walked into your jar this time. Lure them closer, or nudge them in.", P.x + 80, y, 18, INK, "center", P.w - 160)
        y = y + 60
    end
    local x, w = P.x + 70, P.w - 140
    local function line(str, col, size)
        Text.body(str, x, y, size or 16, col or INK, "left", w)
        y = y + Text.bodyHeight(str, size or 16, w) + 10
    end
    local names = function(list)
        local out = {}
        for i, sp in ipairs(list) do out[i] = Bugs[sp].short end
        return table.concat(out, ", ")
    end
    if #sum.napped > 0 then line("Napping now: " .. names(sum.napped) .. ". They sit out the next duel round.", C.purple) end
    if #sum.lost > 0 then line("Ran off into the wild for good: " .. names(sum.lost) .. ".", C.magentaDark) end
    local buzz = math.min(PD.BUZZ_MAX, (sum.buzz or 0) + 1)
    if buzz > (sum.buzz or 0) then
        line("The Buzz rises: " .. PD.buzz[buzz].name .. ". " .. PD.buzz[buzz].text, C.tealDark, 14.5)
    else
        line("The zone is " .. PD.buzz[buzz].name .. ". " .. PD.buzz[buzz].text, C.tealDark, 14.5)
    end
    local sp = sum.newSpecies and sum.newSpecies[1]
    if sp then
        local jy = math.max(y + 4, P.y + P.h - 250)
        Paper.panel(P.x + 50, jy, P.w - 100, 128, { fill = { 0.8, 0.95, 0.97 }, seed = 720, r = 16, rot = -0.003 })
        UI.bugDisc(sp, P.x + 120, jy + 64, 46, { seed = 721 })
        Text.display("NEW IN YOUR BUG JOURNAL: " .. Bugs[sp].name, P.x + 184, jy + 18, 16, C.tealDark, "left", P.w - 270)
        Text.body(Bugs[sp].fact, P.x + 184, jy + 46, 13, INK, "left", P.w - 270)
    end
    local over = Run.overflow(run) > 0
    self:button({ x = 800 - 200, y = P.y + P.h - 104, w = 400, h = 78 }, "ok", over and "MAKE ROOM IN THE JAR" or "BACK TO THE PARK", { size = 26, fill = over and C.orange or C.teal, seed = 725 })
end

function Scene:drawEvent()
    local run = self.run
    local ev = run.event
    if not ev then self.dialog = nil; return end
    local def = PD.events[ev.kind]
    local P = { x = 330, y = 130, w = 940, h = 620 }
    dialogPanel(P.x, P.y, P.w, P.h, nil, 730)
    Text.display(def.name, 800, P.y + 34, 40, C.magenta, "center")
    Text.body(def.text, P.x + 70, P.y + 96, 17, INK, "center", P.w - 140)
    local by = P.y + P.h - 110
    if ev.kind == "swap" then
        local mine = ParkSim.swapEntry(run)
        if not mine then
            Text.body("The bug they wanted isn't in your Jar any more. The swap is off.", P.x + 70, P.y + 260, 18, INK, "center", P.w - 140)
            self:button({ x = 800 - 160, y = by, w = 320, h = 78 }, "evok", "OH WELL", { size = 28, fill = C.teal, seed = 731 })
            return
        end
        UI.bugDisc(mine.species, 610, P.y + 300, 70, { seed = 732 })
        Text.display("YOUR " .. Bugs[mine.species].short, 610 - 150, P.y + 386, 18, INK, "center", 300)
        Text.body(entryLine(mine), 610, P.y + 414, 12.5, SOFT, "center")
        Text.display(">", 800, P.y + 280, 50, C.orange, "center")
        UI.bugDisc(ev.give, 990, P.y + 300, 70, { ring = C.magenta, seed = 733 })
        Text.display("THEIR " .. Bugs[ev.give].short, 990 - 150, P.y + 386, 18, INK, "center", 300)
        Text.body(Bugs[ev.give].role, 990, P.y + 414, 12.5, SOFT, "center")
        self:tipArea({ x = 920, y = P.y + 230, w = 140, h = 140 }, Bugs[ev.give].name, Bugs[ev.give].rules.action)
        self:button({ x = P.x + 120, y = by, w = 320, h = 78 }, "evyes", "SWAP!", { size = 30, fill = C.teal, seed = 734 })
        self:button({ x = P.x + P.w - 440, y = by, w = 320, h = 78 }, "evno", "NO THANKS", { size = 28, fill = C.cream2, color = INK, seed = 735 })
    elseif ev.kind == "ball" then
        love.graphics.push()
        love.graphics.translate(P.x + 150, P.y + 330)
        love.graphics.scale(0.95, 0.95)
        HandView.drawCard(ev.card)
        love.graphics.pop()
        Text.body("The kid's thank-you", P.x + 150, P.y + 440, 13, SOFT, "center")
        Text.display("WHO GOES LOOKING?", P.x + 300, P.y + 200, 16, C.tealDark, "left")
        local list = {}
        for _, e in ipairs(run.jar) do if not e.nap then list[#list + 1] = e end end
        for i, e in ipairs(list) do
            local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
            local r = { x = P.x + 300 + col * 140, y = P.y + 232 + row * 120, w = 128, h = 108 }
            local key = "ball" .. i
            local hov = self.hover == key
            Paper.panel(r.x, r.y + (hov and -5 or 0), r.w, r.h, { fill = hov and C.yellow or C.cream, seed = 740 + i, r = 14, line = 3 })
            UI.bugDisc(e.species, r.x + r.w / 2, r.y + 42 + (hov and -5 or 0), 30, { seed = 745 + i })
            Text.display(Bugs[e.species].short, r.x + 6, r.y + 80 + (hov and -5 or 0), 13, INK, "center", r.w - 12)
            UI.hit(self.hits, r, key, { data = { uid = e.uid }, tip = { "Send the " .. Bugs[e.species].short .. "?", "It comes back worn out: it naps until it has sat out a duel round." } })
        end
        if #list == 0 then Text.body("Everybody is napping.", P.x + 300, P.y + 240, 16, SOFT, "left") end
        self:button({ x = 800 - 160, y = by, w = 320, h = 78 }, "evno", "NOT NOW", { size = 28, fill = C.cream2, color = INK, seed = 749 })
    else
        UI.icon(ev.kind == "shower" and "fx_drop" or "icon_foot", 800, P.y + 300, 150)
        self:button({ x = 800 - 160, y = by, w = 320, h = 78 }, "evyes", "OK!", { size = 30, fill = C.teal, seed = 750 })
    end
end

function Scene:drawBench()
    local run = self.run
    local P = { x = 400, y = 200, w = 800, h = 480 }
    dialogPanel(P.x, P.y, P.w, P.h, { 0.86, 0.92, 1 }, 760)
    UI.icon("icon_bench", P.x + 110, P.y + 90, 120)
    Text.display("THE BENCH", P.x + 200, P.y + 40, 40, INK, "left")
    Text.body("Sit down for a bit. You can do ONE of these, once per part of the day.", P.x + 200, P.y + 96, 16, SOFT, "left", P.w - 260)
    local napping = Run.anyNapping(run)
    local r1 = { x = P.x + 50, y = P.y + 190, w = 330, h = 150 }
    local r2 = { x = P.x + P.w - 380, y = P.y + 190, w = 330, h = 150 }
    self:button(r1, "nap", "NAP TIME", { size = 28, fill = C.purpleLight, seed = 761, disabled = not napping, tip = { "NAP TIME", napping and "Every napping bug in your Jar wakes up." or "Nobody is napping right now." } })
    Text.body("Every napping bug wakes up.", r1.x + r1.w / 2, r1.y + r1.h + 10, 13, SOFT, "center")
    local small = #run.deck <= Shop.MIN_DECK
    self:button(r2, "sort", "SORT YOUR DECK", { size = 26, fill = C.teal, seed = 762, disabled = small, tip = small and { "SORT YOUR DECK", "Your deck is as small as it gets." } or nil })
    Text.body("Throw one card away.", r2.x + r2.w / 2, r2.y + r2.h + 10, 13, SOFT, "center")
    self:button({ x = 800 - 130, y = P.y + P.h - 92, w = 260, h = 64 }, "close", "NOT NOW", { size = 24, fill = C.cream2, color = INK, seed = 763 })
end

--- Every card of the deck in a grid. dialog.pick: what a click does (nil = just looking).
function Scene:drawCards()
    local run = self.run
    local d = self.dialog
    local P = { x = 70, y = 40, w = 1460, h = 820 }
    dialogPanel(P.x, P.y, P.w, P.h, C.cream, 770)
    Text.display(d.title or "YOUR DECK", 800, P.y + 24, 36, C.magenta, "center")
    Text.body(d.text or (#run.deck .. " cards. You draw 5 at the start of every fight."), 800, P.y + 74, 15, SOFT, "center")
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
        love.graphics.translate(cx, cy - (hov and d.pick and 10 or 0))
        love.graphics.scale(k * (hov and 1.06 or 1), k * (hov and 1.06 or 1))
        HandView.drawCard(id, { glow = hov and d.pick ~= nil })
        love.graphics.pop()
        if d.pick then UI.hit(self.hits, { x = cx - cw / 2, y = cy - ch / 2, w = cw, h = ch }, key, { data = { i = i } }) end
    end
    self:button({ x = 800 - 150, y = P.y + P.h - 92, w = 300, h = 66 }, "close", d.pick and "CANCEL" or "CLOSE", { size = 26, fill = d.pick and C.cream2 or C.teal, color = d.pick and INK or nil, seed = 771 })
end

function Scene:drawLetGo()
    local run = self.run
    local e = Run.entry(run, self.dialog.uid)
    if not e then self.dialog = nil; return end
    local P = { x = 460, y = 250, w = 680, h = 400 }
    dialogPanel(P.x, P.y, P.w, P.h, { 0.9, 0.85, 1 }, 780)
    UI.bugDisc(e.species, P.x + 110, P.y + 130, 66, { seed = 781 })
    Text.display("LET THE " .. Bugs[e.species].short .. " GO?", P.x + 200, P.y + 60, 30, C.purple, "left", P.w - 230)
    Text.body("It walks back into the grass for good." .. (e.big and " It's a big one, too." or ""), P.x + 200, P.y + 110, 17, INK, "left", P.w - 230)
    local napHelp = e.nap and Run.has(run, "bandaid") and not run.bandaid
    if napHelp then Text.body("It's napping. Your Band-Aid could wake it up instead.", P.x + 200, P.y + 170, 15, C.magentaDark, "left", P.w - 230) end
    local by = P.y + P.h - 110
    self:button({ x = P.x + 50, y = by, w = 270, h = 76 }, "goyes", "LET IT GO", { size = 26, fill = C.orange, seed = 782 })
    if napHelp then
        self:button({ x = P.x + P.w - 320, y = by, w = 270, h = 76 }, "bandaid", "BAND-AID", { size = 26, fill = C.teal, seed = 783 })
    else
        self:button({ x = P.x + P.w - 320, y = by, w = 270, h = 76 }, "close", "KEEP IT", { size = 26, fill = C.teal, seed = 784 })
    end
end

function Scene:drawOverflow()
    local run = self.run
    local over = Run.overflow(run)
    if over <= 0 then self.dialog = nil; self:autoDialog(); return end
    local P = { x = 160, y = 150, w = 1280, h = 600 }
    dialogPanel(P.x, P.y, P.w, P.h, { 1, 0.9, 0.85 }, 790)
    Text.display("YOUR JAR IS TOO FULL!", 800, P.y + 34, 42, C.red, "center")
    Text.body("Room for " .. run.jarSlots .. " bugs, and you have " .. #run.jar .. ". Let " .. (over == 1 and "one" or over) .. " of them go back into the grass.", 800, P.y + 92, 17, INK, "center")
    local n = #run.jar
    local w = math.min(170, (P.w - 80) / n)
    local x0 = 800 - w * n / 2
    for i, e in ipairs(run.jar) do
        local r = { x = x0 + (i - 1) * w + 6, y = P.y + 160, w = w - 12, h = 260 }
        local key = "free" .. i
        local hov = self.hover == key
        Paper.panel(r.x, r.y + (hov and -6 or 0), r.w, r.h, { fill = hov and C.yellow or C.cream, seed = 791 + i, r = 16, line = 3 })
        local y = r.y + (hov and -6 or 0)
        UI.bugDisc(e.species, r.x + r.w / 2, y + 70, 48, { seed = 800 + i, alpha = e.nap and 0.6 or 1 })
        Text.display(Bugs[e.species].short, r.x + 6, y + 132, 15, INK, "center", r.w - 12)
        Text.body(entryLine(e), r.x + 10, y + 158, 11, SOFT, "center", r.w - 20)
        if e.nap then Text.body("napping", r.x + r.w / 2, y + 196, 11, C.purple, "center") end
        if e.big then UI.tag("BIG", r.x + r.w - 40, y + 6, 10, C.green, { seed = 805 + i }) end
        Text.display("LET GO", r.x + r.w / 2, y + r.h - 34, 14, C.magentaDark, "center")
        UI.hit(self.hits, r, key, { data = { uid = e.uid } })
    end
    Text.body("Bugs you let go are gone for good. You can't hunt, duel or shop until the Jar fits.", 800, P.y + P.h - 70, 14, SOFT, "center")
end

function Scene:drawNote()
    local d = self.dialog
    local P = { x = 430, y = 260, w = 740, h = 360 }
    dialogPanel(P.x, P.y, P.w, P.h, nil, 810)
    Text.display(d.title, 800, P.y + 40, 38, C.magenta, "center")
    Text.body(d.text, P.x + 60, P.y + 104, 17, INK, "center", P.w - 120)
    self:button({ x = 800 - 150, y = P.y + P.h - 104, w = 300, h = 74 }, "ok", "OK!", { size = 30, fill = C.teal, seed = 811 })
end

function Scene:drawDialog()
    local k = self.dialog.kind
    if k == "hunt" then self:drawHuntSum()
    elseif k == "event" then self:drawEvent()
    elseif k == "bench" then self:drawBench()
    elseif k == "cards" then self:drawCards()
    elseif k == "letgo" then self:drawLetGo()
    elseif k == "overflow" then self:drawOverflow()
    elseif k == "note" then self:drawNote() end
end

-- ───────────────────────── draw & input ─────────────────────────

function Scene:draw()
    self.hits = {}
    local phase = self.run.phase
    if phase == "prologue" then self:drawPrologue()
    elseif phase == "zone" then self:drawZones()
    elseif phase == "reward" then self:drawReward()
    elseif phase == "free" then self:drawFree() end
    if self.dialog then
        self.hits = {}
        self:drawDialog()
    end
    local h = UI.hitAt(self.hits, self.mouse.x, self.mouse.y)
    self.hover = h and h.key or nil
    if h and h.data and h.data.tip then UI.tooltip(self.mouse.x, self.mouse.y, h.data.tip[1], h.data.tip[2]) end
end

function Scene:update(dt)
    self.time = self.time + dt
    -- a saved day can come back in any phase: duels and the end have scenes of their own
    if not self.routed and not self.app.trans and Flow.sceneFor(self.run) ~= "park" then
        self.routed = true
        Flow.go(self.app, self.run)
    end
end

function Scene:open(d)
    Audio.play("ui_click")
    self.dialog = d
end

--- auto: something was settled, so whatever else is waiting (a full Jar, an event) comes up next.
function Scene:closeDialog(auto)
    self.dialog = nil
    if auto then self:autoDialog() else Audio.play("ui_back") end
end

function Scene:startHunt(spot)
    if not Hunt.can(self.run) then Audio.play("block"); return end
    Audio.play("ui_click")
    self.app.switch("fight", { run = self.run, mode = "hunt", spot = spot })
end

function Scene:startDuel(rival)
    local ok = Duel.start(self.run, rival)
    if not ok then Audio.play("block"); return end
    Audio.play("ui_click")
    Audio.play("entry", 0.6)
    Flow.go(self.app, self.run)
end

function Scene:press(key, data)
    local run, app = self.run, self.app
    local action, n = key:match("^(%a+)(%d*)$")
    n = tonumber(n)
    local d = self.dialog
    if action == "warmup" then
        Audio.play("ui_click")
        app.switch("fight", { run = run, mode = "prologue" })
    elseif action == "skip" then
        Audio.play("ui_click")
        Run.endPrologue(run)
        Flow.go(app, run)
    elseif action == "zone" then
        Audio.play("ui_click")
        Run.pickZone(run, n)
        Flow.go(app, run)
    elseif action == "reward" then
        Audio.play("coin")
        Run.pickReward(run, n)
        Flow.go(app, run)
    elseif action == "hunt" then self:startHunt(data.spot)
    elseif action == "duel" then self:startDuel(data.rival)
    elseif action == "van" then
        Audio.play("ui_click")
        app.switch("shop", { run = run })
    elseif action == "bench" then self:open({ kind = "bench" })
    elseif action == "event" then self:open({ kind = "event" })
    elseif action == "deck" then self:open({ kind = "cards" })
    elseif action == "jar" then self:open({ kind = "letgo", uid = data.uid })
    elseif action == "ok" then
        Audio.play("ui_click")
        self:closeDialog(true)
    elseif action == "evyes" then
        local kind = run.event and run.event.kind
        if ParkSim.answer(run, true) then
            Saves.store(run)
            Audio.play(kind == "swap" and "coin" or kind == "shower" and "splash" or kind == "dog" and "bump" or "ui_click")
            if kind == "swap" then Fx.sparkle(800, 420, 12, 120); Fx.text("SWAPPED!", 800, 380, C.yellow, 40) end
            if kind == "shower" then for i = 1, 8 do Fx.drops(200 * i, 300, 5) end end
        end
        self:closeDialog(true)
    elseif action == "evno" or action == "evok" then
        ParkSim.dismiss(run)
        Saves.store(run)
        Audio.play("ui_back")
        self:closeDialog(true)
    elseif action == "ball" then
        local card = run.event.card
        if ParkSim.answer(run, true, data.uid) then
            Saves.store(run)
            Audio.play("coin")
            self.dialog = { kind = "note", title = "NEW CARD: " .. Cards[card].name, text = "Your bug found the ball under the bushes, and came back worn out (it naps). The kid gave you a card: it's in your deck now." }
        end
    elseif action == "nap" then
        if ParkSim.bench(run, "wake") then
            Saves.store(run)
            Audio.play("getup")
            Fx.text("EVERYBODY'S UP!", 800, 820, C.yellow, 34)
        end
        self:closeDialog(true)
    elseif action == "sort" then
        self:open({ kind = "cards", pick = "bench", title = "THROW A CARD AWAY", text = "Click the card you want gone. Your deck keeps the rest." })
    elseif action == "card" then
        if d and d.pick == "bench" and ParkSim.bench(run, "remove", n) then
            Saves.store(run)
            Audio.play("blow")
            Fx.puff(800, 450, 10, 0.5)
            self:closeDialog(true)
        end
    elseif action == "goyes" then
        local e = Run.entry(run, d.uid)
        if e and Run.letGo(run, d.uid) then
            Saves.store(run)
            Audio.play("scurry")
            Fx.text("BYE, " .. Bugs[e.species].short .. "!", 800, 800, C.green, 30)
        end
        self:closeDialog(true)
    elseif action == "bandaid" then
        if ParkSim.bandaid(run, d.uid) then
            Saves.store(run)
            Audio.play("getup")
            Fx.text("ALL BETTER!", 800, 800, C.yellow, 30)
        end
        self:closeDialog(true)
    elseif action == "free" then
        if Run.letGo(run, data.uid) then
            Saves.store(run)
            Audio.play("scurry")
        end
    elseif action == "close" then
        self:closeDialog()
    end
end

function Scene:mousemoved(x, y)
    self.mouse.x, self.mouse.y = x, y
end

function Scene:mousepressed(x, y, b)
    self.mouse.x, self.mouse.y = x, y
    if b == 2 then
        if self.dialog and self.dialog.kind ~= "overflow" and self.dialog.kind ~= "hunt" then self:closeDialog() end
        return
    end
    if b ~= 1 then return end
    local h = UI.hitAt(self.hits, x, y)
    if not h or h.key == "tip" then return end
    if h.data and h.data.disabled then Audio.play("block"); return end
    self:press(h.key, (h.data and h.data.data) or {})
end

function Scene:keypressed(key)
    local d = self.dialog
    if d then
        if key == "escape" then
            if d.kind == "overflow" then Audio.play("block")
            elseif d.kind == "hunt" or d.kind == "note" then self:press("ok", {})
            else self:closeDialog() end
        elseif (key == "return" or key == "space") and (d.kind == "hunt" or d.kind == "note") then
            self:press("ok", {})
        end
        return
    end
    if key == "escape" then
        Audio.play("ui_back")
        self.app.switch("title")
    end
end

return Scene
