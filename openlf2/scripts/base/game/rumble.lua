-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- OpenLF2 extension, not in the original: controller/phone haptic feedback on a landed hit.
-- Queues by victim item index, keeping the strongest request per victim per frame;
-- base/ui/match_screen resolves the owning local player and calls context.rumble.
local rumble = {}

function rumble.queue(state, item_index, strength)
    state.rumble_queue = state.rumble_queue or {}
    if strength > (state.rumble_queue[item_index] or 0) then state.rumble_queue[item_index] = strength end
end

function rumble.flush(state)
    local output = {}
    for item_index, strength in pairs(state.rumble_queue or {}) do
        output[#output + 1] = {item_index = item_index, strength = strength}
    end
    state.rumble_queue = nil
    return output
end

return rumble
