-- Intent overlay (GDD §5.4): every bug always shows what it will do when it acts (on the tick after its timer reaches 0).
-- Bugs that act on the next tick are drawn bold (their intent comes from really running that tick), the others are
-- faint ("if nothing changes"). The action icon sits on the acting bug's own badge strip, right of its hearts, so it
-- always reads as *that* bug's plan; the path and the aim line show where it goes and whom it hits.

local Assets = require("client.assets")
local Paper = require("client.paper")
local Text = require("client.text")
local G = require("client.fight.geometry")

local Intent = {}
local C = Paper.C

local function sideColor(side) return side == "kid" and C.teal or C.magenta end

--- The action icon on the actor's strip, with an optional little number tag (damage, +1).
local function chip(actor, icon, color, a, tag)
    local L = actor:badgeLayout()
    local u = G.unit
    local x, y, r = L.chipX, L.y, L.r * 0.95
    Paper.disc(x, y, r, { color[1], color[2], color[3], a }, { seed = actor.id + 3, shadow = true, line = 2.8 * u })
    love.graphics.setColor(1, 1, 1, a)
    Assets.ui:draw(icon, x, y, 0, 0.16 * u)
    if tag then
        local tx, ty, tr = x + r * 0.8, y - r * 0.85, 9.5 * u
        Paper.disc(tx, ty, tr, { C.ink[1], C.ink[2], C.ink[3], a }, { seed = actor.id, line = 0 })
        Text.display(tag, tx, ty - 6.5 * u, 13 * u, { 1, 1, 1, a }, "center")
    end
end

function Intent.draw(scene, forecast, hoverId, changed, time)
    if not forecast then return end
    local u, T = G.unit, G.T
    local chips = {}
    local function queue(...) chips[#chips + 1] = { ... } end
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
            local chipAlpha = hov and 1 or (it.exact and 0.95 or 0.6)
            if hoverId and not hov then chipAlpha = chipAlpha * 0.6 end
            if it.kind == "attack" and act and it.target and it.target.kind == "bug" then
                local t = scene.actorById[it.target.id]
                if t then
                    -- aim line from the attack position to the target, ending in an impact mark on the target
                    local tx, ty = G.foot(t.x, t.y)
                    local ex, ey = tx, ty - t:height() * T * 0.5
                    local ax, ay = G.foot(it.to.x, it.to.y)
                    ay = ay - a:height() * T * 0.5
                    love.graphics.setColor(C.ink[1], C.ink[2], C.ink[3], alpha)
                    love.graphics.setLineWidth(8 * u)
                    love.graphics.line(ax, ay, ex, ey)
                    love.graphics.setColor(col[1], col[2], col[3], alpha)
                    love.graphics.setLineWidth(4 * u)
                    love.graphics.line(ax, ay, ex, ey)
                    love.graphics.setColor(1, 1, 1, alpha)
                    Assets.ui:draw("fx_pow", ex, ey, 0, 0.13 * u)
                    if act.kind == "ram" then
                        local ox, oy = G.center(t.x, t.y)
                        local pts = { { ox, oy }, { ox + act.dx * T * 0.62, oy - act.dy * T * 0.62 } }
                        Paper.arrow(pts, { color = C.orange, alpha = alpha, width = 6 * u, spacing = 13 * u, head = 14 * u })
                    end
                end
                local push = scene.state and scene.state.rule.attackMode == "push"
                queue(a, "icon_fang", C.red, chipAlpha, (not push and act.dmg and act.dmg > 0) and tostring(act.dmg) or nil)
            elseif it.kind == "eat" then
                queue(a, "icon_heart", C.orange, chipAlpha)
            elseif it.kind == "pickup" then
                queue(a, "icon_marble", C.orange, chipAlpha)
            elseif it.kind == "deliver" then
                queue(a, "icon_marble", C.green, chipAlpha, "+1")
            elseif it.kind == "rest" then
                queue(a, "icon_heart", C.red, chipAlpha * 0.95, "+1")
            elseif it.kind == "chirp" then
                queue(a, "fx_note", C.yellow, chipAlpha * 0.95)
                if hov then
                    local cx, cy = G.center(it.to.x, it.to.y)
                    love.graphics.setLineWidth(4)
                    love.graphics.setColor(C.yellow[1], C.yellow[2], C.yellow[3], 0.8)
                    love.graphics.circle("line", cx, cy, T * 2.2)
                end
            elseif it.kind == "getup" then
                queue(a, "icon_undo", C.purple, chipAlpha)
            elseif it.kind == "ready" then
                queue(a, "icon_eye", C.yellow, chipAlpha)
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
    -- action icons last, so no arrow or aim line is ever drawn across one
    for _, c in ipairs(chips) do chip(c[1], c[2], c[3], c[4], c[5]) end
end

--- Who will be gone after the next tick: an X over the bug's own hearts. Drawn after the badges, so it covers them.
function Intent.drawOuts(scene, forecast, time)
    if not (forecast and forecast.events) then return end
    local u = G.unit
    for _, ev in ipairs(forecast.events) do
        if ev.type == "scurry" or ev.type == "fall" then
            local a = scene.actorById[ev.id]
            if a and not a.gone then
                local L = a:badgeLayout()
                local pulse = 0.5 + 0.5 * math.sin(time * 7)
                Paper.disc(L.fx, L.y, 13 * u * (1 + 0.08 * pulse), { 0.17, 0.07, 0.22, 0.92 }, { line = 2.5 })
                Text.display("X", L.fx, L.y - 8 * u, 16 * u, { 1, 0.35, 0.45, 1 }, "center")
            end
        end
    end
end

return Intent
