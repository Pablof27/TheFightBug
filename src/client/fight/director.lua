-- The Director replays simulation events as animation, sound and particles. The simulation has already finished the whole
-- action when the events arrive; the Director walks through them one by one (each handler returns how long to wait before
-- the next one) so the player can follow what happened, in order, at a readable pace.

local Tween = require("client.tween")
local Audio = require("client.audio")
local Fx = require("client.fx")
local Paper = require("client.paper")
local Actor = require("client.fight.actor")
local G = require("client.fight.geometry")
local Grid = require("sim.grid")
local Bugs = require("data.bugs")

local Director = {}
Director.__index = Director

local C = Paper.C

function Director.new(scene)
    return setmetatable({ scene = scene, queue = {}, wait = 0, speed = 1, playing = false }, Director)
end

function Director:push(events)
    for _, ev in ipairs(events) do self.queue[#self.queue + 1] = ev end
    self.playing = #self.queue > 0
end

function Director:busy() return self.playing end

function Director:clear()
    self.queue, self.wait, self.playing = {}, 0, false
end

function Director:update(dt)
    if not self.playing then return end
    self.wait = self.wait - dt * self.speed
    local guard = 0
    while self.wait <= 0 and #self.queue > 0 and guard < 200 do
        guard = guard + 1
        local ev = table.remove(self.queue, 1)
        local h = self.H[ev.type]
        local d = h and h(self, ev) or 0
        self.wait = self.wait + (d or 0)
    end
    if #self.queue == 0 and self.wait <= 0 then
        self.playing = false
        self.scene:onPlaybackDone()
    end
end

-- ───────────────────────── helpers ─────────────────────────
local function actorOf(d, id) return d.scene.actorById[id] end

local function head(a)
    local x, y = G.foot(a.x, a.y)
    return x, y - a:height() * G.T * 0.95
end

local function body(a)
    local x, y = G.foot(a.x, a.y)
    return x, y - a:height() * G.T * 0.5
end

local function squash(a, sx, sy, dur)
    a.sx, a.sy = sx, sy
    Tween.to(a, { sx = 1, sy = 1 }, dur or 0.25, "outBack")
end

local function bounce(a, dxp, dyp, amount, dur)
    local len = math.sqrt(dxp * dxp + dyp * dyp)
    if len < 0.001 then return end
    local ox, oy = dxp / len * amount, dyp / len * amount
    Tween.to(a, { offx = ox, offy = oy }, dur * 0.4, "outQuad", function() Tween.to(a, { offx = 0, offy = 0 }, dur * 0.6, "outBack") end)
end

local function pixelVector(ax, ay, bx, by)
    local x1, y1 = G.center(ax, ay)
    local x2, y2 = G.center(bx, by)
    return x2 - x1, y2 - y1
end

-- ───────────────────────── event handlers ─────────────────────────
local H = {}
Director.H = H

function H.tick(d, ev)
    d.scene.disp.tick = ev.n
    Audio.play("tick", 0.7)
    d.scene.disp.tickPulse = 1
    return 0.2
end

function H.timers(d, ev)
    for _, e in ipairs(ev.list) do
        local a = actorOf(d, e.id)
        if a and a.timer ~= e.timer then a.timer = e.timer; a.pulse = 1 end
    end
    if ev.rival then d.scene.disp.rivalTimer = ev.rival end
    return 0
end

function H.act(d, ev)
    local a = actorOf(d, ev.id)
    if not a then return 0 end
    if ev.to then a:face(a.x, ev.to.x) end
    if ev.kind == "ready" or ev.kind == "idle" or ev.kind == "rest" then return 0 end
    a.pulse = 0.6
    if ev.mode == "fly" and ev.kind ~= "idle" then Audio.play("buzz", 0.5) end
    return ev.react and 0.05 or 0.08
end

function H.move(d, ev)
    local a = actorOf(d, ev.id)
    if not a then return 0 end
    if ev.snap then a:place(ev.x, ev.y); return 0 end
    a:face(ev.fx, ev.x)
    local dur = ev.mode == "charge" and 0.17 or ev.mode == "fly" and 0.2 or ev.mode == "jump" and 0.34 or 0.27
    a.hopT = 0
    if ev.mode == "jump" then a.hopH = G.T * 0.75; Audio.play("hop", 0.6)
    elseif ev.mode == "fly" then a.hopH = 0
    elseif ev.mode == "charge" then a.hopH = 3; local x, y = G.foot(a.x, a.y); Fx.puff(x, y, 2, 0.16); Audio.play("step", 0.8)
    else a.hopH = 6 * G.unit; Audio.play("step", 0.45) end
    if ev.mode ~= "fly" then a:setAnim("walk", dur + 0.05) end
    Tween.to(a, { x = ev.x, y = ev.y }, dur, "inOutQuad")
    Tween.to(a, { hopT = 1 }, dur, "linear", function() a.hopT = 0 end)
    return dur
end

function H.attack(d, ev)
    local s, t = actorOf(d, ev.src), actorOf(d, ev.dst)
    if not s then return 0 end
    local species = s.species
    if t then s:face(s.x, t.x) end
    s.actPhase = false
    s:setAnim("act", 0.5)
    Tween.after(0.1, function() s.actPhase = true end)
    if t then
        local vx, vy = pixelVector(s.x, s.y, t.x, t.y)
        bounce(s, vx, vy, G.T * 0.32, 0.3)
    end
    local snd = ev.kind == "ram" and "ram" or ev.kind == "strike" and "strike" or (species == "wasp" and "sting" or "bite")
    Tween.after(0.1, function() Audio.play(snd) end)
    return 0.2
end

function H.damage(d, ev)
    local a = actorOf(d, ev.id)
    if not a then return 0 end
    a.hp = ev.hp
    a:flashNow({ 1, 0.35, 0.35 }, 1)
    a:setAnim("hurt", 0.4)
    local x, y = body(a)
    Fx.pow(x, y, 0.45)
    Fx.text("-" .. ev.amount, x, y - G.T * 0.5, C.red, 30)
    Fx.shake(5)
    return 0.3
end

function H.blocked(d, ev)
    local a = actorOf(d, ev.id)
    if not a then return 0 end
    Audio.play("block")
    a:flashNow({ 1, 1, 1 }, 0.8)
    local x, y = head(a)
    Fx.text("NOPE!", x, y, C.yellow, 22)
    return 0.2
end

function H.curl(d, ev)
    local a = actorOf(d, ev.id)
    if not a then return 0 end
    a.curled = true
    squash(a, 1.25, 0.7, 0.3)
    Audio.play("curl")
    local x, y = head(a)
    Fx.text("CURL!", x, y, C.blue, 24)
    return 0.3
end

function H.uncurl(d, ev)
    local a = actorOf(d, ev.id)
    if a then a.curled = false; a.rot, a.spin = 0, 0; squash(a, 0.8, 1.2, 0.2) end
    return 0.1
end

function H.scurry(d, ev)
    local a = actorOf(d, ev.id)
    if not a then return 0 end
    a.gone = true
    Audio.play("scurry")
    local x, y = head(a)
    Fx.text("SCURRY!", x, y, ev.side == "kid" and C.teal or C.magenta, 26)
    Fx.sprite("fx_sweat", x + 18, y + 14, { vx = 20, vy = -60, gravity = 160, life = 0.5, s0 = 0.3, s1 = 0.3 })
    a:setAnim("walk", 1)
    local ty = ev.side == "kid" and a.y - 2.4 or a.y + 2.4
    a.facing = a.side == "kid" and -1 or 1
    a.hopH = 5 * G.unit
    Tween.to(a, { y = ty, sx = 1.15 }, 0.55, "inQuad")
    Tween.to(a, { hopT = 1 }, 0.2, "linear")
    Tween.after(0.3, function() Tween.to(a, { alpha = 0 }, 0.25, "linear", function() a.dead = true end) end)
    return 0.5
end

function H.fall(d, ev)
    local a = actorOf(d, ev.id)
    if not a then return 0 end
    a.gone = true
    Audio.play("fall")
    local x, y = head(a)
    Fx.text("WHEEE!", x, y, C.yellow, 26)
    Tween.to(a, { x = a.x + ev.dx * 0.9, y = a.y + ev.dy * 0.9, sx = 0.35, sy = 0.35, rot = a.rot + (ev.dx >= 0 and 4 or -4), alpha = 0 }, 0.6, "inQuad", function() a.dead = true end)
    Fx.shake(3)
    return 0.55
end

function H.push(d, ev)
    local a = actorOf(d, ev.id)
    if not a then return 0 end
    local dur = ev.cause == "roll" and 0.1 or 0.2
    if ev.cause == "flick" or ev.cause == "shove" or ev.cause == "blow" then a:setAnim("hurt", 0.25) end
    a.hopT = 0
    a.hopH = ev.cause == "roll" and 0 or G.T * 0.22
    Tween.to(a, { x = ev.x, y = ev.y }, dur, "outQuad")
    Tween.to(a, { hopT = 1 }, dur, "linear", function() a.hopT = 0 end)
    local x, y = G.foot(a.x, a.y)
    if ev.cause ~= "roll" then Fx.puff(x, y, 2, 0.14) end
    return dur
end

function H.rollstart(d, ev)
    local a = actorOf(d, ev.id)
    if a then a.spin = (ev.dx > 0 or ev.dy < 0) and 14 or -14 end
    Audio.play("roll")
    return 0.05
end

function H.bump(d, ev)
    local a = actorOf(d, ev.id)
    local other = ev.other and actorOf(d, ev.other)
    if a then
        a.spin = 0; a.rot = 0
        bounce(a, ev.dx, -ev.dy, G.T * 0.2, 0.3)
        local x, y = head(a)
        Fx.stars(x, y, 3)
        Fx.text("BUMP!", x, y - 10, C.orange, 26)
    end
    if other then
        bounce(other, -ev.dx, ev.dy, G.T * 0.2, 0.3)
        local x, y = head(other)
        Fx.stars(x, y, 3)
    end
    Audio.play("bump")
    Fx.shake(6)
    return 0.32
end

function H.flip(d, ev)
    local a = actorOf(d, ev.id)
    if not a then return 0 end
    a.flipped = true
    a.hopT, a.hopH = 0, G.T * 0.5
    Tween.to(a, { hopT = 1 }, 0.35, "linear", function() a.hopT = 0 end)
    Audio.play("flip")
    local x, y = head(a)
    Fx.text("FLIPPED!", x, y, C.magenta, 24)
    return 0.35
end

function H.getup(d, ev)
    local a = actorOf(d, ev.id)
    if not a then return 0 end
    a.flipped = false
    a.hopT, a.hopH = 0, G.T * 0.3
    Tween.to(a, { hopT = 1 }, 0.25, "linear", function() a.hopT = 0 end)
    Audio.play("getup")
    local x, y = head(a)
    Fx.text("UP!", x, y, C.green, 22)
    return 0.3
end

function H.resist(d, ev)
    local a = actorOf(d, ev.id)
    if not a then return 0 end
    Audio.play("block", 0.7)
    local x, y = head(a)
    Fx.text("HEAVY!", x, y, C.purpleLight, 22)
    squash(a, 0.9, 1.1, 0.2)
    return 0.2
end

local WHY = { bump = "DAZED", stomp = "STOMPED", shadow = "SHADE", soak = "SOAKED", tap = "FROZEN", sun = "SUNNY", chirp = "CHIRP", alarm = "ALARM", shade = "SHADE" }
function H.timer(d, ev)
    local a = actorOf(d, ev.id)
    if not a then return 0 end
    if a.timer ~= ev.timer then a.pulse = 1 end
    a.timer = ev.timer
    a.ready = (ev.timer == 0) and a.ready
    if ev.reset then return 0 end
    local x, y = head(a)
    local plus = ev.delta > 0
    Fx.text((plus and "+" or "") .. ev.delta, x + G.T * 0.32, y - 24, plus and C.magenta or C.green, 22, { life = 1.0 })
    if ev.why == "bump" or ev.why == "tap" then Audio.play("daze", 0.5) end
    return 0.1
end

function H.soak(d, ev)
    local a = actorOf(d, ev.id)
    if not a then return 0 end
    a.soaked = true
    local x, y = G.foot(a.x, a.y)
    Fx.drops(x, y, 6)
    Audio.play("splash")
    local hx, hy = head(a)
    Fx.text("SOAKED!", hx, hy, C.blue, 22)
    return 0.3
end

local function setFood(d, x, y, food)
    local c = d.scene.view.cells[Grid.key(x, y)]
    if c then c.food = food end
end

function H.eat(d, ev)
    local a = actorOf(d, ev.id)
    setFood(d, ev.x, ev.y, nil)
    if a then
        squash(a, 1.2, 0.85, 0.3)
        local x, y = head(a)
        Fx.text("NOM!", x, y, C.yellow, 22)
        local fx, fy = G.foot(ev.x, ev.y)
        Fx.puff(fx, fy, 3, 0.12)
    end
    Audio.play("eat")
    return 0.3
end

function H.sip(d, ev)
    local a = actorOf(d, ev.id)
    if a then
        squash(a, 1.12, 0.92, 0.3)
        local x, y = head(a)
        Fx.text("GLUG", x, y, C.orange, 20)
    end
    Audio.play("eat", 0.6, 0.8)
    return 0.25
end

function H.pickup(d, ev)
    local a = actorOf(d, ev.id)
    setFood(d, ev.x, ev.y, nil)
    if a then a.carrying = true; squash(a, 1.15, 0.9, 0.25) end
    Audio.play("pickup")
    local x, y = G.foot(ev.x, ev.y)
    Fx.sparkle(x, y - 20, 4)
    return 0.2
end

function H.drop(d, ev)
    local a = actorOf(d, ev.id)
    if a then a.carrying = false end
    setFood(d, ev.x, ev.y, { kind = ev.food })
    return 0.05
end

function H.loot(d, ev)
    setFood(d, ev.x, ev.y, { kind = "loot" })
    local x, y = G.foot(ev.x, ev.y)
    Fx.sparkle(x, y - 24, 6)
    Fx.puff(x, y, 2, 0.14)
    Audio.play("spawn", 0.5)
    return 0.1
end

function H.deliver(d, ev)
    local a = actorOf(d, ev.id)
    if a then a.carrying = false; squash(a, 1.2, 0.85, 0.3) end
    d.scene.disp.score[ev.side] = ev.score
    d.scene.disp.scorePulse[ev.side] = 1
    Audio.play("deliver")
    local x, y = G.foot(ev.x, ev.y)
    Fx.text("+1 CRUMB!", x, y - G.T * 0.9, ev.side == "kid" and C.teal or C.magenta, 26)
    Fx.sparkle(x, y - 30, 8, 30)
    return 0.4
end

function H.rest(d, ev)
    local a = actorOf(d, ev.id)
    if not a then return 0 end
    local healed = ev.hp > a.hp
    a.hp = ev.hp
    local x, y = head(a)
    Fx.sprite("fx_zzz", x + 20, y, { vy = -30, life = 0.9, s0 = 0.25, s1 = 0.3 })
    if healed then Fx.sprite("fx_heart", x - 10, y + 10, { vy = -50, life = 0.8, s0 = 0.18, s1 = 0.22 }); Fx.text("+1", x, y - 16, C.red, 22) end
    return 0.35
end

function H.chirp(d, ev)
    local a = actorOf(d, ev.id)
    if not a then return 0 end
    a:setAnim("alt", 0.7)
    Audio.play("chirp")
    local x, y = head(a)
    Fx.notes(x, y, 3)
    local bx, by = body(a)
    Fx.ring(bx, by, 10, G.T * 2.2, C.yellow, 0.6, 5)
    return 0.5
end

function H.alarm(d, ev)
    local a = actorOf(d, ev.id)
    Audio.play("alarm")
    if a then local x, y = head(a); Fx.sprite("fx_exclaim", x, y - 10, { vy = -20, life = 0.8, s0 = 0.4, s1 = 0.46 }) end
    for _, id in ipairs(ev.others or {}) do
        local o = actorOf(d, id)
        if o then local x, y = head(o); Fx.sprite("fx_exclaim", x, y - 10, { vy = -20, life = 0.8, s0 = 0.34, s1 = 0.4, delay = 0.15 }) end
    end
    return 0.3
end

function H.ready(d, ev)
    local a = actorOf(d, ev.id)
    if a then
        a.ready = true
        squash(a, 0.9, 1.15, 0.3)
        local x, y = head(a)
        Fx.sparkle(x, y, 4, 24)
    end
    Audio.play("ready")
    return 0.25
end

function H.spawn(d, ev)
    local bug = d.scene.state and require("sim.state").byId(d.scene.state, ev.id)
    if not bug then return 0 end
    local a = Actor.new(bug)
    a:place(ev.x, ev.y)
    a.sx, a.sy, a.alpha = 0.1, 0.1, 1
    d.scene:addActor(a)
    Tween.to(a, { sx = 1, sy = 1 }, 0.35, "outBack")
    local x, y = G.foot(ev.x, ev.y)
    Fx.puff(x, y, 4, 0.2)
    Fx.sparkle(x, y - 30, 4, 20)
    Audio.play("spawn")
    return 0.35
end

function H.place(d, ev)
    local kind = ev.kind
    local x, y = G.center(ev.x, ev.y)
    Audio.play(kind == "puddle" and "water" or "place", 0.9)
    local apply = function()
        local cells = d.scene.view.cells
        local c = cells[Grid.key(ev.x, ev.y)]
        if kind == "crumb" or kind == "sugar" or kind == "juice" then c.food = { kind = kind }
        elseif kind == "pebble" then c.block = "pebble"
        elseif kind == "leaf" then c.cover = "leaf"
        elseif kind == "stick" then
            c.block = "stick"; c.stick = { x2 = ev.x2, y2 = ev.y2, first = true }
            local c2 = cells[Grid.key(ev.x2, ev.y2)]
            c2.block = "stick"; c2.stick = { x2 = ev.x, y2 = ev.y }
        elseif kind == "puddle" then
            c.puddle = true
            cells[Grid.key(ev.x2, ev.y2)].puddle = true
        end
        local fx, fy = G.foot(ev.x, ev.y)
        Fx.puff(fx, fy, 3, 0.16)
        if kind == "puddle" then Fx.drops(fx, fy, 6) end
        Fx.shake(2)
    end
    d.scene:dropItem(kind, ev, apply)
    return 0.4
end

function H.area(d, ev)
    local cx, cy = G.center(ev.x, ev.y)
    if ev.kind == "sun" then
        Audio.play("sun")
        Fx.ring(cx, cy, 10, G.T * 1.8, C.yellow, 0.6, 7)
        Fx.sparkle(cx, cy, 10, G.T)
    else
        Audio.play("tap")
        Fx.ring(cx, cy, 10, G.T * 1.8, C.purpleLight, 0.5, 7)
        Fx.ring(cx, cy, 6, G.T * 1.2, C.cream, 0.5, 5)
        Fx.puff(cx, cy + G.T * 0.2, 4, 0.2)
        Fx.shake(4)
    end
    d.scene:glowArea(ev.x, ev.y, ev.kind)
    return 0.4
end

function H.blow(d, ev)
    Audio.play("blow")
    local x, y = G.center(ev.x, ev.y)
    for i = 1, 8 do
        local px, py = x, y
        local off = (i - 4.5) * G.T * 0.6
        if ev.dx ~= 0 then px = G.x + (ev.dx > 0 and 0 or G.size) + (ev.dx > 0 and 1 or -1) * i * 4; py = y + love.math.random(-18, 18)
        else px = x + love.math.random(-18, 18); py = G.y + (ev.dy > 0 and G.size or 0) + (ev.dy > 0 and -1 or 1) * i * 4 end
        Fx.sprite("fx_puff", px, py, { vx = ev.dx * 640, vy = -ev.dy * 640, life = 0.45, s0 = 0.16, s1 = 0.3, a0 = 0.7, delay = i * 0.03 })
    end
    return 0.35
end

function H.hand(d, ev)
    local a = ev.id and actorOf(d, ev.id)
    if ev.card == "shadow" then
        Audio.play("shadow")
        if a then d.scene:handShadow(a) end
        return 0.45
    end
    Audio.play("flick")
    if a then d.scene:handFlick(a, ev.dx or 1, ev.dy or 0) end
    return 0.3
end

function H.card(d, ev)
    Audio.play("card_play", 0.8)
    return 0.1
end

function H.wait(d, ev) return 0 end
function H.release(d, ev) return 0 end
function H.start(d, ev) return 0 end

function H.rival_act(d, ev)
    local s = d.scene
    s.rivalAnim = 1
    if ev.kind == "stomp" then
        Audio.play("stomp")
        s:stompAt(ev.x, ev.y)
        return 0.75
    end
    Audio.play("alarm", 0.5, 0.7)
    local sig = require("data.rivals")[s.state.rival.id].sig
    Fx.text(sig.name .. "!", 210, 300, C.magenta, 30)
    return 0.45
end

function H.rival_timer(d, ev)
    d.scene.disp.rivalTimer = ev.timer
    return 0
end

function H.draw(d, ev)
    Audio.play("draw", 0.7)
    return 0.06
end

function H.shuffle(d, ev) return 0.1 end

H["end"] = function(d, ev)
    d.scene:onFightEnd(ev)
    return 0.4
end

return Director
