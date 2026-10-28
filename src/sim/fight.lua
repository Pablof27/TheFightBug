-- Builds a fight from an encounter definition (data/encounters.lua) and the run's Jar and deck.

local U = require("sim.util")
local State = require("sim.state")
local Rules = require("sim.rules")
local Rival = require("sim.rival")
local Kid = require("sim.kid")
local Grid = require("sim.grid")

local Fight = {}

--- enc: encounter table. opts: { jar = {...}, deck = {...}, seed = n }
function Fight.new(enc, opts)
    opts = opts or {}
    local s = State.new({ w = enc.w or 6, h = enc.h or 6, layout = enc.layout, sunLimit = enc.sunLimit, seed = opts.seed or enc.seed or 1 })
    s.encounter = enc.id
    Rules.setup(s, enc.rule, enc.spawns)
    Rival.setup(s, enc.rival)
    for _, t in ipairs(enc.rivalTeam) do
        State.spawnBug(s, t.species, "rival", t.x, t.y, { timer = t.timer, ready = t.ready })
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
