-- Shared bot toolkit: legal-action enumeration, a random and a greedy (1-ply lookahead through the real simulation)
-- policy, invariants, a board printer and fight setup. Used by tests/bots.lua and tests/watch.lua.

package.path = "src/?.lua;" .. package.path

local State = require("sim.state")
local Grid = require("sim.grid")
local Fight = require("sim.fight")
local Kid = require("sim.kid")
local Run = require("sim.run")
local Q = require("sim.query")
local U = require("sim.util")

local B = {}

function B.invariants(s)
    local seen = {}
    for _, b in ipairs(s.bugs) do
        local k = Grid.key(b.x, b.y)
        assert(not seen[k], "two bugs on tile " .. Grid.name(b.x, b.y))
        seen[k] = b
        assert(s.occ[k] == b, "occupancy map out of sync at " .. Grid.name(b.x, b.y))
        assert(b.hp > 0 and b.hp <= b.maxHp, "bad hp " .. b.hp .. " on " .. b.species)
        assert(b.timer >= 0, "negative timer")
        assert(not b.gone, "removed bug still listed")
        local c = Grid.cell(s, b.x, b.y)
        assert(c and not c.void, "bug on a void tile")
        assert(not (c.block == "pebble" or c.block == "knot"), "bug inside an obstacle " .. b.species .. " at " .. Grid.name(b.x, b.y))
        if b.ready then assert(b.timer == 0, "ready bug with timer " .. b.timer) end
    end
    for k, b in pairs(s.occ) do assert(seen[k] == b, "stale occupancy") end
    assert(#s.hand <= 7, "hand too big")
end

function B.selections(s, cardId)
    local out = {}
    local function rec(sel)
        local o = Kid.options(s, cardId, sel)
        if not o then out[#out + 1] = sel return end
        for _, it in ipairs(o.items) do
            local pick
            if o.kind == "bug" then pick = it.id elseif o.kind == "tile" then pick = { x = it.x, y = it.y }
            elseif it.ok then pick = { dx = it.dx, dy = it.dy } end
            if pick then
                local n = {}
                for i, v in ipairs(sel) do n[i] = v end
                n[#n + 1] = pick
                rec(n)
            end
        end
    end
    rec({})
    return out
end

function B.legalActions(s)
    local acts = { { kind = "wait" } }
    local seenCard = {}
    for hi, id in ipairs(s.hand) do
        if not seenCard[id] then
            seenCard[id] = true
            for _, sel in ipairs(B.selections(s, id)) do acts[#acts + 1] = { kind = "card", hi = hi, sel = sel, id = id } end
        end
    end
    for ji, _ in ipairs(s.jar) do
        for _, t in ipairs(Q.homeTiles(s, "kid")) do
            if Kid.homeFree(s, t.x, t.y) then acts[#acts + 1] = { kind = "release", ji = ji, x = t.x, y = t.y } end
        end
    end
    return acts
end

function B.apply(s, a)
    if a.kind == "wait" then return Kid.wait(s) end
    if a.kind == "card" then return Kid.play(s, a.hi, a.sel) end
    return Kid.release(s, a.ji, a.x, a.y)
end

function B.describe(s, a)
    if a.kind == "wait" then return "wait" end
    if a.kind == "release" then return string.format("release %s on %s", s.jar[a.ji].species, Grid.name(a.x, a.y)) end
    local parts = {}
    for _, v in ipairs(a.sel) do
        if type(v) == "number" then local b = State.byId(s, v); parts[#parts + 1] = b and (b.species .. "@" .. Grid.name(b.x, b.y)) or "?"
        elseif v.x then parts[#parts + 1] = Grid.name(v.x, v.y)
        else parts[#parts + 1] = (v.dx == 1 and "right") or (v.dx == -1 and "left") or (v.dy == 1 and "up") or "down" end
    end
    return a.id .. " " .. table.concat(parts, " ")
end

function B.evaluate(s)
    if s.winner == "kid" then return 10000 - s.tick end
    if s.winner == "rival" then return -10000 + s.tick end
    local v = (Q.totalHp(s, "kid") - Q.totalHp(s, "rival")) * 3
    v = v + (Q.count(s, "kid") - Q.count(s, "rival")) * 5
    local r = s.rule
    if r.id == "crumbs" then
        v = v + (r.score.kid - r.score.rival) * 40
        for _, b in ipairs(s.bugs) do if b.carrying then v = v + (b.side == "kid" and 10 or -10) end end
    elseif r.id == "zumo" then
        v = v + (s.stats.fell.rival + s.stats.scurried.rival - s.stats.fell.kid - s.stats.scurried.kid) * 25
    end
    return v
end

function B.choose(s, policy)
    local acts = B.legalActions(s)
    if policy == "random" then
        if #acts > 1 and U.rand(s, 6) == 1 then return acts[1] end
        return acts[U.rand(s, #acts)]
    end
    local best, bestV
    for _, a in ipairs(acts) do
        local c = State.clone(s)
        if B.apply(c, a) then
            local v = B.evaluate(c)
            if a.kind == "wait" then v = v - 1 end
            if not bestV or v > bestV then best, bestV = a, v end
        end
    end
    return best or acts[1]
end

-- The player's collection when they reach each fight (what the scripted rewards would have given them)
function B.setup(enc, seed)
    local run = Run.new(seed)
    if enc.id == "lawn" then Run.addCard(run, "shove") end
    if enc.id == "stump" then Run.addBug(run, "stag"); Run.addCard(run, "shove"); Run.addCard(run, "tap") end
    local s = Fight.new(enc, { jar = run.jar, deck = run.deck, seed = seed })
    if s.phase == "deploy" then
        local order = {}
        if enc.id == "lawn" then order = { 1, 4, 3 } elseif enc.id == "stump" then order = { 6, 2, 1 } end
        Fight.autoDeploy(s, order)
        Kid.start(s)
    end
    return s
end

local LETTER = { ant = "a", redant = "r", pillbug = "P", stag = "S", mantis = "M", spider = "T", cricket = "C", wasp = "W", hercules = "H" }
function B.dump(s)
    local out = {}
    for y = s.h, 1, -1 do
        local line = y .. "  "
        for x = 1, s.w do
            local b, c = State.at(s, x, y), Grid.cell(s, x, y)
            if c.void then line = line .. "    "
            elseif b then
                local l = LETTER[b.species]
                if b.side == "rival" then l = l:upper() end
                line = line .. l .. (b.ready and "!" or b.timer) .. (b.curled and "o" or (b.flipped and "x" or " ")) .. " "
            elseif c.food then line = line .. (c.food.kind == "loot" and "$   " or "+   ")
            elseif c.block then line = line .. "#   "
            elseif c.puddle then line = line .. "~   "
            elseif c.cover then line = line .. (c.cover == "leaf" and "l   " or "g   ")
            else line = line .. ".   " end
        end
        out[#out + 1] = line
    end
    out[#out + 1] = string.format("tick %d  hand: %s  score %d/%d  rival timer %s", s.tick, table.concat(s.hand, ","), s.rule.score.kid, s.rule.score.rival, s.rival and s.rival.timer or "-")
    return table.concat(out, "\n")
end

return B
