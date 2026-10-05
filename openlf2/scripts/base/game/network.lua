-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local controls = require("base/ui/controls")
local recording = require("base/game/recording")
local network = {}
local timeout = 30000
local function failed(state, message)
    engine.network("close")
    state.phase, state.error = "failed", message
    return nil, message
end
local function send(state, bytes)
    local sent, problem = engine.network("send", bytes)
    if not sent then return failed(state, problem) end
    return true
end
local function take(state, count)
    if #state.received < count then return nil end
    local bytes = state.received:sub(1, count)
    state.received = state.received:sub(count + 1)
    return bytes
end
local function names_packet(host)
    local fields = {host and "11110000" or "00001111", string.rep("0", 24)}
    for index = 1, 4 do
        local name = controls.current().names[index]:sub(1, 10)
        fields[#fields + 1] = name .. string.rep("_", 11 - #name)
    end
    return table.concat(fields) .. "\0"
end
local function read_names(state, bytes)
    local expected = state.host and "00001111" or "11110000"
    if bytes:sub(1, 8) ~= expected or bytes:byte(77) ~= 0 then return failed(state, "Invalid network player assignment") end
    state.names = {}
    for index = 1, 4 do
        local peer = bytes:sub(33 + (index - 1) * 11, 43 + (index - 1) * 11):match("^[^_%z]*")
        local own = controls.current().names[index]:match("^[^_%z]*"):sub(1, 10)
        state.names[(state.host and 0 or 4) + index] = own
        state.names[(state.host and 4 or 0) + index] = peer
    end
    return true
end
function network.create(options)
    assert(type(options.network_profile) == "string" and #options.network_profile == 64, "missing network profile")
    return {phase = "idle", received = "", sequence = 0, frames = 0,
        version = options.recording_version, profile = "OpenLF2 TCP 1\n" .. options.network_profile,
        port = options.network_port or 12345}
end
function network.start(state, host, address)
    network.close(state)
    state.host, state.error, state.received = host, nil, ""
    state.names, state.pending, state.sequence, state.frames = nil, nil, 0, 0
    local started, problem = engine.network(host and "host" or "join", address, state.port)
    if not started then return failed(state, problem) end
    state.phase = "connecting"
    state.deadline = engine.network_time() + timeout
    return true
end
function network.close(state)
    engine.network("close")
    state.phase, state.pending, state.received = "idle", nil, ""
end
-- Called from the lobby or once per attempted tick. No simulation or RNG draw occurs while
-- waiting. Deadlines measure elapsed real time, never simulation time.
function network.poll(state)
    if state.phase == "failed" then return nil, state.error end
    local bytes, problem = engine.network("poll")
    if not bytes then return failed(state, problem) end
    state.received = state.received .. bytes
    if #state.received > 8192 then return failed(state, "Network receive buffer exceeded") end
    if state.phase ~= "ready" and engine.network_time() > state.deadline then
        return failed(state, "Network connection timed out")
    end
    if state.phase == "connecting" and engine.network("status") == "connected" then
        if not send(state, state.profile) then return nil, state.error end
        state.phase = "profile"
    end
    if state.phase == "profile" then
        local profile = take(state, #state.profile)
        if not profile then return false end
        if profile ~= state.profile then return failed(state, "Network engine/scripts/mod profile mismatch") end
        state.checksum = recording.data_checksum() % 65536
        if state.host then
            if not send(state, "u can connect\0") then return nil, state.error end
            state.phase = "players"
        else state.phase = "greeting" end
    end
    if state.phase == "greeting" then
        local greeting = take(state, 14)
        if not greeting then return false end
        if greeting ~= "u can connect\0" then return failed(state, "Invalid network greeting") end
        if not send(state, names_packet(false)) then return nil, state.error end
        state.phase = "players"
    end
    if state.phase == "players" then
        local players = take(state, 77)
        if not players then return false end
        if not read_names(state, players) then return nil, state.error end
        if state.host then
            local random_table = engine.random_state()
            engine.set_random_state(random_table, 0)
            engine.reset_random_sequence()
            if not send(state, names_packet(true) .. random_table .. "\0") then return nil, state.error end
            state.phase = "ready"
        else state.phase = "random" end
    end
    if state.phase == "random" then
        local random_table = take(state, 3001)
        if not random_table then return false end
        if random_table:byte(3001) ~= 0 or random_table:sub(1, 3000):find("\0", 1, true) then
            return failed(state, "Invalid network random table")
        end
        engine.set_random_state(random_table:sub(1, 3000), 0)
        engine.reset_random_sequence()
        state.phase = "ready"
    end
    return state.phase == "ready"
end
local function has(value, bit) return math.floor(value / bit) % 2 == 1 end
-- Packet offsets 10 and 12, unlike recording flags. Bit zero starts set in the original.
local function_bits = {{10, 2}, {10, 64}, {12, 2}, {10, 4}, {10, 8}, {10, 16}, {10, 32}, {12, 4}, {10, 128}}
function network.packet(state, input, hp)
    local bytes = {}
    for index = 1, 20 do bytes[index] = 1 end
    bytes[21], bytes[22] = 0, 0
    for index = 0, 3 do
        bytes[(state.host and 0 or 4) + index + 1] = recording.pack_keys(input[index] or "") + 1
    end
    bytes[10], bytes[12], bytes[14] = state.sequence, state.version, hp % 100 + 1
    bytes[15], bytes[16] = state.checksum % 256, math.floor(state.checksum / 256)
    for key, field in ipairs(function_bits) do
        if input.functions:find(tostring(key), 1, true) then bytes[field[1] + 1] = bytes[field[1] + 1] + field[2] end
    end
    local marks = input.unlock_bits or 0
    if marks % 2 == 1 then bytes[13] = bytes[13] + 8 end
    if math.floor(marks / 2) % 2 == 1 then bytes[13] = bytes[13] + 16 end
    return string.char(unpack(bytes))
end
function network.exchange(state, input, hp)
    if not state.pending then
        state.sequence = (state.sequence + 1) % 50
        state.pending = network.packet(state, input, hp)
        state.deadline = engine.network_time() + timeout
        if not send(state, state.pending) then return nil, state.error end
    end
    local ok, problem = network.poll(state)
    if not ok then return nil, problem end
    local remote = take(state, 22)
    if not remote then
        if engine.network_time() > state.deadline then return failed(state, "Network input timed out") end
        return nil
    end
    local own = state.pending
    for _, check in ipairs({{10, "sequence"}, {12, "version"}, {14, "HP synchronization"}, {15, "data"}, {16, "data"}}) do
        if remote:byte(check[1]) ~= own:byte(check[1]) then return failed(state, "Network " .. check[2] .. " mismatch") end
    end
    -- Reject a peer trying to write the other machine's controls or malformed reserved bytes.
    for index = 1, 8 do
        local peer_slot = state.host and index > 4 or not state.host and index <= 4
        if remote:byte(index) % 2 ~= 1 or (not peer_slot and remote:byte(index) ~= 1) then
            return failed(state, "Invalid network input slot")
        end
    end
    if remote:byte(11) % 2 ~= 1 or remote:byte(13) % 2 ~= 1 or remote:byte(13) > 31
       or remote:byte(9) ~= 1 or remote:sub(17) ~= string.rep("\1", 4) .. "\0\0" then
        return failed(state, "Invalid network packet padding")
    end
    local combined = {functions = "", keys = {}, pointer_x = 0, pointer_y = 0, button = false, network = true}
    for slot = 0, 7 do
        local local_slot = state.host and slot < 4 or not state.host and slot >= 4
        combined[slot] = recording.unpack_keys((local_slot and own or remote):byte(slot + 1))
    end
    combined.function_sources = {"", ""}
    for key, field in ipairs(function_bits) do
        if has(own:byte(field[1] + 1), field[2]) or has(remote:byte(field[1] + 1), field[2]) then
            combined.functions = combined.functions .. tostring(key)
        end
        if has(own:byte(field[1] + 1), field[2]) then combined.function_sources[1] = combined.function_sources[1] .. key end
        if has(remote:byte(field[1] + 1), field[2]) then combined.function_sources[2] = combined.function_sources[2] .. key end
    end
    combined.unlock_bits = 0
    for _, mark in ipairs({{8, 1}, {16, 2}}) do
        if has(own:byte(13), mark[1]) or has(remote:byte(13), mark[1]) then
            combined.unlock_bits = combined.unlock_bits + mark[2]
        end
    end
    state.pending, state.frames = nil, state.frames + 1
    return combined
end
return network
