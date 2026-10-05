-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local background = {}
local cache = {}
local screen_width = 794
-- The painter's fixed replacements for four converted rect: colors.
local remapped = {[0x175317] = 0x104f10, [0x575347] = 0x5a4e4b, [0x977757] = 0x9a6e5a, [0x473f1f] = 0x423818}
local function canonical(path)
    path = path:gsub("\\", "/"):lower()
    assert(path:match("^[a-z0-9_./-]+$"), "unsupported original resource path: " .. path)
    return path
end
function background.load(path)
    path = canonical(path)
    local data = cache[path]
    if not data then
        data = engine.read_background_data(path)
        for _, layer in ipairs(data.layers) do layer.resource = canonical(layer.path) end
        cache[path] = data
    end
    return data
end
-- Mutable per-view state: the original keeps one animation counter per layer slot.
function background.create_state(data)
    local counters = {}
    for index = 1, #data.layers do counters[index] = 0 end
    return {counters = counters}
end
-- C integer division truncates toward zero.
local function truncate(value)
    if value >= 0 then return math.floor(value) end
    return math.ceil(value)
end
local function parallax(layer, stage_width, camera_x)
    return -truncate((layer.width - screen_width) * camera_x / (stage_width - screen_width))
end
-- Advances the counter on every paint call; hidden outside c1..c2.
local function visible(layer, state, index)
    if layer.cc <= 0 then return true end
    local counter = (state.counters[index] + 1) % layer.cc
    state.counters[index] = counter
    return counter >= layer.c1 and counter <= layer.c2
end
-- Paints every layer in file order for a camera at world x `camera_x`.
function background.paint(context, data, state, camera_x)
    local stage_width = assert(data.width, "background has no width")
    for index, layer in ipairs(data.layers) do
        local keyed = layer.transparency ~= 0
        if layer.color == 0 and layer.loop == 0 then
            local offset = 0
            if stage_width > screen_width then offset = parallax(layer, stage_width, camera_x) end
            if visible(layer, state, index) then
                context.image(layer.resource, layer.x + offset, layer.y, keyed)
            end
        elseif layer.color == 0 then
            if visible(layer, state, index) then
                -- The original divides by zero or never terminates in these cases.
                assert(layer.loop > 0, "negative background layer loop step")
                assert(stage_width ~= screen_width, "looped layer on a screen-wide background")
                local offset = parallax(layer, stage_width, camera_x)
                for x = layer.x, layer.width - 1, layer.loop do
                    context.image(layer.resource, offset + x, layer.y, keyed)
                end
            end
        elseif layer.width > 0 and layer.height > 0 then
            local color = (remapped[layer.color] or layer.color) % 16777216
            context.fill(layer.x, layer.y, layer.width, layer.height,
                math.floor(color / 65536), math.floor(color / 256) % 256, color % 256)
        end
    end
end
background.lee_on_road = {name = "Lee On Road", width = 2400, zboundary = {350, 470},
    shadow = "pe/shadow1", shadow_size = {37, 9}, layers = {}}
local function cmod(a, b) return a - (a / b >= 0 and math.floor(a / b) or math.ceil(a / b)) * b end
local function rgb(context, x, y, width, height, color)
    context.fill(x, y, width, height, math.floor(color / 65536), math.floor(color / 256) % 256, color % 256)
end
function background.paint_lee_on_road(context, camera_x)
    context.image("pe/back99_2", 250 - math.floor(camera_x / 100), 120, false)
    for x = 0, 3999, 500 do
        context.image("pe/back99_3", x - math.floor(camera_x * 7 / 10) + 30, 175, true)
    end
    rgb(context, 0, 326, 794, 20, 0x3f3f3f)
    rgb(context, 0, 345, 794, 156, 0x575757)
    rgb(context, 0, 471, 794, 30, 0x3f3f3f)
    rgb(context, 0, 328, 794, 2, 0x373737)
    for x = cmod(900 - camera_x, 70), 792, 70 do
        rgb(context, x, 292, 1, 37, 0x577fa7)
        rgb(context, x + 1, 292, 1, 37, 0x2f4357)
    end
    rgb(context, 0, 310, 794, 1, 0x577fa7)
    rgb(context, 0, 311, 794, 1, 0x2f4357)
    rgb(context, 0, 290, 794, 1, 0x577fa7)
    rgb(context, 0, 291, 794, 1, 0x2f4357)
    for x = 0, 3199, 320 do
        context.image("pe/back99_1", x - camera_x + 10, 390, false)
    end
end
return background
