-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local constants = require("base/game/constants")
local catalog = require("base/game/catalog")
local object_data = require("base/game/object_data")
local recording = {}

local block_size = 0x630e18
local header_size = 0x2b38 -- the checksums end where the frame records begin
local records_offset = 0x2b38
local checksums_offset = 0x14b8
local max_frames = 0x9e33f
local tail_offset = 0x630bb8 -- unlock-flag shadows, author, info and e-mail lines

local function byte_of(value, shift) return math.floor(value / 2 ^ shift) % 256 end
local function to_unsigned(value)
    value = math.floor(value) % 4294967296
    return value
end
-- Little-endian 32-bit integer into a byte table (0-based offsets).
local function put_int(bytes, offset, value)
    local unsigned = to_unsigned(value)
    for index = 0, 3 do bytes[offset + index] = byte_of(unsigned, index * 8) end
end
local function put_text(bytes, offset, text, capacity)
    text = text:sub(1, capacity - 1)
    for index = 1, #text do bytes[offset + index - 1] = text:byte(index) end
    bytes[offset + #text] = 0
end
local function get_int(block, offset)
    local a, b, c, d = block:byte(offset + 1, offset + 4)
    local value = a + b * 256 + c * 65536 + d * 16777216
    if value >= 2147483648 then value = value - 4294967296 end
    return value
end
local function get_text(block, offset, capacity)
    local text = block:sub(offset + 1, offset + capacity)
    local ending = text:find("\0", 1, true)
    return ending and text:sub(1, ending - 1) or text
end
local function bytes_to_string(bytes, first, last)
    local pieces = {}
    for start = first, last, 4096 do
        local chunk = {}
        for offset = start, math.min(last, start + 4095) do chunk[#chunk + 1] = bytes[offset] or 0 end
        pieces[#pieces + 1] = string.char(unpack(chunk))
    end
    return table.concat(pieces)
end

local data_checksum
function recording.data_checksum()
    if data_checksum then return data_checksum end
    local sum = catalog.words_checksum() % 4294967296
    for _, entry in ipairs(catalog.objects().list) do
        sum = (sum + object_data.load(entry.path).token_checksum) % 4294967296
    end
    for _, entry in ipairs(catalog.backgrounds()) do
        sum = (sum + engine.read_background_data(entry.path).token_checksum) % 4294967296
    end
    if sum >= 2147483648 then sum = sum - 4294967296 end
    data_checksum = sum
    return sum
end

local slot_fields = {
    {0x1a8, "team"}, {0x1f0, "record_id"}, {0x238, "present"}, {0x280, "blink"}, {0x2c8, "x_int"},
    {0x310, "y_int"}, {0x358, "z_int"}, {0x3a0, "mp"}, {0x3e8, "owner"}, {0x430, "max_hp"},
    {0x478, "transformed_to"}, {0x4c0, "battle_side"}, {0x508, "armor"},
}

function recording.begin(match_state, setup)
    local header = {}
    put_int(header, 0, setup.difficulty)
    put_int(header, 4, setup.stage_level or 0)
    local unlock = require("base/game/unlock")
    put_int(header, 8, unlock.flags.characters)
    put_int(header, 0xc, unlock.flags.function_keys)
    put_int(header, 0x148, setup.mode)
    for index = 1, 8 do put_text(header, 0x14c + (index - 1) * 11, setup.names[index] or tostring(index), 11) end
    put_int(header, 0x1a4, setup.background)
    for slot = 0, 17 do
        local value = match_state.items[slot]
        for _, field in ipairs(slot_fields) do
            local number = 0
            if value then
                if field[2] == "record_id" then number = value.record.id
                elseif field[2] == "present" then number = 1
                else number = value[field[2]] or 0 end
            end
            put_int(header, field[1] + slot * 4, number)
        end
    end
    put_text(header, 0x550, setup.music or "", 0x1f4)
    put_int(header, 0x744, recording.data_checksum())
    put_int(header, 0x748, setup.version)
    local battle = setup.battle
    for index = 0, 21 do
        put_int(header, 0x74c + index * 4, battle and battle.first[index] or 0)
        put_int(header, 0x7a4 + index * 4, battle and battle.reserve[index] or 0)
        put_int(header, 0x7fc + index * 4, battle and battle.stock and battle.stock[index] or 0)
        put_int(header, 0x854 + index * 4, battle and battle.on_field and battle.on_field[index] or 0)
    end
    engine.reset_random_sequence()
    local table_string, index = engine.random_state()
    put_int(header, 0x8c4, index)
    for position = 1, #table_string do header[0x8c8 + position - 1] = table_string:byte(position) end
    header[0x8c8 + 3000] = 0 -- the flag byte after the table
    for position = 0, 9 do put_int(header, 0x1488 + position * 4, setup.random_fighters[position + 1]) end
    put_int(header, 0x14b0, setup.random_index)
    put_int(header, 0x14b4, setup.input_phase)
    match_state.recording = {header = header, frames = {}, frame = 0, name = setup.name,
        author = setup.author, info = setup.info, email = setup.email, battle = battle}
    recording.status = {kind = constants.recording_statuses.starting, name = setup.name, count = 0}
end

recording.status = nil
function recording.status_text()
    local status = recording.status
    if not status then return nil end
    if status.kind == constants.recording_statuses.starting then return string.format("Start recording '%s'...", status.name) end
    if status.kind == constants.recording_statuses.saved then return string.format("Recording file '%s' saved!", status.name) end
    if status.kind == constants.recording_statuses.cancelled then return "Recording canceled!" end
    return status.text
end
function recording.tick_status(paused)
    local status = recording.status
    if not status or paused then return end
    status.count = status.count + (status.kind == constants.recording_statuses.cancelled and 2 or 1)
    if status.count > 0xf0 then recording.status = nil end
end

local key_bits = {{"u", 0x80}, {"d", 0x40}, {"l", 0x20}, {"r", 0x10}, {"c", 8}, {"b", 4}, {"f", 2}}
function recording.pack_keys(letters)
    local value = 0
    for _, bit in ipairs(key_bits) do
        if letters:find(bit[1], 1, true) then value = value + bit[2] end
    end
    return value
end
function recording.unpack_keys(value)
    local letters = {}
    for _, bit in ipairs(key_bits) do
        if math.floor(value / bit[2]) % 2 == 1 then letters[#letters + 1] = bit[1] end
    end
    return table.concat(letters)
end
-- Function-key flags of byte 8.
recording.function_bits = {[3] = 4, [6] = 0x10, [7] = 0x20, [8] = 0x40, [9] = 0x80}

-- The sum of hp of the items in slots 0-19 (checked every 150 frames).
function recording.hp_sum(match_state)
    local sum = 0
    for index = 0, 19 do
        local value = match_state.items[index]
        if value then sum = sum + value.hp end
    end
    return sum
end

function recording.capture(match_state, bytes)
    local run = match_state.recording
    if not run or run.frame >= max_frames then return end
    run.frames[run.frame + 1] = string.char(unpack(bytes, 1, 10))
    if run.frame % 150 == 0 then
        put_int(run.header, checksums_offset + math.floor(run.frame / 150) * 4, recording.hp_sum(match_state))
    end
    run.frame = run.frame + 1
end

-- The round-end results (counter 101) and the file: per player, human flag/record id/team/
-- kills/damage/hp/mp/pickings/result, plus totals, F-key counters and the Stage/Battle stamp.
-- Returns true, or nil and a message.
function recording.finish(match_state, results)
    local run = match_state.recording
    local header = run.header
    local present = 0
    for k = 0, 7 do
        local entry = match_state.items[k] and k or (match_state.items[k + 10] and k + 10)
        if not entry then
            put_int(header, 0x14 + 4 * k, -1)
        else
            local value = match_state.items[entry]
            put_int(header, 0x34 + 4 * k, value.record.id)
            put_int(header, 0x14 + 4 * k, entry < 10 and 1 or 0)
            put_int(header, 0x54 + 4 * k, value.team)
            put_int(header, 0x74 + 4 * k, value.kills or 0)
            put_int(header, 0x94 + 4 * k, value.damage_dealt or 0)
            put_int(header, 0xb4 + 4 * k, value.hp_spent or 0)
            put_int(header, 0xd4 + 4 * k, value.mp_spent or 0)
            put_int(header, 0xf4 + 4 * k, value.pickings or 0)
            if results.result_of then put_int(header, 0x114 + 4 * k, results.result_of(value)) end
            present = present + 1
        end
    end
    put_int(header, 0x10, present)
    if results.battle_deaths then
        put_int(header, 0x134, results.battle_deaths[1])
        put_int(header, 0x138, results.battle_deaths[2])
        put_int(header, 0x13c, results.battle_damage[1])
        put_int(header, 0x140, results.battle_damage[2])
    end
    put_int(header, 0x144, match_state.elapsed)
    put_int(header, 0x8ac, results.phase or 0)
    for key = 6, 9 do put_int(header, 0x8b0 + (key - 6) * 4, match_state.function_counts[key]) end
    if results.stamp then put_int(header, 0x8c0, results.stamp) end
    -- Checksums past the header overwrite frame records, matching the original's single block.
    local frames = run.frames
    local frame_count = run.frame
    for segment = math.floor((header_size - checksums_offset) / 4), math.floor(math.max(frame_count - 1, 0) / 150) do
        local offset = checksums_offset + segment * 4
        local sum = header[offset] and get_int(bytes_to_string(header, offset, offset + 3), 0) or nil
        if sum then
            for index = 0, 3 do
                local position = offset + index - records_offset
                local frame, column = math.floor(position / 10) + 1, position % 10 + 1
                if frames[frame] then
                    frames[frame] = frames[frame]:sub(1, column - 1) .. string.char(header[offset + index])
                        .. frames[frame]:sub(column + 1)
                end
            end
        end
    end
    local tail = {}
    put_int(tail, 0, 0)
    put_int(tail, 4, 0)
    put_text(tail, 8, run.author, 100)
    put_text(tail, 8 + 0x64, run.info, 0x190)
    put_text(tail, 8 + 0x1f4, run.email, 0x64)
    local records = table.concat(frames)
    local block = table.concat({bytes_to_string(header, 0, header_size - 1), records,
        string.rep("\0", tail_offset - records_offset - #records), bytes_to_string(tail, 0, block_size - tail_offset - 1)})
    assert(#block == block_size, "recording block size")
    return engine.save_recording(run.name, block)
end

function recording.open(block, version)
    if get_int(block, 0x744) ~= recording.data_checksum() then
        return nil, "Error!  Recording file are recorded in a LF2 with some data files (character or stage files) different from yours."
    end
    local recorded_version = get_int(block, 0x748)
    if recorded_version ~= version then
        local function name(number)
            if number == 0x1e then return "v2.0" end
            return number > version and "a newer version" or ""
        end
        return nil, string.format("Version error.  Recording file are recorded in %s. (your LF2 is %s)!",
            name(recorded_version), name(version))
    end
    local replay = {block = block, difficulty = get_int(block, 0), stage_level = get_int(block, 4),
        mode = get_int(block, 0x148), names = {}, background = get_int(block, 0x1a4), slots = {},
        music = get_text(block, 0x550, 0x1f4), random_index = get_int(block, 0x8c4),
        random_table = block:sub(0x8c8 + 1, 0x8c8 + 3000), random_fighters = {},
        random_list_index = get_int(block, 0x14b0), input_phase = get_int(block, 0x14b4),
        total_time = get_int(block, 0x144), author = get_text(block, 0x630bc0, 0x64),
        info = get_text(block, 0x630c24, 0x190), email = get_text(block, 0x630db4, 0x64), frame = 0,
        unlock_characters = get_int(block, 8), unlock_function_keys = get_int(block, 0xc)}
    for index = 1, 8 do replay.names[index] = get_text(block, 0x14c + (index - 1) * 11, 11) end
    for slot = 0, 17 do
        local fields = {}
        for _, field in ipairs(slot_fields) do fields[field[2]] = get_int(block, field[1] + slot * 4) end
        if fields.present ~= 0 then replay.slots[slot] = fields end
    end
    for position = 0, 9 do replay.random_fighters[position + 1] = get_int(block, 0x1488 + position * 4) end
    -- Battle: the four troop tables and the stamp (strategies, sizes and defense per side).
    local battle = {first = {}, reserve = {}, stock = {}, on_field = {}}
    for index = 0, 21 do
        battle.first[index] = get_int(block, 0x74c + index * 4)
        battle.reserve[index] = get_int(block, 0x7a4 + index * 4)
        battle.stock[index] = get_int(block, 0x7fc + index * 4)
        battle.on_field[index] = get_int(block, 0x854 + index * 4)
    end
    local stamp = get_int(block, 0x8c0)
    battle.strategy = {[0] = math.floor(stamp / 10000000) - 1, [1] = math.floor(stamp % 10000 / 1000) - 1}
    battle.size = {[0] = math.floor(stamp % 10000000 / 1000000) - 1, [1] = math.floor(stamp % 1000 / 100) - 1}
    battle.defense = {[0] = (math.floor(stamp % 1000000 / 100000) * 10 + math.floor(stamp % 100000 / 10000)) * 10,
        [1] = (math.floor(stamp % 100 / 10) * 10 + stamp % 10) * 10}
    replay.battle = battle
    return replay
end

-- The recorded input of the replay's current frame: letters per slot 0-7, the function-key
-- flags and the unlock bits, or nil after the last possible frame. Advances the frame counter.
function recording.replay_input(replay)
    if replay.frame >= max_frames then return nil end
    local offset = records_offset + replay.frame * 10
    local bytes = {replay.block:byte(offset + 1, offset + 10)}
    local input = {functions = ""}
    for slot = 0, 7 do input[slot] = recording.unpack_keys(bytes[slot + 1]) end
    input.flags = bytes[9]
    input.unlock = bytes[10]
    return input
end
-- The checksum stored for the current frame (every 150 frames), or nil.
function recording.replay_checksum(replay)
    if replay.frame % 150 ~= 0 then return nil end
    return get_int(replay.block, checksums_offset + math.floor(replay.frame / 150) * 4)
end
function recording.replay_advance(replay)
    if replay.frame < max_frames then replay.frame = replay.frame + 1 end
end
return recording
