fx_version 'cerulean'
game 'gta5'

name 'cobra-anticheat'
description 'Cobra Anti-Cheat — Aimbot/Wallhack/Dupe detection, combined screenshot embeds, full admin audit log'
version '2.0.0'
author 'Cobra Development'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',                -- UI, heartbeat, admin receivers
    'client/detections.lua',          -- Core: god mode, speed, noclip, etc.
    'client/advanced_detections.lua', -- Aimbot, wallhack, dupe event hooks
    'client/noclip.lua',              -- Admin noclip tool
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    -- Load order matters: webhook → bans → adminlog → dupe → main → commands
    'server/webhook.lua',    -- Discord embeds with screenshot baked in
    'server/bans.lua',       -- Ban/kick via txAdmin or fallback bans.json
    'server/adminlog.lua',   -- Full audit log: AC panel, commands, txAdmin, general
    'server/dupe.lua',       -- Server-side item/money duplication detection
    'server/main.lua',       -- Detection receiver, player tracking, admin events
    'server/commands.lua',   -- /acban /ackick /acunban /actp /acbring
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/app.js',
}

lua54 'yes'
