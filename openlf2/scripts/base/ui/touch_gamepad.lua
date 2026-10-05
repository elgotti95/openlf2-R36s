-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- OpenLF2 extension: on-screen touch gamepad for player 1 during a live match. Shows only
-- when the last input was touch-driven; other pages already handle direct taps.
--
-- C++ only reports held fingers in viewport coordinates, plus the window's edges (letterbox
-- bars lie beyond the 794x550 picture); this module owns all hit-testing and draws as an
-- overlay so it can sit in the bars.
local font = require("base/ui/font")
local gamepad = {}

-- Left floating joystick: a finger down in the zone recenters the base; direction comes from
-- the knob's offset past a dead zone (8-way, diagonals set two). Keeps following that finger
-- outside the zone.
-- `run_distance`: running needs a double-tap, not a hold; past this distance the stick fakes
-- that double-tap itself (run_pulse), since a held stick never releases.
-- Position and size come from the configured layout (options.gamepad), measured from the
-- window's edges (`screen`: their viewport coordinates, beyond 0..794 / 0..550 in letterbox
-- bars); distances below are authored for radius 56 and scale with it.
local function build_stick(config, screen, digipad)
    local x, y = screen.left + math.floor(config.left), screen.bottom - math.floor(config.bottom)
    local radius = math.floor(config.radius)
    local scale = radius / 56
    if digipad then
        -- A fixed cross: a finger within a margin of it steers, with 8 directions as on the stick, and
        -- running is the player's own double tap, so there is no run pulse.
        return {zone = {left = x - radius * 1.4, top = y - radius * 1.4, right = x + radius * 1.4, bottom = y + radius * 1.4},
            default_x = x, default_y = y, radius = radius, travel = radius, deadzone = 14 * scale, threshold = 0.4,
            run_distance = math.huge, run_rearm_distance = 0, knob = 0, knob_inner = 0, fixed = true}
    end
    return {zone = {left = screen.left, top = y - 150 * scale, right = x + 205 * scale, bottom = y + 80 * scale},
        default_x = x, default_y = y, radius = radius, travel = 60 * scale,
        deadzone = 14 * scale, threshold = 0.4, run_distance = 51 * scale, run_rearm_distance = 30 * scale,
        knob = math.floor(24 * scale), knob_inner = math.floor(18 * scale)}
end
-- Right action buttons: attack is primary/biggest (thumb rests there); jump/defend are reached
-- by rolling the thumb.
-- Chords: pressing several buttons at once. Each is enabled only while the fighter has a move
-- for it (see `gamepad.set_available`).
local chords = {"da", "dj", "daj"}
local chord_letters = {da = {"f", "c"}, dj = {"f", "b"}, daj = {"f", "b", "c"}}
local chord_labels = {da = "D+A", dj = "D+J", daj = "D+J+A"}
local chord_fill, chord_pressed = {70, 55, 95}, {130, 105, 190}
local function build_buttons(layout, screen)
    local function button(action, label, fill, pressed)
        local config = layout[action]
        local letters = chord_letters[action]
        label = label or chord_labels[action]
        return {action = action, letters = letters, label = label, x = screen.right - math.floor(config.right),
            y = screen.bottom - math.floor(config.bottom), radius = math.floor(config.radius),
            fill = fill, pressed = pressed}
    end
    local list = {button("c", "ATK", {90, 45, 40}, {170, 80, 65}), button("b", "JUMP", {40, 80, 50}, {80, 160, 100}),
        button("f", "DEF", {40, 55, 90}, {75, 105, 175})}
    for _, button_action in ipairs(chords) do list[#list + 1] = button(button_action, nil, chord_fill, chord_pressed) end
    return list
end
local outline = {18, 18, 22}
local disabled_fill = {34, 34, 38}

-- The run pulse: release/press/release/press, mimicking a human double-tap within the dash
-- window. Each step holds two frames since input is only re-read every other frame.
local run_pulse_steps = {false, false, true, true, false, false, true, true}

local default_screen = {left = 0, top = 0, right = 794, bottom = 550}

-- Rebuilds the stick and buttons when the window's edges moved (resize, fullscreen).
local function fit(state, screen)
    local old = state.screen
    if old and old.left == screen.left and old.top == screen.top and old.right == screen.right
       and old.bottom == screen.bottom then
        return
    end
    state.screen = screen
    state.stick = build_stick(state.digipad and state.layout.dpad or state.layout.stick, screen, state.digipad)
    local pause = state.layout.pause
    state.tolerance = state.layout.touch.tolerance
    state.pause = {x = screen.right - math.floor(pause.right), y = screen.top + math.floor(pause.top),
        radius = math.floor(pause.radius)}
    state.buttons = build_buttons(state.layout, screen)
    if not state.finger then
        state.base_x, state.base_y = state.stick.default_x, state.stick.default_y
        state.knob_x, state.knob_y = state.base_x, state.base_y
    end
end

function gamepad.create(layout, digipad)
    local state = {layout = layout, digipad = digipad == true, held = {}, available = {}, visible = false, run_pulse_step = 0}
    fit(state, default_screen)
    return state
end

local function clamp(value, low, high) return math.max(low, math.min(high, value)) end
local function inside_zone(zone, x, y) return x >= zone.left and x <= zone.right and y >= zone.top and y <= zone.bottom end

-- Which chord buttons ("da", "dj", "daj") are enabled; the others cannot be pressed.
function gamepad.set_available(state, available) state.available = available end

-- state: from `create`. input: the frame's input; pass touch_active=false to release the held
-- finger and hide (paused/replaying/other screens).
-- The button (or the pause button) a finger presses: the one whose edge is nearest, as long as
-- the finger is within `tolerance` pixels of it, so a slightly missed press still counts.
local function target_at(state, touch, mode)
    local best, best_gap
    local function consider(target)
        local gap = math.sqrt((touch.x - target.x) ^ 2 + (touch.y - target.y) ^ 2) - target.radius
        if gap <= state.tolerance and (not best_gap or gap < best_gap) then best, best_gap = target, gap end
    end
    if mode ~= "full" then consider(state.pause) end
    if mode ~= "pause" then
        for _, button in ipairs(state.buttons) do consider(button) end
    end
    return best
end

-- `mode`: "full" (default: stick and buttons), "match" (the same plus the pause button) or
-- "pause" (only the pause button is live: the match is paused or replaying).
-- Returns held letters ("udlrcbf" subset), or "" while hidden, and whether the pause button is
-- held; a run pulse briefly overrides l/r on its own.
function gamepad.update(state, input, mode)
    mode = mode or "full"
    fit(state, input.screen or default_screen)
    local stick, buttons = state.stick, state.buttons
    local screen = state.screen
    state.visible = input.touch_active == true
    if not state.visible then
        state.finger, state.held = nil, {}
        state.base_x, state.base_y = stick.default_x, stick.default_y
        state.knob_x, state.knob_y = stick.default_x, stick.default_y
        return "", false
    end
    local touches = input.touches or {}
    local pressed = {}
    for _, touch in ipairs(touches) do
        local target = target_at(state, touch, mode)
        if target then pressed[target] = true end
    end
    local pause_held = pressed[state.pause] == true
    state.pause_held, state.mode = pause_held, mode
    if mode == "pause" then
        state.finger, state.held = nil, {}
        state.base_x, state.base_y = stick.default_x, stick.default_y
        state.knob_x, state.knob_y = stick.default_x, stick.default_y
        state.run_armed, state.run_pulse = nil, nil
        return "", pause_held
    end
    local by_id = {}
    for _, touch in ipairs(touches) do by_id[touch.id] = touch end

    local owner = state.finger and by_id[state.finger]
    if not owner then
        state.finger = nil
        for _, touch in ipairs(touches) do
            if inside_zone(stick.zone, touch.x, touch.y) then
                state.finger, owner = touch.id, touch
                break
            end
        end
        if owner and not stick.fixed then
            state.base_x = clamp(owner.x, screen.left + stick.radius, screen.right - stick.radius)
            state.base_y = clamp(owner.y, screen.top + stick.radius, screen.bottom - stick.radius)
        end
    end
    local held = {}
    if owner then
        local dx, dy = owner.x - state.base_x, owner.y - state.base_y
        local distance = math.sqrt(dx * dx + dy * dy)
        if distance > 0 then
            local travel = math.min(distance, stick.travel)
            state.knob_x, state.knob_y = state.base_x + dx / distance * travel, state.base_y + dy / distance * travel
        else
            state.knob_x, state.knob_y = state.base_x, state.base_y
        end
        if distance >= stick.deadzone then
            if dx / distance > stick.threshold then held.r = true end
            if dx / distance < -stick.threshold then held.l = true end
            if dy / distance > stick.threshold then held.d = true end
            if dy / distance < -stick.threshold then held.u = true end
        end
        -- Crossing run_distance arms a run pulse for l/r; returning past run_rearm_distance
        -- re-arms it (short of the edge, to avoid jitter).
        local run_letter = held.r and "r" or (held.l and "l" or nil)
        if run_letter and distance >= stick.run_distance then
            if state.run_armed ~= run_letter then
                state.run_armed, state.run_pulse, state.run_pulse_step = run_letter, run_pulse_steps, 1
            end
        elseif distance <= stick.run_rearm_distance then
            state.run_armed = nil
        end
    else
        state.base_x, state.base_y = stick.default_x, stick.default_y
        state.knob_x, state.knob_y = stick.default_x, stick.default_y
        state.run_armed, state.run_pulse = nil, nil
    end
    if state.run_pulse then
        held[state.run_armed] = state.run_pulse[state.run_pulse_step]
        state.run_pulse_step = state.run_pulse_step + 1
        if state.run_pulse_step > #state.run_pulse then state.run_pulse = nil end
    end

    -- Any finger on a button holds it; multiple fingers can hold multiple buttons plus the stick.
    -- A disabled chord still catches fingers near it but does nothing.
    for _, button in ipairs(buttons) do
        if pressed[button] and (not button.letters or state.available[button.action]) then
            held[button.action] = true
            for _, letter in ipairs(button.letters or {}) do held[letter] = true end
        end
    end
    state.held = held
    local letters = {}
    for _, letter in ipairs({"u", "d", "l", "r", "c", "b", "f"}) do
        if held[letter] then letters[#letters + 1] = letter end
    end
    return table.concat(letters), pause_held
end

-- A circle approximated by horizontal strips (no rounded/alpha-blended primitive exists),
-- matching the game's chunky pixel look.
local circle_rows = {0.34, 0.63, 0.83, 0.96, 1, 1, 0.96, 0.83, 0.63, 0.34}
local function disc(context, cx, cy, radius, red, green, blue)
    -- Draw coordinates must be integers, so the finger-driven centre is rounded once here.
    cx, cy = math.floor(cx + 0.5), math.floor(cy + 0.5)
    local step = radius * 2 / #circle_rows
    for index, half_fraction in ipairs(circle_rows) do
        local top = cy - radius + (index - 1) * step
        local half = math.floor(half_fraction * radius)
        if half > 0 then context.fill(cx - half, math.floor(top), half * 2, math.ceil(step), red, green, blue) end
    end
end

-- The small pause button (two bars) in the top right corner.
local function draw_pause(state, context)
    local pause = state.pause
    local color = state.pause_held and {120, 120, 130} or {60, 60, 68}
    disc(context, pause.x, pause.y, pause.radius, outline[1], outline[2], outline[3])
    disc(context, pause.x, pause.y, pause.radius - 3, color[1], color[2], color[3])
    local bar = math.max(2, math.floor(pause.radius / 4))
    local height = math.floor(pause.radius * 0.9)
    local top = pause.y - math.floor(height / 2)
    context.fill(pause.x - bar - 1, top, bar, height, 235, 235, 240)
    context.fill(pause.x + 2, top, bar, height, 235, 235, 240)
end

-- The digipad: a cross whose held arms light up (two arms for a diagonal).
local function draw_digipad(state, context, base_color, held_color)
    local x, y, length = state.stick.default_x, state.stick.default_y, state.stick.radius
    local half = math.floor(length * 0.3)
    local function cross(grow, color)
        context.fill(x - length - grow, y - half - grow, (length + grow) * 2, (half + grow) * 2, color[1], color[2], color[3])
        context.fill(x - half - grow, y - length - grow, (half + grow) * 2, (length + grow) * 2, color[1], color[2], color[3])
    end
    cross(3, outline)
    cross(0, base_color)
    local held = state.held
    if held.r then context.fill(x, y - half, length, half * 2, held_color[1], held_color[2], held_color[3]) end
    if held.l then context.fill(x - length, y - half, length, half * 2, held_color[1], held_color[2], held_color[3]) end
    if held.d then context.fill(x - half, y, half * 2, length, held_color[1], held_color[2], held_color[3]) end
    if held.u then context.fill(x - half, y - length, half * 2, length, held_color[1], held_color[2], held_color[3]) end
end

-- Call only while state.visible; the caller hides it while paused or off the match screen.
function gamepad.draw(state, context)
    if not state.visible then return end
    local stick, buttons = state.stick, state.buttons
    context.overlay(true)
    if state.mode ~= "full" then draw_pause(state, context) end
    if state.mode == "pause" then
        context.overlay(false)
        return
    end
    local engaged = state.finger ~= nil
    local base_color = engaged and {55, 90, 130} or {48, 48, 56}
    local knob_color = engaged and {150, 190, 235} or {95, 95, 105}
    if stick.fixed then
        draw_digipad(state, context, base_color, knob_color)
    else
        disc(context, state.base_x, state.base_y, stick.radius, outline[1], outline[2], outline[3])
        disc(context, state.base_x, state.base_y, stick.radius - 6, base_color[1], base_color[2], base_color[3])
        disc(context, state.knob_x, state.knob_y, stick.knob, outline[1], outline[2], outline[3])
        disc(context, state.knob_x, state.knob_y, stick.knob_inner, knob_color[1], knob_color[2], knob_color[3])
    end
    for _, button in ipairs(buttons) do
        local disabled = button.letters and not state.available[button.action]
        local color = disabled and disabled_fill or (state.held[button.action] and button.pressed) or button.fill
        disc(context, button.x, button.y, button.radius, outline[1], outline[2], outline[3])
        disc(context, button.x, button.y, button.radius - 6, color[1], color[2], color[3])
        font.draw(context, button.label, button.x - #button.label * 4, button.y - 8, nil, disabled and 0x606060 or nil)
    end
    context.overlay(false)
end

return gamepad
