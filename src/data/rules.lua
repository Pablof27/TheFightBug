-- Rules of the Game, as content (GDD §5.11). Mechanics live in sim/rules.lua and sim/resolver.lua.

return {
    lbs = {
        name = "Last Bug Standing",
        short = "Make every rival bug scurry off.",
        long = "Bugs that run out of stamina scurry off the board. Win when the rival has none left before the Sun clock runs out.",
        favours = "Fighters",
    },
    crumbs = {
        name = "Crumb Race",
        short = "Be first to carry 5 crumbs home.",
        long = "Big crumbs appear in the middle of the lawn (the next one is always shown in advance). Ants carry them to their own home rows instead of eating them. Bugs that scurry off drop what they carry.",
        goal = 5,
        favours = "Ants and carriers",
    },
    zumo = {
        name = "Mushi-Zumo",
        short = "Push every rival bug off the stump.",
        long = "It's sumo: nobody gets hurt. Every bite, sting and ram is a SHOVE that flings the target as many tiles as the shover is heavy (Light 1, Medium 2, Heavy 3). A bug can only shove one of the same weight or lighter, and the edges are open. Win when the rival has nobody left on the stump.",
        attackMode = "push",
        favours = "Heavy beetles",
    },
    showdown = {
        name = "Showdown",
        short = "Last game, for real! Every hit moves a marble.",
        long = "Round 3 of every duel. There is no bet: every bite, sting, ram or strike that lands moves 1 marble from the owner of the bug that was hit to the owner of the attacker (a curled pill bug's NOPE! saves it). The game ends when one side has no bugs left, when someone is broke, or when the Sun clock runs out. Then the duel is over.",
        favours = "Swarms and fast biters",
    },
    jar = {
        name = "Jar Trap",
        short = "Get wild bugs into your jar.",
        long = "Your jar lies on its side on one of your tiles. A wild bug that walks into it, lands on it or is pushed into it is caught. Knocked-out wild bugs run away. Close the lid whenever you like: you keep what's inside. No marbles are at stake.",
        favours = "Lures and nudges",
    },
}
