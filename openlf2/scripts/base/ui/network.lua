-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local transport = require("base/game/network")
local controls = require("base/ui/controls")
local font = require("base/ui/font")
local sounds = require("base/game/sounds")
local navigation = require("base/ui/navigation")
local screen = {}
local frames = {[1] = {0, 41, 496, 80}, [3] = {0, 247, 304, 126}, [4] = {0, 376, 363, 123},
    [5] = {500, 42, 291, 27}, [6] = {500, 72, 291, 27}, [10] = {460, 203, 334, 108},
    [11] = {460, 313, 334, 108}, [12] = {643, 426, 151, 26}, [13] = {489, 426, 151, 26},
    [14] = {490, 462, 304, 38}}
local function inside(input, left, top, right, bottom)
    return input.pointer_x >= left and input.pointer_x <= right and input.pointer_y >= top and input.pointer_y <= bottom
end
function screen.create(options)
    return {session = transport.create(options), page = "choice", address = "", previous_keys = {},
        nav = navigation.create(), keyboard = false,
        background = (options.menu_seed or 0) % 13 + 1, pointer_x = 0, pointer_y = 0,
        bind = options.network_bind or "0.0.0.0", started = engine.network_time()}
end
function screen.begin(state, host, address)
    state.message = nil
    if transport.start(state.session, host, address) then state.page = "waiting"
    else state.message = state.session.error end
    state.started = engine.network_time()
end
-- The clickable areas for keyboard and controller navigation (base/ui/navigation); the join
-- page starts on its Connect button so Enter connects at once, as it always did.
local function navigation_spec(page)
    local target = navigation.target
    if page == "waiting" then return {page = page, targets = {target(0x142, 0x169, 0x1d8, 0x182)}} end
    if page == "join" then
        return {page = page, autofocus = true,
            targets = {target(0xef, 0x165, 0x185, 0x17e), target(0x19b, 0x165, 0x231, 0x17e)}}
    end
    return {page = page, targets = {target(0x104, 0x112, 0x223, 0x12c), target(0x104, 0x131, 0x223, 0x14a),
        target(0x104, 0x150, 0x223, 0x169)}}
end
function screen.update(state, flow_input, context)
    local input = navigation.apply(state.nav, flow_input, navigation_spec(state.page))
    state.pointer_x, state.pointer_y = input.pointer_x, input.pointer_y
    local cancel = input.nav.cancel
    if state.page == "waiting" then
        cancel = cancel or input.click and inside(input, 0x142, 0x169, 0x1d8, 0x182)
        if not cancel then
            local ready, problem = transport.poll(state.session)
            if ready then context.action("network_ready")
            elseif problem then state.page, state.message = "choice", problem end
        end
    elseif state.page == "join" then
        for code = 0, 255 do
            if input.keys[code] and not state.previous_keys[code] then
                if code == 8 then state.address = state.address:sub(1, -2)
                else
                    local character = controls.key_character(code, false)
                    if character and character:match("^[%d.]$") and #state.address < 15 then state.address = state.address .. character end
                end
            end
        end
        -- Text a soft keyboard delivers without key events.
        for character in input.text:gmatch("[%d.]") do
            if #state.address < 15 then state.address = state.address .. character end
        end
        cancel = cancel or input.click and inside(input, 0x19b, 0x165, 0x231, 0x17e)
        -- Enter connects wherever the focus is (the raw keys: navigation may have taken it).
        if not cancel and (flow_input.keys[13] and not state.previous_keys[13]
           or input.click and inside(input, 0xef, 0x165, 0x185, 0x17e)) then
            screen.begin(state, false, state.address)
        end
    else
        cancel = cancel or input.click and inside(input, 0x104, 0x150, 0x223, 0x169)
        if input.click and inside(input, 0x104, 0x112, 0x223, 0x12c) then
            sounds.direct(state, "ok")
            screen.begin(state, true, state.bind)
        elseif input.click and inside(input, 0x104, 0x131, 0x223, 0x14a) then
            sounds.direct(state, "ok")
            state.page = "join"
        end
    end
    if cancel then
        transport.close(state.session)
        sounds.direct(state, "cancel")
        if state.page == "choice" then context.action("launch") else state.page = "choice" end
    end
    state.previous_keys = flow_input.keys
    -- The on-screen keyboard follows the address field.
    local typing = state.page == "join"
    if typing ~= state.keyboard then
        state.keyboard = typing
        context.text_input(typing)
    end
    for _, sound in ipairs(sounds.flush(state)) do context.sound(sound.resource, sound.volume, sound.pan) end
end
function screen.draw(state, context)
    local function sprite(frame, x, y) context.sprite("pe/menu_clip", frames[frame], x, y, true) end
    context.viewport(794, 550, 16, 32, 108)
    context.image("pe/menu_back" .. state.background, 0, 0, true)
    sprite(1, 0x9b, 0x69)
    sprite(3, 0xfd, 0xde)
    sprite(14, 0xfd, 0x14f)
    -- The original writes " Your IP Address: <address>" here on an opaque box, which also hides
    -- the art's own label; OpenLF2 has no address to show, so it shows its TCP port instead.
    font.gdi(context, " Your TCP port: " .. state.session.port, 0x121, 0xfb, 0xffffff, 0x001e50)
    if state.page == "waiting" then
        sprite(state.session.host and 10 or 11, 0xec, 0x122)
        sprite(12, 0x142, 0x169)
        local count = math.floor((engine.network_time() - state.started) / 150) % 14
        for index = 0, count - 1 do context.fill(0x119 + index * 20, 0x156, 5, 12, 87, 127, 215) end
    elseif state.page == "join" then
        sprite(4, 0xdb, 0x10c)
        sprite(13, 0xef, 0x165)
        sprite(12, 0x19b, 0x165)
        font.gdi(context, state.address .. "_", 0x153, 0x147, 0xffffff, 0x001e50)
    else
        local input = {pointer_x = state.pointer_x, pointer_y = state.pointer_y}
        if inside(input, 0x104, 0x112, 0x223, 0x12c) then sprite(5, 0x103, 0x112) end
        if inside(input, 0x104, 0x131, 0x223, 0x14a) then sprite(6, 0x103, 0x130) end
        if inside(input, 0x104, 0x150, 0x223, 0x169) then sprite(12, 0x149, 0x150) end
    end
    if state.message then font.gdi(context, state.message:sub(1, 94), 10, 510) end
    context.image("pe/lf2_cursor", math.min(state.pointer_x, 0x307), math.min(state.pointer_y + 2, 0x217), true)
end
function screen.describe(state)
    return "network_page=" .. state.page .. " phase=" .. state.session.phase .. (state.message and " error=" .. state.message or "")
end
return screen
