-- Builds a fight from an encounter definition and the run's Jar and deck. An encounter is either one of the hand-made
-- boards of data/encounters.lua (the warm-up) or one built for the run by sim/duel.lua (a duel round) or sim/hunt.lua
-- (a Bug Hunt). Extra encounter fields:
--   openEdges  bugs pushed off the board fall off          house  a Gang leader's house rule (data/rivals.lua)
--   stake      marbles each side has in the pot            keeps  { kid, rival, endOnBroke } every hit moves a marble
--   mood       "angry" | "cocky": the rival's signature move starts 1 tick sooner / later
--   hunt       { spot, buzz, prize }: a Bug Hunt (rule "jar"): the jar is laid on a default tile, you pick your party
--   rivalTeam entries may carry uid (roster entry, for napping), bite and prize

local U = require("sim.util")
local State = require("sim.state")
local Rules = require("sim.rules")
local Rival = require("sim.rival")
local Kid = require("sim.kid")
local Grid = require("sim.grid")
local Park = require("data.park")

local Fight = {}

local TRAP_SPOTS = { { 3, 2 }, { 2, 2 }, { 4, 2 }, { 3, 1 }, { 1, 2 }, { 5, 2 }, { 2, 1 }, { 4, 1 }, { 1, 1 }, { 5, 1 }, { 6, 2 }, { 6, 1 } }

--- enc: encounter table. opts: { jar = {...}, deck = {...}, seed = n, items = { pocket item ids } }
function Fight.new(enc, opts)
    opts = opts or {}
    local s = State.new({ w = enc.w or 6, h = enc.h or 6, layout = enc.layout, sunLimit = enc.sunLimit, seed = opts.seed or enc.seed or 1, openEdges = enc.openEdges })
    s.encounter = enc.id
    s.items = {}
    for _, id in ipairs(opts.items or {}) do s.items[id] = true end
    if s.items.watch then s.sunLimit = s.sunLimit + Park.WATCH end
    s.house = enc.house
    s.stake = enc.stake
    if enc.keeps then s.keeps = { kid = enc.keeps.kid, rival = enc.keeps.rival, endOnBroke = enc.keeps.endOnBroke or nil } end
    if enc.hunt then s.hunt = U.clone(enc.hunt) end
    Rules.setup(s, enc.rule, enc.spawns)
    Rival.setup(s, enc.rival, { timerDelta = enc.mood == "angry" and -1 or enc.mood == "cocky" and 1 or 0 })
    for _, t in ipairs(enc.rivalTeam) do
        State.spawnBug(s, t.species, "rival", t.x, t.y, { timer = t.timer, ready = t.ready, jarUid = t.uid, bite = t.bite, prize = t.prize })
    end
    s.jar = U.clone(enc.jar or opts.jar or {})
    s.deck = U.copyArray(opts.deck or enc.deck or {})
    if enc.kidTeam then
        for _, t in ipairs(enc.kidTeam) do
            State.spawnBug(s, t.species, "kid", t.x, t.y, { timer = t.timer, ready = t.ready, jarUid = t.uid })
        end
    end
    if enc.hand then
        -- scripted opening (the tutorial): fixed hand, fixed draw order
        s.scriptedHand = true
        s.hand = U.copyArray(enc.hand)
        local pile = {}
        for i = #enc.drawPile, 1, -1 do pile[#pile + 1] = enc.drawPile[i] end
        s.deck = pile
        s.phase = "fight"
    else
        s.phase = "deploy"
    end
    s.deployedEntries = {}
    if s.rule.id == "jar" then
        for _, p in ipairs(TRAP_SPOTS) do
            if Kid.placeTrap(s, p[1], p[2]) then break end
        end
    end
    return s
end

local DEFAULT_SPOTS = { { 3, 2 }, { 4, 2 }, { 2, 2 }, { 5, 2 }, { 3, 1 }, { 4, 1 }, { 2, 1 }, { 5, 1 }, { 1, 2 }, { 6, 2 } }

--- Deploys the first Jar entries on default tiles (used by the bots and as the deploy screen's starting suggestion).
function Fight.autoDeploy(s, order)
    local n = 0
    local list = order or {}
    if #list == 0 then for i = 1, #s.jar do list[i] = s.jar[i].uid end end
    for _, uid in ipairs(list) do
        if n >= Kid.MAX_DEPLOY then break end
        for i, e in ipairs(s.jar) do
            if e.uid == uid then
                for _, p in ipairs(DEFAULT_SPOTS) do
                    if Kid.homeFree(s, p[1], p[2]) then
                        if Kid.deploy(s, i, p[1], p[2]) then n = n + 1 end
                        break
                    end
                end
                break
            end
        end
    end
    return n
end

return Fight
