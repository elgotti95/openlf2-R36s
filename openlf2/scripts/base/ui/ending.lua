-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local screen = {}

local sheet = "pe/ending"
local frames = {[0] = {0, 0, 402, 66}, {0, 67, 402, 91}, {0, 159, 402, 156}, {0, 316, 419, 169},
    {0, 486, 419, 65}, {403, 53, 15, 13}}

function screen.create(difficulty)
    return {difficulty = difficulty, page = 0, reveal = 0, closing = 0, blink = 0, display = {},
        previous_attack = {true, true, true, true, true, true, true, true}}
end

local function cdiv(a, b)
    local q = a / b
    if q >= 0 then return math.floor(q) end
    return math.ceil(q)
end

function screen.update(state, held, context)
    local display = {}
    state.display = display
    state.blink = (state.blink + 1) % 10
    if state.difficulty == 1 or state.difficulty == 2 then
        if state.page == 1 then state.page = 2 end
    elseif state.page == 0 then
        state.page = 1
    end
    local frame = frames[state.page]
    local x, y = cdiv(800 - frame[3], 2), cdiv(520 - frame[4], 2)
    display[#display + 1] = {"sprite", frame, x, y}
    local fresh = false
    for player = 0, 7 do
        local attack = (held[player] or ""):find("c", 1, true) ~= nil
        if attack and not state.previous_attack[player + 1] then fresh = true end
        state.previous_attack[player + 1] = attack
    end
    local row = y
    local bars
    if state.reveal < 13 then
        state.reveal = state.reveal + 1
        for _ = 1, 13 do
            display[#display + 1] = {"fill", 0, row, 794, 13 - state.reveal}
            row = row + 13
        end
        bars = state.closing
    else
        bars = state.closing
        if bars == 0 then
            if fresh then
                bars = 1
                state.closing = bars
            end
        elseif bars > 0 then
            for _ = 1, 13 do
                display[#display + 1] = {"fill", 0, row, 794, bars}
                row = row + 13
            end
            bars = bars + 1
            state.closing = bars
            if bars >= 13 then
                state.page = state.page + 1
                state.reveal, bars, state.closing = 0, 0, 0
            end
        end
    end
    if state.blink < 5 and state.reveal == 13 and bars == 0 then
        display[#display + 1] = {"sprite", frames[5], x + frame[3], y + frame[4]}
    end
    if state.page == 5 then context.action("title") end
end

function screen.draw(state, context)
    context.viewport(794, 550, 0, 0, 0)
    for _, command in ipairs(state.display) do
        if command[1] == "sprite" then context.sprite(sheet, command[2], command[3], command[4], false)
        else context.fill(command[2], command[3], command[4], command[5], 0, 0, 0) end
    end
end

function screen.describe(state)
    return string.format("ending_page=%d reveal=%d closing=%d", state.page, state.reveal, state.closing)
end
return screen
