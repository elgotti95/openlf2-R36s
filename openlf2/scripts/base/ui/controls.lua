-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local controls = {}

local actions = {"u", "d", "l", "r", "c", "b", "f"}
local key_names = {"up", "down", "left", "right", "attack", "jump", "defend"}
local loaded -- the current settings, for player names
local default_controller = false

-- data/control.txt: 4 x 11 integers, then four names ('`' for a space).
local function read_control_file()
    local text = engine.read_resource("data/control.txt")
    local numbers = {}
    local position = 1
    for _ = 1, 44 do
        local first, last, value = text:find("^%s*(-?%d+)", position)
        assert(first, "data/control.txt: expected 44 integers")
        numbers[#numbers + 1] = tonumber(value)
        position = last + 1
    end
    local sets = {}
    for set = 1, 4 do
        local row = {}
        for column = 0, 10 do row[column] = numbers[(set - 1) * 11 + column + 1] end
        sets[set] = {device = row[0], keys = {row[1], row[2], row[3], row[4], row[5], row[6], row[7]},
            buttons = {row[8], row[9], row[10]}}
    end
    local names = {}
    local rest = text:sub(position)
    for name, after in rest:gmatch("(%S+)()") do
        names[#names + 1] = name:gsub("`", " ")
        position = after
        if #names == 4 then break end
    end
    for index = #names + 1, 4 do names[index] = tostring(index) end
    local tail = rest:sub(position)
    local online, record, after = tail:match("^%s*(-?%d+)%s*(-?%d+)\r?\n()")
    local author, email, info = "", "", ""
    if after then
        local lines = tail:sub(after)
        local first, second, remainder = lines:match("^([^\n]*)\n([^\n]*)\n?(.*)$")
        author = (first or lines):gsub("[ \r\n]+$", "")
        email = (second or ""):gsub("[ \r\n]+$", "")
        info = remainder or ""
    end
    return {sets = sets, names = names, online = tonumber(online), record = tonumber(record) or 0,
        author = author, email = email, info = info}
end

local function integer(value, low, high)
    return type(value) == "number" and value == math.floor(value) and value >= low and value <= high
end

-- The "controls" member of config.json: {players = [{name, device, up, ..., defend, buttons}]}.
local function from_settings(section)
    if type(section) ~= "table" or type(section.players) ~= "table" then return nil end
    local sets, names = {}, {}
    for set = 1, 4 do
        local player = section.players[set]
        if type(player) ~= "table" or not integer(player.device, 0, 4) or type(player.name) ~= "string"
           or #player.name > 10 or type(player.buttons) ~= "table" then
            return nil
        end
        local keys, buttons = {}, {}
        for index, name in ipairs(key_names) do
            if not integer(player[name], 0, 255) then return nil end
            keys[index] = player[name]
        end
        for index = 1, 3 do
            if not integer(player.buttons[index], 0, 31) then return nil end
            buttons[index] = player.buttons[index]
        end
        sets[set] = {device = player.device, keys = keys, buttons = buttons}
        names[set] = player.name
    end
    return {sets = sets, names = names}
end

-- The saved settings from config.json, otherwise data/control.txt; `source`/`problem` explain
-- which and why.
function controls.load(use_default_controller)
    if use_default_controller ~= nil then default_controller = use_default_controller end
    local stored, problem = engine.read_settings()
    local settings = stored and from_settings(stored.controls)
    if settings then
        settings.source = "config"
        local file = read_control_file()
        settings.online, settings.record = file.online, file.record
        settings.author, settings.email, settings.info = file.author, file.email, file.info
    else
        if stored and stored.controls ~= nil then problem = "invalid controls in the configuration" end
        settings = read_control_file()
        settings.source = "control.txt"
        if default_controller then
            -- Console builds default the first player to the first controller until saved.
            settings.sets[1].device = 1
            settings.sets[1].buttons = {0, 1, 2}
            settings.source = "controller default"
        end
    end
    settings.problem = problem
    -- The recording page's values override control.txt once saved.
    local saved = stored and stored.recording
    if type(saved) == "table" then
        if type(saved.enabled) == "boolean" then settings.record = saved.enabled and 1 or 0 end
        for _, field in ipairs({"author", "email", "info"}) do
            if type(saved[field]) == "string" then settings[field] = saved[field]:sub(1, 99) end
        end
    end
    loaded = settings
    return settings
end

-- Saves the recording page's values (record flag, author, e-mail, info) into config.json.
function controls.save_recording(record, author, email, info)
    local document = engine.read_settings()
    if type(document) ~= "table" then document = {} end
    document.version = 1
    document.recording = {enabled = record ~= 0, author = author, email = email, info = info}
    local saved, problem = engine.write_settings(document)
    if not saved then return nil, problem end
    loaded.record, loaded.author, loaded.email, loaded.info = record, author, email, info
    return true
end

local replaced_names
function controls.replace_names(names) replaced_names = names end

-- A deep copy for editing on the Control Settings screen.
function controls.copy(settings)
    local copy = {sets = {}, names = {}, source = settings.source, online = settings.online,
        record = settings.record, author = settings.author, email = settings.email, info = settings.info}
    for set = 1, 4 do
        local original = settings.sets[set]
        copy.sets[set] = {device = original.device, keys = {unpack(original.keys)},
            buttons = {unpack(original.buttons)}}
        copy.names[set] = settings.names[set]
    end
    return copy
end

-- Saves settings into config.json (keeping other members) and makes them current; returns
-- true or nil+message.
function controls.save(settings)
    local document = engine.read_settings()
    if type(document) ~= "table" then document = {} end
    local players = {}
    for set = 1, 4 do
        local source = settings.sets[set]
        local player = {name = settings.names[set], device = source.device,
            buttons = {source.buttons[1], source.buttons[2], source.buttons[3]}}
        for index, name in ipairs(key_names) do player[name] = source.keys[index] end
        players[set] = player
    end
    document.version = 1
    document.controls = {players = players}
    local saved, problem = engine.write_settings(document)
    if not saved then return nil, problem end
    loaded = controls.copy(settings)
    loaded.source = "config"
    return true
end

function controls.current() return loaded end

-- Adds the letters of the held keys of each keyboard set (slots 0-3) and F1-F9 (0x70-0x78).
local function map_keys(settings, input)
    for slot = 0, 3 do
        local set = settings.sets[slot + 1]
        if set.device == 0 then
            local letters = {}
            for index, action in ipairs(actions) do
                if input.keys[set.keys[index]] and not input[slot]:find(action, 1, true) then
                    letters[#letters + 1] = action
                end
            end
            input[slot] = input[slot] .. table.concat(letters)
        else
            -- A joystick set: `device`'s directions and its three chosen buttons; a missing
            -- controller holds nothing.
            local pad = input.pads[set.device]
            if pad then
                local letters = {}
                for index, direction in ipairs({"u", "d", "l", "r"}) do
                    if pad.dirs[direction] and not input[slot]:find(actions[index], 1, true) then letters[#letters + 1] = actions[index] end
                end
                for index = 5, 7 do
                    if pad.buttons[set.buttons[index - 4]] and not input[slot]:find(actions[index], 1, true) then
                        letters[#letters + 1] = actions[index]
                    end
                end
                input[slot] = input[slot] .. table.concat(letters)
            end
        end
    end
    for key = 1, 9 do
        if input.keys[0x6f + key] and not input.functions:find(tostring(key), 1, true) then
            input.functions = input.functions .. tostring(key)
        end
    end
    -- Map controller Start and Back/Select to the original F1 and F5 actions.
    if input.gamepad.s and not input.functions:find("1", 1, true) then
        input.functions = input.functions .. "1"
    end
    if input.gamepad.k and not input.functions:find("5", 1, true) then
        input.functions = input.functions .. "5"
    end
end

-- Parses the frame's raw input: live host frames ("k" + key/mouse/touch/controller state) or
-- shorthand traces ('/' per player slot, "@x_y", "#n", "%x", "^x", "&n_x_y"). Returns per-slot
-- held letters (u d l r c b f), functions, keys, pointer_x/y, button, gamepad, pads, touches,
-- touch_active, filters and fps.
function controls.read(settings, raw)
    local input = {functions = "", keys = {}, button = false, text = "", gamepad = {}, pads = {},
        touches = {}, touch_active = false}
    for slot = 0, 7 do input[slot] = "" end
    if raw:sub(1, 1) == "k" then
        local codes, x, y, button = raw:match("^k([%d,]*) m(%-?%d+),(%-?%d+),([01])")
        codes = codes or raw:sub(2)
        for code in codes:gmatch("%d+") do input.keys[tonumber(code)] = true end
        input.presses = {}
        for code in (raw:match(" p([%d,]*)") or ""):gmatch("%d+") do input.presses[#input.presses + 1] = tonumber(code) end
        for code in (raw:match(" t([%d,]*)") or ""):gmatch("%d+") do input.text = input.text .. string.char(tonumber(code)) end
        for letter in (raw:match(" g(%a*)") or ""):gmatch("%a") do input.gamepad[letter] = true end
        -- " j": each controller as its held directions, ':' and its buttons in hex, comma separated.
        local index = 0
        for entry in ((raw:match(" j([%w:,]*)") or "") .. ","):gmatch("([^,]*),") do
            local directions, mask = entry:match("^(%a*):(%x*)$")
            if directions then
                index = index + 1
                local pad = {dirs = {}, buttons = {}}
                for letter in directions:gmatch(".") do pad.dirs[letter] = true end
                local bits = tonumber(mask, 16) or 0
                for button = 0, 31 do
                    if math.floor(bits / 2 ^ button) % 2 == 1 then pad.buttons[button] = true end
                end
                input.pads[index] = pad
            end
        end
        -- " h": touch flag (0/1), then each held finger's id,x,y, comma separated.
        local touch_flag, touch_list = raw:match(" h([01])([%d:,-]*)")
        if touch_flag then
            input.touch_active = touch_flag == "1"
            for id, tx, ty in touch_list:gmatch("(%d+):(%-?%d+):(%-?%d+)") do
                input.touches[#input.touches + 1] = {id = tonumber(id), x = tonumber(tx), y = tonumber(ty)}
            end
        end
        -- " e": the window's edges in viewport coordinates (live only): left,top,right,bottom.
        local left, top, right, bottom = raw:match(" e(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+)")
        if left then
            input.screen = {left = tonumber(left), top = tonumber(top), right = tonumber(right), bottom = tonumber(bottom)}
        end
        -- Capability letters (live only): x = xBRZ upscaling, w = a toggleable window (Fullscreen).
        local given_filters = raw:match(" f(%a*)") or ""
        input.filters = {xbrz = given_filters:find("x", 1, true) ~= nil, window = given_filters:find("w", 1, true) ~= nil}
        -- " s": measured FPS for Show FPS (live only; traces have no wall-clock time).
        input.fps = tonumber(raw:match(" s(%d+)"))
        if x then
            input.pointer_x, input.pointer_y = tonumber(x), tonumber(y)
            input.button = button == "1"
        end
        map_keys(settings, input)
        return input
    end
    local x, y = raw:match("@(%d+)_(%d+)")
    if x then input.pointer_x, input.pointer_y = tonumber(x), tonumber(y) end
    raw = raw:gsub("@%d+_%d+", "")
    for code in raw:gmatch("#(%d+)") do input.keys[tonumber(code)] = true end
    raw = raw:gsub("#%d+", "")
    for letter in raw:gmatch("%%(%a)") do input.gamepad[letter] = true end
    raw = raw:gsub("%%%a", "")
    for character in raw:gmatch("%^([%w.])") do input.text = input.text .. character end
    raw = raw:gsub("%^[%w.]", "")
    -- "$1u", "$13": controller 1 holds a direction / a button (traces).
    for number, what in raw:gmatch("%$(%d)(%w)") do
        local pad = input.pads[tonumber(number)] or {dirs = {}, buttons = {}}
        input.pads[tonumber(number)] = pad
        if what:match("%d") then pad.buttons[tonumber(what)] = true else pad.dirs[what] = true end
    end
    raw = raw:gsub("%$%d%w", "")
    -- "&N_X_Y": finger N at (X,Y) (trace form of " h"); marks the frame touch-driven.
    for id, tx, ty in raw:gmatch("&(%d+)_(%d+)_(%d+)") do
        input.touch_active = true
        input.touches[#input.touches + 1] = {id = tonumber(id), x = tonumber(tx), y = tonumber(ty)}
    end
    raw = raw:gsub("&%d+_%d+_%d+", "")
    -- "?x"/"?w": trace form of live " fx"/" fw" (xBRZ / toggleable window).
    if raw:find("?x", 1, true) or raw:find("?w", 1, true) then
        input.filters = input.filters or {}
        if raw:find("?x", 1, true) then input.filters.xbrz = true end
        if raw:find("?w", 1, true) then input.filters.window = true end
    end
    raw = raw:gsub("%?x", ""):gsub("%?w", "")
    -- "~N": trace form of live " sN" (fixed FPS; traces have no wall-clock time).
    local fps = raw:match("~(%d+)")
    if fps then input.fps = tonumber(fps) end
    raw = raw:gsub("~%d+", "")
    if raw:find("!", 1, true) then input.button = true end
    raw = raw:gsub("!", "")
    local slot = 0
    for part in (raw .. "/"):gmatch("([^/]*)/") do
        input[slot] = part:gsub("%d", "")
        input.functions = input.functions .. part:gsub("[^%d]", "")
        slot = slot + 1
    end
    -- Raw trace keys act like held keyboard keys.
    map_keys(settings, input)
    return input
end

function controls.name(slot)
    if replaced_names and replaced_names[slot + 1] then return replaced_names[slot + 1] end
    local name = loaded and loaded.names[slot + 1]
    return name or tostring(slot + 1)
end

-- True when no player holds a key and no F-key is down.
function controls.idle(input)
    if input.functions ~= "" then return false end
    for slot = 0, 7 do
        if input[slot] ~= "" then return false end
    end
    return true
end

-- All players' held letters together, for screens that do not tell players apart.
function controls.any(input)
    local letters = {}
    for slot = 0, 7 do letters[#letters + 1] = input[slot] end
    return table.concat(letters)
end

local labels = {[0x20] = {"Space", 10}, [0x0d] = {"Enter", 10}, [0x6b] = {"Keypad: +", 15},
    [0x6d] = {"Keypad: -", 15}, [0x6a] = {"Keypad: *", 15}, [0x6f] = {"Keypad: /", 15},
    [0x6e] = {"Keypad: .", 15}, [0xbd] = {"-", 0}, [0xbb] = {"=", 0}, [0xdb] = {"[", 0},
    [0xdd] = {"]", 0}, [0xba] = {";", 0}, [0xde] = {"'", 0}, [0xdc] = {"\\", 0}, [0xbc] = {",", 0},
    [0xbe] = {".", 0}, [0xbf] = {"/", 0}, [0xc0] = {"`", 0}, [0x11] = {"Ctrl", 7}, [0x10] = {"Shift", 7},
    [0x09] = {"Tab", 5}, [0x08] = {"Backspace", 13}, [0x2d] = {"Insert", 8}, [0x2e] = {"Delete", 8},
    [0x24] = {"Home", 6}, [0x23] = {"End", 5}, [0x21] = {"PageUp", 10}, [0x22] = {"PageDown", 14},
    [0x26] = {"Up", 2}, [0x25] = {"Left", 4}, [0x28] = {"Down", 5}, [0x27] = {"Right", 6},
    [0x14] = {"CapsLock", 16}}
function controls.key_label(code)
    if code >= 0x41 and code <= 0x5a then return string.char(code), 0 end
    if code >= 0x60 and code <= 0x69 then return "Keypad: " .. string.char(code - 0x30), 15 end
    if code >= 0x30 and code <= 0x39 then return string.char(code), 0 end
    local label = labels[code]
    if label then return label[1], label[2] end
    return "none", 8
end

local shifted = {[0xbd] = "_", [0xbb] = "+", [0xdb] = "{", [0xdd] = "}", [0xba] = ":", [0xde] = "\"",
    [0xdc] = "|", [0xbc] = "<", [0xbe] = ">", [0xbf] = "?", [0xc0] = "~", [0x31] = "!", [0x32] = "@",
    [0x33] = "#", [0x34] = "$", [0x35] = "%", [0x36] = "^", [0x37] = "&", [0x38] = "*", [0x39] = "(",
    [0x30] = ")"}
local plain = {[0xbd] = "-", [0xbb] = "=", [0xdb] = "[", [0xdd] = "]", [0xba] = ";", [0xde] = "'",
    [0xdc] = "\\", [0xbc] = ",", [0xbe] = ".", [0xbf] = "/", [0xc0] = "`"}
local keypad = {[0x6b] = "+", [0x6d] = "-", [0x6a] = "*", [0x6f] = "/", [0x6e] = "."}
local navigation = {[0x21] = "9", [0x22] = "3", [0x23] = "1", [0x24] = "7", [0x25] = "4", [0x26] = "8",
    [0x27] = "6", [0x28] = "2"}
function controls.key_character(code, shift)
    if code == 0x20 then return " " end
    if code >= 0x41 and code <= 0x5a then
        return shift and string.char(code) or string.char(code + 0x20)
    end
    if code >= 0x60 and code <= 0x69 then return string.char(code - 0x30) end
    if keypad[code] then return keypad[code] end
    if shift then
        if shifted[code] then return shifted[code] end
    elseif code >= 0x30 and code <= 0x39 then
        return string.char(code)
    elseif plain[code] then
        return plain[code]
    end
    return navigation[code]
end
return controls
