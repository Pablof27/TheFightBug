-- The Ice-Cream Van (GDD §8.9): it comes once per act, after the kid's duel, and stays for the second free time. Its stock
-- is drawn from data/shop.lua with the run's seed (restocking draws again); prices grow with the act. It never sells you
-- your last marble: with 0 marbles nobody plays with you. Pure Lua like the rest of sim/.

local U = require("sim.util")
local Run = require("sim.run")
local Cards = require("data.cards")
local Bugs = require("data.bugs")
local Items = require("data.items")
local Data = require("data.shop")

local Shop = {}

Shop.MIN_DECK = 5    -- the van won't throw away a card from a deck this small

function Shop.isOpen(run) return run.phase == "free" and run.window == 2 and run.van ~= nil end

--- What the van has right now, in display order: { key, kind = "card" | "bug" | "item" | "remove" | "jar" | "icecream", id, price }
function Shop.stock(run)
    local van = run.van
    if not van then return {} end
    local mult = Run.prices(run)
    local g = Run.gen(run, "van:" .. run.act .. ":" .. van.restocks)
    local out = {}
    local cards = U.shuffle(g, U.copyArray(Data.cards))
    for i = 1, Data.CARDS do out[#out + 1] = { kind = "card", id = cards[i], price = Cards[cards[i]].price * mult } end
    local bugs = U.shuffle(g, U.copyArray(Data.bugs))
    out[#out + 1] = { kind = "bug", id = bugs[1], price = Bugs[bugs[1]].price * mult }
    local exotics = {}
    for id in pairs(Data.exotics) do exotics[#exotics + 1] = id end
    table.sort(exotics)
    if #exotics > 0 and U.rand(g, 3) == 1 then
        local id = exotics[U.rand(g, #exotics)]
        out[#out + 1] = { kind = "bug", id = id, price = Data.exotics[id] * mult, exotic = true }
    else
        out[#out + 1] = { kind = "bug", id = bugs[2], price = Bugs[bugs[2]].price * mult }
    end
    local items = {}
    for id in pairs(Items) do if not Run.has(run, id) then items[#items + 1] = id end end
    table.sort(items)
    U.shuffle(g, items)
    for i = 1, math.min(Data.ITEMS, #items) do out[#out + 1] = { kind = "item", id = items[i], price = Items[items[i]].price * mult } end
    for i, it in ipairs(out) do it.key = van.restocks .. ":" .. i .. ":" .. it.id end
    -- odds and ends: always there, once per visit
    for _, x in ipairs({ "remove", "jar", "icecream" }) do
        out[#out + 1] = { kind = x, id = x, price = Data.extras[x].price * mult, key = "x:" .. x }
    end
    return out
end

function Shop.restockPrice(run) return Data.restock * Run.prices(run) end

--- Can this item be bought right now? false + why: "closed" | "sold" | "owned" | "jar_full" | "nobody_napping" |
--- "deck_small" | "broke" | "last"
function Shop.check(run, item)
    if not Shop.isOpen(run) then return false, "closed" end
    if run.van.sold[item.key] then return false, "sold" end
    if item.kind == "item" and Run.has(run, item.id) then return false, "owned" end
    if item.kind == "bug" and #run.jar >= run.jarSlots then return false, "jar_full" end
    if item.kind == "icecream" and not Run.anyNapping(run) then return false, "nobody_napping" end
    if item.kind == "remove" and #run.deck <= Shop.MIN_DECK then return false, "deck_small" end
    if item.price > run.marbles then return false, "broke" end
    if run.marbles - item.price < 1 then return false, "last" end
    return true
end

--- Buy it. For "remove", cardIndex says which card of the deck goes.
function Shop.buy(run, item, cardIndex)
    local ok, why = Shop.check(run, item)
    if not ok then return false, why end
    if item.kind == "remove" and not run.deck[cardIndex or 0] then return false, "card" end
    run.marbles = run.marbles - item.price
    run.van.sold[item.key] = true
    if item.kind == "card" then
        Run.addCard(run, item.id)
    elseif item.kind == "bug" then
        Run.addBug(run, item.id)
    elseif item.kind == "item" then
        run.items[#run.items + 1] = item.id
    elseif item.kind == "jar" then
        run.jarSlots = run.jarSlots + 1
    elseif item.kind == "icecream" then
        Run.wakeAll(run)
    elseif item.kind == "remove" then
        table.remove(run.deck, cardIndex)
    end
    return true
end

--- Fresh stock: everything not bought is swapped for a new draw.
function Shop.restock(run)
    if not Shop.isOpen(run) then return false, "closed" end
    local price = Shop.restockPrice(run)
    if run.marbles - price < 1 then return false, "last" end
    run.marbles = run.marbles - price
    run.van.restocks = run.van.restocks + 1
    return true
end

return Shop
