-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- Merge and split behavior follows the original game's pair-pass routine.
local constants = require("base/game/constants")
local objects = require("base/game/objects")
local unlock = require("base/game/unlock")
local merge = {}

local merged_id = constants.fighter_ids.firzen
local merge_frame = 0x122 -- the merged fighter's first frame
local merge_time = 0x1194 -- frames until it may split
local split_frame = 0x70 -- both halves after the split
local rest_time = 0x384 -- frames before the pair may merge again

-- Integer division truncating toward zero.
local function half(value)
    local q = value / 2
    if q >= 0 then return math.floor(q) end
    return math.ceil(q)
end
local function state_of(value) return value.record.frame(value.frame).state end

-- A running type-7/8 fighter (slots 0-9) finds a partner of the other type on its team in
-- slots 0-19: running, or (slots 10-19 only) on the ground and not lying. Both need hp below
-- 177, or the characters-unlock cheat. The partner must be within 50px/8px, to the fighter's
-- left unless it is in slots 10-19.
local function try_merge(state, index, value)
    local kind = value.record.id
    if not ((kind == constants.fighter_ids.firen or kind == constants.fighter_ids.freeze)
            and value.hp > 0 and state_of(value) == constants.frame_states.running and value.merge_timer == 0
            and (value.hp < 0xb1 or unlock.flags.characters == 1)) then
        return
    end
    local partner_id = kind == constants.fighter_ids.firen and constants.fighter_ids.freeze
        or constants.fighter_ids.firen
    for partner = 0, 19 do
        local other = state.items[partner]
        -- A merge needs the other fighter from the Freeze/Firen pair.
        if other then
            local health = other.hp
            if other.record.id == partner_id and health > 0 and value.team == other.team
               and other.merge_timer == 0 and (health < 0xb1 or unlock.flags.characters == 1)
               and other.frame > -1 and other.frame < 400 then
                local other_state = state_of(other)
                if (other_state == constants.frame_states.running
                    or (other_state ~= constants.frame_states.lying and other.y_int == 0 and partner > 9))
                   and math.abs(value.x_int - other.x_int) < 0x32 and math.abs(value.z_int - other.z_int) < 8
                   and (value.x_int > other.x_int or partner > 9) and index < 10 then
                    local record = objects.record(state, merged_id)
                    if record then
                        value.hp = value.hp + health
                        value.dark_hp = value.dark_hp + other.dark_hp
                        if value.dark_hp > value.max_hp then value.dark_hp = value.max_hp end
                        if value.hp > value.dark_hp then value.hp = value.dark_hp end
                        value.frame = merge_frame
                        value.twin = 1
                        -- The original zeroes the survivor's vx and the partner's vy.
                        value.vx = 0.0
                        other.vy = 0.0
                        value.x_int = half(other.x_int + value.x_int)
                        value.z_int = half(other.z_int + value.z_int)
                        value.x, value.z = value.x_int, value.z_int
                        value.merge_partner = partner
                        value.merge_timer = merge_time
                        value.merged_own = value.record.id
                        value.merged_partner = other.record.id
                        value.record = record
                        value.mp = 500
                        objects.remove(state, partner)
                    end
                end
            end
        end
    end
end

-- The merged fighter splits when its timer runs out and its frame is below 9 or above 260: it
-- takes its own record back, the partner is re-created in its old slot, both get half hp/dark
-- hp, frame 112, no mp, facing opposite ways.
local function split(state, value)
    local partner = value.merge_partner
    local previous = objects.lookup(state, partner)
    local entrant = previous and previous.entrant
    value.twin = -1
    value.merge_timer = rest_time
    local own = objects.record(state, value.merged_own)
    if own then value.record = own end
    local other
    if objects.record(state, value.merged_partner) then
        other = objects.place(state, partner, value.merged_partner)
        -- The original controls slots 0-9 from the keyboard; the port keeps that as `human`.
        other.human = partner < 10
        -- Championship bookkeeping of the slot survives the re-creation.
        other.entrant = entrant
    else
        -- Without the record, the partner is left as its existing item instead of re-created.
        other = objects.lookup(state, partner)
    end
    if other then
        other.hp = half(value.hp)
        other.dark_hp = half(value.dark_hp)
    end
    value.hp = half(value.hp)
    value.dark_hp = half(value.dark_hp)
    if other then
        other.x_int, other.z_int, other.y_int = value.x_int, value.z_int, 0
        other.x, other.z, other.y = other.x_int, other.z_int, 0.0
        other.vx = 0.0
        other.facing = 1 - value.facing
        other.frame = split_frame
        other.mp = 0
        other.team = value.team
    end
    value.vx = 0.0
    value.frame = split_frame
    value.mp = 0
end

local function try_split(state, index, value)
    if not (value.record.id == merged_id and value.twin == 1 and (value.frame < 9 or value.frame > 0x104)
            and value.merge_timer < 1) then
        return
    end
    split(state, value)
end

function merge.split_at_round_end(state, value)
    split(state, value)
end

function merge.update(state)
    for index = 0, 19 do
        -- The timer counts down in every slot, even after the item there is gone.
        local remembered = objects.lookup(state, index)
        if remembered and remembered.merge_timer > 0 then remembered.merge_timer = remembered.merge_timer - 1 end
        local value = state.items[index]
        if value then
            local kind = value.record.id
            if kind == constants.fighter_ids.firen or kind == constants.fighter_ids.freeze then try_merge(state, index, value)
            elseif kind == merged_id then try_split(state, index, value) end
        end
    end
end
return merge
