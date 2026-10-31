-- A save file: one run (sim/run.lua) as JSON text, with when it was saved and, once the day is over, how it ended.
-- Whatever is read back is checked before the game trusts it: a damaged or hand-edited file is reported, never a crash.
-- Pure Lua like the rest of sim/; the files themselves belong to the client (client/saves.lua).
-- Version 2: One Summer Day (acts, zones, duels, hunts, the van). Version 1 files (the three-fight demo) can't be read.

local json = require("engine.utils.json")
local Run = require("sim.run")
local Cards = require("data.cards")
local Bugs = require("data.bugs")
local Rivals = require("data.rivals")
local Items = require("data.items")
local Rules = require("data.rules")
local Park = require("data.park")

local Save = { VERSION = 2 }

local function int(v, lo, hi)
    return type(v) == "number" and v == math.floor(v) and v >= (lo or 0) and v <= (hi or 2 ^ 31)
end

-- an array and nothing else (JSON gives back [] and {} as the same empty table)
local function list(t)
    if type(t) ~= "table" then return false end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n == #t
end

-- { name = true, ... }, optionally only with names of `known`
local function set(t, known)
    if type(t) ~= "table" then return false end
    for k, v in pairs(t) do
        if type(k) ~= "string" or v ~= true or (known and not known[k]) then return false end
    end
    return true
end

-- { name = number, ... } with names of `known` (or any string) and whole numbers >= 0
local function counts(t, known)
    if type(t) ~= "table" then return false end
    for k, v in pairs(t) do
        if type(k) ~= "string" or not int(v) or (known and not known[k]) then return false end
    end
    return true
end

-- an array of names of `known`
local function names(t, known)
    if not list(t) then return false end
    for _, v in ipairs(t) do if type(v) ~= "string" or not known[v] then return false end end
    return true
end

local function opt(v, check) return v == nil or check(v) end
local function bool(v) return type(v) == "boolean" end

local RULES = { lbs = true, crumbs = true, zumo = true, showdown = true }

local function checkDuel(d, run)
    if type(d) ~= "table" or not Rivals[d.rival] then return false end
    if not (bool(d.leader) and int(d.round, 1, 3) and RULES[d.rule] and Park.boards[d.board1]) then return false end
    if not (d.mood == "neutral" or d.mood == "angry" or d.mood == "cocky") then return false end
    if not list(d.roster) or #d.roster == 0 then return false end
    for _, e in ipairs(d.roster) do
        if type(e) ~= "table" or type(e.uid) ~= "string" or not Bugs[e.species] or not opt(e.nap, bool) then return false end
    end
    if not list(d.history) then return false end
    if d.pick ~= nil and not names(d.pick, RULES) then return false end
    if d.over ~= nil and (type(d.over) ~= "table" or type(d.over.why) ~= "string") then return false end
    if d.offer ~= nil then
        if not list(d.offer) then return false end
        for _, o in ipairs(d.offer) do
            if type(o) ~= "table" or not int(o.price) or not ((o.kind == "card" and Cards[o.id]) or (o.kind == "bug" and Bugs[o.id])) then return false end
        end
    end
    return opt(d.took, function(v) return int(v, 1, 3) end)
end

--- Can the game play this run? true, or false and what is wrong with it.
function Save.check(run)
    if type(run) ~= "table" then return false, "no run in it" end
    if not int(run.seed, 0, Run.SEED_MAX) then return false, "bad seed" end
    if not (int(run.act, 1, Run.ACTS) and Run.PHASES[run.phase] and int(run.window, 1, 2)) then return false, "bad act" end
    if not (int(run.marbles) and int(run.wins) and int(run.losses) and int(run.fights)) then return false, "bad marbles or score" end
    for _, k in ipairs({ "duels", "broke", "hunts", "caught", "rewinds" }) do
        if not int(run[k]) then return false, "bad score" end
    end
    if not list(run.deck) or #run.deck == 0 then return false, "bad deck" end
    for _, id in ipairs(run.deck) do
        if type(id) ~= "string" or not Cards[id] then return false, "unknown card" end
    end
    if not (int(run.jarSlots, 1, 99) and int(run.nextUid, 1) and list(run.jar)) then return false, "bad jar" end
    local uids = {}
    for _, e in ipairs(run.jar) do
        if type(e) ~= "table" or type(e.species) ~= "string" or not Bugs[e.species] then return false, "unknown bug" end
        if not int(e.uid, 1, run.nextUid - 1) or uids[e.uid] then return false, "bad jar" end
        if not (opt(e.nap, bool) and opt(e.big, bool)) then return false, "bad jar" end
        uids[e.uid] = true
    end
    if not names(run.items, Items) then return false, "unknown pocket item" end
    if not (set(run.seen, Bugs) and names(run.released, Bugs) and names(run.lost, Bugs)) then return false, "bad journal" end
    if not (counts(run.faced, Rivals) and counts(run.stacks, Rivals) and counts(run.visits, Park.spots)) then return false, "bad rivals" end
    if not (int(run.buzz, 0, Park.BUZZ_MAX) and bool(run.bigSister)) then return false, "bad day" end
    if run.zone ~= nil and not Park.zones[run.zone] then return false, "unknown zone" end
    if run.lastZone ~= nil and not Park.zones[run.lastZone] then return false, "unknown zone" end
    if run.leader ~= nil and not Rivals[run.leader] then return false, "unknown rival" end
    if run.kids ~= nil and not names(run.kids, Rivals) then return false, "unknown rival" end
    if run.offer ~= nil then
        if not list(run.offer) then return false, "bad zones" end
        for _, o in ipairs(run.offer) do
            if type(o) ~= "table" or not Park.zones[o.zone] or not Rivals[o.leader] then return false, "bad zones" end
        end
    end
    if run.rewardOffer ~= nil and not names(run.rewardOffer, Items) then return false, "bad reward" end
    if run.van ~= nil and (type(run.van) ~= "table" or not int(run.van.restocks) or not set(run.van.sold)) then return false, "bad van" end
    if run.event ~= nil and (type(run.event) ~= "table" or not Park.events[run.event.kind]) then return false, "bad event" end
    if run.fed ~= nil and (type(run.fed) ~= "table" or not Rivals[run.fed.kid] or not int(run.fed.marbles)) then return false, "bad rivals" end
    if not (opt(run.bench, bool) and opt(run.bandaid, bool) and opt(run.wet, bool)) then return false, "bad day" end
    if run.duel ~= nil and not checkDuel(run.duel, run) then return false, "bad duel" end
    if run.result ~= nil and (type(run.result) ~= "table" or not bool(run.result.won)) then return false, "bad ending" end
    -- the phase has what it needs
    if run.phase == "zone" and not run.offer then return false, "bad zones" end
    if (run.phase == "free" or run.phase == "duel") and not (run.zone and run.leader and run.kids) then return false, "bad zone" end
    if run.phase == "duel" and not run.duel then return false, "bad duel" end
    if run.phase == "reward" and not run.rewardOffer then return false, "bad reward" end
    if run.phase == "over" and not run.result then return false, "bad ending" end
    return true
end

--- record: { run = run, savedAt = os.time() (optional), ended = { won = true | false } once the day is over }
--- The run's slot is not written: a file's slot is where it is.
function Save.encode(record)
    local run = {}
    for k, v in pairs(record.run) do if k ~= "slot" then run[k] = v end end
    return json.encode({ version = Save.VERSION, savedAt = record.savedAt, ended = record.ended, run = run })
end

--- The text of a save file -> a record (as above), or nil and why the game can't use it.
function Save.decode(text)
    if type(text) ~= "string" or text == "" then return nil, "empty file" end
    local ok, data = pcall(json.decode, text)
    if not ok or type(data) ~= "table" or data.version == nil then return nil, "not a save file" end
    if data.version ~= Save.VERSION then return nil, "saved by another version of the game" end
    local good, why = Save.check(data.run)
    if not good then return nil, why end
    local ended = data.ended
    if ended ~= nil and (type(ended) ~= "table" or type(ended.won) ~= "boolean") then return nil, "bad ending" end
    if data.savedAt ~= nil and not int(data.savedAt, 0, 2 ^ 33) then return nil, "bad date" end
    return { run = data.run, savedAt = data.savedAt, ended = ended and { won = ended.won } }
end

return Save
