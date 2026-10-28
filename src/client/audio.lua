-- Sound: pooled one-shot effects with a little pitch jitter, and one looping music track at a time.

local Assets = require("client.assets")

local Audio = { sfxVolume = 0.85, musicVolume = 0.45, muted = false, current = nil, fade = nil }

local active = {}

function Audio.play(name, vol, pitch)
    if Audio.muted then return end
    local tpl = Assets.sfx[name]
    if not tpl then return end
    local s = tpl:clone()
    s:setVolume((vol or 1) * Audio.sfxVolume)
    s:setPitch((pitch or 1) * (0.96 + love.math.random() * 0.08))
    s:play()
    active[#active + 1] = s
    if #active > 48 then
        for i = #active, 1, -1 do if not active[i]:isPlaying() then table.remove(active, i) end end
    end
end

function Audio.music(name)
    if Audio.currentName == name then return end
    local prev = Audio.current
    Audio.currentName = name
    Audio.current = name and Assets.music[name] or nil
    if Audio.current then
        Audio.current:setVolume(0)
        if not Audio.muted then Audio.current:play() end
    end
    Audio.fade = { from = prev, to = Audio.current, t = 0 }
end

function Audio.update(dt)
    local f = Audio.fade
    if f then
        f.t = f.t + dt
        local k = math.min(1, f.t / 1.2)
        local target = Audio.muted and 0 or Audio.musicVolume
        if f.to then f.to:setVolume(target * k) end
        if f.from and f.from ~= f.to then
            f.from:setVolume(target * (1 - k))
            if k >= 1 then f.from:stop() end
        end
        if k >= 1 then Audio.fade = nil end
    end
end

function Audio.toggleMute()
    Audio.muted = not Audio.muted
    if Audio.current then
        if Audio.muted then Audio.current:pause() else Audio.current:setVolume(Audio.musicVolume); Audio.current:play() end
    end
end

return Audio
