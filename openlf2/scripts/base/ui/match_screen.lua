-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local constants = require("base/game/constants")
local record_kinds = constants.record_kinds
local match = require("base/game/match")
local background = require("base/game/background")
local object_data = require("base/game/object_data")
local font = require("base/ui/font")
local sounds = require("base/game/sounds")
local rumble = require("base/game/rumble")
local controls = require("base/ui/controls")
local options = require("base/game/options")
local screen = {}
local replay_lines, mode_line

-- options: see base/game/match create().
function screen.create(options)
    local state = {match = match.create(options)}
    state.match.capture = function(current) return screen.snapshot(current) end
    return state
end

local function advance_sparks(list)
    local drawn = {}
    local position = 1
    while position <= #list do
        local spark = list[position]
        local timer = spark.timer
        local frame, left, up
        if timer < 5 then frame, left, up = timer, 0x33, 0x28
        elseif timer >= 10 and timer < 15 then frame, left, up = timer - 5, 0x1e, 0x18
        elseif timer >= 20 and timer < 29 then frame, left, up = math.floor((timer - 20) / 2) + 10, 0x33, 0x28
        elseif timer >= 30 and timer < 39 then frame, left, up = math.floor((timer - 30) / 2) + 15, 0x1e, 0x18 end
        if frame then
            drawn[#drawn + 1] = {frame = frame, x = spark.x - left, y = spark.y - up}
            spark.timer = timer + 1
        elseif position == #list then
            list[position] = nil
        end
        position = position + 1
    end
    return drawn
end

function screen.snapshot(state)
    local order = {}
    for index = 0, 399 do
        local value = state.items[index]
        if value then
            order[#order + 1] = {index = index, record = value.record, frame = value.frame,
                x = value.x_int, y = value.y_int, z = value.z_int, facing = value.facing,
                blink = value.blink, hit_lag = value.hit_lag, draw_offset = value.draw_offset,
                pic_offset = value.pic_offset, weapon = value.weapon, team = value.team,
                hp = value.hp, max_hp = value.max_hp, human = value.human,
                sparks = advance_sparks(value.sparks)}
        end
    end
    -- Bubble sort by depth: stable for equal z, like the original's adjacent swaps.
    for pass = #order - 1, 1, -1 do
        for position = 1, pass do
            if order[position + 1].z < order[position].z then
                order[position], order[position + 1] = order[position + 1], order[position]
            end
        end
    end
    return {items = order, camera = state.camera, shake = state.shake}
end

function screen.update(state, held, context)
    local result = match.step(state.match, held)
    if result == "leave" then
        -- F4 in Championship or during a replay: the game state becomes 10, the title.
        context.action("title")
        return
    end
    if result == "replay_error" then
        context.action("replay_error")
        return
    end
    for _, sound in ipairs(sounds.flush(state.match)) do context.sound(sound.resource, sound.volume, sound.pan) end
    -- Rumble (OpenLF2 extension): a landed hit on a local player's slot rumbles their controller,
    -- or device haptics when slot 1 is reading the on-screen touch gamepad.
    local rumble_enabled = options.current().rumble
    for _, event in ipairs(rumble.flush(state.match)) do
        if rumble_enabled then
            local set = controls.current().sets[event.item_index + 1]
            if set and set.device and set.device >= 1 then
                context.rumble("gamepad", set.device - 1, event.strength)
            elseif set and set.device == 0 and event.item_index == 0 and held.touch_active then
                context.rumble("phone", 0, event.strength)
            end
        end
    end
    if result == "finished" then
        context.action("round_over")
        return
    end
    state.view = state.match.last_snapshot
end

local function bold_text(context, text, x, y)
    for _, offset in ipairs({{-1, 1}, {-1, 0}, {0, 1}, {0, 0}}) do font.draw(context, text, x + offset[1], y + offset[2]) end
end
local function wrapped_text(context, text, x, y, lines)
    local line = 0
    for part in (text .. "\n"):gmatch("([^\n]*)\n") do
        repeat
            if line >= lines then return end
            bold_text(context, part:sub(1, 64), x, y + line * 16)
            part = part:sub(65)
            line = line + 1
        until part == ""
    end
end
local function clock(frames)
    local seconds = math.floor((frames + 15) / 30)
    if seconds < 3600 then return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60) end
    return string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 3600 % 60)
end
replay_lines = function(context, current)
    local replay = current.replay
    local y = current.mode == constants.modes.battle and 0x9b or 0x85
    if replay.author ~= "<No name>" then
        bold_text(context, "Author:", 10, y)
        bold_text(context, replay.author, 0x4b, y)
        y = y + 0x16
    end
    if replay.info ~= "<No info>" then
        bold_text(context, "  Info:", 10, y)
        wrapped_text(context, replay.info, 0x4b, y, 4)
    end
    bold_text(context, clock(current.elapsed) .. " / " .. clock(replay.total_time), 5, 0x1fe)
end
local mode_text = ""
mode_line = function(context, current, replaying)
    local names = {
        [constants.modes.versus] = "VS mode ",
        [constants.modes.championship] = "1 on 1 ",
        [constants.modes.team_championship] = "2 on 2 ",
        [constants.modes.battle] = "Battle mode "}
    local base
    if current.mode == constants.modes.stage then
        base = math.floor((current.stage_run and current.stage_run.id or 0) / 10) == 5 and "Survival Stage " or "Stage mode "
    else
        base = names[current.mode]
    end
    if base then
        local suffixes = {[0] = "(Difficult)", [1] = "(Normal)", [2] = "(Easy)", [-1] = "(CRAZY!)"}
        mode_text = base .. (suffixes[current.difficulty] or "")
    end
    if mode_text ~= "" then bold_text(context, mode_text, 0x316 - #mode_text * 8, replaying and 0x1fe or 0x213) end
end

local function label_font(team)
    if team >= constants.teams.player_one and team <= constants.teams.player_four then
        return "pe/words" .. team
    end
    return "pe/words0"
end
local function glyphs(context, sheet, text, x, y, advance)
    for position = 1, #text do
        local code = text:byte(position)
        context.sprite(sheet, {(code % 16) * 16, math.floor(code / 16) * 16 + 1, 8, 16},
            x + (position - 1) * advance, y, true)
    end
end

local spark_frames = {}
for frame = 1, 4 do
    spark_frames[frame] = {0x66 * frame, 0, 0x66, 0x50}
    spark_frames[frame + 10] = {0x66 * frame, 0x80, 0x66, 0x50}
    spark_frames[frame + 5] = {0x3d * frame, 0x50, 0x3d, 0x30}
    spark_frames[frame + 15] = {0x3d * frame, 0xd0, 0x3d, 0x30}
end

local function draw_item(context, stage, view, entry)
    local frame = entry.record.frame(entry.frame)
    local blink = math.abs(entry.blink)
    local camera = view.camera
    if entry.weapon >= 0 and frame.state ~= 3005
       and frame.state ~= constants.frame_states.team_order_marker
       and entry.record.id ~= constants.object_ids.firzen_ball
       and entry.record.id ~= constants.object_ids.bat_ball
       and entry.blink > -70 and blink % 4 < 2 and stage.shadow then
        local width, height = stage.shadow_size[1] or 0, stage.shadow_size[2] or 0
        local shadow = stage.shadow:gsub("\\", "/"):lower()
        context.image(shadow, entry.draw_offset + entry.x - camera - math.floor(width / 2),
            entry.z - math.floor(height / 2), true)
    end
    local shake = entry.hit_lag < 0 and view.shake * 6 - 3 or 0
    local visible = blink % 4 < 2 and entry.blink > -25
    local on_screen = frame.state == constants.frame_states.team_order_marker
    local resource, source = object_data.picture(entry.record.data, entry.frame, entry.pic_offset)
    if visible and resource and not frame.undefined then
        local y = entry.z - frame.center_y + entry.y
        local x
        if entry.facing == 0 then x = entry.draw_offset - frame.center_x + entry.x - camera + shake
        else x = frame.center_x + entry.draw_offset + entry.x - camera + shake - source[3] end
        if on_screen then x = math.max(0, math.min(x, 0x2ca)) end
        context.sprite(resource, source, x, y, true, entry.facing ~= 0)
    end
    if visible and not on_screen and entry.hp < math.floor(entry.max_hp / 3) and frame.bpoint.x > 0 then
        local offset = entry.facing == 0 and frame.bpoint.x - frame.center_x or frame.center_x - frame.bpoint.x
        context.sprite("pe/bars", {0, 20, 1, 3}, offset + entry.draw_offset + entry.x - camera + shake,
            frame.bpoint.y - frame.center_y + entry.z + entry.y, false)
    end
    if (entry.index < 20 or (entry.team ~= constants.teams.enemies and entry.record.kind == record_kinds.character))
       and entry.blink > -25 then
        local label = entry.index < 8 and controls.name(entry.index) or "Com"
        local length = #label
        local x = entry.draw_offset + entry.x - camera - math.floor(length * 9 / 2)
        if x < 0 then x = 0 end
        if x > 794 - length * 9 then x = 794 - length * 9 end
        glyphs(context, label_font(entry.team), label, x, entry.z + 3, 9)
    end
    for _, spark in ipairs(entry.sparks) do
        local source = spark_frames[spark.frame]
        -- Frames 0, 5, 10 and 15 are never given a rectangle (assumed empty; see docs).
        if source then context.sprite("pe/spark", source, entry.draw_offset + spark.x - camera, spark.y, true) end
    end
end

local function draw_status(context, state)
    for slot = 0, 7 do
        local row, column = math.floor(slot / 4) * 54, (slot % 4) * 198
        context.image("pe/frame", column, row, false)
        local value = state.items[slot] or state.items[slot + 10]
        if value then
            local small = value.record.data.small
            if small then context.image(small:gsub("\\", "/"):lower(), column + 9, row + 7, false) end
            if value.hp > 0 then
                local function bar(source_y, width, y)
                    if width > 0 then context.sprite("pe/bars", {0, source_y, width, 10}, column + 57, row + y, false) end
                end
                bar(30, math.floor(value.dark_hp * 31 / 125), 16)
                bar(20, math.floor(value.hp * 31 / 125), 16)
                bar(10, 124, 36)
                bar(0, math.floor(value.mp * 31 / 125), 36)
            end
            glyphs(context, label_font(value.team), string.char(254), column + 5, row, 8)
        end
    end
end

local function draw_scoreboard(context, current)
    local counter = current.round_counter
    if counter < 101 or counter >= 350 then return end
    local players = 0
    for slot = 0, 7 do
        if current.items[slot] or current.items[slot + 10] then players = players + 1 end
    end
    local battle_run = current.battle_run
    local height = players * 45 + (battle_run and 138 or 93)
    local top = math.floor((530 - height) / 2)
    local row_y = top + 16
    context.image("pe/score_board1", 150, top, false)
    for slot = 0, 7 do
        local index = current.items[slot] and slot or slot + 10
        local value = current.items[index]
        if value then
            row_y = row_y + 45
            context.image("pe/score_board2", 150, row_y, false)
            local small = value.record.data.small
            if small then context.image(small:gsub("\\", "/"):lower(), 165, row_y, false) end
            local label = index < 10 and ("P" .. (index + 1) .. " ") or "Com"
            glyphs(context, label_font(value.team), label, 206, row_y + 15, 9)
            font.gdi(context, tostring(value.kills), 271, row_y + 15)
            font.gdi(context, tostring(value.damage_dealt), 326, row_y + 15)
            font.gdi(context, tostring(value.hp_spent), 390, row_y + 15)
            font.gdi(context, tostring(value.mp_spent), 454, row_y + 15)
            font.gdi(context, tostring(value.pickings), 527, row_y + 15)
            local result
            if current.winner >= 0 then
                if current.winner == value.team then
                    result = value.hp < 1 and "pe/win_dead" or "pe/win_alive"
                else
                    result = "pe/lose_dead"
                end
            end
            if result then context.image(result, 571, row_y + 15, false) end
        end
    end
    local footer = top + players * 45 + 61
    if battle_run then
        context.image("pe/score_board4", 150, footer, false)
        context.image("pe/score_board3", 150, footer + 45, false)
        font.gdi(context, tostring(battle_run.deaths[1]), 243, footer + 23)
        font.gdi(context, tostring(battle_run.deaths[2]), 483, footer + 23)
        font.gdi(context, tostring(battle_run.damage[1]), 323, footer + 23)
        font.gdi(context, tostring(battle_run.damage[2]), 563, footer + 23)
    else
        context.image("pe/score_board3", 150, footer, false)
    end
    local seconds = math.floor((current.elapsed + 15) / 30)
    local text
    if seconds < 3600 then text = string.format("%02d : %02d", math.floor(seconds / 60), seconds % 60)
    else
        text = string.format("%02d : %02d : %02d", math.floor(seconds / 3600),
            math.floor(seconds % 3600 / 60), seconds % 3600 % 60)
    end
    font.gdi(context, text, 580, top + players * 45 + (battle_run and 112 or 67))
end

function screen.describe(state)
    local current = state.match
    local parts = {"frame=" .. current.frame_number, "background=" .. current.background_row,
        "camera=" .. current.camera, "round=" .. current.round_counter, "winner=" .. current.winner}
    if current.paused then parts[#parts + 1] = "paused" end
    if current.mode == constants.modes.demo then parts[#parts + 1] = current.random_game and "demo" or "demo_ending" end
    if current.cheat_lock > 0 then
        local counts = current.function_counts
        parts[#parts + 1] = string.format("fkeys=%d:%d,%d,%d,%d", current.cheat_lock, counts[6], counts[7],
            counts[8], counts[9])
    end
    local run = current.stage_run
    if run then
        parts[#parts + 1] = string.format("stage=%d phase=%d go=%d shutter=%d result=%d bound=%d width=%d", run.id,
            run.phase, run.go, run.shutter, run.result, current.stage_bound, current.stage.width or 794)
    end
    for index = 0, 399 do
        local value = current.items[index]
        if value then
            -- Holding links are listed only when set, so plain items keep the short form.
            local held = value.weapon ~= 0 and string.format(" weapon=%d link=%d", value.weapon,
                value.weapon > 0 and value.held_item or value.holder) or ""
            parts[#parts + 1] = string.format("item%d{id=%d frame=%d x=%.3f y=%.3f z=%.3f vx=%.3f vy=%.3f vz=%.3f hp=%d mp=%d facing=%d%s}",
                index, value.record.id, value.frame, value.x, value.y, value.z, value.vx, value.vy, value.vz,
                value.hp, value.mp, value.facing, held)
        end
    end
    return table.concat(parts, " ")
end

function screen.outcome(state)
    local run = state.match.stage_run
    if not run then return {} end
    return {stage_level = run.id, auto_start = run.next_group, ending = run.ending}
end

function screen.draw(state, context)
    context.viewport(794, 550, 0, 0, 0)
    local view = state.view
    local current = state.match
    if not view then return end
    if current.background_row == 99 then background.paint_lee_on_road(context, view.camera)
    else background.paint(context, current.stage, current.view, view.camera) end
    for _, entry in ipairs(view.items) do draw_item(context, current.stage, view, entry) end
    for _, command in ipairs(view.stage or {}) do
        if command[1] == "sprite" then context.sprite(command[2], command[3], command[4], command[5], true)
        elseif command[1] == "fill" then context.fill(command[2], command[3], command[4], command[5], 0, 0, 0)
        elseif command[1] == "text" then font.gdi(context, command[2], command[3], command[4]) end
    end
    draw_status(context, current)
    if view.paused then
        context.image("pe/pause", 360, 288, true)
        return
    end
    -- After the end loop: the demo's exit hint and DEMO picture, or the function-key line (GDI
    -- text; font.gdi stands in).
    if current.random_game then
        font.gdi(context, "Press F4 or 'Attack' to exit", 0x262, 0x6e)
        font.gdi(context, "http://www.LittleFighter.com", 5, 0x6e)
        context.image("pe/demo", 0x168, 0x120, true)
    elseif current.cheat_lock == 1 then
        local counts = current.function_counts
        local text = string.format("Function Keys Used:    F6: %d time(s)    F7: %d time(s)    F8: %d time(s)    F9: %d time(s)",
            counts[6], counts[7], counts[8], counts[9])
        if current.mode == constants.modes.stage then
            context.fill(0, 128, 794, 21, 0, 0, 0)
            font.gdi(context, text, 0, 129)
        else
            font.gdi(context, text, 0, 109)
        end
    elseif current.cheat_lock == 2 then
        font.gdi(context, "Function Keys Locked", 0, 109)
    end
    draw_scoreboard(context, current)
    local replaying = current.replay and not current.replay_ended
    if replaying then
        context.sprite("pe/menu_clip4", {2, 586, 725, 12}, 0x43, 0x216, false)
        if current.replay_status then replay_lines(context, current) end
    end
    mode_line(context, current, replaying)
end

return screen
