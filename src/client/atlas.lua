-- Texture atlas: one image + named rectangles (+ pivots), as exported by the workshop tools.

local Atlas = {}
Atlas.__index = Atlas

--- imagePath: png; meta: decoded json ({ frames = { name = {x,y,w,h,px,py} }, pivot = {px,py}, scale = n })
function Atlas.new(imagePath, meta)
    local img = love.graphics.newImage(imagePath, { mipmaps = true })
    img:setFilter("linear", "linear")
    img:setMipmapFilter("linear", 0)
    local a = setmetatable({ image = img, frames = meta.frames or {}, quads = {}, meta = meta }, Atlas)
    local iw, ih = img:getDimensions()
    for name, f in pairs(a.frames) do
        a.quads[name] = love.graphics.newQuad(f.x, f.y, f.w, f.h, iw, ih)
        if f.px == nil and meta.pivot then f.px, f.py = meta.pivot[1], meta.pivot[2] end
        f.px = f.px or f.w / 2
        f.py = f.py or f.h / 2
    end
    return a
end

function Atlas:has(name) return self.quads[name] ~= nil end

--- Draws frame `name` with its pivot at (x, y). sx/sy scale, r rotation (radians).
function Atlas:draw(name, x, y, r, sx, sy)
    local q, f = self.quads[name], self.frames[name]
    if not q then return end
    sx = sx or 1
    love.graphics.draw(self.image, q, x, y, r or 0, sx, sy or sx, f.px, f.py)
end

--- Draws frame `name` centred in the box (x, y, w, h), scaled to fit.
function Atlas:drawFit(name, x, y, w, h, r)
    local f = self.frames[name]
    if not f then return end
    local s = math.min(w / f.w, h / f.h)
    love.graphics.draw(self.image, self.quads[name], x + w / 2, y + h / 2, r or 0, s, s, f.w / 2, f.h / 2)
end

function Atlas:size(name)
    local f = self.frames[name]
    return f.w, f.h
end

return Atlas
