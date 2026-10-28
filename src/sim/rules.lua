-- Rules of the Game (GDD §5.11): what a fight is about. Three are implemented for the demo.

local Grid = require("sim.grid")
local State = require("sim.state")
local Q = require("sim.query")
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

--- Things that happen at the end of every tick: scent trails fade, crumbs appear.
function Rules.endOfTick(s)
    for _, c in pairs(s.cells) do
        if c.trail then
            c.trail.ttl = c.trail.ttl - 1
            if c.trail.ttl <= 0 then c.trail = nil end
        end
    end
    if s.rule.id == "crumbs" then Rules.spawnLoot(s, s.tick) end
end

local function finish(s, side, why)
    if s.winner then return end
    s.winner, s.why = side, why
    State.emit(s, "end", { winner = side, why = why })
end

--- Is the fight over? Checked after every activation and every card.
function Rules.check(s)
    if s.winner then return end
    local r = s.rule
    if r.id == "crumbs" then
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

--- The "Sun clock" ran out ("Dinner time! Mom's calling!"): the Rule's score decides, then total stamina. A tie is not a win.
function Rules.timeout(s)
    if s.winner then return end
    local r = s.rule
    local a, b
    if r.id == "crumbs" then
        a, b = r.score.kid, r.score.rival
    elseif r.id == "zumo" then
        a, b = Rules.knockedOut(s, "rival"), Rules.knockedOut(s, "kid")
    else
        a, b = Q.totalHp(s, "kid"), Q.totalHp(s, "rival")
    end
    if a == b then a, b = Q.totalHp(s, "kid"), Q.totalHp(s, "rival") end
    finish(s, a > b and "kid" or "rival", "sun")
end

--- For the HUD: { kid, rival, goal, label }
function Rules.progress(s)
    local r = s.rule
    if r.id == "crumbs" then return { kid = r.score.kid, rival = r.score.rival, goal = r.goal, label = "Crumbs home" } end
    if r.id == "zumo" then
        return { kid = Rules.knockedOut(s, "rival"), rival = Rules.knockedOut(s, "kid"), label = "Bugs off the stump" }
    end
    return { kid = Rules.knockedOut(s, "rival"), rival = Rules.knockedOut(s, "kid"), label = "Bugs scurried off" }
end

return Rules
