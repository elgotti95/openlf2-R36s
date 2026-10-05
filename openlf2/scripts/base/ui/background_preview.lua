-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- Developer preview for comparing background layout with the original; not an LF2 screen.
-- Left/right scroll the camera, up/down cycle entries, Escape returns to the title.
local catalog = require("base/game/catalog")
local background = require("base/game/background")
local navigation = require("base/ui/input")
local controls = require("base/ui/controls")
local font = require("base/ui/font")
local preview = {}
local scroll_step = 8
local function show(state, index)
    state.index = index
    state.entry = state.backgrounds[index]
    state.data = background.load(state.entry.path)
    state.view = background.create_state(state.data)
    state.camera = 0
end
function preview.create()
    local state = {backgrounds = catalog.backgrounds(), input = navigation.create()}
    show(state, 1)
    return state
end
function preview.update(state, held, context)
    local limit = math.max(0, (state.data.width or 794) - 794)
    local any = controls.any(held)
    if any:find("l", 1, true) then state.camera = math.max(0, state.camera - scroll_step) end
    if any:find("r", 1, true) then state.camera = math.min(limit, state.camera + scroll_step) end
    local action = navigation.sample(state.input, held)
    if action == "u" then show(state, (state.index - 2) % #state.backgrounds + 1)
    elseif action == "d" then show(state, state.index % #state.backgrounds + 1)
    elseif action == "b" then context.action("title") end
end
function preview.draw(state, context)
    context.viewport(794, 550, 0, 0, 0)
    background.paint(context, state.data, state.view, state.camera)
    font.draw(context, "bg " .. state.entry.id .. ": " .. (state.data.name or "?") ..
        "  camera " .. state.camera, 8, 8)
end
return preview
