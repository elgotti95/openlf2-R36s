-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local object_data = {}
local cache = {}
local function canonical(path)
    path = path:gsub("\\", "/"):lower()
    assert(path:match("^[a-z0-9_./-]+$"), "unsupported original resource path: " .. path)
    return path
end
function object_data.load(path)
    path = canonical(path)
    local data = cache[path]
    if not data then
        data = engine.read_object_data(path)
        for _, sheet in ipairs(data.sheets) do sheet.resource = canonical(sheet.path) end
        cache[path] = data
    end
    return data
end
function object_data.picture(data, frame_id, offset)
    local frame = data.frames[frame_id]
    if not frame then return nil end
    local picture = frame.picture + (offset or 0)
    for _, sheet in ipairs(data.sheets) do
        local cell = picture - sheet.first_picture
        if cell >= 0 and cell < sheet.columns * sheet.rows then
            local column, row = cell % sheet.columns, math.floor(cell / sheet.columns)
            return sheet.resource, {column * (sheet.cell_width + 1), row * (sheet.cell_height + 1),
                sheet.cell_width, sheet.cell_height}
        end
    end
    return nil
end
return object_data
