-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local constants = require("base/game/constants")
local item = {}
local keys = {"up", "down", "left", "right", "attack", "jump", "defend"}
item.keys = keys

local empty_frame = {name = "", picture = 0, state = 0, wait = 0, next = 0, dvx = 0, dvy = 0, dvz = 0,
    center_x = 0, center_y = 0, mp = 0, undefined = true,
    hits = {a = 0, d = 0, j = 0, Fa = 0, Ua = 0, Da = 0, Fj = 0, Uj = 0, Dj = 0, ja = 0},
    opoint = {kind = 0, x = 0, y = 0, action = 0, dvx = 0, dvy = 0, oid = 0, facing = 0},
    bpoint = {x = 0, y = 0},
    cpoint = {kind = 0, x = 0, y = 0, injury = 0, cover = 0, vaction = 0, aaction = 0, jaction = 0,
        daction = 0, taction = 0, throwvx = 0, throwvy = 0, hurtable = 0, decrease = 0, dircontrol = 0},
    wpoint = {kind = 0, x = 0, y = 0, weaponact = 0, attacking = 0, cover = 0, dvx = 0, dvy = 0, dvz = 0},
    interactions = {}, bodies = {}}
item.empty_frame = empty_frame

-- A record combines the catalog entry (id, type) with the parsed file.
function item.record(entry, data)
    local record = {id = entry.id, kind = entry.kind, data = data, movement = data.movement,
        frames = data.frames}
    function record.frame(frame_id) return data.frames[frame_id] or empty_frame end
    return record
end

function item.create(record)
    local new = {
        record = record, walk_phase = 0, dash_counter = 0, blink = 0,
        x_int = 0, y_int = 0, z_int = 0, draw_offset = 0,
        vx = 0.1, vy = 0.1, vz = 0.1, x = 0, y = 0, z = 0,
        frame = 0, previous_frame = 0, facing = 0, wait_counter = 0,
        weapon = 0, held_item = 0, holder = 0, timer_b0 = 0, hit_lag = 0, timer_b8 = 0,
        attack_press = 0, jump_press = 0, defend_press = 0, defend_lock = 0,
        right_press = 0, left_press = 0, up_press = 0, down_press = 0,
        sequences = {0, 0, 0, 0, 0, 0, 0, 0, 0}, super_window = 0, timer_ec = 0,
        follow = -1, hp = 500, dark_hp = 500, max_hp = 500, mp = 500, pic_offset = 0,
        drop_counter = 0, fall_damage = 0, transform = -1, twin = -1, armor = 0, battle_side = 0,
        hp_spent = 0, mp_spent = 0, owner = 99, team = constants.teams.independent,
        blocked_up = false, blocked_down = false, blocked_left = false, blocked_right = false,
        keys = {}, previous_keys = {},
        impulse_x = 0.1, impulse_y = 0.1, impulse_z = 0.1, hit_count = 0, pair_rest = {},
        hit_list = {}, hit_list_itr = {}, hit_list_count = 0, nearest = 1000, nearest_catcher = 1000,
        frame_at_pass = 0, state_frame = 0, sparks = {}, hit_this_frame = false,
        kills = 0, damage_dealt = 0, pickings = 0,
        order_x = -1000, order_z = -1000, follow_order = 0, last_target = -1,
        key_history = {0, 0, 0, 0, 0},
        chase_target = -1, thrower = -1, regen_timer = 0, heal_timer = 0,
        catching = 0, caught_by = 0, catch_timer = 0, transformed_to = -1,
        -- Stage entries: lives (+0x30c), and the hp/lives with which a beaten enemy joins the
        -- players (+0x314/+0x310).
        lives = 0, join_hp = 0, join_lives = 0,
        merge_timer = 0, merge_partner = -1, merged_own = 0, merged_partner = 0,
    }
    for _, key in ipairs(keys) do
        new.keys[key] = false
        new.previous_keys[key] = false
    end
    return new
end

function item.frame(value) return value.record.frame(value.frame) end
return item
