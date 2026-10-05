-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local collision = {}
local function signed32(value)
    value = value % 4294967296
    return value >= 2147483648 and value - 4294967296 or value
end
local function rectangle(actor, region)
    local x
    if actor.facing_left then
        x = signed32(actor.center_x + actor.x - region.width - region.x)
    else
        x = signed32(region.x + actor.x - actor.center_x)
    end
    return {x = x, y = signed32(region.y + actor.y - actor.center_y),
        width = region.width, height = region.height}
end
function collision.overlaps(first, second)
    -- Strict comparisons: touching edges do not overlap. Preserve 32-bit subtraction.
    return signed32(second.x - first.x) < first.width
       and signed32(first.x - second.x) < second.width
       and signed32(second.y - first.y) < first.height
       and signed32(first.y - second.y) < second.height
end
function collision.can_interact(attacker, defender, defender_cooldown)
    if not attacker.attack_enabled or not defender.body_enabled
       or attacker.attack_cooldown > 0 or defender_cooldown > 0 then return false end
    return collision.overlaps(rectangle(defender, defender.body), rectangle(attacker, attacker.attack))
end
return collision
