-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local input = {}
local priority = {"u", "d", "r", "l", "c", "b", "f"}
function input.create() return {latched = {}} end
-- held: the frame's input from base/ui/controls. Returns one letter or "".
function input.sample(state, held)
    local fresh = {}
    for slot = 0, 7 do
        local keys = held[slot] or ""
        local selected
        for _, key in ipairs(priority) do
            if keys:find(key, 1, true) then selected = key; break end
        end
        if not selected then
            state.latched[slot] = false
        else
            if not state.latched[slot] then fresh[selected] = true end
            state.latched[slot] = true
        end
    end
    for _, key in ipairs(priority) do
        if fresh[key] then return key end
    end
    return ""
end
return input
