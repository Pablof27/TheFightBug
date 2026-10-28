-- Text drawing. The hand-lettered display font (uppercase, outline baked in) is for titles, numbers and names;
-- LÖVE's built-in font (rasterised at 2x so it stays crisp when the window is scaled) is for the small print.

local Assets = require("client.assets")

local Text = {}

local INK = { 0.17, 0.07, 0.22 }
Text.INK = INK

local bodyFonts = {}
local function bodyFont(size)
    local f = bodyFonts[size]
    if not f then
        f = love.graphics.newFont(size * 2)
        f:setFilter("linear", "linear")
        bodyFonts[size] = f
    end
    return f
end

local DISPLAY_BASE = 14      -- px of margin above the capital letters in the font strip
local CAP = 56               -- cap height of the font strip
local SQUEEZE = 0.84         -- the hand-lettered caps are wide; a touch of horizontal squeeze keeps layouts compact
local TRACK = -16             -- glyph cells overlap by this many strip px (the baked outline needs the padding, the eye doesn't)

local advances = {}
local function advance(f, ch)
    local a = advances[ch]
    if not a then a = f:getWidth(ch) + TRACK; advances[ch] = a end
    return a
end

local function measure(f, str)
    local w = 0
    for i = 1, #str do w = w + advance(f, str:sub(i, i)) end
    return math.max(0, w - TRACK)
end

local function clean(str)
    return (tostring(str):upper():gsub("\226\128\148", "-"):gsub("\194\183", "-"))
end

--- Display text; (x, y) = top-left of the capital letters, `size` = cap height in virtual px.
--- Without `limit`, align is relative to x. With `limit` the text sits in a box [x, x + limit] and shrinks to fit it (one line).
function Text.display(str, x, y, size, color, align, limit)
    str = clean(str)
    local f = Assets.fonts.display
    local s = size / CAP
    local w = measure(f, str) * s * SQUEEZE
    if limit and w > limit then
        local k = limit / w
        y = y + size * (1 - k) / 2
        s = s * k
        w = limit
    end
    love.graphics.setFont(f)
    love.graphics.setColor(color or { 1, 1, 1, 1 })
    local px = x
    if limit then
        if align == "center" then px = x + (limit - w) / 2 elseif align == "right" then px = x + limit - w end
    else
        if align == "center" then px = x - w / 2 elseif align == "right" then px = x - w end
    end
    local yy = y - DISPLAY_BASE * s
    local sx = s * SQUEEZE
    for i = 1, #str do
        local ch = str:sub(i, i)
        if ch ~= " " then love.graphics.print(ch, px, yy, 0, sx, s) end
        px = px + advance(f, ch) * sx
    end
end

function Text.displayWidth(str, size)
    return measure(Assets.fonts.display, clean(str)) * size / CAP * SQUEEZE
end

--- Body text with an optional outline (virtual px).
function Text.body(str, x, y, size, color, align, limit, outline)
    str = tostring(str)
    local f = bodyFont(size)
    love.graphics.setFont(f)
    local function put(px, py, c)
        love.graphics.setColor(c)
        if limit then love.graphics.printf(str, px, py, limit * 2, align or "left", 0, 0.5, 0.5)
        else
            local w = f:getWidth(str) * 0.5
            local ax = px
            if align == "center" then ax = px - w / 2 elseif align == "right" then ax = px - w end
            love.graphics.print(str, ax, py, 0, 0.5, 0.5)
        end
    end
    if outline and outline > 0 then
        local o = outline
        for _, d in ipairs({ { -o, 0 }, { o, 0 }, { 0, -o }, { 0, o }, { -o, -o }, { o, -o }, { -o, o }, { o, o } }) do put(x + d[1], y + d[2], INK) end
    end
    put(x, y, color or INK)
end

--- Height of wrapped body text.
function Text.bodyHeight(str, size, limit)
    local f = bodyFont(size)
    local _, lines = f:getWrap(tostring(str), limit * 2)
    return #lines * f:getHeight() * 0.5
end

function Text.bodyWidth(str, size) return bodyFont(size):getWidth(tostring(str)) * 0.5 end

return Text
