-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local constants = require("base/game/constants")
local record_kinds = constants.record_kinds
local hit_fa_modes = constants.hit_fa_modes
local object_data = require("base/game/object_data")
local catalog = require("base/game/catalog")
local item = require("base/game/item")
local sounds = require("base/game/sounds")
local objects = {}

local function cdiv(a, b)
    local q = a / b
    if q >= 0 then return math.floor(q) end
    return math.ceil(q)
end
local function trunc(value)
    if value >= 0 then return math.floor(value) end
    return math.ceil(value)
end
local abs = math.abs
local function random(range) return engine.random(range) end

-- FindRecordIndex: the first catalog record with this id, parsed once per match.
function objects.record(state, id)
    state.records = state.records or {}
    local cached = state.records[id]
    if cached ~= nil then return cached or nil end
    local entry = catalog.objects().by_id[id]
    if not entry then
        state.records[id] = false
        return nil
    end
    local record = item.record(entry, object_data.load(entry.path))
    state.records[id] = record
    return record
end

function objects.free_slot(state)
    for index = 50, 399 do
        if not state.items[index] then return index end
    end
    return -1
end

-- Removed items stay readable (the original keeps their memory), e.g. for stale targets.
function objects.remove(state, index)
    local value = state.items[index]
    if value then
        state.removed = state.removed or {}
        state.removed[index] = value
        state.items[index] = nil
    end
end
function objects.lookup(state, index)
    if index < 0 or index > 399 then return nil end
    return state.items[index] or (state.removed and state.removed[index])
end

-- The creators' common placement (580, -200, 300) and drop counter.
local function new_item(record)
    local value = item.create(record)
    value.x, value.y, value.z = 580.0, -200.0, 300.0
    value.drop_counter = record.data.weapon.hp or 0
    return value
end

local function activate(state, slot, value)
    if state.removed then state.removed[slot] = nil end
    state.items[slot] = value
end

-- The creators' common part: places a fresh item of record `id` at `slot`; nil when the
-- record is missing.
function objects.place(state, slot, id)
    local record = objects.record(state, id)
    if not record then return nil end
    local value = new_item(record)
    activate(state, slot, value)
    return value
end

function objects.create(state, id, owner, frame, team, x, y, z, vx, vy, vz, facing)
    local slot = objects.free_slot(state)
    if slot == -1 then return -1 end
    local record = objects.record(state, id)
    if not record then return -1 end
    local value = new_item(record)
    value.owner = owner
    value.x_int, value.y_int, value.z_int = x, y, z
    value.team = team
    value.x, value.y, value.z = x, y, z
    value.frame = frame
    value.vx, value.vy, value.vz = vx, vy, vz
    value.facing = facing
    activate(state, slot, value)
    return slot
end

local function create_effect(state, me, id, frame)
    local slot = objects.free_slot(state)
    if slot == -1 then return -1 end
    local record = objects.record(state, id)
    if not record then return -1 end
    local value = new_item(record)
    value.owner = me.owner
    value.x_int, value.y_int, value.z_int = me.x_int, me.y_int, me.z_int
    value.team = me.team
    value.x, value.y, value.z = me.x, me.y, me.z
    value.frame = frame
    activate(state, slot, value)
    return slot, value
end

-- Frame opoint spawning, run after the frame advance when the frame has just started. Returns
-- false when the frame does not spawn (the original then checks destroyed weapons instead).
function objects.spawn_from_frame(state, index, parent)
    local frame = parent.record.frame(parent.frame)
    local point = frame.opoint
    if point.kind <= 0 or point.oid <= 0 or parent.wait_counter ~= 0
       or (parent.hit_lag ~= 0 and parent.record.kind == record_kinds.character) then
        return false
    end
    local total = point.facing
    local variant, groups = total, 1
    if total > 10 then
        variant = total % 10
        groups = cdiv(total, 10)
    end
    local spawned = {}
    for group = 0, groups - 1 do
        local slot = objects.free_slot(state)
        local record = objects.record(state, point.oid)
        if slot == -1 or not record then break end
        spawned[#spawned + 1] = slot
        local value = new_item(record)
        value.owner = parent.owner
        for other = 0, 399 do
            local existing = state.items[other]
            if existing then existing.pair_rest[slot] = 0 end
        end
        activate(state, slot, value)
        local base_y = parent.y_int - frame.center_y
        if parent.facing == 0 then value.x_int = parent.x_int - frame.center_x + point.x
        else value.x_int = frame.center_x - point.x + parent.x_int end
        value.y_int = base_y + point.y
        value.team = parent.team
        value.z = parent.z + 1.0
        value.y = value.y_int
        value.frame = point.action
        value.vy = point.dvy
        value.vz = 0.0
        local spawned_state = record.frame(value.frame).state
        if (spawned_state == constants.frame_states.flying_ball
            or spawned_state == constants.frame_states.thrown_item or spawned_state == constants.frame_states.flying_missile)
           and record.id ~= constants.object_ids.firzen_ball and record.id ~= constants.object_ids.bat_ball then
            if not parent.keys.up then
                if parent.keys.down then value.vz = 2.5 end
            elseif not parent.keys.down then
                value.vz = -2.5
            end
            if record.id == constants.object_ids.firen_flame then value.vz = value.vz * 0.25 end
        end
        if record.kind == record_kinds.character then
            value.follow = parent.follow > -1 and parent.follow or index
            value.blink = parent.blink
        end
        if variant == 0 then value.facing = parent.facing
        elseif variant == 1 then value.facing = 1 - parent.facing
        else value.facing = 0 end
        value.vx = value.facing == 0 and point.dvx or -point.dvx
        value.x = value.x_int
        if groups > 1 then
            local spread = (group * 10.0) / (groups - 1.0) - 5.0
            value.vz = spread + value.vz
            if value.vx <= 0.0 or spread <= 0.0 then
                if 0.0 <= value.vx or 0.0 <= spread then value.vx = spread + value.vx
                else value.vx = -spread + value.vx end
            else
                value.vx = -spread + value.vx
            end
        end
        if parent.record.kind == record_kinds.ball and frame.state == constants.frame_states.rebound_ball then
            local hitter = state.items[parent.walk_phase]
            if hitter then hitter.pair_rest[slot] = 10 end
            value.pair_rest[parent.walk_phase] = 10
        end
        if record.id == constants.fighter_ids.rudolf or record.id == constants.fighter_ids.julian then
            value.hp, value.max_hp, value.dark_hp, value.mp = 10, 10, 10, 5
        end
        value.x_int, value.y_int, value.z_int = trunc(value.x), trunc(value.y), trunc(value.z)
        if point.kind == constants.opoint_kinds.held_spawn then
            -- The spawner holds the new object like a light weapon.
            parent.weapon, value.weapon = 1, -1
            parent.held_item, value.holder = slot, index
            value.team = parent.team
        end
    end
    local created = #spawned
    if created > 1 then
        -- Staggered attack rests and mutual pair rests inside a group.
        local half = cdiv(created, 2)
        for k = 0, created - 1 do
            local value = state.items[spawned[k + 1]]
            if created % 2 == 0 then
                if k < half - 1 then value.timer_ec = (half - k) * 2 - 2
                elseif half < k then value.timer_ec = (k - half) * 2 end
            else
                if half <= k then
                    if k > half then value.timer_ec = (k - half) * 2 end
                else
                    value.timer_ec = (half - k) * 2
                end
            end
            for j = 0, k - 1 do
                value.pair_rest[spawned[j + 1]] = 40
                state.items[spawned[j + 1]].pair_rest[spawned[k + 1]] = 40
            end
        end
    end
    return true
end

function objects.state_effects(state, index, value)
    local previous = value.record.frame(value.state_frame).state
    local current = value.record.frame(value.frame).state
    if (previous == constants.frame_states.frozen or value.state_frame == 200)
       and current ~= constants.frame_states.frozen and value.frame ~= 200 then
        sounds.effect(state, value.x_int, 15)
    end
    if (previous == constants.frame_states.frozen or value.state_frame == 200)
       and current ~= constants.frame_states.frozen and value.frame ~= 200
       and objects.record(state, constants.object_ids.broken_weapon) then
        for piece = 0, 14 do
            local slot = objects.free_slot(state)
            if slot == -1 then break end
            local shard = objects.place(state, slot, constants.object_ids.broken_weapon)
            shard.x_int, shard.y_int, shard.z_int = value.x_int, value.y_int, value.z_int
            shard.z = value.z
            shard.y = value.y - random(29)
            shard.x = (random(39) - 19) + value.x
            shard.vy = -cdiv(random(20), 2) - 8.0
            shard.vx = value.impulse_x * 0.5 + (random(11) - 5.0)
            if piece < 2 then shard.frame = 120
            elseif piece < 5 then shard.frame = 130
            elseif piece < 9 then shard.frame = 125
            else shard.frame = 135 end
        end
    end
    if previous == constants.frame_states.burning or previous == constants.frame_states.burning_run then
        local puffs = 7
        if current == constants.frame_states.burning or current == constants.frame_states.burning_run then puffs = random(4) == 0 and 1 or 0 end
        for _ = 1, puffs do
            local slot = objects.free_slot(state)
            if slot == -1 then break end
            local puff = objects.place(state, slot, constants.object_ids.broken_weapon)
            if not puff then break end
            puff.x_int, puff.y_int, puff.z_int = value.x_int, value.y_int, value.z_int
            puff.z = value.z
            puff.y = value.y - random(29)
            puff.x = (random(59) - 29) + value.x
            puff.vy = -1.0
            puff.vx = (random(11) - 5.0) + value.vx
            puff.frame = random(1) + 140
        end
    end
end

local function candidates(state, me)
    local list = {}
    for index = 0, 399 do
        local value = state.items[index]
        if value and value.record.kind == record_kinds.character and value.team ~= me.team and value.hp > 0 then
            list[#list + 1] = index
        end
    end
    return list
end

function objects.update(state, index)
    local me = state.items[index]
    local hit_fa_mode = me.record.frame(me.frame).hits.Fa
    if hit_fa_mode == hit_fa_modes.explosion then
        local c = objects.create
        c(state, constants.object_ids.firen_flame, me.owner, 109, me.team, me.x_int, me.y_int, me.z_int, me.vx, me.vy, me.vz, me.facing)
        c(state, constants.object_ids.firzen_chase_fire, me.owner, 81, me.team, me.x_int, me.y_int - 100, me.z_int, me.vx, me.vy, me.vz, me.facing)
        c(state, constants.object_ids.freeze_column, me.owner, 100, me.team, me.x_int + 80, me.y_int - 3, me.z_int, me.vx, me.vy, me.vz - 7.0, 0)
        c(state, constants.object_ids.freeze_column, me.owner, 100, me.team, me.x_int + 100, me.y_int - 3, me.z_int, me.vx, me.vy, me.vz, 0)
        c(state, constants.object_ids.freeze_column, me.owner, 100, me.team, me.x_int + 80, me.y_int - 3, me.z_int, me.vx, me.vy, me.vz + 7.0, 0)
        c(state, constants.object_ids.freeze_column, me.owner, 100, me.team, me.x_int - 80, me.y_int - 3, me.z_int, me.vx, me.vy, me.vz - 7.0, 1)
        c(state, constants.object_ids.freeze_column, me.owner, 100, me.team, me.x_int - 100, me.y_int - 3, me.z_int, me.vx, me.vy, me.vz, 1)
        c(state, constants.object_ids.freeze_column, me.owner, 100, me.team, me.x_int - 80, me.y_int - 3, me.z_int, me.vx, me.vy, me.vz + 7.0, 1)
        c(state, constants.object_ids.firen_flame, me.owner, 50, me.team, me.x_int - 30, me.y_int - 1, me.z_int - 5, me.vx, me.vy, me.vz, 1)
        c(state, constants.object_ids.firen_flame, me.owner, 50, me.team, me.x_int + 30, me.y_int - 1, me.z_int - 5, me.vx, me.vy, me.vz, 1)
        c(state, constants.object_ids.firen_flame, me.owner, 50, me.team, me.x_int - 30, me.y_int - 1, me.z_int + 2, me.vx, me.vy, me.vz, 0)
        c(state, constants.object_ids.firen_flame, me.owner, 50, me.team, me.x_int + 30, me.y_int - 1, me.z_int + 2, me.vx, me.vy, me.vz, 0)
        c(state, constants.object_ids.firen_flame, me.owner, 50, me.team, me.x_int, me.y_int - 1, me.z_int - 9, me.vx, me.vy, me.vz, 1)
        c(state, constants.object_ids.firen_flame, me.owner, 50, me.team, me.x_int, me.y_int - 1, me.z_int + 6, me.vx, me.vy, me.vz, 0)
        objects.remove(state, index)
    elseif hit_fa_mode == hit_fa_modes.multi_seeker then
        local list = candidates(state, me)
        local amount = 3
        if #list > 4 then amount = cdiv(#list - 3, 2) + 3 end
        repeat
            local slot, value = create_effect(state, me, constants.object_ids.bat_chase, 0)
            if slot == -1 then break end
            value.vx = random(21) - 11
            value.vy = 3.0 - random(24) * 0.25
            value.vz = 3.0 - random(24) * 0.25
            value.facing = me.facing
            value.chase_target = #list == 0 and index or list[random(#list) + 1]
            amount = amount - 1
        until amount == 0
        objects.remove(state, index)
        return
    elseif hit_fa_mode == hit_fa_modes.single_seeker then
        local list = candidates(state, me)
        local slot, value = create_effect(state, me, constants.object_ids.julian_ball, 0)
        if slot ~= -1 then
            value.y_int = me.y_int + random(7) - 3
            value.vx = me.vx
            value.vz = 3.0 - random(24) * 0.25 + me.vz
            value.facing = me.facing
            value.chase_target = #list == 0 and index or list[random(#list) + 1]
        end
        objects.remove(state, index)
        return
    elseif hit_fa_mode == hit_fa_modes.ally_projectiles then
        for other = 0, 399 do
            local ally = state.items[other]
            if ally and ally.record.kind == record_kinds.character and ally.team == me.team and ally.hp > 0 then
                local slot, value = create_effect(state, me, constants.object_ids.jan_ally_chase, 0)
                if slot ~= -1 then
                    value.vx = cdiv(ally.x_int - value.x_int, 50)
                    value.vy, value.vz, value.facing = 0.0, 0.0, 0
                    value.chase_target = other
                end
            end
        end
        objects.remove(state, index)
        return
    elseif hit_fa_mode == hit_fa_modes.enemy_seeker or hit_fa_mode == hit_fa_modes.ranged_attack then
        local minimum = hit_fa_mode == hit_fa_modes.ranged_attack and 4 or 0
        local maximum = hit_fa_mode == hit_fa_modes.enemy_seeker and 7 or 10
        local spawned, pass, slot = 0, 0, nil
        repeat
            for other = 0, 399 do
                local enemy = state.items[other]
                if enemy and enemy.record.kind == record_kinds.character and enemy.team ~= me.team and enemy.hp > 0 then
                    if spawned < minimum or pass == 0 then
                        spawned = spawned + 1
                        slot = objects.free_slot(state)
                        if slot == -1 then break end
                        local id = hit_fa_mode == hit_fa_modes.enemy_seeker and constants.object_ids.jan_chase or constants.object_ids.firzen_chase_fire + random(2)
                        local value
                        slot, value = create_effect(state, me, id, 0)
                        if slot == -1 then break end
                        if hit_fa_mode == hit_fa_modes.enemy_seeker then
                            value.vx = cdiv(enemy.x_int - value.x_int, 50)
                            value.vy = -4 - random(4)
                        else
                            value.vx = random(21) - 11
                            value.vy = -2.0 - random(40) / 6.0
                        end
                        value.vz, value.facing = 0.0, 0
                        value.chase_target = other
                    end
                end
                if spawned >= maximum then break end
            end
            pass = pass + 1
        until not (spawned < minimum and spawned ~= 0 and slot ~= -1 and spawned < maximum)
        objects.remove(state, index)
        return
    elseif hit_fa_mode == hit_fa_modes.returning_copy then
        local slot, value = create_effect(state, me, me.record.id, 40)
        if slot ~= -1 then
            value.vx, value.vy, value.vz, value.facing = 0.0, 0.0, 0.0, 0
        end
    elseif hit_fa_mode == hit_fa_modes.accelerating then
        if 0.0 > me.vx then me.vx = me.vx - 1.1 else me.vx = me.vx + 1.1 end
        if me.vx > 30.0 then me.vx = 30.0 end
        if me.vx < -30.0 then me.vx = -30.0 end
        if me.y > 3.0 then me.y = 3.0 end
        me.facing = me.vx > 0.0 and 0 or 1
        return
    end
    local active = state.items[index] ~= nil
    -- Shared steering: keep or find the nearest living enemy character.
    local linked_team = -1
    if me.thrower >= 0 and state.items[me.thrower] then linked_team = state.items[me.thrower].team end
    if hit_fa_mode ~= hit_fa_modes.healing_projectile
       and hit_fa_mode ~= hit_fa_modes.ally_projectiles and hit_fa_mode ~= hit_fa_modes.enemy_seeker
       and hit_fa_mode ~= hit_fa_modes.returning_copy then
        local current = objects.lookup(state, me.chase_target)
        local current_state = current and current.record.frame(current.frame).state
        if me.chase_target == -1 or not state.items[me.chase_target] or current.hp <= 0 or current_state == constants.frame_states.lying
           or abs(current.blink) > 2 or current.team == me.team or linked_team == current.team then
            local distance = 10000
            for other = 0, 399 do
                local enemy = state.items[other]
                if other ~= index and enemy and enemy.record.kind == record_kinds.character and enemy.team ~= me.team
                   and linked_team ~= enemy.team then
                    local lying = enemy.record.frame(enemy.frame).state == constants.frame_states.lying or abs(enemy.blink) > 2
                    if not (lying and me.chase_target ~= -1) and enemy.hp > 0 then
                        local next = abs(enemy.z_int - me.z_int) + abs(enemy.x_int - me.x_int)
                        if next < distance then me.chase_target, distance = other, next end
                    end
                end
            end
            if me.chase_target == -1 then
                me.hp = 0
                return
            end
        end
    end
    local target = objects.lookup(state, me.chase_target)
    if not target then return end
    if hit_fa_mode == hit_fa_modes.chase then
        if target.x_int > me.x_int then me.vx = me.vx + 0.85 end
        if target.x_int < me.x_int then me.vx = me.vx - 0.85 end
        if target.z_int > me.z_int + 7 then me.vz = me.vz + 0.3 end
        if target.z_int < me.z_int - 7 then me.vz = me.vz - 0.3 end
        me.vy = me.vy / 1.4
        if target.record.kind == record_kinds.character then
            if target.y > me.y + 10.0 then me.y = me.y + 1.2 end
            if target.y < me.y + 10.0 then me.y = me.y - 1.2 end
        elseif me.y > 0.0 then
            me.y = me.y + 1.0
        end
        if me.vx > 13.0 then me.vx = 13.0 end
        if me.vx < -13.0 then me.vx = -13.0 end
        if me.vz > 2.0 then me.vz = 2.0 end
        if me.vz < -2.0 then me.vz = -2.0 end
        if me.y > 1.0 then me.y = 1.0 end
        me.facing = me.vx > 0.0 and 0 or 1
        return
    end
    if hit_fa_mode == hit_fa_modes.healing_projectile and target.hp > 0
       and me.x_int > target.x_int - 30 and me.x_int < target.x_int + 30
       and me.y_int > target.y_int - 80 and me.y_int < target.y_int
       and me.z_int > target.z_int - 10 and me.z_int < target.z_int + 10 then
        me.vx, me.vy, me.vz = 0.0, 0.0, 0.0
        me.frame = 60
        target.heal_timer = 100
        return
    end
    local chasing = hit_fa_mode == hit_fa_modes.special_chase or hit_fa_mode == hit_fa_modes.unanimated_chase
        or hit_fa_mode == hit_fa_modes.animated_chase or hit_fa_mode == hit_fa_modes.healing_projectile
        or hit_fa_mode == hit_fa_modes.returning_copy
    if chasing and me.hp > 0 and active then
        if target.x_int > me.x_int then me.vx = me.vx + 0.7 end
        if target.x_int < me.x_int then me.vx = me.vx - 0.7 end
        if hit_fa_mode == hit_fa_modes.returning_copy then
            if target.x_int > me.x_int then me.vx = me.vx + 0.7 end
            if target.x_int < me.x_int then me.vx = me.vx - 0.7 end
        end
        if target.z_int > me.z_int + 5 then me.vz = me.vz + 0.4 end
        if target.z_int < me.z_int - 5 then me.vz = me.vz - 0.4 end
        if hit_fa_mode == hit_fa_modes.animated_chase or hit_fa_mode == hit_fa_modes.healing_projectile
           or hit_fa_mode == hit_fa_modes.unanimated_chase then
            me.vy = me.vy / 1.4
            if target.record.kind == record_kinds.character then
                if target.y > me.y + 40.0 then me.y = me.y + 1.0 end
                if target.y < me.y + 40.0 then me.y = me.y - 1.0 end
            elseif me.y > 0.0 then
                me.y = me.y + 1.0
            end
        elseif hit_fa_mode == hit_fa_modes.returning_copy then
            if me.vy < 4.0 then me.vy = me.vy + 0.4 end
            me.y = me.y + me.vy
            if me.y_int > -25 then
                me.frame = 60
                me.vz, me.vx, me.vy = 0.0, 0.0, 0.0
            end
        end
        if me.vx > 14.0 then me.vx = 14.0 end
        if me.vx < -14.0 then me.vx = -14.0 end
        if me.y > 1.4 then me.y = 1.4 end
        local limit = hit_fa_mode == hit_fa_modes.special_chase and 1.5 or 2.2
        if me.vz > limit then me.vz = limit end
        if me.vz < -limit then me.vz = -limit end
        me.facing = me.vx > 0.0 and 0 or 1
        local speed = abs(me.vx)
        if hit_fa_mode == hit_fa_modes.animated_chase then
            if speed <= 14.0 then
                if speed <= 7.0 then
                    if me.frame ~= 1 and me.frame ~= 2 then me.frame = 1 end
                elseif me.frame ~= 3 and me.frame ~= 4 then
                    me.frame = 3
                end
            elseif me.frame ~= 5 and me.frame ~= 6 then
                me.frame = 5
            end
        elseif hit_fa_mode == hit_fa_modes.special_chase then
            if speed < 8.0 then
                if me.frame < 10 then me.frame = me.frame + 50 end
            elseif me.frame > 40 then
                me.frame = me.frame - 50
            end
        end
        return
    end
    if chasing and (me.hp <= 0 or not active) then
        me.vx = me.vx + (me.vx >= 0.0 and 2.0 or -2.0)
        if me.vx > 17.0 then me.vx = 17.0 end
        if me.vx < -17.0 then me.vx = -17.0 end
        if hit_fa_mode == hit_fa_modes.animated_chase or hit_fa_mode == hit_fa_modes.healing_projectile
           or hit_fa_mode == hit_fa_modes.special_chase or hit_fa_mode == hit_fa_modes.unanimated_chase then
            if me.y > 1.4 then me.y = 1.4 end
        elseif hit_fa_mode == hit_fa_modes.returning_copy then
            if me.vy < 4.0 then me.vy = me.vy + 0.4 end
            me.y = me.y + me.vy
            if me.y_int > -25 then
                me.frame = 60
                me.y_int = -25
                me.vz, me.vx, me.vy = 0.0, 0.0, 0.0
            end
        end
        me.facing = me.vx > 0.0 and 0 or 1
        local speed = abs(me.vx)
        if hit_fa_mode == hit_fa_modes.animated_chase then
            if speed > 14.0 then
                if me.frame ~= 5 and me.frame ~= 6 then me.frame = 5 end
            elseif speed > 7.0 then
                if me.frame ~= 3 and me.frame ~= 4 then me.frame = 3 end
            elseif me.frame ~= 1 and me.frame ~= 2 then
                me.frame = 1
            end
        end
        return
    end
    if hit_fa_mode == hit_fa_modes.projectile_chase then
        if target.x_int > me.x_int then me.vx = me.vx + 0.7 end
        if target.x_int < me.x_int then me.vx = me.vx - 0.7 end
        if target.z_int > me.z_int + 10 then me.vz = me.vz + 0.17 end
        if target.z_int < me.z_int - 10 then me.vz = me.vz - 0.17 end
        if me.vx > 16.0 then me.vx = 16.0 end
        if me.vx < -16.0 then me.vx = -16.0 end
        if me.vz > 2.4 then me.vz = 2.4 end
        if me.vz < -2.4 then me.vz = -2.4 end
    end
end
return objects
