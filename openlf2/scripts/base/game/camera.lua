-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local constants = require("base/game/constants")
local record_kinds = constants.record_kinds
local record_kinds = constants.record_kinds
local objects = require("base/game/objects")
local camera = {}

local function cdiv(a, b)
    local q = a / b
    if q >= 0 then return math.floor(q) end
    return math.ceil(q)
end
local function truncate(value)
    if value >= 0 then return math.floor(value) end
    return math.ceil(value)
end

-- Keeps items inside the stage depth and width; the last-rendered-width rules by kind.
local function clamp(state)
    local stage = state.stage
    local near, far, width = stage.zboundary[1] or 0, stage.zboundary[2] or 0, stage.width or 794
    for index = 0, 399 do
        local value = state.items[index]
        if value then
            local kind = value.record.kind
            if kind == record_kinds.character then
                if near > value.z then value.z = near end
                if far < value.z then value.z = far end
            else
                if near - 1.0 > value.z then value.z = near - 1.0 end
                if far + 1.0 < value.z then value.z = far + 1.0 end
            end
            value.z_int = truncate(value.z)
            if kind == record_kinds.ball then
                if value.x < -300.0 or width + 300.0 < value.x then objects.remove(state, index) end
            elseif kind == record_kinds.character then
                if index >= 20 then
                    if value.x < -100.0 then value.x = -100.0 end
                    if width + 100.0 < value.x then value.x = width + 100.0 end
                else
                    if value.team == constants.teams.enemies then
                        if value.x < -300.0 then value.x = -300.0 end
                    elseif value.x < 0.0 then
                        value.x = 0.0
                    end
                    if width < value.x then value.x = width end
                end
                if state.stage_bound > 0 and state.stage_bound < value.x and value.team ~= constants.teams.enemies and value.blink == 0 then
                    value.x = state.stage_bound
                end
            elseif (value.record.id == constants.item_ids.milk or value.record.id == constants.item_ids.beer)
                   and (value.battle_side > 0 or (state.mode == constants.modes.stage and math.floor(state.stage_run.id / 10) == constants.stage_groups.survival)) then
                if value.x < 10.0 then value.x = 10.0 end
                if width - 10.0 < value.x then value.x = width - 10.0 end
            elseif (value.x < 0.0 or width < value.x) and value.y_int == 0 then
                objects.remove(state, index)
            end
            value.x_int = truncate(value.x)
        end
    end
end

function camera.step(state)
    clamp(state)
    local sum, count = 0, 0
    local network = state.held and state.held.network
    for index = 0, 7 do
        local value = state.items[index]
        if value and value.human and value.hp > 0 and (network or index < 4) then
            if value.record.frame(value.frame).state == constants.frame_states.lying then sum = sum + value.x_int
            else sum = sum + 130 + value.x_int - value.facing * 260 end
            count = count + 1
        end
    end
    if count == 0 then
        for index = 0, 399 do
            local value = state.items[index]
            if value and value.record.kind == record_kinds.character and value.hp > 0 then
                sum = sum + value.x_int
                count = count + 1
            end
        end
        if count == 0 then sum, count = 800, 1 end
    end
    local width = state.stage.width or 794
    local target = cdiv(sum, count) - 397
    if target < 0 then target = 0 end
    if target > width - 794 then target = width - 794 end
    if state.camera_limit ~= 0 and target > state.camera_limit then target = state.camera_limit end
    state.camera_step = cdiv(cdiv(target - state.camera, 14) + state.camera_step * 6, 7)
    if state.camera_step == 0 then
        if state.camera < target then state.camera_step = 1
        elseif target < state.camera then state.camera_step = -1 end
    end
    state.camera = state.camera + state.camera_step
    local pan = state.replay_pan
    if pan and pan.active then state.camera = pan.x end
    if state.camera < 0 then state.camera = 0 end
    if state.camera > width - 794 then state.camera = width - 794 end
    if pan and pan.active then pan.x = state.camera end
end
return camera
