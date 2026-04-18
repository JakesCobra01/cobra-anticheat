-- =============================================
-- cobra-anticheat / server / main.lua
-- Core server logic: receive client detections, admin auth, player data
-- =============================================

local playerData  = {}   -- [src] = { name, joinTime, flags, lastPos, ... }
local flagCounts  = {}   -- [src][detType] = count
local spectating  = {}   -- [adminSrc] = targetSrc

-- ── Helpers ──────────────────────────────────────────────────────────────────

--- Check if a source has anticheat admin perms
---@param src number
---@return boolean
function IsACAdmin(src)
    if IsPlayerAceAllowed(src, Config.AcePermission) then return true end
    local license = GetPlayerIdentifierByType(src, 'license')
    if license then
        for _, v in ipairs(Config.CustomAdmins) do
            if v == license then return true end
        end
    end
    return false
end

--- Check granular permission
---@param src number
---@param perm string  Config.Permissions key
---@return boolean
local function HasPerm(src, perm)
    if IsACAdmin(src) then return true end
    return IsPlayerAceAllowed(src, perm)
end

--- Increment flag counter; return new count
local function AddFlag(src, detType)
    flagCounts[src] = flagCounts[src] or {}
    flagCounts[src][detType] = (flagCounts[src][detType] or 0) + 1
    return flagCounts[src][detType]
end

--- Build player list for UI
local function BuildPlayerList()
    local list = {}
    for _, src in ipairs(GetPlayers()) do
        local srcN = tonumber(src)
        local ped  = GetPlayerPed(srcN)
        local pos  = GetEntityCoords(ped)
        local data = playerData[srcN] or {}
        list[#list + 1] = {
            id       = srcN,
            name     = GetPlayerName(srcN) or 'Unknown',
            ping     = GetPlayerPing(srcN),
            flags    = flagCounts[srcN] or {},
            joinTime = data.joinTime or 0,
            coords   = { x = pos.x, y = pos.y, z = pos.z },
            license  = GetPlayerIdentifierByType(srcN, 'license') or '',
            discord  = GetPlayerIdentifierByType(srcN, 'discord') or '',
        }
    end
    return list
end

-- ── Player tracking ──────────────────────────────────────────────────────────

AddEventHandler('playerJoining', function()
    local src = source
    playerData[src] = {
        joinTime = os.time(),
        flags    = 0,
    }
    flagCounts[src] = {}
end)

AddEventHandler('playerDropped', function()
    local src = source
    playerData[src]  = nil
    flagCounts[src]  = nil
    if spectating[src] then spectating[src] = nil end
end)

-- ── Receive detection from client ─────────────────────────────────────────────

RegisterNetEvent('cobra_ac:reportDetection', function(detType, detail, isBlatant, extraData)
    local src        = source
    local count      = AddFlag(src, detType)
    local fullDetail = detail .. ' (Flag #' .. count .. ')'

    if isBlatant then
        SendBlatantAlert(src, detType, fullDetail, extraData)
    else
        SendSuspiciousAlert(src, detType, fullDetail, extraData)
    end

    -- Push live alert to all open admin panels
    local alertPayload = {
        detType    = detType,
        detail     = fullDetail,
        isBlatant  = isBlatant,
        playerId   = src,
        playerName = GetPlayerName(src) or 'Unknown',
        time       = os.date('!%H:%M:%S'),
    }
    for _, rawSrc in ipairs(GetPlayers()) do
        local s = tonumber(rawSrc)
        if HasPerm(s, Config.Permissions.view) then
            TriggerClientEvent('cobra_ac:pushAlert', s, alertPayload)
        end
    end

    -- Auto action
    local action = Config.AutoActions[detType]
    if action == 'ban' then
        BanPlayer(src, 'Auto-ban: ' .. detType, nil, 0)
    elseif action == 'kick' then
        KickPlayer(src, 'Auto-kick: ' .. detType, nil)
    end
end)

-- ── Heartbeat / health check ──────────────────────────────────────────────────

RegisterNetEvent('cobra_ac:heartbeat', function()
    local src = source
    if playerData[src] then
        playerData[src].lastHeartbeat = GetGameTimer()
    end
end)

-- ── Admin: request player list ────────────────────────────────────────────────

RegisterNetEvent('cobra_ac:requestPlayerList', function()
    local src = source
    if not HasPerm(src, Config.Permissions.view) then return end
    TriggerClientEvent('cobra_ac:receivePlayerList', src, BuildPlayerList())
end)

-- ── Admin: kick ───────────────────────────────────────────────────────────────

RegisterNetEvent('cobra_ac:adminKick', function(targetId, reason)
    local src = source
    if not HasPerm(src, Config.Permissions.kick) then return end
    targetId = tonumber(targetId)
    if not GetPlayerName(targetId) then return end
    LogAdminAction(src, 'KICK', targetId, reason, 'panel')
    KickPlayer(targetId, reason or 'Kicked by admin', src)
end)

-- ── Admin: ban ────────────────────────────────────────────────────────────────

RegisterNetEvent('cobra_ac:adminBan', function(targetId, reason, duration)
    local src = source
    if not HasPerm(src, Config.Permissions.ban) then return end
    targetId = tonumber(targetId)
    if not GetPlayerName(targetId) then return end
    LogAdminAction(src, 'BAN', targetId, ('Reason: %s | Duration: %s min'):format(reason or 'N/A', tostring(duration or 0)), 'panel')
    BanPlayer(targetId, reason or 'Banned by admin', src, tonumber(duration) or 0)
end)

-- ── Admin: unban ──────────────────────────────────────────────────────────────

RegisterNetEvent('cobra_ac:adminUnban', function(identifier)
    local src = source
    if not HasPerm(src, Config.Permissions.unban) then return end
    if UnbanPlayer(identifier, src) then
        LogAdminAction(src, 'UNBAN', nil, 'Identifier: ' .. identifier, 'panel')
        TriggerClientEvent('cobra_ac:notify', src, 'Player unbanned: ' .. identifier, 'success')
    else
        TriggerClientEvent('cobra_ac:notify', src, 'No active ban found for: ' .. identifier, 'error')
    end
end)

-- ── Admin: ban offline player by identifier ───────────────────────────────────
-- Allows banning a player who has already left the server using any identifier.

RegisterNetEvent('cobra_ac:adminOfflineBan', function(identifier, reason, duration)
    local src = source
    if not HasPerm(src, Config.Permissions.ban) then return end
    if not identifier or identifier == '' then
        TriggerClientEvent('cobra_ac:notify', src, 'Invalid identifier.', 'error')
        return
    end

    local adminName = GetPlayerName(src) or 'Admin'
    local durStr    = (not duration or duration == 0) and 'Permanent' or (duration .. ' minutes')
    reason          = reason ~= '' and reason or 'Banned by admin'

    if Config.TxAdmin.enabled and GetResourceState('monitor') == 'started' then
        -- Route through txAdmin — pass as identifier ban
        local durationISO = nil
        if duration and duration > 0 then
            durationISO = 'PT' .. duration .. 'M'
        end
        local ok, err = pcall(function()
            exports['monitor']:banPlayer({
                author      = adminName,
                reason      = Config.TxAdmin.reasonPrefix .. reason,
                identifiers = { identifier },
                expiration  = durationISO,
            })
        end)
        if ok then
            TriggerClientEvent('cobra_ac:notify', src, 'Offline player banned via txAdmin.', 'success')
        else
            TriggerClientEvent('cobra_ac:notify', src, 'txAdmin ban failed: ' .. tostring(err), 'error')
            return
        end
    else
        -- Fallback: write directly to local bans.json
        -- We don't have a src to call BanPlayer() on, so write the entry manually
        local expires = (duration and duration > 0) and (os.time() + duration * 60) or 0
        local entry   = {
            reason     = reason,
            adminName  = adminName,
            expires    = expires,
            timestamp  = os.time(),
            playerName = 'Offline Player',
        }
        -- Use the same SaveResourceFile path as bans.lua
        local raw = LoadResourceFile(GetCurrentResourceName(), 'bans.json') or '{}'
        local ok2, bans = pcall(json.decode, raw)
        if ok2 and bans then
            bans[identifier] = entry
            local enc = json.encode(bans)
            SaveResourceFile(GetCurrentResourceName(), 'bans.json', enc, -1)
            TriggerClientEvent('cobra_ac:notify', src, 'Offline player banned locally.', 'success')
        else
            TriggerClientEvent('cobra_ac:notify', src, 'Failed to write ban file.', 'error')
            return
        end
    end

    -- Discord alert and admin log
    local fields = {
        { name = '🪪 Identifier',  value = '`' .. identifier .. '`',  inline = true  },
        { name = '📋 Reason',      value = reason,                     inline = true  },
        { name = '📅 Duration',    value = durStr,                     inline = true  },
        { name = '👮 Issued By',   value = adminName,                  inline = true  },
        { name = '🕐 Time (UTC)', value = os.date('!%Y-%m-%d %H:%M:%S'), inline = false },
    }
    if Config.Webhooks.bans and Config.Webhooks.bans ~= 'YOUR_WEBHOOK_URL_HERE' then
        PerformHttpRequest(Config.Webhooks.bans, function() end, 'POST',
            json.encode({
                username = Config.ServerName .. ' | Cobra Anti-Cheat',
                embeds   = {{
                    title     = '🔨 OFFLINE PLAYER BANNED',
                    color     = Config.Colors.ban,
                    fields    = fields,
                    footer    = { text = 'Cobra Anti-Cheat | ' .. Config.ServerName },
                    timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
                }}
            }),
            { ['Content-Type'] = 'application/json' }
        )
    end

    LogAdminAction(src, 'OFFLINE BAN', nil,
        ('Identifier: %s | Reason: %s | Duration: %s'):format(identifier, reason, durStr),
        'panel')
end)

-- ── Admin: freeze ─────────────────────────────────────────────────────────────

RegisterNetEvent('cobra_ac:adminFreeze', function(targetId, frozen)
    local src = source
    if not HasPerm(src, Config.Permissions.moderate) then return end
    targetId = tonumber(targetId)
    TriggerClientEvent('cobra_ac:setFrozen', targetId, frozen)
    local act = frozen and 'FREEZE' or 'UNFREEZE'
    SendAdminAlert(src, act, targetId)
    LogAdminAction(src, act, targetId, nil, 'panel')
end)

-- ── Admin: teleport to player ─────────────────────────────────────────────────

RegisterNetEvent('cobra_ac:adminTeleportTo', function(targetId)
    local src = source
    if not HasPerm(src, Config.Permissions.moderate) then return end
    targetId = tonumber(targetId)
    local ped    = GetPlayerPed(targetId)
    local coords = GetEntityCoords(ped)
    TriggerClientEvent('cobra_ac:teleportTo', src, coords)
    SendAdminAlert(src, 'TELEPORT TO', targetId)
    LogAdminAction(src, 'TELEPORT TO', targetId, ('Coords: %.1f, %.1f, %.1f'):format(coords.x, coords.y, coords.z), 'panel')
end)

-- ── Admin: bring player ───────────────────────────────────────────────────────

RegisterNetEvent('cobra_ac:adminBring', function(targetId)
    local src = source
    if not HasPerm(src, Config.Permissions.moderate) then return end
    targetId = tonumber(targetId)
    local ped    = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    TriggerClientEvent('cobra_ac:teleportTo', targetId, coords)
    SendAdminAlert(src, 'BRING', targetId)
    LogAdminAction(src, 'BRING', targetId, ('Admin coords: %.1f, %.1f, %.1f'):format(coords.x, coords.y, coords.z), 'panel')
end)

-- ── Admin: spectate ───────────────────────────────────────────────────────────

RegisterNetEvent('cobra_ac:adminSpectate', function(targetId)
    local src = source
    if not HasPerm(src, Config.Permissions.moderate) then return end
    targetId = tonumber(targetId)
    spectating[src] = targetId
    TriggerClientEvent('cobra_ac:setSpectate', src, targetId)
    SendAdminAlert(src, 'SPECTATE', targetId)
    LogAdminAction(src, 'SPECTATE', targetId, nil, 'panel')
end)

RegisterNetEvent('cobra_ac:adminStopSpectate', function()
    local src = source
    spectating[src] = nil
    TriggerClientEvent('cobra_ac:setSpectate', src, nil)
    LogAdminAction(src, 'STOP SPECTATE', nil, nil, 'panel')
end)

-- ── Admin: clear flags ────────────────────────────────────────────────────────

RegisterNetEvent('cobra_ac:adminClearFlags', function(targetId)
    local src = source
    if not HasPerm(src, Config.Permissions.moderate) then return end
    targetId = tonumber(targetId)
    local oldFlags = json.encode(flagCounts[targetId] or {})
    flagCounts[targetId] = {}
    TriggerClientEvent('cobra_ac:notify', src, 'Flags cleared for player ' .. targetId, 'success')
    SendAdminAlert(src, 'CLEAR FLAGS', targetId)
    LogAdminAction(src, 'CLEAR FLAGS', targetId, 'Cleared flags: ' .. oldFlags, 'panel')
end)

-- ── Admin: screenshot request ─────────────────────────────────────────────────

RegisterNetEvent('cobra_ac:adminScreenshot', function(targetId)
    local src = source
    if not HasPerm(src, Config.Permissions.moderate) then return end
    targetId = tonumber(targetId)
    if not GetPlayerName(targetId) then return end
    SendAdminScreenshot(src, targetId)
end)

-- ── Admin: open UI ───────────────────────────────────────────────────────────

RegisterNetEvent('cobra_ac:openUI', function()
    local src = source
    if not HasPerm(src, Config.Permissions.view) then return end
    local log = GetAdminLog and GetAdminLog(200) or {}
    TriggerClientEvent('cobra_ac:openPanel', src, BuildPlayerList(), log)
    LogAdminAction(src, 'PANEL OPEN', nil, nil, 'panel')
end)

-- ── Periodic player list refresh ──────────────────────────────────────────────

CreateThread(function()
    while true do
        Wait(5000)
        -- Broadcast updated player list to all admins currently with panel open
        for _, rawSrc in ipairs(GetPlayers()) do
            local s = tonumber(rawSrc)
            if HasPerm(s, Config.Permissions.view) then
                TriggerClientEvent('cobra_ac:receivePlayerList', s, BuildPlayerList())
            end
        end
    end
end)
