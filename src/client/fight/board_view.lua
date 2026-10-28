-- Draws the board: arena painting, terrain, props, bugs (depth sorted) and the highlights on top.
-- It reads the *view* state (what the player has seen so far), not the simulation, so animations can lag behind.

local Assets = require("client.assets")
local Paper = require("client.paper")
local Text = require("client.text")
local G = require("client.fight.geometry")
local Grid = require("sim.grid")

local BV = {}

local function hash(x, y, n) return ((x * 7 + y * 13 + x * y * 3) % n) + 1 end

function BV.backdrop(id)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(Assets.backdrop[id], 0, 0)
end

function BV.arena(id)
    local a = Assets.arena[id]
    local meta = a.meta
    local k = G.T / (meta.tile * meta.scale)
    local m = meta.margin * meta.scale * k
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(a.image, G.x - m, G.y - m, 0, k, k)
end

local function tileScale() return G.T / 200 end

--- Column letters (A..) under the board and row numbers (1..) beside it: the names the hints use ("the tile E4").
function BV.coords(n)
    local col = { 1, 0.95, 0.8 }
    for x = 1, n do
        local cx = G.center(x, 1)
        Text.display(string.char(64 + x), cx, G.y + G.size + 12, 13, col, "center")
    end
    for y = 1, n do
        local _, cy = G.center(1, y)
        Text.display(tostring(y), G.x - 24, cy - 6, 13, col, "center")
    end
end

--- Flat things lying on the ground: puddles, shade, sun patches, ant trails.
function BV.ground(view, state, time)
    local s = tileScale()
    for y = view.h, 1, -1 do
        for x = 1, view.w do
            local c = view.cells[Grid.key(x, y)]
            if c and not c.void then
                local cx, cy = G.center(x, y)
                if c.light == "shade" then
                    love.graphics.setColor(1, 1, 1, 1)
                    Assets.tiles:draw("shade", cx, cy, 0, s * 1.0)
                elseif c.light == "sun" then
                    love.graphics.setColor(1, 1, 1, 0.85 + 0.15 * math.sin(time * 2 + x))
                    Assets.tiles:draw("sunpatch", cx, cy, 0, s * 1.0)
                end
                if c.puddle then
                    love.graphics.setColor(1, 1, 1, 1)
                    local f = Assets.tiles.frames["puddle_" .. hash(x, y, 3)]
                    Assets.tiles:draw("puddle_" .. hash(x, y, 3), cx, cy + (f.h / 2 - f.py) * s, 0, s * 1.02 + math.sin(time * 1.5 + x * 2 + y) * 0.01)
                end
            end
        end
    end
    -- scent trails (taken from the real state: they fade, nobody needs to see them in order)
    if state then
        for y = state.h, 1, -1 do
            for x = 1, state.w do
                local c = state.cells[Grid.key(x, y)]
                if c and c.trail then
                    local cx, cy = G.center(x, y)
                    local col = c.trail.side == "kid" and Paper.C.teal or Paper.C.magenta
                    local a = math.min(0.75, 0.18 + c.trail.ttl * 0.1)
                    for i = 1, 4 do
                        local ox = Paper.noise(x * 31 + y, i * 3) * G.T * 0.3
                        local oy = Paper.noise(x * 17 + y * 5, i * 5) * G.T * 0.3
                        love.graphics.setColor(Paper.C.ink[1], Paper.C.ink[2], Paper.C.ink[3], a * 0.7)
                        love.graphics.circle("fill", cx + ox, cy + oy, 4.2)
                        love.graphics.setColor(col[1], col[2], col[3], a)
                        love.graphics.circle("fill", cx + ox, cy + oy, 2.8)
                    end
                end
            end
        end
    end
end

-- depth-sorted pass: everything that stands up
local function addProp(list, y, fn) list[#list + 1] = { y = y, fn = fn } end

local function foodSprite(kind) return kind == "crumb" and "crumb" or kind == "sugar" and "sugar" or kind == "juice" and "juice" or "loot" end

--- hiddenIds: set of actor ids that are hiding in cover (drawn faint, cover drawn over them)
function BV.props(view, actors, hiddenIds, time, extra)
    local s = tileScale()
    local list = {}
    for y = view.h, 1, -1 do
        for x = 1, view.w do
            local c = view.cells[Grid.key(x, y)]
            if c and not c.void then
                local cx, cy = G.center(x, y)
                if c.cover == "grass" then
                    local v = hash(x, y, 3)
                    addProp(list, cy - G.T * 0.2, function()
                        love.graphics.setColor(1, 1, 1, 1)
                        Assets.tiles:draw("grass_" .. v, cx, cy + G.T * 0.42, 0, s * 0.95)
                    end)
                elseif c.cover == "leaf" then
                    local v = hash(x, y, 2)
                    addProp(list, cy - G.T * 0.25, function()
                        love.graphics.setColor(1, 1, 1, 1)
                        Assets.tiles:draw("leaf_" .. v, cx, cy + G.T * 0.18, 0, s * 0.92)
                    end)
                end
                if c.block == "pebble" then
                    local v = hash(x, y, 2)
                    addProp(list, cy + G.T * 0.1, function()
                        love.graphics.setColor(1, 1, 1, 1)
                        Assets.tiles:draw("pebble_" .. v, cx, cy + G.T * 0.35, 0, s * 0.92)
                    end)
                elseif c.block == "knot" then
                    addProp(list, cy + G.T * 0.1, function()
                        love.graphics.setColor(1, 1, 1, 1)
                        Assets.tiles:draw("knot", cx, cy + G.T * 0.38, 0, s * 0.95)
                    end)
                elseif c.block == "stick" and c.stick and c.stick.first then
                    local x2, y2 = G.center(c.stick.x2, c.stick.y2)
                    local mx, my = (cx + x2) / 2, (cy + y2) / 2
                    local rot = (c.stick.y2 ~= y) and math.pi / 2 or 0
                    addProp(list, my + G.T * 0.05, function()
                        love.graphics.setColor(1, 1, 1, 1)
                        Assets.tiles:draw("stick", mx, my + G.T * 0.2, rot, s * 0.98)
                    end)
                end
                if c.food then
                    local kind = c.food.kind
                    addProp(list, cy + G.T * 0.02, function()
                        love.graphics.setColor(1, 1, 1, 1)
                        local bob = kind == "loot" and math.sin(time * 3 + x) * 2 or 0
                        Assets.tiles:draw(foodSprite(kind), cx, cy + G.T * 0.32 + bob, 0, s * 0.8)
                        if kind == "sugar" or kind == "loot" then
                            love.graphics.setColor(1, 1, 1, 0.5 + 0.5 * math.sin(time * 4 + y))
                            Assets.ui:draw("fx_sparkle", cx + G.T * 0.3, cy - G.T * 0.12, 0, 0.16 + 0.04 * math.sin(time * 5))
                        end
                    end)
                end
            end
        end
    end
    for _, a in ipairs(actors) do
        local hidden = hiddenIds[a.id]
        local fx, fy = G.foot(a.x, a.y)
        addProp(list, fy + a.offy, function() a:drawSprite(hidden) end)
        if hidden then
            -- the cover in front of a hiding bug
            local cx, cy = G.center(math.floor(a.x + 0.5), math.floor(a.y + 0.5))
            local c = view.cells[Grid.key(math.floor(a.x + 0.5), math.floor(a.y + 0.5))]
            if c and c.cover == "grass" then
                addProp(list, fy + a.offy + 0.5, function()
                    love.graphics.setColor(1, 1, 1, 0.95)
                    Assets.tiles:draw("grassfront_" .. hash(math.floor(a.x + 0.5), math.floor(a.y + 0.5), 2), cx, cy + G.T * 0.46, 0, s * 0.95)
                end)
            elseif c and c.cover == "leaf" then
                addProp(list, fy + a.offy + 0.5, function()
                    love.graphics.setColor(1, 1, 1, 0.62)
                    Assets.tiles:draw("leaf_" .. hash(math.floor(a.x + 0.5), math.floor(a.y + 0.5), 2), cx, cy + G.T * 0.18, 0, s * 0.92)
                end)
            end
        end
    end
    if extra then for _, e in ipairs(extra) do addProp(list, e.y, e.fn) end end
    table.sort(list, function(a, b) return a.y < b.y end)
    for _, it in ipairs(list) do it.fn() end
end

--- Rounded tile highlight. kind: "target" (teal) | "hover" | "area" (yellow) | "danger" (magenta)
function BV.tileGlow(x, y, kind, time, strength)
    local cx, cy = G.center(x, y)
    local T = G.T
    local col = kind == "area" and Paper.C.yellow or kind == "danger" and Paper.C.magenta or kind == "ok" and Paper.C.green or Paper.C.teal
    local pulse = 0.5 + 0.5 * math.sin(time * 5 + x + y)
    local soft = kind == "target"      -- many tiles can be targets at once: keep them quiet
    local a = (kind == "hover" and 0.5 or soft and 0.1 + 0.06 * pulse or 0.22 + 0.12 * pulse) * (strength or 1)
    love.graphics.setColor(col[1], col[2], col[3], a)
    love.graphics.rectangle("fill", cx - T / 2 + 4, cy - T / 2 + 4, T - 8, T - 8, 14, 14)
    love.graphics.setLineWidth(kind == "hover" and 5 or soft and 2 or 3)
    love.graphics.setColor(Paper.C.ink[1], Paper.C.ink[2], Paper.C.ink[3], (soft and 0.3 or 0.85) * (strength or 1))
    love.graphics.rectangle("line", cx - T / 2 + 4, cy - T / 2 + 4, T - 8, T - 8, 14, 14)
    love.graphics.setLineWidth(soft and 2 or 2)
    love.graphics.setColor(col[1], col[2], col[3], (soft and 0.7 or 1) * (strength or 1))
    love.graphics.rectangle("line", cx - T / 2 + 7, cy - T / 2 + 7, T - 14, T - 14, 12, 12)
end

function BV.actorRing(a, time, kind)
    local fx, fy = G.foot(a.x, a.y)
    local T = G.T
    local col = kind == "danger" and Paper.C.magenta or Paper.C.yellow
    local pulse = 0.5 + 0.5 * math.sin(time * 6)
    love.graphics.setLineWidth(5)
    love.graphics.setColor(Paper.C.ink[1], Paper.C.ink[2], Paper.C.ink[3], 0.9)
    love.graphics.ellipse("line", fx, fy, T * (0.42 + 0.03 * pulse), T * (0.2 + 0.015 * pulse))
    love.graphics.setLineWidth(3)
    love.graphics.setColor(col[1], col[2], col[3], 1)
    love.graphics.ellipse("line", fx, fy, T * (0.42 + 0.03 * pulse), T * (0.2 + 0.015 * pulse))
end

--- A half-transparent item following the mouse while you decide where to put it.
function BV.ghost(kind, x, y, x2, y2, time)
    local s = tileScale()
    local function at(px, py, name, sc, rot)
        local cx, cy = G.center(px, py)
        love.graphics.setColor(1, 1, 1, 0.62 + 0.12 * math.sin(time * 6))
        Assets.tiles:draw(name, cx, cy + G.T * 0.3 + math.sin(time * 4) * 2, rot or 0, sc)
    end
    if kind == "crumb" or kind == "sugar" or kind == "juice" then at(x, y, kind, s * 0.8)
    elseif kind == "pebble" then at(x, y, "pebble_1", s * 0.92)
    elseif kind == "leaf" then at(x, y, "leaf_1", s * 0.92)
    elseif kind == "stick" and x2 then
        local ax, ay = G.center(x, y)
        local bx, by = G.center(x2, y2)
        love.graphics.setColor(1, 1, 1, 0.7)
        Assets.tiles:draw("stick", (ax + bx) / 2, (ay + by) / 2 + G.T * 0.2, (y2 ~= y) and math.pi / 2 or 0, s * 0.98)
    elseif kind == "puddle" then
        for i, p in ipairs({ { x, y }, { x2 or x, y2 or y } }) do
            local cx, cy = G.center(p[1], p[2])
            love.graphics.setColor(1, 1, 1, 0.65)
            Assets.tiles:draw("puddle_" .. i, cx, cy, 0, s * 1.02)
        end
    end
end

return BV
