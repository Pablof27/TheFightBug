-- A save file: one run (sim/run.lua) as JSON text, with when it was saved and, once the day is over, how it ended.
-- Whatever is read back is checked before the game trusts it: a damaged or hand-edited file is reported, never a crash.
-- Pure Lua like the rest of sim/; the files themselves belong to the client (client/saves.lua).

local json = require("engine.utils.json")
local Run = require("sim.run")
local Cards = require("data.cards")
local Bugs = require("data.bugs")

local Save = { VERSION = 1 }

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

--- Can the game play this run? true, or false and what is wrong with it.
function Save.check(run)
    if type(run) ~= "table" then return false, "no run in it" end
    if not int(run.seed, 0, Run.SEED_MAX) then return false, "bad seed" end
    if not int(run.node, 1, #Run.NODES) then return false, "bad fight number" end
    if not (int(run.marbles) and int(run.wins) and int(run.losses)) then return false, "bad marbles or score" end
    if run.rewinds ~= nil and not int(run.rewinds) then return false, "bad rewind count" end
    if not list(run.deck) or #run.deck == 0 then return false, "bad deck" end
    for _, id in ipairs(run.deck) do
        if type(id) ~= "string" or not Cards[id] then return false, "unknown card" end
    end
    if not (int(run.jarSlots, 1, 99) and int(run.nextUid, 1) and list(run.jar)) or #run.jar > run.jarSlots then return false, "bad jar" end
    local uids = {}
    for _, e in ipairs(run.jar) do
        if type(e) ~= "table" or type(e.species) ~= "string" or not Bugs[e.species] then return false, "unknown bug" end
        if not int(e.uid, 1, run.nextUid - 1) or uids[e.uid] then return false, "bad jar" end
        if e.tired ~= nil and type(e.tired) ~= "boolean" then return false, "bad jar" end
        uids[e.uid] = true
    end
    if not (set(run.bought) and set(run.seen, Bugs)) then return false, "bad shop or journal" end
    if run.released ~= nil then
        if not list(run.released) then return false, "bad journal" end
        for _, sp in ipairs(run.released) do
            if type(sp) ~= "string" or not Bugs[sp] then return false, "bad journal" end
        end
    end
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
