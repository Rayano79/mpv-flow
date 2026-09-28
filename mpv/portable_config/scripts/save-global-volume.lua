-- save-global-volume.lua
-- يحفظ مستوى الصوت تلقائياً ويطبقه على أي ملف أو حلقة جديدة تفتحها
local utils = require 'mp.utils'
local state_file = utils.join_path(mp.command_native({"expand-path", "~~/"}), "volume.state")

local initial_loaded = false

local function load_volume()
    local f = io.open(state_file, "r")
    if f then
        local vol = f:read("*n")
        local mute_line = f:read("*l")
        mute_line = f:read("*l")
        f:close()
        if vol then
            mp.set_property_number("volume", vol)
        end
        if mute_line and mute_line:match("true") then
            mp.set_property_bool("mute", true)
        elseif mute_line and mute_line:match("false") then
            mp.set_property_bool("mute", false)
        end
    end
end

local function save_volume()
    local vol = mp.get_property_number("volume")
    local mute = mp.get_property_bool("mute")
    if vol ~= nil then
        local f = io.open(state_file, "w")
        if f then
            f:write(tostring(vol) .. "\n" .. tostring(mute) .. "\n")
            f:close()
        end
    end
end

mp.register_event("file-loaded", function()
    if not initial_loaded then
        load_volume()
        initial_loaded = true
    end
end)

mp.observe_property("volume", "number", function(_, val)
    if val and initial_loaded then
        save_volume()
    end
end)

mp.observe_property("mute", "bool", function(_, val)
    if val ~= nil and initial_loaded then
        save_volume()
    end
end)

mp.register_event("shutdown", save_volume)
