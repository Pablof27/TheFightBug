-- Movement rules and path finding. Walkers are blocked by terrain and by ENEMY bugs but squeeze past their friends
-- (they just can't stop on a friend). Flyers and jumpers only care about where they land. Nobody ever stands on a
-- pebble, a knot or a stick: flyers and jumpers pass over them, walkers go around, a pushed bug bumps into them.
-- Every tie is broken the same visible way (GDD §5.4): shortest path, then diagonal progress, then trails,
-- then reading order; and the axis with more distance left to go is walked first (vertical on ties).

local Grid = require("sim.grid")
local State = require("sim.state")

local Path = {}

--- Can `bug` stand on (x, y)?  o.pushed: a pushed walker may be dropped into a puddle.  o.pass: friends don't block.
function Path.canEnter(s, bug, x, y, o)
    o = o or {}
    local c = Grid.cell(s, x, y)
    if not c or c.void or c.block then return false end
    if c.puddle and c.cover ~= "leaf" and bug.mtype ~= "fly" and not o.pushed then return false end
    local other = State.at(s, x, y)
    if other and other ~= bug and not (o.pass and other.side == bug.side) then return false end
    return true
end

local PASS = { pass = true }

--- Landing rule for flyers and jumpers (they pass over anything but must come down on a free, open tile).
function Path.canLand(s, bug, x, y)
    local c = Grid.cell(s, x, y)
    if not c or c.void or c.block then return false end
    if bug.mtype == "jump" and c.puddle and c.cover ~= "leaf" then return false end
    local o = State.at(s, x, y)
    if o and o ~= bug then return false end
    return true
end

--- Tiles it may move this activation: move + 1 on its own colony's trail, - 1 while carrying (never below 1).
function Path.allowance(s, bug)
    local n = bug.move
    if n <= 0 then return 0 end
    if bug.traits.trail then
        local c = Grid.cell(s, bug.x, bug.y)
        if c and c.trail and c.trail.side == bug.side then n = n + 1 end
    end
    if bug.carrying then n = n - 1 end
    if n < 1 then n = 1 end
    return n
end

local function flood(s, bug, sx, sy)
    local start = Grid.key(sx, sy)
    local dist = { [start] = 0 }
    local q, head = { { sx, sy } }, 1
    local own = Grid.key(bug.x, bug.y)
    while head <= #q do
        local cur = q[head]; head = head + 1
        local d = dist[Grid.key(cur[1], cur[2])]
        for _, dir in ipairs(Grid.DIRS) do
            local nx, ny = cur[1] + dir.dx, cur[2] + dir.dy
            local k = Grid.key(nx, ny)
            if dist[k] == nil and (k == own or Path.canEnter(s, bug, nx, ny, PASS)) then
                dist[k] = d + 1
                q[#q + 1] = { nx, ny }
            end
        end
    end
    return dist
end

--- Steps from the bug's tile to every tile it can pass through to. dist[key] = steps (friends' tiles included).
function Path.bfs(s, bug) return flood(s, bug, bug.x, bug.y) end

--- Can the bug end its move on (x, y)?  (its own tile counts)
function Path.canStop(s, bug, x, y)
    return (x == bug.x and y == bug.y) or Path.canEnter(s, bug, x, y)
end

local function trailAt(s, bug, x, y)
    local c = Grid.cell(s, x, y)
    return (bug.traits.trail and c and c.trail and c.trail.side == bug.side) and 1 or 0
end

-- greedy descent along a distance field towards its source (tx, ty)
local function descend(s, bug, field, tx, ty, limit)
    local path = {}
    local cx, cy = bug.x, bug.y
    for _ = 1, limit do
        local cd = field[Grid.key(cx, cy)]
        if not cd or cd == 0 then break end
        local rx, ry = tx - cx, ty - cy
        local wantH = math.abs(rx) > math.abs(ry)
        local best, bestScore
        for i, dir in ipairs(Grid.DIRS) do
            local nx, ny = cx + dir.dx, cy + dir.dy
            local k = Grid.key(nx, ny)
            if field[k] == cd - 1 and Path.canEnter(s, bug, nx, ny, PASS) then
                local score = i - 100 * trailAt(s, bug, nx, ny)
                if (dir.dx ~= 0) == wantH then score = score - 10 end
                if not bestScore or score < bestScore then best, bestScore = { x = nx, y = ny }, score end
            end
        end
        if not best then break end
        path[#path + 1] = best
        cx, cy = best.x, best.y
    end
    return path
end

--- The walk towards `goal`: it picks the best tile it can STOP on within `limit` steps (closest to the goal, then
--- diagonal progress, then fewest steps, then trails, then reading order) and walks there. Returns path, reachedGoal.
function Path.walk(s, bug, goal, limit)
    local sk = Grid.key(bug.x, bug.y)
    local back = flood(s, bug, goal.x, goal.y)
    if back[sk] == nil then return {}, false end
    local fwd = flood(s, bug, bug.x, bug.y)
    local best
    for y = s.h, 1, -1 do
        for x = 1, s.w do
            local k = Grid.key(x, y)
            local f, b = fwd[k], back[k]
            if f and b and f <= limit and Path.canStop(s, bug, x, y) then
                local c = { x = x, y = y, b = b, f = f, cheb = math.max(math.abs(goal.x - x), math.abs(goal.y - y)), trail = trailAt(s, bug, x, y) }
                local win = not best
                if best then
                    if c.b ~= best.b then win = c.b < best.b
                    elseif c.cheb ~= best.cheb then win = c.cheb < best.cheb
                    elseif c.f ~= best.f then win = c.f < best.f
                    elseif c.trail ~= best.trail then win = c.trail > best.trail end
                end
                if win then best = c end
            end
        end
    end
    if not best or (best.x == bug.x and best.y == bug.y) then
        return {}, (bug.x == goal.x and bug.y == goal.y)
    end
    local path = descend(s, bug, flood(s, bug, best.x, best.y), best.x, best.y, limit)
    return path, (best.x == goal.x and best.y == goal.y)
end

--- Nothing reachable? Walk as close as possible to (tx, ty) instead.
function Path.approach(s, bug, tx, ty, limit, dist)
    dist = dist or Path.bfs(s, bug)
    local best
    for y = s.h, 1, -1 do
        for x = 1, s.w do
            local d = dist[Grid.key(x, y)]
            if d and Path.canStop(s, bug, x, y) then
                local m = Grid.manhattan(x, y, tx, ty)
                if not best or m < best.m or (m == best.m and d < best.d) then best = { x = x, y = y, m = m, d = d } end
            end
        end
    end
    if not best or (best.x == bug.x and best.y == bug.y) then return {}, false end
    return Path.walk(s, bug, best, limit)
end

--- Staircase of up to `limit` tiles from (sx, sy) towards (gx, gy): the axis with more distance left first, vertical on ties.
function Path.staircase(sx, sy, gx, gy, limit)
    local path = {}
    local cx, cy = sx, sy
    for _ = 1, limit do
        local rx, ry = gx - cx, gy - cy
        if rx == 0 and ry == 0 then break end
        local stepH
        if rx == 0 then stepH = false elseif ry == 0 then stepH = true else stepH = math.abs(rx) > math.abs(ry) end
        if stepH then cx = cx + (rx > 0 and 1 or -1) else cy = cy + (ry > 0 and 1 or -1) end
        path[#path + 1] = { x = cx, y = cy }
    end
    return path
end

--- Flight path: passes over anything but has to land on a free tile, so it is cut back to the last one.
function Path.fly(s, bug, gx, gy, limit)
    local path = Path.staircase(bug.x, bug.y, gx, gy, limit)
    while #path > 0 and not Path.canLand(s, bug, path[#path].x, path[#path].y) do path[#path] = nil end
    return path
end

--- A jump is a single hop to the farthest legal landing along the way.
function Path.jump(s, bug, gx, gy, limit)
    local path = Path.staircase(bug.x, bug.y, gx, gy, limit)
    while #path > 0 and not Path.canLand(s, bug, path[#path].x, path[#path].y) do path[#path] = nil end
    if #path == 0 then return {} end
    return { path[#path] }
end

local function blocksSpray(c)
    return c == nil or c.void or c.block == "pebble" or c.block == "knot"
end

--- Can this bug, standing on (x, y), hit `enemy`? Adjacent, or in a straight line 2 away for acid sprayers.
function Path.inReach(s, bug, x, y, enemy)
    local d = Grid.manhattan(x, y, enemy.x, enemy.y)
    if d == 1 then return true end
    if bug.reach >= 2 and d == 2 and (x == enemy.x or y == enemy.y) then
        local mx, my = (x + enemy.x) / 2, (y + enemy.y) / 2
        return not blocksSpray(Grid.cell(s, mx, my))
    end
    return false
end

--- Tiles from where this bug could hit `enemy` (and that it could stand on).
function Path.attackPositions(s, bug, enemy)
    local out = {}
    local function add(x, y)
        local ok
        if x == bug.x and y == bug.y then ok = true
        elseif bug.mtype == "walk" then ok = Path.canEnter(s, bug, x, y)
        else ok = Path.canLand(s, bug, x, y) end
        if ok then out[#out + 1] = { x = x, y = y } end
    end
    for _, d in ipairs(Grid.DIRS) do
        add(enemy.x + d.dx, enemy.y + d.dy)
        if bug.reach >= 2 then
            local mid = Grid.cell(s, enemy.x + d.dx, enemy.y + d.dy)
            if not blocksSpray(mid) then add(enemy.x + 2 * d.dx, enemy.y + 2 * d.dy) end
        end
    end
    return out
end

return Path
