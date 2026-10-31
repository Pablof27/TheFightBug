-- Rival kids (GDD §9). They don't play cards: each has a team and ONE signature move on its own timer, shown in advance.
-- In the run (GDD §8.5) every kid also has:
--   wealth   where their marble stack sits in the act's range (1 low .. 4 top, data/park.lua); Gang leaders use the act's leader stack
--   rules    { favourite, second favourite }: round 1, and their pick after losing a round ("random": a new one every round)
--   house    the house rule they play by when they are a Gang leader (sim/duel.lua)
--   roster   the bugs they own, in the order they send them out; `field` of them that aren't napping play each round
--   pockets  what they offer when you break them (cards or species), for some of their marbles back
--   leaderOnly  never shows up as an ordinary kid
-- Timers read one lower than in the GDD because a timer at 0 acts on the NEXT tick (demo rule DD-32).

return {
    bully = {
        name = "The Bully", short = "Loud, aggressive, cheats.", portrait = "bully",
        sig = { kind = "stomp", name = "Stomp", timer = 5,
                text = "The ground shakes in a 3x3 area. Bugs there get +2 timer. He aims where the most of YOUR bugs are." },
        line = { start = "Gimme your bugs, shrimp!", win = "Told you!", lose = "No fair! You cheated!" },
        wealth = 2, rules = { "lbs", "zumo" },
        house = { id = "nolures", name = "No Lures in my sandbox!", text = "You can't play Lure cards." },
        roster = { "wasp", "stag", "wasp", "wasp", "stag", "wasp" }, field = 4,
        pockets = { "shove", "stick", "wasp" },
    },
    antgirl = {
        name = "Ant Farm Girl", short = "Patient and organised.", portrait = "antgirl",
        sig = { kind = "farm", name = "Open the Farm", timer = 4,
                text = "2 more ants pour out into her home rows." },
        line = { start = "My ants never sleep.", win = "Teamwork!", lose = "...I'll need a bigger farm." },
        cap = 12,
        wealth = 2, rules = { "crumbs", "lbs" },
        house = { id = "noflick", name = "Don't you dare flick my ants!", text = "Your Nudge cards can't move her ants." },
        roster = { "ant", "ant", "redant", "ant", "redant", "ant", "ant" }, field = 5,
        pockets = { "sugar", "juice", "redant" },
    },
    rich = {
        name = "The Rich Kid", short = "Show-off. Everything came from the pet shop.", portrait = "rich",
        sig = { kind = "buy", name = "Buy Another", timer = 7,
                text = "A new beetle joins his team." },
        shopping = { "hercules", "hercules" },
        line = { start = "My dad paid a LOT for these.", win = "Money wins.", lose = "Daddy will hear about this!" },
        wealth = 4, rules = { "zumo", "lbs" },
        house = { id = "rebuy", name = "Daddy will buy me another one.", text = "A new Hercules beetle joins his team after every round." },
        roster = { "hercules", "stag", "hercules" }, field = 1,
        pockets = { "juice", "shove", "hercules" },
    },
    sibling = {
        name = "Little Sibling", short = "Chaotic and cute. Bites.", portrait = "sibling",
        sig = { kind = "tantrum", name = "Tantrum", timer = 3,
                text = "Throws a fit: one bug (shown in advance) is flung 1 tile." },
        line = { start = "Can I play? Can I? CAN I?", win = "I WON! I WON!", lose = "WAAAAH! MOOOOM!" },
        wealth = 1, rules = { "random" },
        roster = { "ant", "cricket", "pillbug", "wasp", "ant", "cricket" }, field = 4,
        pockets = { "crumb", "leaf", "cricket" },
    },
    nerd = {
        name = "Science Nerd", short = "Precise. Knows every fact.", portrait = "nerd",
        sig = { kind = "notes", name = "Field Notes", timer = 3,
                text = "She studies your next mover: your bug that would act soonest gets +2 timer." },
        line = { start = "Did you know a mantis can turn its head?", win = "As predicted.", lose = "Fascinating. Again?" },
        wealth = 3, rules = { "lbs", "crumbs" },
        house = { id = "nohide", name = "I've read all about your bugs.", text = "Hidden doesn't fool her bugs." },
        roster = { "spider", "mantis", "redant", "spider", "cricket", "redant" }, field = 4,
        pockets = { "tap", "leaf", "spider" },
    },
    twins = {
        name = "The Twins", short = "Two kids, one jar, zero manners.", portrait = "twins", plural = true,
        sig = { kind = "tagteam", name = "Tag Team", timer = 4,
                text = "Their two slowest bugs get -1 timer." },
        line = { start = "Two against one!", win = "TWIN POWER!", lose = "It was HIS fault!" },
        wealth = 3, rules = { "crumbs", "zumo" },
        house = { id = "double", name = "Two against one!", text = "They put 5 bugs on the board instead of 4." },
        roster = { "cricket", "ant", "stag", "ant", "cricket", "wasp", "ant" }, field = 4,
        pockets = { "blow", "sun", "cricket" },
    },
    champ = {
        name = "The Marble Champion", short = "The oldest kid in the park. Never lost a game of marbles.", portrait = "champ",
        sig = { kind = "shooter", name = "Shooter", timer = 4,
                text = "Shoots a marble along a row (shown in advance): the first bug it hits is pushed 1 tile and Dazed." },
        line = { start = "Knuckle down. We play for keeps.", win = "Good game, kid.", lose = "...Nobody beats me. Who ARE you?" },
        wealth = 4, rules = { "lbs", "zumo" }, leaderOnly = true,
        house = { id = "keeps", name = "We play for keeps.", text = "In every round, every hit also moves 1 marble, as in a Showdown." },
        roster = { "stag", "mantis", "wasp", "spider", "redant", "stag", "wasp" }, field = 4,
        pockets = { "shove", "tap", "mantis" },
    },
}
