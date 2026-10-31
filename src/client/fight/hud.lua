-- The fight screen's chrome: timeline, sun clock, rival and rule panels, inspector, jar and buttons.
-- Every draw function registers clickable rectangles through `add(kind, x, y, w, h, data)`.

local Assets = require("client.assets")
local Paper = require("client.paper")
local Text = require("client.text")
local UI = require("client.ui")
local L = require("client.fight.layout")
local Q = require("sim.query")
local Bugs = require("data.bugs")
local Cards = require("data.cards")
local Rivals = require("data.rivals")
local Rules = require("data.rules")
local PD = require("data.park")
local Kid = require("sim.kid")

local Hud = {}
local C = Paper.C
local INK = Text.INK

local function icon(name, x, y, size)
    local w, h = Assets.ui:size(name)
    love.graphics.draw(Assets.ui.image, Assets.ui.quads[name], x, y, 0, size / math.max(w, h), size / math.max(w, h), w / 2, h / 2)
end

local function wrapBody(str, x, y, size, limit, color, align)
    Text.body(str, x, y, size, color or INK, align or "left", limit)
    return Text.bodyHeight(str, size, limit)
end

-- ───────────────────────── timeline ─────────────────────────
-- Columns by timer: READY ambushers first, then 0 (framed: they act on the next tick), then 1, 2, 3...
function Hud.timeline(scene, add, time)
    local P = L.timeline
    Paper.panel(P.x, P.y, P.w, P.h, { fill = C.cream, seed = 3, r = 16, tape = true })
    local s = scene.state
    local items = {}
    for _, b in ipairs(s.bugs) do
        local a = scene.actorById[b.id]
        if not (a and a.gone) then
            local ready = a and a.ready or b.ready
            local t = ready and -1 or math.max(0, a and a.timer or b.timer)
            items[#items + 1] = { kind = "bug", id = b.id, species = b.species, side = b.side, t = t, key = Q.orderKey(b), ready = ready }
        end
    end
    if s.rival then items[#items + 1] = { kind = "rival", t = math.max(0, scene.disp.rivalTimer or s.rival.timer), key = 900000 } end
    table.sort(items, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.key < b.key end)

    Text.display("WHO ACTS", P.x + 16, P.y + 12, 12, { 0.45, 0.25, 0.55 })
    Text.display("WHEN", P.x + 16, P.y + 30, 12, { 0.45, 0.25, 0.55 })
    Text.body("order: you first", P.x + 14, P.y + 54, 10.5, { 0.4, 0.28, 0.5 })

    local x = P.x + 124
    local r = 20
    local i = 1
    while i <= #items do
        local t = items[i].t
        local j = i
        while j <= #items and items[j].t == t do j = j + 1 end
        local n = j - i
        local colW = math.max(t < 0 and 104 or t == 0 and 132 or 60, 12 + n * 46)
        if x + colW > P.x + P.w - 10 then break end
        -- column header
        if t == 0 then
            love.graphics.setLineWidth(4)
            love.graphics.setColor(C.yellow[1], C.yellow[2], C.yellow[3], 0.9)
            love.graphics.rectangle("line", x - 6, P.y + 6, colW, P.h - 12, 12, 12)
            love.graphics.setColor(C.yellow[1], C.yellow[2], C.yellow[3], 0.16)
            love.graphics.rectangle("fill", x - 6, P.y + 6, colW, P.h - 12, 12, 12)
        end
        love.graphics.setColor(1, 1, 1, 1)
        if t < 0 then
            icon("icon_eye", x + 10, P.y + 17, 22)
            Text.display("READY", x + 24, P.y + 10, 13, { 0.45, 0.25, 0.55 }, "left")
        else
            icon("icon_hourglass", x + 10, P.y + 17, 22)
            Text.display(tostring(t), x + 24, P.y + 8, 17, { 0.3, 0.12, 0.4 }, "left")
            if t == 0 then Text.display("NEXT TICK", x + 42, P.y + 11, 11, C.magentaDark, "left") end
        end
        for k = i, j - 1 do
            local it = items[k]
            local px, py = x + 10 + (k - i) * 46 + r - 6, P.y + 54
            local hov = scene.hover.bug == it.id
            local col = it.side == "kid" and C.teal or C.magenta
            if it.kind == "rival" then col = C.magenta end
            Paper.disc(px, py, r + 3, hov and C.yellow or col, { seed = k, shadow = true, line = 3 })
            Paper.disc(px, py, r - 2, C.cream, { seed = k + 5, line = 0 })
            love.graphics.setColor(1, 1, 1, 1)
            if it.kind == "rival" then
                local rv = Rivals[s.rival.id]
                if rv then Assets.drawKid(rv.portrait, "neutral", px, py + 2, r * 2.4)
                else icon(PD.natures[s.rival.id].icon, px, py, r * 1.5) end
                love.graphics.setColor(C.red[1], C.red[2], C.red[3], 1)
                love.graphics.circle("fill", px + r - 2, py - r + 4, 6)
                Text.display("!", px + r - 2, py - r + 0, 8, { 1, 1, 1 }, "center")
            else
                Assets.drawPortrait(it.species, px, py, r * 2 - 4)
            end
            add("timeline", px - r, py - r, r * 2, r * 2, { id = it.id, rival = it.kind == "rival" })
        end
        x = x + colW + 6
        i = j
    end
end

-- ───────────────────────── sun clock ─────────────────────────
function Hud.sunClock(scene, time)
    local P = L.sun
    Paper.panel(P.x, P.y, P.w, P.h, { fill = { 1, 0.9, 0.55 }, seed = 5, r = 16 })
    local s = scene.state
    local tick, limit = scene.disp.tick or s.tick, s.sunLimit
    local late = limit - tick <= 8
    love.graphics.setColor(1, 1, 1, 1)
    icon("icon_sun", P.x + 40, P.y + 38, 64)
    Text.display("SUN CLOCK", P.x + 80, P.y + 8, 13, { 0.5, 0.25, 0.1 }, "left")
    local pulse = scene.disp.tickPulse or 0
    Text.display(tick .. "/" .. limit, P.x + 80, P.y + 30, 26 + pulse * 6, late and { 0.9, 0.2, 0.25 } or { 0.3, 0.12, 0.4 }, "left")
    -- progress bar
    local bx, by, bw = P.x + 80, P.y + 62, P.w - 100
    love.graphics.setColor(INK[1], INK[2], INK[3], 0.85)
    love.graphics.rectangle("fill", bx - 2, by - 2, bw + 4, 14, 7, 7)
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.rectangle("fill", bx, by, bw, 10, 5, 5)
    local k = math.min(1, tick / limit)
    local col = Paper.mix(C.yellow, C.red, math.min(1, k * 1.2))
    love.graphics.setColor(col)
    love.graphics.rectangle("fill", bx, by, math.max(8, bw * k), 10, 5, 5)
end

-- ───────────────────────── rival panel ─────────────────────────
local SIG_ICON = { stomp = "fx_stomp", farm = nil, buy = nil }

function Hud.rival(scene, add, time)
    local P = L.rival
    local s = scene.state
    local rv = Rivals[s.rival.id]
    local nat = PD.natures[s.rival.id]
    Paper.panel(P.x, P.y, P.w, P.h, { fill = C.cream, seed = 7, r = 18, rot = -0.004 })
    local hop = (scene.rivalAnim or 0)
    local sig
    if rv then
        sig = rv.sig
        local mood = scene.rivalMood or "neutral"
        if mood == "neutral" and scene.enc and scene.enc.mood == "cocky" then mood = "happy" end
        if mood == "neutral" and scene.enc and scene.enc.mood == "angry" then mood = "sad" end
        Paper.disc(P.x + 100, P.y + 108, 84, C.magenta, { seed = 2, shadow = true, line = 4 })
        Paper.disc(P.x + 100, P.y + 108, 74, { 1, 0.84, 0.55 }, { seed = 3, line = 0 })
        love.graphics.setColor(1, 1, 1, 1)
        Assets.drawKid(rv.portrait, mood, P.x + 100, P.y + 112 - hop * 20, 190)
        Text.display(rv.name, P.x + 196, P.y + 20, 24, INK, "left", P.w - 206)
        local leader = scene.enc and scene.enc.leader
        Text.display(scene.mode == "prologue" and "WARM-UP" or leader and "THE GANG LEADER" or "THE RIVAL", P.x + 196, P.y + 60, 12, C.magentaDark)
        local house = leader and rv.house
        if house then
            Text.body('"' .. house.name .. '" ' .. house.text, P.x + 196, P.y + 80, 12, C.magentaDark, "left", P.w - 210)
        else
            Text.body(rv.short, P.x + 196, P.y + 84, 13, { 0.35, 0.2, 0.45 }, "left", P.w - 210)
        end
        local moodTag = scene.enc and scene.enc.mood
        if moodTag == "angry" or moodTag == "cocky" then
            UI.tag(moodTag == "angry" and "ANGRY" or "COCKY", P.x + 24, P.y + 12, 11, moodTag == "angry" and C.red or C.orange, { seed = 12, rot = -0.08 })
        end
        -- what this round is worth
        local k = scene.disp.keeps
        if scene.mode == "duel" and k then
            love.graphics.setColor(1, 1, 1, 1)
            icon("icon_marble", P.x + 210, P.y + 157, 26)
            Text.display("YOU " .. k.kid .. "  ·  THEM " .. k.rival, P.x + 228, P.y + 147, 17, INK, "left", P.w - 240)
            Text.body(s.rule.id == "showdown" and "Every hit moves a marble." or "For keeps: hits move marbles.", P.x + 196, P.y + 174, 11, { 0.4, 0.25, 0.5 }, "left", P.w - 206)
        elseif scene.mode == "duel" then
            local stake = scene.stake or 0
            love.graphics.setColor(1, 1, 1, 1)
            icon("icon_marble", P.x + 210, P.y + 157, 26)
            Text.display("POT: " .. (2 * stake) .. " MARBLES", P.x + 228, P.y + 147, 17, INK, "left", P.w - 240)
            local allIn = scene.run and scene.run.duel and require("sim.duel").allIn(scene.run)
            local line = allIn == "kid" and "You're ALL IN!" or allIn == "rival" and "They're ALL IN!" or allIn == "both" and "You're both ALL IN!" or ("You each bet " .. stake .. ".")
            Text.body(line, P.x + 196, P.y + 174, 11, allIn == "kid" and C.red or { 0.4, 0.25, 0.5 }, "left", P.w - 206)
        else
            Text.display("FOR FAIR", P.x + 196, P.y + 147, 17, C.tealDark, "left", P.w - 206)
            Text.body("A warm-up: no marbles at stake.", P.x + 196, P.y + 174, 11, { 0.4, 0.25, 0.5 }, "left", P.w - 206)
        end
    else
        -- a Bug Hunt: no kid, but nature has a move of its own
        sig = nat.sig
        Paper.disc(P.x + 100, P.y + 108, 84, C.green, { seed = 2, shadow = true, line = 4 })
        Paper.disc(P.x + 100, P.y + 108, 74, { 0.86, 0.96, 0.84 }, { seed = 3, line = 0 })
        love.graphics.setColor(1, 1, 1, 1)
        icon(nat.icon, P.x + 100, P.y + 108 - hop * 16, 112)
        Text.display(nat.name, P.x + 196, P.y + 20, 22, INK, "left", P.w - 206)
        Text.display("NATURE", P.x + 196, P.y + 54, 12, C.tealDark)
        Text.body("No kid here, but the park has a move of its own.", P.x + 196, P.y + 74, 12.5, { 0.35, 0.2, 0.45 }, "left", P.w - 210)
        local hunt = s.hunt or {}
        if hunt.prize then
            love.graphics.setColor(1, 1, 1, 1)
            Assets.drawPortrait(hunt.prize, P.x + 212, P.y + 160, 34)
            Text.display("PRIZE: " .. Bugs[hunt.prize].short, P.x + 236, P.y + 147, 16, INK, "left", P.w - 248)
        end
        Text.body("Buzz: " .. PD.buzz[hunt.buzz or 0].name .. ". No marbles at stake.", P.x + 196, P.y + 174, 11, { 0.4, 0.25, 0.5 }, "left", P.w - 206)
    end
    -- signature move
    local sy = P.y + 204
    Paper.panel(P.x + 12, sy, P.w - 24, 104, { fill = rv and { 1, 0.9, 0.95 } or { 0.86, 0.96, 0.84 }, seed = 9, r = 14, line = 3, shadow = false })
    local timer = math.max(0, scene.disp.rivalTimer or s.rival.timer)
    Paper.disc(P.x + 54, sy + 52, 28, rv and C.magenta or C.green, { seed = 4, shadow = true, line = 3.5 })
    Text.display(timer >= 99 and "-" or tostring(timer), P.x + 54, sy + 38, 28, { 1, 1, 1 }, "center")
    Text.display(s.rival.name or sig.name, P.x + 96, sy + 8, 18, INK, "left", P.w - 128)
    local label = rv and "SIGNATURE MOVE" or (sig.once and "COMING" or "NATURE'S MOVE")
    Text.display(timer == 0 and (label .. " - NEXT TICK!") or label, P.x + 96, sy + 36, 9, rv and C.magentaDark or C.tealDark, "left")
    Text.body(sig.text, P.x + 96, sy + 50, 12, INK, "left", P.w - 124)
    add("rivalsig", P.x + 12, sy, P.w - 24, 104, {})
end

-- ───────────────────────── rule panel ─────────────────────────
function Hud.rule(scene, add, time)
    local P = L.rule
    local s = scene.state
    local def = Rules[s.rule.id]
    Paper.panel(P.x, P.y, P.w, P.h, { fill = { 0.88, 0.97, 0.92 }, seed = 11, r = 18, rot = 0.003 })
    Text.display("RULE OF THE GAME", P.x + 18, P.y + 12, 11, { 0.15, 0.5, 0.4 })
    Text.display(def.name, P.x + 18, P.y + 36, 24, INK, "left", P.w - 36)
    local h = wrapBody(def.short, P.x + 18, P.y + 76, 15, P.w - 36, INK)
    local y = P.y + 76 + h + 12
    local footer = "Sun clock ends: you lose."
    if s.rule.id == "jar" then
        footer = "Sun clock ends: the hunt is over."
        local caught = scene.disp.caught or {}
        Text.display("IN THE JAR", P.x + 18, y + 4, 14, C.tealDark, "left")
        Text.display(tostring(#caught), P.x + 150, y, 22, C.tealDark, "left")
        for i, c in ipairs(caught) do
            if i > 8 then break end
            local cx = P.x + 34 + (i - 1) * 40
            Paper.disc(cx, y + 50, 17, c.prize and C.yellow or C.teal, { seed = i, line = 2.5 })
            love.graphics.setColor(1, 1, 1, 1)
            Assets.drawPortrait(c.species, cx, y + 50, 28)
        end
        if #caught == 0 then Text.body("Nothing yet. Lure them in, nudge them in.", P.x + 18, y + 38, 13, { 0.3, 0.3, 0.4 }, "left", P.w - 36) end
        local loose = 0
        for _, b in ipairs(s.bugs) do if b.loose then loose = loose + 1 end end
        if loose > 0 then Text.body(loose .. " of yours LOOSE: get them back into the jar!", P.x + 18, y + 76, 13, C.red, "left", P.w - 36) end
        if s.phase == "fight" and not s.winner then
            local r = { x = P.x + P.w - 186, y = P.y + P.h - 58, w = 170, h = 46 }
            local hov = scene.hover.button == "lid"
            local can = scene.canAct
            Paper.panel(r.x, r.y + (hov and can and -4 or 0), r.w, r.h, { fill = can and C.orange or { 0.6, 0.6, 0.65 }, seed = 13, r = 14, line = 3 })
            Text.display("CLOSE THE LID", r.x + 10, r.y + 14 + (hov and can and -4 or 0), 15, { 1, 1, 1 }, "center", r.w - 20)
            if can then add("button", r.x, r.y, r.w, r.h, { kind = "lid" }) end
            Text.body("[L] keeps what's inside", P.x + 18, P.y + P.h - 50, 11, { 0.3, 0.3, 0.4 })
        end
    elseif s.rule.id == "crumbs" then
        for row = 1, 2 do
            local side = row == 1 and "kid" or "rival"
            local col = side == "kid" and C.teal or C.magenta
            Text.display(side == "kid" and "YOU" or "THEM", P.x + 18, y + 4, 14, col == C.teal and C.tealDark or C.magentaDark, "left")
            local score = scene.disp.score[side] or 0
            for i = 1, s.rule.goal do
                local cx = P.x + 100 + (i - 1) * 40
                local filled = i <= score
                local pop = (i == score and (scene.disp.scorePulse[side] or 0) or 0)
                Paper.disc(cx, y + 12, 15 + pop * 5, filled and col or { 1, 1, 1, 0.55 }, { seed = i + row * 7, line = 3 })
                if filled then love.graphics.setColor(1, 1, 1, 1); Assets.tiles:draw("loot", cx, y + 24, 0, 0.1) end
            end
            y = y + 38
        end
        local nextSp
        for _, sp in ipairs(s.rule.spawns) do if sp.tick > s.tick and (not nextSp or sp.tick < nextSp.tick) then nextSp = sp end end
        if nextSp then
            local soon = nextSp.tick == s.tick + 1
            Text.body("Next crumbs land on tick " .. nextSp.tick .. (soon and ": the next one!" or "."), P.x + 18, y + 4, 13, { 0.15, 0.5, 0.4 })
        end
    else
        local rv = Q.count(s, "rival")
        Text.display("YOU HAVE", P.x + 18, y + 4, 13, C.tealDark, "left")
        Text.display(tostring(Q.count(s, "kid") + #s.jar), P.x + 160, y + 0, 22, C.tealDark, "left")
        Text.display("RIVAL HAS", P.x + 214, y + 4, 13, C.magentaDark, "left")
        Text.display(tostring(rv), P.x + 346, y + 0, 22, C.magentaDark, "left")
        local out = require("sim.rules").knockedOut(s, "rival")
        Text.body((s.rule.id == "zumo" and "Shoved off the stump: " or "Scurried off: ") .. out, P.x + 18, y + 40, 14, INK)
        if s.rule.id == "zumo" then Text.body("Light shoves 1 tile, Medium 2, Heavy 3.", P.x + 18, y + 62, 12.5, { 0.3, 0.3, 0.4 }) end
        local k = scene.disp.keeps
        if k then
            -- the Showdown (and "for keeps"): the marbles move with every hit
            if s.rule.id == "showdown" then footer = "Sun clock ends: the bell rings." end
            Text.display("MARBLES", P.x + 18, y + 72, 11, { 0.15, 0.5, 0.4 }, "left")
            love.graphics.setColor(1, 1, 1, 1)
            icon("icon_marble", P.x + 40, y + 108, 30)
            Text.display(tostring(k.kid), P.x + 62, y + 98, 20, C.tealDark, "left")
            love.graphics.setColor(1, 1, 1, 1)
            icon("icon_marble", P.x + 214, y + 108, 30)
            Text.display(tostring(k.rival), P.x + 236, y + 98, 20, C.magentaDark, "left")
        elseif s.rule.id == "lbs" and scene.run then
            Text.display("YOUR MARBLES", P.x + 18, y + 72, 11, { 0.15, 0.5, 0.4 }, "left")
            love.graphics.setColor(1, 1, 1, 1)
            icon("icon_marble", P.x + 40, y + 108, 30)
            Text.display(tostring(scene.run.marbles), P.x + 62, y + 98, 20, C.tealDark, "left")
        end
    end
    if s.rule.id ~= "jar" or s.phase ~= "fight" or s.winner then
        Text.body(footer, P.x + 18, P.y + P.h - 26, 12, { 0.3, 0.3, 0.4 })
    end
end

-- ───────────────────────── inspector ─────────────────────────
local function statChip(name, text, x, y, color)
    love.graphics.setColor(1, 1, 1, 1)
    icon(name, x, y, 30)
    Text.display(text, x + 20, y - 9, 18, color or INK, "left")
end

local function section(label, body, x, y, w, color, size)
    Text.display(label, x, y, 11, color)
    local h = Text.bodyHeight(body, size or 12.5, w)
    Text.body(body, x, y + 15, size or 12.5, INK, "left", w)
    return y + 15 + h + 6
end

function Hud.inspector(scene, add, time)
    local P = L.inspector
    local s = scene.state
    Paper.panel(P.x, P.y, P.w, P.h, { fill = C.cream, seed = 13, r = 18, rot = 0.004 })
    local id = scene.hover.bug
    local bug = id and require("sim.state").byId(s, id)
    local card = scene.hover.card and s.hand[scene.hover.card]
    if scene.armed then card = scene.armed.id end
    if scene.hover.jar and s.jar[scene.hover.jar] then bug = nil; card = nil end
    if bug then
        local sp = Bugs[bug.species]
        local col = bug.side == "kid" and C.teal or C.magenta
        Paper.disc(P.x + 52, P.y + 56, 40, col, { seed = 4, shadow = true, line = 4 })
        Paper.disc(P.x + 52, P.y + 56, 34, C.cream, { seed = 5, line = 0 })
        love.graphics.setColor(1, 1, 1, 1)
        Assets.drawPortrait(bug.species, P.x + 52, P.y + 56, 66)
        Text.display(sp.name, P.x + 104, P.y + 14, 19, INK, "left", P.w - 112)
        Text.body(sp.latin, P.x + 104, P.y + 46, 13, { 0.4, 0.25, 0.5 })
        Text.display(sp.role .. " · " .. (bug.side == "kid" and "YOURS" or "RIVAL'S"), P.x + 104, P.y + 68, 11, col == C.teal and C.tealDark or C.magentaDark)
        local y = P.y + 112
        statChip("icon_heart", bug.hp .. "/" .. bug.maxHp, P.x + 28, y + 6)
        statChip("icon_fang", tostring(bug.bite), P.x + 118, y + 6)
        statChip("icon_hourglass", (bug.ready and "0" or bug.timer) .. "/" .. bug.baseTimer, P.x + 186, y + 6)
        statChip("icon_weight_" .. bug.weight, ({ "L", "M", "H" })[bug.weight], P.x + 276, y + 6)
        statChip("icon_foot", tostring(bug.move), P.x + 336, y + 6)
        y = y + 34
        local tags = {}
        if bug.ready then tags[#tags + 1] = "READY!" end
        if bug.curled then tags[#tags + 1] = "CURLED" end
        if bug.flipped then tags[#tags + 1] = "FLIPPED" end
        if bug.soaked then tags[#tags + 1] = "SOAKED" end
        if bug.carrying then tags[#tags + 1] = "CARRYING" end
        if bug.loose then tags[#tags + 1] = "LOOSE" end
        if bug.prize then tags[#tags + 1] = "THE PRIZE" end
        if Q.isHidden(s, bug) then tags[#tags + 1] = "HIDDEN" end
        if #tags > 0 then Text.display(table.concat(tags, "  "), P.x + 18, y, 12, C.red, "left") ; y = y + 20 end
        y = section("TARGET", sp.rules.target, P.x + 18, y, P.w - 36, C.tealDark)
        y = section("MOVES", sp.rules.move, P.x + 18, y, P.w - 36, C.tealDark)
        y = section("ACTION", sp.rules.action, P.x + 18, y, P.w - 36, C.tealDark)
        if y < P.y + P.h - 56 then section("DID YOU KNOW?", sp.fact, P.x + 18, y, P.w - 36, C.magentaDark, 11.5) end
    elseif scene.hover.jar and s.jar[scene.hover.jar] then
        local e = s.jar[scene.hover.jar]
        local sp = Bugs[e.species]
        Paper.disc(P.x + 52, P.y + 56, 40, C.teal, { seed = 4, shadow = true, line = 4 })
        Paper.disc(P.x + 52, P.y + 56, 34, C.cream, { seed = 5, line = 0 })
        love.graphics.setColor(1, 1, 1, 1)
        Assets.drawPortrait(e.species, P.x + 52, P.y + 56, 66)
        Text.display(sp.name, P.x + 104, P.y + 14, 19, INK, "left", P.w - 112)
        Text.body(sp.latin, P.x + 104, P.y + 46, 13, { 0.4, 0.25, 0.5 })
        Text.display(sp.role .. (e.big and " · BIG" or ""), P.x + 104, P.y + 68, 11, C.tealDark)
        local y = P.y + 112
        local hp = sp.hp + ((e.big and not sp.colony) and 1 or 0)
        statChip("icon_heart", hp .. "/" .. hp, P.x + 28, y + 6)
        statChip("icon_fang", tostring(sp.bite), P.x + 112, y + 6)
        statChip("icon_hourglass", tostring(sp.timer), P.x + 178, y + 6)
        statChip("icon_weight_" .. sp.weight, ({ "L", "M", "H" })[sp.weight], P.x + 268, y + 6)
        statChip("icon_foot", tostring(sp.move), P.x + 322, y + 6)
        y = section("TARGET", sp.rules.target, P.x + 18, y + 34, P.w - 36, C.tealDark)
        y = section("MOVES", sp.rules.move, P.x + 18, y, P.w - 36, C.tealDark)
        y = section("ACTION", sp.rules.action, P.x + 18, y, P.w - 36, C.tealDark)
        if y < P.y + P.h - 56 then section("DID YOU KNOW?", sp.fact, P.x + 18, y, P.w - 36, C.magentaDark, 11.5) end
    elseif card then
        local def = Cards[card]
        love.graphics.setColor(1, 1, 1, 1)
        icon("card_" .. def.art, P.x + 62, P.y + 70, 108)
        Text.display(def.name, P.x + 130, P.y + 22, 24, INK, "left", P.w - 140)
        Text.display(def.type .. " card", P.x + 130, P.y + 60, 12, C.magentaDark)
        icon("icon_hourglass", P.x + 140, P.y + 96, 30)
        Text.display("COSTS " .. def.cost .. (def.cost == 1 and " TICK" or " TICKS"), P.x + 160, P.y + 86, 16, INK, "left")
        local y = P.y + 138
        local h = wrapBody(def.text, P.x + 18, y, 16, P.w - 36, INK)
        Text.body('"' .. def.flavor .. '"', P.x + 18, y + h + 12, 14, { 0.4, 0.25, 0.5 }, "left", P.w - 36)
    else
        Text.display("READ THE BUGS", P.x + 26, P.y + 26, 26, INK, "left", P.w - 52)
        Text.body("Hover any bug to see what it will do, why, and what it is in real life.", P.x + 26, P.y + 74, 16, INK, "left", P.w - 52)
        Text.body("You never give orders. Cards change the world, and every bug follows its instinct: a bug at 0 acts on the next tick.", P.x + 26, P.y + 146, 14, { 0.4, 0.25, 0.5 }, "left", P.w - 180)
        love.graphics.setColor(1, 1, 1, 1)
        Assets.bug.mantis:draw("idle1", P.x + P.w - 72, P.y + P.h - 14, 0, 0.55)
    end
end

-- ───────────────────────── jar ─────────────────────────
function Hud.jar(scene, add, time)
    local P = L.jar
    local s = scene.state
    Paper.panel(P.x, P.y, P.w, P.h, { fill = { 0.8, 0.95, 0.97 }, seed = 15, r = 18, rot = -0.003 })
    love.graphics.setColor(1, 1, 1, 1)
    icon("icon_jar", P.x + 38, P.y + 38, 56)
    local deploy = s.phase == "deploy"
    local hunt = s.rule.id == "jar"
    local title = deploy and (hunt and "HUNTING PARTY" or "PICK YOUR TEAM") or "THE JAR"
    local sub
    if deploy then sub = (hunt and "Up to 3 go hunting (" or "Free: place up to 3 on your two rows (") .. Kid.deployedCount(s) .. "/3)"
    elseif hunt then sub = "Your party is out hunting. The rest of your Jar is safe at home."
    else sub = "Release for time: Light 1, Medium 2, Heavy 3." .. ((s.items and s.items.sneakers) and " Sneakers: -1." or "") end
    Text.display(title, P.x + 76, P.y + 14, 22, INK, "left", P.w - 90)
    Text.body(sub, P.x + 76, P.y + 44, 12.5, { 0.15, 0.4, 0.45 }, "left", P.w - 90)
    -- 3 rows of 2 fit the panel; a bigger Jar gets compact rows
    local compact = #s.jar > 6
    local cols, cw, chh = 2, 188, compact and 40 or 58
    local top, gap = compact and 72 or 78, compact and 4 or 6
    local k = chh / 58
    for i, e in ipairs(s.jar) do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        local x, y = P.x + 12 + col * (cw + 4), P.y + top + row * (chh + gap)
        local sp = Bugs[e.species]
        local armed = scene.armedJar == i
        local hov = scene.hover.jar == i
        Paper.panel(x, y, cw, chh, { fill = armed and C.yellow or (hov and { 1, 1, 1 } or C.cream), seed = 20 + i, r = 12, line = 3, shadow = not hov, rot = (i % 2 == 0) and 0.01 or -0.01 })
        love.graphics.setColor(1, 1, 1, 1)
        Assets.drawPortrait(e.species, x + 30 * k, y + chh / 2, 48 * k)
        Text.display(sp.short, x + 58 * k, y + 9 * k, 13, INK, "left", cw - 58 * k - 60)
        if not compact then Text.display(sp.role, x + 58, y + 32, 9.5, { 0.45, 0.25, 0.55 }, "left", cw - 58 - 60) end
        if e.big then UI.tag("BIG", x + cw - 60, y - 6, 8, C.green, { seed = 30 + i, shadow = false }) end
        if deploy then
            Text.display("FREE", x + cw - 12, y + chh - 18, 12, C.tealDark, "right")
        elseif not hunt then
            love.graphics.setColor(1, 1, 1, 1)
            icon("icon_hourglass", x + cw - 24, y + chh / 2 - 7 * k, 26 * k)
            Text.display(tostring(Kid.releaseCost(e.species, s)), x + cw - 40, y + chh / 2 - 17 * k, 18 * k, INK, "right")
        end
        add("jar", x, y, cw, chh, { index = i })
    end
    if #s.jar == 0 and not hunt then Text.body("The jar is empty: everybody is out there.", P.x + 20, P.y + 110, 14, { 0.3, 0.3, 0.4 }) end
    -- who sits this one out
    local run = scene.run
    if run and scene.mode ~= "prologue" then
        local naps = {}
        for _, e in ipairs(run.jar) do if e.nap then naps[#naps + 1] = Bugs[e.species].short end end
        if #naps > 0 then
            Text.body("Napping (sitting this one out): " .. table.concat(naps, ", "), P.x + 16, P.y + P.h - 30, 11.5, C.purple, "left", P.w - 32)
        end
    end
end

-- ───────────────────────── buttons ─────────────────────────
function Hud.buttons(scene, add, time)
    local W = L.wait
    local hov = scene.hover.button == "wait"
    local lift = hov and -5 or 0
    local can = scene.canAct and scene.state.phase == "fight"
    local fill = can and C.teal or { 0.6, 0.6, 0.65 }
    Paper.panel(W.x, W.y + lift, W.w, W.h, { fill = fill, seed = 31, r = 22, rot = -0.01 })
    love.graphics.setColor(1, 1, 1, can and 1 or 0.5)
    icon("icon_hourglass", W.x + 52, W.y + lift + 62, 70)
    Text.display("WAIT", W.x + 98, W.y + lift + 26, 30, { 1, 1, 1 }, "left")
    Text.display("1 TICK", W.x + 98, W.y + lift + 70, 16, { 1, 1, 1, 0.9 }, "left")
    Text.display("[SPACE]", W.x + 98, W.y + lift + 94, 11, { 1, 1, 1, 0.7 }, "left")
    if can then add("wait", W.x, W.y, W.w, W.h, {}) end

    local M = L.menu
    Paper.panel(M.x, M.y, M.w, M.h, { fill = C.cream, seed = 33, r = 16, rot = 0.004 })
    local defs = {
        { kind = "undo", icon = "icon_undo", label = "REWIND", key = "Z", cx = M.x + 50 },
        { kind = "mute", icon = "fx_note", label = "SOUND", key = "M", cx = M.x + 143 },
        { kind = "menu", icon = "icon_jar", label = "MENU", key = "ESC", cx = M.x + 236 },
    }
    for _, d in ipairs(defs) do
        local h = scene.hover.button == d.kind
        Paper.disc(d.cx, M.y + 36, 29 + (h and 3 or 0), h and C.yellow or { 1, 0.9, 0.7 }, { seed = 3, shadow = true, line = 3.5 })
        love.graphics.setColor(1, 1, 1, 1)
        icon(d.icon, d.cx, M.y + 36, 38)
        Text.display(d.label, d.cx, M.y + 68, 9, { 0.4, 0.2, 0.5 }, "center")
        add("button", d.cx - 30, M.y + 6, 60, 70, { kind = d.kind })
    end
end

return Hud
