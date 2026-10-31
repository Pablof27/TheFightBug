-- The rival kid's off-board signature move (GDD §5.12): its own timer, shown in advance like any bug's intent.
-- It follows the bugs' clock rule: at 0 it is due, and it happens on the next tick (after all the bugs have acted).
-- On a Bug Hunt there is no kid: nature has a move of its own (data/park.lua natures), run by the same machinery.

local U = require("sim.util")
local Grid = require("sim.grid")
local State = require("sim.state")
local Q = require("sim.query")
local R = require("sim.resolver")
local Rules = require("sim.rules")
local Data = require("data.rivals")
local Park = require("data.park")

local Rival = {}

--- id: a rival kid (data/rivals.lua) or one of nature's moves (data/park.lua). o.timerDelta: the kid's mood after the
--- last round of a duel (Angry -1, Cocky +1, GDD §8.5.2).
function Rival.setup(s, id, o)
    o = o or {}
    local d = Data[id] or Park.natures[id]
    assert(d, "unknown rival " .. tostring(id))
    local sig = d.sig
    s.rival = {
        id = id, kind = sig.kind, name = sig.name, nature = Park.natures[id] ~= nil or nil, once = sig.once or nil,
        timer = math.max(0, sig.timer + (o.timerDelta or 0)), base = sig.timer,
        shopping = U.copyArray(d.shopping or {}), cap = d.cap or 12,
    }
end

function Rival.countdown(s)
    local r = s.rival
    if r then r.timer = r.timer - 1 end      -- 0 -> -1: his move is due this tick
end

--- Stomp aims at the 3x3 area covering the most of YOUR bugs (then the fewest of his own, then reading order).
function Rival.stompCenter(s)
    local best
    for y = s.h, 1, -1 do
        for x = 1, s.w do
            local kidN, rivN = 0, 0
            for dx = -1, 1 do
                for dy = -1, 1 do
                    local b = State.at(s, x + dx, y + dy)
                    if b then if b.side == "kid" then kidN = kidN + 1 else rivN = rivN + 1 end end
                end
            end
            if not best or kidN > best.k or (kidN == best.k and rivN < best.r) then best = { x = x, y = y, k = kidN, r = rivN } end
        end
    end
    return best
end

local function spawn(s, species, x, y)
    local b = State.spawnBug(s, species, "rival", x, y)
    State.emit(s, "spawn", { id = b.id, species = species, side = "rival", x = x, y = y })
    R.arrive(s, b)
    R.reactions(s, b)
    return b
end

local function freeTile(s, order)
    for _, p in ipairs(order) do
        local c = Grid.cell(s, p.x, p.y)
        if c and not c.void and not c.block and not c.puddle and not State.at(s, p.x, p.y) then return p end
    end
end

local function homeOrder(s, xs)
    local order = {}
    for y = s.h, s.h - 1, -1 do
        for _, x in ipairs(xs) do order[#order + 1] = { x = x, y = y } end
    end
    return order
end

local Moves = {}

function Moves.stomp(s)
    local c = Rival.stompCenter(s)
    local ids = {}
    State.emit(s, "rival_act", { kind = "stomp", x = c.x, y = c.y })
    for dx = -1, 1 do
        for dy = -1, 1 do
            local b = State.at(s, c.x + dx, c.y + dy)
            if b then ids[#ids + 1] = b.id end
        end
    end
    for _, id in ipairs(ids) do
        local b = State.byId(s, id)
        if b then R.addTimer(s, b, 2, "stomp") end
    end
end

function Moves.farm(s)
    State.emit(s, "rival_act", { kind = "farm" })
    local order = homeOrder(s, { 1, 2, 3, 4, 5, 6 })
    for _ = 1, 2 do
        if #State.living(s, "rival") >= s.rival.cap then break end
        local p = freeTile(s, order)
        if not p then break end
        spawn(s, "ant", p.x, p.y)
    end
end

function Moves.buy(s)
    State.emit(s, "rival_act", { kind = "buy" })
    local species = table.remove(s.rival.shopping, 1)
    if not species then return end
    local p = freeTile(s, homeOrder(s, { 3, 4, 2, 5, 1, 6 }))
    if p then spawn(s, species, p.x, p.y) end
end

-- ───────────────────────── the new kids' moves ─────────────────────────

-- Science Nerd: the bug of yours that would act soonest (Ready ambushers aside), reading order on ties.
local function notesTarget(s)
    local best
    for _, b in ipairs(Q.timeline(s)) do
        if b.side == "kid" and not b.loose and not b.ready and (not best or b.timer < best.timer) then best = b end
    end
    return best
end

-- The Twins: their two slowest bugs (highest timer, reading order on ties).
local function slowest(s, n)
    local list = {}
    for _, b in ipairs(Q.timeline(s)) do if b.side == "rival" then list[#list + 1] = b end end
    table.sort(list, function(a, b)
        if a.timer ~= b.timer then return a.timer > b.timer end
        return Q.orderKey(a) < Q.orderKey(b)
    end)
    local out = {}
    for i = 1, math.min(n, #list) do out[i] = list[i] end
    return out
end

-- The row with the most bugs that count (lowest row on ties, after `tie`).
local function busiestRow(s, count)
    local best
    for y = 1, s.h do
        local n, t = count(s, y)
        if not best or n > best.n or (n == best.n and t < best.t) then best = { y = y, n = n, t = t } end
    end
    return best.y
end

-- Marble Champion: the row with the most of YOUR bugs (fewest of his on ties).
local function shooterRow(s)
    return busiestRow(s, function(st, y)
        local k, r = 0, 0
        for x = 1, st.w do
            local b = State.at(st, x, y)
            if b and not b.loose then if b.side == "kid" then k = k + 1 else r = r + 1 end end
        end
        return k, r
    end)
end

-- The dog: the row with the most bugs of any side.
local function dogRow(s)
    return busiestRow(s, function(st, y)
        local n = 0
        for x = 1, st.w do if State.at(st, x, y) then n = n + 1 end end
        return n, 0
    end)
end

local function firstInRow(s, y)
    for x = 1, s.w do
        local b = State.at(s, x, y)
        if b then return b end
    end
end

local function rowTiles(s, y)
    local out = {}
    for x = 1, s.w do
        local c = Grid.cell(s, x, y)
        if c and not c.void then out[#out + 1] = { x = x, y = y } end
    end
    return out
end

--- Moves that pick their target in advance (so it can be shown) pick it here, with the fight's seeded generator.
function Rival.pick(s)
    local r = s.rival
    if r.kind == "tantrum" then
        local list = {}
        for _, b in ipairs(Q.timeline(s)) do if not b.loose then list[#list + 1] = b end end
        r.target = nil
        if #list == 0 then return end
        local b = list[U.rand(s, #list)]
        local d = Grid.DIRS[U.rand(s, 4)]
        r.target, r.dx, r.dy = b.id, d.dx, d.dy
    elseif r.kind == "shower" then
        local cands = {}
        for y = s.h - 1, 2, -1 do
            for x = 1, s.w do
                local c = Grid.cell(s, x, y)
                if c and not c.void and not c.block and not c.trap and not c.puddle and not c.food then cands[#cands + 1] = { x = x, y = y } end
            end
        end
        r.tiles = {}
        for _ = 1, 2 do
            if #cands == 0 then break end
            r.tiles[#r.tiles + 1] = table.remove(cands, U.rand(s, #cands))
        end
    end
end

--- The fight has started (after the deploy phase).
function Rival.begin(s)
    local r = s.rival
    if r and (r.kind == "tantrum" or r.kind == "shower") then Rival.pick(s) end
end

function Moves.tantrum(s)
    local r = s.rival
    local b = r.target and State.byId(s, r.target)
    if not b then Rival.pick(s); b = r.target and State.byId(s, r.target) end
    State.emit(s, "rival_act", { kind = "tantrum", id = b and b.id, dx = r.dx, dy = r.dy })
    if b then R.slide(s, b, r.dx, r.dy, 1, "tantrum") end
    Rival.pick(s)
end

function Moves.notes(s)
    local b = notesTarget(s)
    State.emit(s, "rival_act", { kind = "notes", id = b and b.id })
    if b then R.addTimer(s, b, 2, "notes") end
end

function Moves.tagteam(s)
    local list = slowest(s, 2)
    local ids = {}
    for i, b in ipairs(list) do ids[i] = b.id end
    State.emit(s, "rival_act", { kind = "tagteam", ids = ids })
    for _, b in ipairs(list) do if not b.gone then R.addTimer(s, b, -1, "tagteam") end end
end

function Moves.shooter(s)
    local y = shooterRow(s)
    local b = firstInRow(s, y)
    State.emit(s, "rival_act", { kind = "shooter", y = y, id = b and b.id })
    if b then
        local res = R.slide(s, b, 1, 0, 1, "shooter")
        if res == "moved" and not b.gone then R.addTimer(s, b, 1, "shooter") end
    end
end

-- ───────────────────────── nature's moves (Bug Hunts) ─────────────────────────

function Moves.shower(s)
    local r = s.rival
    State.emit(s, "rival_act", { kind = "shower" })
    for _, p in ipairs(r.tiles or {}) do
        local c = Grid.cell(s, p.x, p.y)
        if c and not c.void and not c.block and not c.trap and not c.puddle then
            c.puddle = true
            State.emit(s, "place", { kind = "puddle", x = p.x, y = p.y, x2 = p.x, y2 = p.y })
            local b = State.at(s, p.x, p.y)
            if b then R.arrive(s, b) end
        end
    end
    Rival.pick(s)
end

function Moves.bird(s)
    State.emit(s, "rival_act", { kind = "bird" })
    for _, b in ipairs(Q.timeline(s)) do
        if not b.gone then R.addTimer(s, b, b.mtype == "fly" and 2 or 1, "bird") end
    end
end

function Moves.dog(s)
    local y = dogRow(s)
    State.emit(s, "rival_act", { kind = "dog", y = y })
    local list = {}
    for x = 1, s.w do
        local b = State.at(s, x, y)
        if b then list[#list + 1] = b end
    end
    for _, b in ipairs(list) do if not b.gone then R.slide(s, b, 0, 1, 1, "dog") end end
end

function Moves.mower(s)
    State.emit(s, "rival_act", { kind = "mower" })
    Rules.endHunt(s, "mower")
end

--- Once his timer has run past 0 the rival kid does his thing, after all the bugs have acted.
function Rival.act(s)
    local r = s.rival
    if not r or r.timer >= 0 then return end
    Moves[r.kind](s)
    r.timer = r.once and 99 or r.base
    State.emit(s, "rival_timer", { timer = r.timer })
end

--- What he is going to do (for the HUD / board overlay).
function Rival.peek(s)
    local r = s.rival
    if not r then return nil end
    local p = { kind = r.kind, timer = r.timer }
    if r.kind == "stomp" then
        local c = Rival.stompCenter(s)
        p.x, p.y = c.x, c.y
        p.tiles = {}
        for dx = -1, 1 do
            for dy = -1, 1 do
                local cell = Grid.cell(s, c.x + dx, c.y + dy)
                if cell and not cell.void then p.tiles[#p.tiles + 1] = { x = c.x + dx, y = c.y + dy } end
            end
        end
    elseif r.kind == "farm" then
        p.tiles = {}
        local order = homeOrder(s, { 1, 2, 3, 4, 5, 6 })
        local taken = {}
        for _ = 1, 2 do
            for _, q in ipairs(order) do
                local c = Grid.cell(s, q.x, q.y)
                local key = Grid.key(q.x, q.y)
                if not taken[key] and c and not c.void and not c.block and not c.puddle and not State.at(s, q.x, q.y) then
                    taken[key] = true
                    p.tiles[#p.tiles + 1] = { x = q.x, y = q.y }
                    break
                end
            end
        end
    elseif r.kind == "buy" then
        p.species = r.shopping[1]
        local q = freeTile(s, homeOrder(s, { 3, 4, 2, 5, 1, 6 }))
        p.tiles = q and { q } or {}
    elseif r.kind == "tantrum" then
        local b = r.target and State.byId(s, r.target)
        p.tiles = b and { { x = b.x, y = b.y } } or {}
        p.id, p.dx, p.dy = b and b.id, r.dx, r.dy
    elseif r.kind == "notes" then
        local b = notesTarget(s)
        p.tiles = b and { { x = b.x, y = b.y } } or {}
        p.id = b and b.id
    elseif r.kind == "tagteam" then
        p.tiles, p.ids = {}, {}
        for _, b in ipairs(slowest(s, 2)) do
            p.tiles[#p.tiles + 1] = { x = b.x, y = b.y }
            p.ids[#p.ids + 1] = b.id
        end
    elseif r.kind == "shooter" then
        p.row = shooterRow(s)
        p.tiles = rowTiles(s, p.row)
        local b = firstInRow(s, p.row)
        p.id = b and b.id
    elseif r.kind == "dog" then
        p.row = dogRow(s)
        p.tiles = rowTiles(s, p.row)
    elseif r.kind == "shower" then
        p.tiles = {}
        for i, t in ipairs(r.tiles or {}) do p.tiles[i] = { x = t.x, y = t.y } end
    else
        p.tiles = {}
    end
    return p
end

return Rival
