-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- Music controls and host requests follow the original game's music routines.
local music = {enabled = true, selected = nil, master = 100, queue = {}, sent_volume = nil}

music.tracks = {"bgm/main.wma", "bgm/stage1.wma", "bgm/stage2.wma", "bgm/stage3.wma", "bgm/stage4.wma",
    "bgm/stage5.wma", "bgm/boss1.wma", "bgm/boss2.wma"}

local function canonical(path) return (path:gsub("\\", "/"):lower()) end

function music.play(path)
    if not music.enabled then return end
    music.queue[#music.queue + 1] = {"play", canonical(path)}
    music.stopped = false
end
function music.play_selected()
    if music.selected then music.play(music.selected) end
end
function music.stop()
    if music.stopped then return end
    music.queue[#music.queue + 1] = {"stop"}
    music.stopped = true
end
function music.resume()
    music.queue[#music.queue + 1] = {"resume"}
    music.stopped = false
end

function music.change_volume(step)
    music.master = math.max(0, math.min(100, music.master + step))
end

function music.flush(context)
    local volume = music.master == 0 and -10000 or music.master * 34 - 3900
    if volume ~= music.sent_volume then
        context.music("volume", volume)
        music.sent_volume = volume
    end
    for _, request in ipairs(music.queue) do context.music(request[1], request[2]) end
    music.queue = {}
end
return music
