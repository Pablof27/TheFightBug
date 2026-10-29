-- The fight scene: owns the simulation state, turns mouse input into kid actions, and presents everything.
-- Flow of one action:  input -> Kid.play / Kid.wait / Kid.release on the real state (instant) -> the events it emitted go to
-- the Director, which replays them as animation -> when the replay is over everything is re-synced from the state.

local Assets = require("client.assets")
local Paper = require("client.paper")
local Text = require("client.text")
local Tween = require("client.tween")
local Audio = require("client.audio")
local Fx = require("client.fx")
local Actor = require("client.fight.actor")
local BV = require("client.fight.board_view")
local Director = require("client.fight.director")
local Intent = require("client.fight.intent_view")
local Hud = require("client.fight.hud")
local HandView = require("client.fight.hand_view")
local Hints = require("client.fight.hints")
local L = require("client.fight.layout")
local G = require("client.fight.geometry")

local SimFight = require("sim.fight")
local State = require("sim.state")
local Kid = require("sim.kid")
local Forecast = require("sim.forecast")
local Q = require("sim.query")
local Grid = require("sim.grid")
local Rules = require("sim.rules")
local Run = require("sim.run")
local U = require("sim.util")
local Cards = require("data.cards")
local Rivals = require("data.rivals")

local C = Paper.C
local Fight = {}
Fight.__index = Fight

local STAGE_BACKDROP = { sandbox = "sandbox", lawn = "lawn", stump = "stump" }
local CARD_ITEM = { crumb = "crumb", sugar = "sugar", juice = "juice", pebble = "pebble", leaf = "leaf", stick = "stick", water = "puddle" }

function Fight.new(app, params)
    local self = setmetatable({}, Fight)
    self.app = app
    self.enc, self.run = params.enc, params.run
    self.bet = Run.rivalBet(self.enc.rival)
    self.time = 0
    self.state = SimFight.new(self.enc, { jar = self.run.jar, deck = self.run.deck, seed = (self.run.seed or 1) * 131 + (self.run.node or 1) })
    if self.state.phase == "deploy" then
        local order = {}
        for _, sp in ipairs(self.enc.deploy or {}) do
            for _, e in ipairs(self.state.jar) do if e.species == sp then order[#order + 1] = e.uid break end end
        end
        SimFight.autoDeploy(self.state, order)
    end
    State.drain(self.state)
    G.setup(self.state.w)
    self.view = { cells = U.clone(self.state.cells), w = self.state.w, h = self.state.h }
    self.actors, self.actorById = {}, {}
    self.hand = HandView.new()
    self.director = Director.new(self)
    self.history = {}
    self.version, self.forecastVersion = 0, -1
    self.hover, self.hits = {}, {}
    self.disp = { tick = 0, rivalTimer = self.state.rival.timer, score = { kid = 0, rival = 0 }, scorePulse = { kid = 0, rival = 0 }, tickPulse = 0 }
    self.effects, self.drops = {}, {}
    self.hintsDone, self.hintsMuted = {}, {}
    self.showIntents = true
    self.rewinds = 0
    self.rivalMood = "neutral"
    self.rivalAnim = 0
    self.canAct = true
    self.mouse = { x = app.mouse.x, y = app.mouse.y }
    self:rebuildActors()
    self.hand:sync(self.state.hand, true)
    return self
end

function Fight:enter()
    Audio.music("park")
    self.startedAt = self.time
    self.intro = { t = 0 }
    Audio.play("entry")
end

-- ───────────────────────── actors & view ─────────────────────────
function Fight:addActor(a)
    self.actors[#self.actors + 1] = a
    self.actorById[a.id] = a
end

function Fight:rebuildActors()
    self.actors, self.actorById = {}, {}
    for _, b in ipairs(self.state.bugs) do self:addActor(Actor.new(b)) end
end

--- After a playback (or anything that changed the state without events): make the picture match the state.
function Fight:syncActors()
    local present = {}
    for _, b in ipairs(self.state.bugs) do
        present[b.id] = true
        local a = self.actorById[b.id]
        if not a then
            a = Actor.new(b)
            self:addActor(a)
        end
        a.gone, a.dead, a.alpha = false, false, 1
        a:sync(b)
        a:place(b.x, b.y)
        a.offx, a.offy, a.hopT, a.hopH, a.z, a.rot, a.spin, a.sx, a.sy = 0, 0, 0, 0, 0, 0, 0, 1, 1
        a.hiddenFlag = Q.isHidden(self.state, b)
    end
    for i = #self.actors, 1, -1 do
        local a = self.actors[i]
        if not present[a.id] then
            table.remove(self.actors, i)
            self.actorById[a.id] = nil
        end
    end
    self.view.cells = U.clone(self.state.cells)
    self.disp.tick = self.state.tick
    self.disp.rivalTimer = self.state.rival.timer
    self.disp.score.kid = self.state.rule.score.kid
    self.disp.score.rival = self.state.rule.score.rival
end

function Fight:hiddenSet()
    local set = {}
    local cells = self.view.cells
    for _, a in ipairs(self.actors) do
        if not a:isFlying() and not a.gone then
            local x, y = math.floor(a.x + 0.5), math.floor(a.y + 0.5)
            local c = cells[Grid.key(x, y)]
            if c and c.cover then
                local exposed = false
                for _, o in ipairs(self.actors) do
                    if o.side ~= a.side and not o.gone then
                        local ox, oy = math.floor(o.x + 0.5), math.floor(o.y + 0.5)
                        if math.abs(ox - x) + math.abs(oy - y) == 1 then exposed = true break end
                    end
                end
                if not exposed then set[a.id] = true end
            end
        end
    end
    return set
end

-- ───────────────────────── performing actions ─────────────────────────
function Fight:displayHandCount(events)
    local n = 0
    for _, e in ipairs(events) do if e.type == "draw" then n = n + 1 end end
    return n
end

function Fight:perform(fn)
    self.history[#self.history + 1] = State.clone(self.state)
    if #self.history > 60 then table.remove(self.history, 1) end
    State.drain(self.state)
    local ok, err = fn()
    local events = State.drain(self.state)
    if not ok then
        table.remove(self.history)
        return false, err
    end
    self.version = self.version + 1
    self.forecast, self.preview = nil, nil
    self.armed, self.armedJar = nil, nil
    local shown = {}
    local n = #self.state.hand - self:displayHandCount(events)
    for i = 1, math.max(0, n) do shown[i] = self.state.hand[i] end
    self.hand:sync(shown)
    for _, e in ipairs(events) do if e.type == "alarm" then self.sawAlarm = true end end
    self.director:push(events)
    if not self.director.playing then self:onPlaybackDone() end
    return true
end

function Fight:onPlaybackDone()
    self:syncActors()
    self.hand:sync(self.state.hand)
    self.forecast, self.preview = nil, nil
    if self.pendingEnd then
        local ev = self.pendingEnd
        self.pendingEnd = nil
        -- decided now, before CONTINUE settles the bet: the banner stays on screen during the scene transition
        local lastFight = ev.winner ~= "kid" and self.run.marbles - self.bet < self.bet
        self.result = { winner = ev.winner, why = ev.why, t = 0, lastFight = lastFight }
        self.rivalMood = ev.winner == "rival" and "happy" or "sad"
        Audio.play(ev.winner == "kid" and "win" or "lose")
        if ev.winner == "kid" then
            for i = 1, 8 do Fx.sparkle(love.math.random(300, 1300), love.math.random(150, 500), 3, 40) end
        end
    end
end

function Fight:onFightEnd(ev) self.pendingEnd = ev end

function Fight:rewind()
    if #self.history == 0 then Audio.play("block"); return end
    self.director:clear()
    Tween.clear()
    Fx.clear()
    self.state = table.remove(self.history)
    self.pendingEnd, self.result = nil, nil
    self.rivalMood = "neutral"
    self.armed, self.armedJar = nil, nil
    self.drops, self.effects = {}, {}
    G.setup(self.state.w)
    self:rebuildActors()
    self:syncActors()
    self.hand:sync(self.state.hand, true)
    self.version = self.version + 1
    self.forecast, self.preview = nil, nil
    self.rewinds = self.rewinds + 1
    Audio.play("ui_back")
    Fx.text("REWIND!", 800, 420, C.yellow, 40)
end

function Fight:doWait()
    if not self.canAct or self.state.phase ~= "fight" then return end
    Audio.play("ui_click")
    self:perform(function() return Kid.wait(self.state) end)
end

function Fight:startFight()
    if self.state.phase ~= "deploy" then return end
    if Kid.deployedCount(self.state) == 0 then Audio.play("block"); Fx.text("PICK A BUG FIRST!", 800, 760, C.red, 26); return end
    Audio.play("ui_click")
    self:perform(function() return Kid.start(self.state) end)
    Audio.play("win", 0.3)
end

-- ───────────────────────── effects used by the director ─────────────────────────
function Fight:dropItem(kind, ev, apply)
    local d = { kind = kind, x = ev.x, y = ev.y, x2 = ev.x2, y2 = ev.y2, t = 0, dur = 0.3, apply = apply }
    self.drops[#self.drops + 1] = d
end

function Fight:addEffect(dur, draw)
    self.effects[#self.effects + 1] = { t = 0, dur = dur, draw = draw }
end

function Fight:handShadow(actor)
    self:addEffect(0.6, function(k)
        local x, y = G.foot(actor.x, actor.y)
        local slide = (1 - math.min(1, k * 3)) ^ 2
        love.graphics.setColor(1, 1, 1, 0.5 * (1 - math.max(0, k - 0.7) / 0.3))
        Assets.people:draw("hand_shadow", x + slide * 160, y - 40 - slide * 160, 0, 0.9 * G.unit)
    end)
end

function Fight:handFlick(actor, dx, dy)
    self:addEffect(0.45, function(k)
        local x, y = G.foot(actor.x, actor.y)
        local name = k < 0.35 and "hand_flick1" or "hand_flick2"
        local side = dx >= 0 and -1 or 1
        local appear = math.min(1, k * 6)
        love.graphics.setColor(1, 1, 1, appear * (1 - math.max(0, k - 0.75) / 0.25))
        Assets.people:draw(name, x + side * 70 * G.unit, y - 30 - (1 - appear) * 60, side * -0.3, 0.45 * G.unit * -side, 0.45 * G.unit)
    end)
end

function Fight:stompAt(cx, cy)
    local x, y = G.center(cx, cy)
    self:addEffect(0.75, function(k)
        local fall = math.min(1, k / 0.35)
        local a = k < 0.5 and 1 or (1 - (k - 0.5) / 0.5)
        love.graphics.setColor(1, 1, 1, a * 0.95)
        local s = (G.T * 3.2 / 160) * (1.5 - 0.5 * fall)
        Assets.ui:draw("fx_stomp", x, y - (1 - fall) * 420, 0.1, s)
        if k > 0.33 and not self._stomped then
            self._stomped = true
            Fx.shake(16)
            Fx.puff(x, y, 8, 0.4)
        end
        if k > 0.9 then self._stomped = nil end
    end)
end

function Fight:glowArea(cx, cy, kind)
    self:addEffect(0.6, function(k)
        for dx = -1, 1 do
            for dy = -1, 1 do
                local c = Grid.cell(self.state, cx + dx, cy + dy)
                if c and not c.void then BV.tileGlow(cx + dx, cy + dy, "area", self.time, 1 - k) end
            end
        end
    end)
end

-- ───────────────────────── hover & picking ─────────────────────────
function Fight:actorAt(mx, my)
    local best, bestY
    for _, a in ipairs(self.actors) do
        if not a.gone then
            local fx, fy = G.foot(a.x, a.y)
            local h = a:height() * G.T
            if math.abs(mx - fx) <= G.T * 0.42 and my >= fy - h - 12 and my <= fy + G.T * 0.22 then
                if not bestY or fy > bestY then best, bestY = a, fy end
            end
        end
    end
    return best
end

function Fight:dirHandles()
    if not self.armed then return {} end
    local opts = Kid.options(self.state, self.armed.id, self.armed.sel)
    if not opts or opts.kind ~= "dir" then return {} end
    local out = {}
    local ax, ay
    local prev = self.armed.sel[#self.armed.sel]
    if Cards[self.armed.id].steps[#self.armed.sel] == "bug" then
        local b = State.byId(self.state, prev)
        ax, ay = b.x, b.y
    else
        ax, ay = prev.x, prev.y
    end
    local cx, cy = G.center(ax, ay)
    for _, it in ipairs(opts.items) do
        out[#out + 1] = { dx = it.dx, dy = it.dy, ok = it.ok, x = cx + it.dx * G.T * 0.74, y = cy - it.dy * G.T * 0.74, tx = it.x, ty = it.y }
    end
    return out
end

function Fight:updateHover(mx, my)
    self.mouse.x, self.mouse.y = mx, my
    local h = {}
    for _, hit in ipairs(self.hits) do
        if mx >= hit.x and mx <= hit.x + hit.w and my >= hit.y and my <= hit.y + hit.h then
            if hit.kind == "timeline" then h.bug = hit.data.id; h.timelineRival = hit.data.rival
            elseif hit.kind == "jar" then h.jar = hit.data.index
            elseif hit.kind == "button" then h.button = hit.data.kind
            elseif hit.kind == "wait" then h.button = "wait"
            elseif hit.kind == "rivalsig" then h.rivalsig = true end
        end
    end
    if self.state.phase == "fight" or self.state.phase == "deploy" then
        local ci = self.hand:hit(mx, my)
        if ci and self.state.phase == "fight" then h.card = ci end
    end
    if not h.card and not h.button and not h.jar then
        local tile = { G.tileAt(mx, my) }
        if tile[1] then h.tile = { x = tile[1], y = tile[2] } end
        local a = self:actorAt(mx, my)
        -- while choosing a tile, the bug you inspect is the one standing ON that tile, not one whose tall sprite overlaps it
        if a and self.armed and self.armed.stepKind ~= "bug" and h.tile then
            local on = State.at(self.state, h.tile.x, h.tile.y)
            a = on and self.actorById[on.id] or nil
        end
        if a then h.bug = a.id end
        if not a and h.tile then
            local b = State.at(self.state, h.tile.x, h.tile.y)
            if b then h.bug = b.id end
        end
    end
    if self.armed and self.armed.stepKind == "dir" then
        local best, bd
        for _, hd in ipairs(self:dirHandles()) do
            local d = math.sqrt((mx - hd.x) ^ 2 + (my - hd.y) ^ 2)
            if hd.ok and d < G.T * 0.5 and (not bd or d < bd) then best, bd = hd, d end
        end
        h.dir = best
    end
    self.hover = h
end

-- ───────────────────────── arming & choosing ─────────────────────────
function Fight:arm(cardIndex)
    local id = self.state.hand[cardIndex]
    if not id then return end
    self.armed = { card = cardIndex, id = id, sel = {} }
    self.armedJar = nil
    local opts = Kid.options(self.state, id, {})
    self.armed.stepKind = opts and opts.kind
    Audio.play("card_pick")
end

function Fight:cancelArm()
    if self.armed or self.armedJar then Audio.play("card_cancel") end
    self.armed, self.armedJar, self.preview = nil, nil, nil
end

--- The pick the mouse is hovering over for the current step, if it is a legal one.
function Fight:hoverPick()
    local a = self.armed
    if not a then return nil end
    local opts = Kid.options(self.state, a.id, a.sel)
    if not opts then return nil end
    if opts.kind == "bug" then
        if self.hover.bug then
            for _, it in ipairs(opts.items) do if it.id == self.hover.bug then return self.hover.bug end end
        end
    elseif opts.kind == "tile" then
        local t = self.hover.tile
        if t then
            for _, it in ipairs(opts.items) do if it.x == t.x and it.y == t.y then return { x = t.x, y = t.y } end end
        end
    else
        local d = self.hover.dir
        if d then return { dx = d.dx, dy = d.dy } end
    end
    return nil
end

function Fight:chooseStep()
    local a = self.armed
    local pick = self:hoverPick()
    if pick == nil then Audio.play("block", 0.6); return end
    a.sel[#a.sel + 1] = pick
    local def = Cards[a.id]
    if #a.sel >= #def.steps then
        local idx, sel = a.card, a.sel
        self:perform(function() return Kid.play(self.state, idx, sel) end)
    else
        local opts = Kid.options(self.state, a.id, a.sel)
        a.stepKind = opts and opts.kind
        a.prevKind = def.steps[#a.sel]
        Audio.play("ui_click")
    end
end

function Fight:updatePreview()
    local a = self.armed
    self.preview = nil
    if not a then return end
    local pick = self:hoverPick()
    if pick == nil then return end
    local sel = {}
    for i, v in ipairs(a.sel) do sel[i] = v end
    sel[#sel + 1] = pick
    local def = Cards[a.id]
    local key = a.card .. ":" .. a.id .. ":" .. self.version
    for _, v in ipairs(sel) do
        key = key .. "|" .. (type(v) == "number" and v or (v.x and (v.x .. "," .. v.y) or (v.dx .. "," .. v.dy)))
    end
    if self.previewCache and self.previewCache.key == key then self.preview = self.previewCache.value return end
    local value = { sel = sel, area = Kid.area(self.state, a.id, sel) }
    local item = CARD_ITEM[a.id]
    if item then
        local p1, p2 = sel[1], sel[2]
        if type(p1) == "table" and p1.x then
            value.ghost = { kind = item, x = p1.x, y = p1.y }
            if p2 and p2.dx then value.ghost.x2, value.ghost.y2 = p1.x + p2.dx, p1.y + p2.dy end
        end
    end
    if #sel == #def.steps then
        local f, clone = Forecast.afterCard(self.state, a.card, sel)
        if f then
            value.forecast = f
            local base = self.forecast
            local changed = {}
            if base then
                local function sig(it) return it and (it.kind .. ":" .. (it.to and (it.to.x .. "," .. it.to.y) or "") .. ":" .. (it.target and (tostring(it.target.id) or "") or "")) end
                for id, it in pairs(f.intents) do
                    if sig(it) ~= sig(base.intents[id]) then changed[id] = true end
                end
            end
            value.changed = changed
        end
    end
    self.previewCache = { key = key, value = value }
    self.preview = value
end

-- ───────────────────────── input ─────────────────────────
function Fight:mousemoved(x, y) self:updateHover(x, y) end

function Fight:mousepressed(x, y, button)
    if self.intro then self.intro = nil; Audio.play("ui_click"); return end
    if self.confirm then return self:confirmClick(x, y, button) end
    self:updateHover(x, y)
    if self.result then return self:resultClick(x, y, button) end
    if self.director.playing then self.fastClick = true; return end
    if button == 2 then self:cancelArm(); return end
    if button ~= 1 then return end
    local h = self.hover
    if h.button == "wait" then return self:doWait() end
    if h.button == "undo" then return self:rewind() end
    if h.button == "mute" then Audio.toggleMute(); return end
    if h.button == "menu" then self.confirm = true; Audio.play("ui_click"); return end
    if self.hintRect and x >= self.hintRect.x and x <= self.hintRect.x + self.hintRect.w and y >= self.hintRect.y and y <= self.hintRect.y + self.hintRect.h and self.currentHint then
        self.hintsDone[self.currentHint.id] = true
        self.hintsMuted[self.currentHint.id] = true
        Audio.play("ui_click")
        return
    end
    if self.state.phase == "deploy" and self.startRect and x >= self.startRect.x and x <= self.startRect.x + self.startRect.w and y >= self.startRect.y and y <= self.startRect.y + self.startRect.h then
        return self:startFight()
    end
    if h.jar then
        if self.armedJar == h.jar then self:cancelArm() else self.armedJar = h.jar; self.armed = nil; Audio.play("card_pick") end
        return
    end
    if h.card and self.state.phase == "fight" then
        if self.armed and self.armed.card == h.card then self:cancelArm() else self:arm(h.card) end
        return
    end
    if self.armed then
        if self.armed.stepKind == "dir" then
            if h.dir then self:chooseStep() else self:cancelArm() end
        else
            self:chooseStep()
        end
        return
    end
    if self.armedJar then
        local t = h.tile
        if t and Kid.homeFree(self.state, t.x, t.y) then
            local idx = self.armedJar
            if self.state.phase == "deploy" then self:perform(function() return Kid.deploy(self.state, idx, t.x, t.y) end)
            else self:perform(function() return Kid.release(self.state, idx, t.x, t.y) end) end
        else
            self:cancelArm()
        end
        return
    end
    if self.state.phase == "deploy" and h.bug then
        local b = State.byId(self.state, h.bug)
        if b and b.side == "kid" and b.jarUid then
            local uid = b.jarUid
            local x0, y0 = G.foot(b.x, b.y)
            Fx.puff(x0, y0, 3, 0.2)
            self:perform(function() return Kid.undeploy(self.state, uid) end)
            self:syncActors()
            Audio.play("ui_back")
        end
    end
end

function Fight:mousereleased(x, y, b) self.fastClick = false end

function Fight:keypressed(key, isrepeat)
    if self.intro then
        if key == "space" or key == "return" or key == "escape" then self.intro = nil; Audio.play("ui_click") end
        return
    end
    if self.confirm then
        if key == "escape" or key == "n" then self.confirm = nil elseif key == "return" or key == "y" then self.app.switch("title") end
        return
    end
    if self.result then
        if key == "return" or key == "space" then self:resultContinue() elseif key == "z" then self:rewind() end
        return
    end
    if key == "escape" then
        if self.armed or self.armedJar then self:cancelArm() else self.confirm = true end
    elseif key == "space" then
        if self.director.playing then return end
        if self.state.phase == "deploy" then self:startFight() else self:doWait() end
    elseif key == "z" then
        if not self.director.playing then self:rewind() end
    elseif key == "tab" then
        self.showIntents = not self.showIntents
    elseif key == "return" and self.state.phase == "deploy" then
        self:startFight()
    elseif tonumber(key) and self.state.phase == "fight" and not self.director.playing then
        local i = tonumber(key)
        if self.state.hand[i] then
            if self.armed and self.armed.card == i then self:cancelArm() else self:arm(i) end
        end
    end
end

-- ───────────────────────── results ─────────────────────────
function Fight:resultRects()
    local cx = 800
    return {
        go = { x = cx - 260, y = 640, w = 250, h = 84 },
        back = { x = cx + 10, y = 640, w = 250, h = 84 },
    }
end

function Fight:resultClick(x, y, b)
    if b ~= 1 then return end
    local r = self:resultRects()
    local function inside(rc) return x >= rc.x and x <= rc.x + rc.w and y >= rc.y and y <= rc.y + rc.h end
    if inside(r.go) then self:resultContinue() elseif inside(r.back) then self:rewind() end
end

function Fight:resultContinue()
    if not self.result then return end
    Audio.play("ui_click")
    local run = self.run
    local won = self.result.winner == "kid"
    run.rewinds = (run.rewinds or 0) + self.rewinds
    local sum = Run.finish(run, self.state)
    if won and self.enc.boss then
        self.app.switch("ending", { run = run, won = true, sum = sum })
    elseif Run.over(run) then
        -- you can't cover the next rival's bet. Checked after any fight, not just losses, so the map is never a dead end.
        self.app.switch("ending", { run = run, won = false, sum = sum })
    else
        self.app.switch("map", { run = run, sum = sum })
    end
end

-- ───────────────────────── update ─────────────────────────
function Fight:update(dt)
    self.time = self.time + dt
    if self.intro then
        self.intro.t = self.intro.t + dt
        if self.intro.t > 4.5 then self.intro = nil end
    end
    self.director.speed = (love.keyboard.isDown("space") or self.fastClick) and 4 or 1
    self.director:update(dt)
    for i = #self.actors, 1, -1 do
        local a = self.actors[i]
        a:update(dt)
        if a.dead then table.remove(self.actors, i); self.actorById[a.id] = nil end
    end
    self.hand:update(dt, self.hover.card, self.armed and self.armed.card)
    local d = self.disp
    d.tickPulse = math.max(0, (d.tickPulse or 0) - dt * 3)
    d.scorePulse.kid = math.max(0, d.scorePulse.kid - dt * 2.5)
    d.scorePulse.rival = math.max(0, d.scorePulse.rival - dt * 2.5)
    self.rivalAnim = math.max(0, self.rivalAnim - dt * 2.5)
    for i = #self.effects, 1, -1 do
        local e = self.effects[i]
        e.t = e.t + dt
        if e.t >= e.dur then table.remove(self.effects, i) end
    end
    for i = #self.drops, 1, -1 do
        local dr = self.drops[i]
        dr.t = dr.t + dt
        if dr.t >= dr.dur then
            if dr.apply then dr.apply() end
            table.remove(self.drops, i)
        end
    end
    self.canAct = not self.director.playing and not self.result
    if not self.director.playing and not self.forecast and self.state.phase == "fight" and not self.state.winner then
        self.forecast = Forecast.compute(self.state)
    end
    if self.result then self.result.t = self.result.t + dt end
    self:updateHover(self.mouse.x, self.mouse.y)
    self:updatePreview()
    self.currentHint = (self.enc.tutorial and not self.result and self.state.phase == "fight" and not self.director.playing) and Hints.current(self) or nil
    if self.currentHint and self.currentHint.onShow then self.currentHint.onShow(self) end
    -- hints never nag: after their time on screen they retire
    if self.currentHint and self.currentHint.ttl then
        self.hintClock = self.hintClock or {}
        local id = self.currentHint.id
        self.hintClock[id] = (self.hintClock[id] or 0) + dt
        if self.hintClock[id] > self.currentHint.ttl then self.hintsDone[id] = true; self.hintsMuted[id] = true end
    end
end

-- ───────────────────────── draw ─────────────────────────
local function addHit(self) return function(kind, x, y, w, h, data) self.hits[#self.hits + 1] = { kind = kind, x = x, y = y, w = w, h = h, data = data } end end

function Fight:boardOverlays()
    local t = self.time
    local s = self.state
    local armed = self.armed
    -- legal targets of the armed card / jar release
    if armed and not self.director.playing then
        local opts = Kid.options(s, armed.id, armed.sel)
        if opts then
            if opts.kind == "tile" then
                for _, it in ipairs(opts.items) do
                    local hov = self.hover.tile and self.hover.tile.x == it.x and self.hover.tile.y == it.y
                    BV.tileGlow(it.x, it.y, hov and "hover" or "target", t)
                end
            elseif opts.kind == "bug" then
                for _, it in ipairs(opts.items) do
                    local a = self.actorById[it.id]
                    if a then BV.actorRing(a, t, "target") end
                end
            end
        end
    elseif self.armedJar and not self.director.playing then
        for _, p in ipairs(Q.homeTiles(s, "kid")) do
            if Kid.homeFree(s, p.x, p.y) then
                local hov = self.hover.tile and self.hover.tile.x == p.x and self.hover.tile.y == p.y
                BV.tileGlow(p.x, p.y, hov and "hover" or "target", t)
            end
        end
    elseif self.hover.tile and not self.director.playing then
        local ht = self.hover.tile
        local cx, cy = G.center(ht.x, ht.y)
        love.graphics.setColor(1, 1, 1, 0.12)
        love.graphics.rectangle("fill", cx - G.T / 2 + 3, cy - G.T / 2 + 3, G.T - 6, G.T - 6, 12, 12)
    end
    -- preview: area, ghost
    local pv = self.preview
    if pv then
        for _, tl in ipairs(pv.area or {}) do BV.tileGlow(tl.x, tl.y, "area", t, 0.9) end
        if pv.ghost then BV.ghost(pv.ghost.kind, pv.ghost.x, pv.ghost.y, pv.ghost.x2, pv.ghost.y2, t) end
    end
    -- dir handles (flick, shove, blow, stick, water)
    if armed and armed.stepKind == "dir" and not self.director.playing then
        for _, hd in ipairs(self:dirHandles()) do
            if hd.ok then
                local hov = self.hover.dir and self.hover.dir.dx == hd.dx and self.hover.dir.dy == hd.dy
                local u = G.unit
                local r = (hov and 24 or 19) * u
                Paper.disc(hd.x, hd.y, r, hov and C.yellow or C.teal, { shadow = true, line = 3.5 })
                local ang = math.atan2(-hd.dy, hd.dx)
                love.graphics.setColor(Paper.C.ink[1], Paper.C.ink[2], Paper.C.ink[3], 1)
                love.graphics.polygon("fill",
                    hd.x + math.cos(ang) * r * 0.62, hd.y + math.sin(ang) * r * 0.62,
                    hd.x + math.cos(ang + 2.4) * r * 0.55, hd.y + math.sin(ang + 2.4) * r * 0.55,
                    hd.x + math.cos(ang - 2.4) * r * 0.55, hd.y + math.sin(ang - 2.4) * r * 0.55)
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.polygon("fill",
                    hd.x + math.cos(ang) * r * 0.5, hd.y + math.sin(ang) * r * 0.5,
                    hd.x + math.cos(ang + 2.4) * r * 0.42, hd.y + math.sin(ang + 2.4) * r * 0.42,
                    hd.x + math.cos(ang - 2.4) * r * 0.42, hd.y + math.sin(ang - 2.4) * r * 0.42)
            end
        end
        -- the chosen bug or tile stays marked
        local prev = armed.sel[#armed.sel]
        if armed.prevKind == "bug" then
            local a = self.actorById[prev]
            if a then BV.actorRing(a, t, "target") end
        elseif type(prev) == "table" and prev.x then
            BV.tileGlow(prev.x, prev.y, "hover", t)
        end
    end
    -- rival signature move: where it will land
    local peek = self.forecast and self.forecast.rival
    if peek and peek.tiles and self.state.phase == "fight" and not self.director.playing then
        local danger = peek.timer <= 1
        for _, tl in ipairs(peek.tiles) do
            if peek.kind == "stomp" then
                BV.tileGlow(tl.x, tl.y, "danger", t, danger and 0.9 or 0.35)
            else
                local cx, cy = G.center(tl.x, tl.y)
                love.graphics.setColor(1, 1, 1, 0.45 + 0.2 * math.sin(t * 4))
                if peek.kind == "farm" then Assets.bug.ant:draw("idle1", cx, cy + G.T * 0.3, 0, -0.5 * G.unit, 0.5 * G.unit)
                elseif peek.species then Assets.bug[peek.species]:draw("idle1", cx, cy + G.T * 0.3, 0, -0.5 * G.unit, 0.5 * G.unit) end
            end
        end
    end
    -- next crumbs, with a countdown that reads like a timer (0 = they land on the next tick)
    if s.rule.id == "crumbs" and self.state.phase == "fight" then
        local nextTick
        for _, sp in ipairs(s.rule.spawns) do if sp.tick > s.tick and (not nextTick or sp.tick < nextTick) then nextTick = sp.tick end end
        for _, sp in ipairs(s.rule.spawns) do
            if sp.tick == nextTick then
                local cx, cy = G.center(sp.x, sp.y)
                love.graphics.setColor(1, 1, 1, 0.38)
                Assets.tiles:draw("loot", cx, cy + G.T * 0.3, 0, G.T / 200 * 0.7)
                Text.display(tostring(sp.tick - s.tick - 1), cx, cy - G.T * 0.1, 22 * G.unit, { 1, 1, 1, 0.9 }, "center")
            end
        end
    end
    -- deploy hint: show your two rows
    if s.phase == "deploy" and not self.armedJar then
        for _, p in ipairs(Q.homeTiles(s, "kid")) do
            if Kid.homeFree(s, p.x, p.y) then BV.tileGlow(p.x, p.y, "target", t, 0.35) end
        end
    end
end

function Fight:extraProps()
    local list = {}
    for _, dr in ipairs(self.drops) do
        local k = dr.t / dr.dur
        local cx, cy = G.center(dr.x, dr.y)
        if dr.x2 then local cx2, cy2 = G.center(dr.x2, dr.y2); cx, cy = (cx + cx2) / 2, (cy + cy2) / 2 end
        list[#list + 1] = { y = cy + G.T * 0.6, fn = function()
            local drop = (1 - k) ^ 2
            local name = ({ crumb = "crumb", sugar = "sugar", juice = "juice", pebble = "pebble_1", leaf = "leaf_1", stick = "stick", puddle = "puddle_1" })[dr.kind]
            love.graphics.setColor(Paper.C.ink[1], Paper.C.ink[2], Paper.C.ink[3], 0.35 * k)
            love.graphics.ellipse("fill", cx, cy + G.T * 0.3, G.T * 0.3 * k, G.T * 0.1 * k)
            love.graphics.setColor(1, 1, 1, 1)
            local rot = (dr.kind == "stick" and dr.y2 ~= dr.y) and math.pi / 2 or 0
            local scale = G.T / 200 * (dr.kind == "pebble" and 0.92 or dr.kind == "stick" and 0.98 or dr.kind == "puddle" and 1.0 or 0.8)
            Assets.tiles:draw(name, cx, cy + G.T * 0.3 - drop * 360, rot, scale)
        end }
    end
    return list
end

function Fight:drawWorld()
    local s = self.state
    BV.backdrop(STAGE_BACKDROP[self.enc.arena] or "sandbox")
    BV.arena(self.enc.arena)
    BV.coords(self.state.w)
    BV.ground(self.view, s, self.time)
    for _, a in ipairs(self.actors) do a:drawGround() end
    local hidden = self:hiddenSet()
    for _, a in ipairs(self.actors) do a.hiddenFlag = hidden[a.id] end
    BV.props(self.view, self.actors, hidden, self.time, self:extraProps())
    -- intent arrows
    local intents = self.showIntents and not self.director.playing and self.state.phase == "fight"
        and ((self.preview and self.preview.forecast) or self.forecast) or nil
    if intents then Intent.draw(self, intents, self.hover.bug, self.preview and self.preview.changed, self.time) end
    self:boardOverlays()
    for _, e in ipairs(self.effects) do e.draw(e.t / e.dur) end
    for _, a in ipairs(self.actors) do if not a.gone or a.alpha > 0.05 then a:drawBadges(self.hover.bug == a.id) end end
    if intents then Intent.drawOuts(self, intents, self.time) end
    if self.hover.bug and not self.director.playing then
        local a = self.actorById[self.hover.bug]
        if a and not a.gone then BV.actorRing(a, self.time, a.side == "kid" and "target" or "danger") end
    end
end

function Fight:draw()
    self.hits = {}      -- rebuilt by the HUD below; kept until the next draw so events that arrive after update() still see them
    local sx, sy = 0, 0
    if Fx.shakeAmount > 0.1 then sx, sy = (love.math.random() - 0.5) * Fx.shakeAmount, (love.math.random() - 0.5) * Fx.shakeAmount end
    love.graphics.push()
    love.graphics.translate(sx, sy)
    self:drawWorld()
    love.graphics.pop()

    local add = addHit(self)
    Hud.timeline(self, add, self.time)
    Hud.sunClock(self, self.time)
    Hud.rival(self, add, self.time)
    Hud.rule(self, add, self.time)
    Hud.inspector(self, add, self.time)
    Hud.jar(self, add, self.time)
    Hud.buttons(self, add, self.time)
    self:drawHandArea()
    self:drawHint()
    if self.result then self:drawResult() end
    if self.confirm then self:drawConfirm() end
    if self.intro then self:drawIntro() end
    if Fx.flash > 0 then love.graphics.setColor(1, 1, 1, Fx.flash * 0.5); love.graphics.rectangle("fill", 0, 0, 1600, 900) end
end

function Fight:drawHandArea()
    local s = self.state
    if s.phase == "deploy" then
        local w, h = 360, 120
        local x, y = 800 - w / 2, 770
        self.startRect = { x = x, y = y, w = w, h = h }
        local hov = self.mouse.x >= x and self.mouse.x <= x + w and self.mouse.y >= y and self.mouse.y <= y + h
        Paper.panel(x, y + (hov and -6 or 0), w, h, { fill = C.green, seed = 41, r = 24, rot = 0.006 })
        Text.display("START THE FIGHT!", 800, y + (hov and -6 or 0) + 30, 32, { 1, 1, 1 }, "center")
        Text.body("Pick up to 3 bugs from the Jar, put them on your two rows. Click a placed bug to take it back.", x + 16, y + 74 + (hov and -6 or 0), 12.5, { 1, 1, 1 }, "center", w - 32)
        return
    end
    self.hand:draw(self.hover.card, self.armed and self.armed.card)
    -- deck / discard counters
    local d, di = #s.deck, #s.discard
    Text.body("deck " .. d .. "  ·  discard " .. di, 262, 852, 13, { 1, 0.95, 0.8 }, "left", nil, 2)
end

function Fight:drawHint()
    local P = L.hint
    local h = self.currentHint
    local armed = self.armed
    local text, title, extra, consequence
    local dismissable = false
    if self.director.playing then
        title, text = "WATCH", "Time passes tick by tick. Hold SPACE (or click) to speed it up."
    elseif self.armedJar then
        title, text = "RELEASE", self.state.phase == "deploy" and "Click one of your two home rows." or "Click an empty tile on your two home rows. It costs time: Light 1, Medium 2, Heavy 3."
        extra = "Right click or Esc cancels."
    elseif armed then
        local def = Cards[armed.id]
        local kind = armed.stepKind
        title = def.name
        text = h and h.text or "Hover to preview: bugs that change their mind glow yellow."
        extra = (kind == "bug" and "Click a bug." or kind == "tile" and "Click a tile." or "Click an arrow.") .. " Right click or Esc cancels."
        local pv = self.preview
        if pv and pv.forecast then
            local n = 0
            for _ in pairs(pv.changed or {}) do n = n + 1 end
            local mine, theirs = 0, 0
            for _, ev in ipairs(pv.forecast.events or {}) do
                if ev.type == "scurry" or ev.type == "fall" then if ev.side == "kid" then mine = mine + 1 else theirs = theirs + 1 end end
            end
            local parts = { n == 0 and "Nobody changes their mind." or (n .. (n == 1 and " bug changes" or " bugs change") .. " what it will do!") }
            if theirs > 0 then parts[#parts + 1] = theirs .. " rival out next tick." end
            if mine > 0 then parts[#parts + 1] = mine .. " of YOURS out next tick!" end
            consequence = table.concat(parts, " ")
        end
    elseif h then
        title, text, dismissable = "PSST!", h.text, true
    elseif self.state.phase == "deploy" then
        title, text = "PICK YOUR TEAM", "Put up to 3 Jar bugs on your two home rows (the bottom two). It's free now: once the fight starts, everything you do costs time."
        extra = "Click a Jar bug, then a tile. Click a placed bug to take it back."
    elseif self.state.phase == "fight" then
        title, text = "YOUR MOVE", "Play a card, release a bug, or WAIT. Every action costs time and time lets the bugs act."
    end
    if not text then self.hintRect = nil; return end
    local size = 13
    local bodyH = Text.bodyHeight(text, size, P.w - 36)
    local consH = consequence and Text.bodyHeight(consequence, 13.5, P.w - 36) + 6 or 0
    local tall = math.max(110, math.min(210, 44 + bodyH + consH + (extra and 24 or 0) + (dismissable and 22 or 0)))
    local y = 888 - tall
    self.hintRect = dismissable and { x = P.x, y = y, w = P.w, h = tall } or nil
    local special = h ~= nil
    Paper.panel(P.x, y, P.w, tall, { fill = special and { 1, 0.95, 0.7 } or C.cream, seed = 51, r = 18, rot = -0.004, tape = special })
    Text.display(title, P.x + 18, y + 16, 14, special and C.magentaDark or C.tealDark, "left", P.w - 36)
    Text.body(text, P.x + 18, y + 42, size, Text.INK, "left", P.w - 36)
    local ey = y + 44 + bodyH + 4
    if consequence then Text.body(consequence, P.x + 18, ey, 13.5, C.magentaDark, "left", P.w - 36); ey = ey + consH end
    if extra then Text.body(extra, P.x + 18, ey, 12, { 0.15, 0.5, 0.4 }, "left", P.w - 36) end
    if dismissable then Text.body("(click to dismiss)", P.x + P.w - 18, y + tall - 24, 11, { 0.5, 0.35, 0.5 }, "right") end
end

function Fight:confirmRects()
    return { stay = { x = 480, y = 520, w = 300, h = 84 }, leave = { x = 820, y = 520, w = 300, h = 84 } }
end

function Fight:confirmClick(x, y, b)
    if b ~= 1 then self.confirm = nil; return end
    local r = self:confirmRects()
    local function inside(rc) return x >= rc.x and x <= rc.x + rc.w and y >= rc.y and y <= rc.y + rc.h end
    if inside(r.stay) then self.confirm = nil; Audio.play("ui_back") elseif inside(r.leave) then Audio.play("ui_click"); self.app.switch("title") end
end

function Fight:drawConfirm()
    love.graphics.setColor(0.17, 0.07, 0.22, 0.6)
    love.graphics.rectangle("fill", 0, 0, 1600, 900)
    Paper.panel(420, 300, 760, 330, { fill = { 0.9, 0.85, 1 }, seed = 77, r = 26, rot = -0.005, tape = true })
    Text.display("LEAVE THIS FIGHT?", 800, 340, 42, C.purple, "center")
    Text.body("You will go back to the title screen. This run is lost.", 800, 420, 19, Text.INK, "center", nil)
    local r = self:confirmRects()
    for name, rect in pairs(r) do
        local hov = self.mouse.x >= rect.x and self.mouse.x <= rect.x + rect.w and self.mouse.y >= rect.y and self.mouse.y <= rect.y + rect.h
        Paper.panel(rect.x, rect.y + (hov and -5 or 0), rect.w, rect.h, { fill = name == "stay" and C.teal or C.orange, seed = name == "stay" and 78 or 79, r = 20, rot = name == "stay" and -0.01 or 0.01 })
        Text.display(name == "stay" and "KEEP PLAYING" or "LEAVE", rect.x + rect.w / 2, rect.y + 26 + (hov and -5 or 0), 28, { 1, 1, 1 }, "center")
    end
end

function Fight:drawResult()
    local r = self.result
    local k = math.min(1, r.t * 3)
    love.graphics.setColor(0.17, 0.07, 0.22, 0.55 * k)
    love.graphics.rectangle("fill", 0, 0, 1600, 900)
    local win = r.winner == "kid"
    local y = 150 + (1 - k) * -300
    Paper.panel(420, y, 760, 420, { fill = win and { 1, 0.95, 0.7 } or { 0.9, 0.85, 1 }, seed = 61, r = 28, rot = -0.006, tape = true })
    Text.display(win and "YOU WIN!" or "YOU LOSE", 800, y + 36, 62, win and C.magenta or C.purple, "center")
    local rv = Rivals[self.state.rival.id]
    love.graphics.setColor(1, 1, 1, 1)
    Assets.drawKid(rv.portrait, win and "sad" or "happy", 580, y + 250, 210)
    local why = ({ cleared = "Every rival bug has scurried off.", crumbs = "The crumbs are home.", wiped = "All your bugs scurried off.", sun = "Dinner time! Mom's calling. The Rule's score decided it." })[r.why] or ""
    Text.body(why, 700, y + 120, 17, Text.INK, "left", 440)
    Text.body('"' .. (win and rv.line.lose or rv.line.win) .. '"', 700, y + 170, 22, C.magentaDark, "left", 440)
    -- the stakes
    local bet = self.bet
    love.graphics.setColor(1, 1, 1, 1)
    local mw, mh = Assets.ui:size("icon_marble")
    love.graphics.draw(Assets.ui.image, Assets.ui.quads.icon_marble, 716, y + 252, 0, 34 / mh, 34 / mh, mw / 2, mh / 2)
    Text.display(win and ("YOU TAKE THE POT: +" .. bet .. (bet == 1 and " MARBLE" or " MARBLES")) or ("THEY KEEP THE POT: YOUR " .. bet .. (bet == 1 and " MARBLE" or " MARBLES")),
        742, y + 241, 19, win and C.tealDark or C.magentaDark, "left", 420)
    if r.lastFight then
        Text.body("You can't cover another bet of " .. bet .. ": this was your last fight today. Rewind?", 700, y + 272, 13, C.red, "left", 440)
    end
    Text.body("Rewound " .. self.rewinds .. " time" .. (self.rewinds == 1 and "" or "s") .. ".   Ticks used: " .. self.state.tick .. ".", 700, y + 312, 13, { 0.4, 0.25, 0.5 }, "left", 440)
    local rc = self:resultRects()
    for name, rect in pairs(rc) do
        local hov = self.mouse.x >= rect.x and self.mouse.x <= rect.x + rect.w and self.mouse.y >= rect.y and self.mouse.y <= rect.y + rect.h
        Paper.panel(rect.x, rect.y + (hov and -5 or 0), rect.w, rect.h, { fill = name == "go" and C.teal or C.cream2, seed = name == "go" and 62 or 63, r = 20, rot = name == "go" and -0.01 or 0.01 })
        Text.display(name == "go" and "CONTINUE" or "REWIND", rect.x + rect.w / 2, rect.y + 26 + (hov and -5 or 0), 28, name == "go" and { 1, 1, 1 } or Text.INK, "center")
    end
end

function Fight:drawIntro()
    local t = self.intro.t
    local k = math.min(1, t / 0.45)
    local ease = 1 - (1 - k) ^ 3
    local out = t > 4.1 and (t - 4.1) / 0.4 or 0
    love.graphics.setColor(0.17, 0.07, 0.22, 0.62 * math.min(1, t / 0.3) * (1 - out))
    love.graphics.rectangle("fill", 0, 0, 1600, 900)
    local rv = Rivals[self.state.rival.id]
    local y = 230 - (1 - ease) * 560
    Paper.panel(260, y, 1080, 440, { fill = { 1, 0.95, 0.7 }, seed = 71, r = 30, rot = -0.006, tape = true })
    local node = self.run.node or 1
    Text.display("FIGHT " .. node .. " OF " .. #Run.NODES .. (self.enc.boss and "  -  THE BOSS" or ""), 320, y + 34, 18, C.magentaDark, "left")
    Text.display(self.enc.name, 320, y + 66, 54, Text.INK, "left", 560)
    Text.body(self.enc.place, 322, y + 136, 18, { 0.4, 0.25, 0.5 }, "left")
    local rule = require("data.rules")[self.state.rule.id]
    Text.display("RULE: " .. rule.name, 320, y + 190, 20, C.tealDark, "left", 560)
    Text.body(rule.long, 322, y + 226, 15, Text.INK, "left", 540)
    Text.body(self.enc.tutorial and "First time? Hints will pop up. Hover everything!" or "Click anywhere to begin.", 322, y + 380, 14, { 0.5, 0.35, 0.5 }, "left")
    -- the rival, with a speech bubble
    Paper.disc(1130, y + 220, 150, C.magenta, { seed = 5, shadow = true, line = 5 })
    Paper.disc(1130, y + 220, 138, { 1, 0.84, 0.55 }, { seed = 6, line = 0 })
    love.graphics.setColor(1, 1, 1, 1)
    Assets.drawKid(rv.portrait, "neutral", 1130, y + 232 + math.sin(t * 3) * 3, 300)
    Paper.panel(930, y - 36, 360, 76, { fill = C.cream, seed = 8, r = 20, rot = 0.01 })
    Text.display(rv.name, 950, y - 24, 12, C.magentaDark, "left", 320)
    Text.body('"' .. rv.line.start .. '"', 950, y + 1, 17, Text.INK, "left", 320)
    -- the stakes
    love.graphics.setColor(1, 1, 1, 1)
    local mw, mh = Assets.ui:size("icon_marble")
    love.graphics.draw(Assets.ui.image, Assets.ui.quads.icon_marble, 1004, y + 398, 0, 36 / mh, 36 / mh, mw / 2, mh / 2)
    Text.display("POT: " .. (2 * self.bet) .. " MARBLES", 1030, y + 386, 22, C.magentaDark, "left", 290)
    Text.body(rv.name .. " bets " .. self.bet .. ", and so do you.", 1030, y + 412, 12.5, { 0.4, 0.25, 0.5 }, "left", 300)
end

function Fight:drawCursor(x, y, time)
    love.graphics.setColor(1, 1, 1, 1)
    if self.armed then
        local def = Cards[self.armed.id]
        local w, h = Assets.ui:size("card_" .. def.art)
        local s = 54 / math.max(w, h)
        love.graphics.draw(Assets.ui.image, Assets.ui.quads["card_" .. def.art], x + 34, y + 36, 0, s, s, w / 2, h / 2)
    end
    local press = love.mouse.isDown(1) and 0.9 or 1
    Assets.people:draw("hand_point", x, y, 0, 0.3 * press)
end

return { new = Fight.new, class = Fight }
