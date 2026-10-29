-- A bug as seen on the board: the simulation says where it is, the actor decides how it looks while getting there.
-- Everything here is cosmetic; the Director moves actors around by replaying simulation events.

local Assets = require("client.assets")
local Paper = require("client.paper")
local Text = require("client.text")
local G = require("client.fight.geometry")

local Actor = {}
Actor.__index = Actor

-- sprite height in tiles (for badges and flipped bugs)
local HEIGHT = { ant = 0.6, redant = 0.6, pillbug = 0.62, stag = 0.9, hercules = 1.0, mantis = 1.2, spider = 0.7, cricket = 0.95, wasp = 1.25 }
local FLYING = { wasp = true }

function Actor.new(bug)
    local a = setmetatable({}, Actor)
    a.id, a.species, a.side = bug.id, bug.species, bug.side
    a.x, a.y = bug.x, bug.y
    a.facing = bug.side == "kid" and 1 or -1
    a.z, a.sx, a.sy, a.rot, a.alpha = 0, 1, 1, 0, 1
    a.offx, a.offy = 0, 0
    a.hopH, a.hopT = 0, 0
    a.anim, a.animT, a.animLock = "idle", love.math.random() * 4, 0
    a.actPhase = false
    a.flash, a.flashColor = 0, { 1, 1, 1 }
    a.pulse = 0
    a.spin = 0
    a.gone = false
    a:sync(bug)
    return a
end

--- Copies the numbers that matter from the simulation (used after every playback so nothing can drift).
function Actor:sync(bug)
    self.hp, self.maxHp, self.timer, self.baseTimer = bug.hp, bug.maxHp, bug.timer, bug.baseTimer
    self.ready, self.curled, self.flipped, self.soaked = bug.ready, bug.curled, bug.flipped, bug.soaked
    self.carrying = bug.carrying ~= nil
    self.hiddenFlag = bug.hiddenFlag
end

function Actor:place(x, y)
    self.x, self.y = x, y
end

function Actor:setAnim(name, seconds)
    self.anim = name
    self.animLock = seconds or 0
    self.animT = 0
end

function Actor:face(fromX, toX)
    if toX > fromX + 0.01 then self.facing = 1 elseif toX < fromX - 0.01 then self.facing = -1 end
end

function Actor:flashNow(color, amount)
    self.flash = amount or 1
    self.flashColor = color or { 1, 1, 1 }
end

function Actor:update(dt)
    self.animT = self.animT + dt
    if self.animLock > 0 then
        self.animLock = self.animLock - dt
        if self.animLock <= 0 then self.anim = "idle" end
    end
    if self.flash > 0 then self.flash = math.max(0, self.flash - dt * 4) end
    if self.pulse > 0 then self.pulse = math.max(0, self.pulse - dt * 3) end
    self.rot = self.rot + self.spin * dt
end

function Actor:height() return (HEIGHT[self.species] or 0.8) end

function Actor:isFlying() return FLYING[self.species] end

function Actor:frameName()
    local meta = Assets.bug[self.species].meta
    local anims = meta.anims
    if self.curled and self.species == "pillbug" then return "alt" end
    local anim = self.anim
    if self.species == "wasp" and anim == "idle" then anim = "walk" end
    if anim == "walk" then
        local rate = self.species == "wasp" and 9 or 10
        return anims.walk[math.floor(self.animT * rate) % 4 + 1]
    elseif anim == "act" then
        return self.actPhase and "act2" or "act1"
    elseif anim == "hurt" then
        return "hurt"
    elseif anim == "alt" then
        return "alt"
    end
    if self.ready and self.species == "mantis" then return "act1" end
    return anims.idle[math.floor(self.animT * 3.2) % #anims.idle + 1]
end

--- Ground shadow + team marker. Drawn for every actor before any sprite so nothing is hidden by a neighbour's shadow.
function Actor:drawGround()
    local fx, fy = G.foot(self.x, self.y)
    fx, fy = fx + self.offx, fy + self.offy
    local T = G.T
    local a = self.alpha
    -- team marker: kids stand on a round teal cap, rivals on a magenta diamond (colour AND shape)
    if self.side == "kid" then
        love.graphics.setColor(Paper.C.ink[1], Paper.C.ink[2], Paper.C.ink[3], 0.55 * a)
        love.graphics.ellipse("fill", fx, fy + 3, T * 0.36, T * 0.15)
        love.graphics.setColor(Paper.C.teal[1], Paper.C.teal[2], Paper.C.teal[3], a)
        love.graphics.ellipse("fill", fx, fy, T * 0.34, T * 0.135)
        love.graphics.setColor(1, 1, 1, 0.65 * a)
        love.graphics.setLineWidth(2)
        love.graphics.ellipse("line", fx, fy, T * 0.27, T * 0.1)
    else
        local rx, ry = T * 0.36, T * 0.16
        love.graphics.setColor(Paper.C.ink[1], Paper.C.ink[2], Paper.C.ink[3], 0.55 * a)
        love.graphics.polygon("fill", fx, fy - ry + 3, fx + rx, fy + 3, fx, fy + ry + 3, fx - rx, fy + 3)
        love.graphics.setColor(Paper.C.magenta[1], Paper.C.magenta[2], Paper.C.magenta[3], a)
        love.graphics.polygon("fill", fx, fy - ry + 1, fx + rx - 2, fy + 1, fx, fy + ry - 1, fx - rx + 2, fy + 1)
        love.graphics.setColor(1, 1, 1, 0.55 * a)
        love.graphics.setLineWidth(2)
        love.graphics.polygon("line", fx, fy - ry + 5, fx + rx - 10, fy + 1, fx, fy + ry - 4, fx - rx + 10, fy + 1)
    end
    -- soft shadow (smaller when the bug is in the air)
    local lift = self.z + math.sin(math.pi * self.hopT) * self.hopH + (self:isFlying() and 24 * G.unit or 0)
    local k = math.max(0.45, 1 - lift / (T * 1.2))
    love.graphics.setColor(Paper.C.ink[1], Paper.C.ink[2], Paper.C.ink[3], 0.3 * a * k)
    love.graphics.ellipse("fill", fx, fy, T * 0.26 * k, T * 0.09 * k)
end

function Actor:drawSprite(hidden)
    local atlas = Assets.bug[self.species]
    local fx, fy = G.foot(self.x, self.y)
    fx, fy = fx + self.offx, fy + self.offy
    local T, u = G.T, G.unit
    local lift = self.z + math.sin(math.pi * self.hopT) * self.hopH
    if self:isFlying() then lift = lift + 24 * u + math.sin(self.animT * 5 + self.id) * 3 * u end
    local scale = 0.5 * u
    local sx = scale * self.sx * self.facing
    local sy = scale * self.sy
    local rot = self.rot
    local y = fy - lift
    if self.flipped then
        rot = math.pi + math.sin(self.animT * 5) * 0.1
        y = fy - lift - self:height() * T * 0.66
        sx = -sx
    end
    local a = self.alpha * (hidden and 0.5 or 1)
    local frame = self:frameName()
    love.graphics.setColor(1, 1, 1, a)
    atlas:draw(frame, fx, y, rot, sx, sy)
    if self.flash > 0 then
        love.graphics.setBlendMode("add", "alphamultiply")
        local c = self.flashColor
        love.graphics.setColor(c[1] * self.flash, c[2] * self.flash, c[3] * self.flash, a)
        atlas:draw(frame, fx, y, rot, sx, sy)
        love.graphics.setBlendMode("alpha")
    end
    if self.carrying then
        love.graphics.setColor(1, 1, 1, self.alpha)
        Assets.tiles:draw("loot", fx + 4 * u, fy - self:height() * T * 0.95 - lift, 0, T / 200 * 0.55)
    end
end

--- The badge strip on the ground under the bug: [timer] [hearts] [what it will do]. It stays inside the bug's own tile
--- whatever the species' height, so a tall or flying bug never carries its numbers up into the tile above.
function Actor:badgeLayout()
    local fx, fy = G.foot(self.x, self.y)
    fx, fy = fx + self.offx, fy + self.offy
    local T, u = G.T, G.unit
    local n = math.max(1, self.maxHp or 1)
    local hs = 5.8 * u
    local gap = hs * (n >= 5 and 1.8 or 2.05)
    local hw = (n - 1) * gap / 2 + hs
    local r = 13 * u
    local pad = 3 * u
    return { fx = fx, y = fy + T * 0.19, hs = hs, gap = gap, r = r, timerX = fx - hw - pad - r, chipX = fx + hw + pad + r }
end

--- Timer (left of the hearts) and hearts. Drawn after all sprites. The action icon on the right is drawn by intent_view.lua.
function Actor:drawBadges(highlight)
    local L = self:badgeLayout()
    local u = G.unit
    local a = self.alpha
    local col = self.side == "kid" and Paper.C.teal or Paper.C.magenta
    local timer = math.max(0, self.timer or 0)
    local soon = not self.ready and timer == 0       -- acts on the next tick
    local r = L.r * (1 + 0.14 * self.pulse) * (highlight and 1.12 or 1)
    if soon then
        r = r * (1 + 0.06 * math.sin(love.timer.getTime() * 7))
        local yc = Paper.C.yellow
        love.graphics.setColor(Paper.C.ink[1], Paper.C.ink[2], Paper.C.ink[3], 0.9 * a)
        love.graphics.circle("fill", L.timerX, L.y, r + 6.5 * u)
        love.graphics.setColor(yc[1], yc[2], yc[3], a)
        love.graphics.circle("fill", L.timerX, L.y, r + 4.5 * u)
    end
    Paper.disc(L.timerX, L.y, r, { col[1], col[2], col[3], a }, { seed = self.id, shadow = not soon, line = 3 * u })
    local label = self.ready and "!" or tostring(timer)
    local sz = 17 * u
    Text.display(label, L.timerX, L.y - sz / 2, sz, { 1, 1, 1, a }, "center")
    if self.soaked then
        love.graphics.setColor(1, 1, 1, a)
        Assets.ui:draw("fx_drop", L.timerX - r * 0.95, L.y - r * 1.05, 0, 0.17 * u)
    end
    local x0 = L.fx - (self.maxHp - 1) * L.gap / 2
    for i = 1, self.maxHp do
        Paper.heart(x0 + (i - 1) * L.gap, L.y, L.hs, nil, i > self.hp)
    end
end

return Actor
