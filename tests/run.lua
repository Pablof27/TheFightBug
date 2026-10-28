-- Headless tests for the simulation. Run from the repo root:  lua tests/run.lua
-- (plain Lua 5.1-5.4 / LuaJIT; no LÖVE needed)

package.path = "src/?.lua;" .. package.path

local State = require("sim.state")
local Grid = require("sim.grid")
local Fight = require("sim.fight")
local Kid = require("sim.kid")
local Clock = require("sim.clock")
local Forecast = require("sim.forecast")
local R = require("sim.resolver")
local Q = require("sim.query")
local Encounters = require("data.encounters")

local passed, failed = 0, 0
local VERBOSE = arg and arg[1] == "-v"

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("  ok   " .. name)
    else failed = failed + 1; print("  FAIL " .. name .. "\n         " .. tostring(err)) end
end

local function eq(a, b, msg)
    if a ~= b then error((msg or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "expected truthy", 2) end end

local LETTER = { ant = "a", redant = "r", pillbug = "P", stag = "S", mantis = "M", spider = "T", cricket = "C", wasp = "W", hercules = "H" }
local function dump(s)
    local out = {}
    for y = s.h, 1, -1 do
        local line = y .. "  "
        for x = 1, s.w do
            local b = State.at(s, x, y)
            local c = Grid.cell(s, x, y)
            if b then
                line = line .. (b.side == "kid" and LETTER[b.species] or LETTER[b.species]:upper()) .. (b.ready and "!" or b.timer) .. " "
            elseif c.food then line = line .. (c.food.kind:sub(1, 1) == "l" and "$ " or "+ ")
            elseif c.block then line = line .. "# "
            elseif c.puddle then line = line .. "~ "
            else line = line .. ". " end
        end
        out[#out + 1] = line
    end
    return table.concat(out, "\n")
end

local function find(s, species, side)
    for _, b in ipairs(s.bugs) do if b.species == species and (not side or b.side == side) then return b end end
end
local function at(s, x, y) return State.at(s, x, y) end
local function handIndex(s, card) for i, c in ipairs(s.hand) do if c == card then return i end end error("card not in hand: " .. card) end
local function play(s, card, ...) local ok, err = Kid.play(s, handIndex(s, card), { ... }); if not ok then error("play failed: " .. tostring(err), 2) end end
local function events(s, kind)
    local n = {}
    for _, e in ipairs(s.log) do if e.type == kind then n[#n + 1] = e end end
    return n
end

local function sandbox() return Fight.new(Encounters[1], { seed = 7 }) end

print("GDD §5.13 worked example")

test("shadow delays the wasp, sugar + wait lures it into the Ready mantis", function()
    local s = sandbox()
    local wasp = at(s, 2, 4)
    eq(wasp.species, "wasp"); eq(wasp.timer, 1)
    local antIds = { at(s, 1, 2).id, at(s, 2, 2).id, at(s, 3, 2).id }
    play(s, "shadow", wasp.id)
    eq(wasp.timer, 2, "shadow: wasp timer")
    eq(s.tick, 0, "shadow costs no time")
    play(s, "sugar", { x = 5, y = 4 })
    eq(s.tick, 1, "sugar costs 1 tick")
    eq(wasp.timer, 1); eq(find(s, "stag").timer, 2); eq(at(s, 1, 2).timer, 1)
    s.log = {}
    Kid.wait(s)
    eq(s.tick, 2)
    truthy(wasp.gone, "wasp scurried off")
    eq(#events(s, "scurry"), 1)
    local mantis = find(s, "mantis")
    eq(mantis.hp, 2, "mantis is unharmed"); eq(mantis.ready, false, "mantis spent its ambush"); eq(mantis.timer, 3)
    truthy(Grid.cell(s, 5, 4).food ~= nil, "sugar is still there: the wasp never got to eat it")
    -- the ants walked 2 tiles each towards the sugar (they went first)
    local moved = 0
    for _, e in ipairs(events(s, "move")) do if e.id == antIds[1] or e.id == antIds[2] or e.id == antIds[3] then moved = moved + 1 end end
    eq(moved, 6, "three ants x 2 steps")
    -- the wasp's alarm made the other wasp hurry up
    eq(find(s, "wasp").timer, 1, "alarm: the second wasp gets -1 timer")
    if VERBOSE then print(dump(s)) end
end)

test("the stag beetle charges down column D and the pill bug curls and rolls away", function()
    local s = sandbox()
    local stag = find(s, "stag")
    stag.timer = 1
    local pill = find(s, "pillbug")
    s.log = {}
    Kid.wait(s)
    local rams = {}
    for _, e in ipairs(events(s, "attack")) do if e.kind == "ram" then rams[#rams + 1] = e end end
    eq(#rams, 1, "one ram")
    eq(stag.x, 4); eq(stag.y, 3, "stag ended next to the pill bug")
    truthy(pill.curled, "pill bug curled"); eq(pill.hp, 3, "and took no damage")
    eq(pill.y, 1, "it rolled to the south wall")
    truthy(#events(s, "bump") >= 1, "and bumped into it")
    if VERBOSE then print(dump(s)) end
end)

print("Rules")

test("pushes respect weight: a Heavy bug resists a Flick but not a Shove", function()
    local s = sandbox()
    local stag = find(s, "stag")
    local Fx = require("sim.cardfx")
    local opts = Fx.options(s, "flick", {})
    for _, it in ipairs(opts.items) do eq(it.id == stag.id, false, "stag must not be flickable") end
    local shove = Fx.options(s, "shove", {})
    local found = false
    for _, it in ipairs(shove.items) do if it.id == stag.id then found = true end end
    truthy(found, "stag can be shoved")
end)

test("bumping into a wall or a bug dazes everyone involved (+1 timer), no damage", function()
    local s = sandbox()
    local ant = at(s, 1, 2)
    local t0 = ant.timer
    R.push(s, ant, -1, 0, "test")      -- west wall
    eq(ant.timer, t0 + 1); eq(ant.x, 1); eq(ant.hp, 1)
    local a2, a3 = at(s, 2, 2), at(s, 3, 2)
    local t2, t3 = a2.timer, a3.timer
    R.push(s, a2, 1, 0, "test")        -- into the next ant
    eq(a2.timer, t2 + 1); eq(a3.timer, t3 + 1, "both are dazed")
end)

test("ready ambusher strikes the first enemy that steps next to it, mid-move", function()
    local s = sandbox()
    local wasp = at(s, 2, 4)
    R.push(s, wasp, 1, 0, "test")      -- B4 -> C4, not adjacent
    truthy(not wasp.gone)
    R.push(s, wasp, 1, 0, "test")
    R.push(s, wasp, 1, 0, "test")      -- E4: adjacent to the mantis at E3
    truthy(wasp.gone, "wasp scurried off")
end)

test("a soaked bug is delayed by 2 and cannot walk further into the water", function()
    local s = sandbox()
    local ant = at(s, 1, 2)
    local c = Grid.cell(s, 1, 1); c.puddle = true
    local t0 = ant.timer
    R.push(s, ant, 0, -1, "test")
    eq(ant.y, 1); eq(ant.timer, t0 + 2); truthy(ant.soaked)
end)

test("cloning is independent: previews never touch the real fight", function()
    local s = sandbox()
    local before = Forecast.signature(s)
    local c = State.clone(s)
    Clock.advance(c, 5)
    eq(Forecast.signature(s), before)
    truthy(Forecast.signature(c) ~= before)
end)

test("forecast of the next tick equals what really happens", function()
    local s = sandbox()
    play(s, "sugar", { x = 5, y = 4 })
    local f = Forecast.compute(s)
    local predicted = Forecast.signature(f.after)
    Kid.wait(s)
    eq(Forecast.signature(s), predicted)
end)

print("Determinism")

test("same inputs, same fight (event log hash)", function()
    local function run()
        local s = sandbox()
        play(s, "shadow", at(s, 2, 4).id)
        play(s, "sugar", { x = 5, y = 4 })
        Kid.wait(s); Kid.wait(s); Kid.wait(s)
        local parts = {}
        for _, e in ipairs(s.log) do parts[#parts + 1] = e.type .. (e.id or "") .. (e.x or "") .. (e.y or "") end
        return table.concat(parts, ",")
    end
    eq(run(), run())
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
