-- Card effects (GDD §7). data/cards.lua says what a card is; this file says what it does.
-- A selection `sel` has one entry per step of the card: a bug id, a tile {x, y}, or a direction {dx, dy}.

local Grid = require("sim.grid")
local State = require("sim.state")
local Q = require("sim.query")
local R = require("sim.resolver")
local Cards = require("data.cards")

local Fx = {}

local function targetable(s, b) return b.side == "kid" or not Q.isHidden(s, b) end

local function walkable(s, x, y)
    local c = Grid.cell(s, x, y)
    return c ~= nil and not c.void and not c.block
end

local function freeGround(s, x, y, o)
    o = o or {}
    local c = Grid.cell(s, x, y)
    if not c or c.void or c.block or State.at(s, x, y) then return false end
    if c.puddle and c.cover ~= "leaf" and not o.puddle then return false end
    if c.food then return false end
    return true
end

local function anyTile(s, x, y)
    local c = Grid.cell(s, x, y)
    return c ~= nil and not c.void
end

local function inArea(s, cx, cy)
    local list = {}
    for _, b in ipairs(s.bugs) do
        if math.abs(b.x - cx) <= 1 and math.abs(b.y - cy) <= 1 then list[#list + 1] = b end
    end
    table.sort(list, Q.byOrder)
    return list
end

local defs = {}

defs.flick = {
    bug = function(s, b) return targetable(s, b) and b.weight <= 2 end,
    dir = function() return true end,
    apply = function(s, sel)
        State.emit(s, "hand", { card = "flick", id = sel[1], dx = sel[2].dx, dy = sel[2].dy })
        R.push(s, State.byId(s, sel[1]), sel[2].dx, sel[2].dy, "flick")
    end,
}

defs.shove = {
    bug = function(s, b) return targetable(s, b) end,
    dir = function() return true end,
    apply = function(s, sel)
        State.emit(s, "hand", { card = "shove", id = sel[1], dx = sel[2].dx, dy = sel[2].dy })
        R.push(s, State.byId(s, sel[1]), sel[2].dx, sel[2].dy, "shove")
    end,
}

local function lure(kind)
    return {
        tile = function(s, x, y) return freeGround(s, x, y) end,
        apply = function(s, sel)
            local p = sel[1]
            Grid.cell(s, p.x, p.y).food = { kind = kind }
            State.emit(s, "place", { kind = kind, x = p.x, y = p.y })
        end,
    }
end
defs.crumb, defs.sugar, defs.juice = lure("crumb"), lure("sugar"), lure("juice")

defs.pebble = {
    tile = function(s, x, y) return freeGround(s, x, y) end,
    apply = function(s, sel)
        local p = sel[1]
        Grid.cell(s, p.x, p.y).block = "pebble"
        State.emit(s, "place", { kind = "pebble", x = p.x, y = p.y })
    end,
}

defs.leaf = {
    tile = function(s, x, y) return freeGround(s, x, y, { puddle = true }) and not Grid.cell(s, x, y).cover end,
    apply = function(s, sel)
        local p = sel[1]
        Grid.cell(s, p.x, p.y).cover = "leaf"
        State.emit(s, "place", { kind = "leaf", x = p.x, y = p.y })
    end,
}

defs.stick = {
    tile = function(s, x, y) return freeGround(s, x, y) end,
    dir = function(s, a, d) return freeGround(s, a.x + d.dx, a.y + d.dy) end,
    apply = function(s, sel)
        local a, d = sel[1], sel[2]
        local bx, by = a.x + d.dx, a.y + d.dy
        Grid.cell(s, a.x, a.y).block = "stick"
        Grid.cell(s, bx, by).block = "stick"
        Grid.cell(s, a.x, a.y).stick = { x2 = bx, y2 = by, first = true }
        Grid.cell(s, bx, by).stick = { x2 = a.x, y2 = a.y }
        State.emit(s, "place", { kind = "stick", x = a.x, y = a.y, x2 = bx, y2 = by })
    end,
}

defs.water = {
    tile = walkable,
    dir = function(s, a, d) return walkable(s, a.x + d.dx, a.y + d.dy) end,
    apply = function(s, sel)
        local a, d = sel[1], sel[2]
        local bx, by = a.x + d.dx, a.y + d.dy
        Grid.cell(s, a.x, a.y).puddle = true
        Grid.cell(s, bx, by).puddle = true
        State.emit(s, "place", { kind = "puddle", x = a.x, y = a.y, x2 = bx, y2 = by })
        for _, p in ipairs({ { a.x, a.y }, { bx, by } }) do
            local b = State.at(s, p[1], p[2])
            if b then R.arrive(s, b) end
        end
    end,
}

defs.shadow = {
    bug = function(s, b) return targetable(s, b) end,
    apply = function(s, sel)
        State.emit(s, "hand", { card = "shadow", id = sel[1] })
        R.addTimer(s, State.byId(s, sel[1]), 1, "shadow")
    end,
}

defs.sun = {
    tile = anyTile,
    apply = function(s, sel)
        local p = sel[1]
        State.emit(s, "area", { kind = "sun", x = p.x, y = p.y })
        for _, b in ipairs(inArea(s, p.x, p.y)) do
            if b.side == "kid" then R.addTimer(s, b, -1, "sun") end
        end
    end,
}

defs.tap = {
    tile = anyTile,
    apply = function(s, sel)
        local p = sel[1]
        State.emit(s, "area", { kind = "tap", x = p.x, y = p.y })
        for _, b in ipairs(inArea(s, p.x, p.y)) do
            R.addTimer(s, b, 1, "tap")
            if b.traits.curl and not b.curled then
                b.curled = true
                State.emit(s, "curl", { id = b.id })
            end
        end
    end,
}

defs.blow = {
    tile = anyTile,
    dir = function() return true end,
    apply = function(s, sel)
        local p, d = sel[1], sel[2]
        local line = {}
        for _, b in ipairs(s.bugs) do
            if b.weight == 1 and ((d.dx ~= 0 and b.y == p.y) or (d.dy ~= 0 and b.x == p.x)) then line[#line + 1] = b end
        end
        table.sort(line, function(a, b) return (a.x * d.dx + a.y * d.dy) > (b.x * d.dx + b.y * d.dy) end)
        State.emit(s, "blow", { x = p.x, y = p.y, dx = d.dx, dy = d.dy })
        for _, b in ipairs(line) do
            if not b.gone then
                if b.mtype == "fly" then R.slide(s, b, d.dx, d.dy, 2, "blow") else R.push(s, b, d.dx, d.dy, "blow") end
            end
        end
    end,
}

Fx.defs = defs

--- The tile a "dir" step starts from: the bug or tile chosen just before it.
local function anchorOf(s, def, sel)
    local prev = sel[#sel]
    if def.steps[#sel] == "bug" then
        local b = State.byId(s, prev)
        return { x = b.x, y = b.y }
    end
    return prev
end

--- What can be picked next? Returns { kind, items = { {id}|{x,y}|{x,y,dx,dy,ok} } } or nil when the card is complete.
function Fx.options(s, cardId, sel)
    local def = Cards[cardId]
    local fx = defs[cardId]
    local kind = def.steps[#sel + 1]
    if not kind then return nil end
    local out = { kind = kind, items = {} }
    if kind == "bug" then
        for _, b in ipairs(Q.timeline(s)) do
            if fx.bug(s, b) then out.items[#out.items + 1] = { id = b.id, x = b.x, y = b.y } end
        end
    elseif kind == "tile" then
        for y = s.h, 1, -1 do
            for x = 1, s.w do
                if fx.tile(s, x, y) then out.items[#out.items + 1] = { x = x, y = y } end
            end
        end
    else
        local a = anchorOf(s, def, sel)
        for _, d in ipairs(Grid.DIRS) do
            out.items[#out.items + 1] = { x = a.x + d.dx, y = a.y + d.dy, dx = d.dx, dy = d.dy, ok = fx.dir(s, a, d) and true or false }
        end
    end
    return out
end

function Fx.validate(s, cardId, sel)
    local def = Cards[cardId]
    if not def or #sel ~= #def.steps then return false end
    for i = 1, #sel do
        local prefix = {}
        for j = 1, i - 1 do prefix[j] = sel[j] end
        local opts = Fx.options(s, cardId, prefix)
        local ok = false
        for _, it in ipairs(opts.items) do
            if opts.kind == "bug" then ok = ok or it.id == sel[i]
            elseif opts.kind == "tile" then ok = ok or (it.x == sel[i].x and it.y == sel[i].y)
            else ok = ok or (it.ok and it.dx == sel[i].dx and it.dy == sel[i].dy) end
        end
        if not ok then return false end
    end
    return true
end

--- Tiles a (partial) selection will touch, for the preview highlight.
function Fx.area(s, cardId, sel)
    local tiles = {}
    if cardId == "sun" or cardId == "tap" then
        local p = sel[1]
        if p then
            for dx = -1, 1 do for dy = -1, 1 do
                local c = Grid.cell(s, p.x + dx, p.y + dy)
                if c and not c.void then tiles[#tiles + 1] = { x = p.x + dx, y = p.y + dy } end
            end end
        end
    elseif cardId == "stick" or cardId == "water" then
        if sel[1] then tiles[1] = { x = sel[1].x, y = sel[1].y } end
        if sel[1] and sel[2] then tiles[2] = { x = sel[1].x + sel[2].dx, y = sel[1].y + sel[2].dy } end
    elseif cardId == "blow" then
        local p, d = sel[1], sel[2]
        if p and d then
            if d.dx ~= 0 then for x = 1, s.w do tiles[#tiles + 1] = { x = x, y = p.y } end
            else for y = 1, s.h do tiles[#tiles + 1] = { x = p.x, y = y } end end
        elseif p then
            tiles[1] = { x = p.x, y = p.y }
        end
    end
    return tiles
end

function Fx.apply(s, cardId, sel) defs[cardId].apply(s, sel) end

return Fx
