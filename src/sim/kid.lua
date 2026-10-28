-- The kid's actions (GDD §5.5): play a card, wait, release a bug from the Jar. Every one of them costs time.
-- Before the first action there is a deploy phase: up to 3 Jar bugs go onto the home rows for free.

local Grid = require("sim.grid")
local State = require("sim.state")
local R = require("sim.resolver")
local Clock = require("sim.clock")
local Deck = require("sim.deck")
local Rules = require("sim.rules")
local Fx = require("sim.cardfx")
local U = require("sim.util")
local Cards = require("data.cards")
local Bugs = require("data.bugs")

local Kid = {}

Kid.MAX_DEPLOY = 3

Kid.options = Fx.options
Kid.area = Fx.area

--- Play the card at hand[handIndex] with a complete selection. o.noClock applies the effect only (previews).
function Kid.play(s, handIndex, sel, o)
    o = o or {}
    if s.winner or s.phase ~= "fight" then return false, "not now" end
    local id = s.hand[handIndex]
    if not id then return false, "no such card" end
    if not Fx.validate(s, id, sel) then return false, "bad selection" end
    local def = Cards[id]
    table.remove(s.hand, handIndex)
    if def.exhaust then s.exhaust[#s.exhaust + 1] = id else s.discard[#s.discard + 1] = id end
    s.stats.cards = s.stats.cards + 1
    State.emit(s, "card", { card = id, cost = def.cost, sel = sel })
    Fx.apply(s, id, sel)
    Rules.check(s)
    if def.cost > 0 and not s.winner and not o.noClock then Clock.advance(s, def.cost) end
    return true
end

--- Wait: costs 1 tick and lets the bugs act.
function Kid.wait(s)
    if s.winner or s.phase ~= "fight" then return false end
    State.emit(s, "wait", {})
    Clock.advance(s, 1)
    return true
end

function Kid.releaseCost(speciesId) return Bugs[speciesId].weight end

function Kid.homeFree(s, x, y)
    local c = Grid.cell(s, x, y)
    return c ~= nil and not c.void and Grid.isHomeRow(s, "kid", y) and not c.block
        and not (c.puddle and c.cover ~= "leaf") and not State.at(s, x, y)
end

local function spawnFromJar(s, entry, x, y)
    local sp = Bugs[entry.species]
    local spots = { { x = x, y = y } }
    local n = sp.colony or 1
    if n > 1 then
        local cands = {}
        for _, t in ipairs(require("sim.query").homeTiles(s, "kid")) do
            if not (t.x == x and t.y == y) and Kid.homeFree(s, t.x, t.y) then
                cands[#cands + 1] = { x = t.x, y = t.y, d = Grid.manhattan(x, y, t.x, t.y) }
            end
        end
        table.sort(cands, function(a, b)
            if a.d ~= b.d then return a.d < b.d end
            return Grid.reading(a.x, a.y) < Grid.reading(b.x, b.y)
        end)
        for i = 1, n - 1 do if cands[i] then spots[#spots + 1] = cands[i] end end
    end
    local made = {}
    for _, p in ipairs(spots) do
        local hp = entry.tired and math.max(1, math.ceil(sp.hp / 2)) or nil
        local b = State.spawnBug(s, entry.species, "kid", p.x, p.y, { jarUid = entry.uid, hp = hp })
        State.emit(s, "spawn", { id = b.id, species = entry.species, side = "kid", x = p.x, y = p.y })
        R.arrive(s, b)
        made[#made + 1] = b
    end
    for _, b in ipairs(made) do R.reactions(s, b) end
    return made
end

--- Release a bug from the Jar onto an empty home tile: Light 1, Medium 2, Heavy 3 ticks.
function Kid.release(s, jarIndex, x, y)
    if s.winner or s.phase ~= "fight" then return false, "not now" end
    local entry = s.jar[jarIndex]
    if not entry then return false, "no such bug" end
    if not Kid.homeFree(s, x, y) then return false, "tile" end
    table.remove(s.jar, jarIndex)
    State.emit(s, "release", { species = entry.species, x = x, y = y })
    spawnFromJar(s, entry, x, y)
    Rules.check(s)
    if not s.winner then Clock.advance(s, Kid.releaseCost(entry.species)) end
    return true
end

-- ───────────────────────── deploy phase ─────────────────────────

function Kid.deployedCount(s)
    local seen, n = {}, 0
    for _, b in ipairs(s.bugs) do
        if b.side == "kid" and b.jarUid and not seen[b.jarUid] then seen[b.jarUid] = true; n = n + 1 end
    end
    return n
end

function Kid.deploy(s, jarIndex, x, y)
    if s.phase ~= "deploy" then return false, "not now" end
    local entry = s.jar[jarIndex]
    if not entry then return false, "no such bug" end
    if Kid.deployedCount(s) >= Kid.MAX_DEPLOY then return false, "full" end
    if not Kid.homeFree(s, x, y) then return false, "tile" end
    table.remove(s.jar, jarIndex)
    s.deployedEntries = s.deployedEntries or {}
    s.deployedEntries[entry.uid] = entry
    spawnFromJar(s, entry, x, y)
    return true
end

--- Takes a deployed team back into the Jar (before the fight starts).
function Kid.undeploy(s, uid)
    if s.phase ~= "deploy" then return false end
    local entry = s.deployedEntries and s.deployedEntries[uid]
    if not entry then return false end
    for i = #s.bugs, 1, -1 do
        local b = s.bugs[i]
        if b.side == "kid" and b.jarUid == uid then State.removeBug(s, b) end
    end
    s.deployedEntries[uid] = nil
    s.jar[#s.jar + 1] = entry
    return true
end

--- Ends the deploy phase: shuffle the deck and draw the opening hand.
function Kid.start(s)
    if s.phase ~= "deploy" then return false end
    s.phase = "fight"
    if not s.scriptedHand then
        U.shuffle(s, s.deck)
        Deck.draw(s, Deck.START_HAND)
    end
    State.emit(s, "start", {})
    return true
end

return Kid
