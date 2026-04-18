-- =============================================
-- cobra-anticheat / client / noclip.lua
-- Admin noclip (for legitimate admin use)
-- =============================================

local noclipActive = false
local noclipSpeed  = 1.0

RegisterNetEvent('cobra_ac:toggleAdminNoclip', function()
    noclipActive = not noclipActive
    if not noclipActive then
        local ped = PlayerPedId()
        SetEntityCollision(ped, true, true)
        SetEntityVisible(ped, true, false)
    end
end)

CreateThread(function()
    while true do
        Wait(0)
        if noclipActive then
            local ped = PlayerPedId()
            SetEntityCollision(ped, false, false)

            local pos = GetEntityCoords(ped)
            local rot = GetGameplayCamRot(2)
            local dx  = -math.sin(math.rad(rot.z)) * math.cos(math.rad(rot.x))
            local dy  =  math.cos(math.rad(rot.z)) * math.cos(math.rad(rot.x))
            local dz  =  math.sin(math.rad(rot.x))

            local speed = noclipSpeed
            if IsControlPressed(0, 21) then speed = speed * 3.0 end -- Sprint multiplier
            if IsControlPressed(0, 36) then speed = speed * 0.3 end -- Slow multiplier (Alt)

            local newX, newY, newZ = pos.x, pos.y, pos.z

            if IsControlPressed(0, 32) then -- W
                newX = newX + dx * speed
                newY = newY + dy * speed
                newZ = newZ + dz * speed
            end
            if IsControlPressed(0, 33) then -- S
                newX = newX - dx * speed
                newY = newY - dy * speed
                newZ = newZ - dz * speed
            end
            if IsControlPressed(0, 34) then -- A
                local sinZ = -math.sin(math.rad(rot.z - 90))
                local cosZ =  math.cos(math.rad(rot.z - 90))
                newX = newX + sinZ * speed
                newY = newY + cosZ * speed
            end
            if IsControlPressed(0, 35) then -- D
                local sinZ = -math.sin(math.rad(rot.z + 90))
                local cosZ =  math.cos(math.rad(rot.z + 90))
                newX = newX + sinZ * speed
                newY = newY + cosZ * speed
            end
            if IsControlPressed(0, 44) then newZ = newZ + speed end -- Q = up
            if IsControlPressed(0, 38) then newZ = newZ - speed end -- E = down (Context)

            SetEntityCoordsNoOffset(ped, newX, newY, newZ, false, false, false)
            SetEntityRotation(ped, 0, 0, rot.z, 2, true)

            -- Scroll wheel adjusts speed
            if IsControlPressed(0, 15) then noclipSpeed = math.min(noclipSpeed + 0.05, 10.0) end
            if IsControlPressed(0, 14) then noclipSpeed = math.max(noclipSpeed - 0.05, 0.1) end
        end
    end
end)

-- Server-side toggle command for admins
RegisterNetEvent('cobra_ac:adminNoclipToggle', function()
    noclipActive = not noclipActive
    lib.notify({ title = 'Noclip', description = noclipActive and 'Noclip enabled' or 'Noclip disabled', type = 'inform' })
end)

-- NUI callback
RegisterNUICallback('ac_noclip', function(data, cb)
    TriggerServerEvent('cobra_ac:requestNoclip')
    cb('ok')
end)
