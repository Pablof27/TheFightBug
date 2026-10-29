-- The three save slots. Each is a JSON file in LÖVE's save directory (saves/slot1.json ...) in the format of sim/save.lua.
-- A run remembers its slot (run.slot) and is saved at the calm moments of the day: when it starts, after every fight and
-- after every purchase at the Swap Shop. Leaving in the middle of a fight keeps the save from before it. When the day is
-- over the file stays in its slot as a record of how it ended, until it is erased or a new game replaces it.

local Save = require("sim.save")
local Run = require("sim.run")

local Saves = { COUNT = 3, DIR = "saves" }

local function path(slot) return Saves.DIR .. "/slot" .. slot .. ".json" end

local function write(slot, record)
    record.savedAt = os.time()
    love.filesystem.createDirectory(Saves.DIR)
    local ok, err = love.filesystem.write(path(slot), Save.encode(record))
    if not ok then print("Could not save slot " .. slot .. ": " .. tostring(err)) end
    return ok
end

--- What a slot holds: { slot, kind = "empty" | "run" | "ended" | "damaged", run, savedAt, ended = { won }, why }
function Saves.read(slot)
    if not love.filesystem.getInfo(path(slot), "file") then return { slot = slot, kind = "empty" } end
    local rec, why = Save.decode(love.filesystem.read(path(slot)))
    if not rec then return { slot = slot, kind = "damaged", why = why } end
    rec.slot, rec.run.slot = slot, slot
    rec.kind = rec.ended and "ended" or "run"
    return rec
end

function Saves.list()
    local out = {}
    for i = 1, Saves.COUNT do out[i] = Saves.read(i) end
    return out
end

--- A seed for a new game when nobody picks one.
function Saves.randomSeed() return love.math.random(1, Run.SEED_MAX) end

--- A new day in a slot, replacing whatever was there. seed: optional (a random one by default).
function Saves.create(slot, seed)
    local run = Run.new(seed or Saves.randomSeed())
    run.slot = slot
    write(slot, { run = run })
    return run
end

--- Saves a run in progress. Runs without a slot (dev shortcuts) are not saved.
function Saves.store(run)
    if not (run and run.slot) then return false end
    return write(run.slot, { run = run })
end

--- The day is over: its slot keeps it as a record.
function Saves.finish(run, won)
    if not (run and run.slot) then return false end
    return write(run.slot, { run = run, ended = { won = won } })
end

function Saves.erase(slot)
    if love.filesystem.getInfo(path(slot)) then love.filesystem.remove(path(slot)) end
end

return Saves
