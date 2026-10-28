-- The clock (GDD §5.3). There are no turns: the clock only moves when the kid spends time.
-- One tick:  1. every timer goes down by 1 (Ready ambushers stay at 0, so do the rival's signature timer rules)
--            2. every bug at 0 acts, your bugs first, then the rival's, each side in reading order, then the rival kid
--            3. you draw 1 card   4. effects wear off, crumbs appear, the Rule is checked

local State = require("sim.state")
local Q = require("sim.query")
local Instincts = require("sim.instincts")
local R = require("sim.resolver")
local Rival = require("sim.rival")
local Rules = require("sim.rules")
local Deck = require("sim.deck")

local Clock = {}

--- One bug wakes up: gets up if flipped, otherwise follows its instinct.
function Clock.activate(s, bug)
    bug.acted = true
    if bug.flipped then
        bug.flipped = false
        State.emit(s, "act", { id = bug.id, kind = "getup" })
        State.emit(s, "getup", { id = bug.id })
        R.resetTimer(s, bug)
        return
    end
    local it = Instincts.decide(s, bug)
    if s.record then s.record[bug.id] = it end
    R.perform(s, bug, it)
end

function Clock.tick(s)
    s.tick = s.tick + 1
    s.stats.ticks = s.stats.ticks + 1
    State.emit(s, "tick", { n = s.tick })

    local timers = {}
    for _, b in ipairs(s.bugs) do
        b.acted = false
        if b.timer > 0 then b.timer = b.timer - 1 end
        timers[#timers + 1] = { id = b.id, timer = b.timer }
    end
    Rival.countdown(s)
    State.emit(s, "timers", { list = timers, rival = s.rival and s.rival.timer })

    R.sweepReady(s)
    local guard = 0
    while not s.winner do
        guard = guard + 1
        if guard > 100 then break end
        local pick
        for _, b in ipairs(Q.timeline(s)) do
            if b.timer == 0 and not b.ready and not b.acted then pick = b break end
        end
        if not pick then break end
        Clock.activate(s, pick)
        Rules.check(s)
    end
    if not s.winner then
        Rival.act(s)
        Rules.check(s)
    end
    Deck.draw(s, 1)
    Rules.endOfTick(s)
    Rules.check(s)
    if not s.winner and s.tick >= s.sunLimit then Rules.timeout(s) end
end

function Clock.advance(s, n)
    for _ = 1, n do
        if s.winner then return end
        Clock.tick(s)
    end
end

return Clock
