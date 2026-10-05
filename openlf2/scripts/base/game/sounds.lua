-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local sounds = {}

local function cdiv(a, b)
    local q = a / b
    if q >= 0 then return math.floor(q) end
    return math.ceil(q)
end

local fixed = {[0] = "data/001.wav", "data/002.wav", "data/006.wav", "data/010.wav",
    "data/011.wav", "data/004.wav", "data/016.wav", "data/017.wav", "data/020.wav",
    "data/021.wav", "data/025.wav", "data/032.wav", "data/033.wav", "data/039.wav",
    "data/065.wav", "data/066.wav", "data/068.wav", "data/085.wav"}
sounds.fixed_files = fixed
-- Pan and volume each sound buffer last accepted; buffers persist for the whole session.
local last_pan = {}
local last_volume = {}

sounds.menu = {join = "data/m_join.wav", ok = "data/m_ok.wav", cancel = "data/m_cancel.wav",
    pass = "data/m_pass.wav", finish = "data/m_end.wav"}

-- Data files write Windows paths; resources use lowercase forward slashes.
function sounds.canonical(path)
    return (path:lower():gsub("\\", "/"))
end

-- Two "ears" 200 and 600 px right of the camera hear a sound fully within 200 px, fading to
-- nothing at 400 px.
local function ears(camera, x)
    local offset = x - camera
    local function hear(distance)
        distance = math.abs(distance)
        if distance < 200 then return 100 end
        if distance < 400 then return cdiv((400 - distance) * 100, 200) end
        return 0
    end
    return hear(offset - 200), hear(offset - 600)
end

local function queue(state, bank, key, x)
    state.sound_queue = state.sound_queue or {}
    local channel = state.sound_queue[bank .. key]
    if not channel then
        channel = {bank = bank, resource = bank == "fixed" and fixed[key] or key, left = 0, right = 0}
        state.sound_queue[bank .. key] = channel
        state.sound_order = state.sound_order or {}
        state.sound_order[#state.sound_order + 1] = channel
    end
    local left, right = ears(state.camera or 0, x)
    channel.left = channel.left + left
    channel.right = channel.right + right
end

function sounds.item(state, x, path)
    if path then queue(state, "item", sounds.canonical(path), x) end
end

function sounds.effect(state, x, channel)
    if fixed[channel] then queue(state, "fixed", channel, x) end
end

function sounds.buffer_play(channel)
    local resource = fixed[channel]
    return {resource = resource, volume = last_volume[resource] or 0, pan = last_pan[resource] or 0}
end

-- Menu and jingle sounds play at once without panning, at the master volume.
function sounds.direct(state, name)
    state.direct_sounds = state.direct_sounds or {}
    state.direct_sounds[#state.direct_sounds + 1] = sounds.menu[name]
end

function sounds.flush(state, master)
    master = master or require("base/game/music").master
    local output = {}
    for _, resource in ipairs(state.direct_sounds or {}) do
        -- A ready command (sounds.buffer_play) keeps its own volume and pan.
        if type(resource) == "table" then output[#output + 1] = resource
        elseif master > 0 then output[#output + 1] = {resource = resource, pan = 0, volume = cdiv((master - 100) * 3800, 100)} end
    end
    state.direct_sounds = nil
    local order = state.sound_order or {}
    for _, bank in ipairs({"item", "fixed"}) do
        for _, channel in ipairs(order) do
            if channel.bank == bank then
                local strength = math.min(channel.left + channel.right, 100)
                if strength > 0 and master > 0 then
                    -- Ear totals can exceed 100 each; DirectSound rejects a pan outside +/-10000
                    -- and the buffer keeps the pan it had (assumed from the API contract).
                    local pan = cdiv((channel.right - channel.left) * 1500, 100)
                    if pan < -10000 or pan > 10000 then pan = last_pan[channel.resource] or 0 end
                    last_pan[channel.resource] = pan
                    local volume = cdiv((master - 100) * 3800, 100) + cdiv((strength - 100) * 2000, 100)
                    last_volume[channel.resource] = volume
                    output[#output + 1] = {resource = channel.resource, pan = pan, volume = volume}
                end
            end
        end
    end
    state.sound_queue, state.sound_order = nil, nil
    return output
end
return sounds
