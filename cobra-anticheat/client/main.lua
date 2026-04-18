-- =============================================
-- cobra-anticheat / client / main.lua
-- UI control, heartbeat, admin action receivers
-- Cobra Development
-- =============================================

local uiOpen       = false
local isFrozen     = false
local isSpectating = false

CreateThread(function()
    while true do
        Wait(Config.UI.heartbeatInterval)
        TriggerServerEvent('cobra_ac:heartbeat')
    end
end)

RegisterCommand('acpanel', function()
    TriggerServerEvent('cobra_ac:openUI')
end, false)

RegisterKeyMapping('acpanel', 'Open Cobra Anti-Cheat Panel', 'keyboard', Config.UI.openKey)

RegisterNUICallback('ac_action', function(data, cb)
    local action = data.action

    if action == 'kick' then
        TriggerServerEvent('cobra_ac:adminKick', data.targetId, data.reason)
    elseif action == 'ban' then
        TriggerServerEvent('cobra_ac:adminBan', data.targetId, data.reason, data.duration)
    elseif action == 'offlineBan' then
        TriggerServerEvent('cobra_ac:adminOfflineBan', data.identifier, data.reason, data.duration)
    elseif action == 'unban' then
        TriggerServerEvent('cobra_ac:adminUnban', data.identifier)
    elseif action == 'freeze' then
        TriggerServerEvent('cobra_ac:adminFreeze', data.targetId, data.frozen)
    elseif action == 'teleportTo' then
        TriggerServerEvent('cobra_ac:adminTeleportTo', data.targetId)
    elseif action == 'bring' then
        TriggerServerEvent('cobra_ac:adminBring', data.targetId)
    elseif action == 'spectate' then
        TriggerServerEvent('cobra_ac:adminSpectate', data.targetId)
    elseif action == 'stopSpectate' then
        TriggerServerEvent('cobra_ac:adminStopSpectate')
    elseif action == 'screenshot' then
        TriggerServerEvent('cobra_ac:adminScreenshot', data.targetId)
    elseif action == 'clearFlags' then
        TriggerServerEvent('cobra_ac:adminClearFlags', data.targetId)
    elseif action == 'refreshList' then
        TriggerServerEvent('cobra_ac:requestPlayerList')
    elseif action == 'requestAdminLog' then
        TriggerServerEvent('cobra_ac:requestAdminLog', data.limit or 200)
    elseif action == 'closeUI' then
        CloseUI()
    end

    cb('ok')
end)

RegisterNetEvent('cobra_ac:openPanel', function(playerList, adminLogData)
    uiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        type       = 'openPanel',
        playerList = playerList  or {},
        adminLog   = adminLogData or {},
    })
end)

RegisterNetEvent('cobra_ac:receivePlayerList', function(list)
    if uiOpen then
        SendNUIMessage({ type = 'updatePlayerList', playerList = list })
    end
end)

RegisterNetEvent('cobra_ac:receiveAdminLog', function(log)
    if uiOpen then
        SendNUIMessage({ type = 'receiveAdminLog', log = log })
    end
end)

RegisterNetEvent('cobra_ac:pushAlert', function(alert)
    if uiOpen then
        SendNUIMessage({ type = 'newAlert', alert = alert })
    end
end)

function CloseUI()
    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'closePanel' })
end

CreateThread(function()
    while true do
        Wait(0)
        if uiOpen and IsControlJustReleased(0, 200) then CloseUI() end
    end
end)

RegisterNetEvent('cobra_ac:setFrozen', function(frozen)
    isFrozen = frozen
    FreezeEntityPosition(PlayerPedId(), frozen)
end)

CreateThread(function()
    while true do
        Wait(500)
        if isFrozen then FreezeEntityPosition(PlayerPedId(), true) end
    end
end)

RegisterNetEvent('cobra_ac:teleportTo', function(coords)
    SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z, false, false, false, true)
end)

RegisterNetEvent('cobra_ac:setSpectate', function(targetId)
    if targetId then
        isSpectating = true
        NetworkSetInSpectatorMode(true, GetPlayerPed(GetPlayerFromServerId(targetId)))
    else
        isSpectating = false
        NetworkSetInSpectatorMode(false, PlayerPedId())
    end
end)

RegisterNetEvent('cobra_ac:notify', function(msg, notifType)
    lib.notify({ title = 'Cobra Anti-Cheat', description = msg, type = notifType or 'inform' })
end)
