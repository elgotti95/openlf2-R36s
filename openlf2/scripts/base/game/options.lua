-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- OpenLF2's own settings, which the original game does not have. They
-- live in config.json's "options" member, next to the original's controls and recording values.
local unlock = require("base/game/unlock")
local options = {}

-- Every valid value, in the dropdown's order. "xbrz" is a shader: the host offers it only on
-- renderers that can run it (see options.available_filters), but a saved choice stays valid.
options.upscaling_filters = {"nearest", "linear", "xbrz"}
-- The values to offer: `features` is what the host reported ({xbrz = true} when it can run the shader).
function options.available_filters(features)
    local list = {}
    for _, filter in ipairs(options.upscaling_filters) do
        if filter ~= "xbrz" or (features and features.xbrz) then list[#list + 1] = filter end
    end
    return list
end
-- On-screen gamepad layout, in pixels of the 794x550 viewport measured from the window's edges
-- (so it can sit in the letterbox bars): the stick's `left` counts from the left edge, each
-- button's `right` from the right edge, and `bottom` from the bottom edge. Sizes are radii.
-- `touch.tolerance` is the press tolerance.
local gamepad_defaults = {
    stick = {left = 125, bottom = 110, radius = 56},
    -- The digipad (a fixed cross) used instead of the stick when `digipad` is on; `radius` is the
    -- length of its arms (the cross is twice that wide); `left` and `bottom` keep it clear of the edges.
    dpad = {left = 160, bottom = 160, radius = 110},
    c = {right = 188, bottom = 92, radius = 44},
    b = {right = 180, bottom = 186, radius = 32},
    f = {right = 282, bottom = 150, radius = 32},
    -- How far (pixels) outside a button's edge a finger still presses it; it presses the button
    -- whose edge is nearest.
    touch = {tolerance = 40},
    -- Small pause button in the top right corner: `right` and `top` count from those edges.
    pause = {right = 30, top = 30, radius = 16},
    -- Chords of defend (D), jump (J) and attack (A), a column on the right edge; disabled unless
    -- the character has the move.
    da = {right = 72, bottom = 250, radius = 26},
    dj = {right = 72, bottom = 165, radius = 26},
    daj = {right = 72, bottom = 80, radius = 26},
}
local defaults = {gamepad = gamepad_defaults, unlock_characters = false, upscaling_filter = "linear", fullscreen = false, digipad = true, show_fps = false,
    rumble = false, show_gamepad = false}
local current

local function valid_filter(value)
    for _, filter in ipairs(options.upscaling_filters) do
        if value == filter then return true end
    end
    return false
end
local function copy_gamepad(layout)
    local result = {}
    for name, entry in pairs(gamepad_defaults) do
        result[name] = {}
        for key, default in pairs(entry) do
            local value = type(layout) == "table" and type(layout[name]) == "table" and layout[name][key]
            if type(value) ~= "number" or value ~= value or value < 0 or value > 2000 or (key == "radius" and value < 8) then
                value = default
            end
            result[name][key] = value
        end
    end
    return result
end
local function copy(values)
    return {gamepad = copy_gamepad(values.gamepad),unlock_characters = values.unlock_characters,
        upscaling_filter = valid_filter(values.upscaling_filter) and values.upscaling_filter or defaults.upscaling_filter,
        fullscreen = values.fullscreen, digipad = values.digipad, show_fps = values.show_fps, rumble = values.rumble,
        show_gamepad = values.show_gamepad}
end

-- The saved options, or the defaults for anything missing or invalid.
function options.load()
    local document = engine.read_settings()
    local saved = type(document) == "table" and document.options
    local values = copy(defaults)
    if type(saved) == "table" and type(saved.unlock_characters) == "boolean" then
        values.unlock_characters = saved.unlock_characters
    end
    if type(saved) == "table" and valid_filter(saved.upscaling_filter) then
        values.upscaling_filter = saved.upscaling_filter
    end
    if type(saved) == "table" and type(saved.fullscreen) == "boolean" then
        values.fullscreen = saved.fullscreen
    end
    if type(saved) == "table" and type(saved.digipad) == "boolean" then
        values.digipad = saved.digipad
    end
    if type(saved) == "table" and type(saved.show_fps) == "boolean" then
        values.show_fps = saved.show_fps
    end
    if type(saved) == "table" and type(saved.rumble) == "boolean" then
        values.rumble = saved.rumble
    end
    if type(saved) == "table" and type(saved.show_gamepad) == "boolean" then
        values.show_gamepad = saved.show_gamepad
    end
    if type(saved) == "table" then values.gamepad = copy_gamepad(saved.gamepad) end
    current = values
    return copy(values)
end
function options.current()
    if not current then options.load() end
    return copy(current)
end

local function apply(before, after)
    if after.unlock_characters and not (before and before.unlock_characters) then
        unlock.flags.characters = 1
    elseif before and before.unlock_characters and not after.unlock_characters then
        unlock.flags.characters = 0
    end
end

local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, value in pairs(a) do
        if not same(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

-- At startup: load and apply the saved options, then rewrite config.json's "options" so it
-- lists every option: missing ones filled with defaults, invalid or unknown ones dropped.
function options.start()
    local loaded = options.load()
    apply(nil, loaded)
    local document, problem = engine.read_settings()
    if problem then return end
    if type(document) == "table" and same(document.options, loaded) then return end
    options.save(loaded)
end

-- Saves `values` into config.json (other members are kept) and applies what changed. Returns
-- true, or nil and a message; the options apply even when saving fails.
function options.save(values)
    local before = options.current()
    current = copy(values)
    apply(before, current)
    local document = engine.read_settings()
    if type(document) ~= "table" then document = {} end
    document.version = 1
    document.options = copy(current)
    return engine.write_settings(document)
end
return options
