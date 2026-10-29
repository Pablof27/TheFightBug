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

-- A small custom fight on an empty 6x6 board. o: kid / rival = team lists, layout, hand, rule, rivalKid
local function arena(o)
    return Fight.new({
        id = "test", name = "Test", rule = o.rule or "lbs", rival = o.rivalKid or "bully", w = 6, h = 6,
        layout = o.layout, rivalTeam = o.rival or {}, kidTeam = o.kid or {}, hand = o.hand or {}, drawPile = {},
    }, { seed = 1 })
end
local function activated(s, id)
    for _, e in ipairs(s.log) do if e.type == "act" and e.id == id and not e.react then return true end end
    return false
end

print("GDD §5.13 worked example")

test("shadow delays the wasp, sugar + wait lures it into the Ready mantis", function()
    local s = sandbox()
    local wasp = at(s, 2, 4)
    eq(wasp.species, "wasp"); eq(wasp.timer, 0)
    local antIds = { at(s, 1, 2).id, at(s, 2, 2).id, at(s, 3, 2).id }
    play(s, "shadow", wasp.id)
    eq(wasp.timer, 1, "shadow: wasp timer")
    eq(s.tick, 0, "shadow costs no time")
    play(s, "sugar", { x = 5, y = 4 })
    eq(s.tick, 1, "sugar costs 1 tick")
    eq(wasp.timer, 0); eq(find(s, "stag").timer, 1); eq(at(s, 1, 2).timer, 0)
    eq(wasp.x, 2, "at 0 the wasp has not acted yet"); eq(#events(s, "move"), 0, "nobody moved during the sugar tick")
    s.log = {}
    Kid.wait(s)
    eq(s.tick, 2)
    truthy(wasp.gone, "wasp scurried off")
    eq(#events(s, "scurry"), 1)
    local mantis = find(s, "mantis")
    eq(mantis.hp, 2, "mantis is unharmed"); eq(mantis.ready, false, "mantis spent its ambush"); eq(mantis.timer, 2)
    truthy(Grid.cell(s, 5, 4).food ~= nil, "sugar is still there: the wasp never got to eat it")
    -- the ants walked 2 tiles each towards the sugar (they went first)
    local moved = 0
    for _, e in ipairs(events(s, "move")) do if e.id == antIds[1] or e.id == antIds[2] or e.id == antIds[3] then moved = moved + 1 end end
    eq(moved, 6, "three ants x 2 steps")
    -- the wasp's alarm made the other wasp hurry up
    eq(find(s, "wasp").timer, 0, "alarm: the second wasp gets -1 timer")
    if VERBOSE then print(dump(s)) end
end)

test("the stag beetle charges down column D and the pill bug curls and rolls away", function()
    local s = sandbox()
    local stag = find(s, "stag")
    stag.timer = 0
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

test("a bug at 0 acts on the NEXT tick, then goes back to its base timer", function()
    local s = arena({ kid = { { species = "ant", x = 1, y = 1, timer = 1 } }, rival = { { species = "pillbug", x = 6, y = 6, timer = 9 } } })
    local ant = find(s, "ant")
    Kid.wait(s)
    eq(ant.timer, 0, "1 -> 0")
    eq(ant.x * 10 + ant.y, 11, "at 0 it has not moved yet")
    truthy(not activated(s, ant.id), "and has not acted")
    s.log = {}
    Kid.wait(s)
    truthy(activated(s, ant.id), "it acts on the tick after reaching 0")
    truthy(ant.x * 10 + ant.y ~= 11, "and walks")
    eq(ant.timer, ant.baseTimer, "then its timer goes back to its base")
end)

test("a bug delayed while it waits to act this tick acts exactly one tick later", function()
    local s = arena({
        kid = { { species = "stag", x = 3, y = 1, timer = 0 } },
        rival = { { species = "stag", x = 3, y = 2, timer = 0 }, { species = "ant", x = 3, y = 3, timer = 0 } },
    })
    local rstag, rant = find(s, "stag", "rival"), find(s, "ant", "rival")
    s.log = {}
    Kid.wait(s)
    eq(#events(s, "bump"), 1, "our stag rammed theirs into their ant")
    truthy(not activated(s, rstag.id) and not activated(s, rant.id), "so both lose this tick")
    eq(rstag.timer, 0); eq(rant.timer, 0)
    s.log = {}
    Kid.wait(s)
    truthy(activated(s, rstag.id) and activated(s, rant.id), "and act on the very next one")
end)

test("speed-ups stop at 0: a bug can be made to act on the next tick, never on this one", function()
    local s = arena({
        kid = { { species = "cricket", x = 2, y = 2, timer = 1 }, { species = "ant", x = 3, y = 2, timer = 0 } },
        rival = { { species = "pillbug", x = 6, y = 6, timer = 9 } }, hand = { "sun" },
    })
    local cricket, ant = find(s, "cricket"), find(s, "ant")
    s.log = {}
    truthy(Kid.play(s, 1, { { x = 2, y = 2 } }, { noClock = true }))
    eq(cricket.timer, 0, "1 -> 0"); eq(ant.timer, 0, "0 stays 0")
    eq(#events(s, "timer"), 1, "nothing to announce for the ant")
    truthy(not activated(s, cricket.id) and not activated(s, ant.id), "nobody acts before time passes")
    s.log = {}
    Kid.wait(s)
    truthy(activated(s, cricket.id) and activated(s, ant.id), "both act on the next tick")
end)

test("the rival kid's signature move also waits one tick at 0", function()
    local s = arena({ kid = { { species = "pillbug", x = 1, y = 1, timer = 20 } }, rival = { { species = "pillbug", x = 6, y = 6, timer = 20 } } })
    local base, at0, acted = s.rival.base, nil, nil
    for _ = 1, base + 1 do
        s.log = {}
        Kid.wait(s)
        if s.rival.timer == 0 and not at0 then at0 = s.tick end
        if #events(s, "rival_act") > 0 then acted = s.tick end
    end
    eq(at0, base, "shows 0 after `base` ticks")
    eq(acted, base + 1, "stomps on the next one")
    eq(s.rival.timer, base, "and starts over")
end)

test("timers never show a negative number", function()
    local B = require("tests.botlib")
    for i, enc in ipairs(Encounters) do
        for seed = 1, 4 do
            local s = B.setup(enc, seed)
            local steps = 0
            while not s.winner and steps < 120 do
                s.log = {}
                B.apply(s, B.choose(s, "random"))
                steps = steps + 1
                for _, e in ipairs(s.log) do
                    if e.type == "timers" then
                        for _, t in ipairs(e.list) do truthy(t.timer >= 0, "timers event below 0 in fight " .. i) end
                        truthy(not e.rival or e.rival >= 0, "rival timer event below 0")
                    elseif e.type == "timer" or e.type == "rival_timer" then
                        truthy(e.timer >= 0, e.type .. " event below 0 in fight " .. i)
                    end
                end
                for _, b in ipairs(s.bugs) do truthy(b.timer >= 0, "bug timer below 0 between actions") end
                truthy(s.rival.timer >= 0, "rival timer below 0 between actions")
            end
        end
    end
end)

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

test("the kid sees Hidden bugs: Flick, Shove and Shadow can pick a rival hiding in the grass", function()
    local s = arena({
        layout = { "......", "...g..", "......", "......", "......", "......" },
        kid = { { species = "ant", x = 1, y = 1, timer = 5 } },
        rival = { { species = "ant", x = 4, y = 5, timer = 5 } },
    })
    local hider = find(s, "ant", "rival")
    truthy(Q.isHidden(s, hider), "the rival ant is Hidden in the grass")
    local Fx = require("sim.cardfx")
    for _, card in ipairs({ "flick", "shove", "shadow" }) do
        local found = false
        for _, it in ipairs(Fx.options(s, card, {}).items) do if it.id == hider.id then found = true end end
        truthy(found, card .. " can target it")
    end
    eq(#Q.visibleEnemies(s, find(s, "ant", "kid")), 0, "while the bugs still can't see it")
end)

test("nobody can stand on a stick: a jumper lands next to it and a push bumps into it", function()
    -- the jumper's best landing (next to the wasp, at D4) is a stick tile
    local s = arena({
        kid = { { species = "spider", x = 4, y = 1, timer = 0 } },
        rival = { { species = "wasp", x = 4, y = 5, timer = 9 } },
    })
    local Fx = require("sim.cardfx")
    Fx.apply(s, "stick", { { x = 4, y = 4 }, { dx = 1, dy = 0 } })
    local spider = find(s, "spider")
    Kid.wait(s)
    truthy(not Grid.cell(s, spider.x, spider.y).block, "the spider did not land on the stick (" .. Grid.name(spider.x, spider.y) .. ")")
    -- a flyer pushed towards a stick bumps instead of ending up on it
    local s2 = arena({
        kid = { { species = "pillbug", x = 1, y = 1, timer = 9 } },
        rival = { { species = "wasp", x = 2, y = 4, timer = 9 } },
    })
    Fx.apply(s2, "stick", { { x = 3, y = 4 }, { dx = 0, dy = -1 } })
    local wasp = find(s2, "wasp")
    local t0 = wasp.timer
    R.push(s2, wasp, 1, 0, "test")
    eq(wasp.x, 2, "the wasp stays put"); eq(wasp.timer, t0 + 1, "and is dazed")
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

print("Run layer: marbles are the stakes")

local function lawn() return Fight.new(Encounters[2], { jar = {}, deck = {}, seed = 3 }) end
local function itemOf(Shop, run, id)
    for _, it in ipairs(Shop.stock(run)) do if it.id == id then return it end end
    error("not in stock: " .. id)
end

test("a run starts with 5 marbles and no Spirit; every rival kid plays for a fixed bet", function()
    local Run = require("sim.run")
    local run = Run.new(1)
    eq(run.marbles, 5); eq(run.spirit, nil, "no Spirit any more"); eq(run.jarSlots, 6)
    eq(Run.bet(run), 2, "the Bully bets 2")
    run.node = 2; eq(Run.bet(run), 3, "Ant Farm Girl bets 3")
    run.node = 3; eq(Run.bet(run), 5, "the Rich Kid bets 5")
end)

test("win and you take the pot, lose and the rival keeps it; can't cover the bet and the day is over", function()
    local Run = require("sim.run")
    local run = Run.new(1)
    local s = sandbox(); s.winner = "kid"
    local sum = Run.finish(run, s)
    eq(sum.bet, 2); eq(sum.pot, 4, "the rival matched the bet"); eq(sum.marbles, 2)
    eq(run.marbles, 7); eq(run.wins, 1); eq(run.node, 2, "on to the next fight")
    s = lawn(); s.winner = "rival"
    sum = Run.finish(run, s)
    eq(sum.marbles, -3, "Ant Farm Girl's bet"); eq(run.marbles, 4); eq(run.node, 2, "a rematch, same fight")
    truthy(not Run.over(run), "4 marbles still cover her bet of 3")
    s = lawn(); s.winner = "rival"
    Run.finish(run, s)
    eq(run.marbles, 1); truthy(Run.over(run), "1 marble can't cover a bet of 3: the day is over")
end)

test("the Swap Shop opens after the first fight, sells each thing once and never touches the next bet", function()
    local Run, Shop = require("sim.run"), require("sim.shop")
    local run = Run.new(1)
    truthy(not Shop.isOpen(run), "no shop before the scripted first fight")
    run.node, run.marbles = 2, 7
    truthy(Shop.isOpen(run)); eq(#Shop.stock(run), 8)
    local deck = #run.deck
    local leaf = itemOf(Shop, run, "leaf")
    truthy(Shop.buy(run, leaf)); eq(run.marbles, 7 - leaf.price); eq(#run.deck, deck + 1); eq(run.deck[#run.deck], "leaf")
    local ok, why = Shop.buy(run, leaf)
    truthy(not ok); eq(why, "sold")
    ok, why = Shop.buy(run, itemOf(Shop, run, "stag"))
    truthy(not ok); eq(why, "reserve", "5 - 4 would leave less than her bet of 3"); eq(run.marbles, 5)
    truthy(Shop.buy(run, itemOf(Shop, run, "blow"))); eq(run.marbles, 3)
    for _, it in ipairs(Shop.stock(run)) do truthy(not Shop.check(run, it), it.id .. " must not be for sale any more") end
    truthy(Run.canCover(run), "shopping never leaves you short of the next bet")
    run.marbles = 20
    truthy(Shop.buy(run, itemOf(Shop, run, "shove")))
    run.node = 3
    truthy(Shop.check(run, itemOf(Shop, run, "shove")), "the next stop has its own stock, sold separately")
end)

test("bugs need room in the Jar, a bigger Jar adds a slot, a nap needs a Tired bug", function()
    local Run, Shop = require("sim.run"), require("sim.shop")
    local run = Run.new(1)
    run.node, run.marbles = 2, 30
    Run.addBug(run, "pillbug")
    eq(#run.jar, run.jarSlots, "the Jar is full")
    local wasp = itemOf(Shop, run, "wasp")
    local ok, why = Shop.buy(run, wasp)
    truthy(not ok); eq(why, "jar_full")
    truthy(Shop.buy(run, itemOf(Shop, run, "jar"))); eq(run.jarSlots, 7)
    truthy(Shop.buy(run, wasp)); eq(run.jar[#run.jar].species, "wasp"); truthy(run.seen.wasp, "in the Bug Journal")
    local nap = itemOf(Shop, run, "nap")
    ok, why = Shop.buy(run, nap)
    truthy(not ok); eq(why, "nobody_tired")
    run.jar[1].tired = true
    truthy(Shop.buy(run, nap)); eq(run.jar[1].tired, nil, "rested")
end)

print("Save files")

local function same(a, b, path)
    path = path or "run"
    if type(a) ~= "table" or type(b) ~= "table" then
        if a ~= b then error(path .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 0) end
        return
    end
    for k, v in pairs(b) do same(a[k], v, path .. "." .. tostring(k)) end
    for k, v in pairs(a) do if b[k] == nil then error(path .. "." .. tostring(k) .. ": unexpected " .. tostring(v), 0) end end
end

-- The next fight of a run as the fight scene builds it, after the shuffle and the first draw.
local function deal(run)
    local s = Fight.new(require("sim.run").encounter(run), { jar = run.jar, deck = run.deck, seed = require("sim.run").fightSeed(run) })
    Fight.autoDeploy(s)
    truthy(Kid.start(s), "the fight starts")
    return table.concat(s.hand, ",") .. " | " .. table.concat(s.deck, ",")
end

test("a saved run loads back exactly, so its seed deals the same fights", function()
    local Run, Shop, Save = require("sim.run"), require("sim.shop"), require("sim.save")
    local run = Run.new(123456789)
    run.slot = 2
    local s = sandbox(); s.winner = "kid"
    Run.finish(run, s)
    truthy(Shop.buy(run, itemOf(Shop, run, "leaf")))
    run.jar[1].tired, run.rewinds = true, 4
    local rec = assert(Save.decode(Save.encode({ run = run, savedAt = 1761745816 })))
    eq(rec.savedAt, 1761745816); eq(rec.ended, nil, "still going")
    eq(rec.run.slot, nil, "a file's slot is where it is, not what is in it")
    run.slot = nil
    same(rec.run, run)
    eq(deal(rec.run), deal(run), "same seed, same shuffle")
    local other = Save.decode(Save.encode({ run = run })).run
    other.seed = 987654321
    truthy(deal(other) ~= deal(run), "another seed shuffles another way")
end)

test("a finished day is kept as a record of how it ended", function()
    local Run, Save = require("sim.run"), require("sim.save")
    for _, won in ipairs({ true, false }) do
        local rec = assert(Save.decode(Save.encode({ run = Run.new(9), ended = { won = won } })))
        eq(rec.ended.won, won)
    end
end)

test("damaged or hand-edited save files are reported, never trusted", function()
    local Run, Save = require("sim.run"), require("sim.save")
    local json = require("engine.utils.json")
    for _, text in ipairs({ "", "hello", "42", "[1, 2, 3]", '{"version": 1, "run": ', '{"version": 1}' }) do
        local rec, why = Save.decode(text)
        eq(rec, nil, "decoded " .. text); truthy(type(why) == "string", "says why")
    end
    local good = Save.encode({ run = Run.new(5), savedAt = 1 })
    truthy(Save.decode(good), "the untouched file is fine")
    local function edited(change)
        local data = json.decode(good)
        change(data, data.run)
        return Save.decode(json.encode(data))
    end
    local edits = {
        ["another version"] = function(d) d.version = 99 end,
        ["no run"] = function(d) d.run = "nope" end,
        ["an unknown card"] = function(d, r) r.deck[1] = "laser" end,
        ["an empty deck"] = function(d, r) r.deck = {} end,
        ["an unknown bug"] = function(d, r) r.jar[1].species = "dragon" end,
        ["a Jar fuller than its slots"] = function(d, r) r.jarSlots = 2 end,
        ["two bugs with one uid"] = function(d, r) r.jar[2].uid = r.jar[1].uid end,
        ["a uid from the future"] = function(d, r) r.jar[1].uid = r.nextUid end,
        ["negative marbles"] = function(d, r) r.marbles = -1 end,
        ["half a marble"] = function(d, r) r.marbles = 2.5 end,
        ["a fight that does not exist"] = function(d, r) r.node = #Run.NODES + 1 end,
        ["a seed out of range"] = function(d, r) r.seed = Run.SEED_MAX + 1 end,
        ["a Journal page of no species"] = function(d, r) r.seen.dragon = true end,
        ["a strange ending"] = function(d) d.ended = { won = "yes" } end,
        ["a strange date"] = function(d) d.savedAt = "yesterday" end,
    }
    for what, change in pairs(edits) do
        local rec, why = edited(change)
        eq(rec, nil, what); truthy(type(why) == "string", what .. " says why")
    end
end)

test("seeds stay in the range the generator handles exactly", function()
    local Run = require("sim.run")
    truthy(Run.fightSeed({ seed = Run.SEED_MAX, node = #Run.NODES }) * 48271 < 2 ^ 53, "the generator's first step is exact in doubles")
    eq(Run.fightSeed(Run.new(7)), 7 * 131 + 1, "the old fixed seed still deals the old first fight")
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
