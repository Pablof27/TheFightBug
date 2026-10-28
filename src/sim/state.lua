-- Fight state: plain tables only, so a whole fight can be cloned and replayed for previews (GDD §12: preview = simulation).
-- Everything the simulation changes is reachable from this table; static content lives in src/data.

local U = require("sim.util")
local Grid = require("sim.grid")
local Bugs = require("data.bugs")

local State = {}

local TERRAIN = {
    ["."] = {},
    g = { cover = "grass" },
    l = { cover = "leaf" },
    p = { block = "pebble" },
    k = { block = "knot" },
    ["~"] = { puddle = true },
    s = { light = "shade" },
    u = { light = "sun" },
    ["#"] = { void = true },
}

--- Creates an empty fight. layout = array of h strings, TOP row (y = h) first.
function State.new(o)
    local s = {
        w = o.w or 6, h = o.h or 6,
        cells = {}, bugs = {}, occ = {}, nextId = 1,
        tick = 0, sunLimit = o.sunLimit or 40,
        openEdges = o.openEdges or false,
        log = {}, rng = o.seed or 12345,
        jar = {}, deck = {}, hand = {}, discard = {}, exhaust = {}, field = {}, met = {}, metRival = {},
        rule = nil, rival = nil, winner = nil, why = nil,
        stats = { scurried = { kid = 0, rival = 0 }, fell = { kid = 0, rival = 0 }, cards = 0, ticks = 0 },
    }
    for y = 1, s.h do
        local row = o.layout and o.layout[s.h - y + 1] or string.rep(".", s.w)
        for x = 1, s.w do
            local ch = row:sub(x, x)
            local t = TERRAIN[ch] or TERRAIN["."]
            local c = {}
            for k, v in pairs(t) do c[k] = v end
            s.cells[Grid.key(x, y)] = c
        end
    end
    return s
end

local function cloneBug(b)
    local n = {}
    for k, v in pairs(b) do n[k] = v end
    if b.carrying then n.carrying = { kind = b.carrying.kind } end
    return n
end

local function cloneCell(c)
    local n = {}
    for k, v in pairs(c) do
        if type(v) == "table" then
            local t = {}
            for a, b in pairs(v) do t[a] = b end
            n[k] = t
        else
            n[k] = v
        end
    end
    return n
end

--- Deep copy used by every preview. The event log is not copied: the clone starts with an empty one.
function State.clone(s)
    local c = {}
    for k, v in pairs(s) do
        if k ~= "log" and k ~= "occ" and k ~= "bugs" and k ~= "cells" then c[k] = U.clone(v) end
    end
    c.log = {}
    c.cells = {}
    for k, cell in pairs(s.cells) do c.cells[k] = cloneCell(cell) end
    c.bugs, c.occ = {}, {}
    for i, b in ipairs(s.bugs) do
        local n = cloneBug(b)
        c.bugs[i] = n
        c.occ[Grid.key(n.x, n.y)] = n
    end
    return c
end

function State.emit(s, kind, data)
    data = data or {}
    data.type = kind
    data.tick = s.tick
    s.log[#s.log + 1] = data
    return data
end

--- Takes the events recorded so far and starts a fresh log.
function State.drain(s)
    local l = s.log
    s.log = {}
    return l
end

function State.at(s, x, y) return s.occ[y * 16 + x] end

function State.byId(s, id)
    for i = 1, #s.bugs do if s.bugs[i].id == id then return s.bugs[i] end end
    return nil
end

function State.living(s, side)
    local out = {}
    for i = 1, #s.bugs do
        local b = s.bugs[i]
        if not side or b.side == side then out[#out + 1] = b end
    end
    return out
end

--- Puts a new bug on the board. o: hp, timer, ready, jarUid, colonyIdx
function State.spawnBug(s, speciesId, side, x, y, o)
    o = o or {}
    local sp = Bugs[speciesId]
    assert(sp, "unknown species " .. tostring(speciesId))
    local b = {
        id = s.nextId, species = speciesId, side = side, x = x, y = y,
        hp = o.hp or sp.hp, maxHp = sp.hp, bite = sp.bite, weight = sp.weight,
        move = sp.move, mtype = sp.mtype, reach = sp.reach or 1,
        instinct = sp.instinct, traits = sp.traits, likes = sp.likes,
        baseTimer = sp.timer, timer = o.timer or sp.timer,
        ready = o.ready or false, curled = false, flipped = false, soaked = false,
        acted = false, jarUid = o.jarUid, carrying = nil,
    }
    s.nextId = s.nextId + 1
    s.bugs[#s.bugs + 1] = b
    s.occ[Grid.key(x, y)] = b
    s.met[speciesId] = true
    if side == "rival" then s.metRival[speciesId] = true end
    if o.jarUid then
        local f = s.field[o.jarUid] or { total = 0, lost = 0 }
        f.total = f.total + 1
        s.field[o.jarUid] = f
    end
    return b
end

--- Called when a bug leaves the fight for good (scurried off, pushed off).
function State.markLost(s, b)
    if b.jarUid and s.field[b.jarUid] then s.field[b.jarUid].lost = s.field[b.jarUid].lost + 1 end
end

function State.removeBug(s, b)
    for i = 1, #s.bugs do
        if s.bugs[i] == b then table.remove(s.bugs, i) break end
    end
    local k = Grid.key(b.x, b.y)
    if s.occ[k] == b then s.occ[k] = nil end
    b.gone = true
end

function State.moveBug(s, b, x, y)
    local k = Grid.key(b.x, b.y)
    if s.occ[k] == b then s.occ[k] = nil end
    b.x, b.y = x, y
    s.occ[Grid.key(x, y)] = b
end

return State
