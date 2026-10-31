-- Rules of the Game (GDD §5.11): what a fight is about. Three duel Rules are implemented for the demo, plus the
-- Showdown (round 3 of every duel) and the Jar Trap (Bug Hunts).

local Grid = require("sim.grid")
local State = require("sim.state")
local Q = require("sim.query")
local Trap = require("sim.trap")
local Data = require("data.rules")

local Rules = {}

--- spawns (Crumb Race): array of { tick, x, y } - the crumbs always appear at the same places at the same times.
function Rules.setup(s, ruleId, spawns)
    local def = Data[ruleId]
    assert(def, "unknown rule " .. tostring(ruleId))
    s.rule = {
        id = ruleId, score = { kid = 0, rival = 0 }, goal = def.goal,
        attackMode = def.attackMode, spawns = spawns or {},
    }
    if def.openEdges then s.openEdges = true end
    Rules.spawnLoot(s, 0)
end

function Rules.spawnLoot(s, tick)
    for _, sp in ipairs(s.rule.spawns) do
        if sp.tick == tick then
            local c = Grid.cell(s, sp.x, sp.y)
            if c and not c.void and not c.block and not c.food then
                c.food = { kind = "loot" }
                State.emit(s, "loot", { x = sp.x, y = sp.y })
            end
        end
    end
end

--- Things that happen at the end of every tick: scent trails fade, crumbs appear, the Pooter sucks up a wild bug.
function Rules.endOfTick(s)
    for _, c in pairs(s.cells) do
        if c.trail then
            c.trail.ttl = c.trail.ttl - 1
            if c.trail.ttl <= 0 then c.trail = nil end
        end
    end
    if s.rule.id == "crumbs" then Rules.spawnLoot(s, s.tick) end
    if s.rule.id == "jar" and s.items and s.items.pooter and s.trapAt and not s.winner then
        local t = s.trapAt
        for _, d in ipairs(Grid.DIRS) do
            local b = State.at(s, t.x + d.dx, t.y + d.dy)
            if b and b.side == "rival" and b.weight == 1 then
                State.moveBug(s, b, t.x, t.y)
                Trap.catch(s, b, "pooter")
                break
            end
        end
    end
end

local function finish(s, side, why)
    if s.winner then return end
    s.winner, s.why = side, why
    State.emit(s, "end", { winner = side, why = why })
end
Rules.finish = finish

--- A hunt is over (the lid, the Sun clock, the lawnmower...): whoever of yours is still loose stays in the wild.
--- Nobody loses a hunt: no marbles are at stake (GDD §8.6).
function Rules.endHunt(s, why)
    if s.winner then return end
    Trap.loseLoose(s)
    finish(s, "kid", why)
end

--- Is the fight over? Checked after every activation and every card.
function Rules.check(s)
    if s.winner then return end
    local r = s.rule
    local k = s.keeps
    if k and k.endOnBroke then
        if k.kid <= 0 then return finish(s, "rival", "broke") end
        if k.rival <= 0 then return finish(s, "kid", "broke") end
    end
    if r.id == "jar" then
        -- a hunt only ends by itself once no wild bug is left AND none of yours is still loose
        if Q.count(s, "rival") == 0 and not Trap.anyLoose(s) then return finish(s, "kid", "cleared") end
    elseif r.id == "crumbs" then
        if r.score.kid >= r.goal then return finish(s, "kid", "crumbs") end
        if r.score.rival >= r.goal then return finish(s, "rival", "crumbs") end
        if not Q.kidHasBugs(s) then return finish(s, "rival", "wiped") end
    else
        if Q.count(s, "rival") == 0 then return finish(s, "kid", "cleared") end
        if not Q.kidHasBugs(s) then return finish(s, "rival", "wiped") end
    end
end

--- Bugs of this side that are out of the fight (scurried off or pushed off).
function Rules.knockedOut(s, side)
    return s.stats.scurried[side] + s.stats.fell[side]
end

--- The "Sun clock" ran out ("Dinner time! Mom's calling!"): you didn't finish the Rule in time, so you lose. A hunt just
--- ends (you keep what's in the jar), and a Showdown ends with the bell: whatever the marbles say, the duel is over.
function Rules.timeout(s)
    if s.winner then return end
    if s.rule.id == "jar" then return Rules.endHunt(s, "sun") end
    if s.rule.id == "showdown" then return finish(s, "draw", "bell") end
    finish(s, "rival", "sun")
end

--- For the HUD: { kid, rival, goal, label }
function Rules.progress(s)
    local r = s.rule
    if r.id == "jar" then return { kid = r.score.kid, rival = 0, label = "Caught" } end
    if r.id == "crumbs" then return { kid = r.score.kid, rival = r.score.rival, goal = r.goal, label = "Crumbs home" } end
    if r.id == "zumo" then
        return { kid = Rules.knockedOut(s, "rival"), rival = Rules.knockedOut(s, "kid"), label = "Bugs off the stump" }
    end
    return { kid = Rules.knockedOut(s, "rival"), rival = Rules.knockedOut(s, "kid"), label = "Bugs scurried off" }
end

return Rules
