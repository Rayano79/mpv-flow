-- ==============================================================================
-- fps_counter.lua: Pure Native Real-Time Rendering FPS Engine for MPV
-- 100% Independent & Self-Contained (No External Software / No RTSS required)
-- Comprehensive Hardware Synchronization:
--  - Tracks video filter rate & playback speed
--  - Direct hardware drop detection (VO drops, decoder drops, mistimed sync)
--  - Integer display formatting (Zero decimals as requested)
-- ==============================================================================

local mp = require 'mp'
local utils = require 'mp.utils'

-- Configuration Table
local cfg = {
    enabled = false,
    position = "top-right", -- "top-right", "top-left", "top-center"
    update_interval = 0.40, -- 400ms: stable, responsive and ultra-lightweight
    font_size = 24,
    font_face = "Segoe UI"
}

local player_cfg_file = mp.command_native({"expand-path", "~~/player_settings.conf"})

local function load_config()
    local f = io.open(player_cfg_file, "r")
    if f then
        for line in f:lines() do
            local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
            if k and v then
                local kl = k:lower()
                if kl == "fps_counter" or kl == "fps_counter_enabled" then
                    local vl = v:lower()
                    cfg.enabled = (vl == "yes" or vl == "true" or vl == "1" or vl == "on")
                elseif kl == "fps_counter_pos" or kl == "fps_counter_position" then
                    local vl = v:lower()
                    if vl == "top-left" or vl == "top-right" or vl == "top-center" then
                        cfg.position = vl
                    end
                end
            end
        end
        f:close()
    end
end

load_config()

-- ------------------------------------------------------------------------------
-- High-Accuracy Continuous Delivery Engine
-- ------------------------------------------------------------------------------
local last_sample_time = mp.get_time()
local last_vo_drops = mp.get_property_number("frame-drop-count", 0)
local last_dec_drops = mp.get_property_number("decoder-frame-drop-count", 0)
local last_mistimed = mp.get_property_number("mistimed-frame-count", 0)
local current_live_fps = 0

local function calculate_live_fps()
    local now = mp.get_time()
    local dt = now - last_sample_time
    if dt <= 0 then return current_live_fps end

    local is_paused = mp.get_property_bool("pause", false)
    if is_paused then
        current_live_fps = 0
        last_sample_time = now
        return 0
    end

    -- 1. Query all hardware drop metrics
    local cur_vo_drops = mp.get_property_number("frame-drop-count", 0)
    local cur_dec_drops = mp.get_property_number("decoder-frame-drop-count", 0)
    local cur_mistimed = mp.get_property_number("mistimed-frame-count", 0)

    local delta_vo = cur_vo_drops - last_vo_drops
    local delta_dec = cur_dec_drops - last_dec_drops
    local delta_mis = cur_mistimed - last_mistimed

    if delta_vo < 0 then delta_vo = 0 end
    if delta_dec < 0 then delta_dec = 0 end
    if delta_mis < 0 then delta_mis = 0 end

    -- Primary dropped frames are VO + Decoder
    local total_dropped = delta_vo + delta_dec

    -- 2. Base target delivery rate
    local vf_fps = mp.get_property_number("estimated-vf-fps", 0)
    if vf_fps <= 0 then
        vf_fps = mp.get_property_number("container-fps", 0)
    end

    local speed = mp.get_property_number("speed", 1.0)
    local target_rate = vf_fps * speed

    -- 3. Calculate actual rendered FPS
    local dropped_rate = total_dropped / dt
    local actual = target_rate - dropped_rate

    if actual < 0 then actual = 0 end

    -- Round directly to whole integer (No decimals as requested)
    current_live_fps = math.floor(actual + 0.5)

    last_vo_drops = cur_vo_drops
    last_dec_drops = cur_dec_drops
    last_mistimed = cur_mistimed
    last_sample_time = now

    return current_live_fps
end

-- ------------------------------------------------------------------------------
-- Precision OSD HUD Rendering
-- ------------------------------------------------------------------------------
local overlay = mp.create_osd_overlay("ass-events")
overlay.z = 700

local function render_hud(fps_val)
    if not cfg.enabled then
        overlay:remove()
        return
    end

    local has_vid = mp.get_property("current-tracks/video") ~= nil
    local is_idle = mp.get_property_bool("idle-active", false)
    if not has_vid or is_idle then
        overlay:remove()
        return
    end

    local osd_w, osd_h = mp.get_osd_size()
    if not osd_w or osd_w <= 0 then
        osd_w, osd_h = 1920, 1080
    end

    local is_paused = mp.get_property_bool("pause", false)
    local val = fps_val or 0
    if is_paused then val = 0 end

    -- Integer display without decimals (e.g. "48", "60", "24")
    local fps_str = tostring(math.floor(val + 0.5))

    -- Precision coordinates: 70px safe margin below ModernZ top bar
    local pos_x = osd_w - 45
    local pos_y = 70
    local an = 9 -- Top-Right by default

    if cfg.position == "top-left" then
        pos_x = 45
        pos_y = 70
        an = 7 -- Top-Left
    elseif cfg.position == "top-center" then
        pos_x = math.floor(osd_w / 2)
        pos_y = 70
        an = 8 -- Top-Center
    end

    -- Crystal-clear typography:
    -- \blur0 for razor-sharp text, \bord2.5 solid dark outline, \shad1.2 drop shadow
    local ass = string.format(
        "{\\r}{\\an%d}{\\pos(%d,%d)}" ..
        "{\\fn%s}{\\b1}{\\fs%d}" ..
        "{\\blur0}{\\bord2.5}{\\3c&H08080C&}{\\shad1.2}{\\4c&H000000&}" ..
        "{\\1c&HE22B8A&}FPS {\\1c&HFFFFFF&}%s",
        an, pos_x, pos_y,
        cfg.font_face, cfg.font_size,
        fps_str
    )

    if overlay.data ~= ass or overlay.res_x ~= osd_w or overlay.res_y ~= osd_h then
        overlay.res_x = osd_w
        overlay.res_y = osd_h
        overlay.data = ass
        overlay:update()
    end
end

-- ------------------------------------------------------------------------------
-- Monitoring Timer Loop
-- ------------------------------------------------------------------------------
local timer = nil

local function tick()
    local fps = calculate_live_fps()
    render_hud(fps)
end

local function start_engine()
    if not timer then
        last_sample_time = mp.get_time()
        last_vo_drops = mp.get_property_number("frame-drop-count", 0)
        last_dec_drops = mp.get_property_number("decoder-frame-drop-count", 0)
        last_mistimed = mp.get_property_number("mistimed-frame-count", 0)
        timer = mp.add_periodic_timer(cfg.update_interval, tick)
    end
    tick()
end

local function stop_engine()
    if timer then
        timer:kill()
        timer = nil
    end
    overlay:remove()
end

-- ------------------------------------------------------------------------------
-- Script Message & Property Observers
-- ------------------------------------------------------------------------------
mp.register_script_message("set_fps_enabled", function(val)
    if val == "yes" or val == "true" or val == "1" or val == "on" then
        cfg.enabled = true
        start_engine()
    elseif val == "no" or val == "false" or val == "0" or val == "off" then
        cfg.enabled = false
        stop_engine()
    elseif val == "toggle" then
        cfg.enabled = not cfg.enabled
        if cfg.enabled then start_engine() else stop_engine() end
    end
end)

mp.register_script_message("set_fps_position", function(pos)
    if pos == "top-right" or pos == "top-left" or pos == "top-center" then
        cfg.position = pos
        if cfg.enabled then tick() end
    end
end)

mp.register_script_message("toggle_fps", function()
    cfg.enabled = not cfg.enabled
    if cfg.enabled then start_engine() else stop_engine() end
end)

mp.add_key_binding(nil, "toggle_fps", function()
    cfg.enabled = not cfg.enabled
    if cfg.enabled then
        start_engine()
        mp.osd_message("FPS Counter: ON", 1.5)
    else
        stop_engine()
        mp.osd_message("FPS Counter: OFF", 1.5)
    end
end)

mp.observe_property("pause", "bool", function()
    if cfg.enabled then tick() end
end)

mp.observe_property("osd-width", "native", function()
    if cfg.enabled then tick() end
end)

if cfg.enabled then
    start_engine()
end
