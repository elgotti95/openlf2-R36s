-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local constants = require("base/game/constants")
local cpoint_kinds = constants.cpoint_kinds
local objects = require("base/game/objects")
local battle = require("base/game/battle")
local grab = {}

local function cdiv(a, b)
    local q = a / b
    if q >= 0 then return math.floor(q) end
    return math.ceil(q)
end

local function cpoint(value, frame_id) return value.record.frame(frame_id).cpoint end

-- Negative frame numbers turn the item around (as in the frame advance).
local function enter(value, frame_id)
    value.frame = frame_id
    if value.frame < 0 then
        value.facing = 1 - value.facing
        value.frame = -value.frame
    end
end

function grab.update_holds(state)
    local link
    for index = 0, 399 do
        local holder = state.items[index]
        if holder then
            local hit = cpoint(holder, holder.frame_at_pass)
            if hit.kind == cpoint_kinds.holder and holder.hit_lag >= 0 then
                local target_index = holder.catching
                local target = objects.lookup(state, target_index)
                if target and target.caught_by == index then link = target_index end
                local released = false
                if target and target.caught_by == index and cpoint(target, target.frame_at_pass).kind == cpoint_kinds.caught then
                    if hit.decrease > 0 then holder.catch_timer = holder.catch_timer - hit.decrease end
                    if hit.decrease < 0 then
                        holder.catch_timer = holder.catch_timer + hit.decrease
                        if holder.catch_timer < 0 then
                            holder.frame, target.frame = 0, 0
                            holder.hit_count, target.hit_count = 1, 1
                            target.impulse_x = holder.x_int > target.x_int and -4.0 or 4.0
                            target.impulse_y = -3.0
                            target.frame = 181
                            released = true
                        end
                    end
                    if not released then
                        local keys = holder.keys
                        local function act(frame_id)
                            enter(holder, frame_id)
                            target.frame = cpoint(holder, holder.frame).vaction
                            target.wait_counter = 0
                            holder.wait_counter = 0
                        end
                        if keys.attack and holder.attack_press > 0 and hit.aaction ~= 0
                           and ((not keys.left and not keys.right) or hit.taction == 0) then
                            act(hit.aaction)
                        end
                        if keys.attack and holder.attack_press > 0
                           and (keys.left or keys.right or keys.up or keys.down) and hit.taction ~= 0 then
                            act(hit.taction)
                        end
                        if keys.jump and holder.jump_press > 0 and hit.jaction ~= 0 then act(hit.jaction) end
                    end
                else
                    released = true
                end
                if released then holder.frame = 0 end
                local partner = link and objects.lookup(state, link)
                if hit.throwvx ~= 0 and partner then
                    local change = hit.throwinjury or 0
                    if change >= 1 then
                        partner.fall_damage = change
                    elseif change == -1 then
                        -- Transformation into the partner's record (Rudolf); followers change too.
                        holder.transform = holder.record.id
                        holder.transformed_to = partner.record.id
                        holder.record = partner.record
                        holder.frame = 0
                        for other = 0, 399 do
                            local follower = state.items[other]
                            if follower and follower.follow == index then follower.record = partner.record end
                        end
                    end
                    local frame = holder.record.frame(holder.frame)
                    partner.y_int = holder.y_int - frame.center_y + hit.y
                    partner.y = partner.y_int
                    if holder.facing == 0 then partner.x_int = holder.x_int - frame.center_x + hit.x
                    else partner.x_int = frame.center_x - hit.x + holder.x_int end
                    partner.x = partner.x_int
                    holder.frame = frame.next
                    holder.frame_at_pass = holder.frame
                    holder.wait_counter = 0
                    partner.vx = holder.facing == 0 and hit.throwvx or -hit.throwvx
                    partner.frame = hit.vaction
                    partner.frame_at_pass = partner.frame
                    partner.vy = hit.throwvy
                    local throw_depth = hit.throwvz or 0
                    if holder.keys.up and not holder.keys.down then partner.vz = -throw_depth
                    elseif holder.keys.down and not holder.keys.up then partner.vz = throw_depth end
                end
                -- dircontrol turns the holder with left/right while its wait counter is 2.
                if hit.dircontrol == 1 and holder.wait_counter == 2 then
                    if holder.keys.right and not holder.keys.left then holder.facing = 0 end
                    if not holder.keys.right and holder.keys.left then holder.facing = 1 end
                end
                if hit.dircontrol == -1 and holder.wait_counter == 2 then
                    if holder.keys.right and not holder.keys.left then holder.facing = 1 end
                    if not holder.keys.right and holder.keys.left then holder.facing = 0 end
                end
            elseif cpoint(holder, holder.frame).kind == cpoint_kinds.caught then
                -- A victim whose holder no longer holds it drops (frame 212, vy -3, y at most -2).
                local other_index = holder.caught_by
                local other = objects.lookup(state, other_index)
                local held = other and other.catching == index
                if held then link = other_index end
                if not held or cpoint(other, other.frame).kind ~= cpoint_kinds.holder then
                    holder.frame = 212
                    holder.vy = -3.0
                    if -2.0 < holder.y then holder.y = -2.0 end
                end
            end
        end
    end
end

function grab.place_victims(state)
    for index = 0, 399 do
        local holder = state.items[index]
        if holder then
            local frame = holder.record.frame(holder.frame)
            local hit = frame.cpoint
            local target = objects.lookup(state, holder.catching)
            if hit.kind == cpoint_kinds.holder and frame.state == 9 and target and target.caught_by == index
               and cpoint(target, target.frame).kind == cpoint_kinds.caught then
                if (target.hit_lag == 0 and hit.hurtable == 1) or hit.hurtable == 0 then
                    target.frame = hit.vaction
                end
                if target.frame < 0 then
                    target.facing = 1 - target.facing
                    target.frame = -target.frame
                end
                local damage = hit.injury
                if damage ~= 0 and holder.wait_counter == 0 then
                    local owner = state.items[holder.owner]
                    if damage > 0 then
                        if target.armor > 0 then damage = cdiv(damage * 100, target.armor) end
                        if target.hp > 0 and damage >= target.hp and target.follow == -1 then
                            if owner then owner.kills = owner.kills + 1 end
                            battle.count_kill(state, target)
                        end
                        target.hp = target.hp - damage
                        target.dark_hp = target.dark_hp + cdiv(damage, -3)
                        holder.wait_counter = 1
                        holder.hit_lag = 2
                        target.hit_lag = -3
                        target.hp_spent = target.hp_spent + damage
                        if owner then owner.damage_dealt = owner.damage_dealt + damage end
                        battle.count_damage(state, target, damage)
                    else
                        target.hp = target.hp + hit.injury
                        target.dark_hp = target.dark_hp + cdiv(hit.injury, 3)
                        holder.wait_counter = 1
                    end
                end
                local x, y
                if holder.facing == 0 then x = holder.x_int - frame.center_x + hit.x
                else x = frame.center_x - hit.x + holder.x_int end
                y = holder.y_int - frame.center_y + hit.y
                local other = cpoint(target, hit.vaction)
                local target_frame = target.record.frame(target.frame)
                if target.facing == 0 then target.x_int = target_frame.center_x - other.x + x
                else target.x_int = other.x - target_frame.center_x + x end
                target.y_int = target_frame.center_y - other.y + y
                target.z_int = holder.z_int
                if hit.cover % 10 == 0 then
                    target.z_int = target.z_int - 1
                    target.y_int = target.y_int + 1
                else
                    target.z_int = target.z_int + 1
                    target.y_int = target.y_int - 1
                end
                local direction = cdiv(hit.cover, 10)
                if direction == 1 then target.facing = holder.facing
                elseif direction == 2 then target.facing = 1 - holder.facing end
                target.z, target.x, target.y = target.z_int, target.x_int, target.y_int
            end
        end
    end
end
return grab
