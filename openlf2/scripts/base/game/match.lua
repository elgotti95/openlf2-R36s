-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local constants = require("base/game/constants")
local record_kinds = constants.record_kinds
local object_data = require("base/game/object_data")
local background = require("base/game/background")
local item = require("base/game/item")
local control = require("base/game/control")
local physics = require("base/game/physics")
local animation = require("base/game/animation")
local camera = require("base/game/camera")
local combat = require("base/game/combat")
local ai = require("base/game/ai")
local objects = require("base/game/objects")
local grab = require("base/game/grab")
local weapons = require("base/game/weapons")
local frame_rules = require("base/game/frame_rules")
local sounds = require("base/game/sounds")
local stage = require("base/game/stage")
local speed = require("base/game/speed")
local music = require("base/game/music")
local note_function_keys, function_keys
local battle = require("base/game/battle")
local catalog = require("base/game/catalog")
local recording = require("base/game/recording")
local unlock = require("base/game/unlock")
local match = {}

local function cdiv(a, b)
    local q = a / b
    if q >= 0 then return math.floor(q) end
    return math.ceil(q)
end
local function trunc(value)
    if value >= 0 then return math.floor(value) end
    return math.ceil(value)
end
local after_advance, create_demo, create_replay, start_recording, replay_viewer, save_recording

local function stage_description(catalog_backgrounds, row)
    if row == 99 then return background.lee_on_road end
    return background.load(catalog_backgrounds[row + 1].path)
end

-- options: mode, difficulty, background row (100 = random), fighters (catalog list),
-- backgrounds (catalog list), slots[0..7] = {kind = "human"|"computer"|nil, fighter, team}.
function match.create(options)
    local state = {mode = options.mode, difficulty = options.difficulty, running = true,
        items = {}, counter_12 = 0, counter_3 = 0, shake = 0,
        camera = 0, camera_step = 0, frame_number = 0, input_phase = 0,
        random_game = options.demo ~= nil, ai_skill = 0,
        round_counter = 0, winner = -1, elapsed = 0, finished = false,
        paused = false, pause_request = false, pause_next = false, cheat_lock = 0,
        heal_all = false, weapon_command = 0, function_counts = {[6] = 0, [7] = 0, [8] = 0, [9] = 0}}
    local row = options.background
    local count = #options.backgrounds
    if options.mode == constants.modes.stage then
        -- Stage mode: levels 0, 10 ... 50 use background rows 1 to 6; encounters are pending.
        row = math.floor(options.stage_level / 10) + 1
    elseif row == 100 then
        -- Random background: the last two rows are excluded and the third-last means row 99.
        row = engine.random(count - 2)
        if row == count - 3 then row = 99 end
    end
    state.background_row = row
    state.stage_bound, state.camera_limit = 0, 0
    if options.mode == constants.modes.stage then state.stage_run = stage.create(options.stage_level) end
    if options.mode == constants.modes.battle then state.battle_run = battle.create(options.battle) end
    state.stage = stage_description(options.backgrounds, row)
    state.view = background.create_state(state.stage)
    local width = state.stage.width or 794
    local near, far = state.stage.zboundary[1] or 0, state.stage.zboundary[2] or 0
    if options.demo then create_demo(state, options, width, near, far) end
    if options.replay then create_replay(state, options.replay) end
    for slot = 0, 7 do
        local entry = options.slots[slot]
        if entry and entry.kind then
            local fighter = options.fighters[entry.fighter]
            local record = item.record({id = fighter.id, kind = record_kinds.character}, object_data.load(fighter.path))
            local index = entry.kind == "human" and slot or slot + 10
            local value = item.create(record)
            value.team = entry.team
            value.blink = 75
            value.drop_counter = record.data.weapon.hp or 0
            if options.mode == constants.modes.battle then
                value.x_int = entry.team == constants.teams.player_one and 100 or width - 100
                value.z_int = engine.random(far - near) + near
                value.armor = options.battle.defense[entry.team - 1] or 100
                value.battle_side = entry.team
            else
                value.x_int = engine.random(math.floor(width / 2)) + math.floor(width / 4)
                value.z_int = engine.random(far - near) + near
            end
            value.y_int = 0
            value.x, value.z, value.y = value.x_int, value.z_int, 0.0
            local high_mp_mode = options.mode == constants.modes.stage
                or options.mode == constants.modes.championship
                or options.mode == constants.modes.team_championship
            value.mp = high_mp_mode and 500 or 200
            if entry.hp then
                value.hp, value.dark_hp, value.max_hp = entry.hp, entry.hp, entry.hp
                value.transformed_to = entry.transform or -1
                value.entrant = entry.entrant
            end
            value.owner = index
            value.human = entry.kind == "human"
            value.slot = slot
            state.items[index] = value
        end
    end
    for index = 0, 399 do
        local value = state.items[index]
        if value and value.team == constants.teams.independent then value.team = index + 10 end
    end
    if options.mode == constants.modes.stage and not options.replay then
        for index = 0, 399 do
            local value = state.items[index]
            if value and value.record.kind == record_kinds.character then
                value.x_int = engine.random(30) + 50
                value.x = value.x_int
            end
        end
    end
    -- Network peers may have different local recording preferences. Both must perform the
    -- original game-start sequence reset, even when only one records to disk.
    if options.network then engine.reset_random_sequence() end
    if options.replay then
        local replay = options.replay
        engine.set_random_state(replay.random_table, replay.random_index)
        engine.reset_random_sequence()
        stage.set_random_list(replay.random_fighters, replay.random_list_index)
        state.input_phase = replay.input_phase
    elseif options.record then
        start_recording(state, options)
    end
    return state
end

create_demo = function(state, options, width, near, far)
    local picks = options.demo.pick()
    local candidates = {}
    for slot = 0, 7 do
        local fighter = options.fighters[picks[slot]]
        local record = item.record({id = fighter.id, kind = record_kinds.character}, object_data.load(fighter.path))
        local value = item.create(record)
        value.drop_counter = record.data.weapon.hp or 0
        value.blink = 75
        value.x_int = engine.random(math.floor(width / 2)) + math.floor(width / 4)
        value.z_int = engine.random(far - near) + near
        value.y_int = 0
        value.x, value.z, value.y = value.x_int, value.z_int, 0.0
        value.mp = 200
        value.owner = slot + 10
        value.human = false
        value.slot = slot
        value.team = constants.teams.independent
        candidates[slot] = value
    end
    local present = {}
    local roll = engine.random(30)
    if roll < 7 then
        present[0] = true
        for slot = 1, 7 do
            candidates[slot].team = engine.random(5)
            present[slot] = true
        end
    elseif roll < 18 then
        for slot = 0, 7 do
            candidates[slot].team = math.floor(slot / 4) + 1
            present[slot] = true
        end
        if engine.random(3) == 0 then present[7], present[3] = nil, nil end
        if engine.random(6) == 0 then
            candidates[7].team, candidates[3].team = constants.teams.player_three, constants.teams.player_three
        end
    else
        local size
        if roll < 25 then
            for slot = 0, 7 do candidates[slot].team = math.floor(slot / 2) + 1 end
            size = engine.random(3) * 2 + 4
        else
            size = engine.random(3) + 2
        end
        for slot = 0, size - 1 do present[slot] = true end
    end
    for slot = 0, 7 do
        if present[slot] then state.items[slot + 10] = candidates[slot] end
    end
end

create_replay = function(state, replay)
    for slot = 0, 17 do
        local fields = replay.slots[slot]
        local entry = fields and catalog.objects().by_id[fields.record_id]
        if entry then
            local record = item.record(entry, object_data.load(entry.path))
            local value = item.create(record)
            value.x, value.y, value.z = 350.0, 0.0, 300.0
            value.drop_counter = record.data.weapon.hp or 0
            value.team, value.blink = fields.team, fields.blink
            value.x_int, value.y_int, value.z_int = fields.x_int, fields.y_int, fields.z_int
            value.x, value.z = fields.x_int, fields.z_int
            value.mp, value.owner = fields.mp, fields.owner
            value.max_hp = fields.max_hp
            value.dark_hp, value.hp = fields.max_hp, fields.max_hp
            value.transformed_to, value.battle_side, value.armor = fields.transformed_to, fields.battle_side, fields.armor
            value.human = slot < 10
            value.slot = slot < 10 and slot or slot - 10
            state.items[slot] = value
        end
    end
    state.replay = replay
    state.replay_status = true
    state.replay_pan = {active = false, x = 0, speed = 0}
end
start_recording = function(state, options)
    local record = options.record
    local suffix = ""
    if options.mode == constants.modes.stage then
        local group = math.floor(options.stage_level / 10)
        suffix = group < constants.stage_groups.survival and ("_Stage_" .. (group + 1)) or "_Survival"
    elseif options.mode == constants.modes.versus then
        suffix = "_VS"
    elseif options.mode == constants.modes.battle then
        suffix = "_Battle"
    elseif options.mode == constants.modes.championship or options.mode == constants.modes.team_championship then
        local rounds = {[0] = "Prelminar", [2] = "SemiFinal", [4] = "Final"}
        local format = options.mode == constants.modes.championship and "_1on1_" or "_2on2_"
        suffix = format .. (rounds[options.tournament_round or 0] or "")
    end
    local fighters, index = stage.random_list()
    recording.begin(state, {difficulty = options.difficulty, stage_level = options.stage_level, mode = options.mode,
        names = record.names, background = state.background_row, music = record.music, version = record.version,
        battle = options.mode == constants.modes.battle and options.battle or nil,
        random_fighters = fighters, random_index = index,
        input_phase = state.input_phase, author = record.author, info = record.info, email = record.email,
        name = record.time .. suffix .. ".lfr"})
end

replay_viewer = function(state, held)
    local keys = held.keys or {}
    if held.functions:find("6", 1, true) and not state.replay_f6 then state.replay_status = not state.replay_status end
    state.replay_f6 = held.functions:find("6", 1, true) ~= nil
    local pan = state.replay_pan
    if keys[0x25] or keys[0x27] then
        if not pan.active then
            pan.x = state.camera
            pan.active = true
            pan.speed = state.camera_step
        end
        if keys[0x25] then pan.speed = pan.speed - 5 end
        if keys[0x27] then pan.speed = pan.speed + 5 end
    end
    if keys[0x28] then
        pan.active = false
    elseif pan.active then
        pan.x = pan.x + pan.speed
        pan.speed = cdiv(pan.speed * 6, 7)
        return
    end
    pan.speed = 0
end
-- The round-end results and the file (counter 101).
save_recording = function(state)
    local results = {phase = state.stage_run and state.stage_run.phase or 0}
    local players_alive = false
    for index = 0, 399 do
        local value = state.items[index]
        if value and value.record.kind == record_kinds.character and value.hp > 0
           and value.team > constants.teams.independent
           and value.team < constants.teams.active_end_exclusive
           and value.team ~= constants.teams.enemies then
            players_alive = true
        end
    end
    results.result_of = function(value)
        if state.mode == constants.modes.stage then
            if not players_alive then return -1 end
            return value.hp > 0 and 2 or 1
        elseif state.winner >= 0 then
            if state.winner == value.team then return value.hp > 0 and 2 or 1 end
            return -1
        end
        return 0
    end
    if state.mode == constants.modes.stage then
        local survivors = 0
        for index = 0, 399 do
            local value = state.items[index]
            if value and value.record.kind == record_kinds.character and value.team == constants.teams.enemies and value.hp > 0 then survivors = survivors + 1 end
        end
        results.stamp = survivors < 1 and 1 or 0
    elseif state.mode == constants.modes.battle and state.battle_run then
        local run = state.battle_run
        results.battle_deaths = {run.deaths[1], run.deaths[2]}
        results.battle_damage = {run.damage[1], run.damage[2]}
        local d0, d1 = run.defense[0], run.defense[1]
        results.stamp = (run.strategy[0] + 1) * 10000000 + (run.size[0] + 1) * 1000000
            + math.floor(d0 / 100) * 100000 + math.floor(d0 % 100 / 10) * 10000
            + (run.strategy[1] + 1) * 1000 + (run.size[1] + 1) * 100 + math.floor(d1 / 100) * 10 + math.floor(d1 % 100 / 10)
    end
    local saved, problem = recording.finish(state, results)
    state.recording.saved = true
    if saved then
        recording.status = {kind = constants.recording_statuses.saved, name = state.recording.name, count = 0}
    else
        recording.status = {kind = constants.recording_statuses.error, text = "Recording not saved: " .. tostring(problem), count = 0}
    end
end

local function each_item(state, callback)
    for index = 0, 399 do
        local value = state.items[index]
        if value then callback(index, value) end
    end
end

local function read_input(state, held)
    for index = 0, 7 do
        local value = state.items[index]
        if value and value.human then
            for _, key in ipairs(item.keys) do value.previous_keys[key] = value.keys[key] end
            if state.input_phase == 0 then
                local keys = held[index] or ""
                value.keys.up = keys:find("u", 1, true) ~= nil
                value.keys.down = keys:find("d", 1, true) ~= nil
                value.keys.left = keys:find("l", 1, true) ~= nil
                value.keys.right = keys:find("r", 1, true) ~= nil
                value.keys.attack = keys:find("c", 1, true) ~= nil
                value.keys.jump = keys:find("b", 1, true) ~= nil
                value.keys.defend = keys:find("f", 1, true) ~= nil
            end
        end
    end
    for index = 10, 399 do
        local value = state.items[index]
        if value then
            if value.record.kind == record_kinds.character then ai.control(state, index, state.mode)
            elseif value.record.frame(value.frame).hits.Fa > 0 then objects.update(state, index) end
        end
    end
end

local function versus_counter(state)
    local alive, teams = {}, 0
    for index = 0, 399 do
        local value = state.items[index]
        if value and value.hp > 0 and value.record.kind == record_kinds.character
           and value.team > constants.teams.independent
           and value.team < constants.teams.active_end_exclusive
           and value.team ~= constants.teams.enemies then
            alive[value.team] = (alive[value.team] or 0) + 1
        end
    end
    for team = 0, 39 do
        if (alive[team] or 0) > 0 then
            state.winner = team
            teams = teams + 1
        end
    end
    if teams < 2 and not state.finished and (state.mode ~= constants.modes.battle or (state.battle_run and state.battle_run.over)) then
        if teams == 0 then state.winner = -1 end
        state.round_counter = state.round_counter + 1
        -- At 80 the end jingle plays and normal speed returns; the music stop for other modes
        -- isn't ported.
        if state.round_counter == 80 then
            sounds.direct(state, "finish")
            -- Normal speed returns except in the demo.
            if state.mode ~= constants.modes.demo then speed.fast = false end
        end
    elseif state.mode ~= constants.modes.championship and state.mode ~= constants.modes.team_championship then
        state.winner = -1
    end
end

local function round_end(state)
    if state.mode == constants.modes.stage then
        stage.round_counter(state, state.stage_run)
    else
        versus_counter(state)
    end
    if state.round_counter == 145 then
        if not state.random_game then state.round_counter = 144 end
    elseif state.round_counter >= 350 then
        frame_rules.round_end(state)
        state.finished = true
        return true
    end
    if state.round_counter >= 144 then
        if state.mode == constants.modes.stage then
            stage.round_keys(state, state.stage_run)
        elseif state.random_game then
            for slot = 0, 7 do
                local keys = state.held and state.held[slot] or ""
                if keys:find("c", 1, true) or keys:find("b", 1, true) then
                    state.round_counter = 350
                    state.random_game = false
                end
            end
        else
            for index = 0, 7 do
                local value = state.items[index]
                if value and (value.keys.attack or value.keys.jump) then state.round_counter = 350 end
            end
        end
    end
    if state.round_counter < 100 then state.elapsed = state.elapsed + 1 end
    return false
end

local function regenerate(state, value)
    if value.record.kind ~= record_kinds.character then return end
    if value.hp > 0 and value.hp < value.dark_hp and state.counter_12 == 0 then value.hp = value.hp + 1 end
    -- Whirlwind victims lose 9 hp (900 / armor) every twelfth frame.
    if value.fall_damage < 0 and state.counter_12 == 0 then
        local loss = 9
        if value.armor > 0 then loss = math.floor(900 / value.armor) end
        value.hp = value.hp - loss
        value.dark_hp = value.dark_hp + cdiv(loss, -3)
        if value.hp < 0 then value.hp = 0 end
        if value.dark_hp < 0 then value.dark_hp = 0 end
        value.hp_spent = value.hp_spent + 9
    end
    if (value.follow == -1 or value.mp < 150) and value.mp < 500 and state.counter_3 == 0 and value.blink > -1 then
        local hp = math.min(value.hp, 500)
        if value.record.id == constants.fighter_ids.firzen or value.record.id == constants.fighter_ids.julian then hp = math.floor(hp / 2) end
        value.mp = value.mp + math.floor((500 - hp) / 100) + 1
    end
end

local function heal(value)
    if math.floor(value.regen_timer / 1000) == 1 and value.hp > 0 then
        value.regen_timer = value.regen_timer - 1
        if value.regen_timer % 8 == 0 then
            if value.hp < value.dark_hp then
                if value.hp < value.dark_hp - 8 then value.hp = value.hp + 8 else value.hp = value.dark_hp end
            else
                value.regen_timer = 0
            end
        end
        if value.regen_timer % 1000 == 0 then value.regen_timer = 0 end
    end
    if value.heal_timer > 0 and value.hp > 0 then
        value.heal_timer = value.heal_timer - 1
        if value.heal_timer % 8 == 0 and value.hp < value.dark_hp then
            value.hp = value.hp + 8
            if value.hp > value.dark_hp then
                value.hp = value.dark_hp
                value.heal_timer = 0
            end
        end
    end
    if value.record.frame(value.frame).state == constants.frame_states.heal_self then value.regen_timer = 1100 end
end

local function fill_weapons(state)
    local wanted = {}
    for _, entry in ipairs(catalog.objects().list) do
        if entry.id > constants.record_id_ranges.background_weapon_lower_exclusive
           and entry.id < constants.record_id_ranges.background_weapon_end_exclusive
           and (entry.id ~= constants.item_ids.milk or engine.random(2) ~= 0) then
            wanted[#wanted + 1] = entry.id
        end
    end
    local width = state.stage.width or 794
    local near, far = state.stage.zboundary[1] or 0, state.stage.zboundary[2] or 0
    for _, id in ipairs(wanted) do
        local roll_a = engine.random(30)
        local roll_b = engine.random(30)
        local x = roll_b + 30 + roll_a * cdiv(width - 60, 30)
        local roll_c = engine.random(30)
        local roll_d = engine.random(30)
        local z = roll_d + near + 30 + roll_c * cdiv(far - near - 60, 30)
        local slot = objects.free_slot(state)
        if slot == -1 then break end
        local value = objects.place(state, slot, id)
        if value then
            value.x, value.y, value.z = x, -500.0, z
            for other = 0, 399 do
                local item_value = state.items[other]
                if item_value then item_value.pair_rest[slot] = 0 end
            end
            value.vx, value.vy, value.vz = 0.0, 0.0, 0.0
            if id == constants.item_ids.milk then value.hp = 200 end
            value.x_int, value.y_int, value.z_int = trunc(value.x), trunc(value.y), trunc(value.z)
        end
    end
end

local function function_key_effects(state, index, value)
    local kind = value.record.kind
    if state.weapon_command == 2 then
        if kind == record_kinds.light_item or kind == record_kinds.heavy_item
           or kind == record_kinds.baseball or kind == record_kinds.drink then
            value.drop_counter = -1
        elseif state.mode == constants.modes.stage and value.team == constants.teams.enemies and kind == record_kinds.character and value.record.id ~= constants.record_ids.criminal then
            value.hp, value.mp = 0, 0
        end
    end
    if state.heal_all and (state.mode ~= constants.modes.stage or (index < 8 and value.team == constants.teams.player_one)) then
        if value.max_hp < 500 then value.max_hp = 500 end
        value.dark_hp = value.max_hp
        value.hp = value.dark_hp
        value.mp = 500
        state.resume_music = true
    end
end

after_advance = function(state, index, value)
    if math.floor(value.frame / 100) == 11 or math.floor(value.frame / 100) == 12 then
        for other = 0, 399 do
            local follower = state.items[other]
            if follower and follower.follow == index then follower.blink = 1100 - value.frame end
        end
        value.blink = 1100 - value.frame
        value.frame = 0
        return
    end
    if value.frame < 0 or value.frame >= 400 then
        value.frame = 0
        objects.remove(state, index)
        return
    end
    local function knock_down()
        value.frame = 186
        value.vy = -3.0
        value.impulse_y = -3.0
        value.y = -1.0
        value.y_int = -1
    end
    if value.record.kind == record_kinds.character then
        if value.hp <= 0 and (value.frame < 12 or value.frame == 110 or value.frame == 111) then knock_down() end
        if value.y_int == 0 and value.y == 0.0 and value.vy == 0.0 and value.impulse_y == 0.0
           and ((value.frame >= 180 and value.frame <= 189 and value.frame ~= 184)
                or (value.frame >= 212 and value.frame <= 214)) then
            knock_down()
        end
    end
    -- Without a spawn, destroyed weapons burst; otherwise players' key codes give team orders.
    if not objects.spawn_from_frame(state, index, value) and not weapons.break_apart(state, index, value) then
        frame_rules.team_orders(state, index, value)
    end
    objects.state_effects(state, index, value)
    value.state_frame = value.frame
end

local function_letters = {"1", "2", "3", "4", "5", "6", "7", "8", "9"}
note_function_keys = function(state, held)
    if held.function_sources then
        state.network_function_held = state.network_function_held or {{}, {}}
        state.network_function_pending = state.network_function_pending or {{}, {}}
        state.function_pending = {}
        for key = 1, 9 do
            for side = 1, 2 do
                local down = held.function_sources[side]:find(tostring(key), 1, true) ~= nil
                local previous, pending = state.network_function_held[side], state.network_function_pending[side]
                if down and not previous[key] then pending[key] = true end
                if not down then pending[key] = nil end
                previous[key] = down
                if pending[key] then state.function_pending[key] = true end
            end
        end
        return
    end
    state.function_held = state.function_held or {}
    state.function_pending = state.function_pending or {}
    for key = 1, 9 do
        local down = held.functions:find(function_letters[key], 1, true) ~= nil
        if down and not state.function_held[key] then state.function_pending[key] = true end
        if not down then state.function_pending[key] = nil end
        state.function_held[key] = down
    end
end

function_keys = function(state)
    local pending = state.function_pending or {}
    state.function_pending = {}
    state.network_function_pending = nil
    local function take(key) return pending[key] end
    local function pause_keys()
        if take(1) then
            state.pause_next = not state.paused
            state.pause_request = state.pause_next
        end
        if take(2) then state.pause_next, state.pause_request = true, false end
    end
    if state.held.network then pause_keys() end
    -- Dispatch order: F4, F1, F2, F3, F5, F6-F9.
    if take(4) then
        state.paused, state.pause_request, state.pause_next = false, false, false
        state.random_game = false
        -- A replay returns to the title at once; a recording stops unsaved ("Recording
        -- canceled!" before counter 101).
        if state.replay then return "leave" end
        if state.recording and not state.recording.saved then
            state.recording = nil
            if state.round_counter < 101 then recording.status = {kind = constants.recording_statuses.cancelled, count = 0} end
        end
        speed.fast = false
        if state.mode == constants.modes.championship or state.mode == constants.modes.team_championship then
            -- Championship: returns to the title; F1-F9 are skipped.
            state.round_counter = 0
            return "leave"
        end
        state.round_counter = 350
    end
    if not state.held.network then pause_keys() end
    -- Handlers mark the recorded flags (frame record byte 8).
    local function mark(bit) state.function_flags = (state.function_flags or 0) + bit end
    if take(3) then
        state.cheat_lock = 2
        mark(4)
    end
    if take(5) then speed.fast = not speed.fast end
    local cheats_allowed = state.cheat_lock < 2 and (state.mode == constants.modes.versus or unlock.flags.function_keys == 1)
    for key, bit in pairs({[7] = 0x20, [8] = 0x40, [9] = 0x80}) do
        if pending[key] and cheats_allowed then mark(bit) end
    end
    if take(6) and cheats_allowed then
        mark(0x10)
        state.running = not state.running
        state.function_counts[6] = state.function_counts[6] + 1
        state.cheat_lock = 1
    end
    if take(7) and cheats_allowed and state.round_counter == 0 then
        state.heal_all = not state.heal_all
        state.function_counts[7] = state.function_counts[7] + 1
        state.cheat_lock = 1
    end
    if take(8) and cheats_allowed and state.round_counter == 0 then
        state.weapon_command = 1
        state.function_counts[8] = state.function_counts[8] + 1
        state.cheat_lock = 1
    end
    if take(9) and cheats_allowed and state.round_counter == 0 then
        state.weapon_command = 2
        state.function_counts[9] = state.function_counts[9] + 1
        state.cheat_lock = 1
    end
    return nil
end

-- One frame. `held`: per-slot letters (0-7) and F-keys (1-9) in `functions`.
-- Returns "finished", "leave" (F4 in Championship), "paused" or nil.
function match.step(state, held)
    state.frame_number = state.frame_number + 1
    state.held = held
    state.input_phase = (state.input_phase + 1) % 2
    if state.input_phase == 0 then
        state.paused = state.pause_request
        state.pause_request = state.pause_next
    end
    local locked = state.paused
    local live = held
    local replay_input
    if state.replay then
        replay_viewer(state, held)
        if not state.replay_ended then
            if not locked then replay_input = recording.replay_input(state.replay) end
            held = {functions = held.functions:gsub("[^1245]", ""), keys = held.keys}
            for slot = 0, 7 do held[slot] = replay_input and replay_input[slot] or "" end
        end
    end
    note_function_keys(state, held)
    if replay_input and replay_input.unlock ~= 0 then
        -- The recorded unlock bits (record byte 9) toggle the flags like the typed words.
        state.direct_sounds = state.direct_sounds or {}
        for _, sound in ipairs(unlock.apply_recorded(replay_input.unlock)) do
            state.direct_sounds[#state.direct_sounds + 1] = sound
        end
    end
    if replay_input then
        for key, bit in pairs(recording.function_bits) do
            if math.floor(replay_input.flags / bit) % 2 == 1 then state.function_pending[key] = true end
        end
    end
    if not locked then read_input(state, held) end
    state.function_flags = 0
    if state.input_phase == 0 then
        local result = function_keys(state)
        if result then return result end
    end
    if not locked then
        if replay_input then
            -- Every 150 frames the hp of slots 0-19 must match the recording.
            local expected = recording.replay_checksum(state.replay)
            if expected and expected ~= recording.hp_sum(state) then return "replay_error" end
            recording.replay_advance(state.replay)
        elseif state.recording and not state.recording.saved then
            local bytes = {0, 0, 0, 0, 0, 0, 0, 0, state.function_flags, state.unlock_bits or 0}
            if state.input_phase == 0 then
                for slot = 0, live.network and 7 or 3 do bytes[slot + 1] = recording.pack_keys(live[slot] or "") end
            end
            recording.capture(state, bytes)
        end
    end
    if locked then
        -- The wait frame: everything is redrawn with the PAUSE sprite, nothing advances.
        speed.fast = false
        if state.capture then
            state.last_snapshot = state.capture(state)
            state.last_snapshot.paused = true
        end
        return "paused"
    end
    state.shake = 1 - state.shake
    state.counter_12 = (state.counter_12 + 1) % 12
    state.counter_3 = (state.counter_3 + 1) % 3
    if round_end(state) then return "finished" end
    if state.round_counter == 101 and not state.round_101 then
        state.round_101 = true
        if state.recording and not state.recording.saved then save_recording(state) end
        if state.replay then state.replay_ended = true end
    end
    each_item(state, function(index, value)
        control.step(state, value)
        frame_rules.after_control(state, index, value)
    end)
    each_item(state, function(index, value)
        physics.step(state, value)
        if value.record.frame(value.frame).state == constants.frame_states.removed then objects.remove(state, index) end
        frame_rules.after_physics(state, index, value)
    end)
    weapons.carry(state)
    combat.detect(state)
    each_item(state, function(index, value)
        if value.record.kind == record_kinds.character then combat.apply(state, index) end
    end)
    weapons.drop_background(state)
    each_item(state, function(index, value)
        if value.record.kind > record_kinds.character then combat.apply(state, index) end
    end)
    grab.update_holds(state)
    grab.place_victims(state)
    weapons.check_holders(state)
    weapons.carry(state)
    camera.step(state)
    -- The original draws here, before the impulses and the frame advance.
    if state.capture then state.last_snapshot = state.capture(state) end
    if state.stage_run then
        local display = stage.update(state, state.stage_run)
        if state.last_snapshot then state.last_snapshot.stage = display end
    end
    if state.battle_run then
        local display = battle.update(state, state.battle_run)
        if state.last_snapshot then state.last_snapshot.stage = display end
    end
    combat.apply_impulses(state)
    each_item(state, function(index, value)
        frame_rules.before_advance(state, index, value)
        regenerate(state, value)
        animation.advance(state, value, index)
        after_advance(state, index, value)
    end)
    if state.weapon_command == 1 then fill_weapons(state) end
    each_item(state, function(index, value)
        function_key_effects(state, index, value)
        heal(value)
    end)
    state.heal_all, state.weapon_command = false, 0
    if state.resume_music then
        music.resume()
        state.resume_music = false
    end
    combat.reset_lists(state)
end
return match
