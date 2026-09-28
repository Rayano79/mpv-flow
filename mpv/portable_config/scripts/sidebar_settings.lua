-- ==============================================================================
-- sidebar_settings.lua: Modern In-Screen Embedded Settings Sidebar for MPV
-- Floating glassmorphic cards, purple accent, persistent live tuning,
-- accordions closed by default, clean borderless typography,
-- and double-click protection inside menu boxes.
-- ==============================================================================

local mp = require 'mp'
local utils = require 'mp.utils'
local assdraw = require 'mp.assdraw'

local overlay = mp.create_osd_overlay("ass-events")
overlay.z = 600 -- Below ModernZ bottom bar (1000) so ModernZ stays cleanly in front

local is_open = false
local active_category = "subtitle" -- Default selected category
local active_flyout = nil          -- ALL ACCORDIONS CLOSED BY DEFAULT
local mouse_x = -1
local mouse_y = -1
local flyout_scroll = 0            -- Scroll offset for flyout if content overflows
local hitboxes = {}
local last_open_time = 0

-- Layout bounds calculated per render
local layout = {
    sb_x1 = 0, sb_y1 = 0, sb_x2 = 0, sb_y2 = 0,
    fo_x1 = 0, fo_y1 = 0, fo_x2 = 0, fo_y2 = 0
}

-- UI Colors & Metrics (BGR Hex for ASS)
local COLOR_BG = "120E0E"          -- Unified deep dark glass #0E0E12
local COLOR_BORDER = "362A2A"      -- Hairline glass border #2A2A36
local COLOR_PURPLE = "E22B8A"      -- ModernZ purple #8A2BE2 (BGR: E22B8A)
local COLOR_PURPLE_BG = "421428"   -- Subtle purple tint for active items
local COLOR_HOVER = "261E1E"       -- Hover highlight #1E1E26
local COLOR_ITEM_BG = "1C1515"     -- Elevated field header card #15151C
local COLOR_ITEM_BORDER = "382B2B" -- Glass border for headers and option pills #2B2B38
local COLOR_TEXT = "FFFFFF"        -- Crisp pure white
local COLOR_TEXT_MUTED = "A8A0A0"  -- Readable light silver/gray
local COLOR_CLOSE_RED = "4545E0"   -- Red for close button hover

local function get_ui_scale()
    local scale = mp.get_property_number("osd-scale", 1.0) or 1.0
    if scale < 0.5 then scale = 0.5 end
    if scale > 2.5 then scale = 2.5 end
    return scale
end

-- ==============================================================================
-- Helper Functions & State Queries
-- ==============================================================================

local function set_sub_prop(name, val)
    mp.commandv("script-message-to", "subtitle_manager", "set_sub_prop", name, tostring(val))
end

local function set_sub_mode(mode)
    mp.commandv("script-message-to", "subtitle_manager", "set_sub_mode", mode)
end

local function set_sub_bg(style, color)
    mp.commandv("script-message-to", "subtitle_manager", "set_sub_bg", style, color)
end

local function reset_sub_style()
    mp.commandv("script-message-to", "subtitle_manager", "reset_sub_style")
end

local function set_ui_scale(val)
    mp.commandv("script-message-to", "ui_scale_manager", "set_ui_scale", tostring(val))
end

-- ==============================================================================
-- Unified Player Settings Management (player_settings.conf)
-- ==============================================================================
local player_cfg_file = mp.command_native({"expand-path", "~~/player_settings.conf"})
local current_language = "ar" -- Default: Arabic

local function read_language_cfg()
    local f = io.open(player_cfg_file, "r")
    if f then
        for line in f:lines() do
            local k, v = line:match("^%s*([%w_]+)%s*=%s*([%w_]+)")
            if k and k:lower() == "language" then
                local l = v:lower()
                current_language = (l == "eng" or l == "en") and "eng" or "ar"
                break
            end
        end
        f:close()
    end
end

-- Initialize language immediately on load
read_language_cfg()

-- Update key in player_settings.conf and sync to rife_settings.conf for backward compatibility
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

    -- Sync language to modernz.conf as well
    if key == "language" then
        local mz_file = mp.command_native({"expand-path", "~~/script-opts/modernz.conf"})
        local mf = io.open(mz_file, "r")
        if mf then
            local m_lines = {}
            local m_found = false
            for line in mf:lines() do
                if line:match("^%s*language%s*=") then
                    table.insert(m_lines, "language=" .. tostring(val))
                    m_found = true
                else
                    table.insert(m_lines, line)
                end
            end
            mf:close()
            if not m_found then table.insert(m_lines, "language=" .. tostring(val)) end
            local mout = io.open(mz_file, "w")
            if mout then
                for _, l in ipairs(m_lines) do mout:write(l .. "\n") end
                mout:flush()
                mout:close()
            end
        end
    end
end

local function set_app_language(lang)
    if lang ~= "ar" and lang ~= "eng" then return end
    current_language = lang
    active_flyout = nil
    update_player_conf_key("language", lang)
    mp.commandv("script-message-to", "modernz", "set_language", lang)
    mp.osd_message(lang == "ar" and "تم تفعيل اللغة العربية" or "Switched to English", 2)
    -- Close sidebar after language change so the forced mbtn_left binding is removed.
    -- This allows the user to click the settings gear again without the sidebar
    -- intercepting the mbtn_left_up event before modernz updates its virtual mouse areas.
    sidebar_toggle(false)
end

local function get_active_shaders()
    local s_str = mp.get_property("glsl-shaders", "")
    local s_list = {}
    if s_str and s_str ~= "" then
        for s in string.gmatch(s_str, "[^;]+") do
            s = s:gsub("^%s+", ""):gsub("%s+$", "")
            if s ~= "" then
                table.insert(s_list, s)
            end
        end
    end
    return s_list
end

local function is_shader_active(name_pattern)
    local list = get_active_shaders()
    for _, p in ipairs(list) do
        local base = p:match("([^/\\]+)$") or p
        if base:lower():find(name_pattern:lower(), 1, true) then
            return true
        end
    end
    return false
end

local function save_active_shaders()
    local list = get_active_shaders()
    local names = {}
    for _, p in ipairs(list) do
        local base = p:match("([^/\\]+)$") or p
        if base and base ~= "" then
            table.insert(names, base)
        end
    end
    update_player_conf_key("shaders", table.concat(names, ";"))
end

local function load_saved_shaders()
    local f = io.open(player_cfg_file, "r")
    local shaders_str = ""
    if f then
        for line in f:lines() do
            local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
            if k and k:lower() == "shaders" then
                shaders_str = v or ""
                break
            end
        end
        f:close()
    end
    if shaders_str == "" then
        local s_file = mp.command_native({"expand-path", "~~/shaders_settings.conf"})
        local sf = io.open(s_file, "r")
        if sf then
            local fallback_names = {}
            for line in sf:lines() do
                local name = line:match("^%s*(.-)%s*$")
                if name and name ~= "" and not name:match("^#") then
                    table.insert(fallback_names, name)
                end
            end
            sf:close()
            shaders_str = table.concat(fallback_names, ";")
        end
    end
    if shaders_str == "" then return end
    local paths = {}
    for name in string.gmatch(shaders_str, "[^;]+") do
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" and not name:match("^#") then
            local full_path = mp.command_native({"expand-path", "~~/shaders/" .. name})
            table.insert(paths, full_path)
        end
    end
    if #paths > 0 then
        mp.set_property("glsl-shaders", table.concat(paths, ";"))
    end
end

local function toggle_shader(shader_file, display_name)
    local full_path = mp.command_native({"expand-path", "~~/shaders/" .. shader_file})
    if is_shader_active(shader_file) then
        mp.commandv("change-list", "glsl-shaders", "remove", full_path)
        mp.osd_message("Shader Removed: " .. display_name, 2)
    else
        mp.commandv("change-list", "glsl-shaders", "append", full_path)
        mp.osd_message("Shader Active: " .. display_name, 2)
    end
    mp.add_timeout(0.05, function()
        save_active_shaders()
    end)
end

local function clear_all_shaders()
    mp.commandv("change-list", "glsl-shaders", "clr", "")
    mp.osd_message("All Shaders Cleared", 2)
    mp.add_timeout(0.05, function()
        save_active_shaders()
    end)
end

-- ==============================================================================
-- Menu Structure & Data
-- ==============================================================================

local predefined_fonts = {}
local plist = {
    "notonaskharabic-regular.ttf",
    "cairo-regular.ttf",
    "opensans-regular.ttf",
    "roboto-regular.ttf",
    "notosans-regular.ttf",
    "xb-zar.ttf"
}
for _, fn in ipairs(plist) do predefined_fonts[fn:lower()] = true end

local function get_other_fonts(cur_font)
    local fonts_dir = mp.command_native({"expand-path", "~~/fonts"})
    if not fonts_dir or fonts_dir == "" then return {} end

    -- UI / icon fonts — always skip (lowercase keys for matching)
    local skip = {
        ["materialiconsround-regular.otf"] = true,
        ["modernz-icons.ttf"]              = true,
        ["uosc_textures.ttf"]              = true,
    }

    local files = utils.readdir(fonts_dir, "files") or {}
    local result = {}
    for _, f in ipairs(files) do
        local low = f:lower()
        if (low:match("%.ttf$") or low:match("%.otf$"))
            and not skip[low]
            and not predefined_fonts[low]
        then
            local name = f:gsub("%.[^.]+$", ""):gsub("[-_]+", " ")
            local n = name  -- capture for closure
            table.insert(result, {
                label   = n .. "  [Other]",
                checked = (cur_font == n or (cur_font ~= "" and cur_font:find(n, 1, true) ~= nil)),
                cmd     = function() set_sub_prop("sub-font", n) end
            })
        end
    end
    return result
end

-- ==============================================================================
-- Dynamic Shader Discovery & Custom Shaders
-- ==============================================================================
local predefined_shaders = {
    ["anime4k_restore_cnn_m.glsl"] = true,
    ["anime4k_restore_cnn_vl.glsl"] = true,
    ["anime4k_upscale_cnn_x2_m.glsl"] = true,
    ["anime4k_darken_hq.glsl"] = true,
    ["anime4k_thin_hq.glsl"] = true,
    ["fsrcnnx_x2_8_0_4_1_lineart.glsl"] = true,
    ["fsrcnnx_x2_16_0_4_1.glsl"] = true,
    ["ravu-zoom-ar-r3-rgb.hook"] = true,
    ["amd_cas_aio_rt.glsl"] = true,
    ["amd_fsr_rcas_luma_rt.glsl"] = true,
    ["adaptive_sharpen_rt.glsl"] = true,
}

local function get_custom_shaders(is_ar)
    local shaders_dir = mp.command_native({"expand-path", "~~/shaders"})
    if not shaders_dir or shaders_dir == "" then return {} end
    local files = utils.readdir(shaders_dir, "files") or {}
    local items = {}
    for _, f in ipairs(files) do
        local low = f:lower()
        if (low:match("%.glsl$") or low:match("%.hook$")) and not predefined_shaders[low] then
            local clean_name = f:gsub("%.[^.]+$", ""):gsub("[-_]+", " ")
            local is_active = is_shader_active(f)
            table.insert(items, {
                label = f .. (is_active and (is_ar and "  (مفعّل)" or "  (Active)") or ""),
                desc = is_ar and ("شيدر إضافي تم اكتشافه تلقائياً من مجلد shaders: " .. f) or ("Custom shader auto-detected from shaders/ folder: " .. f),
                checked = is_active,
                cmd = function()
                    toggle_shader(f, clean_name)
                end
            })
        end
    end
    return items
end

-- ==============================================================================
-- ==============================================================================
-- Project Root & TensorRT Engine Status Verification
-- ==============================================================================
local function get_project_root()
    local candidates = {
        mp.command_native({"expand-path", "~~/../.."}),
        mp.command_native({"expand-path", "~~/.."}),
        mp.command_native({"expand-path", "~~"}),
        "."
    }
    for _, dir in ipairs(candidates) do
        local check_tools = utils.file_info(utils.join_path(dir, "tools"))
        local check_vs    = utils.file_info(utils.join_path(dir, "vs"))
        local check_setup = utils.file_info(utils.join_path(dir, "setup.bat"))
        if (check_tools and check_tools.is_dir) or (check_vs and check_vs.is_dir) or check_setup then
            return dir
        end
    end
    return mp.command_native({"expand-path", "~~/../.."})
end

local project_root = get_project_root()
local manifest_file = mp.command_native({"expand-path", "~~/engines_manifest.json"})
local models_dir = utils.join_path(project_root, "vs/vs-plugins/models/rife_v2")
local engines_dir = utils.join_path(models_dir, "engines")

local MODEL_ONNX_FILES = {
    [1] = "rife_v4.25_v2.onnx",
    [2] = "rife_v4.25_lite_v2.onnx",
    [3] = "rife_v4.22_lite_v2.onnx",
    [4] = "rife_v4.17_lite_v2.onnx"
}

local function is_model_onnx_present(model_num)
    local filename = MODEL_ONNX_FILES[model_num]
    if not filename then return false end
    local p = utils.join_path(models_dir, filename)
    local info = utils.file_info(p)
    return (info and info.size and info.size > 1024 * 1024)
end

local function find_tool_bat(bat_name)
    local root = get_project_root()
    local p1 = utils.join_path(root, "tools/" .. bat_name)
    if utils.file_info(p1) then return p1 end
    local p2 = utils.join_path(root, bat_name)
    if utils.file_info(p2) then return p2 end
    return p1
end

local function is_valid_engine_file(filename)
    if not filename or filename == "" then return false end
    local p = utils.join_path(engines_dir, filename)
    local info = utils.file_info(p)
    -- Must exist on disk and be larger than 1MB (aborted/empty builds leave 0-byte or tiny files)
    if not (info and info.size and info.size > 1024 * 1024) then
        return false
    end
    -- Check engine header for TensorRT 10.13.3 compatibility
    local f = io.open(p, "rb")
    if f then
        local header = f:read(32)
        f:close()
        if header and #header >= 28 and header:sub(1, 4) == "ftrt" then
            local b24 = header:byte(25) -- 10
            local b25 = header:byte(26) -- 13
            local b26 = header:byte(27) -- 3
            if b24 ~= 10 or b25 ~= 13 or b26 ~= 3 then
                return false
            end
        end
    end
    return true
end

local engine_status_cache = {}
local engine_status_cache_time = 0

local function invalidate_engine_cache()
    engine_status_cache = {}
    engine_status_cache_time = 0
end

local function get_engine_status(model_num)
    local now = mp.get_time()
    if (now - engine_status_cache_time < 3.0) and engine_status_cache[model_num] then
        local c = engine_status_cache[model_num]
        return c[1], c[2], c[3]
    end

    local onnx_ok = is_model_onnx_present(model_num)
    if not onnx_ok then
        return false, false, "missing_model"
    end

    local base_ready = false
    local is_4k_ready = false

    local mf = io.open(manifest_file, "r")
    if mf then
        local content = mf:read("*all")
        mf:close()
        if content and content ~= "" then
            local data = utils.parse_json(content)
            if data and data.models and data.models[tostring(model_num)] then
                local m = data.models[tostring(model_num)]
                local res = m.resolutions
                if res then
                    local f1080_ok = res["1080p"] and is_valid_engine_file(res["1080p"].file)
                    local f720_ok  = res["720p"] and is_valid_engine_file(res["720p"].file)
                    local f4k_ok   = res["4k"] and is_valid_engine_file(res["4k"].file)

                    base_ready = (f1080_ok and f720_ok)
                    is_4k_ready = (f4k_ok == true)
                    local res_state = (base_ready and "ready" or "need_build")
                    engine_status_cache[model_num] = {base_ready, is_4k_ready, res_state}
                    engine_status_cache_time = now
                    return base_ready, is_4k_ready, res_state
                end
            end
        end
    end

    -- Fallback when manifest is missing or invalid: inspect valid engines in engines_dir
    local info = utils.file_info(engines_dir)
    local count = 0
    if info and info.is_dir then
        local files = utils.readdir(engines_dir, "files") or {}
        for _, f in ipairs(files) do
            if f:match("%.engine$") and is_valid_engine_file(f) then
                count = count + 1
            end
        end
    end
    -- 4 models * 2 base resolutions (1080p + 720p) = 8 engines
    base_ready = (count >= 8)
    is_4k_ready = (count >= 12 or (count >= 8 + model_num))
    local res_state = (base_ready and "ready" or "need_build")
    engine_status_cache[model_num] = {base_ready, is_4k_ready, res_state}
    engine_status_cache_time = now
    return base_ready, is_4k_ready, res_state
end

local function launch_single_model_build(model_num, is_ar, model_name)
    local bat_name = "build_model_" .. tostring(model_num) .. ".bat"
    local bat_path = find_tool_bat(bat_name)
    local info = utils.file_info(bat_path)
    if not info then
        mp.osd_message(is_ar and ("خطأ: لم يتم العثور على tools/" .. bat_name) or ("Error: tools/" .. bat_name .. " not found"), 3)
        return
    end

    local window_title = "TensorRT Model " .. tostring(model_num) .. " Builder"
    utils.subprocess_detached({
        args = {"cmd.exe", "/c", "start", window_title, bat_path},
        cancellable = false
    })

    local name_str = model_name or ("Model " .. tostring(model_num))
    mp.osd_message(is_ar and ("بدأ بناء محركات " .. name_str .. " (1080p و 720p)...\nتابع التقدم في النافذة المنبثقة") or ("Started building " .. name_str .. " (1080p & 720p)...\nCheck the console window"), 4)
end

local function launch_default_engine_build(is_ar)
    local bat_path = find_tool_bat("build_all_engines.bat")
    local info = utils.file_info(bat_path)
    if not info then
        mp.osd_message(is_ar and "خطأ: لم يتم العثور على build_all_engines.bat" or "Error: build_all_engines.bat not found", 3)
        return
    end

    utils.subprocess_detached({
        args = {"cmd.exe", "/c", "start", "TensorRT Default Engines Builder", bat_path},
        cancellable = false
    })

    mp.osd_message(is_ar and "بدأ بناء كافة محركات RIFE الافتراضية... تابع التقدم في النافذة المنبثقة" or "Started Default RIFE Engines Build... check the opened console window", 4)
end

local function launch_4k_engine_build(is_ar)
    -- [ملاحظة: تم تعطيل خيار بناء محركات 4K مؤقتاً لثقل المعالجة الفائق وعدم استقراره حتى على أقوى الكروت]
    mp.osd_message(is_ar and "خيار بناء محركات 4K معطل مؤقتاً لثقل المعالجة الفائق على العتاد" or "4K Engine build is temporarily disabled due to extreme GPU load", 4)
end

local function is_current_video_uhd()
    local w = mp.get_property_number("video-params/w", 0)
    local h = mp.get_property_number("video-params/h", 0)
    return (w > 1920 or h > 1088)
end

local function reload_rife()
    local cur_uhd_mode = 1
    local is_act = true
    local f = io.open(player_cfg_file, "r")
    if f then
        for line in f:lines() do
            local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
            if k then
                local kl = k:lower()
                if kl == "uhd_mode" and v then
                    cur_uhd_mode = tonumber(v) or 1
                elseif kl == "active" and v then
                    local vl = v:lower()
                    is_act = (vl == "yes" or vl == "true" or vl == "1" or vl == "on")
                end
            end
        end
        f:close()
    end

    if not is_act or (cur_uhd_mode == 1 and is_current_video_uhd()) then
        local vf_list = mp.get_property_native("vf") or {}
        local new_vf = {}
        local had_vs = false
        for _, filter in ipairs(vf_list) do
            if filter.name == "vapoursynth" or (filter.label and filter.label:find("interpolation")) then
                had_vs = true
            else
                table.insert(new_vf, filter)
            end
        end
        if had_vs then
            mp.set_property_native("vf", new_vf)
        end
    else
        local vf_list = mp.get_property_native("vf") or {}
        local other_vf = {}
        for _, filter in ipairs(vf_list) do
            if filter.name ~= "vapoursynth" and not (filter.label and filter.label:find("interpolation")) then
                table.insert(other_vf, filter)
            end
        end
        mp.set_property_native("vf", other_vf)
        mp.add_timeout(0.05, function()
            local cur_vf = mp.get_property_native("vf") or {}
            local re_vf = {}
            for _, filter in ipairs(cur_vf) do
                if filter.name ~= "vapoursynth" and not (filter.label and filter.label:find("interpolation")) then
                    table.insert(re_vf, filter)
                end
            end
            table.insert(re_vf, {
                name = "vapoursynth",
                params = {
                    file = "~~/vs/interpolation.vpy",
                    ["buffered-frames"] = "4",
                    ["concurrent-frames"] = "4"
                }
            })
            mp.set_property_native("vf", re_vf)
        end)
    end
end

local function set_active_model(num, name, is_base_ready)
    update_player_conf_key("model", num)
    local is_ar = (current_language == "ar")
    if is_base_ready then
        reload_rife()
        mp.osd_message((is_ar and "نموذج RIFE: " or "RIFE Model: ") .. (name or tostring(num)) .. (is_ar and " (مفعّل ومبني)" or " (Live Applied)"), 2.5)
    else
        mp.osd_message((is_ar and "جاري تحضير وبناء محرك: " or "Preparing engine build: ") .. (name or tostring(num)), 3)
    end
end

mp.register_script_message("select_rife_model", function(m_str)
    local num = tonumber(m_str)
    if not num then return end
    local is_ar = (current_language == "ar")
    local model_defs = {
        [1] = { name_ar = "1. RIFE v4.25 — أعلى جودة", name_en = "1. RIFE v4.25 (Highest Quality)" },
        [2] = { name_ar = "2. RIFE v4.25 Lite — سريع ودقيق", name_en = "2. RIFE v4.25 Lite (Fast & Detailed)" },
        [3] = { name_ar = "3. RIFE v4.22 Lite — متوازن", name_en = "3. RIFE v4.22 Lite (Balanced)" },
        [4] = { name_ar = "4. RIFE v4.17 Lite — أسرع وأخف", name_en = "4. RIFE v4.17 Lite (Ultra Fast)" },
    }
    local m = model_defs[num]
    if not m then return end
    local base_ok = get_engine_status(num)
    local m_name = is_ar and m.name_ar or m.name_en
    if base_ok then
        set_active_model(num, m_name, true)
    else
        set_active_model(num, m_name, false)
        launch_single_model_build(num, is_ar, m_name)
    end
end)


local function get_menu_data()

    local cur_sub_font = mp.get_property("sub-font", "")
    local cur_sub_size = mp.get_property_number("sub-font-size", 45)
    local cur_sub_border = mp.get_property_number("sub-border-size", 2)
    local cur_sub_style = mp.get_property("sub-border-style", "outline-and-shadow")
    local cur_sub_back = mp.get_property("sub-back-color", "#00000000")
    local cur_sub_pos = mp.get_property_number("sub-pos", 100)
    local cur_sub_color = mp.get_property("sub-color", "#FFFFFF"):upper()
    local cur_sub_override = mp.get_property("sub-ass-override", "force")

    local cur_aspect = mp.get_property_number("video-aspect-override", -2)
    local cur_zoom = mp.get_property_number("video-zoom", 0)
    local cur_unscaled = mp.get_property_bool("video-unscaled", false)
    local cur_panscan = mp.get_property_number("panscan", 0)
    local cur_keepaspect = mp.get_property_bool("keepaspect", true)
    local cur_rotate = mp.get_property_number("video-rotate", 0)

    local cur_bright = mp.get_property_number("brightness", 0)
    local cur_contrast = mp.get_property_number("contrast", 0)
    local cur_sat = mp.get_property_number("saturation", 0)
    local cur_gamma = mp.get_property_number("gamma", 0)

    local cur_scale = mp.get_property_number("osd-scale", 1.0)
    local cur_ontop = mp.get_property_bool("ontop", false)
    local cur_fs = mp.get_property_bool("fullscreen", false)

    -- RIFE state
    local vf_list = mp.get_property_native("vf") or {}
    local rife_active = false
    for _, filter in ipairs(vf_list) do
        if filter.name == "vapoursynth" or (filter.label and filter.label:find("interpolation")) then
            rife_active = true
            break
        end
    end

    local vpy_path = mp.command_native({"expand-path", "~~/vs/interpolation.vpy"})
    local vpy_file = io.open(vpy_path, "r")
    local vpy_exists = false
    if vpy_file then
        vpy_exists = true
        vpy_file:close()
    end

    local is_ar = (current_language == "ar")
    local cur_model_id = 425
    local cur_rife_multi = 2
    local cur_rife_streams = 2
    local cur_uhd_mode = 1 -- Default: 1 (Bypass RIFE on 4K)
    local cur_rife_active_conf = true

    -- قراءة الإعدادات من player_settings.conf (مع الرجوع لـ rife_settings.conf عند الحاجة)
    local function read_rife_cfg()
        local rcfg = io.open(player_cfg_file, "r")
        if not rcfg then
            rcfg = io.open(mp.command_native({"expand-path", "~~/rife_settings.conf"}), "r")
        end
        if rcfg then
            for line in rcfg:lines() do
                local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
                if k and v then
                    k = k:lower()
                    if k == "model" then
                        local n = tonumber(v)
                        if n == 1 or n == 425 then cur_model_id = 425
                        elseif n == 2 or n == 4251 then cur_model_id = 4251
                        elseif n == 3 or n == 4221 then cur_model_id = 4221
                        elseif n == 4 or n == 4171 then cur_model_id = 4171
                        end
                    elseif k == "multi" then
                        cur_rife_multi = tonumber(v) or 2
                    elseif k == "streams" then
                        cur_rife_streams = tonumber(v) or 2
                    elseif k == "uhd_mode" then
                        cur_uhd_mode = tonumber(v) or 1
                    elseif k == "active" then
                        local vl = v:lower()
                        cur_rife_active_conf = (vl == "yes" or vl == "true" or vl == "1" or vl == "on")
                    end
                end
            end
            rcfg:close()
        end
    end

    read_rife_cfg()

    local function save_rife_cfg(multi, streams, uhd)
        if multi then
            cur_rife_multi = multi
            update_player_conf_key("multi", multi)
        end
        if streams then
            cur_rife_streams = streams
            update_player_conf_key("streams", streams)
        end
        if uhd then
            cur_uhd_mode = uhd
            update_player_conf_key("uhd_mode", uhd)
        end
        reload_rife()
    end

    local cur_fps_enabled = false
    local cur_fps_pos = "top-right"

    local function read_fps_cfg()
        local f = io.open(player_cfg_file, "r")
        if f then
            for line in f:lines() do
                local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
                if k and v then
                    local kl = k:lower()
                    if kl == "fps_counter" or kl == "fps_counter_enabled" then
                        local vl = v:lower()
                        cur_fps_enabled = (vl == "yes" or vl == "true" or vl == "1" or vl == "on")
                    elseif kl == "fps_counter_pos" or kl == "fps_counter_position" then
                        local vl = v:lower()
                        if vl == "top-left" or vl == "top-right" or vl == "top-center" then
                            cur_fps_pos = vl
                        end
                    end
                end
            end
            f:close()
        end
    end
    read_fps_cfg()

    local function set_fps_counter_state(enabled)
        cur_fps_enabled = enabled
        update_player_conf_key("fps_counter", enabled and "yes" or "no")
        mp.commandv("script-message-to", "fps_counter", "set_fps_enabled", enabled and "yes" or "no")
    end

    local function set_fps_counter_pos(pos)
        cur_fps_pos = pos
        update_player_conf_key("fps_counter_pos", pos)
        mp.commandv("script-message-to", "fps_counter", "set_fps_position", pos)
    end

    local active_shader_count = #get_active_shaders()
    local custom_shaders_list = get_custom_shaders(is_ar)

    local categories = {
        {
            id = "subtitle",
            title = is_ar and "أنماط الترجمة والخطوط" or "Subtitle Style",
            icon = "💬",
            flyouts = {
                {
                    id = "sub_style_mode",
                    title = is_ar and "وضع نمط الترجمة" or "Subtitle Style Mode",
                    badge = (cur_sub_override == "scale" or cur_sub_override == "no") and (is_ar and "ترجمة المصدر الأصلية" or "Embedded Style") or (is_ar and "تخصيص الخط المخصص" or "Custom Style"),
                    items = {
                        {
                            label = is_ar and "نمط المصدر الأصلي (Prefer Embedded Style)" or "Prefer Embedded Style (Source)",
                            desc = is_ar and "الحفاظ على خط وتنسيق وألوان المصدر الأصلية للملف (ass/srt) مع السماح بتعديل الحجم والموضع" or "Keep original embedded subtitle fonts, style, and styling (ass/srt)",
                            checked = (cur_sub_override == "scale" or cur_sub_override == "no"),
                            cmd = function() set_sub_mode("embedded") end
                        },
                        {
                            label = is_ar and "استخدام النمط المخصص (Use My Own Style)" or "Use My Own Style (Custom)",
                            desc = is_ar and "فرض الخط المخصص المختار وقواعد الإطار والألوان على جميع ملفات الترجمة" or "Force custom chosen font, colors, and border across all subtitles",
                            checked = (cur_sub_override == "force" or cur_sub_override == "yes" or cur_sub_override == "strip"),
                            cmd = function() set_sub_mode("custom") end
                        }
                    }
                },
                {
                    id = "font",
                    title = is_ar and "الخط المستخدم" or "Font Family",
                    badge = (cur_sub_font ~= "" and cur_sub_font or "Default"),
                    items = (function()
                        -- ── AR group ──
                        local t = {
                            { label = "sans-serif  [AR]",
                              checked = (cur_sub_font == "sans-serif" or cur_sub_font == ""),
                              cmd = function() set_sub_prop("sub-font", "sans-serif") end },
                            { label = "Noto Naskh Arabic  [AR]",
                              checked = (cur_sub_font == "Noto Naskh Arabic" or (cur_sub_font ~= "" and cur_sub_font:find("Noto Naskh") ~= nil)),
                              cmd = function() set_sub_prop("sub-font", "Noto Naskh Arabic") end },
                            { label = "Cairo  [AR]",
                              checked = (cur_sub_font == "Cairo" or (cur_sub_font ~= "" and cur_sub_font:find("Cairo") ~= nil)),
                              cmd = function() set_sub_prop("sub-font", "Cairo") end },
                            { label = "XB Zar  [AR]",
                              checked = (cur_sub_font == "XB Zar" or (cur_sub_font ~= "" and cur_sub_font:find("XB") ~= nil)),
                              cmd = function() set_sub_prop("sub-font", "XB Zar") end },
                            -- ── ENG group ──
                            { label = "Open Sans  [ENG]",
                              checked = (cur_sub_font == "Open Sans" or (cur_sub_font ~= "" and cur_sub_font:find("Open Sans") ~= nil)),
                              cmd = function() set_sub_prop("sub-font", "Open Sans") end },
                            { label = "Roboto  [ENG]",
                              checked = (cur_sub_font == "Roboto" or (cur_sub_font ~= "" and cur_sub_font:find("Roboto") ~= nil)),
                              cmd = function() set_sub_prop("sub-font", "Roboto") end },
                            { label = "Noto Sans  [ENG]",
                              checked = (cur_sub_font == "Noto Sans" or (cur_sub_font ~= "" and cur_sub_font:find("Noto Sans") ~= nil)),
                              cmd = function() set_sub_prop("sub-font", "Noto Sans") end },
                        }
                        -- ── Other: auto-detected from fonts/ folder ──
                        for _, item in ipairs(get_other_fonts(cur_sub_font)) do
                            table.insert(t, item)
                        end
                        return t
                    end)()
                },
                {
                    id = "font_size",
                    title = is_ar and "حجم الخط" or "Font Size",
                    badge = tostring(cur_sub_size) .. " pt",
                    items = {
                        { label = is_ar and "35 نقطة — صغير" or "35 pt — Small", checked = (cur_sub_size == 35), cmd = function() set_sub_prop("sub-font-size", 35) end },
                        { label = is_ar and "40 نقطة" or "40 pt", checked = (cur_sub_size == 40), cmd = function() set_sub_prop("sub-font-size", 40) end },
                        { label = is_ar and "45 نقطة — افتراضي" or "45 pt — Default", checked = (cur_sub_size == 45), cmd = function() set_sub_prop("sub-font-size", 45) end },
                        { label = is_ar and "50 نقطة" or "50 pt", checked = (cur_sub_size == 50), cmd = function() set_sub_prop("sub-font-size", 50) end },
                        { label = is_ar and "55 نقطة" or "55 pt", checked = (cur_sub_size == 55), cmd = function() set_sub_prop("sub-font-size", 55) end },
                        { label = is_ar and "60 نقطة — كبير" or "60 pt — Large", checked = (cur_sub_size == 60), cmd = function() set_sub_prop("sub-font-size", 60) end },
                        { label = is_ar and "[ + تكبير بمقدار 2 ]" or "[ +2 Increase Size ]", cmd = function() set_sub_prop("sub-font-size", cur_sub_size + 2) end },
                        { label = is_ar and "[ - تصغير بمقدار 2 ]" or "[ -2 Decrease Size ]", cmd = function() set_sub_prop("sub-font-size", math.max(12, cur_sub_size - 2)) end },
                    }
                },
                {
                    id = "border",
                    title = is_ar and "حجم الإطار" or "Border Outline",
                    badge = tostring(cur_sub_border),
                    items = {
                        { label = is_ar and "بلا إطار (0)" or "No Border (0)", checked = (cur_sub_border == 0), cmd = function() set_sub_prop("sub-border-size", 0) end },
                        { label = is_ar and "رفيع (1)" or "Thin (1)", checked = (cur_sub_border == 1), cmd = function() set_sub_prop("sub-border-size", 1) end },
                        { label = is_ar and "قياسي (2 — افتراضي)" or "Standard (2 — Default)", checked = (cur_sub_border == 2), cmd = function() set_sub_prop("sub-border-size", 2) end },
                        { label = is_ar and "متوسط (3)" or "Medium (3)", checked = (cur_sub_border == 3), cmd = function() set_sub_prop("sub-border-size", 3) end },
                        { label = is_ar and "سميك (4)" or "Thick (4)", checked = (cur_sub_border == 4), cmd = function() set_sub_prop("sub-border-size", 4) end },
                        { label = is_ar and "[ + تكبير الإطار ]" or "[ +1 Increase Border ]", cmd = function() set_sub_prop("sub-border-size", cur_sub_border + 1) end },
                        { label = is_ar and "[ - تصغير الإطار ]" or "[ -1 Decrease Border ]", cmd = function() set_sub_prop("sub-border-size", math.max(0, cur_sub_border - 1)) end },
                    }
                },
                {
                    id = "background_box",
                    title = is_ar and "صندوق الخلفية" or "Background Box",
                    items = {
                        { label = is_ar and "بلا خلفية (شفاف)" or "None (Transparent)", checked = (cur_sub_style == "outline-and-shadow"), cmd = function() set_sub_bg("outline-and-shadow", "#00000000") end },
                        { label = is_ar and "زجاج داكن (50%)" or "Dark Glass (50%)", checked = (cur_sub_style == "background-box" and cur_sub_back == "#80000000"), cmd = function() set_sub_bg("background-box", "#80000000") end },
                        { label = is_ar and "شبه صلب داكن (75%)" or "Dark Semi-Solid (75%)", checked = (cur_sub_style == "background-box" and cur_sub_back == "#BF000000"), cmd = function() set_sub_bg("background-box", "#BF000000") end },
                        { label = is_ar and "خلفية سوداء كاملة (100%)" or "Dark Solid (100%)", checked = (cur_sub_style == "background-box" and cur_sub_back == "#FF000000"), cmd = function() set_sub_bg("background-box", "#FF000000") end },
                        { label = is_ar and "زجاج فاتح (50%)" or "Light Glass (50%)", checked = (cur_sub_style == "background-box" and cur_sub_back == "#80FFFFFF"), cmd = function() set_sub_bg("background-box", "#80FFFFFF") end },
                    }
                },
                {
                    id = "color_preset",
                    title = is_ar and "لون النص" or "Color Preset",
                    items = {
                        { label = is_ar and "أبيض نقي (#FFFFFF)" or "Pure White (#FFFFFF)", checked = (cur_sub_color == "#FFFFFF"), cmd = function() set_sub_prop("sub-color", "#FFFFFF") end },
                        { label = is_ar and "أبيض دافئ (#FFF8E7)" or "Warm White (#FFF8E7)", checked = (cur_sub_color == "#FFF8E7"), cmd = function() set_sub_prop("sub-color", "#FFF8E7") end },
                        { label = is_ar and "أصفر فاتح (#FFFFB0)" or "Soft Yellow (#FFFFB0)", checked = (cur_sub_color == "#FFFFB0"), cmd = function() set_sub_prop("sub-color", "#FFFFB0") end },
                        { label = is_ar and "سماوي فاتح (#D0F0FD)" or "Light Cyan (#D0F0FD)", checked = (cur_sub_color == "#D0F0FD"), cmd = function() set_sub_prop("sub-color", "#D0F0FD") end },
                    }
                },
                {
                    id = "position",
                    title = is_ar and "موضع الترجمة" or "Vertical Position",
                    badge = tostring(cur_sub_pos),
                    items = {
                        { label = is_ar and "أسفل الشاشة (100 — افتراضي)" or "Bottom (100 — Default)", checked = (cur_sub_pos == 100), cmd = function() set_sub_prop("sub-pos", 100) end },
                        { label = is_ar and "أعلى قليلاً (90)" or "Higher (90)", checked = (cur_sub_pos == 90), cmd = function() set_sub_prop("sub-pos", 90) end },
                        { label = is_ar and "المنتصف (80)" or "Middle (80)", checked = (cur_sub_pos == 80), cmd = function() set_sub_prop("sub-pos", 80) end },
                        { label = is_ar and "أعلى الشاشة (10)" or "Top (10)", checked = (cur_sub_pos == 10), cmd = function() set_sub_prop("sub-pos", 10) end },
                        { label = is_ar and "[ ↑ تحريك للأعلى -2 ]" or "[ ↑ Move Up -2 ]", cmd = function() set_sub_prop("sub-pos", math.max(0, cur_sub_pos - 2)) end },
                        { label = is_ar and "[ ↓ تحريك للأسفل +2 ]" or "[ ↓ Move Down +2 ]", cmd = function() set_sub_prop("sub-pos", math.min(150, cur_sub_pos + 2)) end },
                    }
                },
                {
                    id = "reset_sub",
                    title = is_ar and "↺ إعادة ضبط الترجمة" or "↺ Reset Subtitle Style",
                    items = {
                        { label = is_ar and "تأكيد الإعادة للافتراضي" or "Confirm Reset to Default", cmd = function() reset_sub_style() end }
                    }
                }
            }
        },
        {
            id = "video",
            title = is_ar and "الفيديو وضبط الصورة" or "Video & Picture",
            icon = "🎬",
            flyouts = {
                {
                    id = "aspect_ratio",
                    title = is_ar and "نسبة العرض" or "Aspect Ratio",
                    items = {
                        { label = is_ar and "16:9 — عريض قياسي" or "16:9 (Standard Widescreen)", checked = (cur_aspect and math.abs(cur_aspect - 16/9) < 1e-3), cmd = function() mp.set_property("video-aspect-override", "16:9") end },
                        { label = is_ar and "4:3 — تلفاز كلاسيكي" or "4:3 (Classic TV)", checked = (cur_aspect and math.abs(cur_aspect - 4/3) < 1e-3), cmd = function() mp.set_property("video-aspect-override", "4:3") end },
                        { label = is_ar and "2.35:1 — سينمائي واسع" or "2.35:1 (Cinemascope)", checked = (cur_aspect == 2.35), cmd = function() mp.set_property("video-aspect-override", "2.35:1") end },
                        { label = is_ar and "تلقائي (افتراضي)" or "Default (Auto)", checked = (cur_aspect == -2), cmd = function() mp.set_property("video-aspect-override", "no") end },
                    }
                },
                {
                    id = "zoom_scaling",
                    title = is_ar and "التكبير والتحجيم" or "Zoom & Scaling",
                    items = {
                        { label = is_ar and "ملء الشاشة (قص الأشرطة السوداء)" or "Fill Screen (Crop Black Bars)", checked = (cur_panscan == 1), cmd = function() mp.command("no-osd cycle-values panscan 0 1; no-osd set video-unscaled no; no-osd set video-zoom 0") end },
                        { label = is_ar and "تمدد لملء النافذة" or "Stretch to Window", checked = (not cur_keepaspect), cmd = function() mp.command("no-osd cycle keepaspect") end },
                        { label = is_ar and "حجم البكسل الأصلي 1:1" or "Original 1:1 Pixel Size", checked = (cur_unscaled), cmd = function() mp.command("no-osd cycle-values video-unscaled yes no; no-osd set video-zoom 0; no-osd set panscan 0") end },
                        { label = is_ar and "75% من الحجم" or "75% Size", checked = (cur_zoom == -0.25), cmd = function() mp.set_property_number("video-zoom", -0.25) end },
                        { label = is_ar and "100% طبيعي (افتراضي)" or "100% Normal", checked = (cur_zoom == 0 and not cur_unscaled and cur_panscan == 0 and cur_keepaspect), cmd = function() mp.command("no-osd set video-zoom 0; no-osd set video-pan-x 0; no-osd set video-pan-y 0; no-osd set panscan 0; no-osd set video-unscaled no; no-osd set keepaspect yes") end },
                        { label = is_ar and "125% من الحجم" or "125% Size", checked = (cur_zoom == 0.25), cmd = function() mp.set_property_number("video-zoom", 0.25) end },
                        { label = is_ar and "150% من الحجم" or "150% Size", checked = (cur_zoom == 0.5), cmd = function() mp.set_property_number("video-zoom", 0.5) end },
                        { label = is_ar and "[ + تكبير 10% ]" or "[ Zoom In +10% ]", cmd = function() mp.command("add video-zoom 0.1") end },
                        { label = is_ar and "[ - تصغير 10% ]" or "[ Zoom Out -10% ]", cmd = function() mp.command("add video-zoom -0.1") end },
                    }
                },
                {
                    id = "orientation",
                    title = is_ar and "الاتجاه والتدوير" or "Orientation & Rotation",
                    items = {
                        { label = is_ar and "تدوير 90° عقارب الساعة" or "Rotate 90° Clockwise", cmd = function() mp.command("cycle-values video-rotate 90 180 270 0") end },
                        { label = is_ar and "تدوير 90° عكس عقارب الساعة" or "Rotate 90° Counter-Clockwise", cmd = function() mp.command("cycle-values video-rotate 270 180 90 0") end },
                        { label = is_ar and "إعادة ضبط التدوير (0°)" or "Reset Rotation (0°)", checked = (cur_rotate == 0), cmd = function() mp.set_property_number("video-rotate", 0) end },
                    }
                },
                {
                    id = "picture_tuning",
                    title = is_ar and "السطوع والألوان" or "Color & Picture Tuning",
                    items = {
                        { label = is_ar and string.format("السطوع: %d (اضغط للصفر)", cur_bright) or string.format("Brightness: %d (Click: 0)", cur_bright), cmd = function() mp.set_property_number("brightness", 0) end },
                        { label = is_ar and "  ↳ [ + رفع السطوع 5 ]" or "  ↳ [ +5 Brightness ]", cmd = function() mp.command("add brightness 5") end },
                        { label = is_ar and "  ↳ [ - خفض السطوع 5 ]" or "  ↳ [ -5 Brightness ]", cmd = function() mp.command("add brightness -5") end },
                        { label = is_ar and string.format("التباين: %d (اضغط للصفر)", cur_contrast) or string.format("Contrast: %d (Click: 0)", cur_contrast), cmd = function() mp.set_property_number("contrast", 0) end },
                        { label = is_ar and "  ↳ [ + رفع التباين 5 ]" or "  ↳ [ +5 Contrast ]", cmd = function() mp.command("add contrast 5") end },
                        { label = is_ar and "  ↳ [ - خفض التباين 5 ]" or "  ↳ [ -5 Contrast ]", cmd = function() mp.command("add contrast -5") end },
                        { label = is_ar and string.format("الإشباع: %d (اضغط للصفر)", cur_sat) or string.format("Saturation: %d (Click: 0)", cur_sat), cmd = function() mp.set_property_number("saturation", 0) end },
                        { label = is_ar and "  ↳ [ + رفع الإشباع 10 ]" or "  ↳ [ +10 Saturation ]", cmd = function() mp.command("add saturation 10") end },
                        { label = is_ar and "  ↳ [ - خفض الإشباع 10 ]" or "  ↳ [ -10 Saturation ]", cmd = function() mp.command("add saturation -10") end },
                        { label = is_ar and string.format("غاما: %d (اضغط للصفر)", cur_gamma) or string.format("Gamma: %d (Click: 0)", cur_gamma), cmd = function() mp.set_property_number("gamma", 0) end },
                        { label = is_ar and "  ↳ [ + تفتيح الظلال 5 ]" or "  ↳ [ +5 Brighten Shadows ]", cmd = function() mp.command("add gamma 5") end },
                        { label = is_ar and "  ↳ [ - تعتيم الظلال 5 ]" or "  ↳ [ -5 Darken Shadows ]", cmd = function() mp.command("add gamma -5") end },
                    }
                },
                {
                    id = "color_profiles",
                    title = is_ar and "إعدادات الصورة المسبقة" or "Picture Presets",
                    items = {
                        { label = is_ar and "طبيعي (افتراضي)" or "Natural (Default)", checked = (cur_bright == 0 and cur_contrast == 0 and cur_sat == 0 and cur_gamma == 0), cmd = function() mp.command("set brightness 0; set contrast 0; set saturation 0; set gamma 0; set hue 0") end },
                        { label = is_ar and "ألوان زاهية (+15 إشباع، +5 تباين)" or "Vivid Boost (+15 Sat, +5 Cont)", checked = (cur_sat == 15 and cur_contrast == 5), cmd = function() mp.command("set brightness 2; set contrast 5; set saturation 15; set gamma 0") end },
                        { label = is_ar and "مُحسِّن المشاهد الداكنة (+10 غاما)" or "Dark Scene Enhancer (+10 Gamma)", checked = (cur_gamma == 10), cmd = function() mp.command("set brightness 5; set contrast 5; set saturation 0; set gamma 10") end },
                        { label = is_ar and "تباين سينمائي" or "Cinema Contrast", checked = (cur_contrast == 10 and cur_sat == 5), cmd = function() mp.command("set brightness -2; set contrast 10; set saturation 5; set gamma -2") end },
                        { label = is_ar and "أبيض وأسود" or "Monochrome / B&W", checked = (cur_sat == -100), cmd = function() mp.command("set brightness 0; set contrast 5; set saturation -100; set gamma 0") end },
                        { label = is_ar and "↺ إعادة ضبط الألوان" or "↺ Reset Color Adjustments", cmd = function() mp.command("set brightness 0; set contrast 0; set saturation 0; set gamma 0; set hue 0") end },
                    }
                }
            }
        },
        {
            id = "audio",
            title = is_ar and "الصوت والتأخير" or "Audio & Sound",
            icon = "🔊",
            flyouts = {
                {
                    id = "audio_channels",
                    title = is_ar and "القنوات الصوتية والدمج" or "Channels & Downmix",
                    items = {
                        { label = is_ar and "تلقائي آمن — متعدد القنوات (افتراضي)" or "Auto-Safe (Multi-channel)", cmd = function() mp.set_property("audio-channels", "auto-safe") end },
                        { label = is_ar and "ستيريو — دمج ثنائي القناة (2.0)" or "Stereo (2.0 Downmix)", cmd = function() mp.set_property("audio-channels", "stereo") end },
                        { label = is_ar and "مونو — قناة واحدة (1.0)" or "Mono (1.0)", cmd = function() mp.set_property("audio-channels", "mono") end },
                    }
                },
                {
                    id = "audio_delay",
                    title = is_ar and "تأخير الصوت (مزامنة)" or "Audio Delay Sync",
                    items = {
                        { label = is_ar and "[ + تقديم الصوت 10ms ]" or "[ +10ms Advance Audio ]", cmd = function() mp.command("add audio-delay 0.010") end },
                        { label = is_ar and "[ - تأخير الصوت 10ms ]" or "[ -10ms Delay Audio ]", cmd = function() mp.command("add audio-delay -0.010") end },
                        { label = is_ar and "إعادة ضبط التأخير (0ms)" or "Reset Audio Delay (0ms)", cmd = function() mp.set_property_number("audio-delay", 0) end },
                    }
                }
            }
        },
        {
            id = "window",
            title = is_ar and "النافذة وتحجيم الواجهة" or "Window & UI Scale",
            icon = "🪟",
            flyouts = {
                {
                    id = "ui_scaling",
                    title = is_ar and "حجم الواجهة والعروض" or "UI & OSD Scale",
                    badge = string.format("%d%%", math.floor(cur_scale * 100 + 0.5)),
                    items = {
                        { label = is_ar and "50% — صغير ومضغوط" or "50% Compact", checked = (math.abs(cur_scale - 0.5) < 0.05), cmd = function() set_ui_scale(0.5) end },
                        { label = is_ar and "80% — أنيق" or "80% Sleek", checked = (math.abs(cur_scale - 0.8) < 0.05), cmd = function() set_ui_scale(0.8) end },
                        { label = is_ar and "100% — قياسي (افتراضي)" or "100% Standard (Default)", checked = (math.abs(cur_scale - 1.0) < 0.05), cmd = function() set_ui_scale(1.0) end },
                        { label = is_ar and "120% — متوسط" or "120% Medium", checked = (math.abs(cur_scale - 1.2) < 0.05), cmd = function() set_ui_scale(1.2) end },
                        { label = is_ar and "150% — كبير" or "150% Large", checked = (math.abs(cur_scale - 1.5) < 0.05), cmd = function() set_ui_scale(1.5) end },
                        { label = is_ar and "200% — ضخم" or "200% Extra Large", checked = (math.abs(cur_scale - 2.0) < 0.05), cmd = function() set_ui_scale(2.0) end },
                    }
                },
                {
                    id = "fps_counter_menu",
                    title = is_ar and "عداد الإطارات المباشر (FPS Counter)" or "Live FPS Counter",
                    badge = cur_fps_enabled and (is_ar and "مفعّل" or "ON") or (is_ar and "معطّل" or "OFF"),
                    items = {
                        {
                            label = is_ar and "تشغيل عداد الإطارات (ON)" or "Enable FPS Counter (ON)",
                            desc = is_ar and "قراءة فعلية دقيقة ومطابقة لـ RTSS بالملي ثانية" or "Physical real-time frame measurement matching RTSS",
                            checked = cur_fps_enabled,
                            cmd = function() set_fps_counter_state(true) end
                        },
                        {
                            label = is_ar and "إيقاف عداد الإطارات (OFF)" or "Disable FPS Counter (OFF)",
                            checked = not cur_fps_enabled,
                            cmd = function() set_fps_counter_state(false) end
                        },
                        {
                            label = is_ar and "── موضع العرض على الشاشة ──" or "── HUD Position ──",
                            cmd = function() end
                        },
                        {
                            label = is_ar and "أعلى اليمين (Top Right)" or "Top Right",
                            checked = (cur_fps_pos == "top-right"),
                            cmd = function() set_fps_counter_pos("top-right") end
                        },
                        {
                            label = is_ar and "أعلى اليسار (Top Left)" or "Top Left",
                            checked = (cur_fps_pos == "top-left"),
                            cmd = function() set_fps_counter_pos("top-left") end
                        },
                        {
                            label = is_ar and "أعلى المنتصف (Top Center)" or "Top Center",
                            checked = (cur_fps_pos == "top-center"),
                            cmd = function() set_fps_counter_pos("top-center") end
                        },
                    }
                },
                {
                    id = "window_controls",
                    title = is_ar and "التحكم بالنافذة" or "Window Controls",
                    items = {
                        { label = is_ar and "تبديل الشاشة الكاملة" or "Toggle Fullscreen", checked = cur_fs, cmd = function() mp.command("cycle fullscreen") end },
                        { label = is_ar and "تثبيت النافذة فوق كل شيء" or "Stay on Top", checked = cur_ontop, cmd = function() mp.command("cycle ontop") end },
                        { label = is_ar and "التقاط صورة" or "Take Screenshot", cmd = function() mp.command("screenshot") end },
                        { label = is_ar and "صورة (بدون ترجمة)" or "Screenshot (No Subtitles)", cmd = function() mp.command("screenshot video") end },
                    }
                }
            }
        },
        {
            id = "shaders",
            title = is_ar and "الشيدرز ومؤثرات الفيديو" or "Shaders & Video FX",
            icon = "✨",
            flyouts = {
                {
                    id = "shader_status",
                    title = is_ar and "حالة الشيدرز النشطة" or "Active Shaders Status",
                    badge = (active_shader_count > 0 and (tostring(active_shader_count) .. (is_ar and " نشط" or " Active")) or (is_ar and "لا يوجد" or "None")),
                    items = {
                        {
                            label = is_ar and
                                (active_shader_count > 0 and ("● " .. tostring(active_shader_count) .. " شيدر نشط") or "○ لا يوجد شيدرز نشطة") or
                                (active_shader_count > 0 and ("● " .. tostring(active_shader_count) .. " Shader(s) Active") or "○ No Shaders Active"),
                            desc = is_ar and "الشيدرز تعمل مباشرةً على GPU بدون تأخير تجميع" or "Shaders process live on GPU with ~0 compile time",
                            checked = (active_shader_count > 0),
                            cmd = function()
                                local str = mp.get_property("glsl-shaders", "")
                                if str == "" then
                                    mp.osd_message(is_ar and "لا توجد شيدرز نشطة" or "No shaders active", 2)
                                else
                                    mp.osd_message((is_ar and "الشيدرز النشطة:\n" or "Active Shaders:\n") .. str:gsub(";", "\n"), 4)
                                end
                            end
                        },
                        {
                            label = is_ar and "✕ إيقاف جميع الشيدرز النشطة" or "✕ Clear All Active Shaders",
                            desc = is_ar and "تعطيل جميع شيدرز GLSL و Hook فورًا" or "Disable all active GLSL and Hook shaders instantly",
                            cmd = function() clear_all_shaders() end
                        }
                    }
                },
                {
                    id = "shader_anime",
                    title = is_ar and "Anime4K — تحسين رسوم الأنيمي" or "Anime Enhancement (Anime4K)",
                    badge = (is_shader_active("Anime4K") and (is_ar and "نشط" or "Active") or (is_ar and "معطل" or "Off")),
                    items = {
                        {
                            label = "Anime4K: Restore CNN — " .. (is_ar and "(استعادة الخطوط وإزالة الضوضاء)" or "Mode A - Clean"),
                            desc = is_ar and "يعيد رسم الخطوط ويزيل ضبابية الضغط والتشويش" or "Restores lines, removes blurring & compression noise",
                            checked = is_shader_active("Anime4K_Restore_CNN_M.glsl"),
                            cmd = function() toggle_shader("Anime4K_Restore_CNN_M.glsl", "Anime4K Restore CNN") end
                        },
                        {
                            label = "Anime4K: Restore CNN VL — " .. (is_ar and "(جودة عالية لـ 1080p)" or "Very-Large HQ"),
                            desc = is_ar and "شبكة عصبية عميقة لاستعادة دقة عالية" or "High-precision line restoration for 1080p anime",
                            checked = is_shader_active("Anime4K_Restore_CNN_VL.glsl"),
                            cmd = function() toggle_shader("Anime4K_Restore_CNN_VL.glsl", "Anime4K Restore VL") end
                        },
                        {
                            label = "Anime4K: Upscale CNN x2 — " .. (is_ar and "(تكبير ذكي x2)" or "Neural Upscale x2"),
                            desc = is_ar and "تكبير عصبي 2× عالي الجودة للأنيمي" or "High quality 2x neural upscaling for anime and cartoons",
                            checked = is_shader_active("Anime4K_Upscale_CNN_x2_M.glsl"),
                            cmd = function() toggle_shader("Anime4K_Upscale_CNN_x2_M.glsl", "Anime4K Upscale x2") end
                        },
                        {
                            label = "Anime4K: Darken Lines — " .. (is_ar and "(تعميق خطوط الحبر)" or "HQ Line Darkening"),
                            desc = is_ar and "يعزز عمق خطوط الرسم وتباينها" or "Enhances anime ink line depth, contrast, and prominence",
                            checked = is_shader_active("Anime4K_Darken_HQ.glsl"),
                            cmd = function() toggle_shader("Anime4K_Darken_HQ.glsl", "Anime4K Darken Lines") end
                        },
                        {
                            label = "Anime4K: Thin Lines — " .. (is_ar and "(ترفيع خطوط الحواف)" or "HQ Line Thinning"),
                            desc = is_ar and "يرفّع الخطوط السميكة لمظهر حديث وحاد" or "Refines heavy outlines for sharper, crisp modern look",
                            checked = is_shader_active("Anime4K_Thin_HQ.glsl"),
                            cmd = function() toggle_shader("Anime4K_Thin_HQ.glsl", "Anime4K Thin Lines") end
                        }
                    }
                },
                {
                    id = "shader_fsrcnnx",
                    title = is_ar and "FSRCNNX / RAVU — مكبرات ذكاء اصطناعي" or "AI Neural Scalers (FSRCNNX / RAVU)",
                    badge = ((is_shader_active("FSRCNNX") or is_shader_active("ravu")) and (is_ar and "نشط" or "Active") or (is_ar and "معطل" or "Off")),
                    items = {
                        {
                            label = "FSRCNNX x2 (8-0-4-1) — " .. (is_ar and "(تحسين خطوط الرسوم سريع)" or "LineArt Fast"),
                            desc = is_ar and "مكبّر ذكائي سريع موجّه لوضوح الخطوط" or "Fast neural upscaler tuned specifically for line clarity",
                            checked = is_shader_active("FSRCNNX_x2_8_0_4_1_LineArt.glsl"),
                            cmd = function() toggle_shader("FSRCNNX_x2_8_0_4_1_LineArt.glsl", "FSRCNNX LineArt x2") end
                        },
                        {
                            label = "FSRCNNX x2 (16-0-4-1) — " .. (is_ar and "(جودة عالية 16 طبقة)" or "High Quality 16-layer"),
                            desc = is_ar and "شبكة عصبية عميقة 16 طبقة لتكبير فائق الجودة" or "Deep 16-layer convolutional neural network upscaler",
                            checked = is_shader_active("FSRCNNX_x2_16_0_4_1.glsl"),
                            cmd = function() toggle_shader("FSRCNNX_x2_16_0_4_1.glsl", "FSRCNNX 16-0-4-1 x2") end
                        },
                        {
                            label = "RAVU Zoom AR R3 — " .. (is_ar and "(مكبّر مع مكافحة الضجيج)" or "Anti-Ringing Upscaler"),
                            desc = is_ar and "RAVU: مكبّر دقيق سريع مع خوارزمية مكافحة الضجيج" or "Rapid Accurate Video Upscaler with anti-ringing compute",
                            checked = is_shader_active("ravu-zoom-ar-r3-rgb.hook"),
                            cmd = function() toggle_shader("ravu-zoom-ar-r3-rgb.hook", "RAVU Zoom AR R3") end
                        }
                    }
                },
                {
                    id = "shader_sharpen",
                    title = is_ar and "CAS / AMD — تحسين الحدة والوضوح" or "Clarity & Sharpening (CAS / Adaptive)",
                    badge = ((is_shader_active("AMD") or is_shader_active("Adaptive_sharpen")) and (is_ar and "نشط" or "Active") or (is_ar and "معطل" or "Off")),
                    items = {
                        {
                            label = "AMD FidelityFX CAS — " .. (is_ar and "(تحسين تكيفي للحدة)" or "Contrast Adaptive Sharpen"),
                            desc = is_ar and "معيار الصناعة — يحسّن التفاصيل بدون تشويش" or "Industry standard sharpener - crisps details with zero halos",
                            checked = is_shader_active("AMD_CAS_AIO_RT.glsl"),
                            cmd = function() toggle_shader("AMD_CAS_AIO_RT.glsl", "AMD FidelityFX CAS") end
                        },
                        {
                            label = "AMD FSR RCAS — " .. (is_ar and "(تحديد حاد للسطوع)" or "Robust CAS Luma Sharpening"),
                            desc = is_ar and "FSR 1.0 RCAS: تحسين حدة مستهدف للسطوع" or "FSR 1.0 RCAS sharpening targeted at luminance",
                            checked = is_shader_active("AMD_FSR_RCAS_luma_RT.glsl"),
                            cmd = function() toggle_shader("AMD_FSR_RCAS_luma_RT.glsl", "AMD FSR RCAS") end
                        },
                        {
                            label = "Adaptive Sharpen — " .. (is_ar and "(تحسين حواف ذكي)" or "Smart Edge Mask"),
                            desc = is_ar and "يحسّن الحواف ديناميكيًا مع الحفاظ على المناطق المستوية" or "Enhances edges dynamically while preserving flat areas",
                            checked = is_shader_active("Adaptive_sharpen_RT.glsl"),
                            cmd = function() toggle_shader("Adaptive_sharpen_RT.glsl", "Adaptive Sharpen") end
                        }
                    }
                },
                {
                    id = "shader_custom",
                    title = is_ar and "شيدرز إضافية ومخصصة" or "Custom & Extra Shaders",
                    badge = (#custom_shaders_list > 0 and (tostring(#custom_shaders_list) .. (is_ar and " متوفر" or " Found")) or (is_ar and "لا يوجد" or "None")),
                    items = #custom_shaders_list > 0 and custom_shaders_list or {
                        {
                            label = is_ar and "○ لا توجد ملفات شيدر إضافية" or "○ No custom shaders found",
                            desc = is_ar and "أضف أي ملف .glsl أو .hook في مجلد shaders/ وسيظهر هنا فوراً" or "Drop any .glsl or .hook files into shaders/ to see them here",
                            cmd = function() end
                        }
                    }
                }
            }
        },
        {
            id = "ai",
            title = is_ar and "محرك نموذج RIFE" or "AI / RIFE Engine",
            icon = "🧠",
            flyouts = (not vpy_exists) and {
                {
                    id = "rife_unavailable",
                    title = is_ar and "RIFE — غير متاح" or "RIFE Status",
                    items = {
                        { label = is_ar and "⚠️ ملف VapourSynth (interpolation.vpy) غير موجود" or "VapourSynth script (interpolation.vpy) not found", cmd = function() end }
                    }
                }
            } or {
                {
                    id = "rife_state",
                    title = is_ar and "حالة RIFE (توليد الإطارات)" or "Interpolation Status",
                    items = (function()
                        local active_model_num = (cur_model_id == 425 and 1) or (cur_model_id == 4251 and 2) or (cur_model_id == 4221 and 3) or (cur_model_id == 4171 and 4) or 1
                        local onnx_ok = is_model_onnx_present(active_model_num)
                        local base_ok = onnx_ok and get_engine_status(active_model_num)
                        local is_actually_interpolating = rife_active and onnx_ok and base_ok and cur_rife_active_conf

                        local status_text = ""
                        if not onnx_ok then
                            status_text = is_ar and "○ RIFE معطل — النموذج غير موجود على القرص (أمان تلقائي)" or "○ RIFE Disabled — Selected model missing from disk (Safe Fallback)"
                        elseif not base_ok then
                            status_text = is_ar and "○ RIFE معطل — المحرك غير مبني بعد (أمان تلقائي)" or "○ RIFE Disabled — Engine not built yet (Safe Fallback)"
                        elseif not cur_rife_active_conf then
                            status_text = is_ar and "○ RIFE معطل — تم إيقافه يدوياً" or "○ RIFE Disabled — Manually turned off"
                        elseif rife_active then
                            status_text = is_ar and "● RIFE يعمل — توليد إطارات نشط ومبني" or "● RIFE is Running (Active & Accelerated)"
                        else
                            status_text = is_ar and "○ RIFE معطل" or "○ RIFE is Disabled"
                        end

                        return {
                            {
                                label = status_text,
                                desc = (not onnx_ok or not base_ok) and (is_ar and "يعمل الفيديو بالسرعة الأصلية الخالصة لتفادي أي تعليق أو خطأ" or "Video is playing natively to prevent freezes or errors") or nil,
                                desc_warning = (not onnx_ok or not base_ok),
                                checked = is_actually_interpolating,
                                cmd = function()
                                    mp.commandv("script-binding", "mode_notify/toggle_rife")
                                    read_rife_cfg()
                                end
                            },
                            {
                                label = is_ar and "تبديل تشغيل/إيقاف (F1)" or "Toggle On / Off (F1)",
                                desc = is_ar and "تفعيل أو تعطيل RIFE وحفظ الحالة" or "Toggle RIFE and persist state",
                                checked = is_actually_interpolating,
                                cmd = function()
                                    mp.commandv("script-binding", "mode_notify/toggle_rife")
                                    read_rife_cfg()
                                end
                            },
                        }
                    end)()
                },
                {
                    id = "rife_models",
                    title = is_ar and "RIFE — اختيار النموذج" or "RIFE Model Selection",
                    badge = (function()
                        local active_num = 1
                        local base_name = "v4.25"
                        if cur_model_id == 425 then active_num = 1; base_name = "v4.25"
                        elseif cur_model_id == 4251 then active_num = 2; base_name = "v4.25 Lite"
                        elseif cur_model_id == 4221 then active_num = 3; base_name = "v4.22 Lite"
                        elseif cur_model_id == 4171 then active_num = 4; base_name = "v4.17 Lite"
                        end
                        if not is_model_onnx_present(active_num) then
                            return is_ar and "غير متوفر" or "Not Found"
                        end
                        local base_ok = get_engine_status(active_num)
                        if not base_ok then
                            return base_name .. (is_ar and " (غير مبني)" or " (Need Build)")
                        end
                        return base_name
                    end)(),
                    items = (function()
                        local model_defs = {
                            { num = 1, id = 425,  name_ar = "1. RIFE v4.25 — أعلى جودة", name_en = "1. RIFE v4.25 (Highest Quality)" },
                            { num = 2, id = 4251, name_ar = "2. RIFE v4.25 Lite — سريع ودقيق", name_en = "2. RIFE v4.25 Lite (Fast & Detailed)" },
                            { num = 3, id = 4221, name_ar = "3. RIFE v4.22 Lite — متوازن", name_en = "3. RIFE v4.22 Lite (Balanced)" },
                            { num = 4, id = 4171, name_ar = "4. RIFE v4.17 Lite — أسرع وأخف", name_en = "4. RIFE v4.17 Lite (Ultra Fast)" },
                        }
                        local list = {}
                        local all_base_ok = true
                        local available_count = 0

                        for _, m in ipairs(model_defs) do
                            if is_model_onnx_present(m.num) then
                                available_count = available_count + 1
                                local base_ok, uhd_ok, model_state = get_engine_status(m.num)
                                if not base_ok then
                                    all_base_ok = false
                                end

                                local status_badge = ""
                                local desc_str = ""
                                local is_warning = false

                                if base_ok then
                                    status_badge = is_ar and "  [✓ جاهز]" or "  [✓ Ready]"
                                    desc_str = is_ar and "✓ محركات النموذج مبنية وجاهزة في الكاش" or "✓ Model TensorRT engines ready in cache"
                                else
                                    status_badge = is_ar and "  ⚠️ [يحتاج بناء! Need Build!]" or "  ⚠️ [Need Build!]"
                                    desc_str = is_ar and "⚠️ اضغط هنا لبناء محركات هذا النموذج فوراً" or "⚠️ Click here to build engines for this model now"
                                    is_warning = true
                                end

                                table.insert(list, {
                                    label = (is_ar and m.name_ar or m.name_en) .. status_badge,
                                    desc = desc_str,
                                    desc_warning = is_warning,
                                    checked = (cur_model_id == m.id),
                                    cmd = function()
                                        if base_ok then
                                            set_active_model(m.num, is_ar and m.name_ar or m.name_en, true)
                                        else
                                            set_active_model(m.num, is_ar and m.name_ar or m.name_en, false)
                                            launch_single_model_build(m.num, is_ar, is_ar and m.name_ar or m.name_en)
                                        end
                                    end
                                })
                            end
                        end

                        if available_count == 0 then
                            table.insert(list, {
                                label = is_ar and "⚠️ لا توجد أي نماذج RIFE مثبتة على القرص" or "⚠️ No RIFE models found on disk",
                                desc = is_ar and "تأكد من وجود ملفات النماذج (.onnx) في مجلد vs/vs-plugins/models/rife_v2" or "Ensure .onnx model files exist in vs/vs-plugins/models/rife_v2",
                                desc_warning = true,
                                cmd = function() end
                            })
                        elseif not all_base_ok then
                            table.insert(list, {
                                label = is_ar and "🔨 [ بناء كافة محركات RIFE للنماذج المتوفرة ]" or "🔨 [ Build Engines for All Available Models ]",
                                desc = is_ar and "بدء بناء كامل محركات النماذج المتوفرة" or "Compiles engines for all available models",
                                desc_warning = true,
                                cmd = function()
                                    launch_default_engine_build(is_ar)
                                end
                            })
                        end

                        return list
                    end)()
                },
                {
                    id = "rife_multi_exp",
                    title = is_ar and "RIFE — مضاعف عدد الإطارات (تجريبي)" or "Frame Multiplier (Experimental)",
                    badge = tostring(cur_rife_multi) .. "x",
                    items = {
                        { label = is_ar and "2x — (ضعف عدد الايطارات)" or "2x Multiplier (Standard / Default)", checked = (cur_rife_multi == 2), cmd = function()
                            save_rife_cfg(2, cur_rife_streams, cur_uhd_mode)
                            mp.osd_message(is_ar and "RIFE: 2x — مفعّل" or "RIFE Multiplier: 2x (Live Applied)", 2)
                        end },
                        { label = is_ar and "3x" or "3x", checked = (cur_rife_multi == 3), cmd = function()
                            save_rife_cfg(3, cur_rife_streams, cur_uhd_mode)
                            mp.osd_message(is_ar and "RIFE: 3x — مفعّل" or "RIFE Multiplier: 3x (Live Applied)", 2)
                        end },
                        { label = is_ar and "4x" or "4x", checked = (cur_rife_multi == 4), cmd = function()
                            save_rife_cfg(4, cur_rife_streams, cur_uhd_mode)
                            mp.osd_message(is_ar and "RIFE: 4x — مفعّل" or "RIFE Multiplier: 4x (Live Applied)", 2)
                        end },
                        { label = is_ar and "5x" or "5x", checked = (cur_rife_multi == 5), cmd = function()
                            save_rife_cfg(5, cur_rife_streams, cur_uhd_mode)
                            mp.osd_message(is_ar and "RIFE: 5x — مفعّل" or "RIFE Multiplier: 5x (Live Applied)", 2)
                        end },
                        { label = is_ar and "6x" or "6x", checked = (cur_rife_multi == 6), cmd = function()
                            save_rife_cfg(6, cur_rife_streams, cur_uhd_mode)
                            mp.osd_message(is_ar and "RIFE: 6x — مفعّل" or "RIFE Multiplier: 6x (Live Applied)", 2)
                        end },
                    }
                },
                {
                    id = "rife_streams_exp",
                    title = is_ar and "TensorRT Streams — (تجريبي)" or "TensorRT Streams (Experimental)",
                    badge = tostring(cur_rife_streams) .. (is_ar and " تدفق" or " Streams"),
                    items = {
                        { label = is_ar and "1 تدفق — استخدام VRAM منخفض" or "1 Stream (Low VRAM Usage)", checked = (cur_rife_streams == 1), cmd = function()
                            save_rife_cfg(cur_rife_multi, 1, cur_uhd_mode)
                            mp.osd_message(is_ar and "TensorRT: 1 تدفق — مفعّل" or "TensorRT Streams: 1 (Live Applied)", 2)
                        end },
                        { label = is_ar and "2 تدفق — أمثل / افتراضي" or "2 Streams (Optimal / Default)", checked = (cur_rife_streams == 2), cmd = function()
                            save_rife_cfg(cur_rife_multi, 2, cur_uhd_mode)
                            mp.osd_message(is_ar and "TensorRT: 2 تدفق — مفعّل" or "TensorRT Streams: 2 (Live Applied)", 2)
                        end },
                        { label = is_ar and "3 تدفق — توازِ متوسط" or "3 Streams (Enhanced Parallelism)", checked = (cur_rife_streams == 3), cmd = function()
                            save_rife_cfg(cur_rife_multi, 3, cur_uhd_mode)
                            mp.osd_message(is_ar and "TensorRT: 3 تدفق — مفعّل" or "TensorRT Streams: 3 (Live Applied)", 2)
                        end },
                        { label = is_ar and "4 تدفق — توازي عالي" or "4 Streams (High Parallelism)", checked = (cur_rife_streams == 4), cmd = function()
                            save_rife_cfg(cur_rife_multi, 4, cur_uhd_mode)
                            mp.osd_message(is_ar and "TensorRT: 4 تدفق — مفعّل" or "TensorRT Streams: 4 (Live Applied)", 2)
                        end },
                        { label = is_ar and "5 تدفق — تشغيل مكثف" or "5 Streams (Aggressive)", checked = (cur_rife_streams == 5), cmd = function()
                            save_rife_cfg(cur_rife_multi, 5, cur_uhd_mode)
                            mp.osd_message(is_ar and "TensorRT: 5 تدفق — مفعّل" or "TensorRT Streams: 5 (Live Applied)", 2)
                        end },
                        { label = is_ar and "6 تدفق — أقصى حد" or "6 Streams (Extreme / Max)", checked = (cur_rife_streams == 6), cmd = function()
                            save_rife_cfg(cur_rife_multi, 6, cur_uhd_mode)
                            mp.osd_message(is_ar and "TensorRT: 6 تدفق — مفعّل" or "TensorRT Streams: 6 (Live Applied)", 2)
                        end },
                    }
                },
                {
                    id = "rife_uhd_mode",
                    title = is_ar and "4K / UHD — معالجة الدقة العالية" or "4K & Ultra HD Processing",
                    badge = (cur_uhd_mode == 1 and (is_ar and "معطل في 4K" or "Off in 4K")) or (is_ar and "1080p سلس" or "1080p Smooth"),
                    items = (function()
                        local t = {
                            {
                                label = is_ar and "1. معطل في 4K — (تشغيل أصلي بدون AI)" or "1. Off in 4K (Passthrough)",
                                desc = is_ar and "يوقف الذكاء الاصطناعي على محتوى 4K/UHD (تشغيل أصلي خالص — يوفّر GPU)" or "Disables AI on 4K/UHD videos (Pure native playback - Saves GPU)",
                                checked = (cur_uhd_mode == 1),
                                cmd = function()
                                    save_rife_cfg(cur_rife_multi, cur_rife_streams, 1)
                                    if is_current_video_uhd() then
                                        mp.osd_message(is_ar and "4K: معطل — تشغيل أصلي خالص (بدون أي ضغط على العتاد)" or "4K Mode: Off (Pure Native Hardware Playback - Zero AI)", 3)
                                    else
                                        mp.osd_message(is_ar and "4K: معطل (توليد الفريمات مفعّل لدقة 1080p وما دون)" or "4K Mode: Off for 4K (RIFE active on 1080p and lower)", 3)
                                    end
                                end
                            },
                            {
                                label = is_ar and "2. تصغير إلى 1080p — (موصى به)" or "2. Downscale to 1080p (Recommended)",
                                desc = is_ar and "يضغط 4K إلى 1080p لذكاء اصطناعي فائق السلاسة (بدون تهالط إطارات)" or "Resizes 4K to 1080p for ultra-smooth AI (Zero Frame Drops)",
                                checked = (cur_uhd_mode == 2),
                                cmd = function()
                                    save_rife_cfg(cur_rife_multi, cur_rife_streams, 2)
                                    mp.osd_message(is_ar and "4K: تصغير إلى 1080p — مفعّل بسلاسة تامة" or "4K Mode: 1080p Smooth Downscale (Live Applied)", 3)
                                end
                            },
                            -- [ملاحظة: تم تعطيل خيار 3 (4K Native RIFE) وبناء محركات 4K مؤقتاً لثقل المعالجة الفائق وعدم استقراره حتى على كروت RTX 5080/5070Ti]
                        }
                        return t
                    end)()
                },
                {
                    id = "rife_reset_exp",
                    title = is_ar and "↺ إعادة ضبط RIFE للافتراضي" or "↺ Reset RIFE to Default",
                    items = {
                        { label = is_ar and "إعادة الضبط (2x مضاعف، 2 تدفق، وضع 1080p، نموذج 4)" or "Reset Settings to Default (2x Multi, 2 Streams, 1080p, Model 4)", cmd = function()
                            save_rife_cfg(2, 2, 2)
                            set_active_model(4, is_ar and "RIFE v4.17 Lite — أسرع وأخف" or "RIFE v4.17 Lite")
                            mp.osd_message(is_ar and "RIFE: إعادة ضبط (2x، 2 تدفق، 1080p، نموذج 4)" or "RIFE Reset to Defaults (2x Multi, 2 Streams, 1080p, Model 4)", 2.5)
                        end }
                    }
                }
            }
        },
        {
            id = "language",
            title = is_ar and "اللغة" or "Language",
            icon = "🌐",
            flyouts = {
                {
                    id = "lang_options",
                    title = is_ar and "اللغة" or "Language",
                    badge = (current_language == "ar" and "العربية" or "English"),
                    items = {
                        {
                            label = "العربية",
                            checked = (current_language == "ar"),
                            cmd = function() set_app_language("ar") end
                        },
                        {
                            label = "English",
                            checked = (current_language == "eng"),
                            cmd = function() set_app_language("eng") end
                        },
                    }
                }
            }
        }
    }

    return categories
end

-- ==============================================================================
-- ASS Drawing & UI Rendering
-- ==============================================================================

local function render_sidebar()
    if not is_open then
        overlay.data = ""
        overlay:update()
        return
    end

    local screen_w, screen_h = mp.get_osd_size()
    if not screen_w or screen_w == 0 then
        screen_w, screen_h = 1920, 1080
    end

    local s = get_ui_scale()

    -- 1. Space at Top for OSD Toasts, and Space at Bottom above ModernZ bar
    local top_margin = math.floor(70 * s)
    local bot_margin = math.floor(95 * s)

    local card_y1 = top_margin
    local card_y2 = screen_h - bot_margin
    if card_y2 <= card_y1 + 100 then
        card_y2 = card_y1 + 100
    end

    local is_ar = (current_language == "ar")
    local sb_w = math.floor(290 * s)
    local fo_w = math.floor(360 * s)
    local sb_x1, sb_x2, fo_x1, fo_x2

    if is_ar then
        -- Arabic Mode: Sidebar on the RIGHT, Flyout opens to the LEFT (towards center)
        sb_x2 = screen_w - math.floor(18 * s)
        sb_x1 = sb_x2 - sb_w
        fo_x2 = sb_x1 - math.floor(10 * s)
        fo_x1 = fo_x2 - fo_w
        if fo_x1 < math.floor(10 * s) then fo_x1 = math.floor(10 * s) end
    else
        -- English Mode: Sidebar on the LEFT, Flyout opens to the RIGHT
        sb_x1 = math.floor(18 * s)
        sb_x2 = sb_x1 + sb_w
        fo_x1 = sb_x2 + math.floor(10 * s)
        fo_x2 = fo_x1 + fo_w
        if fo_x2 > screen_w - math.floor(10 * s) then fo_x2 = screen_w - math.floor(10 * s) end
    end

    -- Save layout bounds for mouse hit tests & protection
    layout.sb_x1, layout.sb_y1, layout.sb_x2, layout.sb_y2 = sb_x1, card_y1, sb_x2, card_y2
    layout.fo_x1, layout.fo_y1, layout.fo_x2, layout.fo_y2 = fo_x1, card_y1, fo_x2, card_y2

    local corner_r = math.floor(12 * s)
    local pad = math.floor(14 * s)
    local item_h = math.floor(44 * s)       -- Roomier, comfortable category fields
    local fo_head_h = math.floor(42 * s)    -- Roomier flyout section headers
    local fo_itm_h = math.floor(36 * s)     -- Standard option rows
    local font_title = math.floor(18 * s)   -- Crisp, larger title
    local font_item = math.floor(15 * s)    -- Crisp item font
    local font_sub = math.floor(14 * s)
    local font_badge = math.floor(12 * s)

    overlay.res_x = screen_w
    overlay.res_y = screen_h

    local ass = assdraw.ass_new()
    hitboxes = {}

    local menu_categories = get_menu_data()

    -- =========================================================================
    -- 1. Draw Main Sidebar Floating Card
    -- =========================================================================

    -- Unified translucent glass background (NO borders on text, crisp & clean)
    ass:new_event()
    ass:append(string.format("{\\pos(0,0)\\an7\\bord0\\shad0\\1c&H%s&\\1a&H1A&}", COLOR_BG))
    ass:draw_start()
    ass:round_rect_cw(sb_x1, card_y1, sb_x2, card_y2, corner_r)
    ass:draw_stop()

    -- Subtle hairline card border
    ass:new_event()
    ass:append(string.format("{\\pos(0,0)\\an7\\bord0\\shad0\\1c&H%s&\\1a&H50&}", COLOR_BORDER))
    ass:draw_start()
    ass:round_rect_cw(sb_x1, card_y1, sb_x2, card_y2, corner_r)
    ass:round_rect_ccw(sb_x1 + 1, card_y1 + 1, sb_x2 - 1, card_y2 - 1, corner_r - 1)
    ass:draw_stop()

    -- Header (Settings Title + Close "✕" Button)
    local header_h = math.floor(54 * s)
    local header_y_mid = card_y1 + math.floor(header_h / 2)
    local close_sz = math.floor(30 * s)
    local close_x, close_y

    if is_ar then
        -- Arabic: Title on the right, Close button on the left
        ass:new_event()
        ass:append(string.format("{\\pos(%d,%d)\\an6\\bord0\\shad0\\fs%d\\b1\\1c&H%s&\\fnInter}", sb_x2 - pad, header_y_mid, font_title, COLOR_TEXT))
        ass:append("الإعدادات")

        close_x = sb_x1 + pad
        close_y = card_y1 + math.floor((header_h - close_sz) / 2)
    else
        -- English: Title on the left, Close button on the right
        ass:new_event()
        ass:append(string.format("{\\pos(%d,%d)\\an4\\bord0\\shad0\\fs%d\\b1\\1c&H%s&\\fnInter}", sb_x1 + pad, header_y_mid, font_title, COLOR_TEXT))
        ass:append("Settings")

        close_x = sb_x2 - pad - close_sz
        close_y = card_y1 + math.floor((header_h - close_sz) / 2)
    end

    local is_close_hover = (mouse_x >= close_x and mouse_x <= close_x + close_sz and mouse_y >= close_y and mouse_y <= close_y + close_sz)

    ass:new_event()
    ass:append(string.format("{\\pos(0,0)\\an7\\bord0\\shad0\\1c&H%s&\\1a&H%s&}", is_close_hover and COLOR_CLOSE_RED or COLOR_HOVER, is_close_hover and "20" or "80"))
    ass:draw_start()
    ass:round_rect_cw(close_x, close_y, close_x + close_sz, close_y + close_sz, math.floor(7 * s))
    ass:draw_stop()

    ass:new_event()
    ass:append(string.format("{\\pos(%d,%d)\\an5\\bord0\\shad0\\fs%d\\b1\\1c&H%s&\\fnInter}", close_x + math.floor(close_sz / 2), close_y + math.floor(close_sz / 2), math.floor(15 * s), is_close_hover and "FFFFFF" or COLOR_TEXT_MUTED))
    ass:append("✕")

    table.insert(hitboxes, {
        x1 = close_x, y1 = close_y, x2 = close_x + close_sz, y2 = close_y + close_sz,
        action = function()
            sidebar_toggle(false)
        end
    })

    -- Header Divider Line
    ass:new_event()
    ass:append(string.format("{\\pos(0,0)\\an7\\bord0\\shad0\\1c&H%s&\\1a&H70&}", COLOR_BORDER))
    ass:draw_start()
    ass:rect_cw(sb_x1 + pad, card_y1 + header_h, sb_x2 - pad, card_y1 + header_h + 1)
    ass:draw_stop()

    -- Category List Items
    local cur_y = card_y1 + header_h + math.floor(12 * s)
    local selected_cat_obj = nil

    for _, cat in ipairs(menu_categories) do
        local is_cat_active = (active_category == cat.id)
        if is_cat_active then selected_cat_obj = cat end

        local item_x1 = sb_x1 + pad
        local item_x2 = sb_x2 - pad
        local is_hover = (mouse_x >= item_x1 and mouse_x <= item_x2 and mouse_y >= cur_y and mouse_y <= cur_y + item_h)

        -- Category Card Pill Background & Glass Border
        if is_cat_active or is_hover then
            ass:new_event()
            local bg_col = is_cat_active and COLOR_PURPLE_BG or COLOR_HOVER
            local bg_alpha = is_cat_active and "25" or "75"
            ass:append(string.format("{\\pos(0,0)\\an7\\bord0\\shad0\\1c&H%s&\\1a&H%s&}", bg_col, bg_alpha))
            ass:draw_start()
            ass:round_rect_cw(item_x1, cur_y, item_x2, cur_y + item_h, math.floor(8 * s))
            ass:draw_stop()

            -- Subtle glass border around active/hover category
            ass:new_event()
            local border_col = is_cat_active and COLOR_PURPLE or COLOR_BORDER
            local border_alpha = is_cat_active and "50" or "80"
            ass:append(string.format("{\\pos(0,0)\\an7\\bord0\\shad0\\1c&H%s&\\1a&H%s&}", border_col, border_alpha))
            ass:draw_start()
            ass:round_rect_cw(item_x1, cur_y, item_x2, cur_y + item_h, math.floor(8 * s))
            ass:round_rect_ccw(item_x1 + 1, cur_y + 1, item_x2 - 1, cur_y + item_h - 1, math.floor(7 * s))
            ass:draw_stop()

            if is_cat_active then
                -- Vertical Purple Accent Indicator Notch
                ass:new_event()
                ass:append(string.format("{\\pos(0,0)\\an7\\bord0\\shad0\\1c&H%s&\\1a&H00&}", COLOR_PURPLE))
                ass:draw_start()
                if is_ar then
                    ass:round_rect_cw(item_x2 - math.floor(4 * s), cur_y + math.floor(8 * s), item_x2, cur_y + item_h - math.floor(8 * s), 2)
                else
                    ass:round_rect_cw(item_x1, cur_y + math.floor(8 * s), item_x1 + math.floor(4 * s), cur_y + item_h - math.floor(8 * s), 2)
                end
                ass:draw_stop()
            end
        end

        -- Category Icon & Title (Crisp, NO text border)
        ass:new_event()
        local text_color = is_cat_active and COLOR_TEXT or (is_hover and COLOR_TEXT or COLOR_TEXT_MUTED)
        if is_ar then
            ass:append(string.format("{\\pos(%d,%d)\\an6\\bord0\\shad0\\fs%d\\b%d\\1c&H%s&\\fnInter}", item_x2 - math.floor(14 * s), cur_y + math.floor(item_h / 2), font_item, is_cat_active and 1 or 0, text_color))
            ass:append(string.format("%s  %s", cat.title, cat.icon))

            -- Chevron indicator `‹` pointing inward/left towards flyout
            ass:new_event()
            ass:append(string.format("{\\pos(%d,%d)\\an4\\bord0\\shad0\\fs%d\\1c&H%s&\\fnInter}", item_x1 + math.floor(12 * s), cur_y + math.floor(item_h / 2), font_item, is_cat_active and "FFFFFF" or COLOR_TEXT_MUTED))
            ass:append("‹")
        else
            ass:append(string.format("{\\pos(%d,%d)\\an4\\bord0\\shad0\\fs%d\\b%d\\1c&H%s&\\fnInter}", item_x1 + math.floor(14 * s), cur_y + math.floor(item_h / 2), font_item, is_cat_active and 1 or 0, text_color))
            ass:append(string.format("%s  %s", cat.icon, cat.title))

            -- Chevron indicator `›` pointing inward/right towards flyout
            ass:new_event()
            ass:append(string.format("{\\pos(%d,%d)\\an6\\bord0\\shad0\\fs%d\\1c&H%s&\\fnInter}", item_x2 - math.floor(12 * s), cur_y + math.floor(item_h / 2), font_item, is_cat_active and "FFFFFF" or COLOR_TEXT_MUTED))
            ass:append("›")
        end

        table.insert(hitboxes, {
            x1 = item_x1, y1 = cur_y, x2 = item_x2, y2 = cur_y + item_h,
            action = function()
                if active_category ~= cat.id then
                    active_category = cat.id
                    active_flyout = nil -- All accordions closed by default on category change!
                    flyout_scroll = 0
                end
                render_sidebar()
            end
        })

        cur_y = cur_y + item_h + math.floor(6 * s)
    end

    -- =========================================================================
    -- 2. Draw Adjacent Flyout Floating Card (Unified Glass Surface)
    -- =========================================================================
    if selected_cat_obj then
        -- Unified Glass Surface (matching main sidebar)
        ass:new_event()
        ass:append(string.format("{\\pos(0,0)\\an7\\bord0\\shad0\\1c&H%s&\\1a&H1A&}", COLOR_BG))
        ass:draw_start()
        ass:round_rect_cw(fo_x1, card_y1, fo_x2, card_y2, corner_r)
        ass:draw_stop()

        -- Subtle hairline card border
        ass:new_event()
        ass:append(string.format("{\\pos(0,0)\\an7\\bord0\\shad0\\1c&H%s&\\1a&H50&}", COLOR_BORDER))
        ass:draw_start()
        ass:round_rect_cw(fo_x1, card_y1, fo_x2, card_y2, corner_r)
        ass:round_rect_ccw(fo_x1 + 1, card_y1 + 1, fo_x2 - 1, card_y2 - 1, corner_r - 1)
        ass:draw_stop()

        -- Flyout Header (Shows active category title)
        ass:new_event()
        if is_ar then
            ass:append(string.format("{\\pos(%d,%d)\\an6\\bord0\\shad0\\fs%d\\b1\\1c&H%s&\\fnInter}", fo_x2 - pad, header_y_mid, font_title - 1, COLOR_TEXT))
            ass:append(string.format("%s %s", selected_cat_obj.title, selected_cat_obj.icon))
        else
            ass:append(string.format("{\\pos(%d,%d)\\an4\\bord0\\shad0\\fs%d\\b1\\1c&H%s&\\fnInter}", fo_x1 + pad, header_y_mid, font_title - 1, COLOR_TEXT))
            ass:append(string.format("%s %s", selected_cat_obj.icon, selected_cat_obj.title))
        end

        -- Header Divider
        ass:new_event()
        ass:append(string.format("{\\pos(0,0)\\an7\\bord0\\shad0\\1c&H%s&\\1a&H70&}", COLOR_BORDER))
        ass:draw_start()
        ass:rect_cw(fo_x1 + pad, card_y1 + header_h, fo_x2 - pad, card_y1 + header_h + 1)
        ass:draw_stop()

        -- Flyout Accordions List
        local fo_cur_y = card_y1 + header_h + math.floor(12 * s)

        for _, sub in ipairs(selected_cat_obj.flyouts or {}) do
            local is_sub_active = (active_flyout == sub.id)

            local sub_x1 = fo_x1 + pad
            local sub_x2 = fo_x2 - pad
            local is_sub_hover = (mouse_x >= sub_x1 and mouse_x <= sub_x2 and mouse_y >= fo_cur_y and mouse_y <= fo_cur_y + fo_head_h)

            -- Setting Field Header Container (Distinct elevated glass style)
            ass:new_event()
            local sub_bg = is_sub_active and COLOR_PURPLE_BG or (is_sub_hover and COLOR_HOVER or COLOR_ITEM_BG)
            local sub_alpha = is_sub_active and "30" or (is_sub_hover and "60" or "80")
            ass:append(string.format("{\\pos(0,0)\\an7\\bord0\\shad0\\1c&H%s&\\1a&H%s&}", sub_bg, sub_alpha))
            ass:draw_start()
            ass:round_rect_cw(sub_x1, fo_cur_y, sub_x2, fo_cur_y + fo_head_h, math.floor(8 * s))
            ass:draw_stop()

            -- Setting Field Header Glass Border
            ass:new_event()
            local sub_border_col = is_sub_active and COLOR_PURPLE or COLOR_ITEM_BORDER
            local sub_border_alpha = is_sub_active and "50" or "60"
            ass:append(string.format("{\\pos(0,0)\\an7\\bord0\\shad0\\1c&H%s&\\1a&H%s&}", sub_border_col, sub_border_alpha))
            ass:draw_start()
            ass:round_rect_cw(sub_x1, fo_cur_y, sub_x2, fo_cur_y + fo_head_h, math.floor(8 * s))
            ass:round_rect_ccw(sub_x1 + 1, fo_cur_y + 1, sub_x2 - 1, fo_cur_y + fo_head_h - 1, math.floor(7 * s))
            ass:draw_stop()

            -- Purple Accent Notch on Active Setting Field Header
            if is_sub_active then
                ass:new_event()
                ass:append(string.format("{\\pos(0,0)\\an7\\bord0\\shad0\\1c&H%s&\\1a&H00&}", COLOR_PURPLE))
                ass:draw_start()
                if is_ar then
                    ass:round_rect_cw(sub_x2 - math.floor(4 * s), fo_cur_y + math.floor(7 * s), sub_x2, fo_cur_y + fo_head_h - math.floor(7 * s), 2)
                else
                    ass:round_rect_cw(sub_x1, fo_cur_y + math.floor(7 * s), sub_x1 + math.floor(4 * s), fo_cur_y + fo_head_h - math.floor(7 * s), 2)
                end
                ass:draw_stop()
            end

            -- Sub-section Title (Crisp vector text, NO border)
            ass:new_event()
            local title_col = is_sub_active and COLOR_TEXT or (is_sub_hover and COLOR_TEXT or COLOR_TEXT_MUTED)
            if is_ar then
                ass:append(string.format("{\\pos(%d,%d)\\an6\\bord0\\shad0\\fs%d\\b%d\\1c&H%s&\\fnInter}", sub_x2 - math.floor(12 * s), fo_cur_y + math.floor(fo_head_h / 2), font_sub, is_sub_active and 1 or 0, title_col))
            else
                ass:append(string.format("{\\pos(%d,%d)\\an4\\bord0\\shad0\\fs%d\\b%d\\1c&H%s&\\fnInter}", sub_x1 + math.floor(12 * s), fo_cur_y + math.floor(fo_head_h / 2), font_sub, is_sub_active and 1 or 0, title_col))
            end
            ass:append(sub.title)

            -- Value Badge if present (Enclosed in mini glass pill, PURE WHITE text)
            if sub.badge then
                local badge_str = tostring(sub.badge)
                local badge_w = math.floor((#badge_str * 7 + 14) * s)
                local badge_h = math.floor(20 * s)
                local badge_x1, badge_x2
                if is_ar then
                    badge_x1 = sub_x1 + math.floor(26 * s)
                    badge_x2 = badge_x1 + badge_w
                else
                    badge_x2 = sub_x2 - math.floor(26 * s)
                    badge_x1 = badge_x2 - badge_w
                end
                local badge_y1 = fo_cur_y + math.floor((fo_head_h - badge_h) / 2)
                local badge_y2 = badge_y1 + badge_h

                -- Glass pill background
                ass:new_event()
                ass:append(string.format("{\\pos(0,0)\\an7\\bord0\\shad0\\1c&H%s&\\1a&H40&}", COLOR_HOVER))
                ass:draw_start()
                ass:round_rect_cw(badge_x1, badge_y1, badge_x2, badge_y2, math.floor(5 * s))
                ass:draw_stop()

                -- Glass pill border
                ass:new_event()
                ass:append(string.format("{\\pos(0,0)\\an7\\bord0\\shad0\\1c&H%s&\\1a&H60&}", COLOR_BORDER))
                ass:draw_start()
                ass:round_rect_cw(badge_x1, badge_y1, badge_x2, badge_y2, math.floor(5 * s))
                ass:round_rect_ccw(badge_x1 + 1, badge_y1 + 1, badge_x2 - 1, badge_y2 - 1, math.floor(4 * s))
                ass:draw_stop()

                -- Badge pure white text
                ass:new_event()
                ass:append(string.format("{\\pos(%d,%d)\\an5\\bord0\\shad0\\fs%d\\b1\\1c&HFFFFFF&\\fnInter}", math.floor((badge_x1 + badge_x2) / 2), math.floor((badge_y1 + badge_y2) / 2), font_badge))
                ass:append(badge_str)
            end

            -- Expand Indicator Arrow
            ass:new_event()
            if is_ar then
                ass:append(string.format("{\\pos(%d,%d)\\an4\\bord0\\shad0\\fs%d\\1c&H%s&\\fnInter}", sub_x1 + math.floor(10 * s), fo_cur_y + math.floor(fo_head_h / 2), font_badge + 1, is_sub_active and "FFFFFF" or COLOR_TEXT_MUTED))
                ass:append(is_sub_active and "▾" or "◂")
            else
                ass:append(string.format("{\\pos(%d,%d)\\an6\\bord0\\shad0\\fs%d\\1c&H%s&\\fnInter}", sub_x2 - math.floor(10 * s), fo_cur_y + math.floor(fo_head_h / 2), font_badge + 1, is_sub_active and "FFFFFF" or COLOR_TEXT_MUTED))
                ass:append(is_sub_active and "▾" or "▸")
            end

            -- Robust Toggle: Click to open, Click AGAIN to close (infinitely re-clickable!)
            local sub_target_id = sub.id
            table.insert(hitboxes, {
                x1 = sub_x1, y1 = fo_cur_y, x2 = sub_x2, y2 = fo_cur_y + fo_head_h,
                action = function()
                    if active_flyout == sub_target_id then
                        active_flyout = nil -- Close on re-click!
                    else
                        active_flyout = sub_target_id -- Open on click!
                    end
                    render_sidebar()
                end
            })

            fo_cur_y = fo_cur_y + fo_head_h + math.floor(6 * s)

            -- If this accordion is expanded, list its actionable items!
            if is_sub_active then
                for _, itm in ipairs(sub.items or {}) do
                    local itm_x1 = sub_x1 + math.floor(6 * s)
                    local itm_x2 = sub_x2 - math.floor(6 * s)
                    local has_desc = (itm.desc ~= nil and itm.desc ~= "")
                    local cur_itm_h = has_desc and math.floor(52 * s) or fo_itm_h
                    local is_itm_hover = (mouse_x >= itm_x1 and mouse_x <= itm_x2 and mouse_y >= fo_cur_y and mouse_y <= fo_cur_y + cur_itm_h)

                    -- Distinct Option Card Background (Glass capsule with subtle tint)
                    ass:new_event()
                    local itm_bg = itm.checked and COLOR_PURPLE_BG or (is_itm_hover and COLOR_HOVER or "161111")
                    local itm_alpha = itm.checked and "25" or (is_itm_hover and "60" or "85")
                    ass:append(string.format("{\\pos(0,0)\\an7\\bord0\\shad0\\1c&H%s&\\1a&H%s&}", itm_bg, itm_alpha))
                    ass:draw_start()
                    ass:round_rect_cw(itm_x1, fo_cur_y, itm_x2, fo_cur_y + cur_itm_h, math.floor(6 * s))
                    ass:draw_stop()

                    -- Subtle glass hairline border on option card
                    ass:new_event()
                    local itm_border_col = itm.checked and COLOR_PURPLE or (is_itm_hover and COLOR_BORDER or "2A2222")
                    local itm_border_alpha = itm.checked and "50" or "80"
                    ass:append(string.format("{\\pos(0,0)\\an7\\bord0\\shad0\\1c&H%s&\\1a&H%s&}", itm_border_col, itm_border_alpha))
                    ass:draw_start()
                    ass:round_rect_cw(itm_x1, fo_cur_y, itm_x2, fo_cur_y + cur_itm_h, math.floor(6 * s))
                    ass:round_rect_ccw(itm_x1 + 1, fo_cur_y + 1, itm_x2 - 1, fo_cur_y + cur_itm_h - 1, math.floor(5 * s))
                    ass:draw_stop()

                    if has_desc then
                        -- Unified Wrapped Card: Title on top, Description underneath
                        local itm_text_col = itm.checked and "FFFFFF" or (is_itm_hover and COLOR_TEXT or "E0DCDC")
                        local desc_col = itm.desc_warning and "5090F8" or COLOR_TEXT_MUTED

                        ass:new_event()
                        if is_ar then
                            ass:append(string.format("{\\pos(%d,%d)\\an6\\bord0\\shad0\\fs%d\\b%d\\1c&H%s&\\fnInter}", itm_x2 - math.floor(10 * s), fo_cur_y + math.floor(17 * s), font_badge + 2, itm.checked and 1 or 0, itm_text_col))
                            ass:append(itm.label)

                            ass:new_event()
                            ass:append(string.format("{\\pos(%d,%d)\\an6\\bord0\\shad0\\fs%d\\1c&H%s&\\fnInter}", itm_x2 - math.floor(10 * s), fo_cur_y + math.floor(36 * s), math.floor(11 * s), desc_col))
                            ass:append(itm.desc)
                        else
                            ass:append(string.format("{\\pos(%d,%d)\\an4\\bord0\\shad0\\fs%d\\b%d\\1c&H%s&\\fnInter}", itm_x1 + math.floor(10 * s), fo_cur_y + math.floor(17 * s), font_badge + 2, itm.checked and 1 or 0, itm_text_col))
                            ass:append(itm.label)

                            ass:new_event()
                            ass:append(string.format("{\\pos(%d,%d)\\an4\\bord0\\shad0\\fs%d\\1c&H%s&\\fnInter}", itm_x1 + math.floor(10 * s), fo_cur_y + math.floor(36 * s), math.floor(11 * s), desc_col))
                            ass:append(itm.desc)
                        end
                    else
                        -- Standard single-line row
                        ass:new_event()
                        local itm_text_col = itm.checked and "FFFFFF" or (is_itm_hover and COLOR_TEXT or COLOR_TEXT_MUTED)
                        if is_ar then
                            ass:append(string.format("{\\pos(%d,%d)\\an6\\bord0\\shad0\\fs%d\\b%d\\1c&H%s&\\fnInter}", itm_x2 - math.floor(10 * s), fo_cur_y + math.floor(cur_itm_h / 2), font_badge + 2, itm.checked and 1 or 0, itm_text_col))
                        else
                            ass:append(string.format("{\\pos(%d,%d)\\an4\\bord0\\shad0\\fs%d\\b%d\\1c&H%s&\\fnInter}", itm_x1 + math.floor(10 * s), fo_cur_y + math.floor(cur_itm_h / 2), font_badge + 2, itm.checked and 1 or 0, itm_text_col))
                        end
                        ass:append(itm.label)
                    end

                    -- Checkmark icon (Vertically centered)
                    if itm.checked then
                        ass:new_event()
                        if is_ar then
                            ass:append(string.format("{\\pos(%d,%d)\\an4\\bord0\\shad0\\fs%d\\b1\\1c&HFFFFFF&\\fnInter}", itm_x1 + math.floor(12 * s), fo_cur_y + math.floor(cur_itm_h / 2), font_badge + 3))
                        else
                            ass:append(string.format("{\\pos(%d,%d)\\an6\\bord0\\shad0\\fs%d\\b1\\1c&HFFFFFF&\\fnInter}", itm_x2 - math.floor(12 * s), fo_cur_y + math.floor(cur_itm_h / 2), font_badge + 3))
                        end
                        ass:append("✓")
                    end

                    table.insert(hitboxes, {
                        x1 = itm_x1, y1 = fo_cur_y, x2 = itm_x2, y2 = fo_cur_y + cur_itm_h,
                        action = function()
                            if itm.cmd then
                                itm.cmd()
                            end
                            -- PERSISTENT LIVE TUNING: STAYS OPEN!
                            mp.add_timeout(0.04, function()
                                render_sidebar()
                            end)
                        end
                    })

                    fo_cur_y = fo_cur_y + cur_itm_h + math.floor(4 * s)
                end
                fo_cur_y = fo_cur_y + math.floor(6 * s)
            end
        end
    end

    overlay.data = ass.text
    overlay:update()
end

-- ==============================================================================
-- Input Trapping & Mouse Protection
-- ==============================================================================

local function is_mouse_inside_menu()
    if not is_open then return false end
    local in_sb = (mouse_x >= layout.sb_x1 and mouse_x <= layout.sb_x2 and mouse_y >= layout.sb_y1 and mouse_y <= layout.sb_y2)
    local in_fo = (mouse_x >= layout.fo_x1 and mouse_x <= layout.fo_x2 and mouse_y >= layout.fo_y1 and mouse_y <= layout.fo_y2)
    return in_sb or in_fo
end

local mouse_timer = nil
local function on_mouse_move(_, pos)
    if not is_open or not pos then return end
    local nx = pos.x or -1
    local ny = pos.y or -1
    if nx == mouse_x and ny == mouse_y then return end
    mouse_x = nx
    mouse_y = ny
    if not mouse_timer then
        mouse_timer = mp.add_timeout(0.033, function()
            mouse_timer = nil
            if is_open then
                render_sidebar()
            end
        end)
    end
end

local function on_mbtn_left()
    if not is_open then return end

    local pos = mp.get_property_native("mouse-pos")
    if pos and pos.x and pos.y then
        mouse_x = pos.x
        mouse_y = pos.y
    end

    -- Debounce: Ignore mouse clicks/releases occurring immediately after opening (<0.25s)
    if mp.get_time() - last_open_time < 0.25 then
        return
    end

    -- 1. Check interactive hitboxes inside menu cards
    for _, hb in ipairs(hitboxes) do
        if mouse_x >= hb.x1 and mouse_x <= hb.x2 and mouse_y >= hb.y1 and mouse_y <= hb.y2 then
            hb.action()
            return
        end
    end

    -- 2. If click is inside the sidebar or flyout background cards:
    -- Swallow click so it does not click-through to the video
    if is_mouse_inside_menu() then
        return
    end

    -- 3. Click is OUTSIDE the menu cards:
    -- A) If click is in the bottom bar region (ModernZ bar where the wheel button is located):
    if mouse_y >= layout.sb_y2 then
        -- User clicked the wheel icon or bottom bar: toggle/close the sidebar immediately!
        sidebar_toggle(false)
        return
    end

    -- B) Click is on the video canvas outside the menu:
    if active_flyout ~= nil then
        -- If an accordion flyout was open, close only the flyout
        active_flyout = nil
        render_sidebar()
        return
    else
        -- If no flyout is open, clicking on video canvas closes the sidebar
        sidebar_toggle(false)
        return
    end
end

-- USER SPECIFICATION (POINT 6):
-- Double-click protection inside menu boxes:
-- If double-clicking inside the boxes, DO NOT toggle fullscreen!
-- If double-clicking outside the boxes on the video, toggle fullscreen as normal!
local function on_mbtn_left_dbl()
    if not is_open then
        mp.command("cycle fullscreen")
        return
    end

    if is_mouse_inside_menu() then
        -- Protected! Swallow double click so video does NOT toggle fullscreen
        return
    else
        -- Outside the boxes: toggle fullscreen as usual
        mp.command("cycle fullscreen")
    end
end

local key_bindings = {
    {"mbtn_left", on_mbtn_left},
    {"mbtn_left_dbl", on_mbtn_left_dbl},
    {"esc", function() sidebar_toggle(false) end},
    {"mbtn_mid", function() sidebar_toggle(false) end},
}

function sidebar_toggle(state)
    if state == nil then
        state = not is_open
    end

    is_open = state

    if is_open then
        last_open_time = mp.get_time()
        active_flyout = nil -- Always start with accordions cleanly closed
        flyout_scroll = 0
        local pos = mp.get_property_native("mouse-pos")
        if pos and pos.x and pos.y then
            mouse_x = pos.x
            mouse_y = pos.y
        end
        mp.observe_property("mouse-pos", "native", on_mouse_move)
        for _, b in ipairs(key_bindings) do
            mp.add_forced_key_binding(b[1], "sb_" .. b[1], b[2])
        end
        render_sidebar()
    else
        mp.unobserve_property(on_mouse_move)
        for _, b in ipairs(key_bindings) do
            mp.remove_key_binding("sb_" .. b[1])
        end
        overlay.data = ""
        overlay:update()
        -- Immediately re-awaken ModernZ bottom bar so controls and hitboxes are active
        mp.commandv("script-message-to", "modernz", "osc-show")
    end
end

-- Bindings & Script Messages
mp.add_forced_key_binding("MBTN_MID", "sidebar_toggle", function()
    sidebar_toggle()
end)

mp.add_key_binding("c", "sidebar_toggle_key", function()
    sidebar_toggle()
end)

mp.register_script_message("toggle_sidebar", function()
    sidebar_toggle()
end)

mp.register_script_message("set_language", function(lang)
    lang = tostring(lang or ""):lower()
    current_language = (lang == "eng" or lang == "en") and "eng" or "ar"
    if is_open then render_sidebar() end
end)

mp.observe_property("osd-dimensions", "native", function()
    if is_open then render_sidebar() end
end)

-- Restore persisted configuration & shaders on startup & file load
read_language_cfg()
load_saved_shaders()

-- Sync language to modernz on startup
mp.add_timeout(0.05, function()
    mp.commandv("script-message-to", "modernz", "set_language", current_language)
end)

mp.register_event("file-loaded", function()
    read_language_cfg()
    local cur = mp.get_property("glsl-shaders", "")
    if cur == "" then
        load_saved_shaders()
    end
    mp.commandv("script-message-to", "modernz", "set_language", current_language)
end)

