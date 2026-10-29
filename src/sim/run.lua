-- The run layer (GDD §8, trimmed for the demo): the kid's Jar, deck and marbles across a morning at the park.
-- Marbles are the stakes: every rival kid plays for a fixed bet (data/rivals.lua), you put up the same, and the winner
-- takes the pot. Marbles also buy cards and bugs at the Swap Shop (sim/shop.lua). If you can't cover the next rival's
-- bet, nobody will play with you and the day is over. Pure Lua like the rest of sim/, so it can be tested headlessly.

local Encounters = require("data.encounters")
local Rivals = require("data.rivals")

local Run = {}

Run.STARTER_DECK = { "flick", "flick", "flick", "crumb", "crumb", "stick", "stick", "shadow", "sun", "water" }
Run.NODES = { "sandbox", "lawn", "stump" }
Run.JAR_SLOTS = 6            -- at the start of the day; the Swap Shop sells a bigger Jar
Run.START_MARBLES = 5
-- Seeds have up to 9 digits: a fight is seeded with Run.fightSeed (seed * 131 + node), and the generator's first step
-- (sim/util.lua) multiplies that by 48271, which has to stay below 2^53 to be exact in LuaJIT's doubles.
Run.SEED_MAX = 999999999

function Run.new(seed)
    local deck = {}
    for i, c in ipairs(Run.STARTER_DECK) do deck[i] = c end
    deck[#deck + 1] = "sugar"    -- the tutorial's gift: a sugar cube from your pocket
    return {
        seed = seed or 1,
        deck = deck,
        jar = {
            { uid = 1, species = "ant" },
            { uid = 2, species = "pillbug" },
            { uid = 3, species = "mantis" },
            { uid = 4, species = "cricket" },
            { uid = 5, species = "spider" },
        },
        nextUid = 6, jarSlots = Run.JAR_SLOTS,
        marbles = Run.START_MARBLES,
        bought = {},    -- Swap Shop items already sold, by key (sim/shop.lua)
        node = 1, wins = 0, losses = 0,
        seen = {},      -- species met so far (Bug Journal)
        released = {},  -- species let go at sunset
    }
end

function Run.currentEncounter(run) return Run.NODES[run.node] end

--- The seed of the next fight's random generator (its deck shuffles): the run's seed and which fight it is.
function Run.fightSeed(run) return (run.seed or 1) * 131 + (run.node or 1) end

--- The encounter table of the next fight.
function Run.encounter(run)
    local id = Run.currentEncounter(run)
    for _, e in ipairs(Encounters) do if e.id == id then return e end end
end

--- What a rival kid bets, and so what you must put in the pot to fight them.
function Run.rivalBet(rivalId) return Rivals[rivalId].bet end

--- The bet of the next fight.
function Run.bet(run) return Run.rivalBet(Run.encounter(run).rival) end

function Run.canCover(run) return run.marbles >= Run.bet(run) end

--- Fold a finished fight into the run: the pot, tired / escaped bugs, Journal entries, and the next node after a win.
--- Returns a summary table for the screens that follow (marbles = what your marble count changed by).
function Run.finish(run, s)
    local bet = Run.rivalBet(s.rival.id)
    local sum = { won = s.winner == "kid", why = s.why, rival = s.rival.id, tired = {}, escaped = {}, bet = bet, pot = 2 * bet, marbles = 0, newSpecies = {} }
    for i = #run.jar, 1, -1 do
        local e = run.jar[i]
        local f = s.field[e.uid]
        if f and f.lost >= f.total then
            if e.tired then
                table.remove(run.jar, i)
                sum.escaped[#sum.escaped + 1] = e.species
            else
                e.tired = true
                sum.tired[#sum.tired + 1] = e.species
            end
        end
    end
    -- the Bug Journal: every species that took part, rivals first (they are the new ones worth reading about)
    local met = {}
    for sp in pairs(s.met or {}) do met[#met + 1] = sp end
    table.sort(met)
    for _, sp in ipairs(met) do
        if not run.seen[sp] then
            run.seen[sp] = true
            local rivalSide = s.metRival and s.metRival[sp]
            if rivalSide then table.insert(sum.newSpecies, 1, sp) else sum.newSpecies[#sum.newSpecies + 1] = sp end
        end
    end
    if sum.won then
        run.wins = run.wins + 1
        sum.marbles = bet                       -- the pot: your bet back plus the rival's
        run.marbles = run.marbles + bet
        if run.node < #Run.NODES then run.node = run.node + 1 else sum.last = true end
    else
        run.losses = run.losses + 1
        sum.marbles = -bet
        run.marbles = math.max(0, run.marbles - bet)
    end
    return sum
end

function Run.addCard(run, card) run.deck[#run.deck + 1] = card end

--- A bought bug joins the Jar (if there is room).
function Run.addBug(run, species)
    if #run.jar >= run.jarSlots then return false end
    run.jar[#run.jar + 1] = { uid = run.nextUid, species = species }
    run.nextUid = run.nextUid + 1
    return true
end

function Run.anyTired(run)
    for _, e in ipairs(run.jar) do if e.tired then return true end end
    return false
end

--- Tired bugs get a rest (a nap on the bench): they are healthy again.
function Run.rest(run)
    for _, e in ipairs(run.jar) do e.tired = nil end
end

--- The day is over when you can't cover the next rival's bet: nobody plays with a kid who can't pay up.
function Run.over(run) return not Run.canCover(run) end

return Run
