-- subtitle_manager.lua: Subtitle style management linked to unified player_settings.conf

local mp = require 'mp'
local utils = require 'mp.utils'

local config_path = mp.command_native({'expand-path', '~~/player_settings.conf'})

local defaults = {
    ['sub-font'] = 'XB Zar',
    ['sub-font-size'] = 45,
    ['sub-border-size'] = 2,
    ['sub-border-color'] = '#000000',
    ['sub-color'] = '#FFFFFF',
    ['sub-pos'] = 100,
    ['sub-spacing'] = 0,
    ['sub-border-style'] = 'outline-and-shadow',
    ['sub-back-color'] = '#00000000',
    ['sub-ass-override'] = 'no',
}

-- Map mpv property names to player_settings.conf keys (convert - to _)
local function prop_to_key(prop)
    return prop:gsub('%-', '_')
end

local function key_to_prop(key)
    return key:gsub('_', '-')
end

local current = {}
for k, v in pairs(defaults) do
    current[k] = v
end

-- Update single key in player_settings.conf
local function update_conf_key(key, val)
    local lines = {}
    local found = false
    local f = io.open(config_path, 'r')
    if f then
        for line in f:lines() do
            local k = line:match('^%s*([%w_%-]+)%s*=')
            if k and (k:lower() == key:lower() or k:lower() == key_to_prop(key):lower()) then
                table.insert(lines, key .. '=' .. tostring(val))
                found = true
            else
                table.insert(lines, line)
            end
        end
        f:close()
    end
    if not found then
        table.insert(lines, key .. '=' .. tostring(val))
    end
    local out = io.open(config_path, 'w')
    if out then
        for _, l in ipairs(lines) do
            out:write(l .. '\n')
        end
        out:flush()
        out:close()
    end
end

local function save_all_sub_props()
    for prop, val in pairs(current) do
        update_conf_key(prop_to_key(prop), val)
    end
end

local function load_config()
    local f = io.open(config_path, 'r')
    if f then
        for line in f:lines() do
            local key, val = line:match('^%s*([%w_%-]+)%s*=%s*(.-)%s*$')
            if key and val and not line:match('^%s*#') then
                local prop = key_to_prop(key)
                if defaults[prop] ~= nil then
                    if tonumber(val) then
                        current[prop] = tonumber(val)
                    else
                        current[prop] = val
                    end
                end
            end
        end
        f:close()
    end
    for k, v in pairs(current) do
        mp.set_property_native(k, v)
    end
end

local function set_sub_prop(name, value)
    if tonumber(value) then value = tonumber(value) end
    current[name] = value
    mp.set_property_native(name, value)
    update_conf_key(prop_to_key(name), value)



    mp.osd_message(name .. ': ' .. tostring(value), 2)
end

local function set_sub_bg(style, color)
    current['sub-border-style'] = style
    current['sub-back-color'] = color
    mp.set_property_native('sub-border-style', style)
    mp.set_property_native('sub-back-color', color)
    update_conf_key(prop_to_key('sub-border-style'), style)
    update_conf_key(prop_to_key('sub-back-color'), color)
    mp.osd_message('Subtitle Background updated', 2)
end

local function set_sub_mode(mode)
    -- mode: "embedded" (sub-ass-override=no) or "custom" (sub-ass-override=force)
    local override_val = (mode == "embedded" or mode == "no") and "no" or "force"
    current['sub-ass-override'] = override_val
    mp.set_property_native('sub-ass-override', override_val)
    update_conf_key('sub_ass_override', override_val)
    local msg = (override_val == "no") and "Subtitle: Prefer Embedded Style (Source)" or "Subtitle: Custom Style Active (Forced)"
    mp.osd_message(msg, 2)
end

local function change_sub_prop(name, delta_str)
    local delta = tonumber(delta_str) or 0
    local val = (current[name] or defaults[name] or 0) + delta
    if name == 'sub-font-size' and val < 10 then val = 10 end
    if name == 'sub-border-size' and val < 0 then val = 0 end
    if name == 'sub-pos' and val < 0 then val = 0 end
    if name == 'sub-pos' and val > 150 then val = 150 end
    set_sub_prop(name, val)
end

local function reset_sub_style()
    for k, v in pairs(defaults) do
        current[k] = v
        mp.set_property_native(k, v)
    end
    save_all_sub_props()
    mp.osd_message('Subtitle style reset to default', 2.5)
end

mp.register_script_message('set_sub_prop', set_sub_prop)
mp.register_script_message('set_sub_mode', set_sub_mode)
mp.register_script_message('set_sub_bg', set_sub_bg)
mp.register_script_message('change_sub_prop', change_sub_prop)
mp.register_script_message('reset_sub_style', reset_sub_style)

load_config()
