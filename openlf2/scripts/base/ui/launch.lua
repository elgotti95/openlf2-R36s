-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local controls = require("base/ui/controls")
local font = require("base/ui/font")
local sounds = require("base/game/sounds")
local options = require("base/game/options")
local navigation = require("base/ui/navigation")
local screen = {}

local menu_clip = {[1] = {0, 41, 496, 80}, [7] = {535, 105, 256, 26}, [8] = {535, 137, 256, 26},
    [9] = {535, 168, 256, 29}, [12] = {643, 426, 151, 26}, [13] = {489, 426, 151, 26}}
local menu_clip2 = {[0] = {0, 0, 704, 353}, {0, 354, 494, 23}, {0, 379, 494, 23}}
local menu_clip5 = {[0] = {0, 0, 282, 181}, {285, 0, 240, 27}, {285, 32, 240, 27}}
local devices = {[0] = "pe/cs6", "pe/cs2", "pe/cs3", "pe/cs4", "pe/cs5"}
local menu_clip6 = {[0] = {0, 0, 704, 312}, {0, 360, 439, 23}, {0, 385, 439, 23}, {0, 411, 704, 258},
    {0, 673, 543, 24}, {548, 363, 19, 19}, {572, 363, 19, 19}, {443, 388, 343, 22}}
local credits = {"by Marti Wong, Starsky Wong", "1999-2008, all rights reserved", "http://www.LittleFighter.com"}

local function note(message) return message and message:sub(1, 96) or nil end

-- options: menu_seed (background choice, like the title), problem (why config was ignored).
function screen.create(options)
    return {page = "menu", background = (options.menu_seed or 0) % 13 + 1, nav = navigation.create(), keyboard = false,
        display = {}, capture = nil, name_player = 0, previous_keys = {},
        message = options.problem and note("Configuration ignored: " .. options.problem)}
end

local function add(state, command) state.display[#state.display + 1] = command end
local function sprite(state, sheet, rectangle, x, y, keyed, mirrored, flipped)
    add(state, {"sprite", sheet, rectangle, x, y, keyed, mirrored, flipped})
end
local function image(state, path, x, y, keyed) add(state, {"image", path, x, y, keyed}) end
-- GDI text (an entry with a fifth field, the variant, is the original's bitmap font instead).
local function text(state, value, x, y, color, background) add(state, {"text", value, x, y, nil, color, background}) end
local function inside(input, left, top, right, bottom)
    return input.pointer_x >= left and input.pointer_x <= right and input.pointer_y >= top and input.pointer_y <= bottom
end

local function background(state)
    add(state, {"fill", 0, 0, 794, 550, 0x10, 0x20, 0x6c})
    image(state, "pe/menu_back" .. state.background, 0, 0, true)
end

local function menu(state, input, context)
    background(state)
    for line, value in ipairs(credits) do
        local hover = line == 3 and input.pointer_x > 0x24f and input.pointer_y > 0x1eb + 0x1e and input.pointer_y < 0x1eb + 0x3c
        text(state, value, 0x24f, 0x1eb + (line - 1) * 0x14, hover and 0xffffff or 0x5077d0, 0x102060)
    end
    sprite(state, "pe/menu_clip", menu_clip[1], 0x9b, 0x60, true)
    local top = 0xca
    sprite(state, "pe/menu_clip5", menu_clip5[0], 0x107, top, true)
    if input.pointer_x < 0x114 or input.pointer_x > 0x208 then return end
    local y = input.pointer_y
    if y >= top + 0xf and y <= top + 0x27 then
        sprite(state, "pe/menu_clip", menu_clip[7], 0x115, top + 0xd, true)
        if input.click then
            sounds.direct(state, "ok")
            state.page = "waiting"
        end
    elseif y >= top + 0x2d and y <= top + 0x46 then
        sprite(state, "pe/menu_clip", menu_clip[8], 0x115, top + 0x2d, true)
        if input.click then state.page = "network"; sounds.direct(state, "ok") end
    elseif y >= top + 0x4d and y <= top + 0x66 then
        sprite(state, "pe/menu_clip", menu_clip[9], 0x115, top + 0x4c, true)
        if input.click then
            sounds.direct(state, "ok")
            state.page = "controls"
            -- The original keeps the edited name between visits; the port starts idle.
            state.name_player = 0
            state.editing = controls.copy(controls.current())
            state.previous_keys = input.keys
        end
    elseif y >= top + 0x6b and y <= top + 0x84 then
        sprite(state, "pe/menu_clip5", menu_clip5[1], 0x117, top + 0x6b, true)
        if input.click then
            sounds.direct(state, "ok")
            local settings = controls.current()
            state.page = "recording"
            state.record = {record = settings.record, author = settings.author, email = settings.email,
                info = settings.info}
            state.previous_keys = input.keys
        end
    elseif y >= top + 0x89 and y <= top + 0xa2 then
        -- OpenLF2's own project site, not the original's (dead) LittleFighter.com link.
        sprite(state, "pe/menu_clip5", menu_clip5[2], 0x117, top + 0x8b, true)
        if input.click then
            sounds.direct(state, "ok")
            context.action("open_website")
        end
    end
end

-- OpenLF2's options entry (not in the original), spelled from the menu art's own letters;
-- 'p' is 'b' flipped vertically.
local options_row = {top = 0xca + 0xa7, bottom = 0xca + 0xc0, baseline = 0xca + 157 + 31}
local letters = {
    normal = {o = {20, 147, 10, 11}, t = {149, 144, 7, 14}, i = {144, 143, 2, 15}, s = {133, 147, 8, 11},
        n = {133, 116, 8, 11}, b = {122, 142, 9, 16}},
    pointed = {o = {289, 40, 10, 11}, t = {418, 37, 7, 14}, i = {413, 36, 2, 15}, s = {402, 40, 8, 11},
        n = {402, 9, 8, 11}, b = {391, 35, 9, 16}},
}
local function options_entry(state, input)
    local pointed = input.pointer_x >= 0x114 and input.pointer_x <= 0x208
        and input.pointer_y >= options_row.top and input.pointer_y <= options_row.bottom
    local set = pointed and letters.pointed or letters.normal
    local x = 363
    for letter in ("options"):gmatch(".") do
        if letter == "p" then
            local b = set.b
            sprite(state, "pe/menu_clip5", b, x, options_row.baseline - 10, true, false, true)
            x = x + b[3] + 3
        else
            local glyph = set[letter]
            sprite(state, "pe/menu_clip5", glyph, x, options_row.baseline - glyph[4] + 1, true)
            x = x + glyph[3] + 3
        end
    end
    if pointed and input.click then
        sounds.direct(state, "ok")
        state.page = "options"
        state.options_focus = nil
        state.options = options.current()
    end
end

-- The options page (OpenLF2 only): checkboxes with OK/Cancel; extension options add
-- Fullscreen/Show FPS where supported.
local options_panel = {x = 0x93, y = 0xb4, width = 0x1f4, height = 0xd2 + 0x34}
local check_box = {x = options_panel.x + 0x1e, y = options_panel.y + 0x46, size = 19}
local filter_box = {x = options_panel.x + 0xf3, y = options_panel.y + 0x60, width = 0xc0, height = 18}
local fullscreen_box = {x = check_box.x, y = filter_box.y + 0x1a, size = check_box.size}
local fps_box = {x = check_box.x, y = fullscreen_box.y + 0x1a, size = check_box.size}
local rumble_box = {x = check_box.x, y = fps_box.y + 0x1a, size = check_box.size}
local ok_button = {x = options_panel.x + 0x5a, y = options_panel.y + 0x9b + 0x34, width = 0x78, height = 0x1a}
local cancel_button = {x = options_panel.x + 0x104, y = ok_button.y, width = 0x78, height = 0x1a}
local function bold(state, value, x, y, variant)
    for _, offset in ipairs({{-1, 1}, {-1, 0}, {0, 1}, {0, 0}}) do
        add(state, {"text", value, x + offset[1], y + offset[2], variant})
    end
end
-- `blocked`: something drawn over the button (the open dropdown list) takes the pointer.
local function button(state, input, area, label, blocked)
    local pointed = not blocked and inside(input, area.x, area.y, area.x + area.width, area.y + area.height)
    add(state, {"fill", area.x, area.y, area.width, area.height, 0xa0, 0xa0, 0xc0})
    add(state, {"fill", area.x + 1, area.y + 1, area.width - 2, area.height - 2,
        pointed and 0x32 or 0x10, pointed and 0x4d or 0x20, pointed and 0x9a or 0x50})
    bold(state, label, area.x + math.floor((area.width - #label * 8) / 2), area.y + 5, pointed and 1 or 0)
    return pointed and input.click
end
local function filter_dropdown(state, input, values)
    local box = filter_box
    local filters = options.available_filters(input.filters)
    if input.click then
        if inside(input, box.x, box.y, box.x + box.width, box.y + box.height) then
            state.filter_open = not state.filter_open
            state.options_focus = 2
        elseif state.filter_open then
            for index, filter in ipairs(filters) do
                local y = box.y + index * box.height
                if inside(input, box.x, y, box.x + box.width, y + box.height) then
                    values.upscaling_filter = filter
                    sounds.direct(state, "ok")
                    break
                end
            end
            state.filter_open = false
            state.options_focus = 2
        end
    end
    bold(state, "Upscaling filter", options_panel.x + 0x1e, box.y + 1, 0)
    add(state, {"fill", box.x, box.y, box.width, box.height, 0xa0, 0xa0, 0xc0})
    add(state, {"fill", box.x + 2, box.y + 2, box.width - 4, box.height - 4, 0x10, 0x20, 0x50})
    bold(state, values.upscaling_filter, box.x + 9, box.y + 1, 1)
    bold(state, state.filter_open and "^" or "v", box.x + box.width - 18, box.y + 1, 1)
end
-- The open list draws last, so it can reach over the OK/Cancel buttons.
local function filter_list(state, input)
    local box = filter_box
    for index, filter in ipairs(options.available_filters(input.filters)) do
        local y = box.y + index * box.height
        local pointed = inside(input, box.x, y, box.x + box.width, y + box.height)
        add(state, {"fill", box.x, y, box.width, box.height, 0xa0, 0xa0, 0xc0})
        add(state, {"fill", box.x + 2, y + 2, box.width - 4, box.height - 4,
            pointed and 0x32 or 0x10, pointed and 0x4d or 0x20, pointed and 0x9a or 0x50})
        bold(state, filter, box.x + 9, y + 1, pointed and 1 or 0)
    end
end
-- `blocked`: like button()'s, the open dropdown list takes the pointer.
local function checkbox(state, input, box, label, checked, blocked)
    local label_x = box.x + box.size + 12
    local pointed = not blocked and inside(input, box.x, box.y, label_x + #label * 8, box.y + box.size)
    add(state, {"fill", box.x, box.y, box.size, box.size, 0xa0, 0xa0, 0xc0})
    add(state, {"fill", box.x + 2, box.y + 2, box.size - 4, box.size - 4, pointed and 0x32 or 0x08,
        pointed and 0x4d or 0x10, pointed and 0x9a or 0x30})
    if checked then bold(state, "x", box.x + 6, box.y + 1, 1) end
    bold(state, label, label_x, box.y + 1, pointed and 1 or 0)
    return pointed and input.click
end
local function options_page(state, input)
    background(state)
    sprite(state, "pe/menu_clip", menu_clip[1], 0x9b, 0x37, true)
    local panel = options_panel
    add(state, {"fill", panel.x, panel.y, panel.width, panel.height, 0xa0, 0xa0, 0xc0})
    add(state, {"fill", panel.x + 2, panel.y + 2, panel.width - 4, panel.height - 4, 0x10, 0x20, 0x50})
    bold(state, "Options", panel.x + 0x1e, panel.y + 0x14, 1)
    local values = state.options
    local was_open = state.filter_open
    if checkbox(state, input, check_box, "Unlock hidden characters", values.unlock_characters, was_open) then
        values.unlock_characters = not values.unlock_characters
    end
    filter_dropdown(state, input, values)
    -- Fullscreen (OpenLF2 extension): only when the host reports a real toggleable window.
    if input.filters.window and
       checkbox(state, input, fullscreen_box, "Fullscreen", values.fullscreen, was_open) then
        values.fullscreen = not values.fullscreen
    end
    -- Show FPS (OpenLF2 extension): every platform.
    if checkbox(state, input, fps_box, "Show FPS", values.show_fps, was_open) then
        values.show_fps = not values.show_fps
    end
    -- Rumble (OpenLF2 extension): controller or device haptics on a landed hit.
    if checkbox(state, input, rumble_box, "Rumble", values.rumble, was_open) then
        values.rumble = not values.rumble
    end
    if button(state, input, ok_button, "OK", was_open) and not was_open then
        sounds.direct(state, "ok")
        local saved, problem = options.save(values)
        state.message = not saved and note("Options not saved: " .. tostring(problem)) or nil
        state.page, state.options, state.filter_open = "menu", nil, false
    elseif button(state, input, cancel_button, "Cancel", was_open) and not was_open then
        sounds.direct(state, "cancel")
        state.page, state.options, state.filter_open = "menu", nil, false
    elseif input.nav.cancel and state.page == "options" then
        -- Escape or B closes the list, or else cancels like the button.
        sounds.direct(state, "cancel")
        if state.filter_open then
            state.filter_open, state.options_focus = false, 2
        else
            state.page, state.options = "menu", nil
        end
    end
    if state.page == "options" and state.filter_open then filter_list(state, input) end
end

-- Arrow keys move focus; the original treated them as numpad digits, so text fields ignore them.
local function typed_character(input, code)
    if code >= 0x25 and code <= 0x28 then return nil end
    return controls.key_character(code, input.keys[0x10] == true)
end

local function type_name(state, input)
    local name = state.editing.names[state.name_player]
    for code = 0, 255 do
        if input.keys[code] and not state.previous_keys[code] then
            local character = typed_character(input, code)
            if character and code ~= 8 then
                if #name < 10 and code ~= 0x0d then name = name .. character end
            elseif code == 8 and #name > 0 then
                name = name:sub(1, -2)
            end
        end
    end
    name = (name .. input.text):sub(1, 10)
    state.editing.names[state.name_player] = name
end

-- Escape, Tab or B end editing; so do Enter/A unless Enter adds a line (`multiline`).
local function leaves_field(state, input, multiline)
    return input.nav.cancel or (input.nav.ok and not multiline)
        or (input.keys[0x09] and not state.previous_keys[0x09])
end

-- Four player columns: name, device picture, seven key rows, and the OK/Cancel buttons.
local function control_settings(state, input)
    background(state)
    sprite(state, "pe/menu_clip", menu_clip[1], 0x9b, 0x23, true)
    sprite(state, "pe/menu_clip2", menu_clip2[0], 0x2e, 0x79, true)
    -- The link bar to the web page's control help (no browser is opened in the port).
    local link = inside(input, 0x2e, 0x1db, 0x21c, 0x1f2) and 2 or 1
    sprite(state, "pe/menu_clip2", menu_clip2[link], 0x2e, 0x1db, true)
    local editing = state.editing
    -- A pending assignment takes the lowest held key/button; Escape cancels a keyboard set
    -- (reserved for Back) but is just a button on joystick sets. The opening button is
    -- ignored until released.
    if state.capture then
        local set = editing.sets[state.capture.player]
        if set.device == 0 then
            if input.nav.cancel then
                state.capture = nil
            else
                for code = 0, 249 do
                    if input.keys[code] then
                        set.keys[state.capture.row] = code
                        state.capture = nil
                        break
                    end
                end
            end
        elseif input.keys[0x1b] and not state.previous_keys[0x1b] then
            state.capture = nil
        else
            local pad, lowest = input.pads[set.device], nil
            for button = 0, 31 do
                if pad and pad.buttons[button] then lowest = button; break end
            end
            if not lowest then state.capture.armed = true
            elseif state.capture.armed then
                set.buttons[state.capture.row - 4] = lowest
                state.capture = nil
            end
        end
    end
    if state.name_player > 0 then
        if leaves_field(state, input, false) then state.name_player = 0 else type_name(state, input) end
    end
    local finished
    for player = 1, 4 do
        local x = 0xc2 + (player - 1) * 0x8b
        local set = editing.sets[player]
        local name = editing.names[player]
        if input.click and inside(input, x, 0xb6, x + 0x69, 0xb6 + 0x5a) then
            state.capture = nil
            set.device = (set.device + 1) % 5
        end
        -- The original draws the edited name/key in orange; the port's bitmap font has one color.
        if state.name_player == player and #name < 10 then text(state, name .. "_", x + 0x15, 0x9f)
        else text(state, name, x + 0x15, 0x9f) end
        if input.click and inside(input, x, 0x9c, x + 0x69, 0x9c + 0x11) then
            state.capture = nil
            state.name_player = player
        end
        for row = 1, 7 do
            local y = 0x11b + (row - 1) * 0x16
            if input.click and inside(input, x, y - 3, x + 0x69, y + 0xf) then
                if set.device == 0 or row > 4 then state.capture = {player = player, row = row} end
                state.name_player = 0
            end
            if set.device == 0 then
                local label, kind = controls.key_label(set.keys[row])
                text(state, label, x + 0x29 - kind, y)
            elseif row <= 4 then
                text(state, "-", x + 0x30, y)
            else
                text(state, "Button: " .. (set.buttons[row - 4] + 1), x + 0x22, y)
            end
        end
        image(state, devices[set.device], x, 0xb6, false)
    end
    if input.pointer_y >= 0x1b9 then
        if input.pointer_y <= 0x1d1 and input.pointer_x >= 0x246 and input.pointer_x <= 0x246 + 0x9b then
            sprite(state, "pe/menu_clip", menu_clip[12], 0x244, 0x1b9, true)
            if input.click then finished = "cancel" end
        end
        if input.pointer_y <= 0x1b9 + 0x18 and input.pointer_x >= 0x195 and input.pointer_x <= 0x195 + 0x9b then
            sprite(state, "pe/menu_clip", menu_clip[13], 0x198, 0x1b9, true)
            if input.click then finished = "ok" end
        end
    end
    -- Escape or a controller's B is the Cancel button (unless it just ended a capture or a name).
    if not finished and input.nav.cancel and not input.locked then finished = "cancel" end
    if finished == "cancel" then
        -- Cancel reloads the stored settings.
        sounds.direct(state, "cancel")
        controls.load()
        state.page, state.editing, state.capture = "menu", nil, nil
    elseif finished == "ok" then
        -- OK saves into config.json.
        sounds.direct(state, "ok")
        local saved, problem = controls.save(editing)
        state.message = not saved and note("Controls not saved: " .. tostring(problem)) or nil
        state.page, state.editing, state.capture = "menu", nil, nil
    end
end

local function field_text(state, text, x, y, lines, selected)
    local row = 0
    for part in (text .. "\n"):gmatch("([^\n]*)\n") do
        repeat
            if row >= lines then return end
            for _, offset in ipairs({{-1, 1}, {-1, 0}, {0, 1}, {0, 0}}) do
                add(state, {"text", part:sub(1, 64), x + offset[1], y + row * 16 + offset[2], selected and 1 or 0})
            end
            part = part:sub(65)
            row = row + 1
        until part == ""
    end
end

-- The recording page (author, info, e-mail, record checkbox); OK saves and shows the notice page.
local function recording_page(state, input, context)
    background(state)
    sprite(state, "pe/menu_clip", menu_clip[1], 0x9b, 0x37, true)
    sprite(state, "pe/menu_clip6", menu_clip6[0], 0x2c, 0x93, true)
    local values = state.record
    -- Escape, Tab or B (and Enter or A, except in the multi-line info) end the editing.
    if state.field and leaves_field(state, input, state.field == "info") then state.field = nil end
    if input.click then
        local x, y = input.pointer_x, input.pointer_y
        state.field = nil
        if x >= 0xd2 and x < 0x2db then
            if y >= 0xcf and y < 0xe2 then state.field = "author"
            elseif y >= 0xe8 and y < 0x12f then state.field = "info"
            elseif y >= 0x135 and y < 0x148 then state.field = "email" end
        end
    end
    if state.field then
        -- Each key appends; Enter adds a line (not first); Backspace deletes; capped at 99 chars.
        local text = values[state.field]
        for code = 0, 249 do
            if input.keys[code] and not state.previous_keys[code] then
                local character = code == 0x0d and "\n" or typed_character(input, code)
                if character and code ~= 8 then
                    if (#text > 0 or character ~= "\n") and #text < 99 then text = text .. character end
                elseif code == 8 and #text > 0 then
                    text = text:sub(1, -2)
                end
            end
        end
        text = (text .. input.text):sub(1, 99)
        values[state.field] = text
    end
    field_text(state, values.author, 0xd5, 0xd1, 1, state.field == "author")
    field_text(state, values.info, 0xd5, 0xea, 4, state.field == "info")
    field_text(state, values.email, 0xd5, 0x137, 1, state.field == "email")
    if values.record ~= 0 then sprite(state, "pe/menu_clip6", menu_clip6[6], 0x11f, 0x185, true) end
    if inside(input, 0x11f, 0x186, 0x132, 0x199) then
        sprite(state, "pe/menu_clip6", menu_clip6[5], 0x11f, 0x185, true)
        if input.click then values.record = 1 - values.record end
    end
    -- "Open the recording folder" asks the host to open it in the system file manager;
    -- the web link below is decorative.
    if inside(input, 0x185, 0x184, 0x2dc, 0x19a) then
        sprite(state, "pe/menu_clip6", menu_clip6[7], 0x185, 0x184, true)
        if input.click then
            sounds.direct(state, "ok")
            context.action("open_recordings")
        end
    end
    local link = inside(input, 0x2c, 0x1cd, 0x1e3, 0x1e4) and 2 or 1
    sprite(state, "pe/menu_clip6", menu_clip6[link], 0x2c, 0x1cd, true)
    if input.pointer_y >= 0x1a0 and input.pointer_y <= 0x1b8 then
        if input.pointer_x >= 0x193 and input.pointer_x <= 0x22e then
            sprite(state, "pe/menu_clip", menu_clip[12], 0x193, 0x1a0, true)
            if input.click then
                sounds.direct(state, "cancel")
                state.page, state.record = "menu", nil
            end
        elseif input.pointer_x >= 0xe7 and input.pointer_x <= 0x182 then
            sprite(state, "pe/menu_clip", menu_clip[13], 0xe7, 0x1a0, true)
            if input.click then
                sounds.direct(state, "ok")
                local saved, problem = controls.save_recording(values.record, values.author, values.email, values.info)
                state.message = not saved and note("Settings not saved: " .. tostring(problem)) or nil
                state.page, state.record = "recorded", nil
            end
        end
    end
    -- Escape or B goes back (a field being edited takes it first).
    if state.page == "recording" and input.nav.cancel and not input.locked then
        sounds.direct(state, "cancel")
        state.page, state.record = "menu", nil
    end
end
-- The notice after the recording page; OK returns to the menu.
local function recorded_page(state, input)
    background(state)
    sprite(state, "pe/menu_clip", menu_clip[1], 0x9b, 0x4b, true)
    sprite(state, "pe/menu_clip6", menu_clip6[3], 0x2c, 0xa7, true)
    if inside(input, 0x60, 0x15c, 0x27f, 0x174) then sprite(state, "pe/menu_clip6", menu_clip6[4], 0x60, 0x15c, true) end
    if inside(input, 0x13e, 0x17e, 0x1d8, 0x196) then
        sprite(state, "pe/menu_clip", menu_clip[13], 0x13e, 0x17e, true)
        if input.click then
            sounds.direct(state, "ok")
            state.page = "menu"
        end
    end
    if state.page == "recorded" and input.nav.cancel then
        sounds.direct(state, "cancel")
        state.page = "menu"
    end
end

-- Navigation targets for the current page: the pointer-test rectangles above, in reading order.
local target = navigation.target
local function navigation_page(state)
    local page = state.page
    if page == "controls" then
        local list = {}
        for player = 1, 4 do
            local x = 0xc2 + (player - 1) * 0x8b
            list[#list + 1] = target(x, 0x9c, x + 0x69, 0x9c + 0x11)
            list[#list + 1] = target(x, 0xb6, x + 0x69, 0xb6 + 0x5a)
            for row = 1, 7 do
                local y = 0x11b + (row - 1) * 0x16
                list[#list + 1] = target(x, y - 3, x + 0x69, y + 0xf)
            end
        end
        list[#list + 1] = target(0x195, 0x1b9, 0x195 + 0x9b, 0x1b9 + 0x18)
        list[#list + 1] = target(0x246, 0x1b9, 0x246 + 0x9b, 0x1b9 + 0x18)
        return {page = page, targets = list, locked = state.capture ~= nil or state.name_player > 0}
    elseif page == "recording" then
        return {page = page, locked = state.field ~= nil,
            targets = {target(0xd2, 0xcf, 0x2da, 0xe1), target(0xd2, 0xe8, 0x2da, 0x12e), target(0xd2, 0x135, 0x2da, 0x147),
                target(0x11f, 0x186, 0x132, 0x199), target(0xe7, 0x1a0, 0x182, 0x1b8), target(0x193, 0x1a0, 0x22e, 0x1b8)}}
    elseif page == "recorded" then
        return {page = page, targets = {target(0x13e, 0x17e, 0x1d8, 0x196)}, autofocus = true}
    elseif page == "options" then
        local box = filter_box
        local check = check_box
        local dropdown = target(box.x, box.y, box.x + box.width, box.y + box.height)
        if state.filter_open then
            -- The list: the box (closes it) and one entry per filter, starting on the current one.
            local list, current = {dropdown}, 1
            for index, filter in ipairs(options.available_filters(state.features)) do
                local y = box.y + index * box.height
                list[#list + 1] = target(box.x, y, box.x + box.width, y + box.height)
                if filter == state.options.upscaling_filter then current = index end
            end
            return {page = "options_list", targets = list, default = current + 1}
        end
        local list = {target(check.x, check.y, check.x + check.size + 12 + 8 * 24, check.y + check.size), dropdown}
        -- Same targets/order as options_page: Fullscreen (only with a real window), Show FPS, Rumble.
        if state.features and state.features.window then
            local box2 = fullscreen_box
            list[#list + 1] = target(box2.x, box2.y, box2.x + box2.size + 12 + 8 * #"Fullscreen", box2.y + box2.size)
        end
        local box3 = fps_box
        list[#list + 1] = target(box3.x, box3.y, box3.x + box3.size + 12 + 8 * #"Show FPS", box3.y + box3.size)
        local box4 = rumble_box
        list[#list + 1] = target(box4.x, box4.y, box4.x + box4.size + 12 + 8 * #"Rumble", box4.y + box4.size)
        list[#list + 1] = target(ok_button.x, ok_button.y, ok_button.x + ok_button.width, ok_button.y + ok_button.height)
        list[#list + 1] = target(cancel_button.x, cancel_button.y, cancel_button.x + cancel_button.width,
            cancel_button.y + cancel_button.height)
        return {page = page, targets = list, default = state.options_focus}
    end
    -- Menu targets: Game Start, Network Game, Controls, Recording, Options, and the quit corner
    -- (the web link is mouse/touch-only, as in the original).
    local top = 0xca
    return {page = "menu", remember = true, targets = {target(0x114, top + 0xf, 0x208, top + 0x27), target(0x114, top + 0x2d, 0x208, top + 0x46),
        target(0x114, top + 0x4d, 0x208, top + 0x66), target(0x114, top + 0x6b, 0x208, top + 0x84),
        target(0x114, options_row.top, 0x208, options_row.bottom), target(0, 0x202, 0x3e, 0x217)}}
end

function screen.update(state, flow_input, context)
    state.display = {}
    state.features = flow_input.filters
    local input = flow_input
    if state.page ~= "waiting" then
        input = navigation.apply(state.nav, flow_input, navigation_page(state))
    end
    if state.page == "waiting" then
        -- The Game Start frame: shows the wait image, then the title.
        image(state, "pe/menu_wait", 0, 0, false)
        context.action("game_start")
    elseif state.page == "controls" then
        control_settings(state, input)
    elseif state.page == "recording" then
        recording_page(state, input, context)
    elseif state.page == "recorded" then
        recorded_page(state, input)
    elseif state.page == "options" then
        options_page(state, input)
    else
        menu(state, input, context)
        options_entry(state, input)
    end
    if state.page == "network" then state.page = "menu"; context.action("network") end
    if state.message then text(state, state.message, 10, 530) end
    state.previous_keys = input.keys
    -- The on-screen keyboard follows the text fields.
    local typing = (state.page == "controls" and state.name_player > 0) or (state.page == "recording" and state.field ~= nil)
    if typing ~= state.keyboard then
        state.keyboard = typing
        context.text_input(typing)
    end
    for _, sound in ipairs(sounds.flush(state)) do context.sound(sound.resource, sound.volume, sound.pan) end
    if state.page ~= "waiting" then
        -- The cursor sprite, clamped to stay on screen.
        image(state, "pe/lf2_cursor", math.min(input.pointer_x, 0x307), math.min(input.pointer_y + 2, 0x217), true)
        -- A click in the bottom-left corner closes the game.
        if input.click and input.pointer_x < 0x3f and input.pointer_y >= 0x202 then context.action("quit") end
    end
end

function screen.draw(state, context)
    context.viewport(794, 550, 0, 0, 0)
    for _, command in ipairs(state.display) do
        local kind = command[1]
        if kind == "sprite" then
            context.sprite(command[2], command[3], command[4], command[5], command[6], command[7], command[8])
        elseif kind == "image" then context.image(command[2], command[3], command[4], command[5])
        elseif kind == "fill" then context.fill(command[2], command[3], command[4], command[5], command[6], command[7], command[8])
        -- Entries with a variant are the original's bitmap-font fields; the rest is GDI text.
        elseif command[5] then font.draw(context, command[2], command[3], command[4], command[5])
        else font.gdi(context, command[2], command[3], command[4], command[6], command[7]) end
    end
end

function screen.describe(state)
    local parts = {"launch_page=" .. state.page}
    local settings = state.editing or controls.current()
    for player = 1, 4 do
        local set = settings.sets[player]
        parts[#parts + 1] = string.format("p%d{name=%s device=%d keys=%s%s}", player, settings.names[player],
            set.device, table.concat(set.keys, ","),
            set.device > 0 and " buttons=" .. table.concat(set.buttons, ",") or "")
    end
    if state.capture then parts[#parts + 1] = string.format("capture=%d:%d", state.capture.player, state.capture.row) end
    if state.name_player > 0 then parts[#parts + 1] = "editing_name=" .. state.name_player end
    if state.nav.mode == "focus" then parts[#parts + 1] = "focus=" .. state.nav.page .. ":" .. state.nav.focus end
    parts[#parts + 1] = "source=" .. tostring(settings.source)
    local shown = state.options or options.current()
    parts[#parts + 1] = "unlock_characters=" .. tostring(shown.unlock_characters)
    parts[#parts + 1] = "upscaling_filter=" .. shown.upscaling_filter
    parts[#parts + 1] = "fullscreen=" .. tostring(shown.fullscreen)
    parts[#parts + 1] = "show_fps=" .. tostring(shown.show_fps)
    local current = controls.current()
    parts[#parts + 1] = "record=" .. tostring(state.record and state.record.record or current.record)
    if state.field then parts[#parts + 1] = "field=" .. state.field end
    if state.record then parts[#parts + 1] = "author=" .. state.record.author end
    if state.message then parts[#parts + 1] = "message=" .. state.message end
    return table.concat(parts, " ")
end
return screen
