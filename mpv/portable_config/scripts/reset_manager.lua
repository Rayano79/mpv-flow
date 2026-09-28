-- reset_manager.lua: Reset all settings to current defaults

local mp = require 'mp'

local function reset_all_to_default()
    -- 1. Video & Aspect Ratio
    mp.set_property_native('video-aspect-override', -2)
    mp.set_property_native('video-zoom', 0)
    mp.set_property_native('video-pan-x', 0)
    mp.set_property_native('video-pan-y', 0)
    mp.set_property_native('video-rotate', 0)
    mp.set_property_native('panscan', 0)
    mp.set_property_native('keepaspect', true)
    mp.set_property_native('video-unscaled', 'no')
    mp.set_property_native('deband', false)
    mp.set_property_native('deinterlace', false)

    -- 2. Audio
    mp.set_property_native('audio-delay', 0)
    mp.set_property_native('speed', 1.0)
    mp.set_property_native('mute', false)

    -- 3. Subtitle
    mp.set_property_native('sub-delay', 0)
    mp.set_property_native('sub-scale', 1.0)
    mp.set_property_native('sub-visibility', true)

    -- 4. Window
    mp.set_property_native('ontop', false)

    -- 5. Subtitle Style Reset
    mp.commandv('script-message-to', 'subtitle_manager', 'reset_sub_style')

    -- 6. OSD notification
    mp.osd_message('All settings reset to default', 3)
end

mp.register_script_message('reset_all_to_default', reset_all_to_default)
