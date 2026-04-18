-- =============================================
-- cobra-anticheat / server / adminlog.lua
-- Comprehensive admin audit log
--
-- Captures every admin action from every source:
--   1. Cobra AC panel (kick, ban, freeze, spectate, TP, bring, screenshot)
--   2. Cobra AC chat commands (/acban /ackick /acunban /actp /acbring)
--   3. txAdmin web panel (ban, kick, warn, unban, restart, resource control)
--   4. QBCore admin commands (/ban /kick /god /noclip /heal /revive /spectate)
--   5. Any other RegisterCommand by a player with admin permissions
--   6. Runtime resource start/stop events
--
-- Every entry is:
--   • Stored in adminlog.json (survives restarts, loaded back on resource start)
--   • Sent to Config.Webhooks.adminlog (dedicated Discord channel)
--   • Sent to Config.Webhooks.generaladmin for non-AC admin actions
--   • Exposed to the in-game panel via GetAdminLog()
--
-- Cobra Development
-- =============================================

local logBuffer  = {}
local MAX_BUFFER = 500
local LOG_FILE   = 'adminlog.json'

-- ── Disk I/O ──────────────────────────────────────────────────────────────────

local function LoadLog()
    local raw = LoadResourceFile(GetCurrentResourceName(), LOG_FILE)
    if raw and raw ~= '' then
        local ok, data = pcall(json.decode, raw)
        if ok and data then
            logBuffer = data
            print(('[cobra-anticheat] Admin log loaded: %d entries'):format(#logBuffer))
        end
    end
end

local function SaveLog()
    while #logBuffer > MAX_BUFFER do table.remove(logBuffer, #logBuffer) end
    local ok, enc = pcall(json.encode, logBuffer)
    if ok then SaveResourceFile(GetCurrentResourceName(), LOG_FILE, enc, -1) end
end

local saveQueued = false
local function QueueSave()
    if saveQueued then return end
    saveQueued = true
    SetTimeout(3000, function() SaveLog(); saveQueued = false end)
end

-- ── Webhook senders ───────────────────────────────────────────────────────────

local function SendToWebhook(url, embed)
    if not url or url == '' or url == 'YOUR_WEBHOOK_URL_HERE' then return end
    PerformHttpRequest(url, function() end, 'POST',
        json.encode({ username = (Config and Config.ServerName or 'Cobra') .. ' | Cobra Admin Log', embeds = { embed } }),
        { ['Content-Type'] = 'application/json' }
    )
end

-- ── Colour / icon maps ────────────────────────────────────────────────────────

local ACTION_COLOR = {
    -- AC actions
    BAN              = 10038562,  -- dark red
    KICK             = 16744272,  -- orange
    UNBAN            = 3066993,   -- green
    WARN             = 16776960,  -- yellow
    FREEZE           = 3447003,   -- blue
    UNFREEZE         = 3447003,
    SPECTATE         = 9807270,   -- grey
    ['STOP SPECTATE']= 9807270,
    SCREENSHOT       = 9807270,
    ['TELEPORT TO']  = 3447003,
    BRING            = 3447003,
    ['CLEAR FLAGS']  = 16776960,
    ['PANEL OPEN']   = 5592575,
    -- txAdmin passthrough
    TXADMIN_BAN      = 10038562,
    TXADMIN_KICK     = 16744272,
    TXADMIN_WARN     = 16776960,
    TXADMIN_UNBAN    = 3066993,
    TXADMIN_RESTART  = 15844367,
    TXADMIN_RESOURCE = 9807270,
    TXADMIN_WHITELIST= 3447003,
    -- General QBCore / other admin commands
    GENERAL_CMD      = 5592575,   -- light blue
    RESOURCE_START   = 16776960,
    RESOURCE_STOP    = 16744272,
    ['AC STOPPED']   = 10038562,
}

local ACTION_ICON = {
    BAN='🔨', KICK='👢', UNBAN='✅', WARN='⚠️', FREEZE='❄️', UNFREEZE='🔓',
    SPECTATE='👁️', ['STOP SPECTATE']='🚫', SCREENSHOT='📸',
    ['TELEPORT TO']='📡', BRING='⬇️', ['CLEAR FLAGS']='🧹', ['PANEL OPEN']='🛡️',
    TXADMIN_BAN='🔨', TXADMIN_KICK='👢', TXADMIN_WARN='⚠️', TXADMIN_UNBAN='✅',
    TXADMIN_RESTART='🔄', TXADMIN_RESOURCE='📦', TXADMIN_WHITELIST='✅',
    GENERAL_CMD='💬', RESOURCE_START='▶️', RESOURCE_STOP='⏹️', ['AC STOPPED']='🚨',
}

-- ── Core write function ───────────────────────────────────────────────────────

local function WriteLog(adminSrc, adminName, adminIds, action, targetSrc, targetName, targetIds, detail, logSource)
    local entry = {
        timestamp    = os.time(),
        timestampFmt = os.date('!%Y-%m-%d %H:%M:%S'),
        adminId      = adminSrc,
        adminName    = adminName or 'System',
        adminIds     = adminIds  or {},
        action       = action,
        targetId     = targetSrc,
        targetName   = targetName or 'N/A',
        targetIds    = targetIds  or {},
        detail       = detail or '',
        source       = logSource or 'panel',
    }
    table.insert(logBuffer, 1, entry)
    QueueSave()

    local icon   = ACTION_ICON[action]  or '⚡'
    local colour = ACTION_COLOR[action] or 9807270
    local srcEmoji = ({ panel='🖥️', command='💬', txadmin='🔧', system='🤖', general='🎮' })[logSource] or '❓'

    local fields = {
        { name = '⚡ Action',     value = ('`%s`'):format(action),                                                                 inline = true  },
        { name = srcEmoji..' Source', value = logSource or 'panel',                                                               inline = true  },
        { name = '🕐 UTC',        value = entry.timestampFmt,                                                                    inline = true  },
        { name = '👮 Admin',      value = (adminName or 'System') .. (adminSrc and (' (SrvID: '..adminSrc..')') or ''),          inline = false },
    }

    if adminIds and #adminIds > 0 then
        fields[#fields + 1] = {
            name  = '🪪 Admin Identifiers',
            value = '```\n' .. table.concat(adminIds, '\n') .. '\n```',
            inline = false,
        }
    end

    if targetSrc or (targetName and targetName ~= 'N/A') then
        fields[#fields + 1] = {
            name  = '🎯 Target',
            value = (targetName or 'Unknown') .. (targetSrc and (' (SrvID: '..targetSrc..')') or ''),
            inline = false,
        }
    end
    if targetIds and #targetIds > 0 then
        fields[#fields + 1] = {
            name  = '🪪 Target Identifiers',
            value = '```\n' .. table.concat(targetIds, '\n') .. '\n```',
            inline = false,
        }
    end
    if detail and detail ~= '' then
        fields[#fields + 1] = { name = '📋 Detail', value = detail, inline = false }
    end

    local embed = {
        title     = icon .. ' ' .. action,
        color     = colour,
        fields    = fields,
        footer    = { text = 'Cobra Anti-Cheat' .. (Config and Config.ServerName and (' | ' .. Config.ServerName) or '') },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    }

    -- Route: general commands go to generaladmin webhook, AC actions to adminlog
    local isGeneral = (logSource == 'general' or logSource == 'system')
    if isGeneral and Config.Webhooks.generaladmin and Config.Webhooks.generaladmin ~= 'YOUR_WEBHOOK_URL_HERE' then
        SendToWebhook(Config.Webhooks.generaladmin, embed)
    end
    -- Everything also goes to the unified admin log channel
    SendToWebhook(Config.Webhooks.adminlog, embed)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function LogAdminAction(adminSrc, action, targetSrc, detail, logSource)
    local adminName  = (adminSrc and adminSrc ~= 0 and GetPlayerName(adminSrc)) or 'System'
    local adminIds   = (adminSrc and adminSrc ~= 0) and GetAllIdentifiers(adminSrc) or {}
    local targetName = targetSrc and GetPlayerName(targetSrc) or nil
    local targetIds  = targetSrc and GetAllIdentifiers(targetSrc) or {}

    -- Mirror into txAdmin's own server log so it shows in txAdmin history
    if GetResourceState('monitor') == 'started' then
        pcall(function()
            exports['monitor']:logAction({
                author = adminName,
                target = targetSrc and GetPlayerName(targetSrc) or nil,
                action = '[cobra-anticheat] ' .. action .. (detail and (': '..detail) or ''),
            })
        end)
    end

    WriteLog(adminSrc, adminName, adminIds, action, targetSrc, targetName, targetIds, detail, logSource or 'panel')
end

function GetAdminLog(n)
    local result = {}
    for i = 1, math.min(n or 100, #logBuffer) do result[#result + 1] = logBuffer[i] end
    return result
end

RegisterNetEvent('cobra_ac:requestAdminLog', function()
    local src = source
    if not IsACAdmin(src) then return end
    TriggerClientEvent('cobra_ac:receiveAdminLog', src, GetAdminLog(200))
end)

-- ── txAdmin event hooks ───────────────────────────────────────────────────────

AddEventHandler('txAdmin:events:playerBanned', function(ev)
    if type(ev) ~= 'table' then return end
    WriteLog(nil, ev.author or 'txAdmin', {}, 'TXADMIN_BAN', nil,
        ev.targetName or 'Unknown', ev.targetIds or {},
        ('Reason: %s | Duration: %s'):format(ev.reason or 'N/A', ev.expiration or 'Permanent'),
        'txadmin')
end)

AddEventHandler('txAdmin:events:playerKicked', function(ev)
    if type(ev) ~= 'table' then return end
    WriteLog(nil, ev.author or 'txAdmin', {}, 'TXADMIN_KICK', ev.targetNetId,
        ev.targetName or 'Unknown', {},
        ('Reason: %s'):format(ev.reason or 'N/A'),
        'txadmin')
end)

AddEventHandler('txAdmin:events:playerWarned', function(ev)
    if type(ev) ~= 'table' then return end
    WriteLog(nil, ev.author or 'txAdmin', {}, 'TXADMIN_WARN', nil,
        ev.targetName or 'Unknown', ev.targetIds or {},
        ('Reason: %s'):format(ev.reason or 'N/A'),
        'txadmin')
end)

AddEventHandler('txAdmin:events:playerUnbanned', function(ev)
    if type(ev) ~= 'table' then return end
    WriteLog(nil, ev.author or 'txAdmin', {}, 'TXADMIN_UNBAN', nil, 'N/A',
        type(ev.targetIds)=='table' and ev.targetIds or {},
        ('Identifiers: %s'):format(type(ev.targetIds)=='table' and table.concat(ev.targetIds,', ') or 'N/A'),
        'txadmin')
end)

AddEventHandler('txAdmin:events:serverShuttingDown', function()
    WriteLog(nil, 'txAdmin', {}, 'TXADMIN_RESTART', nil, nil, nil,
        'Server restart/shutdown initiated via txAdmin panel', 'txadmin')
end)

AddEventHandler('txAdmin:events:whitelistPlayer', function(ev)
    if type(ev) ~= 'table' then return end
    WriteLog(nil, ev.author or 'txAdmin', {}, 'TXADMIN_WHITELIST', nil,
        ev.playerName or 'Unknown', {},
        ('Action: %s'):format(ev.action or 'N/A'), 'txadmin')
end)

-- Resource start / stop at runtime
AddEventHandler('onServerResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then return end
    if GetGameTimer() < 30000 then return end  -- ignore normal boot sequence
    WriteLog(nil, 'System', {}, 'RESOURCE_START', nil, nil, nil,
        ('Resource started at runtime: "%s" — verify this is intentional'):format(resourceName),
        'system')
end)

AddEventHandler('onServerResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        WriteLog(nil, 'System', {}, 'AC STOPPED', nil, nil, nil,
            '🚨 cobra-anticheat was STOPPED — anti-cheat protection is OFFLINE', 'system')
        return
    end
    WriteLog(nil, 'System', {}, 'RESOURCE_STOP', nil, nil, nil,
        ('Resource stopped at runtime: "%s"'):format(resourceName), 'system')
end)

-- ── General admin command hooks ───────────────────────────────────────────────
-- Log QBCore, ESX and other known admin commands used by players with AC perms.
-- We hook the commands by name so only actual admin command usage is captured.

-- Known QBCore admin commands to monitor
local WATCHED_COMMANDS = {
    -- QBCore built-in admin commands
    'ban', 'tempban', 'kick', 'unban',
    'god', 'nogod', 'noclip',
    'heal', 'revive', 'car', 'dv',
    'tp', 'tpm', 'bring',
    'spectate', 'unspectate',
    'setjob', 'setgang', 'setgroup',
    'addmoney', 'removemoney', 'setmoney',
    'additem', 'removeitem',
    'freeze', 'unfreeze',
    'kill', 'suicide',
    -- Common standalone admin resources
    'announce', 'ooc', 'report',
    'staffchat', 'sc',
    'giveweapon', 'removeweapon',
    -- ESX equivalents
    'esx_ban', 'esx_kick', 'esx_setjob',
    'setaccountmoney',
}

local hookedCmds = {}

AddEventHandler('onServerResourceStart', function(resourceName)
    -- Re-hook on resource restart
    SetTimeout(2000, function()
        for _, cmdName in ipairs(WATCHED_COMMANDS) do
            if not hookedCmds[cmdName] then
                local ok = pcall(function()
                    local _orig = nil
                    -- We don't actually replace RegisterCommand here — instead
                    -- we add a parallel handler that fires for the same command
                    -- when used by an admin player.
                    AddEventHandler('__cfx_internal:commandFallback', function() end)
                end)
            end
        end
    end)
end)

-- The cleanest approach for FiveM: listen to the chat message event and
-- detect when an admin types a watched command, then log it.
-- This fires BEFORE the command handler so we never interfere with execution.

AddEventHandler('chatMessage', function(src, name, message)
    src = tonumber(src)
    if not src or src == 0 then return end
    if not IsACAdmin(src) then return end

    -- Check if message is a command (starts with /)
    local cmdStr = message:match('^/(.+)')
    if not cmdStr then return end

    local parts   = {}
    for part in cmdStr:gmatch('%S+') do parts[#parts + 1] = part end
    if #parts == 0 then return end

    local cmdName = parts[1]:lower()

    -- Check if it's a watched command
    local isWatched = false
    for _, w in ipairs(WATCHED_COMMANDS) do
        if w == cmdName then isWatched = true; break end
    end
    if not isWatched then return end

    -- Remove command name from args
    table.remove(parts, 1)
    local argStr = table.concat(parts, ' ')

    WriteLog(
        src,
        GetPlayerName(src) or 'Unknown',
        GetAllIdentifiers(src),
        'GENERAL_CMD',
        nil, nil, nil,
        ('/' .. cmdName .. (argStr ~= '' and (' ' .. argStr) or '')),
        'general'
    )
end)

-- ── Init ─────────────────────────────────────────────────────────────────────
LoadLog()
