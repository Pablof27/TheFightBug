-- Fuzz + balance runner.   lua tests/bots.lua [fights per encounter] [random|greedy]
-- Checks invariants after every action (no crashes, every fight ends) and prints win rates and a "butterfly" measure.

local B = require("tests.botlib")
local Forecast = require("sim.forecast")
local Encounters = require("data.encounters")
local Cards = require("data.cards")

local N = tonumber(arg and arg[1]) or 40
local POLICY = (arg and arg[2]) or "random"

for _, enc in ipairs(Encounters) do
    local r = { fights = 0, wins = 0, ticks = 0, decisions = 0, sun = 0 }
    local t0 = os.clock()
    for seed = 1, N do
        local s = B.setup(enc, seed)
        local steps = 0
        while not s.winner and steps < 200 do
            local a = B.choose(s, POLICY)
            local ok, err = pcall(B.apply, s, a)
            assert(ok, "apply failed: " .. tostring(err))
            B.invariants(s)
            steps = steps + 1
        end
        assert(s.winner, "fight did not finish in " .. steps .. " decisions")
        r.fights = r.fights + 1
        if s.winner == "kid" then r.wins = r.wins + 1 end
        if s.why == "sun" then r.sun = r.sun + 1 end
        r.ticks = r.ticks + s.tick
        r.decisions = r.decisions + steps
    end
    print(string.format("%-18s %-6s bot: %3d fights  win %3.0f%%  avg %4.1f ticks  %4.1f decisions  %3.0f%% ended by the Sun clock  (%.1fs)",
        enc.name, POLICY, r.fights, 100 * r.wins / r.fights, r.ticks / r.fights, r.decisions / r.fights, 100 * r.sun / r.fights, os.clock() - t0))
end

-- Bug Hunts: every spot at every Buzz, with the starting Jar. Fuzzes the jar trap and loose bugs (sim/trap.lua).
do
    local Run = require("sim.run")
    local Hunt = require("sim.hunt")
    local Fight = require("sim.fight")
    local Kid = require("sim.kid")
    local Park = require("data.park")
    local r = { hunts = 0, caught = 0, loose = 0, escaped = 0, rescued = 0, ticks = 0 }
    local t0 = os.clock()
    for zone, z in pairs(Park.zones) do
        for _, spot in ipairs(z.spots) do
            for buzz = 0, Park.BUZZ_MAX do
                for seed = 1, math.max(1, math.floor(N / 10)) do
                    local run = Run.new(seed)
                    run.phase, run.zone, run.buzz = "free", zone, buzz
                    local s = Fight.new(Hunt.encounter(run, spot), { jar = Run.available(run), deck = run.deck, seed = seed })
                    Fight.autoDeploy(s)
                    assert(Kid.start(s), "the hunt starts")
                    local steps = 0
                    while not s.winner and steps < 120 do
                        local a = B.choose(s, POLICY)
                        if not (POLICY == "random" and a.kind == "lid" and steps < 6) then
                            local ok, err = pcall(B.apply, s, a)
                            assert(ok, "apply failed: " .. tostring(err))
                            B.invariants(s)
                        end
                        steps = steps + 1
                    end
                    if not s.winner then Kid.closeLid(s) end
                    assert(s.winner == "kid", "a hunt can't be lost")
                    for _, b in ipairs(s.bugs) do assert(not b.loose, "nobody is left loose when a hunt is over") end
                    r.hunts = r.hunts + 1
                    r.caught = r.caught + #s.caught
                    r.ticks = r.ticks + s.tick
                    for _, f in pairs(s.field) do r.escaped = r.escaped + (f.escaped or 0); r.rescued = r.rescued + (f.rescued or 0) end
                    for _, e in ipairs(s.log) do if e.type == "loose" then r.loose = r.loose + 1 end end
                end
            end
        end
    end
    print(string.format("Bug Hunts         %-6s bot: %3d hunts  %.2f caught each  avg %4.1f ticks  %d knocked out (%d rescued, %d got away)  (%.1fs)",
        POLICY, r.hunts, r.caught / r.hunts, r.ticks / r.hunts, r.loose, r.rescued, r.escaped, os.clock() - t0))
end

-- Butterfly check: put one lure on every legal tile and count how many DIFFERENT futures that produces.
print("\nButterfly check (distinct futures / placements, after the card has been paid for)")
for _, enc in ipairs(Encounters) do
    local total, distinct, samples = 0, 0, 0
    for seed = 1, math.max(4, math.floor(N / 5)) do
        local s = B.setup(enc, 100 + seed)
        for _ = 1, 4 do if not s.winner then B.apply(s, B.choose(s, "random")) end end
        if not s.winner then
            for hi, id in ipairs(s.hand) do
                if #Cards[id].steps == 1 and Cards[id].steps[1] == "tile" and Cards[id].type == "lure" then
                    local sigs, n = {}, 0
                    for _, sel in ipairs(B.selections(s, id)) do
                        local c = Forecast.outcome(s, hi, sel)
                        if c then n = n + 1; sigs[Forecast.signature(c)] = true end
                    end
                    local d = 0
                    for _ in pairs(sigs) do d = d + 1 end
                    total, distinct, samples = total + n, distinct + d, samples + 1
                    break
                end
            end
        end
    end
    if samples > 0 then
        print(string.format("%-18s one lure on any free tile: %2d samples, %.0f%% of the placements end in a different future", enc.name, samples, 100 * distinct / total))
    end
end
