-- Resolver: applies intents and card effects to the state. Every change is announced with an event
-- (State.emit) so the presentation layer can replay what happened, step by step.
--
-- Event types emitted here (all carry `type` and `tick`):
--   act{id,kind,...}  move{id,fx,fy,x,y,mode,pass}  attack{src,dst,kind,dmg}  damage{id,amount,hp}  blocked{id}  curl{id} uncurl{id}
--   scurry{id}  fall{id,x,y,dx,dy}  push{id,fx,fy,x,y,cause}  bump{id,other,x,y,dx,dy}  flip{id}  getup{id}  resist{id}
--   timer{id,timer,delta,why}  soak{id}  eat{id,x,y,food}  sip{id}  pickup{id}  drop{x,y}  deliver{id,side,score}  rest{id,hp}
--   chirp{id,ids}  alarm{id,others}  ready{id}  rollstart{id,dx,dy}  spawn{id,species,side,x,y}

local U = require("sim.util")
local Grid = require("sim.grid")
local State = require("sim.state")
local Q = require("sim.query")
local Path = require("sim.path")

local R = {}

R.TRAIL_TTL = 6

-- ───────────────────────── timers ─────────────────────────

--- A bug's timer after it acted: its base, +1 in shade, -1 in sun (never below 0: at the soonest it acts on the next tick).
function R.resetTimer(s, bug)
    local mod, why = 0, "reset"
    local c = Grid.cell(s, bug.x, bug.y)
    if c and c.light == "shade" then mod, why = 1, "shade"
    elseif c and c.light == "sun" then mod, why = -1, "sun" end
    bug.timer = math.max(0, bug.baseTimer + mod)
    State.emit(s, "timer", { id = bug.id, timer = bug.timer, delta = bug.timer, why = why, reset = true })
end

--- +delay hits anything (a Ready ambusher loses its readiness); speed-ups never go below 0 (the bug acts on the next tick,
--- never "now") and never wake a Ready bug. A bug that is due this tick (-1) or Ready and gets +N acts N ticks later.
function R.addTimer(s, bug, delta, why)
    if bug.gone then return end
    if delta < 0 then
        if bug.ready or bug.timer <= 0 then return end
        bug.timer = math.max(0, bug.timer + delta)
    else
        if bug.ready then
            bug.ready = false
            bug.timer = -1      -- Ready means "would act right now": +1 makes it act on the next tick
        end
        bug.timer = bug.timer + delta
    end
    State.emit(s, "timer", { id = bug.id, timer = math.max(0, bug.timer), delta = delta, why = why })
end

-- ───────────────────────── arrival / reactions ─────────────────────────

--- Called whenever a bug has landed on a tile (walked, pushed, released…): puddles soak walkers.
function R.arrive(s, b)
    local c = Grid.cell(s, b.x, b.y)
    local inWater = c and c.puddle and c.cover ~= "leaf" and b.mtype ~= "fly"
    if inWater and not b.soaked then
        b.soaked = true
        State.emit(s, "soak", { id = b.id, x = b.x, y = b.y })
        R.addTimer(s, b, 2, "soak")
    elseif not inWater then
        b.soaked = false
    end
end

--- A Ready ambusher next to (x, y) strikes whoever just got there — even in the middle of a move.
function R.reactionsAt(s, mover, x, y)
    local list = {}
    for _, a in ipairs(s.bugs) do
        if a.ready and a ~= mover and a.side ~= mover.side and Grid.adjacent(a.x, a.y, x, y) then list[#list + 1] = a end
    end
    table.sort(list, Q.byOrder)
    for _, a in ipairs(list) do
        if mover.gone then return end
        if a.ready and not a.gone then R.strike(s, a, mover) end
    end
end

function R.reactions(s, mover)
    if mover.gone then return end
    R.reactionsAt(s, mover, mover.x, mover.y)
    if mover.gone then return end
    if mover.ready then
        local adj = Q.adjacentEnemies(s, mover)
        if #adj > 0 then R.strike(s, mover, Q.weakest(adj)) end
    end
end

--- Ready ambushers that already have an enemy next to them (it can happen after pushes) strike at the start of a tick.
function R.sweepReady(s)
    for _, a in ipairs(Q.timeline(s)) do
        if a.ready and not a.gone then
            local adj = Q.adjacentEnemies(s, a)
            if #adj > 0 then R.strike(s, a, Q.weakest(adj)) end
        end
    end
end

function R.strike(s, a, target)
    State.emit(s, "act", { id = a.id, kind = "attack", mode = "walk", target = { kind = "bug", id = target.id }, react = true })
    a.ready = false
    R.attack(s, a, target, a.bite, "strike")
    if not a.gone then R.resetTimer(s, a) end
end

-- ───────────────────────── damage ─────────────────────────

function R.alarm(s, b)
    local hit = {}
    for _, o in ipairs(s.bugs) do
        if o ~= b and o.side == b.side and o.traits.alarm then
            R.addTimer(s, o, -1, "alarm")
            hit[#hit + 1] = o.id
        end
    end
    State.emit(s, "alarm", { id = b.id, others = hit })
end

function R.scurry(s, b, why)
    if b.gone then return end
    if b.carrying then
        local c = Grid.cell(s, b.x, b.y)
        if c and not c.food then
            c.food = { kind = b.carrying.kind }
            State.emit(s, "drop", { id = b.id, x = b.x, y = b.y, food = b.carrying.kind })
        end
        b.carrying = nil
    end
    State.emit(s, "scurry", { id = b.id, x = b.x, y = b.y, why = why, side = b.side })
    s.stats.scurried[b.side] = s.stats.scurried[b.side] + 1
    State.markLost(s, b)
    State.removeBug(s, b)
end

function R.damage(s, b, amount, src, kind)
    if amount <= 0 or b.gone then return 0 end
    if b.curled then
        State.emit(s, "blocked", { id = b.id, by = src and src.id })
        return 0
    end
    if b.traits.curl then
        b.curled = true
        State.emit(s, "curl", { id = b.id, by = src and src.id })
        return 0
    end
    b.hp = b.hp - amount
    State.emit(s, "damage", { id = b.id, amount = amount, hp = math.max(0, b.hp), by = src and src.id, kind = kind })
    if b.traits.alarm then R.alarm(s, b) end
    if b.hp <= 0 then R.scurry(s, b, "ko") end
    return amount
end

--- An attack: damage, or (in Mushi-Zumo) a 1-tile shove. `kind` = bite | ram | strike.
function R.attack(s, src, dst, dmg, kind, dx, dy)
    if src.gone or dst.gone then return end
    dx = dx or U.sign(dst.x - src.x)
    dy = dy or U.sign(dst.y - src.y)
    State.emit(s, "attack", { src = src.id, dst = dst.id, kind = kind, dmg = dmg, dx = dx, dy = dy })
    if s.rule and s.rule.attackMode == "push" then
        -- sumo: no damage, the shove flings the target as many tiles as the shover is heavy
        R.push(s, dst, dx, dy, "shove", src, src.weight)
    else
        R.damage(s, dst, dmg, src, kind)
        if kind == "ram" and not dst.gone then R.push(s, dst, dx, dy, "ram", src) end
    end
    if kind == "ram" and src.traits.wrestler and not dst.gone and dst.weight < src.weight and not dst.curled then R.flip(s, dst) end
end

function R.flip(s, b)
    b.flipped = true
    if b.ready then b.ready = false; b.timer = 0 end
    State.emit(s, "flip", { id = b.id })
end

-- ───────────────────────── pushes ─────────────────────────

function R.bump(s, b, other, dx, dy)
    State.emit(s, "bump", { id = b.id, other = other and other.id or nil, x = b.x, y = b.y, dx = dx, dy = dy })
    R.addTimer(s, b, 1, "bump")
    if other then R.addTimer(s, other, 1, "bump") end
end

function R.fall(s, b, x, y, dx, dy)
    State.emit(s, "fall", { id = b.id, x = b.x, y = b.y, dx = dx, dy = dy, side = b.side })
    s.stats.fell[b.side] = s.stats.fell[b.side] + 1
    b.carrying = nil
    State.markLost(s, b)
    State.removeBug(s, b)
end

--- Slide up to n tiles. Hitting a wall, an obstacle or another bug is a Bump (everybody involved is Dazed); no damage, ever.
function R.slide(s, b, dx, dy, n, cause)
    for _ = 1, n do
        if b.gone then return "gone" end
        local nx, ny = b.x + dx, b.y + dy
        local c = Grid.cell(s, nx, ny)
        if c == nil or c.void then
            if s.openEdges then R.fall(s, b, nx, ny, dx, dy); return "fell" end
            R.bump(s, b, nil, dx, dy)
            return "bump"
        end
        local other = State.at(s, nx, ny)
        if other then R.bump(s, b, other, dx, dy); return "bump" end
        if not Path.canEnter(s, b, nx, ny, { pushed = true }) then R.bump(s, b, nil, dx, dy); return "bump" end
        local fx, fy = b.x, b.y
        State.moveBug(s, b, nx, ny)
        State.emit(s, "push", { id = b.id, fx = fx, fy = fy, x = nx, y = ny, cause = cause })
        R.arrive(s, b)
        R.reactions(s, b)
        if b.gone then return "gone" end
    end
    return "moved"
end

function R.roll(s, b, dx, dy)
    State.emit(s, "rollstart", { id = b.id, dx = dx, dy = dy })
    local moved = false
    for _ = 1, 12 do
        local r = R.slide(s, b, dx, dy, 1, "roll")
        if r ~= "moved" then return moved end
        moved = true
    end
    return moved
end

--- Push a bug n tiles (default 1). A pusher can only push targets of the same weight or lighter. Curled bugs roll until they hit something.
function R.push(s, b, dx, dy, cause, pusher, n)
    if b.gone then return false end
    if pusher and b.weight > pusher.weight then
        State.emit(s, "resist", { id = b.id, by = pusher.id })
        return false
    end
    if b.curled then return R.roll(s, b, dx, dy) end
    return R.slide(s, b, dx, dy, n or 1, cause) == "moved"
end

-- ───────────────────────── activations ─────────────────────────

local function markTrail(s, bug, x, y)
    if bug.traits.trail then Grid.cell(s, x, y).trail = { side = bug.side, ttl = R.TRAIL_TTL } end
end

-- Walkers squeeze past friends (a "pass" step: the bug is only over that tile in passing) but stop for enemies.
local function walkSteps(s, bug, it)
    local lx, ly = bug.x, bug.y
    for i, p in ipairs(it.path) do
        local other = State.at(s, p.x, p.y)
        if other and other ~= bug then
            if other.side ~= bug.side or i == #it.path then break end
            local c = Grid.cell(s, p.x, p.y)
            if not c or c.void then break end
            State.emit(s, "move", { id = bug.id, fx = lx, fy = ly, x = p.x, y = p.y, mode = it.mode, pass = true })
            markTrail(s, bug, p.x, p.y)
            R.reactionsAt(s, bug, p.x, p.y)
            if bug.gone then return false end
        else
            if not Path.canEnter(s, bug, p.x, p.y) then break end
            State.moveBug(s, bug, p.x, p.y)
            State.emit(s, "move", { id = bug.id, fx = lx, fy = ly, x = p.x, y = p.y, mode = it.mode })
            markTrail(s, bug, p.x, p.y)
            R.arrive(s, bug)
            R.reactions(s, bug)
            if bug.gone then return false end
        end
        lx, ly = p.x, p.y
    end
    if lx ~= bug.x or ly ~= bug.y then   -- could not land where planned: settle back on the real tile
        State.emit(s, "move", { id = bug.id, fx = lx, fy = ly, x = bug.x, y = bug.y, mode = it.mode, snap = true })
    end
    return true
end

local function flySteps(s, bug, it)
    local lx, ly = bug.x, bug.y
    for i, p in ipairs(it.path) do
        local last = (i == #it.path)
        if last and not Path.canLand(s, bug, p.x, p.y) then break end
        State.emit(s, "move", { id = bug.id, fx = lx, fy = ly, x = p.x, y = p.y, mode = "fly", pass = not last })
        if last then
            State.moveBug(s, bug, p.x, p.y)
            R.arrive(s, bug)
            R.reactions(s, bug)
        else
            R.reactionsAt(s, bug, p.x, p.y)
        end
        if bug.gone then return false end
        lx, ly = p.x, p.y
    end
    return true
end

local function jumpStep(s, bug, it)
    local p = it.path[#it.path]
    if not Path.canLand(s, bug, p.x, p.y) then return true end
    local fx, fy = bug.x, bug.y
    State.moveBug(s, bug, p.x, p.y)
    State.emit(s, "move", { id = bug.id, fx = fx, fy = fy, x = p.x, y = p.y, mode = "jump" })
    R.arrive(s, bug)
    R.reactions(s, bug)
    return not bug.gone
end

local function doAction(s, bug, it)
    local a = it.action
    local k = a.kind
    if k == "bite" then
        local t = State.byId(s, a.target)
        if t and Path.inReach(s, bug, bug.x, bug.y, t) then R.attack(s, bug, t, a.dmg, "bite") end
    elseif k == "strike" then
        local t = State.byId(s, a.target)
        if t and Grid.adjacent(bug.x, bug.y, t.x, t.y) then R.attack(s, bug, t, a.dmg, "strike") end
    elseif k == "ram" then
        local t = State.byId(s, a.target)
        if t and Grid.adjacent(bug.x, bug.y, t.x, t.y) then
            R.attack(s, bug, t, a.dmg, "ram", U.sign(t.x - bug.x), U.sign(t.y - bug.y))
        end
    elseif k == "eat" or k == "sip" then
        local c = Grid.cell(s, bug.x, bug.y)
        if c.food and bug.likes[c.food.kind] then
            State.emit(s, k, { id = bug.id, x = bug.x, y = bug.y, food = c.food.kind })
            if k == "eat" then c.food = nil end
        end
    elseif k == "pickup" then
        local c = Grid.cell(s, bug.x, bug.y)
        if c.food and c.food.kind == "loot" then
            c.food = nil
            bug.carrying = { kind = "loot" }
            State.emit(s, "pickup", { id = bug.id, x = bug.x, y = bug.y })
        end
    elseif k == "deliver" then
        if bug.carrying and Grid.isHomeRow(s, bug.side, bug.y) then
            bug.carrying = nil
            s.rule.score[bug.side] = s.rule.score[bug.side] + 1
            State.emit(s, "deliver", { id = bug.id, side = bug.side, score = s.rule.score[bug.side], x = bug.x, y = bug.y })
        end
    elseif k == "rest" then
        if bug.hp < bug.maxHp then bug.hp = bug.hp + 1 end
        State.emit(s, "rest", { id = bug.id, hp = bug.hp })
    elseif k == "chirp" then
        local ids = {}
        for _, o in ipairs(s.bugs) do
            if o ~= bug and o.side == bug.side and Grid.manhattan(o.x, o.y, bug.x, bug.y) <= 2 then ids[#ids + 1] = o.id end
        end
        State.emit(s, "chirp", { id = bug.id, ids = ids })
        for _, id in ipairs(ids) do
            local o = State.byId(s, id)
            if o then R.addTimer(s, o, -1, "chirp") end
        end
    end
end

--- Executes an intent: wake up, move step by step (reactions may interrupt), act, reset the timer.
function R.perform(s, bug, it)
    State.emit(s, "act", { id = bug.id, kind = it.kind, mode = it.mode, target = it.target, to = it.to })
    if bug.curled then
        bug.curled = false
        State.emit(s, "uncurl", { id = bug.id })
    end
    local alive = true
    if #it.path > 0 then
        if it.mode == "fly" then alive = flySteps(s, bug, it)
        elseif it.mode == "jump" then alive = jumpStep(s, bug, it)
        else alive = walkSteps(s, bug, it) end
    end
    if not alive or bug.gone then return end
    if it.action then doAction(s, bug, it) end
    if bug.gone then return end
    if it.kind == "ready" then
        bug.ready = true
        bug.timer = 0
        State.emit(s, "ready", { id = bug.id })
    else
        R.resetTimer(s, bug)
    end
end

return R
