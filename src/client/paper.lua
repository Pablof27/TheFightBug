-- Hand-drawn UI primitives: wobbly paper panels, discs, hearts, dotted arrows. Shapes are generated once and cached.

local Paper = {}

Paper.C = {
    ink = { 0.17, 0.07, 0.22 },
    cream = { 1.0, 0.953, 0.84 }, cream2 = { 0.96, 0.88, 0.7 },
    teal = { 0.14, 0.78, 0.69 }, tealDark = { 0.08, 0.5, 0.5 },
    magenta = { 0.93, 0.25, 0.56 }, magentaDark = { 0.6, 0.12, 0.36 },
    orange = { 1.0, 0.6, 0.24 }, yellow = { 1.0, 0.82, 0.25 },
    purple = { 0.42, 0.25, 0.65 }, purpleLight = { 0.7, 0.55, 0.95 },
    green = { 0.35, 0.8, 0.55 }, red = { 1.0, 0.31, 0.43 }, blue = { 0.42, 0.72, 1.0 },
    white = { 1, 1, 1 },
}
local C = Paper.C

function Paper.alpha(c, a) return { c[1], c[2], c[3], a } end
function Paper.mix(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, (a[4] or 1) + ((b[4] or 1) - (a[4] or 1)) * t } end
function Paper.dark(c, k) k = k or 0.7; return { c[1] * k, c[2] * k, c[3] * k * 1.05, c[4] } end
function Paper.light(c, k) k = k or 0.3; return { c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k, c[4] } end

local function noise(seed, i)
    local x = math.sin(seed * 12.9898 + i * 78.233) * 43758.5453
    return (x - math.floor(x)) * 2 - 1
end
Paper.noise = noise

local cache = {}

local function roundRectBase(w, h, r)
    r = math.min(r, w / 2 - 1, h / 2 - 1)
    local pts = {}
    local function arc(cx, cy, a0)
        for i = 0, 5 do
            local a = a0 + (i / 5) * math.pi / 2
            pts[#pts + 1] = cx + math.cos(a) * r
            pts[#pts + 1] = cy + math.sin(a) * r
        end
    end
    local function edge(x0, y0, x1, y1)
        local len = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
        local n = math.floor(len / 36)
        for i = 1, n do
            local t = i / (n + 1)
            pts[#pts + 1] = x0 + (x1 - x0) * t
            pts[#pts + 1] = y0 + (y1 - y0) * t
        end
    end
    arc(w - r, r, -math.pi / 2); edge(w, r, w, h - r)
    arc(w - r, h - r, 0); edge(w - r, h, r, h)
    arc(r, h - r, math.pi / 2); edge(0, h - r, 0, r)
    arc(r, r, math.pi); edge(r, 0, w - r, 0)
    return pts
end

local function build(pts, cx, cy, seed, jit)
    local n = #pts / 2
    for i = 1, n do
        pts[2 * i - 1] = pts[2 * i - 1] + noise(seed, i * 2) * jit
        pts[2 * i] = pts[2 * i] + noise(seed, i * 2 + 1) * jit
    end
    local verts = { { cx, cy, 0, 0, 1, 1, 1, 1 } }
    for i = 1, n do verts[#verts + 1] = { pts[2 * i - 1], pts[2 * i], 0, 0, 1, 1, 1, 1 } end
    verts[#verts + 1] = { pts[1], pts[2], 0, 0, 1, 1, 1, 1 }
    local line = {}
    for i = 1, #pts do line[i] = pts[i] end
    line[#line + 1] = pts[1]; line[#line + 1] = pts[2]
    return { mesh = love.graphics.newMesh(verts, "fan", "static"), line = line }
end

local function rectShape(w, h, r, seed, jit)
    w, h = math.floor(w + 0.5), math.floor(h + 0.5)
    local key = w .. "x" .. h .. "r" .. r .. "s" .. seed .. "j" .. jit
    local s = cache[key]
    if not s then s = build(roundRectBase(w, h, r), w / 2, h / 2, seed, jit); cache[key] = s end
    return s
end

local function discShape(r, seed, jit)
    local key = "d" .. math.floor(r * 10) .. "s" .. seed .. "j" .. jit
    local s = cache[key]
    if not s then
        local pts, n = {}, math.max(14, math.floor(r * 0.9))
        for i = 0, n - 1 do
            local a = i / n * math.pi * 2
            pts[#pts + 1] = math.cos(a) * r
            pts[#pts + 1] = math.sin(a) * r
        end
        s = build(pts, 0, 0, seed, jit)
        cache[key] = s
    end
    return s
end

--- A sheet of paper. o: fill, line (width), r (corner), seed, jitter, rot (radians), shadow (default true), tape
function Paper.panel(x, y, w, h, o)
    o = o or {}
    local sh = rectShape(w, h, o.r or 18, o.seed or 1, o.jitter or 2.2)
    love.graphics.push()
    love.graphics.translate(x + w / 2, y + h / 2)
    if o.rot then love.graphics.rotate(o.rot) end
    love.graphics.translate(-w / 2, -h / 2)
    if o.shadow ~= false then
        love.graphics.push(); love.graphics.translate(5, 7)
        love.graphics.setColor(C.ink[1], C.ink[2], C.ink[3], 0.35)
        love.graphics.draw(sh.mesh)
        love.graphics.pop()
    end
    local fill = o.fill or C.cream
    love.graphics.setColor(fill[1], fill[2], fill[3], fill[4] or 1)
    love.graphics.draw(sh.mesh)
    if o.shade ~= false then
        local d = Paper.dark(fill, 0.86)
        love.graphics.setColor(d[1], d[2], d[3], (fill[4] or 1) * 0.55)
        love.graphics.setLineWidth(6)
        love.graphics.line(w * 0.1, h - 5, w * 0.9, h - 5)
    end
    love.graphics.setLineWidth(o.line or 4)
    love.graphics.setLineJoin("bevel")
    love.graphics.setColor(C.ink[1], C.ink[2], C.ink[3], o.lineAlpha or 1)
    love.graphics.line(sh.line)
    if o.tape then
        love.graphics.setColor(1, 0.85, 0.3, 0.85)
        for i = 0, 1 do
            love.graphics.push()
            love.graphics.translate(i == 0 and 18 or w - 18, 2)
            love.graphics.rotate(i == 0 and -0.5 or 0.5)
            love.graphics.rectangle("fill", -22, -9, 44, 18)
            love.graphics.setColor(C.ink[1], C.ink[2], C.ink[3], 0.5)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", -22, -9, 44, 18)
            love.graphics.pop()
            love.graphics.setColor(1, 0.85, 0.3, 0.85)
        end
    end
    love.graphics.pop()
end

--- A wobbly disc centred on (x, y).
function Paper.disc(x, y, r, fill, o)
    o = o or {}
    local sh = discShape(r, o.seed or 1, o.jitter or 1.2)
    love.graphics.push()
    love.graphics.translate(x, y)
    if o.shadow then
        love.graphics.setColor(C.ink[1], C.ink[2], C.ink[3], 0.35)
        love.graphics.push(); love.graphics.translate(3, 4); love.graphics.draw(sh.mesh); love.graphics.pop()
    end
    love.graphics.setColor(fill[1], fill[2], fill[3], fill[4] or 1)
    love.graphics.draw(sh.mesh)
    if o.line ~= 0 then
        love.graphics.setLineWidth(o.line or 3.5)
        love.graphics.setLineJoin("bevel")
        love.graphics.setColor(C.ink[1], C.ink[2], C.ink[3], o.lineAlpha or 1)
        love.graphics.line(sh.line)
    end
    love.graphics.pop()
end

local heartPts
local function heartShape()
    if heartPts then return heartPts end
    local pts = {}
    for i = 0, 23 do
        local t = i / 24 * math.pi * 2
        local x = 16 * math.sin(t) ^ 3
        local y = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t))
        pts[#pts + 1] = x / 17
        pts[#pts + 1] = y / 17
    end
    local verts = { { 0, 0, 0, 0, 1, 1, 1, 1 } }
    for i = 1, #pts, 2 do verts[#verts + 1] = { pts[i], pts[i + 1], 0, 0, 1, 1, 1, 1 } end
    verts[#verts + 1] = { pts[1], pts[2], 0, 0, 1, 1, 1, 1 }
    local line = {}
    for i = 1, #pts do line[i] = pts[i] end
    line[#line + 1] = pts[1]; line[#line + 1] = pts[2]
    heartPts = { mesh = love.graphics.newMesh(verts, "fan", "static"), line = line }
    return heartPts
end

function Paper.heart(x, y, size, fill, empty)
    local h = heartShape()
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.scale(size, size)
    love.graphics.setColor(empty and { 0.3, 0.2, 0.35, 0.5 } or fill or C.red)
    love.graphics.draw(h.mesh)
    love.graphics.setLineWidth(3 / size)
    love.graphics.setColor(C.ink)
    love.graphics.line(h.line)
    love.graphics.pop()
end

--- Dotted line with an arrow head. pts = { {x,y}, ... } (virtual px). o: color, alpha, width, spacing, head
function Paper.arrow(pts, o)
    o = o or {}
    local col = o.color or C.teal
    local a = o.alpha or 1
    local width, spacing = o.width or 7, o.spacing or 16
    if #pts < 2 then return end
    local carry = 0
    local lx, ly = pts[1][1], pts[1][2]
    love.graphics.setLineWidth(1)
    for i = 2, #pts do
        local x1, y1 = pts[i][1], pts[i][2]
        local dx, dy = x1 - lx, y1 - ly
        local len = math.sqrt(dx * dx + dy * dy)
        local d = spacing - carry
        while d <= len do
            local t = d / len
            local px, py = lx + dx * t, ly + dy * t
            love.graphics.setColor(C.ink[1], C.ink[2], C.ink[3], a)
            love.graphics.circle("fill", px, py, width * 0.5 + 2)
            love.graphics.setColor(col[1], col[2], col[3], a)
            love.graphics.circle("fill", px, py, width * 0.5)
            d = d + spacing
        end
        carry = len - (d - spacing)
        lx, ly = x1, y1
    end
    -- arrow head
    local px, py = pts[#pts - 1][1], pts[#pts - 1][2]
    local ex, ey = pts[#pts][1], pts[#pts][2]
    local ang = math.atan2(ey - py, ex - px)
    local hs = o.head or 17
    local function tri(s, c)
        love.graphics.setColor(c)
        love.graphics.polygon("fill",
            ex + math.cos(ang) * (hs + s), ey + math.sin(ang) * (hs + s),
            ex + math.cos(ang + 2.4) * (hs + s), ey + math.sin(ang + 2.4) * (hs + s),
            ex + math.cos(ang - 2.4) * (hs + s), ey + math.sin(ang - 2.4) * (hs + s))
    end
    tri(4, { C.ink[1], C.ink[2], C.ink[3], a })
    tri(0, { col[1], col[2], col[3], a })
end

return Paper
