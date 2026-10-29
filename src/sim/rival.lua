-- The rival kid's off-board signature move (GDD §5.12): its own timer, shown in advance like any bug's intent.
-- It follows the bugs' clock rule: at 0 it is due, and it happens on the next tick (after all the bugs have acted).

local U = require("sim.util")
local Grid = require("sim.grid")
local State = require("sim.state")
local R = require("sim.resolver")
local Data = require("data.rivals")

local Rival = {}

function Rival.setup(s, id)
    local d = Data[id]
    assert(d, "unknown rival " .. tostring(id))
    s.rival = { id = id, kind = d.sig.kind, timer = d.sig.timer, base = d.sig.timer, shopping = U.copyArray(d.shopping or {}), cap = d.cap or 12 }
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

--- Once his timer has run past 0 the rival kid does his thing, after all the bugs have acted.
function Rival.act(s)
    local r = s.rival
    if not r or r.timer >= 0 then return end
    Moves[r.kind](s)
    r.timer = r.base
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
    end
    return p
end

return Rival
