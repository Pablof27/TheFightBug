-- Tweens and delayed calls. One global list, cleared when the scene changes.

local Tween = {}

local E = {}
Tween.ease = E
function E.linear(t) return t end
function E.inQuad(t) return t * t end
function E.outQuad(t) return 1 - (1 - t) * (1 - t) end
function E.inOutQuad(t) return t < 0.5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2 end
function E.outCubic(t) return 1 - (1 - t) ^ 3 end
function E.inCubic(t) return t * t * t end
function E.inOutCubic(t) return t < 0.5 and 4 * t * t * t or 1 - (-2 * t + 2) ^ 3 / 2 end
function E.outBack(t) local c1, c3 = 1.70158, 2.70158; return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2 end
function E.outBounce(t)
    local n1, d1 = 7.5625, 2.75
    if t < 1 / d1 then return n1 * t * t
    elseif t < 2 / d1 then t = t - 1.5 / d1; return n1 * t * t + 0.75
    elseif t < 2.5 / d1 then t = t - 2.25 / d1; return n1 * t * t + 0.9375
    else t = t - 2.625 / d1; return n1 * t * t + 0.984375 end
end
function E.outElastic(t)
    if t == 0 or t == 1 then return t end
    return 2 ^ (-10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi) / 3) + 1
end

local list = {}

--- Tween numeric fields of `obj` to the given values over `dur` seconds.
function Tween.to(obj, props, dur, ease, onDone)
    local from = {}
    for k in pairs(props) do from[k] = obj[k] end
    local tw = { obj = obj, from = from, to = props, dur = math.max(dur, 0.0001), t = 0, ease = E[ease or "outQuad"] or ease, onDone = onDone }
    list[#list + 1] = tw
    return tw
end

function Tween.after(delay, fn)
    local tw = { delay = delay, fn = fn }
    list[#list + 1] = tw
    return tw
end

function Tween.cancel(tw) if tw then tw.dead = true end end
--- Forgets every running tween (they will never fire). Safe to call from inside a tween callback.
function Tween.clear()
    for _, tw in ipairs(list) do tw.dead = true end
    list = {}
end

function Tween.update(dt)
    local cur = list     -- a callback may call clear(), which swaps `list`: keep draining the old one
    local i = 1
    while i <= #cur do
        local tw = cur[i]
        local done = false
        if tw.dead then
            done = true
        elseif tw.fn then
            tw.delay = tw.delay - dt
            if tw.delay <= 0 then tw.fn(); done = true end
        else
            tw.t = tw.t + dt
            local k = math.min(1, tw.t / tw.dur)
            local e = tw.ease(k)
            for key, v in pairs(tw.to) do tw.obj[key] = tw.from[key] + (v - tw.from[key]) * e end
            if k >= 1 then done = true; if tw.onDone then tw.onDone() end end
        end
        if done then table.remove(cur, i) else i = i + 1 end
    end
end

return Tween
