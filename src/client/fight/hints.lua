-- The tutorial voice (fight 1 only): a few hints shown in order of importance, each depending on what is happening.
-- Nothing here forces the player to do anything; hints just point at what the interface can show.

local Hints = {}

local function bugAt(scene, species, side)
    for _, b in ipairs(scene.state.bugs) do if b.species == species and b.side == side then return b end end
end

local LIST = {
    {
        id = "wasp", once = true, ttl = 40,
        text = "A wasp, a stag beetle and more are after your bugs! You never give orders. You change the world and they follow their instincts. Dotted arrows show what each bug will do when its timer hits 0.",
        when = function(s) return s.state.stats.cards == 0 and s.state.tick == 0 and not s.armed and not s.hover.card end,
    },
    {
        id = "shadow", once = false,
        text = "SHADOW costs no time. The wasp's timer goes 1 -> 2, so it will act one tick later. Free actions are the best actions.",
        when = function(s) return s.hover.card and s.state.hand[s.hover.card] == "shadow" or (s.armed and s.armed.id == "shadow") end,
    },
    {
        id = "sugar", once = false,
        text = "SUGAR attracts ants AND wasps, yours and theirs. Your mantis (E3) is Ready: it strikes whatever steps next to it. Try the tile E4, then watch the arrows.",
        when = function(s) return (s.hover.card and s.state.hand[s.hover.card] == "sugar") or (s.armed and s.armed.id == "sugar") end,
    },
    {
        id = "wait", once = true, ttl = 20,
        text = "Time only moves when YOU spend it. Press WAIT (or Space) to let one tick pass and see the bugs act in order: your bugs first, then theirs.",
        when = function(s) return s.state.tick >= 1 and s.state.tick <= 2 and not s.armed and not s.state.winner and s.state.stats.cards >= 1 end,
    },
    {
        id = "alarm", once = true, ttl = 14,
        text = "A hurt wasp sounds the ALARM: every other wasp hurries up (-1 timer). One small change, a very different next tick.",
        when = function(s) return s.sawAlarm end,
    },
    {
        id = "stag", once = false, ttl = 18,
        text = "The stag beetle will charge down its column and ram whatever is in line. It is HEAVY: Flick can't move it. Block it with a stick? Move the target? Or let the pill bug curl and roll?",
        when = function(s)
            local stag = bugAt(s, "stag", "rival")
            return stag and stag.timer <= 2 and not s.armed and s.state.tick >= 2 and not s.state.winner and not s.shownStag
        end,
        onShow = function(s) s.shownStag = true end,
    },
    {
        id = "stomp", once = true, ttl = 16,
        text = "The Bully's STOMP is coming. It lands on the 3x3 area with the most of your bugs and delays everyone in it by +2. Spread out, or shadow his bugs!",
        when = function(s) return s.state.rival and s.state.rival.timer <= 2 and not s.state.winner end,
    },
    {
        id = "rewind", once = true, ttl = 14,
        text = "Tip: REWIND (Z) takes back your last move. Try the same card on a different tile and compare the futures: small changes, big differences.",
        when = function(s) return s.state.stats.cards >= 3 and not s.armed and not s.state.winner end,
    },
}

--- The hint to show right now (or nil).
function Hints.current(scene)
    for _, h in ipairs(LIST) do
        if not (h.once and scene.hintsDone[h.id]) and not scene.hintsMuted[h.id] and h.when(scene) then
            return h
        end
    end
    return nil
end

return Hints
