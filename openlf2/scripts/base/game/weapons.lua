-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local constants = require("base/game/constants")
local record_kinds = constants.record_kinds
local objects = require("base/game/objects")
local catalog = require("base/game/catalog")
local sounds = require("base/game/sounds")
local weapons = {}

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
local function is_weapon(kind)
    return kind == record_kinds.light_item or kind == record_kinds.heavy_item
        or kind == record_kinds.baseball or kind == record_kinds.drink
end
weapons.is_weapon = is_weapon

-- A drink that runs out drops from the holder's hand (the THROW macro of the reference).
local function drop_empty(holder, value)
    holder.weapon, value.weapon = 0, 0
    holder.held_item, value.holder = 0, 0
    value.frame = 0
    value.vy = -8.0
    value.vx = random(7) - 3
    holder.frame = 0
    value.drop_counter = 0
end

-- While the holder drinks (state 17): milk (122) gives hp/dark hp and mp, beer (123) mp.
-- Returns true when the drink ran out and was dropped.
local function drink(value, holder)
    local id = value.record.id
    if id == constants.item_ids.milk and value.hp > 0 then
        value.hp = value.hp - 1
        if value.hp % 5 == 0 then
            holder.dark_hp = holder.dark_hp + 2
            holder.hp = holder.hp + 4
            if holder.dark_hp > holder.max_hp then holder.dark_hp = holder.max_hp end
            if holder.hp > holder.dark_hp then holder.hp = holder.dark_hp end
        end
        if value.hp % 6 == 0 then
            holder.mp = holder.mp + 5
            if 500 < holder.mp then holder.mp = 500 end
        end
        if value.hp <= 0 then
            drop_empty(holder, value)
            return true
        end
    end
    if id == constants.item_ids.beer and value.hp > 0 then
        value.hp = value.hp - 2
        holder.mp = holder.mp + 3
        if 500 < holder.mp then holder.mp = 500 end
        -- The reference tests the drink's own follow index and mp here (as written).
        if value.follow > -1 and 150 < value.mp then holder.mp = 150 end
        if value.hp <= 0 then
            drop_empty(holder, value)
            return true
        end
    end
    return false
end

-- Throw depth from the holder's up/down keys.
local function throw_depth(holder, value, point)
    if holder.keys.up and not holder.keys.down then value.vz = -point.dvz
    elseif holder.keys.down and not holder.keys.up then value.vz = point.dvz end
end

function weapons.carry(state)
    local near, far = state.stage.zboundary[1] or 0, state.stage.zboundary[2] or 0
    for index = 0, 399 do
        local value = state.items[index]
        if value and value.record.kind == record_kinds.character then
            if value.z < near then value.z = near end
            if value.z > far then value.z = far end
            value.z_int = trunc(value.z)
        end
    end
    for index = 0, 399 do
        local value = state.items[index]
        if value and value.weapon < 0 then
            local holder = state.items[value.holder]
            if not holder or holder.held_item ~= index then
                value.weapon = 0
            elseif not (holder.record.frame(holder.frame).state == constants.frame_states.drinking and drink(value, holder)) then
                local point = holder.record.frame(holder.frame).wpoint
                value.frame = point.weaponact
                value.facing = holder.facing
                value.hit_lag = holder.hit_lag
                local frame = holder.record.frame(holder.frame)
                local x
                if holder.facing == 0 then x = holder.x_int - frame.center_x + point.x
                else x = frame.center_x - point.x + holder.x_int end
                local y = holder.y_int - frame.center_y + point.y
                local own = value.record.frame(value.frame)
                local other = own.wpoint
                if value.facing == 0 then value.x_int = own.center_x - other.x + x
                else value.x_int = other.x - own.center_x + x end
                value.y_int = own.center_y - other.y + y
                value.z_int = holder.z_int
                if point.cover == 0 then
                    value.z_int = value.z_int + 1
                    value.y_int = value.y_int - 1
                else
                    value.z_int = value.z_int - 1
                    value.y_int = value.y_int + 1
                end
                value.z, value.x, value.y = value.z_int, value.x_int, value.y_int
                local holder_state = holder.record.frame(holder.frame).state
                if holder_state == constants.frame_states.falling
                   or holder_state == constants.frame_states.caught then
                    -- Falling or caught holders lose the item.
                    holder.weapon, value.weapon = 0, 0
                    value.frame = random(16)
                    if holder.hit_count == 1 then
                        value.vy = holder.impulse_y
                        value.vx = holder.impulse_x / 3.0
                    else
                        value.vy = holder.vy
                        value.vx = holder.vx / 3.0
                    end
                    if -2.0 < value.y then value.y = -2.0 end
                end
                if point.dvx ~= 0 then
                    local kind = value.record.kind
                    if kind == record_kinds.light_item or kind == record_kinds.baseball
                       or kind == record_kinds.drink then
                        value.thrower = value.holder
                        value.frame = 40
                        value.vx = holder.facing == 0 and point.dvx or -point.dvx
                        value.vy = point.dvy
                        holder.weapon, value.weapon = 0, 0
                        throw_depth(holder, value, point)
                    end
                    if kind == record_kinds.heavy_item then
                        value.frame = random(6)
                        value.vx = holder.facing == 0 and point.dvx or -point.dvx
                        value.vy = point.dvy
                        holder.weapon, value.weapon = 0, 0
                        throw_depth(holder, value, point)
                    end
                end
                if point.kind == constants.wpoint_kinds.drop then
                    value.weapon, holder.weapon = 0, 0
                    value.frame = random(6)
                    value.vx = random(7) - 3
                    value.vy = -random(4)
                    value.vz = (random(5) - 2) / 5.0
                end
            end
        end
    end
end

function weapons.check_holders(state)
    for index = 0, 399 do
        local value = state.items[index]
        if value and value.weapon > 0 then
            local held = value.held_item
            local item = (held >= 0 and held <= 399) and state.items[held] or nil
            if not item or item.holder ~= index then value.weapon = 0 end
        end
    end
end

function weapons.drop_background(state)
    local count = 0
    for index = 0, 399 do
        local value = state.items[index]
        if value and is_weapon(value.record.kind) then count = count + 1 end
    end
    if count >= 4 or random(200) ~= 0 then return end
    local slot = objects.free_slot(state)
    local candidates = {}
    for _, entry in ipairs(catalog.objects().list) do
        local id = entry.id
        if id > constants.record_id_ranges.background_weapon_lower_exclusive
           and id < constants.record_id_ranges.background_weapon_end_exclusive
           and ((id ~= constants.item_ids.milk and id ~= constants.item_ids.beer)
                or (random(2) ~= 0 and state.mode ~= constants.modes.championship
                    and state.mode ~= constants.modes.team_championship
                    and state.mode ~= constants.modes.stage and state.mode ~= constants.modes.battle)) then
            candidates[#candidates + 1] = id
        end
    end
    local roll_a, roll_b = random(30), random(30)
    local span = state.stage_bound or 0
    if span == 0 then span = state.stage.width or 794 end
    local x = roll_b + 30 + roll_a * cdiv(span - 60, 30)
    local near, far = state.stage.zboundary[1] or 0, state.stage.zboundary[2] or 0
    roll_a, roll_b = random(30), random(30)
    local z = roll_b + near + 30 + roll_a * cdiv(far - near - 60, 30)
    if slot == -1 or #candidates == 0 then return end
    local value = objects.place(state, slot, candidates[random(#candidates) + 1])
    if not value then return end
    value.x, value.y, value.z = x, -500.0, z
    for other = 0, 399 do
        local existing = state.items[other]
        if existing then existing.pair_rest[slot] = 0 end
    end
    value.vx, value.vy, value.vz = 0.0, 0.0, 0.0
    if value.record.id == constants.item_ids.milk then value.hp = 200 end
    value.x_int, value.y_int, value.z_int = trunc(value.x), trunc(value.y), trunc(value.z)
    value.owner = 99
end

local item_ids, object_ids = constants.item_ids, constants.object_ids
local debris_count = {
    [item_ids.hoe] = 7, [item_ids.louis_armour_two] = 7,
    [item_ids.stick] = 5, [item_ids.ice_sword] = 5,
    [item_ids.louis_armour] = 5, [object_ids.henry_arrow] = 3,
    [item_ids.stone] = 13, [item_ids.wooden_box] = 15,
    [item_ids.knife] = 3, [item_ids.boomerang] = 3,
    [item_ids.baseball] = 4, [item_ids.milk] = 9, [item_ids.beer] = 9,
}
local heavy_debris = {[item_ids.stone] = true, [item_ids.wooden_box] = true,
    [item_ids.ice_sword] = true}
local light_debris = {[item_ids.stick] = true, [object_ids.henry_arrow] = true,
    [item_ids.hoe] = true, [item_ids.knife] = true,
    [item_ids.baseball] = true, [item_ids.milk] = true, [item_ids.beer] = true,
    [item_ids.boomerang] = true, [item_ids.louis_armour] = true,
    [item_ids.louis_armour_two] = true}

-- Debris frame of record 999 per destroyed record id and piece number.
local function debris_frame(id, piece, debris)
    if id == constants.item_ids.stone then return piece < 5 and random(4) or random(4) + 4 end
    if id == constants.item_ids.stick then return piece < 2 and random(4) + 10 or random(4) + 14 end
    if id == constants.item_ids.ice_sword then return piece < 2 and random(4) + 150 or random(4) + 154 end
    if id == constants.item_ids.hoe then
        if piece < 5 then
            local base = random(2) * 4 + 20
            return base + random(4)
        end
        return random(4) + 30
    end
    if id == constants.item_ids.wooden_box then
        if piece < 2 then return random(4) + 40
        elseif piece < 5 then return random(4) + 44
        elseif piece < 8 then return random(4) + 50 end
        return random(4) + 54
    end
    if id == constants.item_ids.knife then
        if piece < 2 then return random(4) + 54
        elseif piece < 5 then return random(4) + 30 end
        return nil
    end
    if id == constants.item_ids.boomerang then return random(4) + 170 end
    if id == constants.item_ids.baseball then return random(4) + 60 end
    if id == constants.item_ids.milk or id == constants.item_ids.beer then
        if piece < 1 then return random(4) + (id == constants.item_ids.milk and 70 or 160)
        elseif piece < 3 then return random(4) + (id == constants.item_ids.milk and 80 or 164) end
        local frame = random(4) + 74
        debris.vy = -cdiv(random(18), 2) - 4.0
        return frame
    end
    if id == constants.item_ids.louis_armour or id == constants.item_ids.louis_armour_two then return random(4) + 174 end
    return nil
end

function weapons.break_apart(state, index, value)
    if not is_weapon(value.record.kind) or value.drop_counter >= 0 then return false end
    value.drop_counter = 0
    local id = value.record.id
    sounds.item(state, value.x_int, value.record.data.weapon.broken_sound)
    for piece = 0, (debris_count[id] or 0) - 1 do
        local slot = objects.free_slot(state)
        if slot == -1 then break end
        local debris = objects.place(state, slot, constants.object_ids.broken_weapon)
        if not debris then break end
        debris.x_int = random(7) - 3 + value.x_int
        debris.y_int = random(7) - 3 + value.y_int
        debris.z_int = value.z_int
        debris.z, debris.y, debris.x = debris.z_int, debris.y_int, debris.x_int
        if heavy_debris[id] then debris.vy = -cdiv(random(20), 2) - 8.0 end
        if light_debris[id] then debris.vy = -cdiv(random(8), 2) - 6.0 end
        debris.vx = random(11) - 5.0
        local frame = debris_frame(id, piece, debris)
        if frame then debris.frame = frame end
    end
    objects.remove(state, index)
    return true
end
return weapons
