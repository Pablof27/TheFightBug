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
