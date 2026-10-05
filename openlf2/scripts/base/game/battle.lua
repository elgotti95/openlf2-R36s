-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local constants = require("base/game/constants")
local record_kinds = constants.record_kinds
local objects = require("base/game/objects")
local battle = {}

local function cdiv(a, b)
    local q = a / b
    if q >= 0 then return math.floor(q) end
    return math.ceil(q)
end
local function cmod(a, b) return a - cdiv(a, b) * b end

local types = {[0] = 30, 31, 33, 34, 39, 32, 35, 36, 37, 122, 123}
local type_count = 11
local strategies = {[0] = "Zero", "Balanced", "Inferior", "Ranged attack", "Melee attack", "Giant", "Full"}
local sizes = {[0] = "(S)", "(M)", "(L)"}
-- Soldier hp by record id (separate ifs in the original, 500 otherwise).
local soldier_hp = {[36] = 250, [37] = 200, [35] = 200, [32] = 200, [39] = 150, [33] = 150, [34] = 100,
    [31] = 50, [30] = 50, [122] = 200}

-- config: the setup's counts (stock/on_field computed at Start Game), defense, strategy, size.
function battle.create(config)
    local run = {stock = {}, on_field = {}, deaths = {[1] = 0, [2] = 0}, damage = {[1] = 0, [2] = 0},
        defense = {[0] = config.defense[0], [1] = config.defense[1]},
        strategy = {[0] = config.strategy[0], [1] = config.strategy[1]},
        size = {[0] = config.size[0], [1] = config.size[1]}, over = false}
    for i = 0, type_count * 2 - 1 do
        run.stock[i] = (config.stock and config.stock[i]) or 0
        run.on_field[i] = (config.on_field and config.on_field[i]) or 0
    end
    return run
end

function battle.count_kill(state, victim)
    local run = state.battle_run
    if run and victim.battle_side > 0 and victim.battle_side < 3 then
        run.deaths[victim.battle_side] = run.deaths[victim.battle_side] + 1
    end
end
function battle.count_damage(state, victim, damage)
    local run = state.battle_run
    if run and victim.battle_side > 0 and victim.battle_side < 3 then
        run.damage[victim.battle_side] = run.damage[victim.battle_side] + damage
    end
end

local function caption(run, side)
    local strategy = run.strategy[side]
    local text = strategies[strategy] or ""
    if strategy > 0 and strategy < 6 then text = text .. (sizes[run.size[side]] or "") end
    local defense = run.defense[side]
    if defense ~= 100 then
        if strategy ~= -1 then text = text .. "    " end
        text = text .. string.format("Defense: %d.%d", cdiv(defense, 100), cdiv(cmod(defense, 100), 10))
    end
    return text
end

function battle.update(state, run)
    local display = {}
    local census = {}
    local men, health = {[0] = 0, [1] = 0}, {[0] = 0, [1] = 0}
    for i = 0, type_count * 2 - 1 do census[i] = 0 end
    for index = 0, 399 do
        local value = state.items[index]
        if value then
            if value.battle_side > 0 and value.battle_side < 3 and index >= 20 then
                local id = value.record.id
                if (id >= constants.fighter_ids.bandit and id <= constants.fighter_ids.justin
                    and id ~= constants.fighter_ids.bat) or id == constants.item_ids.milk or id == constants.item_ids.beer then
                    for kind = 0, type_count - 1 do
                        if types[kind] == id then
                            local key = (value.battle_side - 1) * type_count + kind
                            census[key] = census[key] + 1
                        end
                    end
                end
            end
            if value.record.kind == record_kinds.character and value.hp > 0 then
                local side = value.team == constants.teams.player_one and 0 or 1
                men[side] = men[side] + 1
                health[side] = health[side] + value.hp
            end
        end
    end
    local width = state.stage.width or 794
    local near, far = state.stage.zboundary[1] or 0, state.stage.zboundary[2] or 0
    for side_base = 0, type_count, type_count do
        for kind = 0, type_count - 1 do
            local index = side_base + kind
            if run.stock[index] > 0 and run.on_field[index] > census[index] then
                local slot = -1
                for candidate = 20, 399 do
                    if not state.items[candidate] then slot = candidate break end
                end
                local id = types[kind]
                if slot ~= -1 and objects.record(state, id) then
                    local value = objects.place(state, slot, id)
                    value.x, value.y, value.z = 350.0, 0.0, 300.0
                    value.z_int = engine.random(far - near) + near
                    local character = value.record.kind == record_kinds.character
                    if side_base == 0 then
                        value.x_int = character and -100 or 50
                    elseif character then
                        value.x_int = width + 100
                    else
                        value.x_int = width - 50
                    end
                    value.x, value.z = value.x_int, value.z_int
                    local hp = soldier_hp[id] or 500
                    if side_base == 0 and character then
                        -- Side 1 soldiers use the second color set (picture offset 140; 114 for 37).
                        value.pic_offset = id == constants.fighter_ids.knight and 114 or 140
                    end
                    value.mp = 500
                    value.dark_hp, value.hp, value.max_hp = hp, hp, hp
                    value.owner = slot
                    local side = cdiv(side_base, type_count) + 1
                    if character or value.record.kind == record_kinds.prisoner then
                        value.blink = 20
                        value.facing = value.x_int > cdiv(width, 2) and 1 or 0
                        value.team = side
                    else
                        value.blink = 0
                        value.team = constants.teams.independent
                    end
                    value.battle_side = side
                    value.y_int = -300
                    value.y = value.y_int
                    if character or value.record.kind == record_kinds.prisoner then value.vy = 0.0 end
                    run.stock[index] = run.stock[index] - 1
                end
            end
        end
    end
    local reserves = {[0] = 0, [1] = 0}
    for side = 0, 1 do
        for kind = 0, type_count - 3 do reserves[side] = reserves[side] + run.stock[side * type_count + kind] end
    end
    run.over = not ((reserves[0] > 0 and reserves[1] > 0) or (men[0] > 0 and men[1] > 0))
    for side = 0, 1 do
        display[#display + 1] = {"text", string.format("Man: %3d     HP: %4d     Reserve: %3d     Die: %3d",
            men[side], health[side], reserves[side], run.deaths[side + 1]), side == 0 and 10 or 450, 110}
    end
    local left, right = caption(run, 0), caption(run, 1)
    display[#display + 1] = {"text", left, 10, 133}
    display[#display + 1] = {"text", right, 785 - #right * 8, 133}
    return display
end
return battle
