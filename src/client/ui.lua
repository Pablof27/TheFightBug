-- Small shared widgets for the menu-like scenes (title, map, shop, ending).

local Paper = require("client.paper")
local Text = require("client.text")

local UI = {}
local C = Paper.C

function UI.inside(r, x, y) return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end

--- A big paper button. o: fill, color (text), size (cap height), hover, seed, rot, disabled
function UI.button(r, label, o)
    o = o or {}
    local lift = (o.hover and not o.disabled) and -6 or 0
    local fill = o.disabled and { 0.62, 0.6, 0.66 } or (o.fill or C.teal)
    Paper.panel(r.x, r.y + lift, r.w, r.h, { fill = fill, seed = o.seed or 3, r = o.r or 22, rot = o.rot or -0.008, shadow = true })
    local size = o.size or math.min(40, r.h * 0.4)
    Text.display(label, r.x + r.w / 2, r.y + lift + (r.h - size) / 2 - 1, size, o.color or { 1, 1, 1 }, "center")
end

return UI
