-- Rival kids (GDD §9). They don't play cards: each has a team and ONE signature move on its own timer, shown in advance.

return {
    bully = {
        name = "The Bully", short = "Loud, aggressive, cheats.",
        sig = { kind = "stomp", name = "Stomp", timer = 6,
                text = "The ground shakes in a 3x3 area. Bugs there get +2 timer. He aims where the most of YOUR bugs are." },
        line = { start = "Gimme your bugs, shrimp!", win = "Told you!", lose = "No fair! You cheated!" },
        portrait = "bully",
    },
    antgirl = {
        name = "Ant Farm Girl", short = "Patient and organised.",
        sig = { kind = "farm", name = "Open the Farm", timer = 5,
                text = "2 more ants pour out into her home rows." },
        line = { start = "My ants never sleep.", win = "Teamwork!", lose = "...I'll need a bigger farm." },
        portrait = "antgirl",
        cap = 12,
    },
    rich = {
        name = "The Rich Kid", short = "Show-off. Everything came from the pet shop.",
        sig = { kind = "buy", name = "Buy Another", timer = 8,
                text = "A new beetle joins his team." },
        shopping = { "hercules", "hercules" },
        line = { start = "My dad paid a LOT for these.", win = "Money wins.", lose = "Daddy will hear about this!" },
        portrait = "rich",
    },
}
