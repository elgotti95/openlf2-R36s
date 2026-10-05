-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local constants = require("base/game/constants")
local sounds = require("base/game/sounds")
local unlock = require("base/game/unlock")
local control = {}

local function cdiv(a, b)
    local q = a / b
    if q >= 0 then return math.floor(q) end
    return math.ceil(q)
end
local function cmod(a, b) return a - cdiv(a, b) * b end

local press_fields = {"attack_press", "jump_press", "defend_press", "right_press", "left_press",
    "up_press", "down_press"}
local function clear_presses(value)
    for _, field in ipairs(press_fields) do value[field] = 0 end
end

function control.enter_frame(match, value, target)
    local turn = false
    if target < 0 then
        target = -target
        turn = true
    end
    if target == 999 then target = 0 end
    local frame = value.record.frames[target]
    if not frame then return end
    if not match.running then
        value.frame = target
        clear_presses(value)
        return
    end
    local cost = frame.mp
    local mp_cost, hp_cost = cmod(cost, 1000), cdiv(cost, 1000) * 10
    if value.mp >= mp_cost and value.hp > hp_cost then
        value.hp = value.hp - hp_cost
        value.mp = value.mp - mp_cost
        value.hp_spent = value.hp_spent + hp_cost
        value.mp_spent = value.mp_spent + mp_cost
        value.frame = target
        if turn then value.facing = 1 - value.facing end
        clear_presses(value)
    end
end

local exclusions = {U = "up_press", D = "down_press", L = "left_press", R = "right_press",
    d = "defend_press", j = "jump_press", a = "attack_press"}
local function interrupted(value, expected, advanced)
    for _, field in ipairs(press_fields) do
        if value[field] == 5 and (not advanced or field ~= exclusions[expected]) then return true end
    end
    return false
end

-- Defend, then a direction or jump, then attack or jump. `hit` names the frame field holding
-- the target frame; `facing` is forced for left/right sequences.
local sequences = {
    {"right_press", "R", "attack_press", "a", "Fa", 0},
    {"left_press", "L", "attack_press", "a", "Fa", 1},
    {"up_press", "U", "attack_press", "a", "Ua"},
    {"down_press", "D", "attack_press", "a", "Da"},
    {"right_press", "R", "jump_press", "j", "Fj", 0},
    {"left_press", "L", "jump_press", "j", "Fj", 1},
    {"up_press", "U", "jump_press", "j", "Uj"},
    {"down_press", "D", "jump_press", "j", "Dj"},
    {"jump_press", "j", "attack_press", "a", "ja"},
}
-- Whether a chord of defend (d), jump (j) and attack (a) ("da", "dj", "daj") could start
-- a move for `value`'s fighter in its current frame, whatever the direction: D+A is any of the
-- Defend, direction, Attack sequences (hit_Fa, hit_Ua, hit_Da), D+J likewise with Jump (hit_Fj,
-- hit_Uj, hit_Dj), and D+J+A is hit_ja.
local chord_hits = {da = {"Fa", "Ua", "Da"}, dj = {"Fj", "Uj", "Dj"}, daj = {"ja"}}
function control.chord_available(value, chord)
    local fields = value and chord_hits[chord]
    if not fields then return false end
    -- The sequence begins with Defend, which moves the fighter to the frame its hit_d names (the
    -- defend stance): walking and running frames often carry no combo fields themselves.
    local frame = value.record.frame(value.frame)
    local candidates = {frame.hits}
    if frame.hits.d ~= 0 then candidates[2] = value.record.frame(frame.hits.d).hits end
    for _, hits in ipairs(candidates) do
        for _, field in ipairs(fields) do
            if hits[field] ~= 0 and value.weapon ~= 2 and (field ~= "ja" or value.transform == -1) then return true end
        end
    end
    return chord == "daj" and value.twin == 1
end
local completed_sequence = 3
local function recognize(match, value, index)
    local spec = sequences[index]
    local state = value.sequences[index]
    local advanced = false
    if state == 0 and value.defend_press == 5 then state, advanced = 1, true end
    if state == 1 then
        if value[spec[1]] == 5 then state, advanced = 2, true
        elseif interrupted(value, "d", advanced) then state = 0 end
    end
    if state == 2 then
        if value[spec[3]] == 5 then state, advanced = completed_sequence, true
        elseif interrupted(value, spec[2], advanced) then state = 0 end
    end
    if state == completed_sequence then
        local frame = value.record.frame(value.frame)
        local target = frame.hits[spec[5]]
        if index == 9 then
            if value.record.id == constants.fighter_ids.louis and target == 300 and value.hp > 177 and unlock.flags.characters == 0 then
                value.sequences[index] = state
                return
            end
            if target ~= 0 and value.transform == -1 and value.weapon ~= 2 then
                control.enter_frame(match, value, target)
                value.sequences[index] = 0
                return
            end
            if value.twin == 1 then
                value.merge_timer = 0
                value.sequences[index] = state
                return
            end
        elseif target ~= 0 and value.weapon ~= 2 then
            control.enter_frame(match, value, target)
            if spec[6] then value.facing = spec[6] end
            value.sequences[index] = 0
            return
        end
        if interrupted(value, spec[4], advanced) then state = 0 end
    end
    value.sequences[index] = state
end

-- Walk/heavy-walk animation phase: frames base, base+1 ... base+3, back down.
local function walk_cycle(value, base)
    local rate = value.record.movement.walking_frame_rate or 1
    value.walk_phase = (value.walk_phase + 1) % (rate * 6)
    if value.walk_phase < rate * 4 then value.frame = cdiv(value.walk_phase, rate) + base
    else value.frame = base + 6 - cdiv(value.walk_phase, rate) end
end

local function spend_mp(match, value, frame_id)
    if not match.running then return end
    local cost = value.record.frame(frame_id).mp
    value.mp = value.mp - cost
    if value.mp < 0 then value.mp = 0 else value.mp_spent = value.mp_spent + cost end
end

-- States 0/1 (standing, walking). `heavy` selects the heavy-weapon variant.
local function walking(match, value, heavy)
    local keys, previous, movement = value.keys, value.previous_keys, value.record.movement
    local base, run_frame = heavy and 12 or 5, heavy and 16 or 9
    local speed = (heavy and movement.heavy_walking_speed or movement.walking_speed) or 0
    local speedz = (heavy and movement.heavy_walking_speedz or movement.walking_speedz) or 0
    if value.dash_counter > 0 then value.dash_counter = value.dash_counter - 1 end
    if value.dash_counter < 0 then value.dash_counter = value.dash_counter + 1 end
    if heavy and value.frame < 12 then value.frame = 12 end
    if keys.right and not keys.left and value.y_int == 0 then
        if value.facing == 1 then value.dash_counter = 0 end
        value.facing = 0
        walk_cycle(value, base)
        value.vx = speed
        -- A second fresh press within ten frames starts running.
        if not previous.right then value.dash_counter = value.dash_counter + 10 end
        if value.dash_counter >= 11 then
            value.frame = run_frame
            value.walk_phase, value.dash_counter = 0, 0
        end
    end
    if not keys.right and keys.left and value.y_int == 0 then
        if value.facing == 0 then value.dash_counter = 0 end
        value.facing = 1
        walk_cycle(value, base)
        value.vx = -speed
        if not previous.left then value.dash_counter = value.dash_counter - 10 end
        if value.dash_counter <= -11 then
            value.frame = run_frame
            value.walk_phase, value.dash_counter = 0, 0
        end
    end
    local sideways = keys.left == keys.right
    if keys.up and not keys.down and value.y_int == 0 then
        if sideways then walk_cycle(value, base) end
        value.vz = -speedz
        value.vx = value.vx / 1.4
    end
    if keys.down and not keys.up and value.y_int == 0 then
        if sideways then walk_cycle(value, base) end
        value.vz = speedz
        value.vx = value.vx / 1.4
    end
    if keys.attack and value.attack_press > 0 then
        value.dash_counter, value.wait_counter = 0, 0
        if heavy then
            value.frame = 50
        elseif value.weapon == 0 then
            if value.super_window > 0 then value.frame = 70
            else
                value.frame = (engine.random(2) + 12) * 5
                spend_mp(match, value, value.frame)
            end
        elseif value.weapon % 100 == 1 then
            if value.weapon == constants.weapon_holder_codes.knife_or_boomerang
               and (keys.right or keys.left or keys.up or keys.down) then
                value.frame = 45
            else
                value.frame = (engine.random(2) + 4) * 5
            end
        elseif value.weapon == 4 then value.frame = 45
        elseif value.weapon == 6 then value.frame = 55 end
    end
    if heavy then return end
    if keys.jump and value.jump_press > 0 then
        value.wait_counter, value.dash_counter = 0, 0
        value.frame = 210
    end
    if keys.defend and value.defend_lock == 0 and value.defend_press > 0 then
        value.dash_counter, value.wait_counter = 0, 0
        value.frame = 110
    end
end

-- State 2 (running), also with a heavy weapon.
local function running(match, value, heavy)
    local keys, movement = value.keys, value.record.movement
    local rate = movement.running_frame_rate or 1
    value.wait_counter = 0
    value.walk_phase = (value.walk_phase + 1) % (rate * 4)
    local first, speed, speedz, brake
    if heavy then first, speed, speedz, brake = 16, movement.heavy_running_speed, movement.heavy_running_speedz, 19
    else first, speed, speedz, brake = 9, movement.running_speed, movement.running_speedz, 218 end
    if value.walk_phase < rate * 3 then value.frame = cdiv(value.walk_phase, rate) + first
    else value.frame = first + 1 end
    speed, speedz = speed or 0, speedz or 0
    if value.facing == 0 then
        value.vx = speed
        if keys.left then value.frame = brake end
    end
    if value.facing == 1 then
        value.vx = -speed
        if keys.right then value.frame = brake end
    end
    if keys.up and not keys.down and value.y_int == 0 then
        value.vz = -speedz
        value.vx = value.vx / 1.2
    end
    if not keys.up and keys.down and value.y_int == 0 then
        value.vz = speedz
        value.vx = value.vx / 1.2
    end
    local directions = keys.left or keys.right or keys.up or keys.down
    if keys.attack and value.attack_press > 0 then
        if heavy then value.frame = 50
        elseif value.weapon == 0 then
            if not match.running then value.frame = 85
            elseif value.mp >= value.record.frame(85).mp then
                local cost = value.record.frame(85).mp
                value.mp = value.mp - cost
                value.mp_spent = value.mp_spent + cost
                value.frame = 85
            end
        elseif value.weapon % 100 == 1 then value.frame = directions and 45 or 35
        elseif value.weapon == 4 then value.frame = 45
        elseif value.weapon == 6 then value.frame = directions and 45 or 55 end
    end
    if heavy then return end
    if keys.defend and value.defend_press > 0 then value.frame = 102 end
    if keys.jump and value.jump_press > 0 then
        sounds.effect(match, value.x_int, 7)
        value.dash_counter = 0
        value.frame = 213
        value.vx = (1 - 2 * value.facing) * (movement.dash_distance or 0)
        value.vy = movement.dash_height or 0
        if keys.up and not keys.down then value.vz = -(movement.dash_distancez or 0)
        elseif not keys.up and keys.down then value.vz = movement.dash_distancez or 0 end
    end
end

-- State 4 in the air: turn and attack.
local function jumping(match, value)
    local keys = value.keys
    if keys.right and not keys.left then value.facing = 0 end
    if keys.left and not keys.right then value.facing = 1 end
    if not keys.attack then return end
    if value.weapon == 0 then
        value.wait_counter = 0
        value.frame = 80
        spend_mp(match, value, 80)
    elseif value.weapon % 100 == 1 then
        value.wait_counter = 0
        local directions = keys.left or keys.right or keys.up or keys.down
        value.frame = directions and 52 or 30
    elseif value.weapon == 4 or value.weapon == 6 then
        value.frame = 52
    end
end

-- Frame 215 (landing crouch): defend rolls, jump dashes in the held or moving direction.
local function crouching(match, value)
    local keys, movement = value.keys, value.record.movement
    if keys.defend and value.defend_press > 0 then value.frame = 102 end
    if keys.jump and (keys.right or 0.001 < value.vx) and value.jump_press > 0 then
        sounds.effect(match, value.x_int, 7)
        value.frame = 213 + value.facing
        value.dash_counter = 0
        value.vx = movement.dash_distance or 0
        value.vy = movement.dash_height or 0
    end
    if keys.jump and (keys.left or -0.001 > value.vx) and value.jump_press > 0 then
        sounds.effect(match, value.x_int, 7)
        value.frame = 214 - value.facing
        value.dash_counter = 0
        value.vx = -(movement.dash_distance or 0)
        value.vy = movement.dash_height or 0
    end
    if keys.up and not keys.down then value.vz = -(movement.dash_distancez or 0)
    elseif not keys.up and keys.down then value.vz = movement.dash_distancez or 0 end
end

local function recovering(value)
    local keys, movement = value.keys, value.record.movement
    if not (value.fall_damage >= 0 and keys.jump and value.jump_press > 0 and value.hp > 0) then return end
    if value.facing == 0 then value.frame = value.vx <= 0.0 and 100 or 108
    else value.frame = value.vx >= 0.0 and 100 or 108 end
    value.wait_counter = 0
    local height, distance = movement.rowing_height or 0, movement.rowing_distance or 0
    if height < value.vy then value.vy = height end
    if value.vx < 1.0 and value.vx > -1.0 then
        value.vx = value.facing == 1 and distance or -distance
    else
        value.vx = value.vx > 0.0 and distance or -distance
    end
end

-- State 5 (dashing): turning picks the forward/backward dash frame; attacking only forward.
local function dashing(match, value)
    local keys = value.keys
    if keys.right and not keys.left then value.facing = 0 end
    if value.facing == 0 and value.frame ~= 217 and value.vx < 0.0 then value.frame = 214 end
    if value.facing == 0 and value.frame ~= 216 and value.vx > 0.0 then value.frame = 213 end
    if keys.left and not keys.right then value.facing = 1 end
    if value.facing == 1 and value.frame ~= 217 and value.vx > 0.0 then value.frame = 214 end
    if value.facing == 1 and value.frame ~= 216 and value.vx < 0.0 then value.frame = 213 end
    local forward = (value.vx > 0.0 and value.facing == 0) or (value.vx < 0.0 and value.facing == 1)
    if not forward or not keys.attack then return end
    local weapon = value.weapon
    if weapon == 0 then
        local cost = value.record.frame(90).mp
        if not match.running then value.frame = 90
        elseif value.mp >= cost then
            value.mp = value.mp - cost
            value.mp_spent = value.mp_spent + cost
            value.frame = 90
        end
        return
    end
    local directions = keys.left or keys.right or keys.up or keys.down
    if weapon % 100 == 1 or ((weapon == 4 or weapon == 6) and directions) then
        value.frame = (weapon == 4 or weapon == 6) and 52 or 40
        value.vy = value.vy - 1.0
        value.wait_counter = 0
    end
end

local function frame_velocity(value)
    local frame = value.record.frame(value.frame)
    local dvx = frame.dvx
    if dvx > 500 then value.vx = dvx - 550
    else
        if dvx > 0 and dvx > value.vx and value.facing == 0 then value.vx = dvx end
        if dvx > 0 and -value.vx < dvx and value.facing == 1 then value.vx = -dvx end
        if dvx < 0 and dvx < value.vx and value.facing == 0 then value.vx = dvx end
        if dvx < 0 and -value.vx > dvx and value.facing == 1 then value.vx = -dvx end
    end
    local dvy = frame.dvy
    if dvy ~= 0 then
        if dvy > 500 then value.vy = dvy - 550 else value.vy = dvy + value.vy end
    end
    local dvz = frame.dvz
    if dvz ~= 0 then
        if dvz > 500 then value.vz = dvz - 550
        else
            if value.keys.up and value.up_press >= value.down_press then value.vz = -dvz end
            if value.keys.down and value.up_press <= value.down_press then value.vz = dvz end
        end
    end
end

local key_press = {right = "right_press", left = "left_press", up = "up_press", down = "down_press",
    defend = "defend_press", jump = "jump_press", attack = "attack_press"}
local press_order = {"right", "left", "up", "down", "defend", "jump", "attack"}
local key_codes = {right = 6, left = 4, up = 8, down = 2, defend = 9, jump = 0, attack = 5}

function control.step(match, value)
    for _, field in ipairs(press_fields) do
        if value[field] > 0 then value[field] = value[field] - 1 end
    end
    if value.defend_lock > 0 then value.defend_lock = value.defend_lock - 1 end
    for _, key in ipairs(press_order) do
        if not value.previous_keys[key] and value.keys[key] then
            value[key_press[key]] = 5
            local history = value.key_history
            table.remove(history, 1)
            history[5] = key_codes[key]
        end
    end
    for index = 1, 9 do recognize(match, value, index) end

    -- A frame's hit_a/hit_d/hit_j continue to another frame on the freshest key.
    local frame = value.record.frame(value.frame)
    local hits = frame.hits
    if hits.a ~= 0 and value.attack_press > value.defend_press and value.attack_press > value.jump_press then
        control.enter_frame(match, value, hits.a)
        value.attack_press = 0
    elseif hits.d ~= 0 and value.defend_press > value.attack_press and value.defend_press > value.jump_press then
        control.enter_frame(match, value, hits.d)
        value.defend_press = 0
    elseif hits.j ~= 0 and value.jump_press > value.attack_press and value.jump_press > value.defend_press then
        control.enter_frame(match, value, hits.j)
        value.jump_press = 0
    end
    if value.frame == 110 then
        if value.keys.right then value.facing = 0 end
        if value.keys.left then value.facing = 1 end
    end
    local movement = value.record.movement
    local state = value.record.frame(value.frame).state
    if state == constants.frame_states.deep_dash_sword or state == constants.frame_states.burning_run then
        if value.keys.up and not value.keys.down and value.y_int == 0 then value.vz = -(movement.running_speedz or 0) end
        if value.keys.down and not value.keys.up and value.y_int == 0 then value.vz = movement.running_speedz or 0 end
    end
    if value.weapon ~= 2 and (state == constants.frame_states.standing or state == constants.frame_states.walking) then walking(match, value, false) end
    state = value.record.frame(value.frame).state
    if value.weapon == 2 and (state == constants.frame_states.standing or state == constants.frame_states.walking) then walking(match, value, true) end
    state = value.record.frame(value.frame).state
    if state == constants.frame_states.jumping and value.y_int < 0 then jumping(match, value) end
    state = value.record.frame(value.frame).state
    if state == constants.frame_states.running and value.weapon ~= 2 then running(match, value, false) end
    state = value.record.frame(value.frame).state
    if state == constants.frame_states.running and value.weapon == 2 then running(match, value, true) end
    if value.frame == 215 then crouching(match, value) end
    if value.frame == 182 or value.frame == 188 then recovering(value) end
    if value.record.frame(value.frame).state == constants.frame_states.dashing then dashing(match, value) end
    frame_velocity(value)
end
return control
