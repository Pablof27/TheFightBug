-- Minimal pure-Lua JSON decoder (encode + decode).
-- Based on rxi/json.lua (MIT License) — adapted for LÖVE / Lua 5.1.
-- Only the decode path is needed by SpriteSheetManager, but encode is
-- included for completeness (useful for save-game serialisation later).

local json = {}

-- ─── Decode ──────────────────────────────────────────────────────────────────

local function createSet(list)
    local set = {}
    for _, v in ipairs(list) do set[v] = true end
    return set
end

local escapes = {
    ["\""] = "\"", ["\\"] = "\\", ["/"] = "/",
    ["n"]  = "\n", ["r"]  = "\r", ["t"]  = "\t",
    ["b"]  = "\b", ["f"]  = "\f",
}

local function parseError(str, idx, msg)
    local line = 1
    for i = 1, idx do
        if str:sub(i, i) == "\n" then line = line + 1 end
    end
    error(string.format("JSON parse error at line %d: %s", line, msg))
end

local function skipWhitespace(str, idx)
    return str:match("^%s*()", idx)
end

local parseValue  -- forward declaration
local utf8char    -- forward declaration (defined below)

local function parseString(str, idx)
    local res = ""
    idx = idx + 1  -- skip opening "
    while true do
        local c = str:sub(idx, idx)
        if c == "" then parseError(str, idx, "unexpected end of string") end
        if c == "\"" then return res, idx + 1 end
        if c == "\\" then
            local esc = str:sub(idx + 1, idx + 1)
            if esc == "u" then
                local code = tonumber(str:sub(idx + 2, idx + 5), 16)
                if not code then parseError(str, idx, "invalid unicode escape") end
                res = res .. utf8char(code)
                idx = idx + 6
            else
                local ch = escapes[esc]
                if not ch then parseError(str, idx, "invalid escape '\\"..esc.."'") end
                res = res .. ch
                idx = idx + 2
            end
        else
            res = res .. c
            idx = idx + 1
        end
    end
end

-- Fallback utf8 char builder (works on Lua 5.1 / LuaJIT without utf8 lib)
utf8char = function(code)
    if code < 0x80 then
        return string.char(code)
    elseif code < 0x800 then
        return string.char(0xC0 + math.floor(code / 0x40),
                           0x80 + code % 0x40)
    elseif code < 0x10000 then
        return string.char(0xE0 + math.floor(code / 0x1000),
                           0x80 + math.floor(code / 0x40) % 0x40,
                           0x80 + code % 0x40)
    end
    return "?"
end

local function parseNumber(str, idx)
    local num, endIdx = str:match("^(-?%d+%.?%d*[eE]?[+-]?%d*)()", idx)
    if not num then parseError(str, idx, "invalid number") end
    return tonumber(num), endIdx
end

local function parseArray(str, idx)
    local arr = {}
    idx = skipWhitespace(str, idx + 1)
    if str:sub(idx, idx) == "]" then return arr, idx + 1 end
    while true do
        local val
        val, idx = parseValue(str, idx)
        arr[#arr + 1] = val
        idx = skipWhitespace(str, idx)
        local ch = str:sub(idx, idx)
        if ch == "]" then return arr, idx + 1 end
        if ch ~= "," then parseError(str, idx, "expected ',' or ']'") end
        idx = skipWhitespace(str, idx + 1)
    end
end

local function parseObject(str, idx)
    local obj = {}
    idx = skipWhitespace(str, idx + 1)
    if str:sub(idx, idx) == "}" then return obj, idx + 1 end
    while true do
        if str:sub(idx, idx) ~= "\"" then
            parseError(str, idx, "expected string key")
        end
        local key
        key, idx = parseString(str, idx)
        idx = skipWhitespace(str, idx)
        if str:sub(idx, idx) ~= ":" then
            parseError(str, idx, "expected ':' after key")
        end
        idx = skipWhitespace(str, idx + 1)
        local val
        val, idx = parseValue(str, idx)
        obj[key] = val
        idx = skipWhitespace(str, idx)
        local ch = str:sub(idx, idx)
        if ch == "}" then return obj, idx + 1 end
        if ch ~= "," then parseError(str, idx, "expected ',' or '}'") end
        idx = skipWhitespace(str, idx + 1)
    end
end

parseValue = function(str, idx)
    idx = skipWhitespace(str, idx)
    local ch = str:sub(idx, idx)
    if ch == "\"" then return parseString(str, idx)
    elseif ch == "{" then return parseObject(str, idx)
    elseif ch == "[" then return parseArray(str, idx)
    elseif ch == "t" then
        if str:sub(idx, idx + 3) == "true"  then return true,  idx + 4 end
    elseif ch == "f" then
        if str:sub(idx, idx + 4) == "false" then return false, idx + 5 end
    elseif ch == "n" then
        if str:sub(idx, idx + 3) == "null"  then return nil,   idx + 4 end
    elseif ch == "-" or ch:match("%d") then
        return parseNumber(str, idx)
    end
    parseError(str, idx, "unexpected character '" .. ch .. "'")
end

--- Decode a JSON string into a Lua value.
function json.decode(str)
    assert(type(str) == "string", "json.decode: argument must be a string")
    local val, _ = parseValue(str, 1)
    return val
end

-- ─── Encode ──────────────────────────────────────────────────────────────────

local encodeValue  -- forward declaration

local function encodeString(s)
    return '"' .. s:gsub('[\\"]', '\\%0')
                   :gsub('\n', '\\n')
                   :gsub('\r', '\\r')
                   :gsub('\t', '\\t') .. '"'
end

local function encodeTable(t, indent, step)
    -- detect array vs object
    local isArray = true
    local n = 0
    for k in pairs(t) do
        n = n + 1
        if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
            isArray = false
        end
    end
    if isArray and n ~= #t then isArray = false end

    local parts = {}
    if isArray then
        for _, v in ipairs(t) do
            parts[#parts + 1] = encodeValue(v, indent + step, step)
        end
        return "[" .. table.concat(parts, ",") .. "]"
    else
        for k, v in pairs(t) do
            if type(k) == "string" then
                parts[#parts + 1] = encodeString(k) .. ":" .. encodeValue(v, indent + step, step)
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
end

encodeValue = function(v, indent, step)
    local t = type(v)
    if t == "string"  then return encodeString(v)
    elseif t == "number"  then return tostring(v)
    elseif t == "boolean" then return tostring(v)
    elseif t == "table"   then return encodeTable(v, indent or 0, step or 0)
    elseif t == "nil"     then return "null"
    else error("json.encode: unsupported type '" .. t .. "'") end
end

--- Encode a Lua value as a JSON string.
function json.encode(val)
    return encodeValue(val, 0, 0)
end

return json
