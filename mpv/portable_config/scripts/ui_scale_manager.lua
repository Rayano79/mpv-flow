-- ui_scale_manager.lua: Unified UI scaling linked to player_settings.conf
local mp = require 'mp'
local utils = require 'mp.utils'

local config_path = mp.command_native({'expand-path', '~~/player_settings.conf'})
local current_scale = 1.0

local function update_conf_key(key, val)
    local lines = {}
    local found = false
    local f = io.open(config_path, 'r')
    if f then
        for line in f:lines() do
            local k = line:match('^%s*([%w_%-]+)%s*=')
            if k and (k:lower() == key:lower() or k:lower() == "ui-scale") then
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

local function apply_scale(scale)
    scale = tonumber(scale) or 1.0
    current_scale = scale

    -- 1. Apply to mpv native OSD scale (affects stats window, OSD messages, select menus)
    mp.set_property_number('osd-scale', scale)

    -- 2. Inform ModernZ to scale the bottom bar, top window controls, etc.
    mp.commandv('script-message-to', 'modernz', 'set-ui-scale', tostring(scale))

    -- 3. Inform Modern Volume OSD to scale the Liquid Glass volume HUD
    mp.commandv('script-message-to', 'modern_volume_osd', 'set-ui-scale', tostring(scale))

    -- 4. Persist directly to player_settings.conf
    update_conf_key('ui_scale', string.format('%.2f', scale))
end

local function load_scale()
    local f = io.open(config_path, 'r')
    if f then
        for line in f:lines() do
            local k, val = line:match('^%s*([%w_%-]+)%s*=%s*([%d%.]+)%s*$')
            if k and (k:lower() == 'ui_scale' or k:lower() == 'ui-scale') and val then
                if tonumber(val) then
                    current_scale = tonumber(val)
                    break
                end
            end
        end
        f:close()
    end
    apply_scale(current_scale)
end

mp.register_script_message('set_ui_scale', function(scale_str)
    local scale = tonumber(scale_str)
    if scale then
        apply_scale(scale)
        mp.osd_message(string.format("UI Scale: %d%%", math.floor(scale * 100 + 0.5)), 2)
    end
end)

-- Initialize on load
mp.register_event('playback-restart', function()
    apply_scale(current_scale)
end)

load_scale()
