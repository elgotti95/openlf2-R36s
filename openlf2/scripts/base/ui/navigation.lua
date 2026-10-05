-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- Keyboard/controller navigation for the launch screen's mouse-driven pages, which use fixed
-- default controls (arrows/d-pad move, Enter/A confirms, Escape/B back) since they configure
-- the key bindings themselves; mouse/touch use the pointer as before.
-- A page lists clickable targets; moving focuses the neighbouring one, confirming clicks its
-- centre. Moving the mouse hands the pointer back.
local navigation = {}

-- Directional keys repeat while held: after 15 frames, then every 4 (33 ms frames).
local repeat_delay, repeat_interval = 15, 4
local direction_keys = {u = 0x26, d = 0x28, l = 0x25, r = 0x27}
local directions = {"u", "d", "l", "r"}

-- A clickable area: the pointer is parked at its centre.
function navigation.target(left, top, right, bottom)
    return {left = left, top = top, right = right, bottom = bottom,
        x = math.floor((left + right) / 2), y = math.floor((top + bottom) / 2)}
end

function navigation.create()
    return {mode = "pointer", focus = 1, page = nil, held = {}, suppressed = {}, first_x = nil, first_y = nil,
        raw_x = nil, raw_y = nil, moved = false, remembered = {}}
end

-- The default controls' held state, from the keyboard and the controller.
local function held_controls(input)
    local pad, keys = input.gamepad or {}, input.keys
    local held = {ok = keys[0x0d] or pad.a or pad.s, cancel = keys[0x1b] or pad.b or pad.k}
    for _, direction in ipairs(directions) do held[direction] = keys[direction_keys[direction]] or pad[direction] end
    return held
end

-- Fresh presses; directions repeat while held.
local function edges(state, input)
    local held = held_controls(input)
    local fresh = {}
    for _, name in ipairs({"ok", "cancel", "u", "d", "l", "r"}) do
        if held[name] then
            local frames = (state.held[name] or 0) + 1
            state.held[name] = frames
            local repeating = direction_keys[name] and frames > repeat_delay
                and (frames - repeat_delay) % repeat_interval == 0
            if frames == 1 or repeating then fresh[name] = true end
        else
            state.held[name] = nil
        end
    end
    return fresh
end

local function inside(target, x, y)
    return x >= target.left and x <= target.right and y >= target.top and y <= target.bottom
end

-- The neighbouring target in a direction: the best-aligned target in the nearest row/column
-- beyond the focused one (rows told apart at 20px).
local function neighbour(targets, from, direction)
    local origin = targets[from]
    local best, best_score
    for index, target in ipairs(targets) do
        if index ~= from then
            local dx, dy = target.x - origin.x, target.y - origin.y
            local along, across
            if direction == "u" then along, across = -dy, math.abs(dx)
            elseif direction == "d" then along, across = dy, math.abs(dx)
            elseif direction == "l" then along, across = -dx, math.abs(dy)
            else along, across = dx, math.abs(dy) end
            if along > 4 then
                local score = math.floor(along / 20) * 100000 + across
                if not best_score or score < best_score then best, best_score = index, score end
            end
        end
    end
    return best
end

-- The target under the pointer, else the nearest, else the page's default.
local function reveal(state, targets, input, default)
    if not state.moved then return default end
    local nearest, nearest_distance
    for index, target in ipairs(targets) do
        if inside(target, input.pointer_x, input.pointer_y) then return index end
        local distance = (target.x - input.pointer_x) ^ 2 + (target.y - input.pointer_y) ^ 2
        if not nearest_distance or distance < nearest_distance then nearest, nearest_distance = index, distance end
    end
    return nearest or default
end

-- state: from `create`. input: the frame's input. spec: page (name), targets, default (index,
-- 1), remember (keep focus across visits), locked (text field owns keys), autofocus (start on
-- default even with mouse last used).
-- Returns input with the focused target's pointer/click (keyboard/controller only), `keys`
-- minus navigation keys until released, `nav` fresh-press flags, `locked`, `focused` (index).
function navigation.apply(state, input, spec)
    local page, targets, default = spec.page, spec.targets, spec.default or 1
    local locked = spec.locked
    local view = {}
    for key, value in pairs(input) do view[key] = value end
    view.keys = {}
    for code, down in pairs(input.keys) do
        if down and not state.suppressed[code] then view.keys[code] = true end
    end
    for code in pairs(state.suppressed) do
        if not input.keys[code] then state.suppressed[code] = nil end
    end
    -- A key taken by navigation stays hidden from the page until it is released.
    local function take(code)
        if input.keys[code] then state.suppressed[code] = true end
        view.keys[code] = nil
    end
    local fresh = edges(state, input)
    view.nav = fresh
    view.locked = locked == true

    -- The mouse or a finger moved or clicked: the pointer is in charge again.
    local x, y = input.pointer_x, input.pointer_y
    if state.first_x == nil then state.first_x, state.first_y = x, y end
    if state.raw_x ~= nil and (x ~= state.raw_x or y ~= state.raw_y) then
        state.mode = "pointer"
        if x ~= state.first_x or y ~= state.first_y then state.moved = true end
    end
    if input.click then state.mode, state.moved = "pointer", true end
    state.raw_x, state.raw_y = x, y
    if state.page ~= page then
        if state.page then state.remembered[state.page] = state.focus end
        state.page = page
        state.focus = spec.remember and state.remembered[page] or default
        if spec.autofocus then state.mode = "focus" end
    end
    if locked or #targets == 0 then return view end

    local moving = fresh.u or fresh.d or fresh.l or fresh.r
    local confirming = fresh.ok
    if state.mode == "pointer" then
        if not (moving or confirming) then return view end
        state.mode = "focus"
        state.focus = reveal(state, targets, input, state.focus)
        -- Confirming while the pointer rests on a target clicks it; any other first press just
        -- reveals focus.
        if not (confirming and state.moved and inside(targets[state.focus], x, y)) then
            moving, confirming = false, false
            take(0x0d)
            for _, code in pairs(direction_keys) do take(code) end
        end
    end
    state.focus = math.min(math.max(state.focus, 1), #targets)
    for _, direction in ipairs(directions) do
        if moving and fresh[direction] then
            state.focus = neighbour(targets, state.focus, direction) or state.focus
            take(direction_keys[direction])
        end
    end
    local target = targets[state.focus]
    view.pointer_x, view.pointer_y = target.x, target.y
    view.click = false
    if confirming then
        view.click, view.button = true, true
        take(0x0d)
    end
    if fresh.cancel then take(0x1b) end
    view.focused = state.focus
    return view
end
return navigation
