-- Where things are on the screen. The board is a square of 552 virtual px whatever its size in tiles.

local G = { size = 552, cx = 800, top = 150 }

function G.setup(n)
    G.n = n
    G.T = G.size / n
    G.x = G.cx - G.size / 2
    G.y = G.top
    G.unit = G.T / 100       -- 1.0 when a tile is 100 px
end

--- Pixel centre of tile (tx, ty); ty = 1 is the bottom row. Fractional coordinates are fine.
function G.center(tx, ty)
    return G.x + (tx - 0.5) * G.T, G.y + (G.n - ty + 0.5) * G.T
end

--- Where a bug's feet touch the ground when it stands on the tile.
function G.foot(tx, ty)
    local x, y = G.center(tx, ty)
    return x, y + G.T * 0.3
end

--- Tile under a pixel, or nil.
function G.tileAt(px, py)
    local fx, fy = (px - G.x) / G.T, (py - G.y) / G.T
    if fx < 0 or fy < 0 or fx >= G.n or fy >= G.n then return nil end
    return math.floor(fx) + 1, G.n - math.floor(fy)
end

return G
