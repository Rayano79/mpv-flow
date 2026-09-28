-- ========================================================
-- mode_notify.lua: Intelligent RIFE AI & 4K Mode Synchronizer
-- Handles active state persistence, clean filter injection,
-- and automatic bypass according to player_settings.conf.
-- ========================================================

local mp = require 'mp'

local function check_stremio_fullscreen()
    local path = mp.get_property("path", "")
    if string.match(path, "^https?://127%.0%.0%.1:11470") or string.match(path, "^https?://localhost:11470") then
        mp.set_property_bool("fullscreen", true)
    end
end
mp.register_event("file-loaded", check_stremio_fullscreen)

local player_cfg_file = mp.command_native({"expand-path", "~~/player_settings.conf"})

local function read_conf_value(target_key)
    local f = io.open(player_cfg_file, "r")
    if not f then return nil end
    for line in f:lines() do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k and k:lower() == target_key:lower() then
            f:close()
            return v
        end
    end
    f:close()
    return nil
end

local function read_is_active()
    local v = read_conf_value("active")
    if v then
        local vl = v:lower()
        return (vl == "yes" or vl == "true" or vl == "1" or vl == "on")
    end
    return true -- Default: active if not specified
end

local function read_uhd_mode()
    local v = read_conf_value("uhd_mode")
    if v then
        local n = tonumber(v)
        if n == 1 or n == 2 then return n end
    end
    return 1 -- Default: 1 (Bypass on 4K)
end

local function read_is_ar()
    local v = read_conf_value("language")
    if v then
        local vl = v:lower()
        return (vl == "ar" or vl == "arabic")
    end
    return true -- Default: Arabic
end

local function update_player_conf_key(key, val)
    local lines = {}
    local found = false
    local f = io.open(player_cfg_file, "r")
    if f then
        for line in f:lines() do
            local k = line:match("^%s*([%w_]+)%s*=")
            if k and k:lower() == key:lower() then
                table.insert(lines, key .. "=" .. tostring(val))
                found = true
            else
                table.insert(lines, line)
            end
        end
        f:close()
    end
    if not found then
        table.insert(lines, key .. "=" .. tostring(val))
    end
    local out = io.open(player_cfg_file, "w")
    if out then
        for _, l in ipairs(lines) do
            out:write(l .. "\n")
        end
        out:flush()
        out:close()
    end
end

local function is_vapoursynth_loaded()
    local vf = mp.get_property_native("vf") or {}
    for _, filter in ipairs(vf) do
        if filter.name == "vapoursynth" or (filter.label and filter.label:find("interpolation")) then
            return true
        end
    end
    return false
end

local function remove_vapoursynth_filter()
    local vf = mp.get_property_native("vf") or {}
    local new_vf = {}
    local had_vs = false
    for _, filter in ipairs(vf) do
        if filter.name == "vapoursynth" or (filter.label and filter.label:find("interpolation")) then
            had_vs = true
        else
            table.insert(new_vf, filter)
        end
    end
    if had_vs then
        mp.set_property_native("vf", new_vf)
    end
    return had_vs
end

local function add_vapoursynth_filter()
    if not is_vapoursynth_loaded() then
        mp.command('vf set vapoursynth="~~/vs/interpolation.vpy":4:4')
    end
end

local function sync_rife_for_file()
    mp.add_timeout(0.05, function()
        local src_w = mp.get_property_number("video-params/w", 0)
        local src_h = mp.get_property_number("video-params/h", 0)
        if src_w == 0 and src_h == 0 then return end

        local is_uhd = (src_w > 1920 or src_h > 1088)
        local is_act = read_is_active()
        local uhd_mode = read_uhd_mode()
        local is_ar = read_is_ar()

        -- Case 1: RIFE is disabled in user settings (active=no)
        if not is_act then
            remove_vapoursynth_filter()
            return
        end

        -- Case 2: RIFE is active, but video is 4K/UHD and user configured uhd_mode=1 (Bypass on 4K)
        if is_uhd and uhd_mode == 1 then
            remove_vapoursynth_filter()
            mp.osd_message(is_ar and "RIFE: معطل على دقة 4K (تشغيل أصلي خالص)" or "RIFE: Disabled on 4K (Pure Native Playback)", 2.5)
            return
        end

        -- Case 3: RIFE is active (1080p/720p or 4K with 1080p downscale mode 2)
        add_vapoursynth_filter()

        -- Report status cleanly after pipeline stabilizes
        mp.add_timeout(0.6, function()
            if not is_vapoursynth_loaded() then return end
            local fps = mp.get_property_number("estimated-vf-fps", 0)
            local fps_str = string.format("%.1f", fps)
            if is_uhd and uhd_mode == 2 then
                mp.osd_message(is_ar and ("RIFE: يعمل (4K -> 1080p سلس: " .. fps_str .. " fps)") or ("RIFE: Running (4K -> 1080p Smooth: " .. fps_str .. " fps)"), 2.5)
            elseif fps > 35 then
                mp.osd_message(is_ar and ("RIFE يعمل (" .. fps_str .. " fps)") or ("RIFE is running (" .. fps_str .. " fps)"), 2.5)
            end
        end)
    end)
end

local function toggle_rife()
    local is_act = read_is_active()
    local is_ar = read_is_ar()

    if is_act then
        -- User wants to turn OFF
        update_player_conf_key("active", "no")
        remove_vapoursynth_filter()
        mp.osd_message(is_ar and "○ RIFE: تم التعطيل (وحفظ الحالة)" or "○ RIFE: Disabled (Saved to settings)", 2.5)
    else
        -- User wants to turn ON
        update_player_conf_key("active", "yes")
        local src_w = mp.get_property_number("video-params/w", 0)
        local src_h = mp.get_property_number("video-params/h", 0)
        local is_uhd = (src_w > 1920 or src_h > 1088)
        local uhd_mode = read_uhd_mode()

        if is_uhd and uhd_mode == 1 then
            remove_vapoursynth_filter()
            mp.osd_message(is_ar and "● RIFE: مفعّل (معطل على 4K حسب إعداداتك)" or "● RIFE: Enabled (Bypassed on 4K per settings)", 3.0)
        else
            add_vapoursynth_filter()
            mp.osd_message(is_ar and "● RIFE: تم التفعيل والتشغيل (وحفظ الحالة)" or "● RIFE: Enabled & Running (Saved)", 2.5)
        end
    end
end

mp.register_event("file-loaded", sync_rife_for_file)
mp.add_key_binding("F1", "toggle_rife", toggle_rife)
