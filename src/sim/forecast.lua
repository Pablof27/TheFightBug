-- Live preview (GDD §5.4 / §12): clone the state, apply the card to the copy, and look at what every bug will do.
-- For bugs that act on the very next tick the answer is exact (we really run that tick on the copy); for the others it is
-- "what it would do if nothing changed".

local State = require("sim.state")
local Instincts = require("sim.instincts")
local Clock = require("sim.clock")
local Rival = require("sim.rival")
local Kid = require("sim.kid")

local Forecast = {}

--- Intents for every bug + the events of the next tick. { intents = {[id] = intent}, events = {...}, rival = peek }
function Forecast.compute(s)
    local out = { intents = {}, events = {}, rival = Rival.peek(s) }
    for _, b in ipairs(s.bugs) do
        local it = Instincts.decide(s, b)
        it.exact = false
        out.intents[b.id] = it
    end
    if s.winner then return out end
    local c = State.clone(s)
    c.record = {}
    Clock.tick(c)
    out.events = c.log
    out.after = c
    for id, it in pairs(c.record) do
        it.exact = true
        out.intents[id] = it
    end
    return out
end

--- The same, after applying a card (no time passes yet). Returns forecast, clone.
function Forecast.afterCard(s, handIndex, sel)
    local c = State.clone(s)
    local ok = Kid.play(c, handIndex, sel, { noClock = true })
    if not ok then return nil end
    local events = State.drain(c)
    local f = Forecast.compute(c)
    f.cardEvents = events
    return f, c
end

--- What the fight looks like once the card has been paid for (all its ticks have run). Used by the "futures" overlay.
function Forecast.outcome(s, handIndex, sel)
    local c = State.clone(s)
    local ok = Kid.play(c, handIndex, sel)
    if not ok then return nil end
    return c
end

--- A compact fingerprint of a state: two different futures give two different strings.
function Forecast.signature(s)
    local parts = {}
    for _, b in ipairs(s.bugs) do
        parts[#parts + 1] = string.format("%s%d@%d,%d/%d/%d", b.side:sub(1, 1), b.id, b.x, b.y, b.hp, b.timer)
    end
    table.sort(parts)
    return table.concat(parts, ";") .. "|" .. tostring(s.winner)
end

return Forecast
