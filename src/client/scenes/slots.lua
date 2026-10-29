-- Save slots: three days at the park kept side by side. PLAY on the title screen comes here. A slot continues its run, or
-- starts a new one when it is empty or its day is over (the finished day stays there as a record until then). Erasing
-- asks first. Launched with --debug, a new game first asks for the seed of its random generator (empty = a random one).

local Assets = require("client.assets")
local Paper = require("client.paper")
local Text = require("client.text")
local Audio = require("client.audio")
local Tween = require("client.tween")
local Fx = require("client.fx")
local UI = require("client.ui")
local Saves = require("client.saves")
local Run = require("sim.run")
local Rivals = require("data.rivals")
local Bugs = require("data.bugs")

local C = Paper.C
local INK = Text.INK
local SOFT = { 0.4, 0.25, 0.5 }
local Slots = {}
Slots.__index = Slots

local CARD_W, CARD_H, GAP, CARD_Y = 440, 560, 50, 160
local BACK = { x = 650, y = 768, w = 300, h = 84 }
local DIALOG = { seed = { x = 400, y = 240, w = 800, h = 420 }, erase = { x = 400, y = 280, w = 800, h = 340 } }
local SEED_DIGITS = #tostring(Run.SEED_MAX)
local FILL = {
    empty = { 0.86, 0.95, 0.97 }, run = C.cream, won = { 1, 0.95, 0.7 }, lost = { 0.9, 0.85, 1 }, damaged = { 0.86, 0.82, 0.9 },
}

local SPECIES = 0
for _ in pairs(Bugs) do SPECIES = SPECIES + 1 end

local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "S") end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function marble(x, y, size)
    love.graphics.setColor(1, 1, 1, 1)
    local mw, mh = Assets.ui:size("icon_marble")
    love.graphics.draw(Assets.ui.image, Assets.ui.quads.icon_marble, x, y, 0, size / mh, size / mh, mw / 2, mh / 2)
end

local function when(t)
    if not t then return nil end
    local ok, s = pcall(os.date, "%b %d, %H:%M", t)
    return ok and s or nil
end

local function cardRect(i)
    local x0 = (1600 - (Saves.COUNT * CARD_W + (Saves.COUNT - 1) * GAP)) / 2
    return { x = x0 + (i - 1) * (CARD_W + GAP), y = CARD_Y, w = CARD_W, h = CARD_H }
end

function Slots.new(app, params)
    local self = setmetatable({ app = app, time = 0, frame = 0, hover = nil, dialog = nil, pop = {} }, Slots)
    self.slots = Saves.list()
    for i = 1, Saves.COUNT do self.pop[i] = 0 end
    self.hover = self:hitTest(app.mouse.x, app.mouse.y)
    return self
end

function Slots:enter()
    Audio.music("title")
    for i = 1, Saves.COUNT do
        Tween.after(0.07 * i, function() Tween.to(self.pop, { [i] = 1 }, 0.35, "outBack") end)
    end
end

function Slots:update(dt)
    self.time = self.time + dt
    self.frame = self.frame + 1
end

--- The buttons of a card. main = what clicking anywhere on the card does; erase = only when there is a day to erase.
function Slots:buttons(i)
    local s, r = self.slots[i], cardRect(i)
    local y = r.y + r.h - 108
    if s.kind == "empty" or s.kind == "damaged" then
        return { main = { x = r.x + 36, y = y, w = r.w - 72, h = 80 }, label = s.kind == "empty" and "NEW GAME" or "ERASE" }
    end
    return {
        main = { x = r.x + 28, y = y, w = 250, h = 80 }, label = s.kind == "run" and "CONTINUE" or "NEW GAME",
        erase = { x = r.x + r.w - 148, y = y + 8, w = 120, h = 64 },
    }
end

-- ───────────────────────── actions ─────────────────────────
function Slots:open(i)
    local s = self.slots[i]
    if s.kind == "run" then self:continue(i)
    elseif s.kind == "damaged" then self:askErase(i)
    elseif self.app.debug then
        Audio.play("ui_click")
        -- opened with a number key, the same key also arrives as typed text this frame: it must not become the seed
        self.dialog = { kind = "seed", slot = i, text = "", frame = self.frame }
    else
        self:start(i)
    end
end

--- A new day in slot i. seed: nil = a random one.
function Slots:start(i, seed)
    Audio.play("ui_click")
    Audio.play("win", 0.4)
    local run = Saves.create(i, seed)
    self.app.run = run
    self.app.switch("map", { run = run, intro = true })
end

function Slots:continue(i)
    Audio.play("ui_click")
    local run = self.slots[i].run
    self.app.run = run
    self.app.switch("map", { run = run })
end

function Slots:askErase(i)
    Audio.play("ui_click")
    self.dialog = { kind = "erase", slot = i }
end

function Slots:confirmErase()
    local i = self.dialog.slot
    self.dialog = nil
    Saves.erase(i)
    self.slots[i] = Saves.read(i)
    Audio.play("blow")
    local r = cardRect(i)
    Fx.puff(r.x + r.w / 2, r.y + r.h / 2, 12, 0.5)
    self.pop[i] = 0.6
    Tween.to(self.pop, { [i] = 1 }, 0.35, "outBack")
end

function Slots:closeDialog()
    self.dialog = nil
    Audio.play("ui_back")
end

function Slots:startSeeded()
    local d = self.dialog
    self.dialog = nil
    self:start(d.slot, d.text ~= "" and tonumber(d.text) or nil)
end

--- Digits typed (or pasted) into the seed field; anything else is ignored.
function Slots:typeDigits(str)
    local d = self.dialog
    local digits = str:gsub("%D", "")
    if digits == "" then return end
    local room = SEED_DIGITS - #d.text
    if room <= 0 then Audio.play("block"); return end
    d.text = d.text .. digits:sub(1, room)
end

function Slots:back()
    Audio.play("ui_back")
    self.app.switch("title")
end

-- ───────────────────────── drawing ─────────────────────────
local function drawJar(run, x, y, w, seed)
    Text.display("YOUR JAR", x, y, 13, C.tealDark, "left")
    local step = math.min(60, w / run.jarSlots)
    local rad = step * 0.42
    for j = 1, run.jarSlots do
        local e = run.jar[j]
        local cx, cy = x + step * (j - 0.5), y + 46
        Paper.disc(cx, cy, rad, e and C.cream or { 1, 1, 1, 0.4 }, { seed = seed + j, shadow = e ~= nil, line = e and 3 or 2 })
        if e then
            love.graphics.setColor(1, 1, 1, 1)
            Assets.drawPortrait(e.species, cx, cy, rad * 1.8)
            if e.tired then Assets.ui:draw("fx_zzz", cx + rad * 0.8, cy - rad * 0.8, 0, 0.13) end
        end
    end
end

local function drawRival(rv, mood, x, y, seed)
    Paper.disc(x, y, 56, C.magenta, { seed = seed, shadow = true, line = 4 })
    Paper.disc(x, y, 49, { 1, 0.84, 0.55 }, { seed = seed + 1, line = 0 })
    love.graphics.setColor(1, 1, 1, 1)
    Assets.drawKid(rv.portrait, mood, x, y + 4, 126)
end

--- A run in progress or a finished day: where it stands, the marbles, the Jar, the Bug Journal.
function Slots:drawDay(s, r)
    local run = s.run
    local enc = Run.encounter(run)
    local rv = Rivals[enc.rival]
    local x, w = r.x + 28, r.w - 56
    if s.kind == "run" then
        Text.display("FIGHT " .. run.node .. " OF " .. #Run.NODES .. (enc.boss and " - THE BOSS" or ""), x, r.y + 72, 15, C.tealDark, "left", 250)
        Text.display(enc.name, x, r.y + 98, 30, INK, "left", 250)
        Text.body("against " .. rv.name .. ", who bets " .. rv.bet, x, r.y + 140, 14, SOFT, "left", 250)
        drawRival(rv, "neutral", r.x + r.w - 88, r.y + 112, 150 + s.slot * 3)
    else
        local won = s.ended.won
        Text.display("THE DAY IS OVER", x, r.y + 72, 15, C.tealDark, "left", 250)
        Text.display(won and "SUNSET!" or "HOME EARLY", x, r.y + 96, 34, won and C.magenta or C.purple, "left", 250)
        local why = won and ("You beat all " .. #Run.NODES .. " rival kids.") or ("Couldn't cover " .. rv.name .. "'s bet of " .. rv.bet .. ".")
        Text.body(why, x, r.y + 140, 14, SOFT, "left", 250)
        drawRival(rv, won and "sad" or "happy", r.x + r.w - 88, r.y + 112, 150 + s.slot * 3)
    end
    marble(x + 24, r.y + 210, 46)
    Text.display(plural(run.marbles, "MARBLE"), x + 58, r.y + 193, 28, INK, "left", w - 58)
    Text.body("Won " .. run.wins .. "   ·   Lost " .. run.losses .. "   ·   Deck: " .. #run.deck .. " cards", x, r.y + 244, 14, SOFT, "left", w)
    drawJar(run, x, r.y + 282, w, 160 + s.slot * 10)
    Text.body("Bug Journal: " .. count(run.seen) .. " of " .. SPECIES .. " species", x, r.y + 382, 13.5, INK, "left", w)
    local line = when(s.savedAt) and ("Saved " .. when(s.savedAt)) or ""
    if self.app.debug then line = line .. (line ~= "" and "   ·   " or "") .. "seed " .. run.seed end
    Text.body(line, x, r.y + 406, 12.5, SOFT, "left", w)
end

function Slots:drawCard(i)
    local s, r = self.slots[i], cardRect(i)
    local k = self.pop[i]
    if k < 0.02 then return end
    local hovered = not self.dialog and self.hover == "open" .. i
    love.graphics.push()
    love.graphics.translate(r.x + r.w / 2, r.y + r.h / 2 + (hovered and -8 or 0))
    love.graphics.scale(k, k)
    love.graphics.translate(-(r.x + r.w / 2), -(r.y + r.h / 2))
    local fill = s.kind == "ended" and (s.ended.won and FILL.won or FILL.lost) or FILL[s.kind]
    Paper.panel(r.x, r.y, r.w, r.h, { fill = fill, seed = 140 + i, r = 24, rot = (i - 2) * 0.008, tape = s.kind ~= "empty" })
    Text.display("SLOT " .. i, r.x + 28, r.y + 28, 20, C.magentaDark, "left")
    if s.kind == "empty" then
        love.graphics.setColor(1, 1, 1, 0.5)
        Assets.ui:drawFit("icon_jar", r.x + r.w / 2 - 80, r.y + 80, 160, 160)
        Text.display("EMPTY", r.x + r.w / 2, r.y + 268, 40, INK, "center")
        Text.body("A new Saturday at the park: " .. Run.START_MARBLES .. " marbles, a jar of bugs and " .. #Run.NODES .. " rival kids to beat.",
            r.x + 48, r.y + 330, 15, SOFT, "center", r.w - 96)
    elseif s.kind == "damaged" then
        love.graphics.setColor(1, 1, 1, 1)
        Assets.ui:drawFit("fx_exclaim", r.x + r.w / 2 - 50, r.y + 80, 100, 100)
        Text.display("DAMAGED SAVE", r.x + r.w / 2, r.y + 206, 34, C.red, "center")
        Text.body("This file can't be read (" .. tostring(s.why) .. "). Erase it to use the slot again.", r.x + 48, r.y + 262, 15, INK, "center", r.w - 96)
    else
        self:drawDay(s, r)
    end
    local b = self:buttons(i)
    UI.button(b.main, b.label, { hover = hovered, size = 30, seed = 150 + i, fill = s.kind == "damaged" and C.orange or C.teal })
    if b.erase then
        UI.button(b.erase, "ERASE", { hover = not self.dialog and self.hover == "erase" .. i, size = 20, seed = 160 + i, fill = C.purpleLight })
    end
    love.graphics.pop()
end

function Slots:draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(Assets.backdrop.title, 0, 0)
    love.graphics.setColor(0.17, 0.07, 0.22, 0.5)
    love.graphics.rectangle("fill", 0, 0, 1600, 900)
    Text.display("PICK A SAVE SLOT", 800, 40, 52, C.yellow, "center")
    Text.body("Your day at the park is saved after every fight and every purchase at the Swap Shop.", 800, 110, 16, { 1, 1, 1 }, "center", nil, 2)
    if self.app.debug then Text.body("DEBUG: new games ask for a seed", 1584, 14, 13, C.yellow, "right", nil, 2) end
    for i = 1, Saves.COUNT do self:drawCard(i) end
    UI.button(BACK, "BACK", { hover = not self.dialog and self.hover == "back", size = 30, seed = 170, fill = C.purpleLight })
    Text.body("Click a slot or press 1, 2 or 3.   Esc goes back.", 800, 866, 13, { 1, 1, 1 }, "center", nil, 2)
end

function Slots:dialogButtons()
    local P = DIALOG[self.dialog.kind]
    local y = P.y + P.h - 112
    local left = { x = P.x + 70, y = y, w = 300, h = 80 }
    local right = { x = P.x + P.w - 370, y = y, w = 300, h = 80 }
    if self.dialog.kind == "erase" then
        return { { kind = "no", label = "KEEP IT", fill = C.teal, r = left }, { kind = "yes", label = "ERASE", fill = C.orange, r = right } }
    end
    return { { kind = "start", label = "START!", fill = C.teal, r = left }, { kind = "cancel", label = "CANCEL", fill = C.cream2, color = INK, r = right } }
end

function Slots:drawSeedField(d, x, y, w, h)
    Paper.panel(x, y, w, h, { fill = { 1, 1, 1 }, seed = 181, r = 14, line = 3, shadow = false })
    local tx, caret = x + 28, x + 26
    if d.text == "" then
        Text.display("RANDOM", tx, y + 24, 38, { 0.66, 0.62, 0.72 }, "left")
    else
        Text.display(d.text, tx, y + 22, 42, INK, "left")
        caret = tx + Text.displayWidth(d.text, 42) + 6
    end
    if math.floor(self.time * 2) % 2 == 0 then
        love.graphics.setColor(INK)
        love.graphics.rectangle("fill", caret, y + 18, 5, 50)
    end
end

function Slots:drawOverlay()
    local d = self.dialog
    if not d then return end
    love.graphics.setColor(0.17, 0.07, 0.22, 0.6)
    love.graphics.rectangle("fill", 0, 0, 1600, 900)
    local P = DIALOG[d.kind]
    local x, w = P.x + 70, P.w - 140
    local s = self.slots[d.slot]
    if d.kind == "erase" then
        Paper.panel(P.x, P.y, P.w, P.h, { fill = { 0.9, 0.85, 1 }, seed = 180, r = 26, rot = -0.005, tape = true })
        Text.display("ERASE SLOT " .. d.slot .. "?", P.x + P.w / 2, P.y + 50, 44, C.purple, "center")
        local what = s.kind == "run" and "This day at the park will be gone for good: its marbles, its Jar and its deck."
            or s.kind == "ended" and "The record of this finished day will be gone for good."
            or "The damaged file will be deleted."
        Text.body(what, x, P.y + 130, 19, INK, "center", w)
    else
        Paper.panel(P.x, P.y, P.w, P.h, { fill = C.cream, seed = 182, r = 26, rot = -0.004, tape = true })
        Text.display("NEW GAME IN SLOT " .. d.slot, P.x + P.w / 2, P.y + 36, 40, C.magenta, "center")
        Text.display("SEED", x, P.y + 100, 18, C.tealDark, "left")
        Text.body("debug mode", x + w, P.y + 102, 13, C.magentaDark, "right")
        self:drawSeedField(d, x, P.y + 128, w, 86)
        Text.body("Type up to " .. SEED_DIGITS .. " digits, or leave it empty for a random seed. Same seed, same shuffles.", x, P.y + 228, 14.5, SOFT, "left", w)
        if s.kind == "ended" then Text.body("The finished day in this slot will be replaced.", x, P.y + 254, 14.5, C.magentaDark, "left", w) end
    end
    for _, b in ipairs(self:dialogButtons()) do
        UI.button(b.r, b.label, { hover = self.hover == b.kind, size = 30, seed = 190 + #b.kind, fill = b.fill, color = b.color })
    end
end

-- ───────────────────────── input ─────────────────────────
function Slots:hitTest(x, y)
    if self.dialog then
        for _, b in ipairs(self:dialogButtons()) do if UI.inside(b.r, x, y) then return b.kind end end
        return nil
    end
    if UI.inside(BACK, x, y) then return "back" end
    for i = 1, Saves.COUNT do
        local b = self:buttons(i)
        if b.erase and UI.inside(b.erase, x, y) then return "erase" .. i end
        if UI.inside(cardRect(i), x, y) then return "open" .. i end
    end
    return nil
end

function Slots:mousemoved(x, y) self.hover = self:hitTest(x, y) end

function Slots:mousepressed(x, y, b)
    if self.dialog and b ~= 1 then self:closeDialog(); return end
    if b ~= 1 then return end
    local h = self:hitTest(x, y)
    if not h then return end
    if h == "start" then self:startSeeded()
    elseif h == "cancel" or h == "no" then self:closeDialog()
    elseif h == "yes" then self:confirmErase()
    elseif h == "back" then self:back()
    else
        local what, i = h:match("^(%a+)(%d)$")
        if what == "erase" then self:askErase(tonumber(i)) else self:open(tonumber(i)) end
    end
    self.hover = self:hitTest(x, y)
end

function Slots:textinput(t)
    local d = self.dialog
    if d and d.kind == "seed" and d.frame ~= self.frame then self:typeDigits(t) end
end

function Slots:keypressed(key)
    local d = self.dialog
    if d and d.kind == "seed" then
        if key == "backspace" then d.text = d.text:sub(1, -2)
        elseif key == "return" or key == "kpenter" then self:startSeeded()
        elseif key == "escape" then self:closeDialog()
        elseif key == "v" and love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui") then self:typeDigits(love.system.getClipboardText() or "")
        end
        return
    end
    if d then
        if key == "escape" or key == "n" then self:closeDialog()
        elseif key == "return" or key == "kpenter" or key == "y" then self:confirmErase() end
        return
    end
    local n = tonumber(key:match("^kp(%d)$") or key)
    if n and self.slots[n] then self:open(n)
    elseif key == "escape" or key == "backspace" then self:back()
    elseif (key == "return" or key == "space") and self.hover and self.hover:match("^open") then self:open(tonumber(self.hover:match("%d")))
    end
end

return Slots
