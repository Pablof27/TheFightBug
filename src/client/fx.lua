-- Particles, floating texts and rings. Everything lives in virtual screen coordinates.

local Assets = require("client.assets")
local Text = require("client.text")

local Fx = { items = {}, shakeAmount = 0, flash = 0 }

local function push(it) Fx.items[#Fx.items + 1] = it; return it end
local rnd = function(a, b) return a + love.math.random() * (b - a) end

--- A sprite from the UI atlas flying about. o: vx, vy, gravity, vr (spin), life, s0, s1, a0, a1, rot
function Fx.sprite(name, x, y, o)
    o = o or {}
    return push({
        kind = "sprite", name = name, x = x, y = y, vx = o.vx or 0, vy = o.vy or 0, g = o.gravity or 0,
        rot = o.rot or 0, vr = o.vr or 0, life = o.life or 0.6, t = -(o.delay or 0),
        s0 = o.s0 or 0.3, s1 = o.s1 or 0.3, a0 = o.a0 or 1, a1 = o.a1 or 0, tint = o.tint,
    })
end

--- Floating text that rises and fades. size = cap height of the display font.
function Fx.text(str, x, y, color, size, o)
    o = o or {}
    return push({ kind = "text", str = str, x = x, y = y, vy = o.vy or -48, life = o.life or 0.9, t = -(o.delay or 0), color = color or { 1, 1, 1 }, size = size or 26, pop = o.pop ~= false, body = o.body })
end

function Fx.ring(x, y, r0, r1, color, life, width)
    return push({ kind = "ring", x = x, y = y, r0 = r0, r1 = r1, color = color or { 1, 1, 1 }, life = life or 0.4, t = 0, width = width or 6 })
end

function Fx.puff(x, y, n, scale)
    for _ = 1, n or 4 do
        Fx.sprite("fx_puff", x + rnd(-14, 14), y + rnd(-6, 6), { vx = rnd(-40, 40), vy = rnd(-60, -20), life = rnd(0.35, 0.6), s0 = (scale or 0.22) * 0.6, s1 = (scale or 0.22) * 1.3, a0 = 0.9, rot = rnd(-1, 1), vr = rnd(-2, 2) })
    end
end

function Fx.pow(x, y, scale)
    Fx.sprite("fx_pow", x, y, { life = 0.32, s0 = (scale or 0.5) * 0.5, s1 = (scale or 0.5) * 1.15, a0 = 1, a1 = 0, rot = rnd(-0.3, 0.3) })
end

function Fx.stars(x, y, n)
    for i = 1, n or 3 do
        Fx.sprite("fx_star", x, y, { vx = rnd(-70, 70), vy = rnd(-120, -50), gravity = 260, life = rnd(0.6, 0.9), s0 = 0.34, s1 = 0.2, vr = rnd(-5, 5) })
    end
end

function Fx.sparkle(x, y, n, spread)
    for _ = 1, n or 5 do
        Fx.sprite("fx_sparkle", x + rnd(-(spread or 20), spread or 20), y + rnd(-(spread or 20), spread or 20), { vy = rnd(-40, -10), life = rnd(0.4, 0.8), s0 = 0.1, s1 = 0.34, delay = rnd(0, 0.2) })
    end
end

function Fx.notes(x, y, n)
    for _ = 1, n or 3 do Fx.sprite("fx_note", x, y, { vx = rnd(-50, 50), vy = rnd(-90, -50), life = 1.0, s0 = 0.3, s1 = 0.3, vr = rnd(-1, 1), delay = rnd(0, 0.3) }) end
end

function Fx.drops(x, y, n)
    for _ = 1, n or 5 do Fx.sprite("fx_drop", x, y, { vx = rnd(-90, 90), vy = rnd(-190, -90), gravity = 520, life = 0.6, s0 = 0.28, s1 = 0.2 }) end
end

function Fx.leaves(x, y, n)
    for _ = 1, n or 4 do Fx.sprite("fx_leafp", x + rnd(-30, 30), y, { vx = rnd(-30, 30), vy = rnd(-20, 30), gravity = 20, life = 1.1, s0 = 0.22, s1 = 0.2, vr = rnd(-3, 3) }) end
end

function Fx.shake(amount) Fx.shakeAmount = math.max(Fx.shakeAmount, amount) end
function Fx.whiteFlash(a) Fx.flash = math.max(Fx.flash, a) end

function Fx.clear() Fx.items = {}; Fx.shakeAmount = 0 end

function Fx.update(dt)
    Fx.shakeAmount = math.max(0, Fx.shakeAmount - dt * 40)
    Fx.flash = math.max(0, Fx.flash - dt * 2.5)
    local i = 1
    while i <= #Fx.items do
        local it = Fx.items[i]
        it.t = it.t + dt
        if it.t >= 0 then
            if it.kind == "sprite" then
                it.vy = it.vy + it.g * dt
                it.x, it.y = it.x + it.vx * dt, it.y + it.vy * dt
                it.rot = it.rot + it.vr * dt
            elseif it.kind == "text" then
                it.y = it.y + it.vy * dt
                it.vy = it.vy * (1 - 1.8 * dt)
            end
        end
        if it.t >= it.life then table.remove(Fx.items, i) else i = i + 1 end
    end
end

function Fx.draw()
    for _, it in ipairs(Fx.items) do
        if it.t >= 0 then
            local k = it.t / it.life
            if it.kind == "sprite" then
                local s = it.s0 + (it.s1 - it.s0) * k
                local a = it.a0 + (it.a1 - it.a0) * k
                local c = it.tint or { 1, 1, 1 }
                love.graphics.setColor(c[1], c[2], c[3], a)
                Assets.ui:draw(it.name, it.x, it.y, it.rot, s, s)
            elseif it.kind == "text" then
                local a = k < 0.7 and 1 or (1 - (k - 0.7) / 0.3)
                local s = it.size * (it.pop and (1 + 0.5 * math.max(0, 1 - k * 7)) or 1)
                local c = it.color
                if it.body then Text.body(it.str, it.x, it.y, s, { c[1], c[2], c[3], a }, "center", nil, 2)
                else Text.display(it.str, it.x, it.y - s / 2, s, { c[1], c[2], c[3], a }, "center") end
            elseif it.kind == "ring" then
                local r = it.r0 + (it.r1 - it.r0) * (1 - (1 - k) ^ 2)
                love.graphics.setLineWidth(it.width * (1 - k * 0.6) + 2)
                love.graphics.setColor(Text.INK[1], Text.INK[2], Text.INK[3], 1 - k)
                love.graphics.circle("line", it.x, it.y, r)
                love.graphics.setLineWidth(it.width * (1 - k * 0.6))
                love.graphics.setColor(it.color[1], it.color[2], it.color[3], 1 - k)
                love.graphics.circle("line", it.x, it.y, r)
            end
        end
    end
end

return Fx
