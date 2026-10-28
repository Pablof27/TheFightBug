-- Loads and owns every resource the game uses (all of it produced by tools/ and exported into resources/).

local json = require("engine.utils.json")
local Atlas = require("client.atlas")
local Bugs = require("data.bugs")

local Assets = { bug = {}, arena = {}, backdrop = {}, sfx = {}, music = {}, fonts = {}, loaded = false }

local ART = "resources/art/"
local AUDIO = "resources/audio/"

local function readJson(path)
    local s = love.filesystem.read(path)
    assert(s, "missing resource " .. path .. " (run: node tools/build.js)")
    return json.decode(s)
end

local function img(path)
    local i = love.graphics.newImage(path, { mipmaps = true })
    i:setFilter("linear", "linear")
    i:setMipmapFilter("linear", 0)
    return i
end

function Assets.load()
    if Assets.loaded then return end
    for id in pairs(Bugs) do
        local meta = readJson(ART .. "bug_" .. id .. ".json")
        Assets.bug[id] = Atlas.new(ART .. "bug_" .. id .. ".png", meta)
    end
    Assets.tiles = Atlas.new(ART .. "tiles.png", readJson(ART .. "tiles.json"))
    Assets.ui = Atlas.new(ART .. "ui.png", readJson(ART .. "ui.json"))
    Assets.people = Atlas.new(ART .. "people.png", readJson(ART .. "people.json"))
    for _, id in ipairs({ "sandbox", "lawn", "stump" }) do
        Assets.arena[id] = { image = img(ART .. "arena_" .. id .. ".png"), meta = readJson(ART .. "arena_" .. id .. ".json") }
    end
    for _, id in ipairs({ "sandbox", "lawn", "stump", "title", "map" }) do Assets.backdrop[id] = img(ART .. "backdrop_" .. id .. ".png") end
    Assets.logo = img(ART .. "logo.png")

    -- display font: hand-lettered, uppercase only. The tool tells us which characters are in the strip.
    local fmeta = readJson(ART .. "font_display.json")
    local fimg = love.image.newImageData(ART .. "font_display.png")
    Assets.fonts.display = love.graphics.newImageFont(fimg, fmeta.chars)
    Assets.fonts.display:setFilter("linear", "linear")
    Assets.fonts.displayMeta = fmeta

    for _, f in ipairs(love.filesystem.getDirectoryItems(AUDIO)) do
        local name = f:match("^sfx_(.+)%.wav$")
        if name then Assets.sfx[name] = love.audio.newSource(AUDIO .. f, "static") end
        local m = f:match("^music_(.+)%.wav$")
        if m then
            local s = love.audio.newSource(AUDIO .. f, "stream")
            s:setLooping(true)
            Assets.music[m] = s
        end
    end
    Assets.loaded = true
end

--- A sprite frame of a species: Assets.bugFrame("ant", "walk", 3) -> frame name
function Assets.animFrame(species, anim, index)
    local list = Assets.bug[species].meta.anims[anim]
    return list[((index - 1) % #list) + 1]
end

local portraitQuads = {}

--- Draws the face of a species (a crop of its idle frame) as a square of `size` px centred on (x, y).
function Assets.drawPortrait(species, x, y, size, noclip)
    local atlas = Assets.bug[species]
    local q = portraitQuads[species]
    if not q then
        local f = atlas.frames.idle1
        local h = atlas.meta.head or { x = 128, y = 120, r = 70 }
        local iw, ih = atlas.image:getDimensions()
        q = love.graphics.newQuad(f.x + h.x - h.r, f.y + h.y - h.r, h.r * 2, h.r * 2, iw, ih)
        portraitQuads[species] = q
    end
    local h = atlas.meta.head or { r = 70 }
    -- the crop is a square; most limbs would show its flat edges, so it is clipped to a circle
    if not noclip then
        love.graphics.stencil(function() love.graphics.circle("fill", x, y, size * 0.5, 28) end, "replace", 1)
        love.graphics.setStencilTest("greater", 0)
    end
    love.graphics.draw(atlas.image, q, x, y, 0, size / (h.r * 2), size / (h.r * 2), h.r, h.r)
    if not noclip then love.graphics.setStencilTest() end
end

local facePortraits = {}

--- The face of a rival kid (head and shoulders crop of the portrait), centred on (x, y).
function Assets.drawKid(name, mood, x, y, size)
    local key = name .. "_" .. mood
    local f = Assets.people.frames[key]
    if not f then return end
    love.graphics.draw(Assets.people.image, Assets.people.quads[key], x, y, 0, size / f.w, size / f.h, f.w / 2, f.h / 2)
end

return Assets
