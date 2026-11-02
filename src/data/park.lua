-- One Summer Day (GDD §8): the park as content. Acts, zones, the boards duels are played on, hunt spots, nature's moves,
-- events and the numbers of the marble economy. Mechanics live in sim/run.lua, sim/duel.lua, sim/hunt.lua, sim/park.lua.
-- Layouts are written top row first, column A first (legend in data/encounters.lua). All numbers are first guesses.

local Park = {}

Park.START_MARBLES = 10
Park.JAR_SLOTS = 6
Park.BIG_SISTER = 3          -- marbles she slips you, once per run
Park.HUNT_PARTY = 3          -- bugs you can take on a hunt
Park.SUN = { duel = 40, hunt = 20 }
Park.WATCH = 10              -- extra ticks with the Wristwatch

-- A run is one summer day. Each act: pick 1 of 2 zones (each shows its Gang leader), free time, a kid, the van, free time,
-- the Gang leader. kidStacks[wealth] = a kid's marbles in that act; prices multiply everything the van and the kids sell.
Park.acts = {
    { id = "morning", name = "Morning", leaders = { "bully", "antgirl" }, kidStacks = { 3, 5, 6, 7 }, leaderStack = 14, prices = 1,
      text = "Cool, busy ground. The early kids are already at the sandbox." },
    { id = "afternoon", name = "Afternoon", leaders = { "nerd", "twins" }, kidStacks = { 6, 9, 12, 15 }, leaderStack = 30, prices = 2,
      text = "Hot! Everything with six legs is wide awake." },
    { id = "dusk", name = "Dusk", leaders = { "rich", "champ" }, kidStacks = { 12, 18, 24, 30 }, leaderStack = 60, prices = 4,
      text = "Long shadows. The big kids come out to play." },
}

-- The boards duels are played on. A zone plays each Rule on one of them.
Park.boards = {
    sandbox = {
        arena = "sandbox", w = 6, h = 6,
        -- point-symmetric: nobody starts with the better side
        layout = {
            "s..p..",
            "......",
            "~.u..l",
            "l..u.~",
            "......",
            "..p..s",
        },
        spawns = {
            { tick = 0, x = 2, y = 4 }, { tick = 0, x = 5, y = 3 },
            { tick = 3, x = 4, y = 4 }, { tick = 3, x = 3, y = 3 },
            { tick = 6, x = 5, y = 4 }, { tick = 6, x = 2, y = 3 },
            { tick = 9, x = 3, y = 4 }, { tick = 9, x = 4, y = 3 },
            { tick = 12, x = 2, y = 4 }, { tick = 12, x = 5, y = 3 },
        },
        wet = { { x = 2, y = 5 }, { x = 5, y = 2 } },
    },
    lawn = {
        arena = "lawn", w = 6, h = 6,
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
        wet = { { x = 2, y = 3 }, { x = 5, y = 4 } },
    },
    stump = {
        arena = "stump", w = 5, h = 5, openEdges = true,
        layout = {
            ".....",
            ".....",
            "..k..",
            ".....",
            ".....",
        },
    },
}

-- The tiles of the rival's home rows, by board size. Each duel shuffles them (sim/duel.lua lineup); blocked ones are skipped.
Park.rivalSpots = {
    [6] = { { 3, 6 }, { 4, 6 }, { 2, 5 }, { 5, 5 }, { 2, 6 }, { 5, 6 }, { 1, 5 }, { 6, 5 }, { 3, 5 }, { 4, 5 }, { 1, 6 }, { 6, 6 } },
    [5] = { { 3, 5 }, { 2, 4 }, { 4, 4 }, { 2, 5 }, { 4, 5 }, { 1, 4 }, { 5, 4 }, { 3, 4 }, { 1, 5 }, { 5, 5 } },
}

-- The Rules kids play (GDD §5.11 ★); Little Sibling rolls one of them. Mushi-Zumo is built (sim/rules.lua) but parked
-- (D-010): most players lack the heavy bugs or the shoves to win it. The Showdown is always round 3, on the duel's board.
Park.RULES = { "lbs", "crumbs" }

Park.zones = {
    sandbox = {
        name = "The Sandbox", short = "Sandbox", backdrop = "sandbox", huntArena = "sandbox5",
        rules = { lbs = "sandbox", crumbs = "sandbox" },
        spots = { "bucket", "corner", "castle" },
        text = "Dry sand, a forgotten bucket and the ruins of yesterday's castle.",
    },
    lawn = {
        name = "The Lawn", short = "Lawn", backdrop = "lawn", huntArena = "lawn5",
        rules = { lbs = "lawn", crumbs = "lawn" },
        spots = { "grass", "clover", "molehill" },
        text = "Long grass and clover nobody has mowed for a week.",
    },
    stump = {
        name = "The Old Stump", short = "Old Stump", backdrop = "stump", huntArena = "stump",
        rules = { lbs = "stump", crumbs = "lawn" },
        spots = { "bark", "deadwood", "litter" },
        text = "What's left of the old oak: bark, rotting wood and a carpet of dead leaves.",
    },
}

-- Hunt spots (GDD §8.6): a 5x5 habitat, the bugs that live there, the prize (which gets rarer as the Buzz rises) and
-- nature's move. prize = { [buzz] = species }: the highest key not above the Buzz wins.
Park.spots = {
    bucket = {
        name = "Under the bucket", icon = "pebble_1",
        text = "Damp and dark: woodlice heaven. Something bigger is under there too.",
        common = { "pillbug", "ant" }, prize = { [0] = "cricket", [2] = "spider", [3] = "stag" }, nature = "dog",
        layout = { "ss.ss", "..s..", ".p...", ".....", "....." },
    },
    corner = {
        name = "The dry corner", icon = "sunpatch",
        text = "Hot, loose sand. Ants patrol it, and hunters wait for them.",
        common = { "ant", "redant" }, prize = { [0] = "spider", [2] = "wasp", [3] = "mantis" }, nature = "bird",
        layout = { "u...u", ".....", "..p..", ".....", "u...." },
    },
    castle = {
        name = "The sandcastle ruins", icon = "puddle_1",
        text = "The moat still holds water. Wasps come down to drink.",
        common = { "ant", "wasp" }, prize = { [0] = "cricket", [2] = "wasp", [3] = "mantis" }, nature = "shower",
        layout = { ".~.~.", ".p.p.", ".....", "~...~", "....." },
    },
    grass = {
        name = "The long grass", icon = "grass_1",
        text = "Tall enough to hide anything. Crickets sing in it; a mantis may be watching.",
        common = { "cricket", "ant" }, prize = { [0] = "spider", [2] = "mantis", [4] = "mantis" }, nature = "mower",
        layout = { "g.g.g", ".g.g.", "g...g", ".....", "..g.." },
    },
    clover = {
        name = "The clover patch", icon = "leaf_1",
        text = "Flowers mean visitors: ants below, wasps above.",
        common = { "ant", "wasp" }, prize = { [0] = "cricket", [2] = "spider", [3] = "mantis" }, nature = "bird",
        layout = { ".l.g.", "g...l", "..l..", ".....", ".g..." },
    },
    molehill = {
        name = "The molehill", icon = "pebble_2",
        text = "Fresh earth turned over. Ants are busy rebuilding.",
        common = { "ant", "redant" }, prize = { [0] = "pillbug", [2] = "cricket", [3] = "stag" }, nature = "dog",
        layout = { "..p..", ".g.g.", "p...p", ".....", "g...g" },
    },
    bark = {
        name = "The bark", icon = "knot",
        text = "Jumping spiders sunbathe on it. Beetles crawl out of the cracks.",
        common = { "spider", "ant" }, prize = { [0] = "cricket", [2] = "spider", [3] = "stag" }, nature = "bird",
        layout = { "s...s", ".p.p.", ".....", "..p..", "....." },
    },
    deadwood = {
        name = "The dead wood", icon = "stick",
        text = "Soft, rotting wood: a stag beetle's nursery for years.",
        common = { "pillbug", "redant" }, prize = { [0] = "spider", [2] = "stag", [4] = "stag" }, nature = "shower",
        layout = { "sl.ls", ".....", "l.p.l", ".....", ".s.s." },
    },
    litter = {
        name = "The leaf litter", icon = "leaf_2",
        text = "A thick carpet of dead leaves. Everything here hides.",
        common = { "pillbug", "cricket" }, prize = { [0] = "spider", [2] = "mantis", [3] = "stag" }, nature = "mower",
        layout = { "l.l.l", ".l.l.", "l...l", ".....", "..l.." },
    },
}

-- Where wild bugs start on a hunt board: the prize first, then its friends; guards and the nest come closer.
Park.wildSpots = {
    prize = { { 3, 5 }, { 2, 5 }, { 4, 5 }, { 3, 4 } },
    common = { { 2, 4 }, { 4, 4 }, { 1, 5 }, { 5, 5 }, { 2, 5 }, { 4, 5 }, { 3, 4 }, { 1, 4 }, { 5, 4 } },
    guard = { { 3, 3 }, { 2, 3 }, { 4, 3 } },
}

-- The Buzz (GDD §8.6.5): every hunt stirs the zone up a little more; a duel calms it down again.
Park.buzz = {
    [0] = { name = "Quiet", text = "Wild bugs start 1 tick slower: they haven't noticed you." },
    [1] = { name = "Noticed", text = "Wild bugs are on their guard." },
    [2] = { name = "Alert", text = "A guard joins every group." },
    [3] = { name = "Agitated", text = "A guard joins, and every wild bug bites 1 harder." },
    [4] = { name = "Swarming", text = "The nest joins in, every wild bug bites 1 harder and starts 1 tick sooner." },
}
Park.BUZZ_MAX = 4

-- Nature's moves: the hunt's version of a rival kid's signature move (shown in advance, own timer).
Park.natures = {
    dog = { name = "A dog!", icon = "icon_foot", sig = { kind = "dog", name = "Dog!", timer = 5,
            text = "A dog runs along the busiest row (shown in advance): everyone in it is pushed 1 tile up." } },
    bird = { name = "A blackbird", icon = "icon_eye", sig = { kind = "bird", name = "Blackbird's Shadow", timer = 4,
             text = "A shadow sweeps the ground: every bug freezes (+1 timer), flyers duck (+2)." } },
    shower = { name = "Rain", icon = "fx_drop", sig = { kind = "shower", name = "Rain Shower", timer = 4,
               text = "Two new puddles (shown in advance). A bug caught in one is Soaked." } },
    mower = { name = "The lawnmower", icon = "icon_hourglass", sig = { kind = "mower", name = "The Lawnmower", timer = 11, once = true,
              text = "The park keeper is mowing his way over here. When he arrives, the hunt is over." } },
}

-- Events (GDD §8.9): something happening in the park during free time. Always optional.
Park.events = {
    swap = { name = "A kid wants to swap", text = "\"I'll swap you!\" A bug of theirs for one of yours. No marbles change hands." },
    shower = { name = "A sudden shower!", text = "Rain! The bugs dive for cover (the Buzz drops by 1) and the next duel's boards get extra puddles." },
    dog = { name = "A dog runs through!", text = "A big friendly dog charges through every bush in the zone. Every hunt spot shows a new group." },
    ball = { name = "A lost ball", text = "A little kid lost their ball under the bushes. Send one of your bugs to look? It comes back worn out (it naps), and the kid gives you a card." },
}
Park.EVENT_POOL = { "swap", "shower", "dog", "ball" }
Park.SWAP_POOL = { "wasp", "spider", "cricket", "redant", "stag", "mantis", "pillbug" }
Park.BALL_CARDS = { "leaf", "pebble", "blow", "tap", "sugar", "juice" }

return Park
