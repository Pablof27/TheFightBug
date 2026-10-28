-- Rules of the Game, as content (GDD §5.11). Mechanics live in sim/rules.lua and sim/resolver.lua.

return {
    lbs = {
        name = "Last Bug Standing",
        short = "Make every rival bug scurry off.",
        long = "Bugs that run out of stamina scurry off the board. Win when the rival has none left. If the Sun clock runs out, the side with more total stamina wins.",
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
        openEdges = true,
        favours = "Heavy beetles",
    },
}
