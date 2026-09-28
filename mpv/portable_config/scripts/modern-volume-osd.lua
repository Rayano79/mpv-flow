-- ==============================================================================
-- Harbor Liquid Glass Volume HUD for MPV
-- Recreated 1:1 from Harbor's React/Tailwind source code:
-- (harbor-editing/src/components/player/volume-indicator.tsx)
-- Center-Center Position, Liquid Glass Surface, Hairline Borders,
-- Pure White Bar, 100% Marker Line, 0px Waste at Max Volume (130%)
-- ==============================================================================

local mp = require 'mp'
local assdraw = require 'mp.assdraw'
local overlay = mp.create_osd_overlay("ass-events")

local opts = {
    duration = 1.3,               -- Fadeout delay in seconds
    card_w = 320,                 -- Elongated wide luxury card
    card_h = 66,                  -- Balanced height
    card_r = 18,                  -- Rounded corners (Harbor rounded-[20px])
    badge_size = 40,              -- Left icon badge container (w-11 h-11)
    badge_r = 13,                 -- Badge corner radius (rounded-[15px])
    bar_h = 7.5,                  -- Progress track height (h-2.5)
    bar_r = 3.75,                 -- Rounded track ends
    font = "Inter Tight Medium",
    font_icon = "MaterialIconsRound-Regular",

    -- Exact Harbor Liquid Glass Palette (BGR hex)
    color_glass_bg = "18120C",    -- rgba(8, 12, 18, 0.35) -> Luminous deep navy glass
    color_border_white = "FFFFFF",-- Pure white for hairlines
    color_track_bg = "000000",    -- Track recess
    color_bar_normal = "E22B8A",  -- Purple #8A2BE2 in BGR hex
    color_boost = "1673F9"        -- Harbor boost orange rgb(249, 115, 22)
}

local timer = nil
local active = false
local ui_scale = 1.0

local function draw_harbor_hud(vol, mute)
    local screen_w, screen_h = mp.get_osd_size()
    if not screen_w or screen_w == 0 then
        screen_w, screen_h = 1920, 1080
    end

    local s = ui_scale or 1.0
    local card_w = math.floor(opts.card_w * s)
    local card_h = math.floor(opts.card_h * s)
    local card_r = math.floor(opts.card_r * s)
    local badge_size = math.floor(opts.badge_size * s)
    local badge_r = math.floor(opts.badge_r * s)
    local bar_h = math.floor(opts.bar_h * s)
    local bar_r = math.floor(opts.bar_r * s)
    local pad = math.floor(12 * s)

    -- Explicit 1:1 resolution sync to prevent any clipping or canvas distortion
    overlay.res_x = screen_w
    overlay.res_y = screen_h
    overlay.z = 1000

    -- =========================================================================
    -- 1. PERFECT CENTER-CENTER POSITION (Harbor Default)
    -- =========================================================================
    local card_x = math.floor((screen_w - card_w) / 2)
    local card_y = math.floor((screen_h - card_h) / 2)

    -- Boundary safety
    card_x = math.max(10, math.min(card_x, screen_w - card_w - 10))
    card_y = math.max(10, math.min(card_y, screen_h - card_h - 10))

    -- =========================================================================
    -- 2. VOLUME CALCULATION & 100% CEILING (0px wasted space at max)
    -- =========================================================================
    local vol_max = mp.get_property_number("volume-max", 130)
    if vol_max < 100 then vol_max = 100 end

    local current_vol = math.max(0, math.min(vol, vol_max))
    local boosting = current_vol > 100

    -- Card layout dimensions
    local badge_x = card_x + pad
    local badge_y = card_y + pad
    local content_x = badge_x + badge_size + math.floor(14 * s)
    local content_w = (card_x + card_w - pad) - content_x

    -- Progress bar width calculation
    local fill_w = 0
    if vol_max > 0 then
        fill_w = math.floor((current_vol / vol_max) * content_w)
    end
    fill_w = math.max(0, math.min(fill_w, content_w))

    -- 100% boundary marker position
    local mark_100_x = content_x + math.floor((100 / vol_max) * content_w)

    -- Dynamic icon selector
    local icon = "volume_up"
    if mute or vol == 0 then
        icon = "volume_off"
    elseif vol < 50 then
        icon = "volume_down"
    end

    local bar_color = boosting and opts.color_boost or opts.color_bar_normal
    local icon_color = (mute and "5B5CF4") or (boosting and opts.color_boost) or opts.color_bar_normal

    local ass = assdraw.ass_new()

    -- =========================================================================
    -- 3. OUTER LIQUID GLASS CARD (Harbor 35% glass + Hairline 0.75px border)
    -- =========================================================================
    ass:new_event()
    ass:pos(card_x, card_y)
    ass:an(7)
    ass:append(string.format("{\\bord0.75\\3c&H%s&\\1c&H%s&\\shad2\\4c&H000000&\\alpha&HA6&}", opts.color_border_white, opts.color_glass_bg))
    ass:draw_start()
    ass:round_rect_cw(0, 0, card_w, card_h, card_r)
    ass:draw_stop()

    -- =========================================================================
    -- 4. LEFT ICON BADGE (Harbor 9% frosted white container + 12% border)
    -- =========================================================================
    ass:new_event()
    ass:pos(badge_x, badge_y)
    ass:an(7)
    ass:append(string.format("{\\bord0.6\\3c&H%s&\\1c&H%s&\\shad0\\alpha&HE8&}", opts.color_border_white, opts.color_border_white))
    ass:draw_start()
    ass:round_rect_cw(0, 0, badge_size, badge_size, badge_r)
    ass:draw_stop()

    -- =========================================================================
    -- 5. SPEAKER ICON (Centered inside badge)
    -- =========================================================================
    local icon_cx = badge_x + math.floor(badge_size / 2)
    local icon_cy = badge_y + math.floor(badge_size / 2)
    local fs_icon = math.floor(21 * s)
    ass:new_event()
    ass:pos(icon_cx, icon_cy)
    ass:an(5)
    ass:append(string.format("{\\fn%s\\fs%d\\1c&H%s&\\bord0\\shad0\\alpha&H08&}", opts.font_icon, fs_icon, icon_color))
    ass:append(icon)

    -- =========================================================================
    -- 6. UPPER ROW: "V O L U M E" (Left uppercase tracking)
    -- =========================================================================
    local label_y = badge_y + math.floor(4 * s)
    local fs_label = math.floor(10 * s)
    ass:new_event()
    ass:pos(content_x, label_y)
    ass:an(7)
    ass:append(string.format("{\\fn%s\\fs%d\\b1\\1c&H%s&\\bord0\\shad0\\alpha&H30&}", opts.font, fs_label, opts.color_border_white))
    ass:append("V O L U M E")

    -- =========================================================================
    -- 7. UPPER ROW: "65%" PERCENTAGE (Right bold - Pure White #FFFFFF)
    -- =========================================================================
    local pct_x = content_x + content_w
    local pct_str = mute and "Mute" or string.format("%d%%", vol)
    local fs_pct = math.floor(15 * s)
    ass:new_event()
    ass:pos(pct_x, label_y - math.floor(2 * s))
    ass:an(9)
    ass:append(string.format("{\\fn%s\\fs%d\\b1\\1c&H%s&\\bord0\\shad0\\alpha&H08&}", opts.font, fs_pct, boosting and opts.color_boost or opts.color_border_white))
    ass:append(pct_str)

    -- =========================================================================
    -- 8. BOTTOM ROW: PROGRESS TRACK (Recessed slot with hairline border)
    -- =========================================================================
    local bar_y = badge_y + math.floor(24 * s)
    ass:new_event()
    ass:pos(content_x, bar_y)
    ass:an(7)
    ass:append(string.format("{\\bord0.6\\3c&H%s&\\1c&H%s&\\shad0\\alpha&HC7&}", opts.color_border_white, opts.color_track_bg))
    ass:draw_start()
    ass:round_rect_cw(0, 0, content_w, bar_h, bar_r)
    ass:draw_stop()

    -- =========================================================================
    -- 9. BOTTOM ROW: ACTIVE FILL (Purple with fine hairline white outline)
    -- =========================================================================
    if not mute and fill_w > 0 then
        ass:new_event()
        ass:pos(content_x, bar_y)
        ass:an(7)
        ass:append(string.format("{\\bord0.5\\3c&H%s&\\shad0\\1c&H%s&\\alpha&H08&}", opts.color_border_white, bar_color))
        ass:draw_start()
        ass:round_rect_cw(0, 0, fill_w, bar_h, bar_r)
        ass:draw_stop()
    end

    -- =========================================================================
    -- 10. 100% MAXIMUM THRESHOLD MARKER LINE (Harbor's 1px hairline indicator)
    -- =========================================================================
    if vol_max > 100 then
        ass:new_event()
        ass:pos(mark_100_x, bar_y - math.floor(2 * s))
        ass:an(7)
        ass:append(string.format("{\\bord0\\shad0\\1c&H%s&\\alpha&H9E&}", opts.color_border_white))
        ass:draw_start()
        ass:rect_cw(0, 0, 1, bar_h + math.floor(4 * s))
        ass:draw_stop()
    end

    overlay.data = ass.text
    overlay:update()
end

local function hide_osd()
    overlay:remove()
    active = false
end

local file_loaded = false
local last_vol = nil
local last_mute = nil

mp.register_event("file-loaded", function()
    file_loaded = false
    last_vol = mp.get_property_number("volume", 100)
    last_mute = mp.get_property_bool("mute", false)
    -- Allow user volume changes after 0.5s of file start
    mp.add_timeout(0.5, function()
        file_loaded = true
        last_vol = mp.get_property_number("volume", 100)
        last_mute = mp.get_property_bool("mute", false)
    end)
end)

mp.register_event("end-file", function()
    file_loaded = false
    hide_osd()
end)

local function on_volume_change(name, val)
    local vol = mp.get_property_number("volume", 100)
    local mute = mp.get_property_bool("mute", false)

    if not file_loaded then
        last_vol = vol
        last_mute = mute
        return
    end

    if last_vol == vol and last_mute == mute then
        return
    end

    last_vol = vol
    last_mute = mute

    if not mp.get_property("path") then return end

    draw_harbor_hud(vol, mute)
    active = true

    if timer then
        timer:kill()
    end
    timer = mp.add_timeout(opts.duration, hide_osd)
end

-- Observe volume and mute
mp.observe_property("volume", "number", on_volume_change)
mp.observe_property("mute", "bool", on_volume_change)

mp.register_script_message("set-ui-scale", function(scale_str)
    local s = tonumber(scale_str)
    if s and s > 0 then
        ui_scale = s
        if active then
            local vol = mp.get_property_number("volume", 100)
            local mute = mp.get_property_bool("mute", false)
            draw_harbor_hud(vol, mute)
        end
    end
end)
