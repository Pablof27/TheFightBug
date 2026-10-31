-- The Ice-Cream Van (GDD §8.9): what it can stock. It comes once per act, after the kid's duel, and stays for the second
-- free time. Every visit draws its stock from these pools with the run's seed; restocking draws again.
-- Card and bug prices live with the cards and bugs (`price` in data/cards.lua and data/bugs.lua), pocket items in
-- data/items.lua. Every price is multiplied by the act (data/park.lua: acts[i].prices).

return {
    CARDS = 4, BUGS = 2, ITEMS = 2,
    cards = { "shove", "juice", "blow", "leaf", "tap", "pebble", "sugar", "crumb", "flick", "stick", "shadow", "sun", "water" },
    bugs = { "wasp", "stag", "redant", "spider", "mantis", "cricket", "pillbug", "ant" },
    -- pet-shop exotics: one may turn up instead of the second bug
    exotics = { hercules = 6 },
    restock = 1,
    -- odds and ends that are always there
    extras = {
        remove = {
            name = "Throw a card away", short = "REMOVE A CARD", price = 3, icon = "icon_undo",
            text = "Pick a card from your deck and throw it away. Once per visit.",
        },
        jar = {
            name = "A bigger Jar", short = "BIGGER JAR", price = 3, icon = "icon_jar",
            text = "Room for one more bug in your Jar.",
        },
        icecream = {
            name = "An ice-cream break", short = "ICE CREAM", price = 2, icon = "icon_icecream",
            text = "Every napping bug in your Jar wakes up.",
        },
    },
}
