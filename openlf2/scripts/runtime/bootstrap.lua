-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- Trusted runtime implementation. The host prepends the validated declarations table.
local compile = loadstring or load
local read_resource = openlf2_read_resource
local read_object_data = openlf2_read_object_data
local read_background_data = openlf2_read_background_data
local read_stage_data = openlf2_read_stage_data
local random = openlf2_random
local crt_random = openlf2_crt_random
local read_settings = openlf2_read_settings
local write_settings = openlf2_write_settings
local random_state, set_random_state = openlf2_random_state, openlf2_set_random_state
local reset_random_sequence = openlf2_reset_random_sequence
local save_recording, take_recording = openlf2_save_recording, openlf2_take_recording
local local_time = openlf2_local_time
local network, network_time = openlf2_network, openlf2_network_time
local set_environment = setfenv
local unpack_values = unpack or table.unpack
local traceback = debug.traceback
local protected_call = xpcall
local concatenate = table.concat
local floor = math.floor
local module_definitions, module_cache, loading = {}, {}, {}

local function copy_library(library)
    local copy = {}
    for key, value in pairs(library) do copy[key] = value end
    return copy
end

local load_module
local function evaluate(declaration, previous)
    local environment = {
        assert = assert, error = error, ipairs = ipairs, pairs = pairs,
        next = next, select = select, tonumber = tonumber, tostring = tostring,
        type = type, unpack = unpack_values, pcall = pcall,
        math = copy_library(math), string = copy_library(string), table = copy_library(table),
        require = load_module,
        engine = {read_resource = read_resource, read_object_data = read_object_data,
            read_background_data = read_background_data, read_stage_data = read_stage_data,
            random = random, crt_random = crt_random,
            read_settings = read_settings, write_settings = write_settings,
            random_state = random_state, set_random_state = set_random_state,
            reset_random_sequence = reset_random_sequence, save_recording = save_recording,
            take_recording = take_recording, local_time = local_time,
            network = network, network_time = network_time},
    }
    environment.math.random = nil
    environment.math.randomseed = nil
    environment.string.dump = nil
    local chunk, message
    if set_environment then
        chunk, message = compile(declaration[4], "@" .. declaration[3])
    else
        chunk, message = compile(declaration[4], "@" .. declaration[3], "t", environment)
    end
    assert(chunk, message)
    if set_environment then set_environment(chunk, environment) end
    local exported = chunk()
    if declaration[1] == "extend" then
        assert(type(exported) == "function", declaration[3] .. ": extension must return a decorator")
        exported = exported(previous)
    end
    assert(type(exported) == "table", declaration[3] .. ": module must export a table")
    return exported
end

for _, declaration in ipairs(declarations) do
    local target = declaration[2]
    local chain = module_definitions[target] or {}
    if declaration[1] == "replace" then
        -- Replacement substitutes the base; explicit extensions still decorate the result.
        chain[1] = declaration
    elseif declaration[1] == "module" then
        assert(#chain == 0, "duplicate module: " .. target)
        chain[1] = declaration
    else
        chain[#chain + 1] = declaration
    end
    module_definitions[target] = chain
end

load_module = function(name)
    assert(type(name) == "string", "require expects a module name")
    if module_cache[name] then return module_cache[name] end
    assert(not loading[name], "cyclic module import: " .. name)
    local chain = assert(module_definitions[name], "module not declared: " .. name)
    loading[name] = true
    local exported
    for _, declaration in ipairs(chain) do exported = evaluate(declaration, exported) end
    loading[name] = nil
    module_cache[name] = exported
    return exported
end

local screen = load_module("base/ui/flow")
local state = screen.create(runtime_settings or {menu_seed = 0})
local function integer(value)
    assert(type(value) == "number" and value == floor(value) and value >= -8192 and value <= 8192,
        "draw coordinates must be integers within limits")
    return tostring(value)
end

local function render(input)
    local commands = {}
    local context = {}
    function context.viewport(width, height, red, green, blue)
        assert(#commands < 4096, "command limit exceeded")
        commands[#commands + 1] = concatenate({"viewport", integer(width), integer(height),
            integer(red), integer(green), integer(blue)}, " ")
    end
    -- `tint`: 0xRRGGBB multiplied into the sprite's colors (used for tinted text); nil leaves them.
    function context.sprite(resource, source, x, y, color_key, mirrored, flipped, tint)
        assert(type(resource) == "string" and resource:match("^[a-z0-9_./-]+$"), "invalid resource path")
        assert(#commands < 4096, "draw command limit exceeded")
        assert(tint == nil or (type(tint) == "number" and tint == floor(tint) and tint >= 0 and tint <= 0xffffff),
            "sprite tint must be an integer 0..0xffffff")
        commands[#commands + 1] = concatenate({"sprite", resource,
            integer(source[1]), integer(source[2]), integer(source[3]), integer(source[4]),
            integer(x), integer(y), color_key and "1" or "0", mirrored and "1" or "0", flipped and "1" or "0",
            tint and tostring(tint) or nil}, " ")
    end
    function context.fill(x, y, width, height, red, green, blue)
        assert(#commands < 4096, "draw command limit exceeded")
        for _, channel in ipairs({red, green, blue}) do
            assert(type(channel) == "number" and channel >= 0 and channel <= 255, "fill channels must be 0..255")
        end
        commands[#commands + 1] = concatenate({"fill", integer(x), integer(y), integer(width),
            integer(height), integer(red), integer(green), integer(blue)}, " ")
    end
    -- While on, draw commands cover the whole window, letterbox bars included; coordinates stay
    -- the viewport's (so they can be negative or past its size). Draw order is kept.
    function context.overlay(active)
        assert(#commands < 4096, "draw command limit exceeded")
        commands[#commands + 1] = active and "overlay 1" or "overlay 0"
    end
    -- Volume and pan are hundredths of a decibel (volume -10000..0).
    function context.sound(resource, volume, pan)
        assert(type(resource) == "string" and resource:match("^[a-z0-9_./-]+$"), "invalid resource path")
        assert(#commands < 4096, "command limit exceeded")
        assert(volume >= -10000 and volume <= 0 and pan >= -10000 and pan <= 10000, "sound volume or pan out of range")
        -- Volume and pan span -10000..10000, beyond the draw-coordinate limits.
        assert(volume == floor(volume) and pan == floor(pan), "sound volume and pan must be integers")
        commands[#commands + 1] = concatenate({"sound", resource, tostring(volume), tostring(pan)}, " ")
    end
    -- Haptic feedback (OpenLF2 extension): "gamepad" rumbles the `index`-th controller (0-based);
    -- "phone" is the device's own motor (iOS/Android; no-op elsewhere, `index` unused). `strength`: 0..100.
    function context.rumble(kind, index, strength)
        assert(kind == "gamepad" or kind == "phone", "invalid rumble kind")
        assert(type(index) == "number" and index == floor(index) and index >= 0, "invalid rumble index")
        assert(type(strength) == "number" and strength == floor(strength) and strength >= 0 and strength <= 100,
            "rumble strength must be an integer 0..100")
        assert(#commands < 4096, "command limit exceeded")
        commands[#commands + 1] = concatenate({"rumble", kind, tostring(index), tostring(strength)}, " ")
    end
    -- Music: ("play", path), ("stop"), ("resume") or ("volume", hundredths of a decibel).
    function context.music(kind, value)
        assert(#commands < 4096, "command limit exceeded")
        if kind == "play" then
            assert(type(value) == "string" and value:match("^[a-z0-9_./-]+$"), "invalid music path")
            commands[#commands + 1] = "music play " .. value
        elseif kind == "volume" then
            assert(type(value) == "number" and value >= -10000 and value <= 0, "music volume out of range")
            commands[#commands + 1] = "music volume " .. integer(value)
        else
            assert(kind == "stop" or kind == "resume", "invalid music command")
            commands[#commands + 1] = "music " .. kind
        end
    end
    -- Frame pacing: true for the 3 ms fast mode (F5), false for the normal 33 ms.
    function context.speed(fast)
        assert(#commands < 4096, "command limit exceeded")
        commands[#commands + 1] = fast and "speed 1" or "speed 0"
    end
    function context.render_filter(filter)
        assert(filter == "nearest" or filter == "linear" or filter == "xbrz", "invalid render filter")
        assert(#commands < 4096, "command limit exceeded")
        commands[#commands + 1] = "render_filter " .. filter
    end
    -- Shows (true) or hides the on-screen keyboard while a text field is being edited.
    function context.text_input(active)
        assert(type(active) == "boolean", "text input must be true or false")
        assert(#commands < 4096, "command limit exceeded")
        commands[#commands + 1] = active and "text_input 1" or "text_input 0"
    end
    -- Enters/leaves borderless fullscreen (OpenLF2's Fullscreen option); a no-op without a real window.
    function context.fullscreen(active)
        assert(type(active) == "boolean", "fullscreen must be true or false")
        assert(#commands < 4096, "command limit exceeded")
        commands[#commands + 1] = active and "fullscreen 1" or "fullscreen 0"
    end
    function context.image(resource, x, y, color_key)
        context.sprite(resource, {0, 0, 0, 0}, x, y, color_key)
    end
    function context.action(name)
        assert(type(name) == "string" and name:match("^[a-z_]+$"), "invalid action")
        assert(#commands < 4096, "command limit exceeded")
        commands[#commands + 1] = "action " .. name
    end
    if screen.update(state, input, context) == false then return "waiting" end
    screen.draw(state, context)
    return concatenate(commands, "\n")
end

function openlf2_describe()
    local success, output = protected_call(function()
        return screen.describe and screen.describe(state) or "no description"
    end, traceback)
    if not success then error(output) end
    return output
end

function openlf2_frame(input)
    local success, output = protected_call(function() return render(input) end, traceback)
    if not success then error(output) end
    return output
end
return "ready"
