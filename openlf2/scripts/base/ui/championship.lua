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
local function random(range) return engine.random(range) end

local clip3, clip4 = "pe/menu_clip3", "pe/menu_clip4"
local frames = {[0] = {0, 0, 713, 332}, {0, 335, 40, 45}, {46, 335, 235, 111}, {0, 461, 171, 38},
    {183, 461, 173, 38}, {284, 335, 52, 19}, {342, 334, 47, 20}, {284, 356, 59, 24}, {345, 356, 59, 24},
    {170, 0, 543, 332}, {414, 340, 282, 239}, {717, 0, 15, 19}, {717, 21, 15, 19}, {717, 42, 15, 19},
    {717, 63, 15, 19}, {717, 84, 15, 19}, {717, 105, 15, 19}, {717, 126, 15, 19}, {717, 147, 15, 19},
    {142, 508, 258, 58}, {288, 386, 117, 25}}
local bar_size = {{4, 34}, {34, 4}, {4, 35}, {64, 4}, {4, 38}, {124, 4}, {4, 34}}
local bar_position = {
    [0] = {{235, 221}, {235, 217}, {265, 182}, {265, 178}, {325, 140}, {325, 136}, {445, 102}},
    {{295, 221}, {265, 217}, {265, 182}, {265, 178}, {325, 140}, {325, 136}, {445, 102}},
    {{355, 221}, {355, 217}, {385, 182}, {325, 178}, {325, 140}, {325, 136}, {445, 102}},
    {{415, 221}, {385, 217}, {385, 182}, {325, 178}, {325, 140}, {325, 136}, {445, 102}},
    {{475, 221}, {475, 217}, {505, 182}, {505, 178}, {565, 140}, {445, 136}, {445, 102}},
    {{535, 221}, {505, 217}, {505, 182}, {505, 178}, {565, 140}, {445, 136}, {445, 102}},
    {{595, 221}, {595, 217}, {625, 182}, {565, 178}, {565, 140}, {445, 136}, {445, 102}},
    {{655, 221}, {625, 217}, {625, 182}, {565, 178}, {565, 140}, {445, 136}, {445, 102}},
}
local option_highlights = {
    [0] = {{407, 183, 126, 21}, 92, 16}, {{379, 206, 186, 21}, 64, 39}, {{355, 231, 235, 21}, 40, 64},
    {{330, 254, 279, 22}, 15, 87}, {{352, 278, 228, 22}, 37, 111}, {{416, 304, 111, 19}, 101, 137},
}
local difficulties = {[2] = "Easy", [1] = "Normal", [0] = "Difficult", [-1] = "Difficult"}
local clip3_frames = {[16] = {364, 455, 429, 6}, [17] = {367, 469, 63, 26}, [18] = {487, 469, 63, 26},
    [19] = {607, 469, 63, 26}, [20] = {727, 469, 63, 26}, [21] = {285, 458, 63, 21}}

-- options: the shared match options (background, difficulty); team: Team Championship.
function screen.create(options, team)
    local state = {fighters = catalog.load(), backgrounds = catalog.backgrounds(), options = options,
        team = team, teams = {},
        state = 0x14, input = navigation.create(), display = {}, portraits = {}, blink = 0,
        entrants = {}, order = {}, wins = {}, hp = {}, transform = {}, round = 0, pair = {}, counter = 0,
        slot = 0, stage = 0, row = 0, taken = {}, previous_attack = {}}
    return state
end

local function add(state, command) state.display[#state.display + 1] = command end
local function sprite(state, resource, source, x, y, keyed) add(state, {"sprite", resource, source, x, y, keyed}) end
local function image(state, resource, x, y) add(state, {"image", resource, x, y}) end
local function text(state, value, x, y, color, background) add(state, {"text", value, x, y, color, background}) end
local white, option_blue, label_box = 0xffffff, 0x9b9bff, 0x2f478f
local human_label, computer_label = 0x4d79e6, 0xc87996
local function blink_color(state)
    local step = state.blink % 6
    return (step * 30 + 0x19) * 65536 + (step * 30 + 0x46) * 256 + 0xff
end
local function fill(state, x, y, width, height, color) add(state, {"fill", x, y, width, height, color}) end

local function small_portrait(state, fighter)
    if state.portraits[fighter.path] == nil then
        local small = object_data.load(fighter.path).small
        state.portraits[fighter.path] = small and (small:lower():gsub("\\", "/")) or false
    end
    return state.portraits[fighter.path] or nil
end

-- Bracket bars: segments first+1..count of bracket position `slot`'s path toward the final.
local function bars(state, slot, count, color, first)
    for bar = (first or 0) + 1, count do
        local position, size = bar_position[slot][bar], bar_size[bar]
        fill(state, position[1] - 51, position[2] + 126, size[1], size[2], color)
    end
end

local function entrant_fighter(state, index) return state.fighters[state.entrants[index].fighter] end

-- State 0x14: every entrant starts as Random and Computer, in draw order 0..7.
local function setup(state)
    state.state = 0x15
    state.slot, state.stage = 0, 0
    for index = 0, 7 do
        state.entrants[index] = {fighter = 0, random = true, human = 0}
        state.order[index] = index
        state.teams[index] = math.floor(index / 2) + 1
    end
end

-- States 0x15-0x17 and later: the selection panel and the entrants' small portraits.
local function selection(state, key)
    local offset_x, offset_y
    if state.state < 0x18 then
        offset_x, offset_y = 27, 106
        sprite(state, clip4, frames[0], 27, 106, false)
        fill(state, 47, 384, 131, 41, {0x32, 0x4d, 0x9a})
    else
        offset_x, offset_y = -51, 126
        sprite(state, clip4, frames[9], 119, 126, false)
    end
    if state.team then
        -- Team panels: MENU_CLIP3 frame 21, the line (16) and each pair's team label (16 + team).
        sprite(state, clip3, clip3_frames[21], offset_x + 309, offset_y + 23, false)
        sprite(state, clip3, clip3_frames[16], offset_x + 232, offset_y + 215, false)
        for pair = 0, 3 do
            local x = offset_x + 237 + pair * 120
            fill(state, x - 5, offset_y + 221, 73, 36, {0x32, 0x4d, 0x9a})
            sprite(state, clip3, clip3_frames[state.teams[pair * 2] + 16], x, offset_y + 223, false)
        end
    end
    local slot = state.slot
    if slot < 8 then
        local entrant = state.entrants[slot]
        if state.stage == 0 then
            if key == "u" then
                entrant.fighter, entrant.random = 0, true
            elseif key == "r" then
                entrant.fighter = catalog.step(state.fighters, entrant.fighter, 1)
                entrant.random = entrant.fighter == 0
            elseif key == "l" then
                entrant.fighter = catalog.step(state.fighters, entrant.fighter, -1)
                entrant.random = entrant.fighter == 0
            end
            if key == "c" then
                key = ""
                sounds.direct(state, "join")
                state.stage = 1
            elseif key == "b" then
                key = ""
                sounds.direct(state, "cancel")
                if state.slot < 1 then
                    state.leave = "title"
                else
                    state.slot = state.slot - 1
                    state.stage = 1
                end
            end
            slot = state.slot
        end
        entrant = state.entrants[slot]
        local fighter = state.fighters[entrant.fighter]
        image(state, fighter and fighter.portrait or "pe/rface", offset_x + 25, offset_y + 53)
        text(state, fighter and fighter.name or " Random", offset_x + 59, offset_y + 206,
            state.stage == 0 and blink_color(state) or white)
        if state.stage == 1 then
            if key == "r" or key == "l" then entrant.human = entrant.human < 1 and 1 or 0 end
            if key == "c" then
                key = ""
                sounds.direct(state, "join")
                state.stage = 0
                state.slot = state.slot + 1
                if state.slot == 8 then
                    state.state = 0x16
                    state.row = 0
                end
            elseif key == "b" then
                key = ""
                sounds.direct(state, "cancel")
                state.stage = state.stage - 1
            else
                text(state, entrant.human == 0 and "Computer" or " Human", offset_x + 59, offset_y + 253, blink_color(state))
            end
        end
    end
    -- Humans are numbered 1, 2, ... in slot order.
    local step = 0
    for index = 0, math.min(state.slot, 8) - 1 do
        if state.entrants[index].human > 0 then
            step = step + 1
            state.entrants[index].human = step
        end
    end
    local function draw_entrant(position, index, label)
        local fighter = entrant_fighter(state, index)
        local x, y, label_x, label_y = offset_x + 216 + position * 60, offset_y + 260, 13, 307
        if state.team then
            -- Pairs sit together: odd positions move 20 px left.
            x = offset_x + position * 60 + (position % 2 ~= 0 and -20 or 0) + 226
            y, label_x, label_y = offset_y + 252, 13, 299
        end
        if fighter then
            local portrait = small_portrait(state, fighter)
            if portrait then image(state, portrait, x, y) end
        else
            sprite(state, clip4, frames[1], x, y, false)
        end
        if label then
            text(state, label, x + label_x, offset_y + label_y, label == "C" and computer_label or human_label, label_box)
        end
    end
    for position = 0, math.min(state.slot, 8) - 1 do
        local index = state.order[position]
        local entrant = state.entrants[index]
        draw_entrant(position, index, entrant.human == 0 and "C" or tostring(entrant.human))
    end
    if state.slot < 8 then
        local entrant = state.entrants[state.slot]
        draw_entrant(state.slot, state.slot,
            state.stage > 0 and (entrant.human == 0 and "C" or tostring(step + 1)) or nil)
    end
    return key
end

-- The two-choice menu of 0x16 (and before a match): MENU_CLIP4 frames 2, 3/4, 5, 6, 7/8.
local function two_choice(state, caption)
    sprite(state, clip4, frames[2], 278, 162, false)
    sprite(state, clip4, frames[caption], 314, 179, false)
    sprite(state, clip4, frames[5], 322, 232, false)
    sprite(state, clip4, frames[6], 426, 232, false)
    if state.row == 0 then sprite(state, clip4, frames[7], 319, 229, false)
    else sprite(state, clip4, frames[8], 420, 230, false) end
end

local function random_fighters(state)
    for index = 0, 7 do
        local entrant = state.entrants[index]
        if entrant.random then
            local candidates = {}
            for position, fighter in ipairs(state.fighters) do
                local used = false
                for other = 0, 7 do
                    if state.entrants[other].fighter == position then used = true end
                end
                if fighter.record ~= 0 and not used
                   and fighter.id < constants.record_id_ranges.random_fighter_end_exclusive then
                    candidates[#candidates + 1] = position
                end
            end
            entrant.fighter = candidates[random(#candidates) + 1]
        end
    end
end

local function background_name(state, row)
    if row == 99 then return "Lee On Road" end
    if row == 100 then return "Random" end
    local entry = state.backgrounds[row + 1]
    return entry and background.load(entry.path).name or ""
end

local function options_panel(state, key)
    local options = state.options
    sprite(state, clip3, {348, 0, 304, 156}, 3, 3, false)
    sprite(state, clip3, {348, 156, 304, 10}, 3, 159, true)
    local highlight = option_highlights[state.row]
    sprite(state, clip3, highlight[1], highlight[2], highlight[3], false)
    if options.random_background then options.background = 100 end
    text(state, background_name(state, options.background), 174, 91, option_blue)
    text(state, difficulties[options.difficulty] or "", 174, 115, option_blue)
    if key == "u" then
        state.row = state.row - 1
        if state.row == -1 then state.row = 5 end
    end
    if key == "d" then state.row = (state.row + 1) % 6 end
    if key == "b" then
        sounds.direct(state, "cancel")
        state.state = 0x16
        state.row = 0
        for index = 0, 7 do
            if state.entrants[index].random then state.entrants[index].fighter = 0 end
        end
        return ""
    end
    if key ~= "c" then return key end
    sounds.direct(state, "ok")
    local row = state.row
    if row == 0 then
        state.state = 0x1a
        music.play_selected()
        for index = 0, 7 do
            state.hp[index], state.transform[index], state.wins[index] = 500, -1, 0
        end
        if state.team then
            for index = 0, 7 do state.wins[index] = 2 end
        end
        state.counter, state.round = 25, 0
    elseif row == 1 then
        state.state = 0x14
    elseif row == 2 then
        state.state = 0x18
    elseif row == 3 then
        sounds.direct(state, "ok")
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
    elseif row == 4 then
        options.difficulty = options.difficulty - 1
        if options.difficulty < constants.difficulties.difficult then
            options.difficulty = constants.difficulties.easy
        end
        sounds.direct(state, "ok")
    elseif row == 5 then
        state.leave = "title"
    end
    return ""
end

local function human_of(state, slot) return state.entrants[state.order[slot]].human end

local function kind_of(state, slot) return cdiv(entrant_fighter(state, state.order[slot]).id, 10) end
local highlight = {0xff, 0xa0, 0xa0}
local team_highlight = {0xff, 0xa7, 0xa7}

-- Team version of 0x1a: the first two pairs at the round level meet; simulated results favor
-- a side with a boss, and both winners lose some hp.
local function next_teams(state, key)
    local found = 0
    for index = 0, 7, 2 do
        if state.wins[index] == state.round then
            state.pair[found], state.pair[found + 1] = index, index + 1
            found = found + 2
            if found == 4 then break end
        end
    end
    if found == 0 then
        if state.round < 6 then state.round = state.round + 2 end
        return
    end
    if found ~= 4 then return end
    if state.counter > 30 then
        local shown = state.blink % 10 >= 5 and state.pair[2] or state.pair[0]
        bars(state, shown, math.min(state.wins[shown] + 2, 7), team_highlight, 2)
    end
    state.counter = state.counter + 1
    if key == "b" then state.counter = 80 elseif state.counter ~= 80 then return end
    local all_computers = true
    for member = 0, 3 do
        if human_of(state, state.pair[member]) ~= 0 then all_computers = false end
    end
    if all_computers then
        sounds.direct(state, "join")
        local side_a = kind_of(state, state.pair[0]) == 5 or kind_of(state, state.pair[1]) == 5
        local side_b = kind_of(state, state.pair[2]) == 5 or kind_of(state, state.pair[3]) == 5
        state.counter = 0
        local winner
        if side_a and not side_b then winner = 0
        elseif not side_a and side_b then winner = 2
        else winner = random(2) * 2 end
        local first, second = state.pair[winner], state.pair[winner + 1]
        state.wins[first] = state.wins[first] + 2
        state.wins[second] = state.wins[second] + 2
        state.wins[state.pair[2 - winner]] = state.wins[state.pair[2 - winner]] + 1
        state.wins[state.pair[3 - winner]] = state.wins[state.pair[3 - winner]] + 1
        if state.wins[first] == 6 then state.wins[first] = 7 end
        if state.wins[second] == 6 then state.wins[second] = 7 end
        -- No clamp of the difficulty here, unlike 1 on 1.
        local spread = state.options.difficulty
        local roll = random(spread * 18 + 15)
        state.hp[first] = cdiv((roll - spread * 18 + 85) * state.hp[first], 100)
        roll = random(spread * 18 + 15)
        state.hp[second] = cdiv((roll - spread * 18 + 85) * state.hp[second], 100)
    else
        state.state = 0x1b
        state.counter = 0
        state.taken = {}
        for member = 0, 3 do state.wins[state.pair[member]] = state.wins[state.pair[member]] + 1 end
    end
end

-- State 0x1a: the next pair is the first two entrants whose progress equals the round level.
local function next_pair(state, key)
    if state.team then return next_teams(state, key) end
    local found = 0
    for index = 0, 7 do
        if state.wins[index] == state.round then
            state.pair[found] = index
            found = found + 1
            if found == 2 then break end
        end
    end
    if found == 0 then
        if state.round < 6 then state.round = state.round + 2 end
        return
    end
    if found ~= 2 then return end
    if state.counter > 30 then
        local shown = state.pair[0]
        if state.blink % 10 > 4 then shown = state.pair[1] end
        bars(state, shown, math.min(state.wins[shown] + 2, 7), {0xff, 0xa0, 0xa0})
    end
    state.counter = state.counter + 1
    if key == "b" then state.counter = 80 elseif state.counter ~= 80 then return end
    local first, second = state.pair[0], state.pair[1]
    if human_of(state, first) == 0 and human_of(state, second) == 0 then
        -- Two computers: the result is drawn, bosses (ids 50-59) always win.
        sounds.direct(state, "join")
        local first_kind = cdiv(entrant_fighter(state, state.order[first]).id, 10)
        local second_kind = cdiv(entrant_fighter(state, state.order[second]).id, 10)
        state.counter = 0
        local winner
        if first_kind == 5 then winner = second_kind == 5 and random(2) or 1
        elseif second_kind ~= 5 then winner = random(2)
        else winner = 0 end
        local won = state.pair[winner]
        state.wins[won] = state.wins[won] + 2
        state.wins[state.pair[1 - winner]] = state.wins[state.pair[1 - winner]] + 1
        if state.wins[won] == 6 then state.wins[won] = 7 end
        local spread = state.options.difficulty
        if spread < -1 then spread = 0 end
        spread = random(spread * 12 + 15)
        state.hp[won] = cdiv((spread - state.options.difficulty * 12 + 85) * state.hp[won], 100)
    else
        state.state = 0x1b
        state.counter = 0
        state.taken = {}
        state.wins[first] = state.wins[first] + 1
        state.wins[second] = state.wins[second] + 1
    end
end

-- State 0x1b: each human entrant is claimed by a player pressing attack, then the start menu;
-- computers fill the rest.
local function claim(state, key, held, context)
    local members = state.team and 4 or 2
    if state.counter < members then
        local entrant = state.pair[state.counter]
        if state.blink % 10 < 5 then
            bars(state, entrant, math.min(state.wins[entrant] + 1, 7), state.team and team_highlight or highlight,
                state.team and 2 or 0)
        end
        local human = human_of(state, entrant)
        if human < 1 then
            state.counter = state.counter + 1
            state.row = 1
        else
            sprite(state, clip4, frames[10], 10, 10, false)
            sprite(state, clip4, frames[human + 10], 169, 24, false)
            image(state, entrant_fighter(state, state.order[entrant]).portrait, 90, 49)
            -- A player's fresh attack claims the entrant; a player who already has one hears a
            -- cancel sound and the next player is tried.
            for player = 0, 7 do
                local attack = (held[player] or ""):find("c", 1, true) ~= nil
                if attack and not state.previous_attack[player] then
                    if not state.taken[player] then
                        key = ""
                        sounds.direct(state, "join")
                        state.taken[player] = entrant
                        state.counter = state.counter + 1
                        state.previous_attack[player] = true
                        break
                    end
                    sounds.direct(state, "cancel")
                end
            end
        end
    end
    for player = 0, 7 do state.previous_attack[player] = (held[player] or ""):find("c", 1, true) ~= nil end
    if state.counter == members then
        two_choice(state, 4)
        if key == "l" or key == "r" then state.row = 1 - state.row end
        if key == "c" then
            key = ""
            sounds.direct(state, "join")
            if state.row ~= 0 then
                state.counter = 0
                state.taken = {}
                return key
            end
            state.counter = members + 1
        else
            return key
        end
    end
    if state.counter ~= members + 1 then return key end
    -- Computers take the computer slot of the first player slot without a human.
    state.computers = {}
    for position = 0, members - 1 do
        local entrant = state.pair[position]
        if human_of(state, entrant) == 0 then
            for index = 0, 7 do
                if not state.taken[index] and not state.computers[index] then
                    sounds.direct(state, "join")
                    state.computers[index] = entrant
                    break
                end
            end
        end
    end
    state.state = 0x1c
    context.action("start_match")
    return key
end

-- Match options for base/game/match: claimed entrants as humans (slot i), others as computers
-- (slot 10+i), each with its carried hp and transformation; team = entrant + 10.
function screen.match_options(state)
    local slots = {}
    local function entry(kind, entrant)
        local fighter = state.entrants[state.order[entrant]].fighter
        local team = state.team and state.teams[entrant] or entrant + 10
        return {kind = kind, fighter = fighter, team = team, hp = state.hp[entrant],
            transform = state.transform[entrant], entrant = entrant}
    end
    for index = 0, 7 do
        if state.taken[index] then slots[index] = entry("human", state.taken[index])
        elseif state.computers[index] then slots[index] = entry("computer", state.computers[index]) end
    end
    local options = state.options
    local mode = state.team and constants.modes.team_championship or constants.modes.championship
    return {mode = mode, difficulty = options.difficulty, background = options.background,
        fighters = state.fighters, backgrounds = state.backgrounds, slots = slots, tournament_round = state.round}
end

-- State 0x1c (after the round): dark hp/transformations return to entrants; the winner
-- advances (or a random side, if none).
function screen.round_over(state, match)
    if state.team then
        -- A beaten member keeps half its dark hp; the winning team advances (or a random side,
        -- if none).
        for index = 0, 19 do
            local value = match.items[index]
            if value and value.entrant then
                if value.hp <= 0 then value.dark_hp = cdiv(value.dark_hp, 2) end
                state.hp[value.entrant] = value.dark_hp
                state.transform[value.entrant] = value.transformed_to
                if value.team == match.winner then
                    state.wins[value.entrant] = state.wins[value.entrant] + 1
                    if state.wins[value.entrant] == 6 then state.wins[value.entrant] = 7 end
                end
            end
        end
        if match.winner == -1 then
            local side = random(2)
            for member = 0, 1 do
                local entrant = state.pair[side * 2 + member]
                state.wins[entrant] = state.wins[entrant] + 1
                if state.wins[entrant] == 6 then state.wins[entrant] = 7 end
            end
        end
        state.state = 0x1a
        state.taken, state.computers = {}, {}
        return
    end
    for index = 0, 19 do
        local value = match.items[index]
        if value and value.entrant then
            state.hp[value.entrant] = value.dark_hp
            state.transform[value.entrant] = value.transformed_to
        end
    end
    local winner = match.winner
    local advancing
    if winner < 10 then advancing = state.pair[random(2)] else advancing = winner - 10 end
    state.wins[advancing] = state.wins[advancing] + 1
    if state.wins[advancing] == 6 then state.wins[advancing] = 7 end
    state.state = 0x1a
    state.taken, state.computers = {}, {}
end

function screen.update(state, held, context)
    state.display = {}
    state.leave = nil
    local key = navigation.sample(state.input, held)
    if state.state == 0x14 then setup(state) end
    state.blink = (state.blink + 1) % 30
    if state.state > 0x14 then key = selection(state, key) end
    if state.state == 0x16 then
        two_choice(state, 3)
        if key == "l" or key == "r" then state.row = 1 - state.row end
        if key == "c" then
            sounds.direct(state, "join")
            if state.row == 0 then
                state.state = 0x17
                state.counter = 0
            else
                state.row = 0
                state.state = 0x18
            end
            key = ""
        elseif key == "b" then
            sounds.direct(state, "cancel")
            state.state = 0x15
            state.stage, state.slot = 1, 7
            for index = 0, 7 do
                state.order[index] = index
                state.teams[index] = math.floor(index / 2) + 1
            end
            key = ""
        end
    end
    if state.state == 0x17 then
        for _ = 1, 50 do
            if state.team then
                -- Pairs move together, with their team numbers.
                local first, second = random(4) * 2, random(4) * 2
                for member = 0, 1 do
                    local a, b = first + member, second + member
                    state.order[a], state.order[b] = state.order[b], state.order[a]
                    state.teams[a], state.teams[b] = state.teams[b], state.teams[a]
                end
            else
                local first, second = random(8), random(8)
                state.order[first], state.order[second] = state.order[second], state.order[first]
            end
        end
        state.counter = state.counter + 1
        if state.counter % 5 == 0 then sounds.direct(state, "ok") end
        if state.counter > 10 then
            state.state = 0x16
            state.row = 0
        end
    end
    if state.state == 0x18 then
        random_fighters(state)
        state.state = 0x19
        state.row = 2
    end
    if state.state == 0x19 then key = options_panel(state, key) end
    if state.state > 0x19 then
        local step = state.team and 2 or 1
        for slot = 0, 7, step do
            local wins = math.min(state.wins[slot], 7)
            if wins == 7 and state.state < 0x1d then
                state.state = 0x1d
                state.champion = slot
                state.counter = 0
            end
            local lost = state.team and {0x19, 0x2f, 0x67} or {0x10, 0x28, 0x60}
            local color = (wins < 7 and wins % 2 == 1) and lost or {0xff, 0xff, 0xff}
            bars(state, slot, wins, color, state.team and 2 or 0)
        end
    end
    if state.state == 0x1a then next_pair(state, key) end
    if state.state == 0x1b then key = claim(state, key, held, context) end
    if state.state == 0x1d then
        if state.counter < 50 then state.counter = state.counter + 1 end
        if state.counter > 20 then
            if state.counter == 21 then
                music.stop()
                sounds.direct(state, "pass")
            end
            sprite(state, clip4, frames[10], 10, 10, false)
            if state.team then
                -- The winning team: its label and both heads (the second read as order + 1).
                sprite(state, clip4, {288, 416, 60, 24}, 109, 22, false)
                sprite(state, clip4, frames[state.teams[state.champion] + 10], 169, 24, false)
                local entrant = state.order[state.champion]
                image(state, entrant_fighter(state, entrant).portrait, 30, 49)
                local partner = state.fighters[state.entrants[entrant + 1] and state.entrants[entrant + 1].fighter or 0]
                if partner then image(state, partner.portrait, 150, 49) end
            else
                local human = human_of(state, state.champion)
                if human == 0 then sprite(state, clip4, frames[20], 93, 22, false)
                else sprite(state, clip4, frames[human + 10], 169, 24, false) end
                image(state, entrant_fighter(state, state.order[state.champion]).portrait, 90, 49)
            end
            sprite(state, clip4, frames[19], 23, 175, false)
            if key == "c" and state.counter == 50 then state.leave = "title" end
        end
    end
    for _, sound in ipairs(sounds.flush(state)) do context.sound(sound.resource, sound.volume, sound.pan) end
    if state.leave then context.action(state.leave) end
end

function screen.draw(state, context)
    context.viewport(794, 550, 0, 0, 0)
    for _, command in ipairs(state.display) do
        local kind = command[1]
        if kind == "image" then context.image(command[2], command[3], command[4], false)
        elseif kind == "sprite" then context.sprite(command[2], command[3], command[4], command[5], command[6])
        elseif kind == "text" then font.gdi(context, command[2], command[3], command[4], command[5], command[6])
        elseif kind == "fill" then
            local color = command[6]
            context.fill(command[2], command[3], command[4], command[5], color[1], color[2], color[3])
        end
    end
end

function screen.describe(state)
    local wins = {}
    for index = 0, 7 do wins[#wins + 1] = tostring(state.wins[index] or 0) end
    local taken = {}
    for player = 0, 7 do taken[#taken + 1] = tostring(state.taken[player] or -1) end
    local humans = {}
    for position = 0, 7 do humans[#humans + 1] = tostring(human_of(state, position)) end
    return string.format("championship_state=%d slot=%d round=%d wins=%s counter=%d taken=%s humans=%s", state.state,
        state.slot, state.round, table.concat(wins, ","), state.counter or 0, table.concat(taken, ","),
        table.concat(humans, ","))
end
return screen
