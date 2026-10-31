-- The kid's actions (GDD §5.5): play a card, wait, release a bug from the Jar. Every one of them costs time.
-- Before the first action there is a deploy phase: up to 3 Jar bugs go onto the home rows for free. On a Bug Hunt the deploy
-- phase also lays the jar (the trap), the bugs you deploy are your whole hunting party (nobody is released later), and
-- you can close the lid at any time.

local Grid = require("sim.grid")
local State = require("sim.state")
local R = require("sim.resolver")
local Clock = require("sim.clock")
local Deck = require("sim.deck")
local Rules = require("sim.rules")
local Rival = require("sim.rival")
local Fx = require("sim.cardfx")
local U = require("sim.util")
local Cards = require("data.cards")
local Bugs = require("data.bugs")

local Kid = {}

Kid.MAX_DEPLOY = 3

Kid.options = Fx.options
Kid.area = Fx.area

--- The time a card takes: the Lunchbox makes your first Lure of the fight free.
function Kid.cost(s, id)
    local def = Cards[id]
    if def.type == "lure" and s.items and s.items.lunchbox and not s.lunchUsed then return 0 end
    return def.cost
end

--- Can this card be played at all right now? (A house rule can forbid it: "No Lures in my sandbox!")
function Kid.playable(s, id)
    local o = Fx.options(s, id, {})
    return o ~= nil and #o.items > 0
end

--- Play the card at hand[handIndex] with a complete selection. o.noClock applies the effect only (previews).
function Kid.play(s, handIndex, sel, o)
    o = o or {}
    if s.winner or s.phase ~= "fight" then return false, "not now" end
    local id = s.hand[handIndex]
    if not id then return false, "no such card" end
    if not Fx.validate(s, id, sel) then return false, "bad selection" end
    local def = Cards[id]
    local cost = Kid.cost(s, id)
    if def.type == "lure" and s.items and s.items.lunchbox then s.lunchUsed = true end
    table.remove(s.hand, handIndex)
    if def.exhaust then s.exhaust[#s.exhaust + 1] = id else s.discard[#s.discard + 1] = id end
    s.stats.cards = s.stats.cards + 1
    State.emit(s, "card", { card = id, cost = cost, sel = sel })
    Fx.apply(s, id, sel)
    Rules.check(s)
    if cost > 0 and not s.winner and not o.noClock then Clock.advance(s, cost) end
    return true
end

--- Wait: costs 1 tick and lets the bugs act.
function Kid.wait(s)
    if s.winner or s.phase ~= "fight" then return false end
    State.emit(s, "wait", {})
    Clock.advance(s, 1)
    return true
end

--- Close the lid (Bug Hunts): the hunt ends now and you keep what's in the jar. It takes no time.
function Kid.closeLid(s)
    if s.winner or s.phase ~= "fight" or not (s.rule and s.rule.id == "jar") then return false end
    State.emit(s, "lid", {})
    Rules.endHunt(s, "lid")
    return true
end

--- Light 1, Medium 2, Heavy 3 ticks. With Sneakers, 1 less (never less than 1).
function Kid.releaseCost(speciesId, s)
    local w = Bugs[speciesId].weight
    if s and s.items and s.items.sneakers then return math.max(1, w - 1) end
    return w
end

function Kid.homeFree(s, x, y)
    local c = Grid.cell(s, x, y)
    return c ~= nil and not c.void and Grid.isHomeRow(s, "kid", y) and not c.block and not c.trap
        and not (c.puddle and c.cover ~= "leaf") and not State.at(s, x, y)
end

--- Where the jar can be laid on a hunt: a free tile of your home rows with nothing on it.
function Kid.trapFree(s, x, y)
    local c = Grid.cell(s, x, y)
    return Kid.homeFree(s, x, y) and not c.food and not c.cover
end

--- Lay the jar on its side on (x, y) (deploy phase of a Bug Hunt). It stays there for the whole hunt.
function Kid.placeTrap(s, x, y)
    if s.phase ~= "deploy" or not (s.rule and s.rule.id == "jar") then return false, "not now" end
    if not Kid.trapFree(s, x, y) then return false, "tile" end
    if s.trapAt then Grid.cell(s, s.trapAt.x, s.trapAt.y).trap = nil end
    Grid.cell(s, x, y).trap = true
    s.trapAt = { x = x, y = y }
    State.emit(s, "trap", { x = x, y = y })
    return true
end

local function spawnFromJar(s, entry, x, y)
    local sp = Bugs[entry.species]
    local spots = { { x = x, y = y } }
    -- a merged ("bigger and better") entry: one more ant in a colony, one more heart for anybody else
    local n = sp.colony and (sp.colony + (entry.big and 1 or 0)) or 1
    local bonus = (entry.big and not sp.colony) and 1 or 0
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
        local b = State.spawnBug(s, entry.species, "kid", p.x, p.y, { jarUid = entry.uid, bonus = bonus })
        State.emit(s, "spawn", { id = b.id, species = entry.species, side = "kid", x = p.x, y = p.y })
        R.arrive(s, b)
        made[#made + 1] = b
    end
    for _, b in ipairs(made) do R.reactions(s, b) end
    return made
end

--- Release a bug from the Jar onto an empty home tile: Light 1, Medium 2, Heavy 3 ticks. Not on a hunt: the bugs that
--- stayed home are safe at home.
function Kid.release(s, jarIndex, x, y)
    if s.winner or s.phase ~= "fight" then return false, "not now" end
    if s.hunt then return false, "hunt" end
    local entry = s.jar[jarIndex]
    if not entry then return false, "no such bug" end
    if not Kid.homeFree(s, x, y) then return false, "tile" end
    table.remove(s.jar, jarIndex)
    State.emit(s, "release", { species = entry.species, x = x, y = y })
    spawnFromJar(s, entry, x, y)
    Rules.check(s)
    if not s.winner then Clock.advance(s, Kid.releaseCost(entry.species, s)) end
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

--- Ends the deploy phase: shuffle the deck and draw the opening hand (one more with the Lucky Marble). On a hunt, the
--- bugs that weren't picked stay home.
function Kid.start(s)
    if s.phase ~= "deploy" then return false end
    if s.hunt and not s.trapAt then return false, "jar" end
    s.phase = "fight"
    if s.hunt then s.jar = {} end
    if not s.scriptedHand then
        U.shuffle(s, s.deck)
        Deck.draw(s, Deck.START_HAND + ((s.items and s.items.lucky) and 1 or 0))
    end
    Rival.begin(s)
    State.emit(s, "start", {})
    return true
end

return Kid
