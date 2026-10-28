-- Intent overlay (GDD §5.4): every bug always shows what it will do when its timer runs out. Bugs that act on the next tick
-- are drawn bold (their intent comes from really running that tick), the others are faint ("if nothing changes").

local Assets = require("client.assets")
local Paper = require("client.paper")
local Text = require("client.text")
local G = require("client.fight.geometry")

local Intent = {}
local C = Paper.C

local function sideColor(side) return side == "kid" and C.teal or C.magenta end

--- A small speech-bubble style chip with an icon and an optional number.
local function chip(x, y, icon, label, color, a)
    local u = G.unit
    Paper.disc(x, y, 15 * u, { color[1], color[2], color[3], a }, { shadow = true, line = 3 * u })
    love.graphics.setColor(1, 1, 1, a)
    Assets.ui:draw(icon, x, y, 0, 0.17 * u)
    if label then Text.display(label, x + 14 * u, y + 2 * u, 15 * u, { 1, 1, 1, a }, "left") end
end

function Intent.draw(scene, forecast, hoverId, changed, time)
    if not forecast then return end
    local u, T = G.unit, G.T
    local order = {}
    for id in pairs(forecast.intents) do order[#order + 1] = id end
    table.sort(order)
    for _, id in ipairs(order) do
        local it = forecast.intents[id]
        local a = scene.actorById[id]
        if a and not a.gone and it.kind ~= "idle" then
            local col = sideColor(a.side)
            local hov = (id == hoverId)
            local alpha = hov and 1 or (it.exact and 0.9 or 0.34)
            if hoverId and not hov then alpha = alpha * 0.55 end
            local fx, fy = G.foot(a.x, a.y)
            local sx, sy = fx, fy - T * 0.3
            local moves = it.path and #it.path > 0
            if moves then
                local pts = { { sx, sy } }
                if it.mode == "fly" or it.mode == "jump" then
                    local ex, ey = G.center(it.to.x, it.to.y)
                    pts[#pts + 1] = { (sx + ex) / 2, (sy + ey) / 2 - T * 0.45 }
                    pts[#pts + 1] = { ex, ey + T * 0.05 }
                else
                    for _, p in ipairs(it.path) do local px, py = G.center(p.x, p.y); pts[#pts + 1] = { px, py + T * 0.05 } end
                end
                Paper.arrow(pts, { color = col, alpha = alpha, width = 6.5 * u, spacing = 15 * u, head = 15 * u })
                if it.exact or hov then
                    -- ghost of where it will be standing
                    local gx, gy = G.foot(it.to.x, it.to.y)
                    love.graphics.setColor(1, 1, 1, hov and 0.5 or 0.3)
                    local frame = a.curled and "alt" or "idle1"
                    local facing = (it.to.x < a.x) and -1 or (it.to.x > a.x and 1 or a.facing)
                    Assets.bug[a.species]:draw(frame, gx, gy - (a:isFlying() and 24 * u or 0), 0, 0.5 * u * facing, 0.5 * u)
                end
            end
            -- what it does there
            local act = it.action
            if it.kind == "attack" and act and it.target and it.target.kind == "bug" then
                local t = scene.actorById[it.target.id]
                if t then
                    local tx, ty = G.foot(t.x, t.y)
                    local ex, ey = tx, ty - T * 0.55
                    -- aim line from the attack position
                    local ax, ay = G.foot(it.to.x, it.to.y)
                    love.graphics.setColor(C.ink[1], C.ink[2], C.ink[3], alpha)
                    love.graphics.setLineWidth(8 * u)
                    love.graphics.line(ax, ay - T * 0.5, ex, ey)
                    love.graphics.setColor(col[1], col[2], col[3], alpha)
                    love.graphics.setLineWidth(4 * u)
                    love.graphics.line(ax, ay - T * 0.5, ex, ey)
                    local label = act.dmg and act.dmg > 0 and ("-" .. act.dmg) or nil
                    if scene.state and scene.state.rule.attackMode == "push" then label = nil end
                    chip(ex, ey - 10 * u, "icon_fang", label, C.red, alpha)
                    if act.kind == "ram" then
                        local ox, oy = G.center(t.x, t.y)
                        local pts = { { ox, oy }, { ox + act.dx * T * 0.62, oy - act.dy * T * 0.62 } }
                        Paper.arrow(pts, { color = C.orange, alpha = alpha, width = 6 * u, spacing = 13 * u, head = 14 * u })
                    end
                end
            elseif (it.kind == "eat" or it.kind == "pickup") and it.target then
                local ex, ey = G.foot(it.target.x, it.target.y)
                chip(ex, ey - T * 0.5, it.kind == "pickup" and "icon_marble" or "icon_heart", nil, C.orange, alpha)
            elseif it.kind == "deliver" then
                local ex, ey = G.foot(it.to.x, it.to.y)
                chip(ex, ey - T * 0.9, "icon_marble", "+1", C.green, alpha)
            elseif it.kind == "rest" then
                chip(fx, fy - T * 1.0, "icon_heart", "+1", C.red, alpha * 0.9)
            elseif it.kind == "chirp" then
                chip(fx, fy - T * 1.15, "fx_note", nil, C.yellow, alpha * 0.9)
                if hov then
                    local cx, cy = G.center(it.to.x, it.to.y)
                    love.graphics.setLineWidth(4)
                    love.graphics.setColor(C.yellow[1], C.yellow[2], C.yellow[3], 0.8)
                    love.graphics.circle("line", cx, cy, T * 2.2)
                end
            elseif it.kind == "getup" then
                chip(fx, fy - T * 0.9, "icon_undo", nil, C.purple, alpha)
            elseif it.kind == "ready" then
                chip(fx - T * 0.3, fy - T * 0.9, "icon_eye", nil, C.yellow, alpha)
            end
            -- intent changed by the card being previewed
            if changed and changed[id] then
                local pulse = 0.5 + 0.5 * math.sin(time * 8)
                love.graphics.setLineWidth(5)
                love.graphics.setColor(C.yellow[1], C.yellow[2], C.yellow[3], 0.6 + 0.4 * pulse)
                love.graphics.ellipse("line", fx, fy, T * (0.46 + 0.04 * pulse), T * 0.22)
            end
        end
    end
    -- who will be gone after the next tick
    if forecast.events then
        for _, ev in ipairs(forecast.events) do
            if ev.type == "scurry" or ev.type == "fall" then
                local a = scene.actorById[ev.id]
                if a and not a.gone then
                    local fx, fy = G.foot(a.x, a.y)
                    local pulse = 0.5 + 0.5 * math.sin(time * 7)
                    Paper.disc(fx - T * 0.3, fy - T * 0.95, 13 * G.unit * (1 + 0.08 * pulse), { 0.17, 0.07, 0.22, 0.92 }, { line = 2.5 })
                    Text.display("X", fx - T * 0.3, fy - T * 0.95 - 8 * G.unit, 16 * G.unit, { 1, 0.35, 0.45, 1 }, "center")
                end
            end
        end
    end
end

return Intent
