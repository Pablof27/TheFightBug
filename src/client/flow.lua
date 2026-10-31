-- Scene routing for a day at the park: every phase of the run (sim/run.lua) has the scene that shows it. Moving on always
-- goes through Flow.go, which saves first, so whatever the player sees is what a reload will show.

local Saves = require("client.saves")

local Flow = {}

local SCENE = { prologue = "park", zone = "park", free = "park", reward = "park", duel = "duel", over = "ending" }

function Flow.sceneFor(run) return SCENE[run.phase] or "park" end

--- Save the run and show the scene of its phase. params go to that scene.
function Flow.go(app, run, params)
    params = params or {}
    params.run = run
    app.run = run
    if run.phase == "over" then
        local won = run.result and run.result.won or false
        params.won = won
        Saves.finish(run, won)
    else
        Saves.store(run)
    end
    app.switch(Flow.sceneFor(run), params)
end

return Flow
