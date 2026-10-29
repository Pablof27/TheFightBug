-- Rival kids (GDD §9). They don't play cards: each has a team and ONE signature move on its own timer, shown in advance.
-- bet: the marbles each side puts in the pot to fight this kid (demo rule DD-72). You can't challenge them without it.

return {
    bully = {
        name = "The Bully", short = "Loud, aggressive, cheats.", bet = 2,
        sig = { kind = "stomp", name = "Stomp", timer = 5,
                text = "The ground shakes in a 3x3 area. Bugs there get +2 timer. He aims where the most of YOUR bugs are." },
        line = { start = "Gimme your bugs, shrimp!", win = "Told you!", lose = "No fair! You cheated!" },
        portrait = "bully",
    },
    antgirl = {
        name = "Ant Farm Girl", short = "Patient and organised.", bet = 3,
        sig = { kind = "farm", name = "Open the Farm", timer = 4,
                text = "2 more ants pour out into her home rows." },
        line = { start = "My ants never sleep.", win = "Teamwork!", lose = "...I'll need a bigger farm." },
        portrait = "antgirl",
        cap = 12,
    },
    rich = {
        name = "The Rich Kid", short = "Show-off. Everything came from the pet shop.", bet = 5,
        sig = { kind = "buy", name = "Buy Another", timer = 7,
                text = "A new beetle joins his team." },
        shopping = { "hercules", "hercules" },
        line = { start = "My dad paid a LOT for these.", win = "Money wins.", lose = "Daddy will hear about this!" },
        portrait = "rich",
    },
}
