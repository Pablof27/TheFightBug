-- The run layer (GDD §8, trimmed for the demo): the kid's Jar, deck and Spirit across a morning at the park.
-- Pure Lua like the rest of sim/, so it can be tested headlessly.

local Run = {}

Run.STARTER_DECK = { "flick", "flick", "flick", "crumb", "crumb", "stick", "stick", "shadow", "sun", "water" }
Run.NODES = { "sandbox", "lawn", "stump" }
Run.JAR_SLOTS = 6
Run.MAX_SPIRIT_LOSS = 3      -- demo only: the GDD has no cap (see design/02-demo-decisions.md, DD-72)

-- Rewards are scripted per fight so every demo plays the same way (the GDD draws them at random from a seeded pool).
Run.REWARDS = {
    sandbox = { cards = { "shove", "juice", "blow" }, bets = { "stag", "wasp" }, marbles = 3 },
    lawn = { cards = { "tap", "leaf", "pebble" }, bets = { "redant" }, marbles = 3 },
}

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
        nextUid = 6,
        spirit = 10, maxSpirit = 10, marbles = 0,
        node = 1, wins = 0, losses = 0,
        seen = {},      -- species met so far (Bug Journal)
        released = {},  -- species let go at sunset
    }
end

function Run.currentEncounter(run) return Run.NODES[run.node] end

--- Fold a finished fight into the run: tired / escaped bugs, Spirit, marbles, Journal entries.
--- Returns a summary table for the results screen.
function Run.finish(run, s)
    local sum = { won = s.winner == "kid", tired = {}, escaped = {}, spirit = 0, marbles = 0, newSpecies = {} }
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
        local r = Run.REWARDS[s.encounter]
        sum.marbles = r and r.marbles or 5
        run.marbles = run.marbles + sum.marbles
    else
        run.losses = run.losses + 1
        local left = 0
        for _, b in ipairs(s.bugs) do if b.side == "rival" then left = left + 1 end end
        sum.spirit = -math.min(Run.MAX_SPIRIT_LOSS, math.max(1, left))
        run.spirit = math.max(0, run.spirit + sum.spirit)
    end
    return sum
end

function Run.addCard(run, card) run.deck[#run.deck + 1] = card end

--- A caught or won bug joins the Jar (if there is room).
function Run.addBug(run, species)
    if #run.jar >= Run.JAR_SLOTS then return false end
    run.jar[#run.jar + 1] = { uid = run.nextUid, species = species }
    run.nextUid = run.nextUid + 1
    return true
end

--- Tired bugs get a rest (a Bench, a Band-Aid…): they are healthy again.
function Run.rest(run)
    for _, e in ipairs(run.jar) do e.tired = nil end
end

function Run.over(run) return run.spirit <= 0 end

return Run
