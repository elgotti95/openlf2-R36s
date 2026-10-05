-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local font = {}
-- `tint`: 0xRRGGBB multiplied into the glyph colors (nil leaves them).
function font.draw(context, text, x, y, variant, tint)
    assert(#text <= 128, "text line exceeds font limit")
    local origin = x
    for position = 1, #text do
        local code = text:byte(position)
        if code == 10 then x = origin; y = y + 16
        else
            context.sprite("pe/words" .. (variant or 0),
                {(code % 16) * 16, math.floor(code / 16) * 16 + 1, 8, 16}, x, y, true, false, false, tint)
            x = x + 8
        end
    end
end

-- Approximate GDI text with trimmed WORDS0 glyphs. The System font is proportional; these
-- measured widths keep credits, time and labels within their original bounds.
local space_advance = 4
local glyph_spacing = -1
local gdi_widths

local function u16(bytes, offset) return bytes:byte(offset + 1) + bytes:byte(offset + 2) * 256 end
local function u32(bytes, offset) return u16(bytes, offset) + u16(bytes, offset + 2) * 65536 end

-- Reads the uncompressed BMP the engine returns and yields a function telling whether the pixel
-- (x, y), counted from the top, is ink (not the RGB-black color key).
local function ink_reader(bytes)
    local header = 14
    local pixels, width = u32(bytes, 10), u32(bytes, header + 4)
    local height = u32(bytes, header + 8)
    local top_down = height >= 0x80000000
    if top_down then height = 0x100000000 - height end
    local bits = u16(bytes, header + 14)
    local colors = u32(bytes, header + 32)
    if colors == 0 and bits <= 8 then colors = 2 ^ bits end
    local palette = header + u32(bytes, header)
    local stride = math.floor((width * bits + 31) / 32) * 4
    local function black(offset) return bytes:byte(offset + 1) == 0 and bytes:byte(offset + 2) == 0 and bytes:byte(offset + 3) == 0 end
    return function(x, y)
        if x >= width or y >= height then return false end
        local row = pixels + (top_down and y or height - 1 - y) * stride
        if bits >= 24 then return not black(row + x * bits / 8) end
        local per_byte = 8 / bits
        local value = bytes:byte(row + math.floor(x / per_byte) + 1)
        local shift = (per_byte - 1 - x % per_byte) * bits
        local index = math.floor(value / 2 ^ shift) % 2 ^ bits
        return index < colors and not black(palette + index * 4)
    end
end

-- Per character code: the first ink column and the ink width within the 8x16 cell.
local function measure()
    local ink = ink_reader(engine.read_resource("pe/words0"))
    gdi_widths = {}
    for code = 0, 255 do
        local cell_x, cell_y = (code % 16) * 16, math.floor(code / 16) * 16 + 1
        local left, right
        for column = 0, 7 do
            for row = 0, 15 do
                if ink(cell_x + column, cell_y + row) then
                    left = left or column
                    right = column
                    break
                end
            end
        end
        gdi_widths[code] = left and {left, right - left + 1} or false
    end
end

-- Width of GDI text in pixels: the advances of `gdi` below.
function font.gdi_width(text)
    if not gdi_widths then measure() end
    local width = 0
    for position = 1, #text do
        local glyph = gdi_widths[text:byte(position)]
        width = width + (glyph and glyph[2] + glyph_spacing or space_advance)
    end
    return width
end

-- GDI text at (x, y), top-left like TextOut. `color` (0xRRGGBB, default white; red/blue
-- swapped for COLORREF); `background`, if given, paints an opaque box behind the text (16px high).
function font.gdi(context, text, x, y, color, background)
    assert(#text <= 128, "text line exceeds font limit")
    if not gdi_widths then measure() end
    if background then
        context.fill(x, y, font.gdi_width(text) + 1, 16, math.floor(background / 65536) % 256,
            math.floor(background / 256) % 256, background % 256)
    end
    local tint = color ~= 0xffffff and color or nil
    for position = 1, #text do
        local code = text:byte(position)
        local glyph = gdi_widths[code]
        if glyph then
            context.sprite("pe/words0", {(code % 16) * 16 + glyph[1], math.floor(code / 16) * 16 + 1, glyph[2], 16}, x, y, true,
                false, false, tint)
            x = x + glyph[2] + glyph_spacing
        else
            x = x + space_advance
        end
    end
end
return font
