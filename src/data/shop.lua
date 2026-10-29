-- The Swap Shop (the demo's version of the GDD §8.2 "Ice-Cream Van"): what you can buy with marbles between fights.
-- A stop is named after the fight it comes BEFORE, so there is none before the first (scripted) fight.
-- The stock is scripted so every demo plays the same way, and every item in it can be bought once.
-- Card and bug prices live with the cards and bugs (`price` in data/cards.lua and data/bugs.lua).

return {
    -- odds and ends that are neither a card nor a bug
    extras = {
        nap = {
            name = "A nap on the bench", short = "A NAP", price = 2, icon = "fx_zzz",
            text = "Every Tired bug in your Jar gets its stamina back.",
        },
        jar = {
            name = "A bigger Jar", short = "BIGGER JAR", price = 3, icon = "icon_jar",
            text = "Room for one more bug in your Jar.",
        },
    },
    stops = {
        -- after beating the Bully, before the Crumb Race: his bugs are up for trade
        lawn = {
            cards = { "shove", "juice", "blow", "leaf" },
            bugs = { "wasp", "stag" },
            extras = { "nap", "jar" },
        },
        -- after beating Ant Farm Girl, before the boss on the stump
        stump = {
            cards = { "tap", "pebble", "shove", "sugar" },
            bugs = { "redant", "stag" },
            extras = { "nap", "jar" },
        },
    },
}
