-- Bug Hunts (GDD §8.6): a short fight against a group of wild bugs at home. No marbles are at stake; your bugs can get
-- hurt (they run loose, sim/trap.lua) and you take home whatever ends up in your jar. Every hunt raises the zone's Buzz,
-- which makes the next group meaner (and its prize rarer); a duel calms the park down again.
-- A spot always shows its next group: it is rolled from the run's seed, the act, the spot and how many groups it has
-- shown so far, then the Buzz is applied, so what you see is exactly what you will get.

local U = require("sim.util")
local Run = require("sim.run")
local Park = require("data.park")
local Bugs = require("data.bugs")

local Hunt = {}

--- The zone's three hunt spots.
function Hunt.spots(run) return run.zone and Park.zones[run.zone].spots or {} end

--- The prize of a spot at this Buzz: the entry with the highest Buzz not above it.
function Hunt.prizeAt(spotId, buzz)
    local best, key
    for k, sp in pairs(Park.spots[spotId].prize) do
        if k <= buzz and (not key or k > key) then best, key = sp, k end
    end
    return best
end

--- The next Buzz at which the prize changes, and what it becomes (for the spot card), or nil.
function Hunt.nextPrize(spotId, buzz)
    local best, key
    for k, sp in pairs(Park.spots[spotId].prize) do
        if k > buzz and (not key or k < key) and sp ~= Hunt.prizeAt(spotId, buzz) then best, key = sp, k end
    end
    return key, best
end

--- The group waiting at a spot: { prize, common = {..}, guards = {..}, nest = {..}, timer = delta, bite = +n }
function Hunt.group(run, spotId)
    local spot = Park.spots[spotId]
    local buzz = run.buzz or 0
    local g = Run.gen(run, "spot:" .. run.act .. ":" .. spotId .. ":" .. (run.visits[spotId] or 0))
    local function pick() return spot.common[U.rand(g, #spot.common)] end
    local grp = { prize = Hunt.prizeAt(spotId, buzz), common = { pick(), pick() }, guards = {}, nest = {} }
    local guard = pick()
    if buzz >= 2 then grp.guards[1] = guard end
    if buzz >= 4 then grp.nest = Run.contains(spot.common, "wasp") and { "wasp" } or { "ant", "ant" } end
    grp.timer = buzz == 0 and 1 or (buzz >= 4 and -1 or 0)
    grp.bite = buzz >= 3 and 1 or 0
    return grp
end

local function free(layout, x, y)
    local row = layout[5 - y + 1]
    local ch = row and row:sub(x, x) or "#"
    return ch ~= "p" and ch ~= "k" and ch ~= "~" and ch ~= "#"
end

--- Can you go hunting right now? (free time, nobody waiting to be let go, somebody awake to take along)
function Hunt.can(run)
    if run.phase ~= "free" or Run.overflow(run) > 0 then return false end
    return #Run.available(run) > 0
end

--- The encounter of a hunt at spotId (for sim/fight.lua).
function Hunt.encounter(run, spotId)
    local spot = Park.spots[spotId]
    local zone = Park.zones[run.zone]
    local grp = Hunt.group(run, spotId)
    local team, taken = {}, {}
    local function place(species, spots, prize)
        local sp = Bugs[species]
        local function at(x, y)
            taken[x .. "," .. y] = true
            team[#team + 1] = {
                species = species, x = x, y = y, prize = prize or nil,
                timer = math.max(0, sp.timer + grp.timer + (#team % 2)),
                bite = sp.bite > 0 and sp.bite + grp.bite or nil,
            }
        end
        for _, p in ipairs(spots) do
            if not taken[p[1] .. "," .. p[2]] and free(spot.layout, p[1], p[2]) then return at(p[1], p[2]) end
        end
        for y = 5, 3, -1 do
            for x = 1, 5 do
                if not taken[x .. "," .. y] and free(spot.layout, x, y) then return at(x, y) end
            end
        end
    end
    place(grp.prize, Park.wildSpots.prize, true)
    for _, sp in ipairs(grp.common) do place(sp, Park.wildSpots.common) end
    for _, sp in ipairs(grp.guards) do place(sp, Park.wildSpots.guard) end
    for _, sp in ipairs(grp.nest) do place(sp, Park.wildSpots.common) end
    return {
        id = "hunt", name = spot.name, place = zone.name, arena = zone.huntArena, w = 5, h = 5,
        layout = spot.layout, rule = "jar", rival = spot.nature, sunLimit = Park.SUN.hunt,
        rivalTeam = team, hunt = { spot = spotId, buzz = run.buzz or 0, prize = grp.prize },
    }
end

--- The hunt at s is over: your knocked-out bugs nap (or are gone for good if every one of them got away), what's in
--- the jar joins your Jar (merging into bugs of its kind that haven't grown yet), the Buzz rises and the spot shows its
--- next group. Returns a summary; sum.overflow > 0 means somebody has to go free before anything else (Run.letGo).
function Hunt.settle(run, s)
    local spotId = s.hunt.spot
    local sum = { spot = spotId, caught = {}, napped = {}, lost = {}, buzz = run.buzz }
    for _, k in ipairs(Run.knockedOut(run, s)) do
        local e, f = k.entry, k.field
        if (f.escaped or 0) >= f.total then
            local _, i = Run.entry(run, e.uid)
            table.remove(run.jar, i)
            run.lost[#run.lost + 1] = e.species
            sum.lost[#sum.lost + 1] = e.species
        else
            e.nap = true
            sum.napped[#sum.napped + 1] = e.species
        end
    end
    for _, c in ipairs(s.caught) do
        local how = Run.addCaught(run, c.species)
        sum.caught[#sum.caught + 1] = { species = c.species, prize = c.prize, how = how }
    end
    sum.newSpecies = Run.meet(run, s)
    run.buzz = math.min(Park.BUZZ_MAX, (run.buzz or 0) + 1)
    run.visits[spotId] = (run.visits[spotId] or 0) + 1
    run.hunts = run.hunts + 1
    run.caught = run.caught + #s.caught
    run.fights = run.fights + 1
    sum.overflow = Run.overflow(run)
    return sum
end

return Hunt
