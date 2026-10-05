-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local sounds = require("base/game/sounds")
local unlock = {}

unlock.flags = {characters = 0, function_keys = 0}

-- Virtual-key codes of each word (0xbe is the period key) with its record bit, flag and buffer.
local words = {
    {keys = {0x4c, 0x46, 0x32, 0xbe, 0x4e, 0x45, 0x54}, bit = 1, flag = "characters", buffer = 3},
    {keys = {0x48, 0x45, 0x52, 0x4f, 0x46, 0x49, 0x47, 0x48, 0x54, 0x45, 0x52, 0xbe, 0x43, 0x4f, 0x4d},
        bit = 2, flag = "function_keys", buffer = 4},
}
local progress = {0, 0}
-- Marks waiting for the next frame that takes them (the key table's 'd' at 0xf9 / 0xf8).
local marked = {}
-- Held keys of the previous trace frame, to turn traces' held "#n" keys into key-downs.
local previous_keys = {}

-- One key-down: the next letter advances; repeating the previous letter keeps place; anything
-- else restarts. The last letter marks the word and keeps place, so repeating it marks again.
local function key_down(code)
    for index, word in ipairs(words) do
        local place = progress[index]
        if code == word.keys[place + 1] then
            if place + 1 == #word.keys then marked[word.bit] = true
            else progress[index] = place + 1 end
        elseif place == 0 or code ~= word.keys[place] then
            progress[index] = 0
        end
    end
end

-- Flips a flag and returns the sound command of its buffer.
local function toggle(word)
    unlock.flags[word.flag] = 1 - unlock.flags[word.flag]
    return sounds.buffer_play(word.buffer)
end

-- Feeds one frame's input (base/ui/controls): live key-downs in order, or for traces the keys
-- newly held since the previous frame in code order.
function unlock.observe(input)
    local presses = input.presses
    if not presses then
        presses = {}
        for code = 0, 255 do
            if input.keys[code] and not previous_keys[code] then presses[#presses + 1] = code end
        end
        previous_keys = {}
        for code in pairs(input.keys) do previous_keys[code] = true end
    end
    for _, code in ipairs(presses) do key_down(code) end
end

function unlock.take_pending()
    local bits = 0
    for _, word in ipairs(words) do
        if marked[word.bit] then marked[word.bit] = nil; bits = bits + word.bit end
    end
    return bits
end
function unlock.take_marks()
    local bits = unlock.take_pending()
    return bits, unlock.apply_recorded(bits)
end

-- A new network session starts with equal flags and empty word recognizers on both peers.
function unlock.reset_session()
    unlock.end_replay()
    unlock.flags.characters, unlock.flags.function_keys = 0, 0
    progress, marked, previous_keys = {0, 0}, {}, {}
end

-- A replay frame's recorded bits (byte 9 of the record) toggle the flags instead.
function unlock.apply_recorded(bits)
    local played = {}
    for _, word in ipairs(words) do
        if math.floor(bits / word.bit) % 2 == 1 then played[#played + 1] = toggle(word) end
    end
    return played
end

local saved
function unlock.begin_replay(characters, function_keys)
    saved = {characters = unlock.flags.characters, function_keys = unlock.flags.function_keys}
    unlock.flags.characters, unlock.flags.function_keys = characters, function_keys
end
function unlock.end_replay()
    if saved then unlock.flags.characters, unlock.flags.function_keys = saved.characters, saved.function_keys end
    saved = nil
end

-- For headless descriptions: "characters:function_keys" when either is set.
function unlock.describe()
    if unlock.flags.characters == 0 and unlock.flags.function_keys == 0 then return nil end
    return unlock.flags.characters .. ":" .. unlock.flags.function_keys
end
return unlock
