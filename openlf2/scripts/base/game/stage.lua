-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local constants = require("base/game/constants")
local record_kinds = constants.record_kinds
local objects = require("base/game/objects")
local sounds = require("base/game/sounds")
local speed = require("base/game/speed")
local music = require("base/game/music")
local stage = {}

local function cdiv(a, b)
    local q = a / b
    if q >= 0 then return math.floor(q) end
    return math.ceil(q)
end
local function trunc(value)
    if value >= 0 then return math.floor(value) end
    return math.ceil(value)
end
local function random(range) return engine.random(range) end
local function cmod(a, b) return a - cdiv(a, b) * b end
local menu_sheet, menu_sheet2 = "pe/menu_clip3", "pe/menu_clip2"
local frames = {
    [24] = {328, 401, 132, 41}, [25] = {488, 400, 176, 41}, [36] = {722, 124, 29, 40},
    [37] = {12, 552, 386, 40},
    [27] = {662, 9, 29, 40}, [28] = {692, 9, 29, 40}, [29] = {722, 9, 29, 40}, [30] = {752, 9, 29, 40},
    [31] = {662, 66, 29, 40}, [32] = {692, 66, 29, 40}, [33] = {722, 66, 29, 40}, [34] = {752, 66, 29, 40},
    [35] = {662, 124, 29, 40},
}
local survival_frame = {0, 403, 469, 41}

local random_fighters = {constants.fighter_ids.deep, constants.fighter_ids.john,
    constants.fighter_ids.henry, constants.fighter_ids.rudolf, constants.fighter_ids.louis,
    constants.fighter_ids.davis, constants.fighter_ids.dennis, constants.fighter_ids.woody,
    constants.fighter_ids.freeze, constants.fighter_ids.firen}
local random_index = -1

function stage.random_list()
    return {unpack(random_fighters)}, random_index
end
function stage.set_random_list(fighters, index)
    for position = 1, 10 do random_fighters[position] = fighters[position] end
    random_index = index
end

local list
local function stage_list()
    if not list then list = engine.read_stage_data("data/stage.dat").stages end
    return list
end

local empty_phase = {bound = -1, music = "", when_clear_goto_phase = -1, entry_count = 0, entries = {}}
local function stage_data(run) return stage_list()[run.id] or {phase_count = -1, phases = {}} end
local function phase_data(run, index) return stage_data(run).phases[index] or empty_phase end

function stage.create(level)
    return {id = level, phase = -1, phase_done = 0, boss_alive = 0, last_phase = 0, go = 70,
        shutter = 0, result = 0, survival = -1, survival_blink = 0, runtime = {}, marked = {},
        next_group = false, ending = false}
end

local function spawn(state, run, entry, runtime, slot)
    local index = 20
    while state.items[index] or run.marked[index] do
        index = index + 1
        if index >= 400 then
            runtime.ids[slot] = -1
            return
        end
    end
    local health, id = entry.hp, entry.id
    if state.difficulty == constants.difficulties.crazy then
        if id ~= constants.record_ids.criminal then health = trunc(health * 1.5) end
    elseif state.difficulty == constants.difficulties.easy then
        if id ~= constants.record_ids.criminal then health = trunc(health * 0.75) end
    end
    if id == constants.stage_record_selectors.random_fighter then
        if random_index == 10 or random_index == -1 then
            for _ = 1, 50 do
                local a, b = random(10), random(10)
                random_fighters[a + 1], random_fighters[b + 1] = random_fighters[b + 1], random_fighters[a + 1]
            end
            random_index = 0
        end
        id = random_fighters[random_index + 1]
        random_index = random_index + 1
    elseif id == constants.stage_record_selectors.random_stage_enemy then
        id = random(2) + constants.fighter_ids.bandit
    elseif id == constants.stage_record_selectors.random_stage_enemy_with_rare then
        if random(7) == 0 then
            id = constants.fighter_ids.mark
            health = health * 4
        else
            id = random(2) + constants.fighter_ids.bandit
        end
    end
    if not objects.record(state, id) then
        runtime.ids[slot] = -1
        return
    end
    runtime.ids[slot] = index
    local value = objects.place(state, index, id)
    value.x, value.y, value.z = 350.0, 0.0, 300.0
    local near, far = state.stage.zboundary[1] or 0, state.stage.zboundary[2] or 0
    value.z_int = random(far - near) + near
    if entry.x ~= -1000 then
        value.x_int = random(300) + entry.x
    elseif random(2) == 0 then
        value.x_int = random(300) + 150 + state.stage_bound
    else
        value.x_int = -150 - random(300)
    end
    value.lives, value.join_hp, value.join_lives = entry.reserve, entry.join, entry.join_reserve
    value.x, value.z = value.x_int, value.z_int
    value.mp = 500
    value.dark_hp, value.hp, value.max_hp = health, health, health
    value.owner = index
    local kind = value.record.kind
    if kind ~= record_kinds.character and kind ~= record_kinds.prisoner then
        value.blink, value.team = 0, constants.teams.independent
        value.y_int = -300
        value.y = value.y_int
    else
        value.blink = 20
        value.facing = value.x_int > state.stage_bound - 794 and 1 or 0
        value.frame = entry.act
        value.team = constants.teams.enemies
        value.y_int = entry.y
        value.y = value.y_int
        value.vy = 0.0
    end
    if value.record.id == constants.item_ids.milk then value.hp = 200 end
    runtime.count = runtime.count + 1
end

local function next_stage(state, run)
    run.id = run.id + 1
    run.go, run.result, run.last_phase, run.phase, run.survival = 70, 0, 0, -1, -1
    run.runtime = {}
    state.camera_step, state.camera = 0, 0
    local near, far = state.stage.zboundary[1] or 0, state.stage.zboundary[2] or 0
    for index = 0, 399 do
        local value = state.items[index]
        if value and value.record.kind == record_kinds.character then
            value.x_int = random(30) + 50
            value.x = value.x_int
            value.dark_hp = value.dark_hp + (state.difficulty + 2) * 50
            if value.dark_hp > value.max_hp then value.dark_hp = value.max_hp end
            value.hp = value.dark_hp
            value.mp = 500
            if value.frame >= 9 and value.frame <= 11 then value.frame = 0 end
            if value.frame >= 16 and value.frame <= 18 then value.frame = 12 end
            value.z_int = random(far - near) + near
            value.z = value.z_int
        end
    end
    for index = 0, 399 do
        local value = state.items[index]
        if value then value.order_x, value.order_z = -1000, -1000 end
    end
    local counts = {}
    for index = 20, 399 do
        local value = state.items[index]
        if value then
            if value.record.kind > record_kinds.character and value.weapon >= 0 then
                objects.remove(state, index)
            elseif value.follow >= 0 and value.follow < 20 then
                if (counts[value.follow] or 0) < 2 then counts[value.follow] = (counts[value.follow] or 0) + 1
                else objects.remove(state, index) end
            end
        end
    end
end

-- Black shutter bars: eleven 794-wide bars 43 px apart from y 135.
local function shutter(display, height)
    for y = 135, 564, 43 do display[#display + 1] = {"fill", 0, y, 794, height} end
end

-- New phase: counters, bounds, revival in survival, and the first wave of every entry.
local function start_phase(state, run)
    local phase = run.phase
    local group = cdiv(run.id, 10)
    run.phase_done, run.boss_alive, run.last_phase = 0, 0, 0
    run.survival = run.survival + 1
    if group == constants.stage_groups.survival then run.survival_blink = 1 end
    local goto_phase = phase >= 0 and phase_data(run, phase).when_clear_goto_phase or -1
    if phase < 0 or goto_phase == -1 then run.phase = phase + 1 else run.phase = goto_phase end
    local data = phase_data(run, run.phase)
    if data.music ~= "" then music.play(data.music) end
    state.camera_limit = data.bound - 794
    state.stage_bound = data.bound
    if group == constants.stage_groups.survival then
        for index = 0, 19 do
            local value = state.items[index]
            if value and value.hp <= 0 then
                if value.dark_hp < 5 then value.dark_hp = 5 end
                value.hp, value.mp = 5, 500
                value.x_int, value.x = 100, 100.0
            end
        end
    end
    local characters = 0
    for index = 0, 19 do
        local value = state.items[index]
        if value and value.record.kind == record_kinds.character then
            characters = characters + 1
            if value.record.id == constants.fighter_ids.firzen then characters = characters + 1 end
            if value.record.id == constants.fighter_ids.julian then characters = characters + 2 end
        end
    end
    if state.difficulty == constants.difficulties.crazy then characters = trunc(characters * 1.5 + 1.0) end
    run.runtime[run.phase] = {}
    for position, entry in ipairs(data.entries) do
        local runtime = {count = 0, ids = {}}
        run.runtime[run.phase][position] = runtime
        if entry.id >= 0 then
            if entry.ratio <= 0.0 then
                runtime.total, runtime.parallel = entry.times, 1
            else
                local scaled = characters * entry.ratio
                runtime.total = trunc(entry.times * scaled)
                runtime.parallel = math.min(trunc(scaled), 40)
            end
            for slot = 0, runtime.parallel - 1 do spawn(state, run, entry, runtime, slot) end
        end
    end
end

function stage.update(state, run)
    local display = {}
    run.marked = {}
    local group = cdiv(run.id, 10)
    if run.result > 2 then
        if run.result == 3 then
            state.round_counter = 0
            if run.shutter >= 0 and run.shutter < 21 then
                if run.shutter < 10 then shutter(display, cdiv(run.shutter * 43, 10))
                else display[#display + 1] = {"fill", 0, 109, 794, 440} end
                run.shutter = run.shutter + 1
                if run.shutter == 21 then
                    if group == constants.stage_groups.final_story then
                        -- After the last group the original shows the ending (state 300).
                        run.ending = true
                    else
                        run.id = (group * 5 + 5) * 2
                        run.next_group = true
                    end
                    state.round_counter = 350
                    return display
                end
            end
        end
        return display
    end
    if run.phase == -1 and run.id % 10 == 0 then random_index = -1 end
    local data = stage_data(run)
    local phase = run.phase
    if (phase < data.phase_count - 1 or (phase > -1 and phase_data(run, phase).when_clear_goto_phase ~= -1))
       and (phase == -1 or run.phase_done == 1) then
        start_phase(state, run)
    end
    run.phase_done, run.boss_alive = 1, 0
    if run.phase >= 0 then
        local entries = phase_data(run, run.phase).entries
        local runtimes = run.runtime[run.phase] or {}
        for position, entry in ipairs(entries) do
            local runtime = runtimes[position]
            if runtime and entry.id >= 0 and entry.kind > 1 then
                for slot = 0, (runtime.parallel or 0) - 1 do
                    local id = runtime.ids[slot] or -1
                    if id >= 0 then
                        run.marked[id] = true
                        local value = state.items[id]
                        if value and value.team == constants.teams.enemies and value.record.kind == record_kinds.character then run.boss_alive = 1 end
                    end
                end
            end
        end
        for pass = 0, 1 do
            for position, entry in ipairs(entries) do
                local runtime = runtimes[position]
                if runtime and entry.id >= 0 then
                    for slot = 0, (runtime.parallel or 0) - 1 do
                        local id = runtime.ids[slot] or -1
                        if id >= 0 and not state.items[id] then
                            if pass == 0 then
                                -- Soldiers stop coming once no boss is left.
                                if entry.kind == constants.stage_entry_kinds.soldier then
                                    if run.boss_alive == 0 or runtime.total <= runtime.count then
                                        runtime.ids[slot] = -1
                                        runtime.count = runtime.total
                                    end
                                elseif runtime.total <= runtime.count then
                                    runtime.ids[slot] = -1
                                    runtime.count = runtime.total
                                end
                            elseif runtime.count < runtime.total then
                                spawn(state, run, entry, runtime, slot)
                                run.phase_done = 0
                            end
                        end
                    end
                end
            end
        end
    end
    local enemies_left = false
    for index = 20, 399 do
        local value = state.items[index]
        if value and value.record.kind == record_kinds.character and value.team == constants.teams.enemies then enemies_left = true break end
    end
    local target
    if enemies_left then
        run.phase_done = 0
    end
    if not enemies_left and run.phase_done == 1 and run.go == 0 then
        if run.last_phase ~= 0 then
            target = "last_check"
        else
            run.go = 169
            if run.phase == data.phase_count - 1 then
                run.last_phase = 1
                state.stage_bound = 0
            end
            target = "clear"
        end
    else
        if run.go > 0 and run.go < 100 then
            if group < constants.stage_groups.survival then
                display[#display + 1] = {"sprite", menu_sheet, frames[25], 265, 299}
                display[#display + 1] = {"sprite", menu_sheet, frames[36], 490, 299}
                display[#display + 1] = {"sprite", menu_sheet, frames[group + 27], 460, 299}
                display[#display + 1] = {"sprite", menu_sheet, frames[run.id % 10 + 27], 520, 299}
            else
                display[#display + 1] = {"sprite", menu_sheet2, survival_frame, 165, 299}
            end
            run.go = run.go - 1
        end
        target = (run.go > 100 and run.go < 300) and "clear" or "last_check"
    end
    if target == "clear" then
        if run.phase >= 0 and run.phase < 99 and run.last_phase ~= 1
           and phase_data(run, run.phase).bound == phase_data(run, run.phase + 1).bound then
            run.go = 0
        end
        if cmod(cdiv(run.go, 10), 2) == 1 then
            if cmod(run.go, 10) == 0 and run.go < 200 then sounds.direct(state, "ok") end
            display[#display + 1] = {"sprite", menu_sheet, frames[24], 660, 299}
        end
        run.go = run.go - 1
        if run.go == 101 or run.go == 201 then
            if run.last_phase ~= 1 then run.go = 0
            else
                run.go = 280
                target = "final"
            end
        end
        if target ~= "final" then target = "last_check" end
    end
    if target == "last_check" then target = run.last_phase == 1 and "final" or "shutter_out" end
    if target == "final" then
        if run.shutter ~= 0 then
            target = "shutter_out"
        else
            local next_exists = stage_list()[run.id + 1] ~= nil
            if run.id % 10 ~= 9 and next_exists then
                local bound = phase_data(run, run.phase).bound
                local all_done = true
                for index = 0, 19 do
                    local value = state.items[index]
                    if value and value.record.kind == record_kinds.character and value.hp > 0 and value.x_int < bound then all_done = false end
                end
                if all_done then
                    run.shutter = 1
                    target = "shutter_in"
                else
                    target = "items"
                end
            else
                if state.round_counter == 1 then
                    -- Normal speed returns and the music stops.
                    sounds.direct(state, "pass")
                    speed.fast = false
                    music.stop()
                end
                if state.round_counter < 90 then
                    display[#display + 1] = {"sprite", menu_sheet, frames[37], 215, 298}
                end
                if run.result == 0 then run.result = 1 end
                run.last_phase, run.go, run.shutter = 0, 0, 0
                target = "items"
            end
        end
    end
    if target == "shutter_out" then
        if run.shutter >= 11 and run.shutter <= 20 then
            shutter(display, cdiv((21 - run.shutter) * 43, 10))
            run.shutter = run.shutter + 1
            if run.shutter == 21 then run.shutter = 0 end
        elseif run.shutter > 0 and run.shutter < 11 then
            target = "shutter_in"
        end
    end
    if target == "shutter_in" then
        shutter(display, cdiv(run.shutter * 43, 10))
        run.shutter = run.shutter + 1
        if run.shutter == 11 then next_stage(state, run) end
    end
    stage.status(state, run, display)
    return display
end

function stage.status(state, run, display)
    local any_alive = false
    for index = 0, 19 do
        local value = state.items[index]
        if value and value.record.kind == record_kinds.character and value.hp > 0 and value.team ~= constants.teams.enemies then any_alive = true break end
    end
    local men_a, hp_a, men_b, hp_b, reserve = 0, 0, 0, 0, 0
    for index = 0, 399 do
        local value = state.items[index]
        if value and value.record.kind == record_kinds.character then
            if value.team ~= constants.teams.enemies then
                if value.hp > 0 then
                    hp_a = hp_a + value.hp
                    men_a = men_a + 1
                end
                local lives = value.lives
                if lives >= 2 and any_alive then
                    reserve = reserve + lives - 1
                elseif not (lives < 2 and any_alive and lives >= 0) then
                    value.lives = -value.lives
                end
            elseif value.hp > 0 then
                hp_b = hp_b + value.hp
                men_b = men_b + 1
            end
        end
    end
    if run.id < constants.stage_levels.survival_start then
        display[#display + 1] = {"text", string.format("STAGE %d-%d", cdiv(run.id, 10) + 1, run.id % 10 + 1),
            360, 110, 0xc8c8c8}
    elseif run.survival >= 0 then
        if run.survival_blink > 0 then run.survival_blink = run.survival_blink + 1 end
        if run.survival_blink > 69 then run.survival_blink = 0 end
        local color = (run.survival_blink ~= 0 and cdiv(run.survival_blink, 10) % 2 ~= 1) and 0xc85a5a or 0xc8c8c8
        display[#display + 1] = {"text", "Survival Stage: " .. run.survival, 340, 110, color}
    end
    local left = string.format("Man: %3d      HP: %4d", men_a, hp_a)
    if reserve ~= 0 then left = left .. string.format("     Reserve: %3d", reserve) end
    display[#display + 1] = {"text", left, 10, 110, 0xff7878}
    display[#display + 1] = {"text", string.format("Man: %3d      HP: %4d", men_b, hp_b), 645, 110, 0xff00ff}
end

function stage.round_counter(state, run)
    local alive = false
    for index = 0, 399 do
        local value = state.items[index]
        if value and value.hp > 0 and value.record.kind == record_kinds.character
           and value.team > constants.teams.independent
           and value.team < constants.teams.active_end_exclusive
           and value.team ~= constants.teams.enemies then
            alive = true
        end
    end
    if not alive or run.result > 0 then
        state.round_counter = state.round_counter + 1
        if run.result < 1 and state.round_counter == 80 then
            sounds.direct(state, "finish")
            speed.fast = false
            music.stop()
        end
    end
end

function stage.round_keys(state, run)
    for index = 0, 7 do
        local value = state.items[index]
        if value and (value.keys.attack or value.keys.jump) then
            if state.random_game or run.result ~= 1 then
                if run.result == 2 or run.result == 0 then
                    run.id = cdiv(run.id, 10) * 10
                    state.round_counter = 350
                end
            else
                run.result = 3
            end
        end
    end
end
return stage
