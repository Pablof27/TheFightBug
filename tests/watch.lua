-- Watch one bot fight, board by board.   lua tests/watch.lua [encounter 1-3] [seed] [random|greedy]
local B = require("tests.botlib")
local Encounters = require("data.encounters")

local enc = Encounters[tonumber(arg[1]) or 1]
local seed = tonumber(arg[2]) or 1
local policy = arg[3] or "greedy"
local s = B.setup(enc, seed)
print(enc.name .. "\n" .. B.dump(s) .. "\n")
local steps = 0
while not s.winner and steps < 60 do
    local a = B.choose(s, policy)
    print("> " .. B.describe(s, a))
    B.apply(s, a)
    print(B.dump(s) .. "\n")
    steps = steps + 1
end
print("winner:", s.winner, s.why, "after", s.tick, "ticks")
