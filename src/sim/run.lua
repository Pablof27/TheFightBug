-- The run layer (GDD §8, "One Summer Day"): one day at the park in three acts. A run is plain data (it IS the save file,
-- sim/save.lua) and the whole run layer is pure Lua, so it can be played and tested headlessly.
--
--   run.phase  "prologue"  the warm-up offer: the tutorial fight, played "for fair" (no marbles), or skip it
--              "zone"      pick 1 of 2 zones of the park; each shows the Gang leader you'll face there
--              "free"      free time on the park screen. window 1: before the kid's duel; window 2: before the Gang
--                          leader's (the Ice-Cream Van is there). Bug Hunts (sim/hunt.lua), the bench and events
--                          (sim/park.lua), the van (sim/shop.lua)
--              "duel"      a duel is on: run.duel (sim/duel.lua)
--              "reward"    the act is done: pick 1 of 3 pocket items (+1 Jar slot)
--              "over"      the day is over: run.result = { won, why }
--
-- Marbles are the only stakes (GDD D-007): the day ends when you are broke. Knocked-out bugs nap (GDD §8.7): a napping
-- bug can't play until it has sat out one duel round. Everything random comes from the run's seed through Run.gen, one
-- generator per purpose, so nothing has to be stored and a saved day plays on exactly as it would have.

local U = require("sim.util")
local Park = require("data.park")
local Rivals = require("data.rivals")
local Items = require("data.items")
local Encounters = require("data.encounters")

local Run = {}

Run.STARTER_DECK = { "flick", "flick", "flick", "crumb", "crumb", "stick", "stick", "shadow", "sun", "water" }
-- The starting Jar: the bugs of the warm-up (in the order of its uids 1-5).
Run.STARTER_JAR = { "ant", "pillbug", "mantis", "cricket", "spider" }
Run.ACTS = #Park.acts
Run.PHASES = { prologue = true, zone = true, free = true, duel = true, reward = true, over = true }
-- Seeds have up to 9 digits: a fight is seeded with Run.fightSeed (seed * 131 + fights + 1), and the generator's first
-- step (sim/util.lua) multiplies that by 48271, which has to stay below 2^53 to be exact in LuaJIT's doubles.
Run.SEED_MAX = 999999999

local function contains(list, v)
    for _, x in ipairs(list or {}) do if x == v then return true end end
    return false
end
Run.contains = contains

function Run.new(seed)
    local deck = U.copyArray(Run.STARTER_DECK)
    deck[#deck + 1] = "sugar"    -- the warm-up's gift: a sugar cube from your pocket
    local run = {
        seed = seed or 1,
        marbles = Park.START_MARBLES,
        deck = deck, jar = {}, nextUid = 1, jarSlots = Park.JAR_SLOTS,
        items = {},
        act = 1, phase = "prologue", window = 1,
        buzz = 0, visits = {}, stacks = {},
        bigSister = true,
        fights = 0, wins = 0, losses = 0, duels = 0, broke = 0, hunts = 0, caught = 0, rewinds = 0,
        faced = {}, seen = {}, released = {}, lost = {},
    }
    for _, sp in ipairs(Run.STARTER_JAR) do Run.addBug(run, sp) end
    return run
end

--- A seeded generator for one purpose of the day (zones of act 2, the van's 3rd restock...). Same seed, same tag, same rolls.
function Run.gen(run, tag) return { rng = U.seedOf(tostring(run.seed) .. "|" .. tag) } end

function Run.actDef(run) return Park.acts[run.act] end
function Run.prices(run) return Park.acts[run.act].prices end

function Run.has(run, item) return contains(run.items, item) end

--- The seed of the next fight's random generator (its deck shuffles): the run's seed and how many fights came before.
function Run.fightSeed(run) return (run.seed or 1) * 131 + (run.fights or 0) + 1 end

-- ───────────────────────── the Jar ─────────────────────────

function Run.addCard(run, card) run.deck[#run.deck + 1] = card end

--- A new bug joins the Jar (bought, swapped, or caught when no bug of its kind can grow). The Jar can end up over its
--- slots: then you have to let somebody go before doing anything else (Run.overflow, Run.letGo).
function Run.addBug(run, species)
    local e = { uid = run.nextUid, species = species }
    run.nextUid = run.nextUid + 1
    run.jar[#run.jar + 1] = e
    run.seen[species] = true
    return e
end

--- A caught bug: it merges into a bug of the same species that hasn't grown yet ("a bigger one!": +1 stamina, or +1 ant
--- in a colony), or it takes a new slot. Returns "merged" | "added", entry.
function Run.addCaught(run, species)
    run.seen[species] = true
    for _, e in ipairs(run.jar) do
        if e.species == species and not e.big then
            e.big = true
            return "merged", e
        end
    end
    return "added", Run.addBug(run, species)
end

function Run.entry(run, uid)
    for i, e in ipairs(run.jar) do if e.uid == uid then return e, i end end
end

--- How many bugs have to go free before the Jar fits in its slots again.
function Run.overflow(run) return math.max(0, #run.jar - run.jarSlots) end

--- Let a bug go: it walks back into the grass for good.
function Run.letGo(run, uid)
    local e, i = Run.entry(run, uid)
    if not e then return false end
    table.remove(run.jar, i)
    run.released[#run.released + 1] = e.species
    return true
end

--- The Jar entries that can play (not napping), as copies for a fight.
function Run.available(run)
    local out = {}
    for _, e in ipairs(run.jar) do
        if not e.nap then out[#out + 1] = { uid = e.uid, species = e.species, big = e.big } end
    end
    return out
end

function Run.anyNapping(run)
    for _, e in ipairs(run.jar) do if e.nap then return true end end
    return false
end

function Run.wakeAll(run)
    for _, e in ipairs(run.jar) do e.nap = nil end
end

--- Jar entries every one of whose bugs was knocked out in this fight (s.field, by uid). Ant colonies count only when all
--- their ants are out. On a hunt, f.escaped tells how many of them got away.
function Run.knockedOut(run, s)
    local out = {}
    for _, e in ipairs(run.jar) do
        local f = s.field[e.uid]
        if f and f.total > 0 and f.lost >= f.total then out[#out + 1] = { entry = e, field = f } end
    end
    return out
end

--- The Bug Journal: every species met in a fight gets a page. Returns the new ones, rivals' first (they are the ones
--- worth reading about).
function Run.meet(run, s)
    local met, new = {}, {}
    for sp in pairs(s.met or {}) do met[#met + 1] = sp end
    table.sort(met)
    for _, sp in ipairs(met) do
        if not run.seen[sp] then
            run.seen[sp] = true
            if s.metRival and s.metRival[sp] then table.insert(new, 1, sp) else new[#new + 1] = sp end
        end
    end
    return new
end

-- ───────────────────────── the day ─────────────────────────

--- The warm-up: the tutorial fight (GDD §5.13), played "for fair". No marbles change hands and nobody naps.
function Run.prologueEncounter() return Encounters[1] end

--- The warm-up was played (s = its fight) or skipped (s = nil): on to the first zone.
function Run.endPrologue(run, s)
    if run.phase ~= "prologue" then return false end
    if s then Run.meet(run, s) end
    run.phase = "zone"
    Run.offerZones(run)
    return true
end

--- Two of the three zones, each with one of the act's two Gang leaders. The zone you just left is offered last.
function Run.offerZones(run)
    local act = Run.actDef(run)
    local g = Run.gen(run, "zones:" .. run.act)
    local ids = U.shuffle(g, { "sandbox", "lawn", "stump" })
    if run.lastZone and (ids[1] == run.lastZone or ids[2] == run.lastZone) then
        for i = 1, 2 do if ids[i] == run.lastZone then ids[i], ids[3] = ids[3], ids[i] end end
    end
    local leaders = U.shuffle(g, U.copyArray(act.leaders))
    run.offer = { { zone = ids[1], leader = leaders[1] }, { zone = ids[2], leader = leaders[2] } }
end

--- The stack a rival brings to this act: kids by how rich they are, Gang leaders the act's leader stack.
function Run.stackOf(run, rivalId, leader)
    local act = Run.actDef(run)
    if leader then return act.leaderStack end
    return act.kidStacks[Rivals[rivalId].wealth or 2]
end

--- Pick zone i of the offer: its Gang leader, two kids to choose from (rivals you have met least first), everybody's stack.
function Run.pickZone(run, i)
    local o = run.offer and run.offer[i]
    if run.phase ~= "zone" or not o then return false end
    local act = Run.actDef(run)
    run.zone, run.leader, run.offer = o.zone, o.leader, nil
    local ids = {}
    for id, rv in pairs(Rivals) do
        if not rv.leaderOnly and not contains(act.leaders, id) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    U.shuffle(Run.gen(run, "kids:" .. run.act), ids)
    local order = {}
    for k, id in ipairs(ids) do order[k] = { id = id, met = run.faced[id] or 0, k = k } end
    table.sort(order, function(a, b) if a.met ~= b.met then return a.met < b.met end return a.k < b.k end)
    run.kids = { order[1].id, order[2].id }
    run.stacks = {}
    for _, k in ipairs(run.kids) do run.stacks[k] = Run.stackOf(run, k, false) end
    run.stacks[run.leader] = Run.stackOf(run, run.leader, true)
    Run.enterFree(run, 1)
    return true
end

--- Free time begins. The Buzz is back to 0 (a duel calms the park down); window 2 brings the Ice-Cream Van.
function Run.enterFree(run, window)
    run.phase, run.window = "free", window
    run.buzz = 0
    if window == 1 then
        run.visits, run.bench, run.bandaid, run.van, run.fed = {}, nil, nil, nil, nil
    else
        run.van = { restocks = 0, sold = {} }
    end
    Run.rollEvent(run)
end

--- About every other free time something is going on in the park (GDD §8.9). Resolved in sim/park.lua.
function Run.rollEvent(run)
    run.event = nil
    local g = Run.gen(run, "event:" .. run.act .. ":" .. run.window)
    if U.rand(g, 2) ~= 1 then return end
    local kind = Park.EVENT_POOL[U.rand(g, #Park.EVENT_POOL)]
    local ev = { kind = kind }
    if kind == "swap" then
        ev.give = Park.SWAP_POOL[U.rand(g, #Park.SWAP_POOL)]
        local mine = {}
        for _, e in ipairs(run.jar) do if e.species ~= ev.give then mine[#mine + 1] = e.uid end end
        if #mine == 0 then return end
        ev.want = mine[U.rand(g, #mine)]
    elseif kind == "ball" then
        ev.card = Park.BALL_CARDS[U.rand(g, #Park.BALL_CARDS)]
    end
    run.event = ev
end

--- The act is over. rewarded: you got past its Gang leader (not when Big Sister dragged you away). After the last act
--- there is nothing left to spend a reward on: the sun sets.
function Run.endAct(run, rewarded)
    run.van, run.event, run.kids, run.fed = nil, nil, nil, nil
    if rewarded and run.act < Run.ACTS then
        local owned, pool = {}, {}
        for _, id in ipairs(run.items) do owned[id] = true end
        for id in pairs(Items) do if not owned[id] then pool[#pool + 1] = id end end
        table.sort(pool)
        U.shuffle(Run.gen(run, "reward:" .. run.act), pool)
        run.rewardOffer = { pool[1], pool[2], pool[3] }
        if #run.rewardOffer > 0 then run.phase = "reward"; return end
        run.rewardOffer = nil
        run.jarSlots = run.jarSlots + 1
    end
    Run.nextAct(run)
end

--- Pick pocket item i of the act's reward (it comes with a bigger Jar).
function Run.pickReward(run, i)
    local id = run.rewardOffer and run.rewardOffer[i]
    if run.phase ~= "reward" or not id then return false end
    run.items[#run.items + 1] = id
    run.jarSlots = run.jarSlots + 1
    run.rewardOffer = nil
    Run.nextAct(run)
    return true
end

function Run.nextAct(run)
    if run.act >= Run.ACTS then
        run.phase = "over"
        run.result = { won = true, why = "sunset" }
        return
    end
    run.lastZone = run.zone
    run.act = run.act + 1
    run.zone, run.leader, run.stacks = nil, nil, {}
    run.phase = "zone"
    Run.offerZones(run)
end

--- You're broke and Big Sister has already helped once: you go home with empty pockets.
function Run.goHome(run)
    run.phase = "over"
    run.result = { won = false, why = "broke" }
end

function Run.over(run) return run.phase == "over" end

return Run
