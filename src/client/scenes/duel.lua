-- The duel (GDD §8.5): the screen between the rounds of a match against a rival kid. Both stacks, what this round is
-- worth (the poorer side is ALL IN), the three rounds and how they went, who is napping on both sides, the rival's mood
-- and house rule. When it's over: how it ended, and what a broke kid offers from their pockets.
-- The rules are sim/duel.lua; each round is played in the fight scene.

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
local PD = require("data.park")
local Rivals = require("data.rivals")
local Bugs = require("data.bugs")
local Cards = require("data.cards")
local RuleData = require("data.rules")

local C = Paper.C
local INK = Text.INK
local SOFT = UI.SOFT

local Scene = {}
Scene.__index = Scene

local ACT_TINT = { { 1, 1, 1, 0 }, { 1, 0.78, 0.35, 0.13 }, { 0.42, 0.16, 0.5, 0.3 } }
local BOARD_NAME = { sandbox = "in the sandbox", lawn = "on the lawn", stump = "on the old stump" }

local OVER = {
    broke = { title = "BROKE!", color = C.magenta, fill = { 1, 0.95, 0.7 } },
    bell = { title = "THE BELL RINGS", color = C.tealDark, fill = { 1, 0.95, 0.7 } },
    sister = { title = "BIG SISTER!", color = C.purple, fill = { 0.9, 0.85, 1 } },
    home = { title = "OUT OF MARBLES", color = C.purple, fill = { 0.9, 0.85, 1 } },
}

local function ruleName(id) return RuleData[id] and RuleData[id].name or id end

function Scene.new(app, params)
    local self = setmetatable({ app = app, time = 0, hits = {}, hover = nil, pop = 0 }, Scene)
    self.run = params.run or app.run
    app.run = self.run
    self.rec = params.rec
    self.mouse = { x = app.mouse.x, y = app.mouse.y }
    return self
end

function Scene:duel() return self.run.duel end

function Scene:enter()
    Audio.music("title")
    Tween.to(self, { pop = 1 }, 0.4, "outBack")
    local d = self:duel()
    if d and d.over then
        Audio.play((d.over.why == "broke" or d.over.why == "bell") and "win" or "lose", 0.7)
        if d.over.why == "broke" then for i = 1, 8 do Fx.sparkle(200 * i, 220, 3, 60) end end
    elseif self.rec then
        Audio.play(self.rec.winner == "kid" and "coin" or "ui_back")
    end
end

function Scene:update(dt)
    self.time = self.time + dt
    if not self:duel() and not self.routed and not self.app.trans then
        -- nothing to show (a save from after the duel): go where the run is
        self.routed = true
        Flow.go(self.app, self.run)
    end
end

function Scene:button(r, key, label, o, data)
    o = o or {}
    o.hover = self.hover == key
    UI.button(r, label, o)
    if not o.disabled or o.tip then UI.hit(self.hits, r, key, { disabled = o.disabled, tip = o.tip, data = data }) end
end

--- The rival's face: Cocky (won the last round) smiles, Angry (lost it) frowns.
function Scene:rivalMood()
    local d = self:duel()
    if d.over then return (d.over.why == "broke") and "sad" or (d.over.why == "home" or d.over.why == "sister") and "happy" or "neutral" end
    return d.mood == "cocky" and "happy" or d.mood == "angry" and "sad" or "neutral"
end

function Scene:rivalLine()
    local d = self:duel()
    local rv = Rivals[d.rival]
    local last = d.history[#d.history]
    if not last then return rv.line.start end
    if last.winner == "kid" then return rv.line.lose end
    if last.winner == "rival" then return rv.line.win end
    return rv.line.start
end

-- ───────────────────────── the two sides ─────────────────────────

function Scene:drawYou()
    local run = self.run
    local d = self:duel()
    local P = { x = 24, y = 140, w = 400, h = 606 }
    Paper.panel(P.x, P.y, P.w, P.h, { fill = { 0.86, 0.96, 0.95 }, seed = 901, r = 22, rot = -0.004 })
    Text.display("YOU", P.x + 24, P.y + 20, 34, C.tealDark, "left")
    UI.marble(P.x + 62, P.y + 112, 66)
    Text.display(tostring(run.marbles), P.x + 104, P.y + 78, 64, INK, "left")
    Text.body("marbles", P.x + 106, P.y + 148, 14, SOFT, "left")
    local allIn = not d.over and Duel.allIn(run)
    if allIn == "kid" or allIn == "both" then UI.tag("ALL IN!", P.x + P.w - 30, P.y + 24, 18, C.red, { align = "right", seed = 902, rot = 0.06 }) end
    Text.body(run.bigSister and "Big Sister can still bail you out once." or "Big Sister already helped you today.", P.x + 24, P.y + 178, 13, run.bigSister and SOFT or C.magentaDark, "left", P.w - 48)
    Text.display("YOUR BUGS", P.x + 24, P.y + 222, 15, C.tealDark, "left")
    local up, naps = 0, 0
    for i, e in ipairs(run.jar) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local cx, cy = P.x + 74 + col * 126, P.y + 290 + row * 112
        UI.bugDisc(e.species, cx, cy, 38, { seed = 910 + i, alpha = e.nap and 0.5 or 1, ring = e.nap and { 0.62, 0.6, 0.7 } or C.teal })
        Text.display(Bugs[e.species].short, cx - 60, cy + 44, 12, INK, "center", 120)
        if e.nap then UI.icon("fx_zzz", cx + 30, cy - 30, 34); naps = naps + 1 else up = up + 1 end
        if e.big and not e.nap then UI.tag("BIG", cx + 14, cy - 44, 9, C.green, { seed = 915 + i }) end
        UI.hit(self.hits, { x = cx - 40, y = cy - 40, w = 80, h = 80 }, "tip", { tip = { Bugs[e.species].name, e.nap and "Napping: it sits out this round, then wakes up." or (Bugs[e.species].role .. ". " .. Bugs[e.species].rules.action) } })
    end
    local note = naps > 0 and (naps .. " napping: they sit this round out.") or "Everybody is awake."
    Text.body(note, P.x + 24, P.y + P.h - 40, 13, naps > 0 and C.purple or SOFT, "left", P.w - 48)
end

--- Who the rival puts on the board this round: the first `field` roster bugs that aren't napping (as in sim/duel.lua).
local function fielded(d)
    local rv = Rivals[d.rival]
    local field = (rv.field or 4) + ((d.leader and rv.house and rv.house.id == "double") and 1 or 0)
    local on, n = {}, 0
    for _, e in ipairs(d.roster) do
        if not e.nap and n < field then on[e.uid] = true; n = n + 1 end
    end
    return on
end

function Scene:drawRival()
    local run = self.run
    local d = self:duel()
    local rv = Rivals[d.rival]
    local P = { x = 1176, y = 140, w = 400, h = 606 }
    Paper.panel(P.x, P.y, P.w, P.h, { fill = { 1, 0.9, 0.93 }, seed = 920, r = 22, rot = 0.004 })
    UI.kidDisc(rv.portrait, self:rivalMood(), P.x + 100, P.y + 104, 78, 921)
    Text.display(rv.name, P.x + 190, P.y + 26, 22, INK, "left", P.w - 206)
    local stack = run.stacks[d.rival] or 0
    UI.marble(P.x + 208, P.y + 96, 40)
    Text.display(tostring(stack), P.x + 236, P.y + 72, 46, INK, "left")
    Text.body("marbles", P.x + 238, P.y + 124, 13, SOFT, "left")
    local allIn = not d.over and Duel.allIn(run)
    if allIn == "rival" or allIn == "both" then UI.tag("ALL IN!", P.x + P.w - 24, P.y + 62, 16, C.red, { align = "right", seed = 922, rot = -0.06 }) end
    -- what they say
    Paper.panel(P.x + 20, P.y + 192, P.w - 40, 62, { fill = C.cream, seed = 923, r = 14, line = 3, shadow = false })
    Text.body('"' .. self:rivalLine() .. '"', P.x + 34, P.y + 202, 14, C.magentaDark, "left", P.w - 68)
    -- mood
    local my = P.y + 270
    if not d.over and d.mood ~= "neutral" then
        local angry = d.mood == "angry"
        UI.tag(angry and "ANGRY" or "COCKY", P.x + 24, my, 12, angry and C.red or C.orange, { seed = 924 })
        Text.body(rv.sig.name .. (angry and " comes 1 tick sooner." or " comes 1 tick later."), P.x + 130, my + 2, 12.5, INK, "left", P.w - 150)
        my = my + 36
    end
    Text.display("THEIR BUGS", P.x + 24, my + 6, 15, C.magentaDark, "left")
    local on = fielded(d)
    for i, e in ipairs(d.roster) do
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        local cx, cy = P.x + 62 + col * 92, my + 74 + row * 96
        local playing = on[e.uid] and not d.over
        UI.bugDisc(e.species, cx, cy, 30, { ring = e.nap and { 0.62, 0.6, 0.7 } or C.magenta, seed = 930 + i, alpha = (e.nap or not playing) and 0.55 or 1 })
        Text.display(Bugs[e.species].short, cx - 46, cy + 34, 10.5, INK, "center", 92)
        if e.nap then UI.icon("fx_zzz", cx + 24, cy - 24, 28) end
        local status = e.nap and "Napping: it sits this round out." or playing and "On the board this round." or "Waits in their jar this round."
        UI.hit(self.hits, { x = cx - 32, y = cy - 32, w = 64, h = 64 }, "tip", { tip = { Bugs[e.species].name, status .. " " .. Bugs[e.species].rules.action } })
    end
    Text.body("Bright ones play this round.", P.x + 24, P.y + P.h - 40, 12.5, SOFT, "left", P.w - 48)
end

-- ───────────────────────── the middle ─────────────────────────

function Scene:drawHeader()
    local run = self.run
    local d = self:duel()
    local rv = Rivals[d.rival]
    local P = { x = 440, y = 14, w = 720, h = 112 }
    Paper.panel(P.x, P.y, P.w, P.h, { fill = { 1, 0.95, 0.7 }, seed = 940, r = 22, rot = -0.003, tape = true })
    local what = d.leader and "THE GANG LEADER" or "A DUEL"
    Text.display(what .. "  ·  " .. Run.actDef(run).name .. "  ·  " .. PD.zones[run.zone].short, 800, P.y + 16, 13, C.magentaDark, "center")
    Text.display("YOU  VS  " .. rv.name, P.x + 20, P.y + 40, 34, INK, "center", P.w - 40)
    local sub = d.over and "THE DUEL IS OVER" or ("ROUND " .. d.round .. " OF 3")
    Text.display(sub, 800, P.y + 84, 15, C.tealDark, "center")
end

function Scene:drawStake()
    local run = self.run
    local d = self:duel()
    local P = { x = 440, y = 140, w = 720, h = 148 }
    Paper.panel(P.x, P.y, P.w, P.h, { fill = C.cream, seed = 941, r = 20, rot = 0.003 })
    if d.over then
        local s = d.start
        local delta = run.marbles - s.kid
        Text.display("YOU CAME WITH " .. UI.plural(s.kid, "MARBLE"), 800, P.y + 22, 22, INK, "center")
        Text.display((delta >= 0 and "+" or "") .. delta .. "  ·  NOW " .. run.marbles, 800, P.y + 62, 34, delta >= 0 and C.tealDark or C.magentaDark, "center")
        return
    end
    if Duel.rule(run) == "showdown" then
        Text.display("THE SHOWDOWN: NO BET", 800, P.y + 18, 28, C.magenta, "center")
        Text.body("Every bite, sting, ram or strike moves 1 marble from the owner of the bug that got hit to the owner of the attacker. It ends when a side has no bugs left, somebody is broke, or the Sun clock runs out. Then the duel is over.", P.x + 30, P.y + 56, 13.5, INK, "center", P.w - 60)
        return
    end
    local stake = Duel.stake(run)
    UI.marble(P.x + 150, P.y + 52, 44)
    Text.display("YOU BOTH BET " .. stake, P.x + 184, P.y + 26, 34, INK, "left")
    Text.body("Winner takes all " .. (2 * stake) .. ". A draw gives the bets back.", P.x + 184, P.y + 72, 14, SOFT, "left", P.w - 220)
    local allIn = Duel.allIn(run)
    local who = allIn == "kid" and "You have less: you're ALL IN. Lose this round and you're broke."
        or allIn == "rival" and (Rivals[d.rival].name .. " has less: they're ALL IN. Win this round and they're broke!")
        or "Same stacks: you're both ALL IN. Winner takes everything."
    Text.body(who, P.x + 30, P.y + 106, 13.5, allIn == "kid" and C.red or C.tealDark, "center", P.w - 60)
    if Duel.house(run) == "keeps" then Text.body("For keeps: every hit also moves a marble.", P.x + 30, P.y + 128, 12, C.magentaDark, "center", P.w - 60) end
end

--- What we know about round i: { rule, title, sub, state = "done" | "now" | "later", rec }
function Scene:roundInfo(i)
    local run = self.run
    local d = self:duel()
    local zone = PD.zones[run.zone]
    local rec = d.history[i]
    local info = { rec = rec }
    if i == 3 then
        info.rule = "showdown"
        info.sub = BOARD_NAME[PD.boards[d.board1].arena] or ""
    elseif rec then
        info.rule = rec.rule
        info.sub = BOARD_NAME[PD.boards[zone.rules[rec.rule]].arena] or ""
    elseif i == d.round and not d.pick then
        info.rule = d.rule
        info.sub = BOARD_NAME[PD.boards[zone.rules[d.rule]].arena] or ""
    elseif i == 2 then
        info.title = d.pick and "YOU PICK!" or "LOSER'S CHOICE"
        info.sub = "Who loses round 1 picks the game."
    end
    info.state = rec and "done" or (i == d.round and not d.over) and "now" or "later"
    return info
end

function Scene:drawLadder()
    local d = self:duel()
    local y = 304
    for i = 1, 3 do
        local info = self:roundInfo(i)
        local r = { x = 440 + (i - 1) * 246, y = y, w = 228, h = 252 }
        local now = info.state == "now"
        local fill = info.state == "done" and { 0.93, 0.92, 0.95 } or now and { 1, 0.97, 0.82 } or C.cream
        Paper.panel(r.x, r.y - (now and 8 or 0), r.w, r.h, { fill = fill, seed = 950 + i, r = 18, rot = (i - 2) * 0.012, tape = now })
        local ry = r.y - (now and 8 or 0)
        Text.display("ROUND " .. i, r.x + r.w / 2, ry + 18, 18, i == 3 and C.magenta or C.tealDark, "center")
        local title = info.title or ruleName(info.rule)
        Text.display(title, r.x + 14, ry + 54, 20, INK, "center", r.w - 28)
        if info.rule and RuleData[info.rule] then
            Text.body(RuleData[info.rule].short, r.x + 16, ry + 86, 12, INK, "center", r.w - 32)
        end
        Text.body(info.sub or "", r.x + 16, ry + 146, 11.5, SOFT, "center", r.w - 32)
        if info.rec then
            local rec = info.rec
            local won, lost = rec.winner == "kid", rec.winner == "rival"
            local stamp = won and "WON" or lost and "LOST" or "DRAW"
            local col = won and C.green or lost and C.red or C.purpleLight
            love.graphics.push()
            love.graphics.translate(r.x + r.w / 2, ry + 202)
            love.graphics.rotate(-0.12)
            Paper.panel(-80, -26, 160, 52, { fill = col, seed = 960 + i, r = 12, line = 3 })
            Text.display(stamp, 0, -12, 24, { 1, 1, 1 }, "center")
            love.graphics.pop()
            local delta = rec.delta or 0
            Text.display((delta >= 0 and "+" or "") .. delta, r.x + r.w - 20, ry + 226, 16, delta >= 0 and C.tealDark or C.magentaDark, "right")
            if rec.why == "forfeit" then Text.body("forfeit", r.x + 20, ry + 228, 11, SOFT, "left") end
        elseif now then
            UI.tag("NEXT!", r.x + r.w / 2, ry + 188, 16, C.magenta, { align = "center", seed = 965 + i })
        end
        if info.rule and RuleData[info.rule] then
            UI.hit(self.hits, r, "tip", { tip = { RuleData[info.rule].name, RuleData[info.rule].long } })
        end
    end
end

function Scene:drawNews()
    local run = self.run
    local d = self:duel()
    local y = 574
    local rv = Rivals[d.rival]
    if d.leader and rv.house then
        Paper.panel(440, y, 720, 64, { fill = { 1, 0.9, 0.95 }, seed = 970, r = 14, line = 3, rot = -0.002 })
        Text.display("HOUSE RULE", 460, y + 10, 12, C.magentaDark, "left")
        Text.body('"' .. rv.house.name .. '"  ' .. rv.house.text, 460, y + 30, 13, INK, "left", 680)
        y = y + 74
    end
    local rec = self.rec
    if rec and not d.over then
        local parts = {}
        local who = rec.winner == "kid" and "You won round " .. rec.round or rec.winner == "rival" and "You lost round " .. rec.round or "Round " .. rec.round .. " was a draw"
        parts[#parts + 1] = who .. " (" .. ((rec.delta or 0) >= 0 and "+" or "") .. (rec.delta or 0) .. ")."
        local function names(list)
            local out = {}
            for i, sp in ipairs(list or {}) do out[i] = Bugs[sp].short end
            return table.concat(out, ", ")
        end
        if #(rec.napped or {}) > 0 then parts[#parts + 1] = "Napping now: your " .. names(rec.napped) .. "." end
        if #(rec.rnapped or {}) > 0 then parts[#parts + 1] = "Theirs: " .. names(rec.rnapped) .. "." end
        if #(rec.woke or {}) > 0 then parts[#parts + 1] = "Awake again: " .. names(rec.woke) .. "." end
        Text.body(table.concat(parts, "  "), 460, y + 4, 14, INK, "left", 680)
    end
end

function Scene:drawActions()
    local run = self.run
    local d = self:duel()
    if d.over or d.pick then return end
    local side = Duel.forfeitSide(run)
    local r = { x = 520, y = 760, w = 560, h = 104 }
    if side == "kid" then
        self:button(r, "forfeit", "FORFEIT THE ROUND", { size = 30, fill = C.orange, seed = 980 })
        Text.body("Every bug of yours is napping: you can't field anybody.", 800, r.y + r.h + 8, 13, C.red, "center")
    elseif side == "rival" then
        self:button(r, "forfeit", "THEY FORFEIT!", { size = 32, fill = C.green, seed = 981 })
        Text.body("Every bug of theirs is napping: the round is yours.", 800, r.y + r.h + 8, 13, C.tealDark, "center")
    else
        self:button(r, "play", "PLAY ROUND " .. d.round .. "!", { size = 40, fill = C.teal, seed = 982 })
        Text.body("Esc: back to the title (the duel waits for you).", 800, r.y + r.h + 8, 12, { 1, 1, 1 }, "center", nil, 2)
    end
end

-- ───────────────────────── overlays ─────────────────────────

function Scene:drawPick()
    local run = self.run
    local d = self:duel()
    UI.veil(0.55)
    local P = { x = 220, y = 120, w = 1160, h = 660 }
    Paper.panel(P.x, P.y, P.w, P.h, { fill = { 1, 0.95, 0.7 }, seed = 990, r = 26, rot = -0.004, tape = true })
    Text.display("LOSER'S CHOICE", 800, P.y + 30, 44, C.magenta, "center")
    Text.body("You lost round 1, so you pick the game for round 2. Pick the one your bugs are good at.", P.x + 80, P.y + 90, 17, INK, "center", P.w - 160)
    local zone = PD.zones[run.zone]
    local n = #d.pick
    local w = 440
    local x0 = 800 - (n * w + (n - 1) * 40) / 2
    for i, id in ipairs(d.pick) do
        local def = RuleData[id]
        local r = { x = x0 + (i - 1) * (w + 40), y = P.y + 150, w = w, h = 450 }
        local key = "rule" .. i
        local hov = self.hover == key
        Paper.panel(r.x, r.y + (hov and -6 or 0), r.w, r.h, { fill = hov and { 1, 1, 0.94 } or C.cream, seed = 991 + i, r = 20, rot = (i == 1) and -0.008 or 0.008 })
        local y = r.y + (hov and -6 or 0)
        Text.display(def.name, r.x + 20, y + 24, 28, INK, "center", r.w - 40)
        Text.body(BOARD_NAME[PD.boards[zone.rules[id]].arena] or "", r.x + r.w / 2, y + 66, 14, SOFT, "center")
        Text.body(def.long, r.x + 28, y + 100, 14, INK, "left", r.w - 56)
        Text.body("Good for: " .. (def.favours or "anybody"), r.x + 28, y + r.h - 130, 14, C.tealDark, "left", r.w - 56)
        self:button({ x = r.x + 40, y = y + r.h - 96, w = r.w - 80, h = 70 }, key, "PLAY THIS", { size = 28, fill = C.teal, seed = 995 + i }, { rule = id })
    end
end

function Scene:drawOver()
    local run = self.run
    local d = self:duel()
    local rv = Rivals[d.rival]
    local why = d.over.why
    local look = OVER[why] or OVER.bell
    UI.veil(0.5)
    local P = { x = 300, y = 90, w = 1000, h = 720 }
    Paper.panel(P.x, P.y, P.w, P.h, { fill = look.fill, seed = 1000, r = 28, rot = -0.004, tape = true })
    UI.kidDisc(rv.portrait, self:rivalMood(), P.x + 130, P.y + 150, 92, 1001)
    local title = why == "broke" and (rv.name .. (rv.plural and " ARE BROKE!" or " IS BROKE!")) or look.title
    Text.display(title, P.x + 250, P.y + 44, 38, look.color, "left", P.w - 290)
    local text
    if why == "broke" then
        text = "You won every last marble. " .. (d.leader and "This corner of the park is yours!" or "They'll have to go home early.")
    elseif why == "bell" then
        local delta = run.marbles - d.start.kid
        text = "After the Showdown the duel is over, whoever is ahead. " .. (delta > 0 and "You come out ahead!" or delta < 0 and "They come out ahead." or "Nobody won anything.")
        if d.leader then text = text .. " You got past the Gang leader." end
    elseif why == "sister" then
        text = '"Mom says it\'s lunchtime!" Big Sister drags you away from the duel and slips you ' .. PD.BIG_SISTER .. " marbles. She won't do it again today."
        if d.leader then text = text .. " This part of the day is over, without a prize." end
    else
        text = "Nobody plays with a kid with empty pockets. Time to go home."
    end
    Text.body(text, P.x + 250, P.y + 100, 17, INK, "left", P.w - 290)
    Text.body('"' .. self:rivalLine() .. '"', P.x + 250, P.y + 190, 16, C.magentaDark, "left", P.w - 290)
    local delta = run.marbles - d.start.kid
    UI.marble(P.x + 80, P.y + 296, 44)
    Text.display(UI.plural(run.marbles, "MARBLE") .. "  (" .. (delta >= 0 and "+" or "") .. delta .. ")", P.x + 112, P.y + 276, 30, delta >= 0 and C.tealDark or C.magentaDark, "left")
    if d.over.album then Text.body("+" .. d.over.album .. " from your Sticker Album.", P.x + 112, P.y + 318, 14, C.tealDark, "left") end
    if d.offer and #d.offer > 0 then
        Text.display("FROM THEIR POCKETS", P.x + 60, P.y + 358, 16, C.magentaDark, "left")
        Text.body(d.took and "Deal! Pleasure doing business." or "Before going home, they offer you one thing, for some of their marbles back. Take one, or none.", P.x + 60, P.y + 382, 14, SOFT, "left", P.w - 120)
        for i, o in ipairs(d.offer) do
            local r = { x = P.x + 60 + (i - 1) * 300, y = P.y + 420, w = 280, h = 180 }
            local took = d.took == i
            Paper.panel(r.x, r.y, r.w, r.h, { fill = took and C.yellow or C.cream, seed = 1010 + i, r = 16, line = 3 })
            if o.kind == "card" then
                love.graphics.push()
                love.graphics.translate(r.x + 64, r.y + 90)
                love.graphics.scale(0.72, 0.72)
                HandView.drawCard(o.id)
                love.graphics.pop()
                Text.display(Cards[o.id].name, r.x + 130, r.y + 22, 15, INK, "left", r.w - 140)
                Text.body("A card for your deck.", r.x + 130, r.y + 48, 11.5, SOFT, "left", r.w - 140)
            else
                UI.bugDisc(o.id, r.x + 64, r.y + 80, 48, { ring = C.magenta, seed = 1015 + i })
                Text.display(Bugs[o.id].short, r.x + 130, r.y + 22, 16, INK, "left", r.w - 140)
                Text.body("A bug for your Jar.", r.x + 130, r.y + 48, 11.5, SOFT, "left", r.w - 140)
            end
            local ok, why2 = true, nil
            if d.took then ok = false end
            if o.kind == "bug" and #run.jar >= run.jarSlots then ok, why2 = false, "Your Jar is full." end
            if run.marbles - o.price < 1 then ok, why2 = false, "You'd be out of marbles." end
            UI.marble(r.x + 146, r.y + 92, 24)
            Text.display(tostring(o.price), r.x + 164, r.y + 80, 22, INK, "left")
            if not took then
                self:button({ x = r.x + 130, y = r.y + 116, w = r.w - 146, h = 50 }, "offer" .. i, "TAKE IT", { size = 20, fill = C.teal, seed = 1020 + i, disabled = not ok, tip = why2 and { "NOT NOW", why2 } or nil })
            else
                Text.display("YOURS!", r.x + 200, r.y + 130, 20, C.tealDark, "center")
            end
        end
    end
    local label = why == "home" and "GO HOME" or (d.leader and why ~= "sister") and "THE PARK IS YOURS!" or "BACK TO THE PARK"
    self:button({ x = 800 - 220, y = P.y + P.h - 100, w = 440, h = 78 }, "leave", label, { size = 28, fill = why == "home" and C.purpleLight or C.teal, seed = 1030 })
end

-- ───────────────────────── draw & input ─────────────────────────

function Scene:draw()
    self.hits = {}
    local run = self.run
    local d = self:duel()
    love.graphics.setColor(1, 1, 1, 1)
    local z = run.zone and PD.zones[run.zone]
    love.graphics.draw(Assets.backdrop[z and z.backdrop or "sandbox"], 0, 0)
    local t = ACT_TINT[run.act] or ACT_TINT[1]
    if t[4] > 0 then love.graphics.setColor(t); love.graphics.rectangle("fill", 0, 0, 1600, 900) end
    UI.veil(0.3)
    if not d then return end
    self:drawHeader()
    self:drawYou()
    self:drawRival()
    self:drawStake()
    self:drawLadder()
    self:drawNews()
    self:drawActions()
    if d.over then
        self.hits = {}
        self:drawOver()
    elseif d.pick then
        self.hits = {}
        self:drawPick()
    end
    local h = UI.hitAt(self.hits, self.mouse.x, self.mouse.y)
    self.hover = h and h.key or nil
    if h and h.data and h.data.tip then UI.tooltip(self.mouse.x, self.mouse.y, h.data.tip[1], h.data.tip[2]) end
end

function Scene:press(key, data)
    local run = self.run
    local action, n = key:match("^(%a+)(%d*)$")
    n = tonumber(n)
    if action == "play" then
        Audio.play("ui_click")
        self.app.switch("fight", { run = run, mode = "duel" })
    elseif action == "forfeit" then
        local rec = Duel.forfeit(run)
        if rec then
            Saves.store(run)
            Audio.play(rec.winner == "kid" and "coin" or "lose", 0.7)
            self.rec = rec
            if run.duel and run.duel.over then self:enter() end
        end
    elseif action == "rule" then
        if Duel.pickRule(run, data.rule) then
            Saves.store(run)
            Audio.play("ui_click")
        end
    elseif action == "offer" then
        local ok = Duel.takeOffer(run, n)
        if ok then
            Saves.store(run)
            Audio.play("coin")
            Fx.sparkle(800, 520, 10, 100)
        else
            Audio.play("block")
        end
    elseif action == "leave" then
        Audio.play("ui_click")
        Duel.leave(run)
        local note
        if run.phase == "free" and run.window == 2 then
            note = { title = "THE ICE-CREAM VAN IS HERE!", text = "Ding-ding! It stays until you face the Gang leader: cards, bugs and pocket items, for marbles. The park has calmed down again, too." }
        end
        Flow.go(self.app, run, { note = note })
    end
end

function Scene:mousemoved(x, y) self.mouse.x, self.mouse.y = x, y end

function Scene:mousepressed(x, y, b)
    self.mouse.x, self.mouse.y = x, y
    if b ~= 1 then return end
    local h = UI.hitAt(self.hits, x, y)
    if not h or h.key == "tip" then return end
    if h.data and h.data.disabled then Audio.play("block"); return end
    self:press(h.key, (h.data and h.data.data) or {})
end

function Scene:keypressed(key)
    local d = self:duel()
    if not d then return end
    if key == "escape" then
        Audio.play("ui_back")
        self.app.switch("title")
    elseif (key == "return" or key == "space") and not d.over and not d.pick and not Duel.forfeitSide(self.run) then
        self:press("play", {})
    end
end

return Scene
