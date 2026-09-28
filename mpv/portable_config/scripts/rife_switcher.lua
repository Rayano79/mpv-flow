-- ========================================================
-- rife_switcher.lua: التبديل السلس بين نماذج RIFE عبر زر F2
-- ========================================================

local mp = require 'mp'
local utils = require 'mp.utils'

local models = {
    { num = 1, id = 425,  name = "RIFE v4.25 (Highest Quality)" },
    { num = 2, id = 4251, name = "RIFE v4.25 Lite (Fast & Detailed)" },
    { num = 3, id = 4221, name = "RIFE v4.22 Lite (Balanced)" },
    { num = 4, id = 4171, name = "RIFE v4.17 Lite (Ultra Fast)" },
}

local current_idx = 1
local player_cfg_file = mp.command_native({"expand-path", "~~/player_settings.conf"})
local rife_cfg_file = mp.command_native({"expand-path", "~~/rife_settings.conf"})

-- Read currently saved model from player_settings.conf (or fallback to rife_settings.conf)
local function read_current()
    local f = io.open(player_cfg_file, "r") or io.open(rife_cfg_file, "r")
    if f then
        for line in f:lines() do
            local k, v = line:match("^%s*([%w_]+)%s*=%s*([%w_]+)")
            if k and k:lower() == "model" and v then
                local n = tonumber(v)
                if n and n >= 1 and n <= #models then
                    current_idx = n
                    break
                elseif n == 425 then current_idx = 1; break
                elseif n == 4251 then current_idx = 2; break
                elseif n == 4221 then current_idx = 3; break
                elseif n == 4171 then current_idx = 4; break
                end
            end
        end
        f:close()
    end
end

read_current()

-- Update key in player_settings.conf
local function update_conf_model(num)
    local target_file = io.open(player_cfg_file, "r") and player_cfg_file or rife_cfg_file
    local lines = {}
    local found = false
    local f = io.open(target_file, "r")
    if f then
        for line in f:lines() do
            local k = line:match("^%s*([%w_]+)%s*=")
            if k and k:lower() == "model" then
                table.insert(lines, "model=" .. tostring(num))
                found = true
            else
                table.insert(lines, line)
            end
        end
        f:close()
    end
    if not found then
        table.insert(lines, "model=" .. tostring(num))
    end
    local out = io.open(target_file, "w")
    if out then
        for _, l in ipairs(lines) do
            out:write(l .. "\n")
        end
        out:flush()
        out:close()
    end
end

local MODEL_ONNX_FILES = {
    [1] = "rife_v4.25_v2.onnx",
    [2] = "rife_v4.25_lite_v2.onnx",
    [3] = "rife_v4.22_lite_v2.onnx",
    [4] = "rife_v4.17_lite_v2.onnx"
}

local function is_model_onnx_present(num)
    local fn = MODEL_ONNX_FILES[num]
    if not fn then return false end
    local candidates = {
        mp.command_native({"expand-path", "~~/../../vs/vs-plugins/models/rife_v2/" .. fn}),
        mp.command_native({"expand-path", "~~/../vs/vs-plugins/models/rife_v2/" .. fn}),
        mp.command_native({"expand-path", "~~/vs/vs-plugins/models/rife_v2/" .. fn})
    }
    for _, p in ipairs(candidates) do
        local info = utils.file_info(p)
        if info and info.size and info.size > 1024 * 1024 then
            return true
        end
    end
    return false
end

local function cycle_model()
    local available = {}
    for _, m in ipairs(models) do
        if is_model_onnx_present(m.num) then
            table.insert(available, m)
        end
    end

    if #available == 0 then
        mp.osd_message("No RIFE models found on disk", 2)
        return
    end

    local chosen = nil
    for _, m in ipairs(available) do
        if m.num > current_idx then
            chosen = m
            break
        end
    end
    if not chosen then
        chosen = available[1]
    end

    current_idx = chosen.num
    update_conf_model(chosen.num)

    -- Re-initialize video filter to apply new model instantly
    local vf_list = mp.get_property_native("vf") or {}
    local other_vf = {}
    local has_vs = false
    for _, filter in ipairs(vf_list) do
        if filter.name == "vapoursynth" or (filter.label and filter.label:find("interpolation")) then
            has_vs = true
        else
            table.insert(other_vf, filter)
        end
    end
    if has_vs then
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
    mp.osd_message("RIFE Model: " .. chosen.name, 2)
end

mp.add_key_binding(nil, "rife_cycle_model", cycle_model)

