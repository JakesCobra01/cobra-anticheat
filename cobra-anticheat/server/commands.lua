-- =============================================
-- cobra-anticheat / server / commands.lua
-- Chat commands for admin actions
-- All commands are logged to the admin audit log.
-- Cobra Development
-- =============================================

-- /acban [id] [duration_minutes] [reason]
RegisterCommand('acban', function(src, args)
    if not IsACAdmin(src) then
        TriggerClientEvent('cobra_ac:notify', src, 'No permission.', 'error'); return
    end
    local targetId = tonumber(args[1])
    local duration = tonumber(args[2]) or 0
    table.remove(args, 1); table.remove(args, 1)
    local reason = table.concat(args, ' ')
    if not targetId or not GetPlayerName(targetId) then
        TriggerClientEvent('cobra_ac:notify', src, 'Invalid player ID.', 'error'); return
    end
    LogAdminAction(src, 'BAN', targetId,
        ('Reason: %s | Duration: %s min'):format(reason ~= '' and reason or 'N/A', tostring(duration)),
        'command')
    BanPlayer(targetId, reason ~= '' and reason or 'Banned by admin', src, duration)
end, false)

-- /acunban [identifier]
RegisterCommand('acunban', function(src, args)
    if not IsACAdmin(src) then
        TriggerClientEvent('cobra_ac:notify', src, 'No permission.', 'error'); return
    end
    local identifier = args[1]
    if not identifier then
        TriggerClientEvent('cobra_ac:notify', src, 'Usage: /acunban [identifier]', 'error'); return
    end
    if UnbanPlayer(identifier, src) then
        LogAdminAction(src, 'UNBAN', nil, 'Identifier: ' .. identifier, 'command')
        TriggerClientEvent('cobra_ac:notify', src, 'Unbanned: ' .. identifier, 'success')
    else
        TriggerClientEvent('cobra_ac:notify', src, 'No ban found for: ' .. identifier, 'error')
    end
end, false)

-- /ackick [id] [reason]
RegisterCommand('ackick', function(src, args)
    if not IsACAdmin(src) then
        TriggerClientEvent('cobra_ac:notify', src, 'No permission.', 'error'); return
    end
    local targetId = tonumber(args[1])
    table.remove(args, 1)
    local reason = table.concat(args, ' ')
    if not targetId or not GetPlayerName(targetId) then
        TriggerClientEvent('cobra_ac:notify', src, 'Invalid player ID.', 'error'); return
    end
    LogAdminAction(src, 'KICK', targetId, reason ~= '' and reason or 'Kicked by admin', 'command')
    KickPlayer(targetId, reason ~= '' and reason or 'Kicked by admin', src)
end, false)

-- /acpanel — open the UI
RegisterCommand('acpanel', function(src)
    if not IsACAdmin(src) then return end
    local log = GetAdminLog and GetAdminLog(200) or {}
    TriggerClientEvent('cobra_ac:openPanel', src, {}, log)
    LogAdminAction(src, 'PANEL OPEN', nil, nil, 'command')
end, false)

-- /actp [id] — teleport to player
RegisterCommand('actp', function(src, args)
    if not IsACAdmin(src) then return end
    local targetId = tonumber(args[1])
    if not targetId or not GetPlayerName(targetId) then return end
    local coords = GetEntityCoords(GetPlayerPed(targetId))
    TriggerClientEvent('cobra_ac:teleportTo', src, coords)
    SendAdminAlert(src, 'TELEPORT TO (CMD)', targetId)
    LogAdminAction(src, 'TELEPORT TO', targetId,
        ('Coords: %.1f, %.1f, %.1f'):format(coords.x, coords.y, coords.z), 'command')
end, false)

-- /acbring [id] — bring player to you
RegisterCommand('acbring', function(src, args)
    if not IsACAdmin(src) then return end
    local targetId = tonumber(args[1])
    if not targetId or not GetPlayerName(targetId) then return end
    local coords = GetEntityCoords(GetPlayerPed(src))
    TriggerClientEvent('cobra_ac:teleportTo', targetId, coords)
    SendAdminAlert(src, 'BRING (CMD)', targetId)
    LogAdminAction(src, 'BRING', targetId,
        ('Admin coords: %.1f, %.1f, %.1f'):format(coords.x, coords.y, coords.z), 'command')
end, false)

-- /acfreeze [id] — freeze/unfreeze a player
RegisterCommand('acfreeze', function(src, args)
    if not IsACAdmin(src) then return end
    local targetId = tonumber(args[1])
    if not targetId or not GetPlayerName(targetId) then return end
    TriggerClientEvent('cobra_ac:setFrozen', targetId, true)
    SendAdminAlert(src, 'FREEZE (CMD)', targetId)
    LogAdminAction(src, 'FREEZE', targetId, nil, 'command')
end, false)

-- /acspectate [id] — spectate a player
RegisterCommand('acspectate', function(src, args)
    if not IsACAdmin(src) then return end
    local targetId = tonumber(args[1])
    if not targetId or not GetPlayerName(targetId) then return end
    TriggerClientEvent('cobra_ac:setSpectate', src, targetId)
    SendAdminAlert(src, 'SPECTATE (CMD)', targetId)
    LogAdminAction(src, 'SPECTATE', targetId, nil, 'command')
end, false)

-- /acflags [id] — print flag summary for a player to admin
RegisterCommand('acflags', function(src, args)
    if not IsACAdmin(src) then return end
    local targetId = tonumber(args[1])
    if not targetId then return end
    local flags = flagCounts and flagCounts[targetId] or {}
    if not next(flags) then
        TriggerClientEvent('cobra_ac:notify', src, 'No flags for player ' .. targetId, 'inform')
        return
    end
    local lines = {}
    for k, v in pairs(flags) do lines[#lines + 1] = k .. ' ×' .. v end
    TriggerClientEvent('cobra_ac:notify', src,
        'Flags for ID ' .. targetId .. ':\n' .. table.concat(lines, ' | '), 'inform')
end, false)

-- /acscreenshot [id] — take a manual screenshot
RegisterCommand('acscreenshot', function(src, args)
    if not IsACAdmin(src) then return end
    local targetId = tonumber(args[1])
    if not targetId or not GetPlayerName(targetId) then return end
    SendAdminScreenshot(src, targetId)
end, false)

-- /achelp — list available commands
RegisterCommand('achelp', function(src)
    if not IsACAdmin(src) then return end
    TriggerClientEvent('cobra_ac:notify', src,
        '/acban /acunban /ackick /actp /acbring /acfreeze /acspectate /acflags /acscreenshot /acpanel /achelp',
        'inform')
end, false)
