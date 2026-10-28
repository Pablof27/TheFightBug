-- Instincts (GDD §5.4): every species decides Target -> Movement -> Action by one fixed rule.
-- Instincts are PURE: (state, bug) -> intent. They never change the state, so the live preview can call them freely.
--
-- intent = {
--   id, kind  = "idle" | "move" | "attack" | "eat" | "pickup" | "deliver" | "rest" | "chirp" | "ready" | "getup",
--   mode      = "walk" | "fly" | "jump" | "charge",
--   path      = { {x, y}, ... }  tiles it will move through this activation (already cut to its allowance),
--   from, to  = {x, y},
--   target    = { kind = "bug" | "food" | "home" | "cover", id|x|y },
--   action    = { kind = "bite" | "ram" | "strike" | "eat" | "sip" | "pickup" | "deliver" | "rest" | "chirp", ... },
-- }

local Grid = require("sim.grid")
local State = require("sim.state")
local Q = require("sim.query")
local Path = require("sim.path")

local I = {}

local function newIntent(bug)
    return { id = bug.id, kind = "idle", mode = "walk", path = {}, from = { x = bug.x, y = bug.y }, to = { x = bug.x, y = bug.y } }
end

local function setPath(it, path, mode)
    it.path = path
    if mode then it.mode = mode end
    if #path > 0 then it.to = { x = path[#path].x, y = path[#path].y } end
end

local function better(a, b)   -- a, b = { enemy, d } : distance, then lowest stamina, then reading order
    if not b then return true end
    if a.d ~= b.d then return a.d < b.d end
    if a.enemy.hp ~= b.enemy.hp then return a.enemy.hp < b.enemy.hp end
    return Grid.reading(a.enemy.x, a.enemy.y) < Grid.reading(b.enemy.x, b.enemy.y)
end

-- nearest visible enemy that a walker can reach: { enemy, pos = tile to attack from, d = steps }
local function nearestEnemyWalk(s, bug, dist)
    local best
    for _, e in ipairs(Q.targets(s, bug)) do
        local pos, d
        for _, p in ipairs(Path.attackPositions(s, bug, e)) do
            local pd = dist[Grid.key(p.x, p.y)]
            if pd and (not d or pd < d or (pd == d and Grid.reading(p.x, p.y) < Grid.reading(pos.x, pos.y))) then pos, d = p, pd end
        end
        if pos then
            local cand = { enemy = e, pos = pos, d = d }
            if better(cand, best) then best = cand end
        end
    end
    return best
end

local function nearestEnemyManhattan(s, bug)
    local best
    for _, e in ipairs(Q.targets(s, bug)) do
        local m = Grid.manhattan(bug.x, bug.y, e.x, e.y)
        if not best or m < best.m or (m == best.m and Grid.reading(e.x, e.y) < Grid.reading(best.e.x, best.e.y)) then best = { e = e, m = m } end
    end
    return best and best.e
end

-- walk to the nearest enemy and bite it
local function hunt(s, bug, it, dist, allow)
    local best = nearestEnemyWalk(s, bug, dist)
    if best then
        it.target = { kind = "bug", id = best.enemy.id }
        setPath(it, Path.walk(s, bug, best.pos, allow), "walk")
        if bug.bite > 0 and Path.inReach(s, bug, it.to.x, it.to.y, best.enemy) then
            it.kind = "attack"
            it.action = { kind = "bite", target = best.enemy.id, dmg = bug.bite }
        else
            it.kind = (#it.path > 0) and "move" or "idle"
        end
        return it
    end
    local e = nearestEnemyManhattan(s, bug)
    if e then
        it.target = { kind = "bug", id = e.id }
        setPath(it, (Path.approach(s, bug, e.x, e.y, allow, dist)), "walk")
        it.kind = (#it.path > 0) and "move" or "idle"
    end
    return it
end

-- ───────────────────────── Forager (ants) ─────────────────────────
function I.forager(s, bug)
    local it = newIntent(bug)
    local dist = Path.bfs(s, bug)
    local allow = Path.allowance(s, bug)

    if bug.carrying then
        local best
        for _, t in ipairs(Q.homeTiles(s, bug.side)) do
            local d = dist[Grid.key(t.x, t.y)]
            if d and Path.canStop(s, bug, t.x, t.y) and (not best or d < best.d) then best = { x = t.x, y = t.y, d = d } end
        end
        if best then
            it.target = { kind = "home", x = best.x, y = best.y }
            setPath(it, Path.walk(s, bug, best, allow), "walk")
            if it.to.x == best.x and it.to.y == best.y then
                it.kind = "deliver"
                it.action = { kind = "deliver" }
            else
                it.kind = "move"
            end
        end
        return it
    end

    local bestF
    for _, f in ipairs(Q.foods(s)) do
        if bug.likes[f.kind] then
            local d = dist[Grid.key(f.x, f.y)]
            if d and Path.canStop(s, bug, f.x, f.y) and (not bestF or d < bestF.d) then bestF = { x = f.x, y = f.y, d = d, kind = f.kind } end
        end
    end
    if bestF then
        it.target = { kind = "food", x = bestF.x, y = bestF.y, food = bestF.kind }
        setPath(it, Path.walk(s, bug, bestF, allow), "walk")
        if it.to.x == bestF.x and it.to.y == bestF.y then
            if bestF.kind == "loot" then
                it.kind = "pickup"
                it.action = { kind = "pickup" }
            else
                it.kind = "eat"
                it.action = { kind = bestF.kind == "juice" and "sip" or "eat" }
            end
        else
            it.kind = "move"
        end
        return it
    end
    return hunt(s, bug, it, dist, allow)
end

-- ───────────────────────── Charger (beetles) ─────────────────────────
function I.charger(s, bug)
    local it = newIntent(bug)
    it.mode = "charge"
    local allow = Path.allowance(s, bug)
    local best
    for _, d in ipairs(Grid.DIRS) do
        local x, y, n = bug.x, bug.y, 0
        while true do
            x, y, n = x + d.dx, y + d.dy, n + 1
            local c = Grid.cell(s, x, y)
            if not c or c.void then break end
            local o = State.at(s, x, y)
            if o then
                if o.side ~= bug.side and not Q.isHidden(s, o) and (not (s.rule and s.rule.attackMode == "push") or o.weight <= bug.weight) then
                    local cand = { enemy = o, d = n, dir = d }
                    if better(cand, best) then best = cand end
                end
                break
            end
            if not Path.canEnter(s, bug, x, y) then break end
        end
    end
    if best then
        local steps = math.min(best.d - 1, allow)
        local path = {}
        for i = 1, steps do path[i] = { x = bug.x + best.dir.dx * i, y = bug.y + best.dir.dy * i } end
        setPath(it, path, "charge")
        it.target = { kind = "bug", id = best.enemy.id }
        if steps == best.d - 1 then
            it.kind = "attack"
            it.action = { kind = "ram", target = best.enemy.id, dx = best.dir.dx, dy = best.dir.dy, dmg = bug.bite }
        else
            it.kind = "move"
        end
        return it
    end
    -- nobody in line: line up with the nearest enemy (sidestep into its column), or march forward if it already is
    local e = nearestEnemyManhattan(s, bug)
    local function march(dx, dy, n)
        local path, x, y = {}, bug.x, bug.y
        for _ = 1, n do
            if not Path.canEnter(s, bug, x + dx, y + dy) then break end
            x, y = x + dx, y + dy
            path[#path + 1] = { x = x, y = y }
        end
        return path
    end
    local path = {}
    if e then
        it.target = { kind = "bug", id = e.id }
        local sx, sy = (e.x > bug.x) and 1 or -1, (e.y > bug.y) and 1 or -1
        if e.x ~= bug.x then path = march(sx, 0, math.min(allow, math.abs(e.x - bug.x))) end
        if #path == 0 and e.y ~= bug.y then path = march(0, sy, allow) end
        if #path == 0 then path = march(sx, 0, 1) end
        if #path == 0 then path = march(-sx, 0, 1) end
    else
        path = march(0, Grid.forward(bug.side), allow)
    end
    setPath(it, path, "charge")
    it.kind = (#path > 0) and "move" or "idle"
    return it
end

-- ───────────────────────── Ambusher (mantis) ─────────────────────────
function I.ambusher(s, bug)
    local it = newIntent(bug)
    local adj = Q.adjacentEnemies(s, bug)
    if #adj > 0 then
        local t = Q.weakest(adj)
        it.kind = "attack"
        it.target = { kind = "bug", id = t.id }
        it.action = { kind = "strike", target = t.id, dmg = bug.bite }
    else
        it.kind = "ready"
    end
    return it
end

-- ───────────────────────── Hider (pill bug) ─────────────────────────
local function isCover(c)
    return c ~= nil and not c.void and (c.cover ~= nil or c.light == "shade") and not (c.puddle and c.cover ~= "leaf")
end

function I.hider(s, bug)
    local it = newIntent(bug)
    if isCover(Grid.cell(s, bug.x, bug.y)) then
        it.kind = "rest"
        it.action = { kind = "rest" }
        return it
    end
    local dist = Path.bfs(s, bug)
    local best
    for y = s.h, 1, -1 do
        for x = 1, s.w do
            if isCover(s.cells[Grid.key(x, y)]) then
                local d = dist[Grid.key(x, y)]
                if d and Path.canStop(s, bug, x, y) and (not best or d < best.d) then best = { x = x, y = y, d = d } end
            end
        end
    end
    if best then
        it.target = { kind = "cover", x = best.x, y = best.y }
        setPath(it, Path.walk(s, bug, best, Path.allowance(s, bug)), "walk")
        it.kind = (#it.path > 0) and "move" or "idle"
        if it.to.x == best.x and it.to.y == best.y then it.kind = "rest"; it.action = { kind = "rest" } end
    else
        it.kind = "rest"
        it.action = { kind = "rest" }
    end
    return it
end

-- ───────────────────────── Pouncer (jumping spider) ─────────────────────────
function I.pouncer(s, bug)
    local it = newIntent(bug)
    it.mode = "jump"
    local cands = {}
    for _, e in ipairs(Q.visibleEnemies(s, bug)) do
        local land
        for _, p in ipairs(Path.attackPositions(s, bug, e)) do
            local m = Grid.manhattan(bug.x, bug.y, p.x, p.y)
            if m <= bug.move and (not land or m < land.m or (m == land.m and Grid.reading(p.x, p.y) < Grid.reading(land.x, land.y))) then
                land = { x = p.x, y = p.y, m = m }
            end
        end
        if land then cands[#cands + 1] = { e = e, land = land } end
    end
    if #cands > 0 then
        table.sort(cands, function(a, b)
            if a.e.hp ~= b.e.hp then return a.e.hp < b.e.hp end
            local da, db = Grid.manhattan(bug.x, bug.y, a.e.x, a.e.y), Grid.manhattan(bug.x, bug.y, b.e.x, b.e.y)
            if da ~= db then return da < db end
            return Grid.reading(a.e.x, a.e.y) < Grid.reading(b.e.x, b.e.y)
        end)
        local c = cands[1]
        it.target = { kind = "bug", id = c.e.id }
        if c.land.x ~= bug.x or c.land.y ~= bug.y then setPath(it, { { x = c.land.x, y = c.land.y } }, "jump") end
        it.kind = "attack"
        it.action = { kind = "bite", target = c.e.id, dmg = bug.bite }
        return it
    end
    local e = nearestEnemyManhattan(s, bug)
    if e then
        it.target = { kind = "bug", id = e.id }
        setPath(it, Path.jump(s, bug, e.x, e.y, bug.move), "jump")
        it.kind = (#it.path > 0) and "move" or "idle"
    end
    return it
end

-- ───────────────────────── Chorus (cricket) ─────────────────────────
function I.chorus(s, bug)
    local it = newIntent(bug)
    local dist = Path.bfs(s, bug)
    local allow = Path.allowance(s, bug)
    local allies = {}
    for _, b in ipairs(s.bugs) do if b.side == bug.side and b ~= bug then allies[#allies + 1] = b end end

    local best
    for _, a in ipairs(allies) do
        local g = 0
        for _, o in ipairs(allies) do
            if o ~= a and Grid.manhattan(a.x, a.y, o.x, o.y) <= 2 then g = g + 1 end
        end
        local d = Grid.manhattan(bug.x, bug.y, a.x, a.y)
        if not best or g > best.g or (g == best.g and (d < best.d or (d == best.d and Grid.reading(a.x, a.y) < Grid.reading(best.a.x, best.a.y)))) then
            best = { a = a, g = g, d = d }
        end
    end
    if best then it.target = { kind = "bug", id = best.a.id } end

    local adj = Q.adjacentEnemies(s, bug)
    if #adj > 0 then
        -- hop away from whoever is next to us
        local enemies = Q.visibleEnemies(s, bug)
        local bestTile
        for y = s.h, 1, -1 do
            for x = 1, s.w do
                local d = dist[Grid.key(x, y)]
                if d and d > 0 and d <= allow and Path.canStop(s, bug, x, y) then
                    local far = 99
                    for _, e in ipairs(enemies) do far = math.min(far, Grid.manhattan(x, y, e.x, e.y)) end
                    local near = best and Grid.manhattan(x, y, best.a.x, best.a.y) or 0
                    if not bestTile or far > bestTile.far or (far == bestTile.far and near < bestTile.near) then bestTile = { x = x, y = y, far = far, near = near } end
                end
            end
        end
        if bestTile and bestTile.far > 1 then setPath(it, Path.walk(s, bug, bestTile, allow), "walk") end
    elseif best and best.d > 2 then
        local goal
        for y = s.h, 1, -1 do
            for x = 1, s.w do
                local d = dist[Grid.key(x, y)]
                if d and Grid.manhattan(x, y, best.a.x, best.a.y) <= 2 and Path.canStop(s, bug, x, y) and (not goal or d < goal.d) then goal = { x = x, y = y, d = d } end
            end
        end
        if goal then setPath(it, Path.walk(s, bug, goal, allow), "walk") end
    end
    it.kind = "chirp"
    it.action = { kind = "chirp" }
    return it
end

-- ───────────────────────── Sweet tooth (wasp) ─────────────────────────
function I.sweet(s, bug)
    local it = newIntent(bug)
    it.mode = "fly"
    local allow = Path.allowance(s, bug)
    local bestF
    for _, f in ipairs(Q.foods(s)) do
        if bug.likes[f.kind] and ((f.x == bug.x and f.y == bug.y) or Path.canLand(s, bug, f.x, f.y)) then
            local m = Grid.manhattan(bug.x, bug.y, f.x, f.y)
            if not bestF or m < bestF.m then bestF = { x = f.x, y = f.y, m = m, kind = f.kind } end
        end
    end
    if bestF then
        it.target = { kind = "food", x = bestF.x, y = bestF.y, food = bestF.kind }
        setPath(it, Path.fly(s, bug, bestF.x, bestF.y, allow), "fly")
        if it.to.x == bestF.x and it.to.y == bestF.y then
            it.kind = "eat"
            it.action = { kind = bestF.kind == "juice" and "sip" or "eat" }
        else
            it.kind = "move"
        end
        return it
    end
    local best
    for _, e in ipairs(Q.visibleEnemies(s, bug)) do
        for _, p in ipairs(Path.attackPositions(s, bug, e)) do
            local m = Grid.manhattan(bug.x, bug.y, p.x, p.y)
            local cand = { e = e, p = p, m = m }
            local win = not best
            if best then
                if cand.m ~= best.m then win = cand.m < best.m
                elseif cand.e.hp ~= best.e.hp then win = cand.e.hp < best.e.hp
                elseif cand.e ~= best.e then win = Grid.reading(cand.e.x, cand.e.y) < Grid.reading(best.e.x, best.e.y)
                else win = Grid.reading(cand.p.x, cand.p.y) < Grid.reading(best.p.x, best.p.y) end
            end
            if win then best = cand end
        end
    end
    if best then
        it.target = { kind = "bug", id = best.e.id }
        setPath(it, Path.fly(s, bug, best.p.x, best.p.y, allow), "fly")
        if Path.inReach(s, bug, it.to.x, it.to.y, best.e) then
            it.kind = "attack"
            it.action = { kind = "bite", target = best.e.id, dmg = bug.bite }
        else
            it.kind = (#it.path > 0) and "move" or "idle"
        end
    end
    return it
end

--- What would this bug do if it acted right now?
function I.decide(s, bug)
    if bug.flipped then
        local it = newIntent(bug)
        it.kind = "getup"
        return it
    end
    local it = I[bug.instinct](s, bug)
    it.from = { x = bug.x, y = bug.y }
    return it
end

return I
