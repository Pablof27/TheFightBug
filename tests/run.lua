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

test("the Sun clock running out is a loss, even when you are ahead", function()
    for _, rule in ipairs({ "lbs", "crumbs", "zumo" }) do
        local s = arena({ rule = rule, kid = { { species = "stag", x = 1, y = 1 }, { species = "stag", x = 2, y = 1 } }, rival = { { species = "ant", x = 6, y = 6, timer = 99 } } })
        if rule == "crumbs" then s.rule.score.kid = 4 end
        s.tick = s.sunLimit - 1
        Kid.wait(s)
        eq(s.winner, "rival", rule); eq(s.why, "sun", rule)
    end
end)

print("Bug Hunts: the jar is a trap")

local Run = require("sim.run")
local Duel = require("sim.duel")
local Hunt = require("sim.hunt")
local Shop = require("sim.shop")
local Park = require("sim.park")
local Save = require("sim.save")
local Path = require("sim.path")
local Instincts = require("sim.instincts")
local ParkData = require("data.park")

-- A hunt on an empty 6x6 board (scripted hand, so it starts at once) with the jar laid on `trap`.
local function hunt(o)
    local s = arena({ rule = "jar", rivalKid = o.nature or "bird", kid = o.kid, rival = o.rival, hand = o.hand, layout = o.layout })
    local t = o.trap or { x = 3, y = 2 }
    Grid.cell(s, t.x, t.y).trap = true
    s.trapAt = { x = t.x, y = t.y }
    s.hunt = { spot = "bucket", buzz = 0 }
    s.rival.timer = 99
    for k, v in pairs(o.items or {}) do s.items[k] = v end
    return s
end

test("a wild bug that walks into the jar is caught; your bugs walk past it but never stop on it", function()
    local s = hunt({ kid = { { species = "ant", x = 1, y = 1, timer = 9, uid = 1 } }, rival = { { species = "ant", x = 3, y = 4, timer = 0 } }, hand = { "crumb" } })
    play(s, "crumb", { x = 3, y = 2 })          -- a lure inside the jar
    eq(#s.caught, 1, "caught"); eq(s.caught[1].species, "ant"); eq(s.rule.score.kid, 1)
    eq(#events(s, "catch"), 1); eq(Q.count(s, "rival"), 0)
    eq(s.winner, "kid", "no wild bug left and nobody loose: the hunt is over"); eq(s.why, "cleared")
    local mine = find(s, "ant", "kid")
    truthy(not Path.canEnter(s, mine, 3, 2), "can't stop on the jar")
    truthy(Path.canEnter(s, mine, 3, 2, { pass = true }), "but can walk past it")
    truthy(not Path.canLand(s, mine, 3, 2))
end)

test("a wild bug pushed into the jar is caught; one of yours pushed at it bumps", function()
    local s = hunt({ kid = { { species = "cricket", x = 2, y = 2, timer = 9, uid = 1 } },
        rival = { { species = "pillbug", x = 3, y = 3, timer = 9 }, { species = "ant", x = 6, y = 6, timer = 9 } }, hand = { "flick", "flick" } })
    play(s, "flick", find(s, "pillbug", "rival").id, { dx = 0, dy = -1 })
    eq(#s.caught, 1); eq(s.caught[1].species, "pillbug")
    local cricket = find(s, "cricket", "kid")
    play(s, "flick", cricket.id, { dx = 1, dy = 0 })
    eq(cricket.x, 2, "bumped into the jar"); eq(#events(s, "bump"), 1)
    eq(s.winner, nil, "a wild ant is still out there")
end)

test("a bug of yours knocked out on a hunt runs loose: ignored by the wild, it crawls off the board unless the jar takes it back", function()
    local s = hunt({ kid = { { species = "spider", x = 2, y = 2, timer = 9, uid = 5 } },
        rival = { { species = "wasp", x = 2, y = 3, timer = 0 }, { species = "ant", x = 6, y = 6, timer = 9 } }, trap = { x = 5, y = 1 } })
    Kid.wait(s)
    local spider = find(s, "spider", "kid")
    truthy(spider and spider.loose, "loose, not gone"); eq(spider.hp, 0); eq(#events(s, "loose"), 1); eq(s.stats.scurried.kid, 0)
    local wasp = find(s, "wasp", "rival")
    local it = Instincts.decide(s, wasp)
    truthy(not (it.target and it.target.id == spider.id), "the wild bugs ignore a loose bug")
    it = Instincts.decide(s, spider)
    eq(it.kind, "crawl"); eq(it.to.x, 1, "the nearest way out is left (ties: left first)"); eq(it.to.y, 2)
    for _ = 1, 8 do if not spider.gone then Kid.wait(s) end end
    truthy(spider.gone, "it got away"); eq(s.field[5].escaped, 1); eq(#events(s, "escape") > 0, true)
    -- the same, but the jar is in its way: it crawls right back in
    s = hunt({ kid = { { species = "spider", x = 2, y = 2, timer = 9, uid = 5 } },
        rival = { { species = "wasp", x = 2, y = 3, timer = 0 }, { species = "ant", x = 6, y = 6, timer = 9 } }, trap = { x = 1, y = 2 } })
    for _ = 1, 4 do Kid.wait(s) end
    eq(s.field[5].rescued, 1, "rescued"); eq(s.field[5].escaped, nil)
end)

test("a hunt can't be lost: the lid, the Sun clock or the lawnmower end it, and whoever is still loose stays in the wild", function()
    local s = hunt({ kid = { { species = "spider", x = 2, y = 2, timer = 9, uid = 5 } },
        rival = { { species = "wasp", x = 2, y = 3, timer = 0 }, { species = "ant", x = 6, y = 6, timer = 9 } } })
    Kid.wait(s)
    truthy(find(s, "spider", "kid").loose)
    truthy(Kid.closeLid(s)); eq(s.winner, "kid"); eq(s.why, "lid"); eq(s.field[5].escaped, 1, "left behind")
    s = hunt({ kid = { { species = "ant", x = 1, y = 1, timer = 9, uid = 1 } }, rival = { { species = "ant", x = 6, y = 6, timer = 99 } } })
    s.tick = s.sunLimit - 1
    Kid.wait(s); eq(s.winner, "kid"); eq(s.why, "sun")
    s = hunt({ nature = "mower", kid = { { species = "ant", x = 1, y = 1, timer = 9, uid = 1 } }, rival = { { species = "ant", x = 6, y = 6, timer = 99 } } })
    s.rival.timer = 0
    Kid.wait(s); Kid.wait(s); eq(s.why, "mower")
end)

test("nature's moves: the blackbird freezes everyone, the dog pushes the busiest row, the rain makes the puddles it showed", function()
    local s = hunt({ kid = { { species = "ant", x = 1, y = 1, timer = 5, uid = 1 } }, rival = { { species = "wasp", x = 4, y = 5, timer = 5 } } })
    s.rival.timer = 0
    Kid.wait(s); Kid.wait(s)
    eq(find(s, "ant", "kid").timer, 5 - 2 + 1, "+1"); eq(find(s, "wasp", "rival").timer, 5 - 2 + 2, "flyers +2")
    s = hunt({ nature = "dog", kid = { { species = "ant", x = 1, y = 3, timer = 9, uid = 1 } }, rival = { { species = "pillbug", x = 4, y = 3, timer = 9 }, { species = "ant", x = 6, y = 6, timer = 9 } } })
    s.rival.timer = 0
    eq(require("sim.rival").peek(s).row, 3, "the busiest row, shown in advance")
    Kid.wait(s); Kid.wait(s)
    eq(find(s, "ant", "kid").y, 4); eq(find(s, "pillbug", "rival").y, 4)
    s = hunt({ nature = "shower", kid = { { species = "ant", x = 1, y = 1, timer = 9, uid = 1 } }, rival = { { species = "ant", x = 6, y = 6, timer = 9 } } })
    require("sim.rival").pick(s)
    local shown = require("sim.rival").peek(s).tiles
    eq(#shown, 2, "two puddles shown in advance")
    s.rival.timer = 0
    Kid.wait(s); Kid.wait(s)
    for _, t in ipairs(shown) do truthy(Grid.cell(s, t.x, t.y).puddle, "a puddle where it was shown") end
end)

test("pocket items on a hunt: the Bug Net catches flyers passing over the jar, the Pooter sucks in a Light neighbour, the Sweep Net scoops hidden bugs", function()
    local s = hunt({ items = { net = true }, kid = { { species = "ant", x = 1, y = 1, timer = 9, uid = 1 } }, trap = { x = 3, y = 3 },
        rival = { { species = "wasp", x = 3, y = 5, timer = 0 }, { species = "ant", x = 6, y = 6, timer = 9 } }, hand = { "sugar" } })
    play(s, "sugar", { x = 3, y = 1 })     -- the wasp flies over the jar to get it
    eq(#s.caught, 1); eq(events(s, "catch")[1].how, "net")
    s = hunt({ items = { pooter = true }, kid = { { species = "ant", x = 1, y = 1, timer = 9, uid = 1 } },
        rival = { { species = "ant", x = 3, y = 3, timer = 9 }, { species = "stag", x = 6, y = 6, timer = 9 } } })
    Kid.wait(s)
    eq(#s.caught, 1); eq(events(s, "catch")[1].how, "pooter")
    s = hunt({ items = { sweep = true }, layout = { "......", "......", "......", "....g.", "......", "......" },
        kid = { { species = "ant", x = 1, y = 1, timer = 9, uid = 1 } }, rival = { { species = "cricket", x = 5, y = 3, timer = 9 }, { species = "ant", x = 6, y = 6, timer = 9 } }, hand = { "flick" } })
    truthy(Q.isHidden(s, find(s, "cricket", "rival")))
    play(s, "flick", find(s, "cricket", "rival").id, { dx = 0, dy = 1 })
    eq(#s.caught, 1); eq(events(s, "catch")[1].how, "sweep")
end)

print("Duels: the poorer side goes all in")

local function newDay(seed)
    local run = Run.new(seed or 1)
    Run.endPrologue(run)
    Run.pickZone(run, 1)
    return run
end
local function settle(run, winner, o)
    o = o or {}
    return Duel.settle(run, { winner = winner, why = o.why or (winner == "kid" and "cleared" or winner == "rival" and "wiped" or "bell"),
        field = o.field or {}, stake = Duel.stake(run), keeps = o.keeps })
end

test("a day starts with 10 marbles, the warm-up, then two zones, each with its Gang leader", function()
    local run = Run.new(1)
    eq(run.marbles, 10); eq(run.phase, "prologue"); eq(#run.jar, 5); eq(run.jarSlots, 6); eq(run.spirit, nil)
    eq(Run.prologueEncounter().id, "sandbox", "the warm-up is the GDD's worked example")
    Run.endPrologue(run)
    eq(run.phase, "zone"); eq(#run.offer, 2)
    truthy(run.offer[1].zone ~= run.offer[2].zone)
    local leaders = { [run.offer[1].leader] = true, [run.offer[2].leader] = true }
    truthy(leaders.bully and leaders.antgirl, "the Morning's two Gang leaders")
    Run.pickZone(run, 2)
    eq(run.phase, "free"); eq(run.window, 1); eq(run.leader, run.offer == nil and run.leader)
    eq(#run.kids, 2); truthy(run.kids[1] ~= run.leader and run.kids[2] ~= run.leader)
    eq(run.stacks[run.leader], 14)
    local again = newDay(1)
    eq(again.kids[1], (function() local r = Run.new(1); Run.endPrologue(r); Run.pickZone(r, 1); return r.kids[1] end)(), "same seed, same day")
end)

test("the bet is the smaller stack, the winner takes it, and a broke rival ends the duel", function()
    local run = newDay(1)
    local kid = run.kids[1]
    truthy(Duel.start(run, kid)); eq(run.phase, "duel")
    run.marbles, run.stacks[kid] = 10, 4
    eq(Duel.stake(run), 4); eq(Duel.allIn(run), "rival")
    local rec = settle(run, "kid")
    eq(run.marbles, 14); eq(run.stacks[kid], 0); eq(rec.delta, 4)
    eq(run.duel.over.why, "broke"); truthy(#run.duel.offer > 0, "a broke kid makes you an offer")
    truthy(Duel.leave(run)); eq(run.phase, "free"); eq(run.window, 2, "on to the van and the Gang leader"); truthy(Shop.isOpen(run))
end)

--- Where the rival's bugs start, as text: "r1@3,6 r2@5,5 ..."
local function lineupOf(run)
    local out = {}
    for _, t in ipairs(Duel.encounter(run).rivalTeam) do out[#out + 1] = t.uid .. "@" .. t.x .. "," .. t.y end
    return table.concat(out, " ")
end

test("the rematch: the same game on the same board, the rival's bugs on other tiles; then the Showdown ends the duel", function()
    local run = newDay(2)
    local kid = run.kids[1]
    Duel.start(run, kid)
    run.marbles, run.stacks[kid] = 10, 4
    local first, board = run.duel.rule, Duel.boardId(run)
    local used = {}
    for _, t in ipairs(Duel.encounter(run).rivalTeam) do used[t.x .. "," .. t.y] = true end
    settle(run, "rival")
    eq(run.marbles, 6); eq(run.stacks[kid], 8); eq(run.duel.round, 2); eq(run.duel.mood, "cocky")
    local enc = Duel.encounter(run)
    eq(enc.rule, first, "you lost round 1: the same game again, nobody picks"); eq(Duel.boardId(run), board, "on the same board")
    for _, t in ipairs(enc.rivalTeam) do truthy(not used[t.x .. "," .. t.y], "their bugs start on other tiles") end
    eq(Duel.stake(run), 6); eq(Duel.allIn(run), "kid")
    settle(run, "kid")
    eq(run.marbles, 12); eq(run.stacks[kid], 2); eq(run.duel.round, 3); eq(run.duel.mood, "angry")
    eq(Duel.rule(run), "showdown"); eq(Duel.stake(run), 0); eq(Duel.boardId(run), board, "the Showdown too")
    enc = Duel.encounter(run)
    eq(enc.rule, "showdown"); eq(enc.keeps.kid, 12); eq(enc.keeps.rival, 2); truthy(enc.keeps.endOnBroke)
    settle(run, "draw", { keeps = { kid = 13, rival = 1 } })
    eq(run.duel.over.why, "bell", "the Showdown ends the duel"); eq(run.marbles, 13); eq(run.stacks[kid], 1)
end)

test("every kid plays one game, never Mushi-Zumo for now; Little Sibling rolls hers once per act", function()
    local Rivals = require("data.rivals")
    for id, rv in pairs(Rivals) do
        local ok = rv.rule == "random"
        for _, r in ipairs(ParkData.RULES) do if r == rv.rule then ok = true end end
        truthy(ok, id .. " plays a game from Park.RULES"); truthy(rv.rule ~= "zumo", id .. ": Mushi-Zumo is parked")
    end
    for zid, z in pairs(ParkData.zones) do
        for _, r in ipairs(ParkData.RULES) do truthy(ParkData.boards[z.rules[r]], zid .. " has a board for " .. r) end
    end
    local run = newDay(3)
    local kid = run.kids[1]
    Duel.start(run, kid)
    run.marbles, run.stacks[kid] = 3, 9
    local rule = run.duel.rule
    eq(rule, Duel.ruleOf(run, kid))
    settle(run, "kid")
    eq(run.duel.round, 2); eq(run.duel.rule, rule, "the rival lost round 1: still the same game")
    eq(Duel.ruleOf(run, "sibling"), Duel.ruleOf(run, "sibling"), "seeded")
    local seen = {}
    for seed = 1, 30 do seen[Duel.ruleOf(newDay(seed), "sibling")] = true end
    truthy(seen.lbs and seen.crumbs and not seen.zumo, "either game, never Mushi-Zumo")
end)

test("the rival's bugs start on random free tiles of their home rows: other tiles every round, the same after a reload", function()
    local firsts = {}
    for seed = 1, 12 do
        local run = newDay(seed)
        Duel.start(run, run.kids[1])
        run.marbles, run.stacks[run.kids[1]] = 30, 30
        local b = ParkData.boards[Duel.boardId(run)]
        firsts[lineupOf(run):gsub("r%d+@", "")] = true
        local prev
        for round = 1, 3 do
            local enc = Duel.encounter(run)
            eq(enc.round, round)
            local here = {}
            for _, t in ipairs(enc.rivalTeam) do
                truthy(t.y > b.h - 2, "in their home rows")
                local ch = enc.layout[b.h - t.y + 1]:sub(t.x, t.x)
                truthy(ch ~= "p" and ch ~= "k" and ch ~= "~" and ch ~= "#", "never on a blocked tile")
                truthy(not here[t.x .. "," .. t.y], "one bug per tile"); here[t.x .. "," .. t.y] = true
                truthy(not (prev and prev[t.x .. "," .. t.y]), "never a tile the round before used")
            end
            eq(lineupOf(Save.decode(Save.encode({ run = run })).run), lineupOf(run), "a reload lines them up the same way")
            prev = here
            settle(run, "draw")
        end
        eq(run.duel.over.why, "bell", "three rounds were played")
    end
    local n = 0
    for _ in pairs(firsts) do n = n + 1 end
    truthy(n >= 6, "round 1 starts somewhere else in most duels (" .. n .. " different lineups in 12)")
end)

test("in the Showdown every hit moves a marble, and a side that runs out is broke", function()
    local s = arena({ rule = "showdown", kid = { { species = "ant", x = 3, y = 2, timer = 9, uid = 1 } }, rival = { { species = "wasp", x = 3, y = 3, timer = 0 } } })
    s.keeps = { kid = 1, rival = 5, endOnBroke = true }
    Kid.wait(s)
    eq(#events(s, "marble"), 1); eq(s.keeps.kid, 0); eq(s.keeps.rival, 6)
    eq(s.winner, "rival"); eq(s.why, "broke")
    s = arena({ rule = "showdown", kid = { { species = "ant", x = 1, y = 1, timer = 9, uid = 1 } }, rival = { { species = "ant", x = 6, y = 6, timer = 99 } } })
    s.keeps = { kid = 3, rival = 3, endOnBroke = true }
    s.tick = s.sunLimit - 1
    Kid.wait(s); eq(s.winner, "draw"); eq(s.why, "bell", "the bell rings: the duel is over")
    -- a hit has to land: the pill bug curls up (NOPE!) and keeps its marble
    s = arena({ rule = "showdown", kid = { { species = "pillbug", x = 3, y = 2, timer = 9, uid = 1 } }, rival = { { species = "wasp", x = 3, y = 3, timer = 0 } } })
    s.keeps = { kid = 4, rival = 4, endOnBroke = true }
    Kid.wait(s)
    eq(#events(s, "attack"), 1); eq(#events(s, "marble"), 0, "a blocked attack moves no marble"); eq(s.keeps.kid, 4)
end)

test("napping: bugs knocked out in a round sit out the next one, on both sides, then wake up", function()
    local run = newDay(4)
    local kid = run.kids[1]
    Duel.start(run, kid)
    run.marbles, run.stacks[kid] = 10, 9
    local ant = run.jar[1]
    eq(ant.species, "ant")
    local rec = settle(run, "rival", { field = { [ant.uid] = { total = 3, lost = 3 }, r1 = { total = 1, lost = 1 } } })
    truthy(ant.nap, "your colony naps"); truthy(run.duel.roster[1].nap, "so does their first bug")
    eq(rec.napped[1], "ant"); eq(rec.rnapped[1], run.duel.roster[1].species)
    for _, e in ipairs(Run.available(run)) do truthy(e.uid ~= ant.uid, "a napping bug can't play") end
    for _, t in ipairs(Duel.encounter(run).rivalTeam) do truthy(t.uid ~= "r1", "theirs neither") end
    settle(run, "kid")
    eq(ant.nap, nil, "it sat out a round: awake again"); eq(run.duel.roster[1].nap, nil)
end)

test("knockouts on a hunt nap through every hunt and the first round of the next duel", function()
    local run = newDay(5)
    local mantis = run.jar[3]
    local sum = Hunt.settle(run, { hunt = { spot = Hunt.spots(run)[1] }, caught = {}, met = {}, field = { [mantis.uid] = { total = 1, lost = 1, rescued = 1 } } })
    eq(sum.napped[1], "mantis"); truthy(mantis.nap)
    eq(run.buzz, 1, "the zone is stirred up")
    Duel.start(run, run.kids[1])
    settle(run, "rival")
    eq(mantis.nap, nil, "it sat out round 1")
    -- every bug of an entry got away: it's gone for good
    run = newDay(5)
    local spider = run.jar[5]
    sum = Hunt.settle(run, { hunt = { spot = Hunt.spots(run)[1] }, caught = {}, met = {}, field = { [spider.uid] = { total = 1, lost = 1, escaped = 1 } } })
    eq(sum.lost[1], "spider"); eq(#run.jar, 4); eq(run.lost[1], "spider")
end)

test("the kid you don't pick plays the Gang leader and loses: their marbles join the leader's", function()
    local run = newDay(6)
    local a, b = run.kids[1], run.kids[2]
    local leader, before, fed = run.leader, run.stacks[run.leader], run.stacks[b]
    Duel.start(run, a)
    eq(run.stacks[leader], before + fed); eq(run.stacks[b], 0); eq(run.fed.kid, b)
end)

test("Big Sister: the first time you're broke she lends you 3 marbles and ends the duel; the next time you go home", function()
    local run = newDay(7)
    local kid = run.kids[1]
    Duel.start(run, kid)
    run.marbles, run.stacks[kid] = 2, 10
    local rec = settle(run, "rival")
    truthy(rec.sister); eq(run.marbles, 3); eq(run.bigSister, false); eq(run.duel.over.why, "sister")
    Duel.leave(run)
    eq(run.phase, "free"); eq(run.window, 2)
    Duel.start(run, run.leader)
    settle(run, "rival")
    eq(run.duel.over.why, "home")
    Duel.leave(run)
    truthy(Run.over(run)); eq(run.result.won, false)
end)

test("a side that can't field a single bug forfeits the round: it loses the bet", function()
    local run = newDay(8)
    local kid = run.kids[1]
    Duel.start(run, kid)
    run.marbles, run.stacks[kid] = 10, 4
    for _, e in ipairs(run.jar) do e.nap = true end
    eq(Duel.forfeitSide(run), "kid")
    local rec = Duel.forfeit(run)
    eq(rec.why, "forfeit"); eq(run.marbles, 6); eq(run.stacks[kid], 8)
end)

print("The day: hunts, the van, the acts")

test("a whole day: three acts of zone, kid, van and Gang leader, a pocket item after the first two, then sunset", function()
    local run = newDay(9)
    for act = 1, 3 do
        eq(run.act, act); eq(run.phase, "free")
        local kid = run.kids[1]
        Duel.start(run, kid)
        run.stacks[kid] = 1
        settle(run, "kid"); Duel.leave(run)
        eq(run.window, 2); truthy(run.van)
        Duel.start(run, run.leader)
        run.marbles, run.stacks[run.leader] = 20, 5
        settle(run, "kid"); Duel.leave(run)
        if act < 3 then
            eq(run.phase, "reward"); eq(#run.rewardOffer, 3)
            local slots = run.jarSlots
            truthy(Run.pickReward(run, 1)); eq(#run.items, act); eq(run.jarSlots, slots + 1)
            eq(run.phase, "zone"); Run.pickZone(run, 1)
        end
    end
    truthy(Run.over(run)); eq(run.result.won, true); eq(run.result.why, "sunset")
end)

test("every hunt stirs the zone up (meaner groups, rarer prizes); a duel calms it down", function()
    local run = newDay(10)
    local spot = Hunt.spots(run)[1]
    local calm = Hunt.group(run, spot)
    eq(calm.timer, 1, "Buzz 0: they haven't noticed you"); eq(#calm.guards, 0); eq(calm.bite, 0)
    run.buzz = 3
    local busy = Hunt.group(run, spot)
    eq(#busy.guards, 1); eq(busy.bite, 1); eq(busy.prize, Hunt.prizeAt(spot, 3))
    eq(busy.common[1], calm.common[1], "the same group, only meaner"); eq(busy.common[2], calm.common[2])
    local enc = Hunt.encounter(run, spot)
    eq(enc.rule, "jar"); eq(enc.w, 5); eq(#enc.rivalTeam, 4)
    local prizes = 0
    for _, t in ipairs(enc.rivalTeam) do if t.prize then prizes = prizes + 1 end end
    eq(prizes, 1)
    Hunt.settle(run, { hunt = { spot = spot }, caught = {}, met = {}, field = {} })
    eq(run.buzz, 4); eq(run.visits[spot], 1)
    truthy(Hunt.group(run, spot).common[1] ~= nil, "the spot shows its next group")
    Duel.start(run, run.kids[1]); run.stacks[run.kids[1]] = 1; settle(run, "kid"); Duel.leave(run)
    eq(run.buzz, 0)
end)

test("a caught bug merges into one of its kind (a bigger one), otherwise takes a slot; a full Jar must let someone go", function()
    local run = newDay(11)
    eq(Run.addCaught(run, "mantis"), "merged"); truthy(run.jar[3].big)
    eq(Run.addCaught(run, "mantis"), "added"); eq(#run.jar, 6)
    Run.addCaught(run, "wasp")
    eq(Run.overflow(run), 1)
    truthy(not Duel.start(run, run.kids[1]), "not with a Jar too full"); truthy(not Hunt.can(run))
    truthy(Run.letGo(run, run.jar[1].uid)); eq(Run.overflow(run), 0); eq(run.released[1], "ant")
    -- bigger bugs in a fight: one more heart, or one more ant
    run.jar[1].big = true     -- now the pill bug
    local s = Fight.new(Hunt.encounter(run, Hunt.spots(run)[1]), { jar = Run.available(run), deck = run.deck, seed = 1 })
    Kid.deploy(s, 1, 2, 2)
    eq(find(s, "pillbug", "kid").maxHp, 4)
end)

test("the van: seeded stock, prices grow with the act, never your last marble; restock, throw a card away, an ice-cream break", function()
    local run = newDay(12)
    Duel.start(run, run.kids[1]); run.stacks[run.kids[1]] = 1; settle(run, "kid"); Duel.leave(run)
    local a, b = Shop.stock(run), Shop.stock(run)
    eq(#a, 11); for i = 1, #a do eq(a[i].id, b[i].id) end
    local card = a[1]
    eq(card.price, require("data.cards")[card.id].price, "Morning prices")
    run.marbles = card.price
    local ok, why = Shop.buy(run, card); truthy(not ok); eq(why, "last", "never your last marble")
    run.marbles = 30
    truthy(Shop.buy(run, card)); eq(run.deck[#run.deck], card.id)
    ok, why = Shop.buy(run, card); eq(why, "sold")
    local remove
    for _, it in ipairs(a) do if it.kind == "remove" then remove = it end end
    local n = #run.deck
    truthy(Shop.buy(run, remove, 1)); eq(#run.deck, n - 1)
    truthy(Shop.restock(run)); truthy(Shop.stock(run)[1].key ~= a[1].key)
    run.jar[1].nap = true
    local cream
    for _, it in ipairs(Shop.stock(run)) do if it.kind == "icecream" then cream = it end end
    truthy(Shop.buy(run, cream)); eq(run.jar[1].nap, nil)
    run.act = 3
    eq(Shop.stock(run)[1].price, require("data.cards")[Shop.stock(run)[1].id].price * 4, "Dusk prices")
end)

test("events: a swap, a lost ball, a shower, a dog; the bench once per act", function()
    local run = newDay(13)
    run.event = { kind = "swap", give = "stag", want = run.jar[4].uid }
    truthy(Park.answer(run, true)); eq(run.jar[4].species, "stag"); eq(run.event, nil)
    run.event = { kind = "ball", card = "leaf" }
    truthy(Park.answer(run, true, run.jar[2].uid)); truthy(run.jar[2].nap); eq(run.deck[#run.deck], "leaf")
    run.buzz = 2
    run.event = { kind = "shower" }
    truthy(Park.answer(run, true)); eq(run.buzz, 1); truthy(run.wet)
    local spot = Hunt.spots(run)[2]
    run.event = { kind = "dog" }
    Park.answer(run, true); eq(run.visits[spot], 1, "every spot shows a new group")
    truthy(Park.bench(run, "wake")); eq(run.jar[2].nap, nil)
    local ok = Park.bench(run, "wake"); truthy(not ok, "once per act")
    -- the shower's puddles on the next duel's board
    Duel.start(run, run.kids[1])
    local enc = Duel.encounter(run)
    local b = ParkData.boards[Duel.boardId(run)]
    if b.wet then
        local p = b.wet[1]
        eq(enc.layout[b.h - p.y + 1]:sub(p.x, p.x), "~")
    end
end)

test("house rules: no Lures, hands off her ants, nobody hides from the Nerd, the Rich Kid buys more, the Champion plays for keeps", function()
    local s = arena({ kid = { { species = "ant", x = 1, y = 1, timer = 9, uid = 1 } }, rival = { { species = "ant", x = 4, y = 4, timer = 9 } }, hand = { "crumb", "flick" },
        layout = { "......", "......", "......", "......", "......", "g....." } })
    s.house = "nolures"
    truthy(not Kid.playable(s, "crumb")); truthy(Kid.playable(s, "flick"))
    s.house = "noflick"
    for _, it in ipairs(Kid.options(s, "flick", {}).items) do truthy(it.id ~= find(s, "ant", "rival").id, "not her ants") end
    truthy(Q.isHidden(s, find(s, "ant", "kid")))
    s.house = "nohide"
    truthy(not Q.isHidden(s, find(s, "ant", "kid")), "she has read about your bugs")
    local run = newDay(14)
    run.leader = "rich"; run.stacks.rich = 30
    Duel.start(run, run.kids[1]); run.stacks[run.kids[1]] = 1; settle(run, "kid"); Duel.leave(run)
    Duel.start(run, "rich")
    local n = #run.duel.roster
    run.marbles = 40
    settle(run, "rival")
    eq(#run.duel.roster, n + 1); eq(run.duel.roster[n + 1].species, "hercules")
    run = newDay(15)
    run.leader = "champ"
    Duel.start(run, run.kids[1]); run.stacks[run.kids[1]] = 1; settle(run, "kid"); Duel.leave(run)
    run.stacks.champ = 20
    Duel.start(run, "champ")
    run.marbles = 12
    local enc = Duel.encounter(run)
    eq(enc.house, "keeps"); eq(enc.stake, 12); eq(enc.keeps.kid, 0); eq(enc.keeps.rival, 8); eq(enc.keeps.endOnBroke, nil)
end)

test("pocket items in fights: Lucky Marble, Lunchbox, Sneakers, Wristwatch; the Sticker Album pays when you break a rival", function()
    local run = newDay(16)
    run.items = { "lucky", "lunchbox", "sneakers", "watch" }
    Duel.start(run, run.kids[1])
    local s = Fight.new(Duel.encounter(run), { jar = Run.available(run), deck = run.deck, seed = 1, items = run.items })
    eq(s.sunLimit, 40 + 10)
    Fight.autoDeploy(s); Kid.start(s)
    eq(#s.hand, 6, "one more card")
    eq(Kid.cost(s, "crumb"), 0, "the first Lure is free"); eq(Kid.releaseCost("stag", s), 2)
    run = newDay(17)
    run.items = { "album" }
    Duel.start(run, run.kids[1])
    run.marbles, run.stacks[run.kids[1]] = 10, 3
    settle(run, "kid")
    eq(run.marbles, 15, "13 + 2 for the album")
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
    local s = Fight.new(Duel.encounter(run), { jar = Run.available(run), deck = run.deck, seed = Run.fightSeed(run), items = run.items })
    Fight.autoDeploy(s)
    truthy(Kid.start(s), "the fight starts")
    return table.concat(s.hand, ",") .. " | " .. table.concat(s.deck, ",")
end

test("a saved run loads back exactly, in the middle of a duel, so its seed deals the same fights", function()
    local run = newDay(123456789)
    run.slot = 2
    Hunt.settle(run, { hunt = { spot = Hunt.spots(run)[1] }, caught = { { species = "wasp" } }, met = { wasp = true }, field = { [1] = { total = 3, lost = 3, rescued = 1 } } })
    Duel.start(run, run.kids[1])
    settle(run, "rival", { field = { r2 = { total = 1, lost = 1 } } })
    run.rewinds = 4
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
    for _, won in ipairs({ true, false }) do
        local run = Run.new(9)
        run.phase, run.result = "over", { won = won, why = won and "sunset" or "broke" }
        local rec = assert(Save.decode(Save.encode({ run = run, ended = { won = won } })))
        eq(rec.ended.won, won); eq(rec.run.result.won, won)
    end
end)

test("damaged or hand-edited save files are reported, never trusted", function()
    local json = require("engine.utils.json")
    for _, text in ipairs({ "", "hello", "42", "[1, 2, 3]", '{"version": 2, "run": ', '{"version": 2}' }) do
        local rec, why = Save.decode(text)
        eq(rec, nil, "decoded " .. text); truthy(type(why) == "string", "says why")
    end
    local run = newDay(5)
    Duel.start(run, run.kids[1])
    local good = Save.encode({ run = run, savedAt = 1 })
    truthy(Save.decode(good), "the untouched file is fine")
    local function edited(change)
        local data = json.decode(good)
        change(data, data.run)
        return Save.decode(json.encode(data))
    end
    local edits = {
        ["the old demo's format"] = function(d) d.version = 1 end,
        ["no run"] = function(d) d.run = "nope" end,
        ["an unknown card"] = function(d, r) r.deck[1] = "laser" end,
        ["an empty deck"] = function(d, r) r.deck = {} end,
        ["an unknown bug"] = function(d, r) r.jar[1].species = "dragon" end,
        ["two bugs with one uid"] = function(d, r) r.jar[2].uid = r.jar[1].uid end,
        ["a uid from the future"] = function(d, r) r.jar[1].uid = r.nextUid end,
        ["negative marbles"] = function(d, r) r.marbles = -1 end,
        ["half a marble"] = function(d, r) r.marbles = 2.5 end,
        ["an act that does not exist"] = function(d, r) r.act = 4 end,
        ["a strange phase"] = function(d, r) r.phase = "nap time" end,
        ["a seed out of range"] = function(d, r) r.seed = Run.SEED_MAX + 1 end,
        ["a Journal page of no species"] = function(d, r) r.seen.dragon = true end,
        ["an unknown pocket item"] = function(d, r) r.items = { "laser" } end,
        ["an unknown zone"] = function(d, r) r.zone = "moon" end,
        ["a rival nobody knows"] = function(d, r) r.duel.rival = "batman" end,
        ["a duel in round 4"] = function(d, r) r.duel.round = 4 end,
        ["a Buzz off the scale"] = function(d, r) r.buzz = 9 end,
        ["a duel phase without a duel"] = function(d, r) r.duel = nil end,
        ["a strange ending"] = function(d) d.ended = { won = "yes" } end,
        ["a strange date"] = function(d) d.savedAt = "yesterday" end,
    }
    for what, change in pairs(edits) do
        local rec, why = edited(change)
        eq(rec, nil, what); truthy(type(why) == "string", what .. " says why")
    end
end)

test("seeds stay in the range the generator handles exactly", function()
    truthy(Run.fightSeed({ seed = Run.SEED_MAX, fights = 200 }) * 48271 < 2 ^ 53, "the generator's first step is exact in doubles")
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
