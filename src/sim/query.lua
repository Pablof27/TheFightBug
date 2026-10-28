-- Read-only questions about a fight state. Nothing here mutates anything.

local Grid = require("sim.grid")
local State = require("sim.state")

local Q = {}

function Q.opposite(side) return side == "kid" and "rival" or "kid" end

-- Timeline order key: your bugs first, then the rival's; inside a side, reading order (top-left first).
function Q.orderKey(b)
    return (b.side == "kid" and 0 or 100000) + Grid.reading(b.x, b.y)
end

function Q.byOrder(a, b) return Q.orderKey(a) < Q.orderKey(b) end

function Q.timeline(s)
    local list = {}
    for i = 1, #s.bugs do list[i] = s.bugs[i] end
    table.sort(list, Q.byOrder)
    return list
end

function Q.isCoverCell(c)
    return c ~= nil and c.cover ~= nil
end

--- Hidden (GDD §5.8, derived): a walker standing in grass or under a leaf, with no enemy next to it.
function Q.isHidden(s, b)
    if b.mtype == "fly" then return false end
    local c = Grid.cell(s, b.x, b.y)
    if not c or not c.cover then return false end
    for _, d in ipairs(Grid.DIRS) do
        local o = State.at(s, b.x + d.dx, b.y + d.dy)
        if o and o.side ~= b.side then return false end
    end
    return true
end

--- Enemies that this bug's instinct can see (Hidden ones are ignored).
function Q.visibleEnemies(s, bug)
    local out = {}
    for i = 1, #s.bugs do
        local o = s.bugs[i]
        if o.side ~= bug.side and not Q.isHidden(s, o) then out[#out + 1] = o end
    end
    return out
end

--- Enemies worth going after: in Mushi-Zumo nobody wastes time on a bug heavier than itself (it can't shove it).
function Q.targets(s, bug)
    local all = Q.visibleEnemies(s, bug)
    if not (s.rule and s.rule.attackMode == "push") then return all end
    local out = {}
    for _, o in ipairs(all) do if o.weight <= bug.weight then out[#out + 1] = o end end
    return out
end

function Q.adjacentEnemies(s, bug, x, y)
    x, y = x or bug.x, y or bug.y
    local out = {}
    for _, d in ipairs(Grid.DIRS) do
        local o = State.at(s, x + d.dx, y + d.dy)
        if o and o.side ~= bug.side then out[#out + 1] = o end
    end
    return out
end

--- Lowest stamina first, then reading order: the fixed tie-break of GDD §5.4.
function Q.weakest(list)
    local best
    for _, o in ipairs(list) do
        if not best or o.hp < best.hp or (o.hp == best.hp and Grid.reading(o.x, o.y) < Grid.reading(best.x, best.y)) then best = o end
    end
    return best
end

--- All food on the board in reading order: { {x, y, kind}, ... }
function Q.foods(s)
    local out = {}
    for y = s.h, 1, -1 do
        for x = 1, s.w do
            local c = s.cells[Grid.key(x, y)]
            if c.food then out[#out + 1] = { x = x, y = y, kind = c.food.kind } end
        end
    end
    return out
end

function Q.homeTiles(s, side)
    local out = {}
    for y = s.h, 1, -1 do
        if Grid.isHomeRow(s, side, y) then
            for x = 1, s.w do
                local c = s.cells[Grid.key(x, y)]
                if not c.void then out[#out + 1] = { x = x, y = y } end
            end
        end
    end
    return out
end

function Q.count(s, side)
    local n = 0
    for i = 1, #s.bugs do if s.bugs[i].side == side then n = n + 1 end end
    return n
end

function Q.totalHp(s, side)
    local n = 0
    for i = 1, #s.bugs do if s.bugs[i].side == side then n = n + s.bugs[i].hp end end
    return n
end

--- Is a bug from this side still around, on the board or waiting in the Jar?
function Q.kidHasBugs(s)
    return Q.count(s, "kid") + #s.jar > 0
end

return Q
