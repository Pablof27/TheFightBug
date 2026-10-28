-- Virtual screen: the whole game is laid out on a 1600 x 900 canvas that is scaled (and letterboxed) to the window.

local Screen = { W = 1600, H = 900, scale = 1, ox = 0, oy = 0 }

function Screen.resize(w, h)
    w, h = w or love.graphics.getWidth(), h or love.graphics.getHeight()
    Screen.scale = math.min(w / Screen.W, h / Screen.H)
    Screen.ox = (w - Screen.W * Screen.scale) / 2
    Screen.oy = (h - Screen.H * Screen.scale) / 2
end

function Screen.begin()
    love.graphics.push()
    love.graphics.translate(Screen.ox, Screen.oy)
    love.graphics.scale(Screen.scale, Screen.scale)
end

function Screen.finish() love.graphics.pop() end

--- window pixels -> virtual coordinates
function Screen.toVirtual(x, y)
    return (x - Screen.ox) / Screen.scale, (y - Screen.oy) / Screen.scale
end

return Screen
