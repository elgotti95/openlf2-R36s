-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local constants = require("base/game/constants")
local music = require("base/game/music")
local catalog = require("base/game/catalog")
local object_data = require("base/game/object_data")
local background = require("base/game/background")
local navigation = require("base/ui/input")
local font = require("base/ui/font")
local sounds = require("base/game/sounds")
local screen = {}

local function cdiv(a, b)
    local q = a / b
    if q >= 0 then return math.floor(q) end
    return math.ceil(q)
end
local function cmod(a, b) return a - cdiv(a, b) * b end

local types = {[0] = 30, 31, 33, 34, 39, 32, 35, 36, 37, 122, 123}
local type_count = 11
local preset_total = {[0] = 20, 20, 8, 8, 8, 2, 2, 3, 2, 10, 10, 42, 42, 2, 8, 0, 0, 0, 3, 0, 10, 10, 0, 20,
    12, 12, 0, 0, 8, 3, 0, 10, 10, 20, 0, 4, 0, 10, 8, 0, 3, 6, 10, 10, 0, 0, 0, 0, 0, 9, 8, 3, 8, 10, 10, 0}
local preset_first = {[0] = 7, 7, 4, 4, 4, 1, 1, 1, 1, 3, 3, 20, 20, 1, 4, 0, 0, 0, 1, 0, 3, 3, 0, 10, 6, 6,
    0, 0, 4, 1, 1, 3, 3, 10, 0, 2, 0, 5, 4, 0, 1, 3, 3, 3, 0, 0, 0, 0, 0, 6, 4, 1, 4, 3, 3, 0}
local origin_x = 45

local clip3, clip4, clip = "pe/menu_clip3", "pe/menu_clip4", "pe/menu_clip"
local clip_frames = {[15] = {316, 124, 29, 19}, [16] = {316, 144, 29, 19}, [17] = {316, 164, 29, 19},
    [18] = {316, 184, 37, 19}, [19] = {316, 204, 70, 19}, [20] = {316, 224, 70, 19},
    [21] = {316, 244, 110, 19}, [22] = {316, 264, 102, 19}, [23] = {316, 284, 45, 19},
    [24] = {316, 304, 37, 19}}
local option_highlights = {
    [0] = {{407, 183, 126, 21}, 92, 16}, {{379, 206, 186, 21}, 64, 39}, {{355, 231, 235, 21}, 40, 64},
    {{330, 254, 279, 22}, 15, 87}, {{352, 278, 228, 22}, 37, 111}, {{416, 304, 111, 19}, 101, 137},
}

-- Counts from preset `strategy` scaled by size/3 (the picker's arithmetic).
local function apply_preset(config, side, strategy, scale)
    for i = 0, type_count - 1 do
        local total = cdiv(preset_total[strategy * type_count + i] * scale, 3)
        local first = cdiv(preset_first[strategy * type_count + i] * scale, 3)
        if first < 1 and total > 0 then first = 1 end
        total = total - first
        config.first[side * type_count + i] = first
        config.reserve[side * type_count + i] = total < 0 and 0 or total
    end
end

-- The configuration lives in globals in the original; the flow keeps it across visits.
function screen.create_config()
    local config = {first = {}, reserve = {}, defense = {[0] = 100, [1] = 100}, strategy = {[0] = 1, [1] = 1},
        size = {[0] = 0, [1] = 0}, pick_size = {[0] = 0, [1] = 0}, pick_strategy = {[0] = 0, [1] = 0},
        row = 6, column = 2, side = 0, options_row = 0, picker = 0, blink = 0}
    for side = 0, 1 do apply_preset(config, side, 0, 1) end
    return config
end

-- characters: the character menu state (slots, fighters, options); config: see create_config.
function screen.create(characters, config)
    return {characters = characters, config = config, state = 200, input = navigation.create(),
        display = {}, portraits = {}}
end

local function add(state, command) state.display[#state.display + 1] = command end
local function sprite(state, resource, source, x, y, keyed) add(state, {"sprite", resource, source, x, y, keyed}) end
local function image(state, resource, x, y) add(state, {"image", resource, x, y}) end
local function text(state, value, x, y) add(state, {"text", value, x, y}) end
local white, black, lilac = {255, 255, 255}, {0, 0, 0}, {0xa7, 0xa7, 0xff}
local function fill(state, x, y, width, height, color) add(state, {"fill", x, y, width, height, color}) end

local function outline(state, x, y, width, height, color)
    fill(state, x + 1, y, width - 2, 1, color)
    fill(state, x + 1, y + height - 1, width - 2, 1, color)
    fill(state, x, y + 1, 1, height - 2, color)
    fill(state, x + width - 1, y + 1, 1, height - 2, color)
end
local blink_counter = 0
local function blinking_outline(state, x, y, width, height)
    blink_counter = (blink_counter + 1) % 4
    if blink_counter < 2 then return outline(state, x, y, width, height, white) end
    fill(state, x, y - 1, width, 1, white)
    fill(state, x, y + height, width, 1, white)
    fill(state, x - 1, y, 1, height, white)
    fill(state, x + width, y, 1, height, white)
    fill(state, x, y, width, 1, white)
    fill(state, x, y + height - 1, width, 1, white)
    fill(state, x, y, 1, height, white)
    fill(state, x + width - 1, y, 1, height, white)
end

-- Small portraits (`small:`) of fighters and soldier types, parsed once.
local function small_portrait(state, path)
    if state.portraits[path] == nil then
        local small = object_data.load(path).small
        state.portraits[path] = small and (small:lower():gsub("\\", "/")) or false
    end
    return state.portraits[path] or nil
end
local function type_portrait(state, id)
    local entry = catalog.objects().by_id[id]
    return entry and small_portrait(state, entry.path)
end

local function ready(slot) return slot.phase == 3 or slot.phase == 13 end

local function draw_panel(state)
    local config = state.config
    local y0
    if state.state > 200 and state.state < 210 then
        y0 = 80
        sprite(state, "pe/battlemode", {0, 0, 705, 400}, origin_x, y0, false)
        sprite(state, "pe/battlemode", {0, 471, 705, 16}, origin_x, y0 + 400, false)
    elseif state.state >= 210 and state.state < 220 then
        y0 = 60
        sprite(state, "pe/battlemode", {0, 0, 705, 400}, origin_x, y0, false)
        sprite(state, "pe/battlemode", {0, 471, 705, 16}, origin_x, y0 + 400, false)
    else
        y0 = 33
        image(state, "pe/battlemode", origin_x, y0)
    end
    state.y0 = y0
    local characters = state.characters
    local column = {[1] = origin_x + 179, [2] = origin_x + 526}
    for index = 0, 7 do
        local slot = characters.slots[index]
        if ready(slot) and (slot.team == constants.teams.player_one or slot.team == constants.teams.player_two) then column[slot.team] = column[slot.team] - 20 end
    end
    for index = 0, 7 do
        local slot = characters.slots[index]
        if ready(slot) and (slot.team == constants.teams.player_one or slot.team == constants.teams.player_two) then
            local x, y = column[slot.team], y0 + 86
            column[slot.team] = column[slot.team] + 40
            local fighter = characters.fighters[slot.fighter]
            if (slot.was_random or slot.fighter == 0) and (state.state <= 200 or state.state >= 210) then
                sprite(state, clip4, {0, 335, 40, 45}, x, y, false)
            elseif fighter then
                local portrait = small_portrait(state, fighter.path)
                if portrait then image(state, portrait, x, y) end
            end
            text(state, slot.phase == 3 and tostring(index + 1) or "C", x + 15, y + 45)
        end
    end
    for side = 0, 1 do
        local value = config.defense[side]
        text(state, string.format("x %d.%d", cdiv(value, 100), cdiv(cmod(value, 100), 10)), side * 347 + 240 + origin_x, y0 + 154)
    end
    local grid = {[0] = origin_x + 39, [1] = origin_x + 386}
    for side = 0, 1 do
        for row = 0, type_count - 1 do
            local px, py
            if row < 6 then px, py = grid[side] + row * 48, y0 + 215
            else px, py = grid[side] + row * 48 - 264, y0 + 306 end
            if row == type_count - 1 then sprite(state, clip4, {0, 383, 40, 45}, px, py, false)
            elseif row == type_count - 2 then sprite(state, clip4, {0, 505, 40, 45}, px, py, false)
            else
                local portrait = type_portrait(state, types[row])
                if portrait then image(state, portrait, px, py) end
            end
            fill(state, px + 3, py + 46, 34, 16, black)
            fill(state, px + 3, py + 64, 34, 16, black)
            local first, reserve = config.first[side * type_count + row], config.reserve[side * type_count + row]
            if first == 0 then
                text(state, "0", px + 10, py + 46)
                text(state, "--", px + 10, py + 64)
            else
                text(state, tostring(first), px + 10, py + 46)
                text(state, tostring(reserve), px + 10, py + 64)
            end
        end
        local strategy = config.strategy[side]
        if strategy ~= -1 then
            local right = origin_x + 345 + side * 347
            local frame = clip_frames[strategy + 18]
            if frame then sprite(state, clip, frame, right - frame[3], y0 + 192, true) end
            if strategy ~= 0 and strategy ~= 6 then
                local size = clip_frames[config.size[side] + 15]
                if size then sprite(state, clip, size, right - size[3], y0 + 192, true) end
            end
        end
    end
end

-- State 200: the panel's rows (0 defense, 1-4 count grids, 5 troop picker, 6 continue).
local function panel_keys(state, key, context)
    local config = state.config
    local y0 = state.y0
    if key == "u" then config.row = config.row - 1 elseif key == "d" then config.row = config.row + 1 end
    local row = config.row
    if row >= 7 or row == 0 then
        config.row = 0
        blinking_outline(state, config.side * 347 + 80 + origin_x, y0 + 150, 208, 25)
        if key == "l" or key == "r" then config.side = 1 - config.side end
        if key == "c" then
            config.defense[config.side] = config.defense[config.side] + 50
            if config.defense[config.side] > 300 then config.defense[config.side] = 100 end
        end
        if key == "b" then
            config.defense[config.side] = config.defense[config.side] - 50
            if config.defense[config.side] < 100 then config.defense[config.side] = 300 end
        end
    elseif row < 0 then
        config.row = 6
    end
    row = config.row
    if row > 0 and row < 5 then
        local last = row <= 2 and 5 or 4
        if key == "r" then
            config.column = config.column + 1
            if config.column > last then
                config.side = 1 - config.side
                config.column = 0
            end
        end
        if key == "l" then
            local c = math.min(config.column, last)
            config.column = c - 1
            if c - 1 < 0 then
                config.side = 1 - config.side
                config.column = last
            end
        end
        local c = config.column
        if key == "c" or key == "b" or key == "f" then
            config.strategy[config.side], config.size[config.side] = -1, -1
            local list, index, limit
            local base = config.side * type_count
            if row == 1 then list, index, limit = config.first, c + base, 10
            elseif row == 2 then list, index, limit = config.reserve, c + base, 30
            elseif row == 3 then list, index, limit = config.first, (c < 4 and c + 6 or 10) + base, 10
            else list, index, limit = config.reserve, (c < 4 and c + 6 or 10) + base, 30 end
            local value = list[index]
            if key == "c" then value = value + 1 end
            if key == "f" then
                value = value + 5
                if limit < value and value < limit + 5 then value = limit end
            end
            if key == "b" then value = value - 1 end
            if value < 0 then value = limit elseif limit < value then value = 0 end
            list[index] = value
        end
        c = math.min(c, last)
        local px, py
        if row < 3 then px, py = c * 48 + 42, y0 + 243 + row * 18
        else px, py = c * 48 + 66, y0 + 298 + row * 18 end
        blinking_outline(state, px + config.side * 347 + origin_x, py, 34, 16)
    end
    if row == 5 then
        blinking_outline(state, config.side * 347 + 43 + origin_x, y0 + 396, 272, 25)
        if key == "l" or key == "r" then config.side = 1 - config.side end
        if key == "c" then
            state.state = 210
            config.picker = 10
            key = ""
            config.backup = {first = {}, reserve = {}}
            for i = 0, type_count * 2 - 1 do
                config.backup.reserve[i] = config.reserve[i]
                config.backup.first[i] = config.first[i]
            end
            config.backup.size = config.pick_size[config.side]
            config.backup.strategy = config.pick_strategy[config.side]
        end
    end
    if row == 6 then
        blinking_outline(state, origin_x + 301, y0 + 441, 106, 24)
        if key == "c" then
            state.state = 202
            config.options_row = 2
            key = ""
            sounds.direct(state, "join")
        end
        if key == "l" then
            config.row = 5
            config.side = 0
        elseif key == "r" then
            config.row = 5
            config.side = 1
        end
        if key == "b" then state.leave = "characters" end
    end
    return key
end

local function restore(config)
    for i = 0, type_count * 2 - 1 do
        config.reserve[i] = config.backup.reserve[i]
        config.first[i] = config.backup.first[i]
    end
end

-- States 0xd2-0xdb: the troop picker (Zero, S/M/L, Full, five strategies, OK, Cancel).
local function picker_keys(state, key)
    local config = state.config
    local side = config.side
    local shift = 410 - side * 275
    image(state, "pe/battletroops", shift, 65)
    if key == "b" then
        restore(config)
        config.pick_size[side] = config.backup.size
        config.pick_strategy[side] = config.backup.strategy
        state.state = 200
    end
    if config.pick_size[side] ~= -1 then outline(state, shift + 46, config.pick_size[side] * 22 + 168, 161, 19, lilac) end
    if config.pick_strategy[side] ~= -1 then
        outline(state, shift + 46, config.pick_strategy[side] * 22 + 304, 161, 19, lilac)
    end
    local line = config.picker
    if line >= 0 and line <= 9 then
        if line < 5 then
            blinking_outline(state, shift + 44, line * 22 + 144, 165, 23)
            if key == "c" then
                if line >= 1 and line <= 3 then
                    config.pick_size[side] = line - 1
                    if config.pick_strategy[side] == -1 then config.pick_strategy[side] = 0 end
                    apply_preset(config, side, config.pick_strategy[side], line)
                    config.size[side] = line - 1
                    config.strategy[side] = config.pick_strategy[side] + 1
                end
                if line == 0 then
                    config.pick_size[side], config.pick_strategy[side] = -1, -1
                    for i = 0, type_count - 1 do
                        config.reserve[side * type_count + i] = 0
                        config.first[side * type_count + i] = 0
                    end
                    config.strategy[side] = 0
                elseif line == 4 then
                    local base = side * type_count
                    config.pick_size[side], config.pick_strategy[side] = -1, -1
                    for i = 0, type_count - 1 do
                        config.reserve[base + i] = 30
                        config.first[base + i] = 2
                    end
                    config.first[base + 7], config.reserve[base + 7] = 1, 15
                    config.first[base + 9], config.first[base + 10] = 3, 3
                    config.strategy[side] = 6
                end
            end
        else
            blinking_outline(state, shift + 44, line * 22 + 192, 165, 23)
            if key == "c" then
                if config.pick_size[side] == -1 then config.pick_size[side] = 0 end
                config.strategy[side] = line - 4
                config.size[side] = config.pick_size[side]
                config.pick_strategy[side] = line - 5
                apply_preset(config, side, line - 5, config.pick_size[side] + 1)
            end
        end
        if key == "u" then config.picker = config.picker - 1 end
        if key == "d" then config.picker = config.picker + 1 end
        if config.picker < 0 then config.picker = 10 end
        return key
    end
    if line == 10 then
        blinking_outline(state, shift + 22, 433, 83, 24)
        if key == "r" then config.picker = config.picker + 1 end
        if key == "u" then config.picker = config.picker - 1 end
        if key == "d" then config.picker = 0 end
        if key == "c" then state.state = 200 end
    elseif line == 11 then
        blinking_outline(state, shift + 122, 433, 106, 24)
        if key == "u" then config.picker = config.picker - 2 end
        if key == "d" then config.picker = 0 end
        if key == "l" then config.picker = config.picker - 1 end
        if key == "c" then
            restore(config)
            state.state = 200
            key = ""
            sounds.direct(state, "cancel")
        end
    end
    return key
end

-- State 0xc9: slots that chose Random get a fighter not taken by another slot, below id 30.
local function reroll(state)
    local characters = state.characters
    for index = 0, 7 do
        local slot = characters.slots[index]
        if slot.was_random then
            local candidates = {}
            for position, fighter in ipairs(characters.fighters) do
                local taken = false
                for other = 0, 7 do
                    if characters.slots[other].fighter == position then taken = true end
                end
                if not taken and fighter.id < constants.record_id_ranges.random_fighter_end_exclusive
                   and fighter.id ~= constants.fighter_ids.template then
                    candidates[#candidates + 1] = position
                end
            end
            if #candidates > 0 then slot.fighter = candidates[engine.random(#candidates) + 1] end
        end
    end
end

local difficulties = {[2] = "Easy", [1] = "Normal", [0] = "Difficult", [-1] = "Difficult"}
local function background_name(characters, row)
    if row == 99 then return "Lee On Road" end
    if row == 100 then return "Random" end
    local entry = characters.backgrounds[row + 1]
    return entry and background.load(entry.path).name or ""
end

-- State 0xca: the options panel (Start Game, Reset All, Reset Random, background, difficulty,
-- Exit); jump returns to the troop panel.
local function options_keys(state, key, context)
    local config, options = state.config, state.characters.options
    sprite(state, clip3, {348, 0, 304, 156}, 3, 3, false)
    sprite(state, clip3, {348, 156, 304, 10}, 3, 159, true)
    local highlight = option_highlights[config.options_row]
    sprite(state, clip3, highlight[1], highlight[2], highlight[3], false)
    if options.random_background then options.background = 100 end
    text(state, background_name(state.characters, options.background), 174, 91)
    text(state, difficulties[options.difficulty] or "", 174, 115)
    if key == "u" then
        config.options_row = config.options_row - 1
        if config.options_row == -1 then config.options_row = 5 end
    end
    if key == "d" then config.options_row = (config.options_row + 1) % 6 end
    if key == "b" then
        state.state = 200
        return key
    end
    if key ~= "c" then return key end
    -- Stock per type: first wave + reserve (nothing without a first wave); on-field limit.
    config.stock, config.on_field = {}, {}
    for i = 0, type_count * 2 - 1 do
        config.stock[i] = config.first[i] < 1 and 0 or config.reserve[i] + config.first[i]
        config.on_field[i] = config.first[i]
    end
    key = ""
    sounds.direct(state, "ok")
    local row = config.options_row
    if row == 0 then
        music.play_selected()
        context.action("start_match")
    elseif row == 1 then
        options.background, options.random_background = 100, true
        state.leave = "characters"
    elseif row == 2 then
        state.state = 201
    elseif row == 3 then
        sounds.direct(state, "ok")
        options.random_background = false
        if options.background == 100 then options.background = 99
        elseif options.background == 99 then options.background = 0
        else
            options.background = options.background + 1
            if options.background == #state.characters.backgrounds then
                options.background = 100
                options.random_background = true
            end
        end
    elseif row == 4 then
        options.difficulty = options.difficulty - 1
        if options.difficulty < constants.difficulties.difficult then
            options.difficulty = constants.difficulties.easy
        end
        sounds.direct(state, "ok")
    elseif row == 5 then
        state.leave = "title"
    end
    return key
end

function screen.update(state, held, context)
    state.display = {}
    state.leave = nil
    local key = navigation.sample(state.input, held)
    draw_panel(state)
    if state.state == 200 then key = panel_keys(state, key, context) end
    if state.state == 201 then
        reroll(state)
        state.state = 202
        state.config.options_row = 2
        key = options_keys(state, key, context)
    elseif state.state >= 210 and state.state < 220 then
        key = picker_keys(state, key)
    elseif state.state == 202 then
        key = options_keys(state, key, context)
    end
    -- Every attack or defend press clicks; jump cancels.
    if key == "c" or key == "f" then sounds.direct(state, "join") end
    if key == "b" then sounds.direct(state, "cancel") end
    for _, sound in ipairs(sounds.flush(state)) do context.sound(sound.resource, sound.volume, sound.pan) end
    if state.leave then context.action(state.leave) end
end

function screen.draw(state, context)
    context.viewport(794, 550, 0, 0, 0)
    for _, command in ipairs(state.display) do
        local kind = command[1]
        if kind == "image" then context.image(command[2], command[3], command[4], true)
        elseif kind == "sprite" then context.sprite(command[2], command[3], command[4], command[5], command[6])
        elseif kind == "text" then font.gdi(context, command[2], command[3], command[4])
        elseif kind == "fill" then
            local color = command[6]
            context.fill(command[2], command[3], command[4], command[5], color[1], color[2], color[3])
        end
    end
end

-- Match options for base/game/match (mode 4): the character menu's slots plus the troops.
function screen.match_options(state)
    local options = require("base/ui/character_select").match_options(state.characters)
    options.battle = state.config
    return options
end

function screen.describe(state)
    return string.format("battle_state=%d row=%d side=%d options_row=%d", state.state, state.config.row,
        state.config.side, state.config.options_row)
end
return screen
