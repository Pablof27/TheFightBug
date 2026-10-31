-- Bug Hunts (GDD §8.6): the jar laid on its side is a trap, and your bugs that get knocked out run loose instead of
-- scurrying off. A wild bug that walks, lands or is pushed onto the jar's tile is caught; a loose bug of yours that gets
-- back into the jar is safe (it naps); one that crawls off the board, or is still loose when the hunt ends, is free for good.
-- Used by the resolver (arrivals), the rules (end of the hunt, the Pooter) and the card effects (the Sweep Net).

local Grid = require("sim.grid")
local State = require("sim.state")

local Trap = {}

function Trap.on(s, x, y)
    local c = Grid.cell(s, x, y)
    return c ~= nil and c.trap == true
end

--- A wild bug fell into the jar. how: nil (walked/landed/pushed in) | "net" | "pooter" | "sweep"
function Trap.catch(s, b, how)
    if b.gone then return end
    s.caught[#s.caught + 1] = { species = b.species, prize = b.prize or nil }
    s.rule.score.kid = s.rule.score.kid + 1
    State.emit(s, "catch", { id = b.id, species = b.species, x = b.x, y = b.y, prize = b.prize, how = how, score = s.rule.score.kid })
    State.removeBug(s, b)
end

--- One of your bugs was knocked out on a hunt: it runs loose. From now on it only crawls for the nearest edge, and the
--- wild bugs ignore it. Its timer starts over, so there is always time to react.
function Trap.loosen(s, b)
    b.loose = true
    b.hp = 0
    b.ready, b.curled, b.flipped, b.soaked = false, false, false, false
    b.carrying = nil
    b.instinct = "loose"
    b.timer = b.baseTimer
    State.markLost(s, b)
    State.emit(s, "loose", { id = b.id, x = b.x, y = b.y, timer = b.timer })
end

local function field(s, b) return b.jarUid and s.field[b.jarUid] end

--- A loose bug is back in the jar: safe, but worn out (it naps).
function Trap.rescue(s, b)
    local f = field(s, b)
    if f then f.rescued = (f.rescued or 0) + 1 end
    State.emit(s, "rescue", { id = b.id, x = b.x, y = b.y })
    State.removeBug(s, b)
end

--- A loose bug crawled off the board: it found a new home in the wild.
function Trap.escape(s, b, dx, dy)
    local f = field(s, b)
    if f then f.escaped = (f.escaped or 0) + 1 end
    State.emit(s, "escape", { id = b.id, x = b.x, y = b.y, dx = dx or 0, dy = dy or 0, species = b.species })
    State.removeBug(s, b)
end

function Trap.anyLoose(s)
    for _, b in ipairs(s.bugs) do if b.loose then return true end end
    return false
end

--- The hunt is over: whoever is still loose stays in the wild.
function Trap.loseLoose(s)
    local list = {}
    for _, b in ipairs(s.bugs) do if b.loose then list[#list + 1] = b end end
    for _, b in ipairs(list) do Trap.escape(s, b) end
end

return Trap
