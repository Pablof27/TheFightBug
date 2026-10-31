-- Duels (GDD §8.5): a match against a rival kid for marbles, over 1 to 3 rounds. Each round is a normal fight.
--   stakes   before each round both sides bet the SMALLER of the two stacks: the poorer side is always all in, and the
--            winner takes the bet. The duel ends when a side is broke, or after the Showdown.
--   ladder   round 1: the rival's favourite Rule. Round 2: the loser picks the game (you choose from the other Rules; the
--            rival picks its second favourite). Round 3: the Showdown, no bet, every hit moves a marble; then it's over.
--   napping  both sides: bugs knocked out in a round sit out the next one (GDD §8.7); the ones that sat out wake up.
--   moods    a rival who lost the last round is Angry (signature move 1 tick sooner), one who won it is Cocky (1 later).
-- The duel lives in run.duel, plain data like the rest of the run.

local U = require("sim.util")
local Run = require("sim.run")
local Park = require("data.park")
local Rivals = require("data.rivals")
local Bugs = require("data.bugs")
local Cards = require("data.cards")
local ShopData = require("data.shop")

local Duel = {}

Duel.SHOWDOWN_FORFEIT = 3   -- what a side that can't field a bug pays in the Showdown

local contains = Run.contains

--- Little Sibling picks a random Rule every round (seeded, so it can be shown in advance).
local function randomRule(run, round)
    local g = Run.gen(run, "sibling:" .. run.act .. ":" .. (run.window or 1) .. ":" .. round)
    return Park.RULES[U.rand(g, #Park.RULES)]
end

local function favourite(run, rivalId, round, second)
    local rules = Rivals[rivalId].rules
    if rules[1] == "random" then return randomRule(run, round) end
    return second and (rules[2] or rules[1]) or rules[1]
end
Duel.favourite = favourite

--- Who can you challenge right now? Window 1: the act's two kids; window 2: its Gang leader.
function Duel.challengers(run)
    if run.phase ~= "free" then return {} end
    if run.window == 1 then return run.kids or {} end
    return { run.leader }
end

--- Start a duel against rivalId. Picking one of the kids sends the other to play the Gang leader, and lose: their whole
--- stack joins the leader's (GDD §8.5.3).
function Duel.start(run, rivalId)
    if run.phase ~= "free" or not contains(Duel.challengers(run), rivalId) then return false, "not now" end
    if Run.overflow(run) > 0 then return false, "jar" end
    local leader = run.window == 2
    if not leader then
        for _, k in ipairs(run.kids) do
            if k ~= rivalId and (run.stacks[k] or 0) > 0 then
                run.fed = { kid = k, marbles = run.stacks[k] }
                run.stacks[run.leader] = (run.stacks[run.leader] or 0) + run.stacks[k]
                run.stacks[k] = 0
            end
        end
    end
    local roster = {}
    for i, sp in ipairs(Rivals[rivalId].roster) do roster[i] = { uid = "r" .. i, species = sp } end
    local rule = favourite(run, rivalId, 1)
    run.duel = {
        rival = rivalId, leader = leader, round = 1, mood = "neutral", rule = rule,
        board1 = Park.zones[run.zone].rules[rule],
        roster = roster, history = {},
        start = { kid = run.marbles, rival = run.stacks[rivalId] },
    }
    run.phase = "duel"
    run.faced[rivalId] = (run.faced[rivalId] or 0) + 1
    return true
end

function Duel.house(run)
    local d = run.duel
    local rv = Rivals[d.rival]
    return d.leader and rv.house and rv.house.id or nil
end

--- The Rule of the coming round ("showdown" in round 3).
function Duel.rule(run)
    local d = run.duel
    return d.round >= 3 and "showdown" or d.rule
end

--- The board of the coming round: the zone plays each Rule on one of its boards; the Showdown stays on round 1's.
function Duel.boardId(run)
    local d = run.duel
    if d.round >= 3 then return d.board1 end
    return Park.zones[run.zone].rules[d.rule]
end

--- Marbles each side puts in the pot this round: the smaller stack (0 in the Showdown).
function Duel.stake(run)
    local d = run.duel
    if d.round >= 3 then return 0 end
    return math.min(run.marbles, run.stacks[d.rival] or 0)
end

--- Who is all in this round: "kid", "rival", "both" (equal stacks) or nil (the Showdown).
function Duel.allIn(run)
    local d = run.duel
    if d.round >= 3 then return nil end
    local a, b = run.marbles, run.stacks[d.rival] or 0
    if a == b then return "both" end
    return a < b and "kid" or "rival"
end

local function blocked(b, layout, x, y)
    local row = layout[b.h - y + 1]
    local ch = row and row:sub(x, x) or "#"
    return ch == "p" or ch == "k" or ch == "~" or ch == "#"
end

--- The bugs the rival sends out: the first `field` roster entries that aren't napping, on their home rows.
function Duel.lineup(run, b, layout)
    local d = run.duel
    local rv = Rivals[d.rival]
    local field = (rv.field or 4) + (Duel.house(run) == "double" and 1 or 0)
    local team, si = {}, 1
    local spots = Park.rivalSpots[b.w]
    for _, e in ipairs(d.roster) do
        if #team >= field then break end
        if not e.nap then
            while spots[si] and blocked(b, layout, spots[si][1], spots[si][2]) do si = si + 1 end
            local p = spots[si]
            if not p then break end
            si = si + 1
            team[#team + 1] = { species = e.species, x = p[1], y = p[2], uid = e.uid, timer = Bugs[e.species].timer + (#team % 2) }
        end
    end
    return team
end

--- Can both sides field a bug? Returns the side that has to forfeit the round, or nil.
function Duel.forfeitSide(run)
    local d = run.duel
    if #Run.available(run) == 0 then return "kid" end
    for _, e in ipairs(d.roster) do if not e.nap then return nil end end
    return "rival"
end

--- The encounter of the coming round (for sim/fight.lua), or nil when there is no round to play right now (the duel is
--- over, or you still have to pick the Rule).
function Duel.encounter(run)
    local d = run.duel
    if not d or d.over or d.pick then return nil end
    local rv = Rivals[d.rival]
    local b = Park.boards[Duel.boardId(run)]
    local rule = Duel.rule(run)
    local layout = U.copyArray(b.layout)
    if run.wet and b.wet then
        -- the sudden shower left puddles (on plain ground only)
        for _, p in ipairs(b.wet) do
            local r = b.h - p.y + 1
            local row = layout[r]
            if row:sub(p.x, p.x) == "." then layout[r] = row:sub(1, p.x - 1) .. "~" .. row:sub(p.x + 1) end
        end
    end
    local house = Duel.house(run)
    local stake = Duel.stake(run)
    local keeps
    if rule == "showdown" then
        keeps = { kid = run.marbles, rival = run.stacks[d.rival], endOnBroke = true }
    elseif house == "keeps" then
        keeps = { kid = run.marbles - stake, rival = run.stacks[d.rival] - stake }
    end
    return {
        id = "duel", name = rv.name, place = Park.zones[run.zone].name, arena = b.arena, w = b.w, h = b.h,
        layout = layout, openEdges = b.openEdges, spawns = rule == "crumbs" and b.spawns or nil,
        rule = rule, rival = d.rival, sunLimit = Park.SUN.duel,
        rivalTeam = Duel.lineup(run, b, layout), house = house, stake = stake, keeps = keeps, mood = d.mood,
        round = d.round, leader = d.leader, boss = d.leader,
    }
end

--- Loser's choice (round 2) when you lost round 1: every built Rule but the one just played.
function Duel.choices(run, last)
    local out = {}
    for _, id in ipairs(Park.RULES) do if id ~= last then out[#out + 1] = id end end
    return out
end

function Duel.pickRule(run, ruleId)
    local d = run.duel
    if not (d and d.pick) or not contains(d.pick, ruleId) then return false end
    d.rule, d.pick = ruleId, nil
    return true
end

--- Napping after a round (both sides): who sat it out wakes up, who got knocked out in it naps.
local function napAfter(run, s)
    local d = run.duel
    local out = { woke = {}, napped = {}, rwoke = {}, rnapped = {} }
    for _, e in ipairs(run.jar) do
        if e.nap then e.nap = nil; out.woke[#out.woke + 1] = e.species end
    end
    for _, e in ipairs(d.roster) do
        if e.nap then e.nap = nil; out.rwoke[#out.rwoke + 1] = e.species end
    end
    for _, k in ipairs(Run.knockedOut(run, s)) do
        k.entry.nap = true
        out.napped[#out.napped + 1] = k.entry.species
    end
    for _, e in ipairs(d.roster) do
        local f = s.field[e.uid]
        if f and f.total > 0 and f.lost >= f.total then
            e.nap = true
            out.rnapped[#out.rnapped + 1] = e.species
        end
    end
    return out
end

--- The rival is broke: what they offer from their pockets, for some of their marbles back (GDD §8.9).
local function offerOf(run, rivalId)
    local mult = Run.prices(run)
    local out = {}
    for _, id in ipairs(Rivals[rivalId].pockets or {}) do
        if Cards[id] then
            out[#out + 1] = { kind = "card", id = id, price = Cards[id].price * mult }
        elseif Bugs[id] then
            out[#out + 1] = { kind = "bug", id = id, price = (Bugs[id].price or ShopData.exotics[id] or 5) * mult }
        end
    end
    return out
end

local function over(run, why)
    local d = run.duel
    d.over = { why = why }
    run.duels = run.duels + 1
    if why == "broke" then
        run.broke = run.broke + 1
        if Run.has(run, "album") then run.marbles = run.marbles + 2; d.over.album = 2 end
        if not d.leader then d.offer = offerOf(run, d.rival) end
    end
end

--- Settle a round from its finished fight s (or a forfeit). Returns the round's record for the summary screens.
function Duel.settle(run, s)
    local d = run.duel
    local rule = Duel.rule(run)
    local stake = s.stake or 0
    local kid, rival
    if s.keeps then
        kid, rival = s.keeps.kid, s.keeps.rival
    else
        kid, rival = run.marbles - stake, run.stacks[d.rival] - stake
    end
    if s.winner == "kid" then kid = kid + 2 * stake
    elseif s.winner == "rival" then rival = rival + 2 * stake
    else kid, rival = kid + stake, rival + stake end
    local rec = { round = d.round, rule = rule, winner = s.winner, why = s.why, stake = stake,
                  delta = kid - run.marbles, kid = kid, rival = rival, allIn = Duel.allIn(run) }
    run.marbles, run.stacks[d.rival] = kid, rival
    local naps = napAfter(run, s)
    rec.woke, rec.napped, rec.rwoke, rec.rnapped = naps.woke, naps.napped, naps.rwoke, naps.rnapped
    rec.newSpecies = Run.meet(run, s)
    if s.winner == "kid" then run.wins = run.wins + 1 elseif s.winner == "rival" then run.losses = run.losses + 1 end
    if s.why ~= "forfeit" then run.fights = run.fights + 1 end
    d.history[#d.history + 1] = rec
    if Duel.house(run) == "rebuy" then d.roster[#d.roster + 1] = { uid = "r" .. (#d.roster + 1), species = "hercules" } end
    if run.marbles <= 0 then
        if run.bigSister then
            -- "Mom says it's lunchtime!" She drags you away and slips you 3 marbles. The duel ends there.
            run.bigSister = false
            run.marbles = Park.BIG_SISTER
            rec.sister = true
            over(run, "sister")
        else
            over(run, "home")
        end
    elseif rival <= 0 then
        over(run, "broke")
    elseif d.round >= 3 then
        over(run, "bell")
    else
        d.round = d.round + 1
        d.mood = s.winner == "kid" and "angry" or "cocky"
        if d.round == 2 then
            if s.winner == "kid" then d.rule = favourite(run, d.rival, 2, true)
            else d.pick = Duel.choices(run, d.rule) end
        end
    end
    return rec
end

--- A side with no bug to field forfeits the round: it loses the bet (or pays 3 marbles in the Showdown).
function Duel.forfeit(run)
    local d = run.duel
    local side = Duel.forfeitSide(run)
    if not side or d.over or d.pick then return nil end
    local s = { winner = side == "kid" and "rival" or "kid", why = "forfeit", field = {}, stake = Duel.stake(run) }
    if Duel.rule(run) == "showdown" then
        local pay = Duel.SHOWDOWN_FORFEIT
        local k, r = run.marbles, run.stacks[d.rival]
        if side == "kid" then pay = math.min(pay, k); k, r = k - pay, r + pay
        else pay = math.min(pay, r); k, r = k + pay, r - pay end
        s.keeps = { kid = k, rival = r }
    end
    return Duel.settle(run, s)
end

--- Take thing i of a broke kid's offer: you hand back its price in marbles (never your last one).
function Duel.takeOffer(run, i)
    local d = run.duel
    local o = d and d.offer and d.offer[i]
    if not o or d.took then return false, "none" end
    if o.kind == "bug" and #run.jar >= run.jarSlots then return false, "jar_full" end
    if run.marbles - o.price < 1 then return false, "broke" end
    run.marbles = run.marbles - o.price
    run.stacks[d.rival] = (run.stacks[d.rival] or 0) + o.price
    if o.kind == "card" then Run.addCard(run, o.id) else Run.addBug(run, o.id) end
    d.took = i
    return true
end

--- Leave a finished duel: after the kid comes the van and more free time, after the Gang leader the act's reward.
function Duel.leave(run)
    local d = run.duel
    if not (d and d.over) then return false end
    run.duel, run.wet = nil, nil
    local why = d.over.why
    if why == "home" then Run.goHome(run); return true end
    if d.leader then Run.endAct(run, why ~= "sister") else Run.enterFree(run, 2) end
    return true
end

return Duel
