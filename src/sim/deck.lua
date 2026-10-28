-- The kid's draw pile (GDD §5.5): you draw 1 card per tick, hand size 7. The discard pile is reshuffled when the deck runs out.

local U = require("sim.util")
local State = require("sim.state")

local Deck = {}

Deck.HAND_MAX = 7
Deck.START_HAND = 5

function Deck.draw(s, n)
    local drawn = {}
    for _ = 1, n or 1 do
        if #s.hand >= Deck.HAND_MAX then break end
        if #s.deck == 0 then
            if #s.discard == 0 then break end
            s.deck = U.shuffle(s, s.discard)
            s.discard = {}
            State.emit(s, "shuffle", {})
        end
        local card = table.remove(s.deck)
        s.hand[#s.hand + 1] = card
        drawn[#drawn + 1] = card
        State.emit(s, "draw", { card = card })
    end
    return drawn
end

return Deck
