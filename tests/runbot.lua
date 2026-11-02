-- Whole-day bot: plays One Summer Day runs end to end through the simulation (no LÖVE), checking invariants after every
-- action, and prints how the days went: the Monte Carlo of the marble economy (GDD §8.12).
--   lua tests/runbot.lua [runs] [greedy|random] [hunts per free time] [-v]
-- The run decisions are simple, fixed heuristics (a careful but not clever player); the fights use the bots of botlib.

local B = require("tests.botlib")
local Run = require("sim.run")
local Duel = require("sim.duel")
local Hunt = require("sim.hunt")
local Shop = require("sim.shop")
local P = require("sim.park")
local Fight = require("sim.fight")
local Kid = require("sim.kid")
local Bugs = require("data.bugs")
local Park = require("data.park")

local N = tonumber(arg and arg[1]) or 10
local POLICY = (arg and arg[2]) or "greedy"
local HUNTS = tonumber(arg and arg[3]) or 2
local VERBOSE = false
for _, a in ipairs(arg or {}) do if a == "-v" then VERBOSE = true end end

local function say(...) if VERBOSE then print(...) end end

--- Play one fight to the end. Returns the finished state.
local function play(run, enc, steps)
    local s = Fight.new(enc, { jar = Run.available(run), deck = run.deck, seed = Run.fightSeed(run), items = run.items })
    if s.phase == "deploy" then
        Fight.autoDeploy(s)
        assert(Kid.start(s), "the fight starts")
    end
    local n = 0
    while not s.winner and n < (steps or 300) do
        local a = B.choose(s, POLICY)
        local ok, err = pcall(B.apply, s, a)
        assert(ok, "apply failed: " .. tostring(err))
        B.invariants(s)
        n = n + 1
    end
    assert(s.winner, "fight did not finish in " .. n .. " decisions")
    return s
end

local function price(sp) return Bugs[sp].price or 6 end

--- Let go of the cheapest bug until the Jar fits.
local function fitJar(run)
    while Run.overflow(run) > 0 do
        local worst
        for _, e in ipairs(run.jar) do
            if not worst or price(e.species) < price(worst.species) then worst = e end
        end
        assert(Run.letGo(run, worst.uid))
    end
end

local function freeTime(run, st)
    fitJar(run)
    local ev = run.event
    if ev then
        if ev.kind == "swap" then
            local e = P.swapEntry(run)
            P.answer(run, e and price(ev.give) >= price(e.species))
        elseif ev.kind == "ball" then
            P.dismiss(run)
        else
            P.answer(run, true)
        end
    end
    -- hunt at the spot with the best prize while the Buzz is low
    while run.buzz < HUNTS and Hunt.can(run) do
        local best, bv
        for _, id in ipairs(Hunt.spots(run)) do
            local v = price(Hunt.prizeAt(id, run.buzz))
            if not bv or v > bv then best, bv = id, v end
        end
        local s = play(run, Hunt.encounter(run, best))
        local sum = Hunt.settle(run, s)
        st.hunts = st.hunts + 1
        st.caught = st.caught + #sum.caught
        st.lost = st.lost + #sum.lost
        say(string.format("  hunt %-22s caught %d, napping %d, lost %d", Park.spots[best].name, #sum.caught, #sum.napped, #sum.lost))
        fitJar(run)
    end
    if not run.bench and Run.anyNapping(run) then P.bench(run, "wake") end
    -- the van: spend at most a quarter of your marbles, a thing at a time
    if Shop.isOpen(run) then
        for _, it in ipairs(Shop.stock(run)) do
            if it.kind ~= "remove" and it.price <= run.marbles * 0.25 and Shop.check(run, it) then
                Shop.buy(run, it)
                st.bought = st.bought + 1
            end
        end
    end
end

local function duel(run, st)
    local d = run.duel
    while not d.over do
        if Duel.forfeitSide(run) then
            Duel.forfeit(run)
            st.forfeits = st.forfeits + 1
        else
            local stake, round = Duel.stake(run), d.round
            local s = play(run, Duel.encounter(run))
            local rec = Duel.settle(run, s)
            st.rounds = st.rounds + 1
            if round == 3 then st.showdowns = st.showdowns + 1 end
            say(string.format("  round %d %-9s stake %3d  %-5s (%s)  you %d, %s %d", round, rec.rule, stake, tostring(rec.winner), tostring(rec.why), run.marbles, d.rival, run.stacks[d.rival]))
        end
    end
    if d.over.why == "sister" then st.sister = true end
    if d.offer then
        for i, o in ipairs(d.offer) do
            if o.price <= run.marbles * 0.2 and Duel.takeOffer(run, i) then break end
        end
    end
    say(string.format("  duel vs %s over: %s", d.rival, d.over.why))
    Duel.leave(run)
    fitJar(run)
end

local totals = { won = 0, runs = 0, marbles = 0, acts = 0, rounds = 0, hunts = 0, caught = 0, lost = 0, showdowns = 0, sister = 0, forfeits = 0, bought = 0, duels = 0 }
local reached = { 0, 0, 0 }
local t0 = os.clock()
for seed = 1, N do
    local run = Run.new(seed)
    local st = { rounds = 0, hunts = 0, caught = 0, lost = 0, showdowns = 0, forfeits = 0, bought = 0 }
    Run.endPrologue(run)
    local guard = 0
    while not Run.over(run) do
        guard = guard + 1
        assert(guard < 200, "the day never ends")
        if run.phase == "zone" then
            say(string.format("ACT %d: %s with %s, or %s with %s", run.act, run.offer[1].zone, run.offer[1].leader, run.offer[2].zone, run.offer[2].leader))
            Run.pickZone(run, 1 + seed % 2)
            reached[run.act] = reached[run.act] + 1
        elseif run.phase == "free" then
            freeTime(run, st)
            local who = Duel.challengers(run)
            local pick = who[1]
            if #who > 1 and run.stacks[who[2]] < run.stacks[who[1]] then pick = who[2] end
            assert(Duel.start(run, pick), "the duel starts")
            say(string.format(" duel vs %s (%d marbles, you %d)", pick, run.stacks[pick], run.marbles))
        elseif run.phase == "duel" then
            duel(run, st)
        elseif run.phase == "reward" then
            assert(Run.pickReward(run, 1))
        else
            error("stuck in phase " .. run.phase)
        end
        assert(require("sim.save").check(run), "the run must always be saveable")
    end
    local won = run.result.won
    totals.runs = totals.runs + 1
    if won then totals.won = totals.won + 1 end
    totals.marbles = totals.marbles + (won and run.marbles or 0)
    totals.acts = totals.acts + run.act
    totals.rounds = totals.rounds + st.rounds
    totals.hunts = totals.hunts + st.hunts
    totals.caught = totals.caught + st.caught
    totals.lost = totals.lost + st.lost
    totals.showdowns = totals.showdowns + st.showdowns
    totals.forfeits = totals.forfeits + st.forfeits
    totals.bought = totals.bought + st.bought
    totals.duels = totals.duels + run.duels
    if st.sister then totals.sister = totals.sister + 1 end
    print(string.format("seed %3d  %-6s act %d  marbles %4d  duels %d  rounds %2d (showdowns %d)  hunts %2d caught %2d lost %d  jar %d%s",
        seed, won and "SUNSET" or "HOME", run.act, run.marbles, run.duels, st.rounds, st.showdowns, st.hunts, st.caught, st.lost, #run.jar, st.sister and "  (Big Sister)" or ""))
end
local n = totals.runs
print(string.format("\n%d days, %s fights, %d hunt(s) per free time: finished %.0f%% · reached act 2 %.0f%%, act 3 %.0f%% · avg %.1f duel rounds, %.1f showdowns, %.1f hunts, %.1f caught, %.1f lost · Big Sister %.0f%% · winners' marbles %.0f · %.1fs",
    n, POLICY, HUNTS, 100 * totals.won / n, 100 * reached[2] / n, 100 * reached[3] / n, totals.rounds / n, totals.showdowns / n, totals.hunts / n, totals.caught / n, totals.lost / n,
    100 * totals.sister / n, totals.won > 0 and totals.marbles / totals.won or 0, os.clock() - t0))
