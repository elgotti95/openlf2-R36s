-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local constants = require("base/game/constants")
local catalog = require("base/game/catalog")
local background = require("base/game/background")
local font = require("base/ui/font")
local sounds = require("base/game/sounds")
local controls = require("base/ui/controls")
local music = require("base/game/music")
local selection = {}
local idle_countdown = 150
local computer_phase, computer_team_phase, computer_done = 11, 12, 13

local function origin(slot)
    return (slot % 4) * 153, math.floor(slot / 4) * 212
end
local function pressed(keys, key) return keys:find(key, 1, true) ~= nil end
local function image(state, path, x, y) state.display[#state.display + 1] = {"image", path, x, y} end
local white, computer_red, option_blue = 0xffffff, 0xff9b9b, 0x9b9bff
local music_title, music_hint = 0x5a77d8, 0x223fa0
local count_greyed, count_box = 0x5068c0, 0x2f479f
-- Red and green step up by 30 every 6th of the counter, from (25, 70); blue stays full.
local function blink_color(state)
    local step = state.blink % 6
    return (step * 30 + 0x19) * 65536 + (step * 30 + 0x46) * 256 + 0xff
end
local function text(state, value, x, y, color, background)
    state.display[#state.display + 1] = {"text", value, x, y, color, background}
end
local function sprite(state, path, rectangle, x, y, keyed)
    state.display[#state.display + 1] = {"sprite", path, rectangle, x, y, keyed}
end
local function fill(state, x, y, width, height, gray)
    state.display[#state.display + 1] = {"fill", x, y, width, height, gray}
end

function selection.create(options)
    local previous = options.previous or {}
    local mode = assert(constants.modes[options.mode], "unknown character menu mode")
    local slots = {}
    for slot = 0, 7 do
        -- Teams persist between visits except where the mode prescribes them.
        local team = previous.slots and previous.slots[slot].team or 0
        if mode == constants.modes.stage then team = constants.teams.player_one
        elseif mode == constants.modes.battle then team = math.floor(slot / 4) + 1 end
        slots[slot] = {phase = 0, fighter = 0, team = team, latched = true, ready = false}
    end
    -- Option values are globals in the original and keep their values between visits.
    local options = previous.options or {row = 2, background = 100, random_background = true,
        difficulty = 0, music = 0, stage_level = 0}
    return {mode = mode, fighters = catalog.load(), backgrounds = catalog.backgrounds(),
        slots = slots, menu = 0, last_menu = 0, options = options,
        countdown = idle_countdown, computers = previous.computers or -100,
        order = {}, cursor = 0, previous_random = false, blink = 0, display = {}}
end

local function pick_fighter(state)
    local candidates = {}
    for index, fighter in ipairs(state.fighters) do
        if fighter.record >= 1 and fighter.id < constants.record_id_ranges.random_fighter_end_exclusive then
            local taken = false
            for slot = 0, 7 do
                if state.slots[slot].fighter == index then taken = true end
            end
            if not taken then candidates[#candidates + 1] = index end
        end
    end
    -- The original would read an uninitialized candidate here.
    assert(#candidates > 0, "no fighter left for a random pick")
    return candidates[engine.random(#candidates) + 1]
end
local function resolve_random(state)
    for index = 0, 7 do state.slots[index].was_random = state.slots[index].fighter == 0 end
    for index = 0, 7 do
        local slot = state.slots[index]
        if slot.was_random then slot.fighter = pick_fighter(state) end
    end
end

-- Fighter 0 is Random; others index the catalog in file order.
local function next_fighter(state, slot) slot.fighter = catalog.step(state.fighters, slot.fighter, 1) end
local function previous_fighter(state, slot) slot.fighter = catalog.step(state.fighters, slot.fighter, -1) end

local function draw_fighter(state, slot, col, row, color)
    local fighter = state.fighters[slot.fighter]
    image(state, fighter and fighter.portrait or "pe/rface", col + 147, row + 94)
    text(state, fighter and fighter.name or " Random", col + 177, row + 241, color)
end
local function draw_team(state, slot, col, row, color)
    if slot.team == constants.teams.independent then text(state, "Independent", col + 167, row + 263, color)
    else text(state, "Team " .. slot.team, col + 187, row + 263, color) end
end

-- The last slot to pick a team may not join the side every other ready slot is on.
local function avoided_team(state, current)
    local avoid = -1
    for index = 0, 7 do
        local other = state.slots[index]
        if index ~= current and other.phase % 10 == 3 then
            if other.team == constants.teams.independent then avoid = -2
            elseif avoid == -1 then avoid = other.team
            elseif avoid >= 0 and other.team ~= avoid then avoid = -2 end
        end
    end
    return avoid
end
local function normalize_team(state, slot, avoid)
    while slot.team == avoid or (state.mode == constants.modes.battle
           and (slot.team == constants.teams.independent or slot.team >= constants.teams.player_three)) do
        slot.team = (slot.team + 1) % 5
    end
end
local function previous_team(state, slot, avoid)
    repeat
        slot.team = slot.team - 1
        if slot.team < 0 then slot.team = constants.teams.player_four end
    until slot.team ~= avoid and not (state.mode == constants.modes.battle
        and (slot.team == constants.teams.independent or slot.team > constants.teams.player_two))
end

-- A key press acts once per latch; returns whether the action should run now.
local function trigger(slot, allowed)
    local run = not slot.latched and allowed ~= false
    slot.latched = true
    return run
end

local function empty_slot(state, index, slot, keys, col, row, all_empty)
    if state.countdown == idle_countdown then
        image(state, state.blink % 5 < 3 and "pe/cma" or "pe/cma2", col + 147, row + 120)
    elseif state.countdown >= 0 then
        image(state, "pe/cm" .. (math.floor(state.countdown / 30) + 1), col + 181, row + 125)
    end
    if pressed(keys, "c") then
        if trigger(slot, state.last_menu == 0) then
            slot.phase = 1
            sounds.direct(state, "join")
        end
    elseif pressed(keys, "b") and all_empty then
        if trigger(slot) then
            state.leave = true
            sounds.direct(state, "cancel")
        end
    else
        slot.latched = false
    end
end

local function fighter_slot(state, slot, keys)
    if pressed(keys, "r") then
        if trigger(slot) then next_fighter(state, slot) end
    elseif pressed(keys, "l") then
        if trigger(slot) then previous_fighter(state, slot) end
    elseif pressed(keys, "u") then
        if trigger(slot) then slot.fighter = 0 end
    elseif pressed(keys, "c") then
        if trigger(slot) then
            slot.phase = state.mode == constants.modes.stage and 3 or 2
            sounds.direct(state, "join")
        end
    elseif pressed(keys, "b") then
        if trigger(slot) then
            slot.phase = 0
            sounds.direct(state, "cancel")
        end
    else
        slot.latched = false
    end
end

local function team_slot(state, index, slot, keys, col, row)
    local avoid = -1
    local ready = 0
    for other = 0, 7 do
        if state.slots[other].phase == 3 then ready = ready + 1 end
    end
    if ready == 7 and (state.mode == constants.modes.versus or state.mode == constants.modes.battle) then
        avoid = avoided_team(state, index)
    end
    normalize_team(state, slot, avoid)
    draw_team(state, slot, col, row, blink_color(state))
    if state.mode == constants.modes.championship then
        -- Championship: Independent, with attack forced on; right/left still take priority.
        slot.team = constants.teams.independent
        slot.latched = false
        keys = keys .. "c"
    end
    if pressed(keys, "r") then
        if trigger(slot) then
            repeat
                repeat slot.team = (slot.team + 1) % 5 until slot.team ~= avoid
            until not (state.mode == constants.modes.battle
                and (slot.team == constants.teams.independent or slot.team > constants.teams.player_two))
        end
    elseif pressed(keys, "l") then
        if trigger(slot) then previous_team(state, slot, avoid) end
    elseif pressed(keys, "c") then
        if trigger(slot) then
            slot.phase = 3
            sounds.direct(state, "join")
        end
    elseif pressed(keys, "b") then
        if trigger(slot) then
            slot.phase = 1
            sounds.direct(state, "cancel")
        end
    else
        slot.latched = false
    end
end

local function ready_slot(state, slot, keys)
    if state.menu ~= 0 then return false end
    if not pressed(keys, "b") then
        slot.latched = false
    elseif state.countdown == idle_countdown then
        if trigger(slot) then
            slot.phase = state.mode == constants.modes.stage and 1 or 2
            sounds.direct(state, "cancel")
        end
    elseif trigger(slot) then
        return true
    end
    return false
end

local function slots_pass(state, held)
    local all_empty = false
    if state.menu == 0 then
        all_empty = true
        for index = 0, 7 do
            if state.slots[index].phase ~= 0 then all_empty = false end
        end
    end
    local ready_count, idle_count, skip = 0, 0, false
    for index = 0, 7 do
        local slot = state.slots[index]
        local keys = held[index] or ""
        local col, row = origin(index)
        if slot.phase < 1 then
            -- "Join?" blinks while the join screen runs; afterwards the empty slot shows dashes.
            if state.menu == 0 then text(state, "   Join?", col + 177, row + 219, blink_color(state))
            else text(state, "     ----", col + 177, row + 219, white) end
        elseif slot.phase < computer_phase then text(state, controls.name(index), col + 177, row + 219, white)
        else text(state, "Computer", col + 177, row + 219, computer_red) end
        if slot.phase == 0 and state.menu == 0 then empty_slot(state, index, slot, keys, col, row, all_empty) end
        if slot.phase == 1 then
            draw_fighter(state, slot, col, row, blink_color(state))
            fighter_slot(state, slot, keys)
        end
        if slot.phase == 2 then
            draw_fighter(state, slot, col, row, white)
            team_slot(state, index, slot, keys, col, row)
        end
        slot.ready = false
        if slot.phase == 3 then
            draw_fighter(state, slot, col, row, white)
            draw_team(state, slot, col, row, white)
            if ready_slot(state, slot, keys) then skip = true end
            if slot.phase == 3 then
                ready_count = ready_count + 1
                slot.ready = true
            end
        end
        if slot.phase == 0 or slot.phase == 3 then idle_count = idle_count + 1 end
    end
    local previous = state.countdown
    if ready_count < 1 or idle_count ~= 8 then
        state.countdown = idle_countdown
    else
        state.countdown = state.countdown - 1
        if skip then state.countdown = previous - 31 end
        if ready_count == 8 then state.countdown = 0 end
    end
end

local function computer_count_menu(state, previous_menu)
    image(state, "pe/cmc", 218, 215)
    local free, sides, teams = 0, 0, {}
    for index = 0, 7 do
        local slot = state.slots[index]
        if not slot.ready then free = free + 1
        elseif slot.team == constants.teams.independent or not teams[slot.team] then
            teams[slot.team] = true
            sides = sides + 1
        end
    end
    if free == 0 then state.menu = 3 end
    local minimum = (sides < 2 and state.mode ~= constants.modes.stage) and 1 or 0
    if state.computers == -100 or state.computers < minimum or free < state.computers then
        state.computers = minimum
    end
    local accept = previous_menu == 1
    for index = 0, 7 do
        local slot = state.slots[index]
        if slot.ready then
            local keys = state.held[index] or ""
            local auto = state.mode == constants.modes.championship or state.mode == constants.modes.team_championship
            if pressed(keys, "r") then
                if trigger(slot, accept) then
                    state.computers = state.computers + 1
                    if free < state.computers then state.computers = minimum end
                end
            elseif pressed(keys, "l") then
                if trigger(slot, accept) then
                    state.computers = state.computers - 1
                    if state.computers < minimum then state.computers = free end
                end
            elseif pressed(keys, "c") or auto then
                if auto then
                    slot.latched = false
                    state.computers = free
                end
                if trigger(slot, accept) then
                    if not auto then sounds.direct(state, "ok") end
                    state.menu = 2
                    state.order, state.cursor = {}, 0
                    if state.computers == 0 then
                        state.options.row = 2
                        resolve_random(state)
                        state.menu = 3
                    else
                        for other = 0, 7 do
                            if not state.slots[other].ready and #state.order < state.computers then
                                state.order[#state.order + 1] = other
                                state.slots[other].phase = computer_phase
                            end
                        end
                    end
                    break
                end
            else
                slot.latched = false
            end
        end
    end
    for number = 0, 7 do
        local x = 280 + number * 30
        -- Digits the choice cannot reach (below the minimum, or more than the free slots) are greyed.
        local unavailable = number < minimum or free < number
        text(state, tostring(number), x + 6, 286, unavailable and count_greyed or white, count_box)
        if state.computers == number then
            fill(state, x, 283, 21, 1, 255)
            fill(state, x, 283, 1, 21, 255)
            fill(state, x, 303, 21, 1, 255)
            fill(state, x + 20, 283, 1, 21, 255)
        end
    end
end

-- Menu 2: ready human slots choose each computer's fighter, then its team.
local function computer_keys(state, previous_menu)
    local actions = {}
    if state.menu ~= 2 then return actions end
    local accept = previous_menu == 2
    for index = 0, 7 do
        local slot = state.slots[index]
        if slot.ready then
            local keys = state.held[index] or ""
            if pressed(keys, "u") then actions.random = trigger(slot, accept) or actions.random
            elseif pressed(keys, "d") then slot.latched = true
            elseif pressed(keys, "r") then actions.next = trigger(slot, accept) or actions.next
            elseif pressed(keys, "l") then actions.previous = trigger(slot, accept) or actions.previous
            elseif pressed(keys, "c") then actions.confirm = trigger(slot, accept) or actions.confirm
            elseif pressed(keys, "b") then actions.back = trigger(slot, accept) or actions.back
            else slot.latched = false end
        end
    end
    return actions
end

local function advance_computer(state)
    local current = state.slots[state.order[state.cursor + 1]]
    current.phase = computer_done
    state.previous_random = current.fighter == 0
    state.cursor = state.cursor + 1
    if state.cursor < state.computers then
        state.slots[state.order[state.cursor + 1]].phase = computer_phase
        return false
    end
    resolve_random(state)
    state.options.row = 2
    state.menu = 3
    return true
end

local function computer_menu(state, previous_menu)
    local actions = computer_keys(state, previous_menu)
    for position = 1, state.computers do
        local index = state.order[position]
        local slot = state.slots[index]
        local col, row = origin(index)
        if slot.phase > computer_phase then draw_fighter(state, slot, col, row, computer_red) end
        if slot.phase > computer_team_phase then draw_team(state, slot, col, row, computer_red) end
    end
    local index = state.order[state.cursor + 1]
    local slot = index and state.slots[index]
    if slot and slot.phase == computer_phase then
        local col, row = origin(index)
        draw_fighter(state, slot, col, row, blink_color(state))
        if actions.next then next_fighter(state, slot) end
        if actions.previous then previous_fighter(state, slot) end
        if actions.random then slot.fighter = 0 end
        if state.previous_random then
            slot.fighter = 0
            state.previous_random = false
        end
        if actions.confirm then
            actions.confirm = false
            sounds.direct(state, "join")
            slot.phase = computer_team_phase
            if state.mode == constants.modes.stage and advance_computer(state) then return end
        end
        if actions.back then
            actions.back = false
            sounds.direct(state, "cancel")
            if state.cursor == 0 then
                state.menu = 1
                for other = 0, 7 do
                    if state.slots[other].phase == computer_phase then state.slots[other].phase = 0 end
                end
            else
                state.cursor = state.cursor - 1
                local previous = state.slots[state.order[state.cursor + 1]]
                previous.phase = (state.mode == constants.modes.stage or state.mode == constants.modes.championship)
                    and computer_phase or computer_team_phase
            end
        end
    end
    index = state.order[state.cursor + 1]
    slot = index and state.slots[index]
    if slot and slot.phase == computer_team_phase then
        local col, row = origin(index)
        local avoid = -1
        if state.cursor == state.computers - 1 and (state.mode == constants.modes.versus or state.mode == constants.modes.battle) then
            avoid = avoided_team(state, index)
        end
        normalize_team(state, slot, avoid)
        draw_team(state, slot, col, row)
        if actions.next then
            slot.team = (slot.team + 1) % 5
            if slot.team == avoid then slot.team = (slot.team + 1) % 5 end
        end
        if actions.previous then previous_team(state, slot, avoid) end
        if state.mode == constants.modes.championship then
            slot.team = constants.teams.independent
            actions.confirm = true
        end
        if actions.confirm then
            sounds.direct(state, "join")
            if advance_computer(state) then return end
        end
        if actions.back then
            sounds.direct(state, "cancel")
            slot.phase = computer_phase
            state.previous_random = false
        end
    end
end

local options_sheet = "pe/menu_clip3"
local option_highlights = {
    [0] = {{407, 183, 126, 21}, 92, 16}, {{379, 206, 186, 21}, 64, 39}, {{355, 231, 235, 21}, 40, 64},
    {{330, 254, 279, 22}, 15, 87}, {{352, 278, 228, 22}, 37, 111}, {{416, 304, 111, 19}, 101, 137},
}
local difficulties = {[2] = "Easy", [1] = "Normal", [0] = "Difficult", [-1] = "CRAZY!"}
local music_names = {[0] = "Random", "Main Theme", "Stage 1", "Stage 2", "Stage 3", "Stage 4",
    "Stage 5", "Boss", "Final Boss"}
local function background_name(state, row)
    if row == 99 then return "Lee On Road" end
    if row == 100 then return "Random" end
    local entry = state.backgrounds[row + 1]
    return entry and background.load(entry.path).name or ""
end

local function music_option(state, left, right)
    local options = state.options
    local index = options.music
    local label
    if state.mode == constants.modes.stage then
        if left or right then index = index == -1 and 0 or -1 end
        label = index == -1 and "OFF" or "ON"
    else
        if right then index = index + 1 end
        if index > 8 then index = -1 end
        if left then index = index - 1 end
        if index < -1 then index = 8 end
        if index == 0 then options.track = engine.random(8) + 1
        elseif index > 0 then options.track = index
        else options.track = nil end
        music.selected = options.track and music.tracks[options.track] or nil
        label = index == -1 and "OFF" or music_names[index]
    end
    options.music = index
    if index == -1 then
        music.enabled = false
        music.stop()
    else
        music.enabled = true
    end
    text(state, "Music: " .. label, 603, 3, music_title)
    text(state, "(Press Left/Right to change)", 603, 20, music_hint)
end

local function options_menu(state, previous_menu, context)
    local options = state.options
    sprite(state, options_sheet, {348, 0, 304, 156}, 3, 3, false)
    sprite(state, options_sheet, {348, 156, 304, 10}, 3, 159, true)
    local highlight = option_highlights[options.row]
    sprite(state, options_sheet, highlight[1], highlight[2], highlight[3], false)
    if options.random_background then options.background = 100 end
    if state.mode == constants.modes.stage then
        options.stage_level = options.stage_level - options.stage_level % 10
        sprite(state, options_sheet, {330, 363, 279, 22}, 15, 87, false)
        if options.row == 3 then sprite(state, options_sheet, {330, 332, 279, 22}, 15, 87, false) end
        local level = math.floor(options.stage_level / 10)
        if level < 5 then text(state, tostring(level + 1), 194, 91, option_blue)
        else text(state, "Survival", 174, 91, option_blue) end
    else
        text(state, background_name(state, options.background), 174, 91, option_blue)
    end
    text(state, difficulties[options.difficulty] or "", 174, 115, option_blue)

    local keys = {}
    local accept = previous_menu == 3
    for index = 0, 7 do
        local slot = state.slots[index]
        if slot.ready then
            local held = state.held[index] or ""
            local key
            for _, candidate in ipairs({"u", "d", "r", "l", "c"}) do
                if pressed(held, candidate) then key = candidate; break end
            end
            if key then
                keys[key] = trigger(slot, accept) or keys[key]
            else
                -- Jump neither acts nor releases the latch here.
                slot.latched = pressed(held, "b")
            end
        end
    end
    if keys.u then
        options.row = options.row - 1
        if options.row < 0 then options.row = 5 end
    end
    if keys.d then options.row = (options.row + 1) % 6 end
    music_option(state, keys.l, keys.r)
    if not keys.c then return end
    sounds.direct(state, "ok")
    if options.row == 0 then
        if state.mode == constants.modes.versus then music.play_selected() end
        -- The flow reads selection.match_options(state) to build the match.
        context.action("start_match")
    elseif options.row == 4 then
        options.difficulty = options.difficulty - 1
        local unlocked = require("base/game/unlock").flags.characters
        if (options.difficulty < constants.difficulties.difficult and unlocked == 0)
           or options.difficulty < constants.difficulties.crazy then
            options.difficulty = constants.difficulties.easy
        end
    elseif options.row == 5 then
        context.action("title")
    elseif options.row == 1 then
        for index = 0, 7 do
            local slot = state.slots[index]
            slot.phase = 0
            slot.latched = true
            if slot.was_random then slot.fighter = 0 end
        end
        state.countdown = idle_countdown
        state.menu = 0
    elseif options.row == 3 then
        if state.mode == constants.modes.stage then
            options.stage_level = (options.stage_level + 10) % 60
        else
            options.random_background = false
            if options.background == 100 then options.background = 99
            elseif options.background == 99 then options.background = 0
            else
                options.background = options.background + 1
                if options.background == #state.backgrounds then
                    options.background = 100
                    options.random_background = true
                end
            end
        end
    elseif options.row == 2 then
        for index = 0, 7 do
            local slot = state.slots[index]
            if slot.was_random then slot.fighter = pick_fighter(state) end
        end
    end
end

function selection.reset_all(state)
    for index = 0, 7 do
        local slot = state.slots[index]
        slot.phase = 0
        slot.latched = true
        if slot.was_random then slot.fighter = 0 end
    end
    state.countdown = idle_countdown
    state.menu, state.last_menu = 0, 0
    state.display = {}
    return state
end

function selection.resume_options(state, outcome)
    if outcome and outcome.stage_level then state.options.stage_level = outcome.stage_level end
    for index = 0, 7 do state.slots[index].latched = true end
    state.menu, state.last_menu = 3, 3
    state.display = {}
    return state
end

-- Match setup for base/game/match: human slots are joined (1-10), computers 11 and up.
function selection.match_options(state)
    local slots = {}
    for index = 0, 7 do
        local slot = state.slots[index]
        if slot.phase >= 1 and slot.phase <= 10 then
            slots[index] = {kind = "human", fighter = slot.fighter, team = slot.team}
        elseif slot.phase >= 11 then
            slots[index] = {kind = "computer", fighter = slot.fighter, team = slot.team}
        end
    end
    return {mode = state.mode, difficulty = state.options.difficulty, background = state.options.background,
        stage_level = state.options.stage_level,
        fighters = state.fighters, backgrounds = state.backgrounds, slots = slots}
end

function selection.update(state, held, context)
    state.display = {}
    state.held = held
    state.leave = false
    state.blink = (state.blink + 1) % 30
    local previous_menu = state.menu
    fill(state, 0, 0, 794, 550, 0)
    image(state, "pe/charmenu", 40, 33)
    slots_pass(state, held)
    state.last_menu = state.menu
    if state.menu == 1 then computer_count_menu(state, previous_menu) end
    if state.menu == 2 or state.menu == 3 then computer_menu(state, previous_menu) end
    if state.countdown < 1 and state.menu == 0 then state.menu = 1 end
    if state.leave then context.action("title") end
    if state.menu == 3 and state.mode ~= constants.modes.battle then
        options_menu(state, previous_menu, context)
    elseif state.menu == 3 and previous_menu ~= 3 then
        context.action("battle_setup")
    end
    for _, sound in ipairs(sounds.flush(state)) do context.sound(sound.resource, sound.volume, sound.pan) end
end

function selection.draw(state, context)
    context.viewport(794, 550, 0, 0, 0)
    for _, command in ipairs(state.display) do
        if command[1] == "image" then context.image(command[2], command[3], command[4], false)
        elseif command[1] == "sprite" then
            context.sprite(command[2], command[3], command[4], command[5], command[6])
        elseif command[1] == "text" then font.gdi(context, command[2], command[3], command[4], command[5], command[6])
        elseif command[1] == "fill" then
            context.fill(command[2], command[3], command[4], command[5], command[6], command[6], command[6])
        end
    end
end
-- Headless traces: menu, countdown and each slot's phase:fighter:team.
function selection.describe(state)
    local slots = {}
    for index = 0, 7 do
        local slot = state.slots[index]
        slots[#slots + 1] = string.format("%d:%d:%d", slot.phase, slot.fighter, slot.team)
    end
    return string.format("menu=%d countdown=%d slots=%s", state.menu, state.countdown, table.concat(slots, ","))
end
return selection
