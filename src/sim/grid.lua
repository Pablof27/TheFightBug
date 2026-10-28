-- Grid helpers. Columns A..F are x = 1..6 (left to right); rows are y = 1..6 with row 1 at the BOTTOM of the screen
-- (the kid's side) and row 6 at the top (the rival's side), exactly like the GDD diagrams.

local Grid = {}

-- "up" is towards the rival (y + 1)
Grid.DIRS = {
    { name = "up",    dx = 0,  dy = 1 },
    { name = "right", dx = 1,  dy = 0 },
    { name = "down",  dx = 0,  dy = -1 },
    { name = "left",  dx = -1, dy = 0 },
}

function Grid.key(x, y) return y * 16 + x end

function Grid.name(x, y) return string.char(64 + x) .. y end

function Grid.manhattan(ax, ay, bx, by) return math.abs(ax - bx) + math.abs(ay - by) end

-- Timeline reading order: top-left first (higher row first, then column). Lower value acts first.
function Grid.reading(x, y) return (100 - y) * 100 + x end

-- returns the cell table or nil when (x, y) is outside the board. Void cells exist but have .void = true.
function Grid.cell(state, x, y)
    if x < 1 or y < 1 or x > state.w or y > state.h then return nil end
    return state.cells[y * 16 + x]
end

function Grid.isHomeRow(state, side, y)
    if side == "kid" then return y <= 2 end
    return y >= state.h - 1
end

-- the way a side faces: the kid pushes up the board, the rival down
function Grid.forward(side) return side == "kid" and 1 or -1 end

function Grid.adjacent(ax, ay, bx, by) return math.abs(ax - bx) + math.abs(ay - by) == 1 end

return Grid
