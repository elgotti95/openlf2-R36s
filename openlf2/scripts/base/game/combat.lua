-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local constants = require("base/game/constants")
local cpoint_kinds = constants.cpoint_kinds
local record_kinds = constants.record_kinds
local effects = constants.effects
local attack_kinds = constants.attack_kinds
-- Collision and hit policy follows the original pair pass.
local collision = require("base/game/collision")
local objects = require("base/game/objects")
local sounds = require("base/game/sounds")
local battle = require("base/game/battle")
local merge = require("base/game/merge")
local rumble = require("base/game/rumble")
local combat = {}

local function cdiv(a, b)
    local q = a / b
    if q >= 0 then return math.floor(q) end
    return math.ceil(q)
end
local function trunc(value)
    if value >= 0 then return math.floor(value) end
    return math.ceil(value)
end

local function box(value, frame_id, area)
    local frame = value.record.frame(frame_id)
    local x
    if value.facing == 0 then x = area.x + value.x_int - frame.center_x
    else x = frame.center_x + value.x_int - area.width - area.x end
    return {x = x, y = area.y + value.y_int - frame.center_y, width = area.width, height = area.height}
end

local function may_touch(items, a, b)
    local attacker, defender = items[a], items[b]
    if #attacker.record.frame(attacker.frame).interactions == 0
       or #defender.record.frame(defender.frame).bodies == 0
       or attacker.timer_ec > 0 or (defender.pair_rest[a] or 0) > 0 then
        return false
    end
    local attack = box(attacker, attacker.frame_at_pass, attacker.record.frame(attacker.frame_at_pass).interaction_bounds)
    local body = box(defender, defender.frame_at_pass, defender.record.frame(defender.frame_at_pass).body_bounds)
    return collision.overlaps(body, attack)
end

local breakable = {
    [constants.object_ids.john_ball] = true, [constants.object_ids.deep_ball] = true,
    [constants.object_ids.dennis_ball] = true, [constants.object_ids.woody_ball] = true,
    [constants.object_ids.davis_ball] = true, [constants.object_ids.dennis_chase] = true,
    [constants.object_ids.jack_ball] = true,
}
combat.breakable = breakable
local function is_weapon(kind)
    return kind == record_kinds.light_item or kind == record_kinds.heavy_item
        or kind == record_kinds.baseball or kind == record_kinds.drink
end

local function eligible(state, attacker, defender, itr)
    local attack_kind = itr.kind
    if attack_kind > attack_kinds.freezing_whirlwind or attack_kind == attack_kinds.ignored_12 or attack_kind == attack_kinds.ignored_13 then return false end
    if breakable[attacker.record.id] and defender.record.id == constants.object_ids.freeze_ball and attack_kind ~= attack_kinds.reflect_ball then return false end
    local defender_kind = defender.record.kind
    if attack_kind == attack_kinds.catch and defender_kind ~= record_kinds.character then return false end
    if attack_kind == attack_kinds.heal and defender_kind ~= record_kinds.character then return false end
    local function recent_state(value) return value.record.frame(value.state_frame).state end
    if attack_kind == attack_kinds.plain then
        local effect = itr.effect
        if effect == effects.skip_characters and defender_kind == record_kinds.character then return false end
        if effect == effects.burn_alt and (defender_kind ~= record_kinds.character or recent_state(defender) == constants.frame_states.burning or recent_state(defender) == constants.frame_states.burning_run) then
            return false
        end
        if effect == effects.burn_state_guard and (recent_state(defender) == constants.frame_states.burning or recent_state(defender) == constants.frame_states.burning_run) then return false end
        if effect == effects.rebound and defender.frame >= 200 and defender.frame <= 202 then return false end
        if effect == effects.burn and recent_state(attacker) == constants.frame_states.burning_run and recent_state(defender) == constants.frame_states.burning then return false end
    end
    if defender.blink ~= 0 and attack_kind ~= attack_kinds.heal and attack_kind ~= attack_kinds.obstacle then return false end
    -- Frozen or caught victims can be hit by their own team; so can a ball met head-on.
    local defender_state = defender.record.frame(defender.frame).state
    local team_rule = attack_kind <= attack_kinds.catch or attack_kind == attack_kinds.super_window
        or (attack_kind == attack_kinds.reflect_ball and defender_kind == record_kinds.character)
        or attack_kind == attack_kinds.whirlwind or attack_kind == attack_kinds.conditional_whirlwind
        or attack_kind == attack_kinds.pulling_whirlwind or attack_kind == attack_kinds.freezing_whirlwind
    if team_rule and defender_state ~= constants.frame_states.frozen and defender_state ~= constants.frame_states.caught
       and (defender.record.id ~= constants.object_ids.freeze_column
            or (attacker.record.id == constants.object_ids.freeze_column and (defender.frame % 10 ~= 5 or attacker.frame % 10 ~= 0)))
       and attacker.team == defender.team and attacker.team ~= constants.teams.independent
       and attack_kind ~= attack_kinds.heal
       and (attacker.record.frame(attacker.frame).state ~= constants.frame_states.burning or itr.effect == effects.burn_state_guard or itr.effect == effects.burn_push)
       and (attacker.record.kind ~= record_kinds.character or defender_kind ~= record_kinds.ball or attacker.facing == defender.facing)
       and not is_weapon(defender_kind) then
        return false
    end
    if attack_kind == attack_kinds.held_item then
        -- A held weapon spares its holder's team (record 212 has an exception).
        local holder = state.items[attacker.holder]
        local team = holder and holder.team or 0
        if team == defender.team and team ~= 0 and defender_state ~= constants.frame_states.frozen and not is_weapon(defender_kind) then
            if defender.record.id ~= constants.object_ids.freeze_column then return false end
            if attacker.record.id == constants.object_ids.freeze_column and (defender.frame % 10 ~= 5 or attacker.frame % 10 ~= 0) then
                return false
            end
        end
    end
    return true
end

local function record_targets(state, a, b)
    local attacker, defender = state.items[a], state.items[b]
    local a_frame = attacker.record.frame(attacker.frame_at_pass)
    local b_frame = defender.record.frame(defender.frame_at_pass)
    for itr_index, itr in ipairs(a_frame.interactions) do
        if eligible(state, attacker, defender, itr) then
            local window = itr.zwidth ~= 0 and itr.zwidth or 15
            local depth = attacker.z_int - defender.z_int
            local attack_box = box(attacker, attacker.frame_at_pass, itr)
            for _, body in ipairs(b_frame.bodies) do
                local body_box = box(defender, defender.frame_at_pass, body)
                if collision.overlaps(body_box, attack_box) and depth < window and depth > -window then
                    -- Weak attacks do not touch a falling victim.
                    local skip = defender.record.frame(defender.frame).state == constants.frame_states.falling and itr.fall < 41
                        and itr.kind ~= attack_kinds.whirlwind and itr.kind ~= attack_kinds.conditional_whirlwind
                    if state.mode == constants.modes.stage and body.kind > 999 then
                        local record = attacker.record
                        local protected = (record.kind == record_kinds.character or record.id == constants.object_ids.henry_arrow or record.id == constants.object_ids.rudolf_weapon)
                            and attacker.team ~= constants.teams.enemies
                        if attacker.weapon < 0 then
                            local owner = state.items[attacker.holder]
                            if owner and owner.record.kind == record_kinds.character and owner.team ~= constants.teams.enemies then protected = true end
                        end
                        if not protected then skip = true end
                    end
                    -- Lying light weapons are only listed for pickups.
                    local lying_weapon = b_frame.state == constants.frame_states.resting_light_item
                        and (attacker.record.kind < record_kinds.light_item or attacker.weapon < 0)
                    if itr.vrest ~= 0 or itr.kind == attack_kinds.catch_nearest or itr.kind == attack_kinds.pick_up or itr.kind == attack_kinds.rolling_pickup or lying_weapon or skip then
                        if attacker.hit_list_count < 20 and not skip then
                            local result = constants.hit_list_results.not_listed
                            if lying_weapon and itr.kind ~= attack_kinds.pick_up and itr.kind ~= attack_kinds.rolling_pickup and itr.kind ~= attack_kinds.whirlwind then result = constants.hit_list_results.skip end
                            local defender_state = defender.record.frame(defender.frame).state
                            local fresh_attack = attacker.keys.attack and not attacker.previous_keys.attack
                            if itr.kind == attack_kinds.catch_nearest then
                                -- The nearest catcher per victim wins; ties broken by a coin flip.
                                local distance = math.abs(attacker.x_int - defender.x_int)
                                if distance < defender.nearest_catcher
                                   or (distance == defender.nearest_catcher and engine.random(2) == 0) then
                                    defender.nearest_catcher = distance
                                else
                                    result = constants.hit_list_results.skip
                                end
                                -- Only a dizzy victim, walked toward with left/right held.
                                if ((attacker.keys.right and attacker.x_int < defender.x_int)
                                    or (attacker.keys.left and defender.x_int <= attacker.x_int))
                                   and defender.record.frame(defender.frame).state == constants.frame_states.dizzy and result ~= constants.hit_list_results.skip then
                                    result = constants.hit_list_results.list
                                end
                            elseif itr.kind ~= attack_kinds.pick_up and itr.kind ~= attack_kinds.rolling_pickup then
                                if result ~= constants.hit_list_results.skip then result = constants.hit_list_results.list end
                            end
                            -- Pickups need a fresh attack press on a lying weapon; without the
                            -- attack key held, picking up lists nothing.
                            if itr.kind == attack_kinds.pick_up and not (attacker.weapon == 0 and not attacker.keys.attack) then
                                if attacker.weapon == 0 and fresh_attack and defender_state == constants.frame_states.resting_light_item and result ~= constants.hit_list_results.skip then
                                    result = constants.hit_list_results.list
                                end
                                if fresh_attack and defender_state == constants.frame_states.resting_heavy_item and result ~= constants.hit_list_results.skip then result = constants.hit_list_results.list end
                            end
                            if itr.kind == attack_kinds.rolling_pickup and fresh_attack and defender_state == constants.frame_states.resting_light_item and result ~= constants.hit_list_results.skip then
                                result = constants.hit_list_results.list
                            end
                            if result == constants.hit_list_results.list then
                                attacker.hit_list_count = attacker.hit_list_count + 1
                                attacker.hit_list[attacker.hit_list_count] = b
                                attacker.hit_list_itr[attacker.hit_list_count] = itr_index
                            end
                        end
                    else
                        local distance = math.abs(attacker.x_int - defender.x_int)
                        if attacker.weapon < 0 then
                            local holder = objects.lookup(state, attacker.holder)
                            if b == attacker.holder then distance = 2000
                            elseif holder then distance = math.abs(holder.x_int - defender.x_int) end
                        end
                        if distance < attacker.nearest or (distance == attacker.nearest and engine.random(2) == 0) then
                            attacker.nearest = distance
                            attacker.hit_list[1] = b
                            attacker.hit_list_itr[1] = itr_index
                            attacker.hit_list_count = 1
                        end
                    end
                end
            end
        end
    end
end

function combat.detect(state)
    local items = state.items
    for index = 0, 399 do
        local value = items[index]
        if value then
            value.frame_at_pass = value.frame
            local holder = value.record.frame(value.frame).state == constants.frame_states.held_item and objects.lookup(state, value.holder)
            if #value.record.frame(value.frame).interactions == 0
               or (holder and holder.record.frame(holder.frame).wpoint.attacking == 0) then
                value.timer_ec = 0
            end
        end
    end
    for a = 0, 399 do
        if items[a] then
            for b = a + 1, 399 do
                if items[b] then
                    if (items[a].pair_rest[b] or 0) > 0 then items[a].pair_rest[b] = items[a].pair_rest[b] - 1 end
                    if (items[b].pair_rest[a] or 0) > 0 then items[b].pair_rest[a] = items[b].pair_rest[a] - 1 end
                    if may_touch(items, a, b) then record_targets(state, a, b) end
                    if may_touch(items, b, a) then record_targets(state, b, a) end
                end
            end
        end
    end
    merge.update(state)
end

-- Characters that absorb hits while their defense meter is low.
local function armored(attacker, victim, itr)
    local effect = itr.effect
    local elemental = math.floor(effect / 10) == 2 or math.floor(effect / 10) == 3 or effect == effects.burn or effect == effects.freeze
    local attacker_id = attacker.record.id
    local id = victim.record.id
    if id == constants.fighter_ids.knight and victim.timer_b8 < 16 then
        return not (elemental or attacker_id == constants.object_ids.john_biscuit
            or attacker_id == constants.object_ids.henry_arrow_two)
    elseif id == constants.fighter_ids.louis and victim.timer_b8 < 2 then
        local victim_state = victim.record.frame(victim.frame).state
        return not elemental and attacker_id ~= constants.object_ids.john_biscuit
            and attacker_id ~= constants.object_ids.henry_arrow_two
            and (victim.frame < 20 or victim_state == constants.frame_states.dashing or victim_state == constants.frame_states.jumping or victim_state == constants.frame_states.defending)
    elseif id == constants.fighter_ids.julian and victim.timer_b8 < 16
        and attacker_id ~= constants.object_ids.john_biscuit
        and attacker_id ~= constants.object_ids.henry_arrow_two then
        return true
    end
    return false
end

local function push(value, amount) value.impulse_x = value.impulse_x + amount end

local function rest_byte(value)
    value = value % 256
    if value > 127 then return value - 256 end
    return value
end

local function record_spark(state, p, v, attacker, victim, itr, spark_kind)
    -- The attacker owns the spark only while it is still active (a henry_arrow can vanish).
    local owner_index = v
    if victim.z_int <= attacker.z_int and state.items[p] then
        owner_index = p
        if attacker.z_int <= victim.z_int then
            owner_index = v
            if v < p then owner_index = p end
        end
    end
    local owner = state.items[owner_index]
    if not owner or #owner.sparks >= 10 then return end
    local frame = attacker.record.frame(attacker.frame)
    local x
    if attacker.facing == 0 then
        x = attacker.x_int - frame.center_x + itr.width + itr.x
        if x > victim.x_int then x = victim.x_int end
    else
        x = frame.center_x - itr.width - itr.x + attacker.x_int
        if x < victim.x_int then x = victim.x_int end
    end
    local row = frame.center_y
    local spark = cdiv(itr.height, 2) + attacker.y_int + itr.y - row
    local lower = victim.y_int - row
    if spark < lower then spark = cdiv(spark + lower, 2)
    elseif victim.y_int < spark then spark = cdiv(spark + victim.y_int, 2) end
    local y = engine.crt_random() % 9 + attacker.z_int - 4 + spark
    x = x + engine.crt_random() % 9 - 4
    owner.sparks[#owner.sparks + 1] = {timer = spark_kind * 20 + (itr.fall <= 60 and 10 or 0), x = x, y = y}
end

local function ball_struck(state, p, attacker, victim, itr)
    local held = attacker.weapon < 0
    local holder = held and objects.lookup(state, attacker.holder) or nil
    local source = holder or attacker
    local function freeze_record()
        local replacement = objects.record(state, constants.object_ids.freeze_ball)
        if replacement then
            victim.record = replacement
            victim.previous_frame, victim.state_frame = victim.frame, victim.frame
        end
    end
    local victim_state = victim.record.frame(victim.frame).state
    local attacker_state = attacker.record.frame(attacker.frame).state
    if victim_state ~= 3005 and (victim_state ~= constants.frame_states.flying_missile or attacker_state == 3005) then
        victim.team = source.team
        victim.owner = source.owner
        victim.hit_this_frame = true
        victim.wait_counter = 0
        victim.impulse_y, victim.impulse_x, victim.impulse_z = 0.0, 0.0, 0.0
        if attacker.record.id == constants.object_ids.freeze_ball and breakable[victim.record.id] then
            victim.team, victim.owner = attacker.team, attacker.owner
            victim.record = attacker.record
            victim.frame, victim.previous_frame, victim.state_frame = 40, 40, 40
        elseif (attacker.record.kind == record_kinds.character or held) and itr.effect ~= effects.burn and itr.effect ~= effects.burn_alt then
            victim.frame = 30
            if attacker.record.id == constants.fighter_ids.freeze and breakable[victim.record.id] then freeze_record() end
        else
            victim.frame = 20
        end
        if held then
            victim.walk_phase = attacker.holder
            if attacker.record.id == constants.item_ids.ice_sword and breakable[victim.record.id] then freeze_record() end
        else
            victim.walk_phase = p
        end
    end
    victim_state = victim.record.frame(victim.frame).state
    attacker_state = attacker.record.frame(attacker.frame).state
    if (victim_state == 3005 and attacker_state == 3005) or (victim_state == constants.frame_states.flying_missile and attacker_state == constants.frame_states.flying_missile) then
        for _, value in ipairs({victim, attacker}) do
            value.frame = 20
            value.wait_counter = 0
            value.impulse_y, value.impulse_x, value.impulse_z = 0.0, 0.0, 0.0
        end
    end
    local lagged = holder or attacker
    if lagged.hit_lag > 0 then lagged.hit_lag = -lagged.hit_lag end
end

local function plain_hit(state, p, v, attacker, victim, itr)
    local victim_frame = victim.record.frame(victim.frame_at_pass)
    local victim_kind = victim.record.kind
    local spark_kind = 0
    victim.timer_b8 = 45
    if victim.record.id == constants.record_ids.criminal then
        local body = victim.record.frame(victim.frame).bodies[1]
        if body and body.kind > 1000 then
            victim.team = constants.teams.player_one
            victim.frame = body.kind - 1000
            attacker.hit_lag = 3
            victim.hit_lag = -3
        end
        return "stop"
    end
    if victim_kind ~= record_kinds.drink then
        local damage = itr.injury
        if victim.armor > 0 then damage = cdiv(damage * 100, victim.armor) end
        local counted = victim_kind == record_kinds.character and victim.follow == -1
        if victim.hp > 0 and damage >= victim.hp and counted then
            local owner = state.items[attacker.owner]
            if owner then owner.kills = owner.kills + 1 end
            battle.count_kill(state, victim)
        end
        victim.hp = victim.hp - damage
        victim.dark_hp = victim.dark_hp + cdiv(damage, -3)
        victim.hp_spent = victim.hp_spent + damage
        battle.count_damage(state, victim, damage)
        if counted then
            local owner = state.items[attacker.owner]
            if owner then owner.damage_dealt = owner.damage_dealt + damage end
        end
    end
    if victim.hp < 1 or itr.effect == effects.skip_characters then victim.timer_b0 = 80 end
    if is_weapon(victim_kind) then
        victim.drop_counter = victim.drop_counter - itr.injury
        if itr.bdefend == 100 then victim.drop_counter = -1 end
    end
    if victim_kind ~= record_kinds.heavy_item or itr.fall > 40 then victim.hit_count = victim.hit_count + 1 end
    victim.timer_b0 = victim.timer_b0 + (itr.fall == 0 and 20 or itr.fall)
    if victim.record.frame(victim.state_frame).state == constants.frame_states.frozen or victim_frame.state == constants.frame_states.falling or is_weapon(victim_kind) then
        victim.timer_b0 = 80
    end
    local b0 = victim.timer_b0
    local same_facing = victim.facing == attacker.facing and 1 or 0
    if b0 > 60 and victim_kind ~= record_kinds.ball then victim.timer_b0 = 80
    elseif victim_kind == record_kinds.ball then
        -- Balls keep their frame; the accumulated value only matters at 80.
    elseif b0 > 40 then
        victim.frame = 226
        victim.timer_b0 = victim.y_int < 0 and 80 or 60
    elseif b0 > 20 then
        victim.frame = same_facing * 2 + 222
        victim.timer_b0 = victim.y_int < 0 and 80 or 40
    elseif b0 > 0 then
        victim.frame = 220
        victim.timer_b0 = 20
        if victim.y_int < 0 then victim.frame = same_facing * 2 + 222 end
    end
    -- A ball plays its broken sound; characters play hit/knockdown/sharper sound effects;
    -- other victims their own hit sound.
    if attacker.record.kind == record_kinds.ball then sounds.item(state, attacker.x_int, attacker.record.data.weapon.broken_sound) end
    if victim_kind == record_kinds.character then
        if itr.effect == effects.plain_hit then sounds.effect(state, victim.x_int, victim.timer_b0 == 80 and 2 or 0) end
        if itr.effect == effects.sharp_hit then
            spark_kind = 1
            if victim.timer_b0 == 80 then
                sounds.effect(state, victim.x_int, 12)
                sounds.effect(state, victim.x_int, 2)
            else
                sounds.effect(state, victim.x_int, 11)
                sounds.effect(state, victim.x_int, 0)
            end
        end
    elseif victim_kind > 0 then
        sounds.item(state, victim.x_int, victim.record.data.weapon.hit_sound)
    end
    local attacker_state = attacker.record.frame(attacker.frame).state
    if victim.timer_b0 ~= 80 or victim.vx >= 5.0 or victim.vx <= -5.0 or itr.dvx ~= 0 then
        if attacker_state == constants.frame_states.flying_heavy_item then
            push(victim, attacker.x_int < victim.x_int and itr.dvx or -itr.dvx)
        elseif victim_kind == record_kinds.baseball or victim_kind == record_kinds.drink then
            -- Light weapons in flight.
            local limit = math.abs(victim.vx * 0.55)
            if limit < itr.dvx or (attacker.facing == 0 and victim.impulse_x > 0.0)
               or (attacker.facing == 1 and victim.impulse_x < 0.0) then
                if attacker.facing == 0 then push(victim, itr.dvx) end
                if attacker.facing == 1 then push(victim, -itr.dvx) end
            elseif (attacker.facing == 1 and victim.vx > 0.0) or (attacker.facing == 0 and victim.vx < 0.0) then
                victim.impulse_x = -(victim.vx * 0.55)
            end
            if attacker.record.id == constants.item_ids.stick and attacker.weapon < 0 then
                -- A swung club bats flying bottles away at least 10 px/frame.
                victim.impulse_x = victim.impulse_x * 2.5
                sounds.effect(state, victim.x_int, 13)
                if 0.0 < victim.impulse_x and victim.impulse_x < 10.0 then victim.impulse_x = 10.0 end
                if victim.impulse_x < 0.0 and victim.impulse_x > -10.0 then victim.impulse_x = -10.0 end
            end
        elseif itr.effect == effects.burn_push or itr.effect == effects.burn_sound then
            push(victim, victim.x_int <= attacker.x_int and itr.dvx or -itr.dvx)
        else
            if attacker.facing == 0 then push(victim, itr.dvx) end
            if attacker.facing == 1 then push(victim, -itr.dvx) end
        end
    elseif attacker_state == constants.frame_states.flying_heavy_item then
        push(victim, 5.0)
    else
        push(victim, (attacker.facing * -2 + 1) * 5.0)
    end
    if attacker_state == constants.frame_states.flying_ball
       and (victim_kind == record_kinds.character or attacker.record.id ~= constants.object_ids.freeze_ball
            or not (breakable[victim.record.id] or (victim.record.id == constants.object_ids.freeze_ball and victim.frame == 40))) then
        attacker.frame = 10
        attacker.wait_counter = 0
        attacker.vx = 0.0
        attacker.vz = attacker.record.frame(10).dvy
    end
    if victim.timer_b0 == 80 then
        local light = (victim_kind ~= record_kinds.heavy_item and victim_kind ~= record_kinds.ball) or itr.fall > 40
        if itr.dvy == 0 then
            if light then victim.impulse_y = victim.impulse_y - 7.0 end
        else
            if light then victim.impulse_y = itr.dvy + victim.impulse_y end
            if trunc(victim.y_int + victim.impulse_y) > 0 then victim.impulse_y = 12.0 end
        end
        if (victim.facing == 0 and victim.impulse_x <= 0.0) or (victim.facing == 1 and victim.impulse_x >= 0.0) then
            victim.frame = 180
        else
            victim.frame = 186
        end
        -- A knocked-down holder's item gets pair rests against both.
        local held = objects.lookup(state, victim.held_item)
        if victim.weapon > 0 and held and held.holder == v then
            attacker.pair_rest[victim.held_item] = 45
            victim.pair_rest[victim.held_item] = 30
        end
    end
    if attacker.hit_lag >= 0 then attacker.hit_lag = 3 end
    victim.hit_lag = -3
    if itr.arest < 4 and itr.vrest == 0 then attacker.timer_ec = 4 else attacker.timer_ec = itr.arest end
    if itr.vrest > 0 then victim.pair_rest[p] = rest_byte(itr.vrest) end
    -- A caught victim hit through a hurtable catch plays its front/back hurt frame.
    local catch_point = victim.record.frame(victim.frame_at_pass).cpoint
    local catcher = objects.lookup(state, victim.caught_by)
    if catch_point.kind == cpoint_kinds.caught and catcher and catcher.catching == v and victim.timer_b0 ~= 80
       and catch_point.injury ~= 0 then
        victim.frame = victim.facing ~= attacker.facing and catch_point.injury or catch_point.cover
    end
    if victim.timer_b0 == 80 then victim.timer_b0 = 0 end
    local holder = attacker.weapon < 0 and objects.lookup(state, attacker.holder)
    if holder then holder.hit_lag = attacker.hit_lag end
    if attacker.record.frame(attacker.frame).state == constants.frame_states.thrown_item then
        -- A thrown weapon bounces off.
        attacker.frame = engine.random(16)
        attacker.vx = -(victim.impulse_x * 0.5)
        attacker.vy = -4.0
        if attacker.record.kind == record_kinds.baseball and victim_kind == record_kinds.baseball then attacker.impulse_x = -victim.impulse_x end
    end
    if victim_kind == record_kinds.light_item then
        victim.hit_this_frame = true
        victim.frame = engine.random(16)
        victim.team = attacker.team
    end
    if victim_kind == record_kinds.baseball or victim_kind == record_kinds.drink then
        attacker.pair_rest[v] = 30
        victim.hit_this_frame = true
        victim.frame = engine.random(16)
        victim.team = attacker.team
    end
    if victim_kind == record_kinds.heavy_item then
        victim.hit_this_frame = true
        local rest = (itr.fall <= 40 and itr.effect ~= effects.skip_characters) and 3 or 19
        local thrower = attacker.weapon == -2 and objects.lookup(state, attacker.holder)
        if thrower then thrower.pair_rest[v] = rest
        elseif attacker.record.kind ~= record_kinds.heavy_item then attacker.pair_rest[v] = rest end
        victim.facing = attacker.facing
        if itr.fall <= 40 and victim.y_int > -1 and itr.effect ~= effects.skip_characters then victim.frame = 20
        else victim.frame = engine.random(6) end
        victim.team = attacker.team
    end
    if attacker.record.id == constants.object_ids.henry_arrow and victim_kind == record_kinds.character then objects.remove(state, p) end
    if attacker.record.id == constants.object_ids.john_biscuit and victim_kind == record_kinds.character then attacker.hp = 0 end
    if victim_kind == record_kinds.ball then ball_struck(state, p, attacker, victim, itr) end
    if (itr.effect == effects.freeze or itr.effect == effects.rebound) and victim_kind == record_kinds.character
       and victim.record.frame(victim.state_frame).state ~= constants.frame_states.frozen then
        victim.frame = 200
        victim.wait_counter = 0
        sounds.effect(state, victim.x_int, 14)
    end
    if (itr.effect == effects.burn or itr.effect == effects.burn_state_guard or itr.effect == effects.burn_push
        or (itr.effect == effects.burn_alt and victim.record.frame(victim.state_frame).state ~= constants.frame_states.burning)) and victim_kind == record_kinds.character then
        victim.frame = 203
        victim.wait_counter = 0
        sounds.effect(state, victim.x_int, 16)
        victim.facing = victim.impulse_x < 0.0 and 0 or 1
    end
    if itr.effect == effects.burn_sound then sounds.effect(state, victim.x_int, 16) end
    return spark_kind
end

local function defended_hit(state, p, attacker, victim, itr)
    local victim_frame = victim.record.frame(victim.frame_at_pass)
    if attacker.record.kind == record_kinds.ball then
        sounds.item(state, attacker.x_int, attacker.record.data.weapon.broken_sound)
    elseif victim.record.id == constants.fighter_ids.knight or victim.record.id == constants.fighter_ids.louis then
        sounds.effect(state, victim.x_int, 17)
    else
        sounds.effect(state, victim.x_int, 1)
    end
    local base = itr.injury
    if victim.armor > 0 then base = cdiv(base * 100, victim.armor) end
    local damage = cdiv(base, 10)
    if victim.hp > 0 and damage >= victim.hp and victim.follow == -1 then
        local owner = state.items[attacker.owner]
        if owner then owner.kills = owner.kills + 1 end
        battle.count_kill(state, victim)
    end
    victim.hp = victim.hp - damage
    victim.dark_hp = victim.dark_hp + cdiv(damage, -3)
    victim.hp_spent = victim.hp_spent + damage
    battle.count_damage(state, victim, damage)
    if victim.follow == -1 then
        local owner = state.items[attacker.owner]
        if owner then owner.damage_dealt = owner.damage_dealt + damage end
    end
    if victim.hp <= 0 then victim.timer_b0 = 80 end
    victim.wait_counter = 0
    victim.timer_b8 = victim.timer_b8 + itr.bdefend
    victim.hit_count = victim.hit_count + 1
    attacker.hit_lag = 3
    victim.hit_lag = -5
    local attacker_state = attacker.record.frame(attacker.frame).state
    if victim.y_int == 0 then
        if victim.timer_b8 < 31 or victim_frame.state ~= constants.frame_states.defending then
            if victim.frame == 110 then victim.frame = 111 end
        else
            victim.frame = 112
        end
        if victim.timer_b0 ~= 80 or victim.vx >= 3.0 or victim.vx <= -3.0 or itr.dvx ~= 0 then
            if attacker_state == constants.frame_states.flying_heavy_item then
                push(victim, attacker.x_int < victim.x_int and itr.dvx or -itr.dvx)
            elseif itr.effect == effects.burn_push or itr.effect == effects.burn_sound then
                push(victim, victim.x_int <= attacker.x_int and itr.dvx or -itr.dvx)
            else
                if attacker.facing == 0 then push(victim, cdiv(itr.dvx, 2)) end
                if attacker.facing == 1 then push(victim, -cdiv(itr.dvx, 2)) end
            end
        elseif attacker_state == constants.frame_states.flying_heavy_item then
            push(victim, attacker.x_int < victim.x_int and 6.0 or -6.0)
        else
            push(victim, (attacker.facing * -2 + 1) * 3.0)
        end
    else
        if victim.timer_b0 ~= 80 or victim.vx >= 6.0 or victim.vx <= -6.0 or itr.dvx > 5 then
            if itr.effect ~= effects.burn_push and itr.effect ~= effects.burn_sound then
                if attacker.facing == 0 then push(victim, itr.dvx) end
                if attacker.facing == 1 then push(victim, -itr.dvx) end
            else
                push(victim, victim.x_int <= attacker.x_int and itr.dvx or -itr.dvx)
            end
        else
            push(victim, (attacker.facing * -2 + 1) * 6.0)
        end
    end
    if itr.arest < 4 and itr.vrest == 0 then attacker.timer_ec = 4
    else attacker.timer_ec = math.min(itr.arest, 12) end
    if itr.vrest > 0 then victim.pair_rest[p] = itr.vrest < 5 and 4 or math.min(rest_byte(itr.vrest), 12) end
    local holder = attacker.weapon < 0 and objects.lookup(state, attacker.holder)
    if holder then holder.hit_lag = attacker.hit_lag end
    if attacker.record.frame(attacker.frame).state == constants.frame_states.thrown_item then
        attacker.frame = engine.random(16)
        attacker.vx = -(victim.impulse_x * 0.5)
        attacker.vy = -4.0
        attacker.vz = attacker.vz / -1.5
    end
    if attacker.record.frame(attacker.frame).state == constants.frame_states.flying_heavy_item then
        -- A flying heavy weapon slows down against a defending fighter.
        if (victim.x_int < attacker.x_int and attacker.vx < 0.0) or (attacker.x_int < victim.x_int and 0.0 < attacker.vx) then
            attacker.vx = attacker.vx / 2.5
            attacker.vz = attacker.vz / 2.5
        end
    end
    if attacker.record.frame(attacker.frame).state == constants.frame_states.flying_ball then
        attacker.frame = 10
        attacker.wait_counter = 0
        attacker.vx = 0.0
    end
end

local function copy_itr(itr)
    local copy = {}
    for key, value in pairs(itr) do copy[key] = value end
    return copy
end

-- Itr kind 5 (held weapon): the holder's wpoint `attacking` selects a strength-list entry that
-- replaces everything but the box. No entry, or hitting the holder, does nothing.
local function weapon_strike(state, p, attacker, v, itr)
    local holder = objects.lookup(state, attacker.holder)
    if not holder or holder.held_item ~= p then return itr end
    local entry = holder.record.frame(holder.frame_at_pass).wpoint.attacking
    if entry <= 0 or attacker.holder == v then return itr end
    local strength = attacker.record.data.strengths[entry] or {}
    local hit = {kind = attack_kinds.plain, x = itr.x, y = itr.y, width = itr.width, height = itr.height}
    for _, field in ipairs({"dvx", "dvy", "fall", "arest", "vrest", "respond", "effect", "bdefend",
                            "injury", "zwidth"}) do
        hit[field] = strength[field] or 0
    end
    hit.catching_actions = strength.catching_actions or {0, 0}
    hit.caught_actions = strength.caught_actions or {0, 0}
    return hit
end

-- Links a picked-up item to its holder; counts a picking.
local function link_weapon(attacker, victim, v, p, weapon)
    attacker.weapon = weapon
    victim.weapon = -weapon
    victim.team = attacker.team
    attacker.held_item = v
    victim.holder = p
    victim.owner = p
    attacker.pickings = attacker.pickings + 1
end
local function light_code(victim)
    local id = victim.record.id
    return (id == constants.item_ids.knife or id == constants.item_ids.boomerang)
        and constants.weapon_holder_codes.knife_or_boomerang or constants.record_kinds.light_item
end

-- Itr kind 2: picking up enters frame 115 (light, drinks) or 116 (heavy).
local function pick_up(attacker, victim, v, p)
    local kind = victim.record.kind
    if kind == record_kinds.light_item then
        attacker.frame = 115
        link_weapon(attacker, victim, v, p, 1)
        attacker.weapon = light_code(victim)
        victim.weapon = -1
    end
    if kind == record_kinds.baseball then
        attacker.frame = 115
        link_weapon(attacker, victim, v, p, 4)
    end
    if kind == record_kinds.drink then
        attacker.frame = 115
        local weapon = 6
        if victim.hp <= 0 then
            weapon = 4
            victim.drop_counter = 0
        end
        link_weapon(attacker, victim, v, p, weapon)
    end
    if kind == record_kinds.heavy_item then
        attacker.frame = 116
        link_weapon(attacker, victim, v, p, 2)
    end
    attacker.wait_counter = 0
end

-- Itr kind 7 (e.g. rolling over a weapon): picks it up without changing frames.
local function grab_weapon(attacker, victim, v, p)
    link_weapon(attacker, victim, v, p, 1)
    attacker.weapon = light_code(victim)
    victim.weapon = -1
    local kind = victim.record.kind
    if kind == record_kinds.baseball then
        attacker.weapon, victim.weapon = 4, -4
    end
    if kind == record_kinds.drink then
        if victim.hp <= 0 then
            attacker.weapon = 4
            victim.drop_counter = 0
        else
            attacker.weapon = 6
        end
        victim.weapon = -attacker.weapon
    end
end

-- Whirlwind lift: caps height at 2px, then accelerates upward toward -6 vy.
local function lift(victim, step)
    if victim.y_int >= -2 then
        victim.y_int = -2
        victim.vy = -6.0
    end
    if victim.vy > -6.0 then
        victim.vy = victim.vy - step
        victim.impulse_y = victim.vy
    end
end

-- Itr kind 9 vs a ball: state 3005 balls vanish; others turn to the attacker's team (frame 30).
local function reflect_ball(state, p, attacker, victim)
    if victim.record.kind == record_kinds.ball then
        sounds.item(state, victim.x_int, victim.record.data.weapon.broken_sound)
        attacker.hit_lag = -3
        victim.hit_this_frame = true
        if victim.record.frame(victim.frame).state == 3005 then
            victim.frame = 40
        else
            victim.team = attacker.team
            victim.owner = attacker.owner
            victim.frame = 30
            victim.wait_counter = 0
            victim.impulse_y, victim.vy, victim.impulse_x = 0.0, 0.0, 0.0
            victim.vx, victim.impulse_z, victim.vz = 0.0, 0.0, 0.0
            victim.walk_phase = p
        end
    elseif victim.record.kind == record_kinds.character then
        attacker.hp = 0
    end
end

-- Itr kinds 10/11 (whirlwinds): characters take fall_damage -20 (11 damage credited when the
-- 12-frame counter is 0), slow by 1.07, and lift in frame 182; weapons just lift.
local function whirl(state, p, attacker, victim)
    local kind = victim.record.kind
    if kind == record_kinds.character then
        victim.fall_damage = -20
        if victim.follow == -1 and state.counter_12 == 0 then
            local owner = state.items[attacker.owner]
            if owner then owner.damage_dealt = owner.damage_dealt + 11 end
        end
        battle.count_damage(state, victim, 11)
        victim.impulse_x = victim.vx / 1.07
        victim.vx = victim.impulse_x
        victim.impulse_z = victim.vz / 1.07
        victim.vz = victim.impulse_z
        victim.frame = 182
        lift(victim, 3.0)
    elseif (kind == record_kinds.light_item or kind == record_kinds.baseball
            or kind == record_kinds.drink) and victim.record.id ~= constants.object_ids.henry_arrow and victim.record.id ~= constants.object_ids.rudolf_weapon then
        if victim.record.frame(victim.frame).state ~= constants.frame_states.airborne_item then victim.frame = 0 end
        victim.impulse_x = victim.vx / 1.07
        victim.vx = victim.impulse_x
        victim.impulse_z = victim.vz / 1.07
        victim.vz = victim.impulse_z
        lift(victim, 3.0)
    elseif kind == record_kinds.heavy_item then
        if victim.record.frame(victim.frame).state ~= constants.frame_states.flying_heavy_item then victim.frame = 0 end
        victim.impulse_x = victim.vx / 1.07
        victim.vx = victim.impulse_x
        victim.impulse_z = victim.vz / 1.07
        victim.vz = victim.impulse_z
        lift(victim, 2.3)
    end
end

-- Itr kind 14 (obstacles): blocks the victim's movement toward the attacker for this frame.
local function obstruct(attacker, victim)
    if attacker.x_int > victim.x_int + 5 and not (victim.vx <= 0.0 and victim.impulse_x <= 0.0) then
        victim.blocked_right = true
    elseif attacker.x_int < victim.x_int - 5 and (victim.vx < 0.0 or victim.impulse_x < 0.0) then
        victim.blocked_left = true
    end
    if attacker.z_int > victim.z_int + 2 and not (victim.vz <= 0.0 and victim.impulse_z <= 0.0) then
        victim.blocked_down = true
    elseif attacker.z_int < victim.z_int - 2 and (victim.vz < 0.0 or victim.impulse_z < 0.0) then
        victim.blocked_up = true
    end
end

-- Itr kind 15 (pulling whirlwind): pulls 1px/frame toward the attacker's x, 0.5 toward its
-- depth, and lifts.
local function pull(attacker, victim, step)
    if victim.x_int > attacker.x_int then victim.impulse_x = victim.vx - 1.0
    else victim.impulse_x = victim.vx + 1.0 end
    victim.vx = victim.impulse_x
    if victim.z_int > attacker.z_int then victim.impulse_z = victim.vz - 0.5
    else victim.impulse_z = victim.vz + 0.5 end
    victim.vz = victim.impulse_z
    lift(victim, step)
end

-- Itr kind 16 (freezing whirlwind): armor-scaled damage, frozen frame 200, vrest, drops a
-- heavy item.
local function freeze_hit(state, p, v, attacker, victim, itr)
    local damage = itr.injury
    if victim.armor > 0 then damage = cdiv(damage * 100, victim.armor) end
    local owner = state.items[attacker.owner]
    if victim.hp > 0 and damage >= victim.hp and victim.follow == -1 then
        if owner then owner.kills = owner.kills + 1 end
        battle.count_kill(state, victim)
    end
    victim.hp = victim.hp - damage
    victim.dark_hp = victim.dark_hp + cdiv(damage, -3)
    victim.hp_spent = victim.hp_spent + damage
    if victim.follow == -1 and owner then owner.damage_dealt = owner.damage_dealt + damage end
    battle.count_damage(state, victim, damage)
    victim.frame = 200
    victim.wait_counter = 0
    sounds.effect(state, victim.x_int, 14)
    if itr.vrest > 0 then victim.pair_rest[p] = rest_byte(itr.vrest) end
    local held = objects.lookup(state, victim.held_item)
    if victim.weapon == 2 and held and held.holder == v and held.weapon == -2 then
        attacker.pair_rest[victim.held_item] = 45
        victim.weapon = 0
        victim.pair_rest[victim.held_item] = 30
        held.weapon = 0
        held.frame = engine.random(6)
        held.vy = -1.0
    end
end

local function catch(state, p, v, attacker, victim, itr)
    victim.vx, attacker.vx = 0.0, 0.0
    attacker.facing = attacker.x_int > victim.x_int and 1 or 0
    victim.facing = 1 - attacker.facing
    local catching, caught = itr.catching_actions[1], itr.caught_actions[1]
    attacker.frame = catching
    victim.frame = caught
    local first = attacker.record.frame(catching).cpoint.x
    local second = victim.record.frame(caught).cpoint.x
    attacker.x, attacker.y = attacker.x_int, attacker.y_int
    local catching_center = attacker.record.frame(catching).center_x
    local caught_center = attacker.record.frame(caught).center_x
    if attacker.facing == 0 then
        victim.x = attacker.x_int - catching_center - caught_center + second + first
    else
        victim.x = catching_center + caught_center + attacker.x_int - second - first
    end
    victim.y = victim.record.frame(caught).center_y - attacker.record.frame(catching).center_y + attacker.y_int
    local shift = (victim.x_int - victim.x) * 0.5
    victim.x = victim.x + shift
    attacker.x = shift + attacker.x
    victim.x_int = trunc(victim.x)
    attacker.x_int = trunc(attacker.x)
    attacker.catching = v
    victim.caught_by = p
    attacker.catch_timer = 300
    victim.timer_b0 = 0
end

function combat.apply(state, p)
    local attacker = state.items[p]
    local frame = attacker.record.frame(attacker.frame_at_pass)
    for position = 1, attacker.hit_list_count do
        local itr_index = attacker.hit_list_itr[position]
        if itr_index > #frame.interactions then break end
        local v = attacker.hit_list[position]
        local victim = objects.lookup(state, v)
        if victim and (victim.pair_rest[p] or 0) <= 0 then
            if attacker.hit_this_frame and victim.record.kind == record_kinds.character then return end
            local itr = frame.interactions[itr_index]
            -- A caught victim is protected unless its catcher's frame is hurtable.
            local catcher = objects.lookup(state, victim.caught_by)
            local protected = victim.record.frame(victim.frame_at_pass).cpoint.kind == cpoint_kinds.caught and catcher ~= nil
                and catcher.catching == v and catcher.record.frame(catcher.frame_at_pass).cpoint.hurtable == 0
            if protected then
                itr = nil
            elseif itr.kind == attack_kinds.plain and itr.effect == effects.burn_state_guard then
                local victim_state = victim.record.frame(victim.frame).state
                if victim_state == constants.frame_states.burning or victim_state == constants.frame_states.burning_run then return end
            elseif itr.kind == attack_kinds.held_item and attacker.weapon < 0 then
                itr = weapon_strike(state, p, attacker, v, itr)
            elseif itr.kind == attack_kinds.thrown_body and attacker.fall_damage > 0 then
                -- A thrown body hits like a plain attack, pushing backward when moving backward.
                local copy = copy_itr(itr)
                copy.kind = attack_kinds.plain
                if (attacker.vx > 0.0 and attacker.facing == 1) or (attacker.vx < 0.0 and attacker.facing == 0) then
                    copy.dvx = -copy.dvx
                end
                itr = copy
            end
            if itr and itr.kind == attack_kinds.plain then
                -- A victim holding a heavy weapon drops it.
                local held = objects.lookup(state, victim.held_item)
                if victim.weapon == 2 and held and held.holder == v and held.weapon == -2 then
                    attacker.pair_rest[victim.held_item] = 45
                    victim.weapon = 0
                    victim.pair_rest[victim.held_item] = 30
                    held.weapon = 0
                    held.frame = engine.random(6)
                    held.vy = -1.0
                end
            end
            if itr and victim.record.kind == record_kinds.heavy_item then
                itr = copy_itr(itr)
                itr.dvx, itr.dvy = cdiv(itr.dvx, 2), cdiv(itr.dvy, 2)
            end
            if itr and itr.kind == attack_kinds.reflect_ball then
                local victim_state = victim.record.frame(victim.frame).state
                if victim.record.kind == record_kinds.character or victim_state == constants.frame_states.thrown_item or victim_state == constants.frame_states.flying_heavy_item then
                    itr = copy_itr(itr)
                    itr.kind = attack_kinds.plain
                    if victim.record.kind == record_kinds.character then attacker.hp = 0 end
                end
            end
            if not itr then
                -- Skipped: protected caught victim.
            elseif itr.kind == attack_kinds.pick_up then
                pick_up(attacker, victim, v, p)
            elseif itr.kind == attack_kinds.rolling_pickup then
                if attacker.weapon == 0 then grab_weapon(attacker, victim, v, p) end
            elseif itr.kind == attack_kinds.catch_nearest or itr.kind == attack_kinds.catch then
                catch(state, p, v, attacker, victim, itr)
            elseif itr.kind == attack_kinds.super_window then
                victim.super_window = 3
            elseif itr.kind == attack_kinds.heal then
                -- Healing: the victim regenerates, the healer jumps onto it.
                victim.regen_timer = itr.injury + 1000
                attacker.frame = itr.dvx
                attacker.x = victim.x
                attacker.z = victim.z + 1.0
            elseif itr.kind == attack_kinds.reflect_ball then
                reflect_ball(state, p, attacker, victim)
            elseif itr.kind == attack_kinds.whirlwind or (itr.kind == attack_kinds.conditional_whirlwind and victim.fall_damage < 0) then
                whirl(state, p, attacker, victim)
            elseif itr.kind == attack_kinds.obstacle then
                obstruct(attacker, victim)
            elseif itr.kind == attack_kinds.pulling_whirlwind or itr.kind == attack_kinds.freezing_whirlwind then
                if victim.record.kind == record_kinds.character then
                    if itr.kind == attack_kinds.freezing_whirlwind then freeze_hit(state, p, v, attacker, victim, itr) end
                    if itr.kind == attack_kinds.pulling_whirlwind then pull(attacker, victim, 3.0) end
                elseif is_weapon(victim.record.kind) and victim.record.kind ~= record_kinds.heavy_item
                       and victim.record.id ~= constants.object_ids.henry_arrow and victim.record.id ~= constants.object_ids.rudolf_weapon then
                    if victim.record.frame(victim.frame).state ~= constants.frame_states.airborne_item then victim.frame = 0 end
                    pull(attacker, victim, 3.0)
                elseif victim.record.kind == record_kinds.heavy_item then
                    if victim.record.frame(victim.frame).state ~= constants.frame_states.flying_heavy_item then victim.frame = 0 end
                    pull(attacker, victim, 2.3)
                end
            elseif itr.kind == attack_kinds.plain then
                local victim_frame = victim.record.frame(victim.frame_at_pass)
                local defended = false
                local exposed = itr.bdefend == 100 or victim_frame.state == constants.frame_states.broken_defend or victim_frame.state == constants.frame_states.injured
                    or victim_frame.state == constants.frame_states.falling or victim_frame.state == constants.frame_states.frozen or victim_frame.state == constants.frame_states.lying
                    or victim_frame.state == constants.frame_states.dizzy or victim_frame.state == constants.frame_states.burning
                if not exposed then defended = armored(attacker, victim, itr) end
                if not defended and victim_frame.state == constants.frame_states.defending and itr.bdefend < 61
                   and (attacker.facing ~= victim.facing or itr.dvx < 0 or attacker.record.id == constants.item_ids.boomerang
                        or attacker.record.id == constants.object_ids.jan_chase or attacker.record.id == constants.object_ids.firzen_chase_fire or attacker.record.id == constants.object_ids.firzen_chase_ice)
                   and victim.hp > 0 then
                    defended = true
                end
                -- A defended hit on a non-character leaves this branch (unreachable: only
                -- characters defend or wear armor).
                if not (defended and victim.record.kind ~= record_kinds.character) then
                    local spark_kind = 0
                    if defended then
                        defended_hit(state, p, attacker, victim, itr)
                        rumble.queue(state, v, 40) -- lighter feedback for a blocked hit
                    else
                        spark_kind = plain_hit(state, p, v, attacker, victim, itr)
                        if victim.record.kind == record_kinds.character then rumble.queue(state, v, 100) end
                    end
                    if spark_kind == "stop" then return end
                    record_spark(state, p, v, attacker, victim, itr, spark_kind)
                end
            end
        end
    end
end

function combat.apply_impulses(state)
    for index = 0, 399 do
        local value = state.items[index]
        if value and value.hit_lag == 0 then
            if value.hit_count ~= 0 then
                value.vx = value.impulse_x * 2.0 / (value.hit_count + 1)
                value.vy = value.impulse_y * 2.0 / (value.hit_count + 1)
                value.vz = value.impulse_z * 2.0 / (value.hit_count + 1)
                value.hit_count = 0
            end
            value.impulse_x, value.impulse_y, value.impulse_z = 0.0, 0.0, 0.0
        end
    end
end

function combat.reset_lists(state)
    for index = 0, 399 do
        local value = state.items[index]
        if value then
            value.nearest, value.nearest_catcher = 1000, 1000
            value.hit_list_count = 0
            value.hit_this_frame = false
        end
    end
end
return combat
