-- The Swap Shop (demo rule DD-74): between fights, marbles buy cards for your deck and bugs for your Jar.
-- What is for sale is scripted per stop (data/shop.lua) so every demo plays the same way; each item is sold once.
-- You can never spend the marbles you need for the next rival's bet (DD-72), so shopping can't end your day.
-- Pure Lua like the rest of sim/.

local Run = require("sim.run")
local Cards = require("data.cards")
local Bugs = require("data.bugs")
local Data = require("data.shop")

local Shop = {}

local function stopOf(run) return Data.stops[Run.currentEncounter(run)] end

--- Is there a shop before the next fight? (There is none before the first one: that fight is scripted.)
function Shop.isOpen(run) return stopOf(run) ~= nil end

--- The items of the current stop, in display order: { key, kind = "card" | "bug" | "nap" | "jar", id, price }
function Shop.stock(run)
    local stop = stopOf(run)
    local out = {}
    if not stop then return out end
    for _, id in ipairs(stop.cards or {}) do out[#out + 1] = { kind = "card", id = id, price = Cards[id].price } end
    for _, sp in ipairs(stop.bugs or {}) do out[#out + 1] = { kind = "bug", id = sp, price = Bugs[sp].price } end
    for _, ex in ipairs(stop.extras or {}) do out[#out + 1] = { kind = ex, id = ex, price = Data.extras[ex].price } end
    local where = Run.currentEncounter(run)
    for i, it in ipairs(out) do it.key = where .. ":" .. i .. ":" .. it.id end
    return out
end

--- Marbles that must stay in your pocket: the next rival's bet.
function Shop.reserve(run) return Run.bet(run) end

--- Can this item be bought right now? false + why: "sold" | "jar_full" | "nobody_tired" | "broke" | "reserve"
function Shop.check(run, item)
    if run.bought[item.key] then return false, "sold" end
    if item.kind == "bug" and #run.jar >= run.jarSlots then return false, "jar_full" end
    if item.kind == "nap" and not Run.anyTired(run) then return false, "nobody_tired" end
    if item.price > run.marbles then return false, "broke" end
    if run.marbles - item.price < Shop.reserve(run) then return false, "reserve" end
    return true
end

function Shop.buy(run, item)
    local ok, why = Shop.check(run, item)
    if not ok then return false, why end
    run.marbles = run.marbles - item.price
    run.bought[item.key] = true
    if item.kind == "card" then
        Run.addCard(run, item.id)
    elseif item.kind == "bug" then
        Run.addBug(run, item.id)
        run.seen[item.id] = true
    elseif item.kind == "nap" then
        Run.rest(run)
    elseif item.kind == "jar" then
        run.jarSlots = run.jarSlots + 1
    end
    return true
end

return Shop
