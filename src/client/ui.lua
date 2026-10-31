-- Small shared widgets for the menu-like scenes (title, park, duel, van, ending): paper buttons, icons, portraits,
-- tooltips, and an immediate-mode list of clickable areas (UI.hits) rebuilt on every draw.

local Assets = require("client.assets")
local Paper = require("client.paper")
local Text = require("client.text")

local UI = {}
local C = Paper.C
UI.SOFT = { 0.4, 0.25, 0.5 }

function UI.inside(r, x, y) return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end

function UI.plural(n, word) return n .. " " .. word .. (n == 1 and "" or "S") end

--- A big paper button. o: fill, color (text), size (cap height), hover, seed, rot, disabled
function UI.button(r, label, o)
    o = o or {}
    local lift = (o.hover and not o.disabled) and -6 or 0
    local fill = o.disabled and { 0.62, 0.6, 0.66 } or (o.fill or C.teal)
    Paper.panel(r.x, r.y + lift, r.w, r.h, { fill = fill, seed = o.seed or 3, r = o.r or 22, rot = o.rot or -0.008, shadow = true })
    local size = o.size or math.min(40, r.h * 0.4)
    Text.display(label, r.x + 12, r.y + lift + (r.h - size) / 2 - 1, size, o.color or { 1, 1, 1 }, "center", r.w - 24)
end

--- A sprite of the UI atlas, centred on (x, y), fitted in a square of `size`.
function UI.icon(name, x, y, size, alpha)
    local w, h = Assets.ui:size(name)
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(Assets.ui.image, Assets.ui.quads[name], x, y, 0, size / math.max(w, h), size / math.max(w, h), w / 2, h / 2)
end

function UI.marble(x, y, size) UI.icon("icon_marble", x, y, size) end

--- A rival kid's face in a magenta disc.
function UI.kidDisc(portrait, mood, x, y, r, seed)
    Paper.disc(x, y, r, C.magenta, { seed = seed or 1, shadow = true, line = 4 })
    Paper.disc(x, y, r * 0.88, { 1, 0.84, 0.55 }, { seed = (seed or 1) + 1, line = 0 })
    love.graphics.setColor(1, 1, 1, 1)
    Assets.drawKid(portrait, mood or "neutral", x, y + r * 0.06, r * 2.25)
end

--- A bug's face in a disc. o: ring (colour), fill, seed, shadow, alpha
function UI.bugDisc(species, x, y, r, o)
    o = o or {}
    Paper.disc(x, y, r, o.ring or C.teal, { seed = o.seed or 3, shadow = o.shadow ~= false, line = r > 24 and 4 or 3 })
    Paper.disc(x, y, r * 0.86, o.fill or C.cream, { seed = (o.seed or 3) + 1, line = 0 })
    love.graphics.setColor(1, 1, 1, o.alpha or 1)
    Assets.drawPortrait(species, x, y, r * 1.62)
end

--- A small tag: a rounded label in a colour (NEW!, ZZZ, ALL IN...).
function UI.tag(label, x, y, size, fill, o)
    o = o or {}
    local w = Text.displayWidth(label, size) + size * 1.2
    local h = size * 1.9
    local x0 = o.align == "center" and x - w / 2 or o.align == "right" and x - w or x
    Paper.panel(x0, y, w, h, { fill = fill or C.magenta, seed = o.seed or 7, r = h / 2.4, line = 2.5, shadow = o.shadow ~= false, rot = o.rot or 0 })
    Text.display(label, x0 + w / 2, y + (h - size) / 2, size, o.color or { 1, 1, 1 }, "center")
    return w, h
end

--- A row of marble pips (for stacks that are small enough to count), else the number.
function UI.marbles(n, x, y, size, color, align)
    UI.marble(x + size / 2, y + size / 2, size)
    Text.display(UI.plural(n, "MARBLE"), x + size + 8, y + size * 0.12, size * 0.72, color or Text.INK, align or "left")
end

--- A tooltip box near the mouse: a title and a body, kept on screen.
function UI.tooltip(mx, my, title, body, o)
    o = o or {}
    local w = o.w or 340
    local bh = body and Text.bodyHeight(body, 13, w - 32) or 0
    local h = 22 + (title and 26 or 0) + bh + 16
    local x = math.min(mx + 24, 1600 - w - 12)
    local y = math.min(my + 20, 900 - h - 12)
    if x < 12 then x = 12 end
    Paper.panel(x, y, w, h, { fill = o.fill or C.cream, seed = 501, r = 14, line = 3, rot = 0 })
    local ty = y + 14
    if title then Text.display(title, x + 16, ty, 15, o.titleColor or C.magentaDark, "left", w - 32); ty = ty + 26 end
    if body then Text.body(body, x + 16, ty, 13, Text.INK, "left", w - 32) end
end

--- A dark veil over the whole screen (under a dialog).
function UI.veil(a)
    love.graphics.setColor(0.17, 0.07, 0.22, a or 0.55)
    love.graphics.rectangle("fill", 0, 0, 1600, 900)
end

-- ───────────────────────── clickable areas ─────────────────────────
-- A scene keeps a hit list: draw code registers areas with UI.hit(list, r, key, data) while drawing, and input reads the
-- list of the last frame drawn. The last area registered on top wins.

function UI.hit(list, r, key, data)
    list[#list + 1] = { r = r, key = key, data = data }
end

function UI.hitAt(list, x, y)
    for i = #list, 1, -1 do
        local h = list[i]
        if UI.inside(h.r, x, y) then return h end
    end
    return nil
end

return UI
