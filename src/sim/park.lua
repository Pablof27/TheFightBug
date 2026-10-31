-- Free time at the park (GDD §8.4, §8.9): the bench, the Band-Aid and the events. Bug Hunts are sim/hunt.lua, the van is
-- sim/shop.lua, challenging a kid is sim/duel.lua. Everything here is optional and pure Lua.

local Run = require("sim.run")
local Park = require("data.park")

local P = {}

local function free(run) return run.phase == "free" and Run.overflow(run) == 0 end

--- The bench, once per act. choice: "wake" (every napping bug wakes up) | "remove" (cardIndex goes from your deck).
function P.bench(run, choice, cardIndex)
    if not free(run) or run.bench then return false, "used" end
    if choice == "wake" then
        if not Run.anyNapping(run) then return false, "nobody_napping" end
        Run.wakeAll(run)
    elseif choice == "remove" then
        if #run.deck <= 5 or not run.deck[cardIndex or 0] then return false, "card" end
        table.remove(run.deck, cardIndex)
    else
        return false, "choice"
    end
    run.bench = true
    return true
end

--- The Band-Aid (pocket item), once per act: wake up one napping bug.
function P.bandaid(run, uid)
    if not free(run) or not Run.has(run, "bandaid") or run.bandaid then return false, "used" end
    local e = Run.entry(run, uid)
    if not (e and e.nap) then return false, "awake" end
    e.nap = nil
    run.bandaid = true
    return true
end

--- Is the swap still on? (the bug they wanted may have gone free, or merged away)
function P.swapEntry(run)
    local ev = run.event
    if not (ev and ev.kind == "swap") then return nil end
    return Run.entry(run, ev.want)
end

--- Answer the event of this free time. A swap: accept = true swaps. A lost ball: uid = the bug you send (it naps).
--- A shower or a dog: just happens. Ignoring an event (P.dismiss) is always fine.
function P.answer(run, accept, uid)
    local ev = run.event
    if not free(run) or not ev then return false, "none" end
    if ev.kind == "swap" then
        if accept then
            local e = P.swapEntry(run)
            if not e then return false, "gone" end
            e.species, e.big, e.nap = ev.give, nil, nil
            run.seen[ev.give] = true
        end
    elseif ev.kind == "ball" then
        if accept then
            local e = Run.entry(run, uid)
            if not e or e.nap then return false, "napping" end
            e.nap = true
            Run.addCard(run, ev.card)
        end
    elseif ev.kind == "shower" then
        run.buzz = math.max(0, (run.buzz or 0) - 1)
        run.wet = true
    elseif ev.kind == "dog" then
        for _, id in ipairs(Park.zones[run.zone].spots) do run.visits[id] = (run.visits[id] or 0) + 1 end
    end
    run.event = nil
    return true
end

function P.dismiss(run)
    if not run.event then return false end
    run.event = nil
    return true
end

return P
