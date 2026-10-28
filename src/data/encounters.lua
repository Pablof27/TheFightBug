-- The three fights of the demo: a morning at the park. Layouts are written top row (y = 6) first, column A first.
--   .  plain ground     g  grass (cover)   l  leaf (cover)   p  pebble   k  knot (stump)   ~  puddle
--   s  shade (+1 timer when a bug acts here)    u  sun patch (-1)    #  not part of the arena
-- Teams: { species, x, y, timer }. Home rows are 1-2 (yours) and 5-6 (the rival's).

return {
    -- 1 ─ The GDD's own worked example (§5.13) is the opening position, so the first thing you do is solve it.
    {
        id = "sandbox", name = "Sandbox Showdown", place = "The Sandbox", arena = "sandbox",
        rule = "lbs", rival = "bully", sunLimit = 40, tutorial = true,
        layout = {
            "s....~",
            "..p..~",
            "......",
            "l....p",
            "......",
            ".....u",
        },
        rivalTeam = {
            { species = "wasp", x = 2, y = 4, timer = 1 },
            { species = "stag", x = 4, y = 5, timer = 3 },
            { species = "wasp", x = 5, y = 6, timer = 4 },
            { species = "wasp", x = 1, y = 5, timer = 5 },
        },
        kidTeam = {
            { species = "ant", x = 1, y = 2, timer = 2, uid = 1 },
            { species = "ant", x = 2, y = 2, timer = 2, uid = 1 },
            { species = "ant", x = 3, y = 2, timer = 2, uid = 1 },
            { species = "pillbug", x = 4, y = 2, timer = 3, uid = 2 },
            { species = "mantis", x = 5, y = 3, timer = 0, ready = true, uid = 3 },
        },
        jar = {
            { uid = 4, species = "cricket" },
            { uid = 5, species = "spider" },
        },
        hand = { "shadow", "sugar", "flick", "stick", "crumb" },
        drawPile = { "flick", "sun", "crumb", "water", "flick", "stick" },
    },

    -- 2 ─ Crumb Race on the lawn. Everything is point-symmetric: nobody starts with an edge.
    {
        id = "lawn", name = "Lawn Rumble", place = "The Lawn", arena = "lawn",
        rule = "crumbs", rival = "antgirl", sunLimit = 40,
        deploy = { "ant", "cricket", "pillbug" },
        layout = {
            "..g...",
            ".g..l.",
            "..~g..",
            "..g~..",
            ".l..g.",
            "...g..",
        },
        spawns = {
            { tick = 0, x = 2, y = 4 }, { tick = 0, x = 5, y = 3 },
            { tick = 3, x = 3, y = 3 }, { tick = 3, x = 4, y = 4 },
            { tick = 6, x = 1, y = 3 }, { tick = 6, x = 6, y = 4 },
            { tick = 9, x = 2, y = 3 }, { tick = 9, x = 5, y = 4 },
            { tick = 12, x = 1, y = 4 }, { tick = 12, x = 6, y = 3 },
        },
        rivalTeam = {
            { species = "ant", x = 2, y = 6, timer = 2 },
            { species = "ant", x = 3, y = 5, timer = 2 },
            { species = "ant", x = 4, y = 6, timer = 2 },
            { species = "redant", x = 5, y = 5, timer = 2 },
            { species = "redant", x = 1, y = 5, timer = 2 },
        },
    },

    -- 3 ─ Mushi-Zumo on a tree stump: a small round arena (5x5), open edges, and nobody bites: everybody shoves.
    {
        id = "stump", name = "Stump Showdown", place = "The Old Stump", arena = "stump",
        rule = "zumo", rival = "rich", sunLimit = 40, boss = true, w = 5, h = 5,
        deploy = { "stag", "pillbug", "mantis" },
        layout = {
            ".....",
            ".....",
            "..k..",
            ".....",
            ".....",
        },
        rivalTeam = {
            { species = "hercules", x = 3, y = 4, timer = 3 },
        },
    },
}
