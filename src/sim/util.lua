-- Small shared helpers for the simulation. Plain Lua 5.1 compatible (runs on LuaJIT/LÖVE and on stock Lua for tests).

local U = {}

U.unpack = table.unpack or unpack

-- deep copy of plain data (no metatables, no cycles)
function U.clone(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = U.clone(x) end
    return t
end

function U.copyArray(a)
    local t = {}
    for i = 1, #a do t[i] = a[i] end
    return t
end

function U.sign(n) if n > 0 then return 1 elseif n < 0 then return -1 else return 0 end end
function U.clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end

-- Park–Miller generator stored as a plain number on the state so that clones replay identically.
function U.rand(state, n)
    state.rng = (state.rng * 48271) % 2147483647
    return (state.rng % n) + 1
end

function U.shuffle(state, list)
    for i = #list, 2, -1 do
        local j = U.rand(state, i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

function U.seedOf(str)
    local h = 5381
    for i = 1, #str do h = (h * 33 + str:byte(i)) % 2147483646 end
    return h + 1
end

return U
