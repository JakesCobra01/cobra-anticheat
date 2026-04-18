-- =============================================
-- cobra-anticheat / client / detections.lua
-- All client-side cheat detection loops
-- =============================================

local playerPed   = PlayerPedId()
local lastPos     = GetEntityCoords(playerPed)
local lastHealth  = GetEntityHealth(playerPed)
local lastArmour  = GetPedArmour(playerPed)
local lastAmmo    = {}
local shotCount   = 0
local shotTimer   = GetGameTimer()
local explosionCount = 0
local explosionTimer = GetGameTimer()
local noClipFrames   = 0
local entityCount    = 0
local entityTimer    = GetGameTimer()
local inVehicleLast  = false
local lastVehicleHealth = 1000.0

-- Refresh ped reference periodically
CreateThread(function()
    while true do
        Wait(1000)
        playerPed = PlayerPedId()
    end
end)

--- Report a detection to the server
---@param detType string
---@param detail string
---@param isBlatant boolean
local function Report(detType, detail, isBlatant)
    TriggerServerEvent('cobra_ac:reportDetection', detType, detail, isBlatant)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- GOD MODE DETECTION
-- ─────────────────────────────────────────────────────────────────────────────
if Config.Detections.godMode then
    CreateThread(function()
        while true do
            Wait(Config.UI.detectionInterval)
            if GetEntityInvincible(playerPed) then
                Report('godMode', 'Player entity is invincible (god mode flag set)', true)
            end
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- HEALTH REGEN DETECTION
-- ─────────────────────────────────────────────────────────────────────────────
if Config.Detections.healthRegen then
    CreateThread(function()
        while true do
            Wait(Config.UI.detectionInterval)
            local hp = GetEntityHealth(playerPed)
            if hp > lastHealth + Config.Thresholds.healthRegenMax then
                local gained = hp - lastHealth
                Report('healthRegen', ('Health jumped by %d HP (%.0f → %.0f)'):format(gained, lastHealth, hp), false)
            end
            lastHealth = hp
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- ARMOUR REGEN DETECTION
-- ─────────────────────────────────────────────────────────────────────────────
if Config.Detections.armourRegen then
    CreateThread(function()
        while true do
            Wait(Config.UI.detectionInterval)
            local arm = GetPedArmour(playerPed)
            if arm > lastArmour + Config.Thresholds.healthRegenMax then
                local gained = arm - lastArmour
                Report('armourRegen', ('Armour jumped by %d (%.0f → %.0f)'):format(gained, lastArmour, arm), false)
            end
            lastArmour = arm
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- SPEED HACK & NOCLIP DETECTION
-- ─────────────────────────────────────────────────────────────────────────────
if Config.Detections.speedHack or Config.Detections.noClip then
    CreateThread(function()
        while true do
            Wait(500)
            local pos   = GetEntityCoords(playerPed)
            local vel   = GetEntityVelocity(playerPed)
            local speed = #(vector3(vel.x, vel.y, vel.z))

            -- On foot speed
            if Config.Detections.speedHack and not IsPedInAnyVehicle(playerPed, false) then
                if speed > Config.Thresholds.footSpeedMax and not IsPedRagdoll(playerPed) then
                    Report('speedHack', ('On-foot speed: %.1f m/s (max %.1f)'):format(speed, Config.Thresholds.footSpeedMax), false)
                end
            end

            -- Vehicle speed
            if Config.Detections.speedHack and IsPedInAnyVehicle(playerPed, false) then
                local veh = GetVehiclePedIsIn(playerPed, false)
                local vSpeed = GetEntitySpeed(veh)
                if vSpeed > Config.Thresholds.vehicleSpeedMax then
                    Report('speedHack', ('Vehicle speed: %.1f m/s (max %.1f)'):format(vSpeed, Config.Thresholds.vehicleSpeedMax), false)
                end
            end

            -- NoClip: detect movement through solid geometry by checking if
            -- the player is airborne but not actually in the air
            if Config.Detections.noClip then
                if not IsPedInAnyVehicle(playerPed, false) then
                    local onGround = IsEntityOnGround(playerPed)
                    local falling  = IsPedFalling(playerPed)
                    local jumping  = IsPedJumping(playerPed)
                    local ragdoll  = IsPedRagdoll(playerPed)
                    local height   = pos.z

                    -- If player is moving horizontally fast but not on ground and not legit airborne
                    if not onGround and not falling and not jumping and not ragdoll then
                        local horizSpeed = math.sqrt(vel.x^2 + vel.y^2)
                        if horizSpeed > 5.0 then
                            noClipFrames = noClipFrames + 1
                        else
                            noClipFrames = math.max(0, noClipFrames - 1)
                        end
                    else
                        noClipFrames = math.max(0, noClipFrames - 2)
                    end

                    if noClipFrames >= Config.Thresholds.noClipFrames then
                        noClipFrames = 0
                        Report('noClip', ('Possible noclip detected at %.1f,%.1f,%.1f'):format(pos.x, pos.y, pos.z), true)
                    end
                end
            end

            lastPos = pos
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TELEPORT DETECTION
-- ─────────────────────────────────────────────────────────────────────────────
if Config.Detections.teleport then
    CreateThread(function()
        while true do
            Wait(500)
            local pos  = GetEntityCoords(playerPed)
            local dist = #(pos - lastPos)
            if dist > Config.Thresholds.teleportDistance
               and not IsPedInAnyVehicle(playerPed, false)
               and not IsScreenFadedOut()
               and not IsScreenFadingOut()
               and not IsScreenFadingIn() then
                Report('teleport', ('Jumped %.0f units (%.0f,%.0f,%.0f → %.0f,%.0f,%.0f)')
                    :format(dist, lastPos.x, lastPos.y, lastPos.z, pos.x, pos.y, pos.z), false)
            end
            lastPos = pos
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- SUPER JUMP DETECTION
-- ─────────────────────────────────────────────────────────────────────────────
if Config.Detections.superJump then
    CreateThread(function()
        while true do
            Wait(200)
            if IsPedJumping(playerPed) or IsPedFalling(playerPed) then
                local vel = GetEntityVelocity(playerPed)
                if vel.z > Config.Thresholds.superJumpVelocity then
                    Report('superJump', ('Vertical velocity: %.1f m/s (max %.1f)'):format(vel.z, Config.Thresholds.superJumpVelocity), false)
                end
            end
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- INVISIBILITY DETECTION
-- ─────────────────────────────────────────────────────────────────────────────
if Config.Detections.invisibility then
    CreateThread(function()
        while true do
            Wait(2000)
            if not IsEntityVisible(playerPed) then
                Report('invisibility', 'Player entity is not visible (invisible flag set)', true)
            end
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- EXPLOSION SPAM DETECTION
-- ─────────────────────────────────────────────────────────────────────────────
if Config.Detections.explosionSpam then
    AddEventHandler('explosionEvent', function(sender, ev)
        if sender == PlayerId() then
            local now = GetGameTimer()
            if (now - explosionTimer) > Config.Thresholds.explosionInterval then
                explosionCount = 0
                explosionTimer = now
            end
            explosionCount = explosionCount + 1
            if explosionCount >= Config.Thresholds.explosionMax then
                explosionCount = 0
                Report('explosionSpam', ('>=%d explosions in %dms'):format(
                    Config.Thresholds.explosionMax, Config.Thresholds.explosionInterval), true)
            end
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- RAPID FIRE / INFINITE AMMO DETECTION
-- ─────────────────────────────────────────────────────────────────────────────
if Config.Detections.rapidFire or Config.Detections.infiniteAmmo then
    CreateThread(function()
        while true do
            Wait(100)
            if IsPedShooting(playerPed) then
                local weapon = GetSelectedPedWeapon(playerPed)
                local ammo   = GetAmmoInPedWeapon(playerPed, weapon)

                -- Rapid fire
                if Config.Detections.rapidFire then
                    local now = GetGameTimer()
                    if (now - shotTimer) > 1000 then
                        shotCount = 0
                        shotTimer = now
                    end
                    shotCount = shotCount + 1
                    if shotCount > Config.Thresholds.rapidFireMax then
                        shotCount = 0
                        Report('rapidFire', ('%.0f shots/s with %s'):format(
                            Config.Thresholds.rapidFireMax, GetLabelText(GetWeaponName(weapon))), false)
                    end
                end

                -- Infinite ammo: ammo should decrease when shooting
                if Config.Detections.infiniteAmmo then
                    if lastAmmo[weapon] and ammo ~= 0 and ammo >= lastAmmo[weapon] then
                        Report('infiniteAmmo', ('Ammo did not decrease while shooting (weapon: %s, ammo: %d)'):format(
                            weapon, ammo), true)
                    end
                end
                lastAmmo[weapon] = ammo
            else
                -- Reset shot counter when not shooting
                shotCount = 0
            end
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- BLACKLISTED WEAPON DETECTION
-- ─────────────────────────────────────────────────────────────────────────────
if Config.Detections.blacklistedWeapons then
    CreateThread(function()
        while true do
            Wait(2000)
            local weapon = GetSelectedPedWeapon(playerPed)
            local wName  = GetHashKey(GetEntityModel(playerPed)) -- dummy; use weapon hash
            for _, bw in ipairs(Config.BlacklistedWeapons) do
                if weapon == GetHashKey(bw) then
                    Report('blacklistedWeapons', ('Player has blacklisted weapon: %s'):format(bw), true)
                    break
                end
            end
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- VEHICLE GOD MODE DETECTION
-- ─────────────────────────────────────────────────────────────────────────────
if Config.Detections.vehicleGodMode then
    CreateThread(function()
        while true do
            Wait(1000)
            if IsPedInAnyVehicle(playerPed, false) then
                local veh = GetVehiclePedIsIn(playerPed, false)
                local hp  = GetVehicleBodyHealth(veh)
                if GetEntityInvincible(veh) then
                    Report('vehicleGodMode', 'Vehicle invincibility flag is set', true)
                end
                lastVehicleHealth = hp
            end
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- RESOURCE INJECTION DETECTION
-- ─────────────────────────────────────────────────────────────────────────────
if Config.Detections.resourceInjection then
    AddEventHandler('onClientResourceStart', function(resourceName)
        local allowed = false
        for _, r in ipairs(Config.AllowedResources) do
            if r == resourceName then allowed = true; break end
        end
        if not allowed then
            Report('resourceInjection', ('Unknown resource started: %s'):format(resourceName), true)
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CHEAT MENU SIGNATURE DETECTION
-- Check for known exported net events / global variables used by cheat menus
-- ─────────────────────────────────────────────────────────────────────────────
if Config.Detections.menuDetection then
    CreateThread(function()
        Wait(5000) -- Let the game load first
        for _, sig in ipairs(Config.CheatSignatures) do
            -- Attempt to detect if a known cheat menu event/export exists
            if _G[sig] ~= nil then
                Report('menuDetection', ('Cheat signature detected: %s'):format(sig), true)
            end
        end
    end)

    -- Monitor for known cheat menu net events being triggered
    -- This hooks into the event system at a low level
    local originalAddEventHandler = AddEventHandler
    for _, sig in ipairs(Config.CheatSignatures) do
        AddEventHandler(sig, function()
            Report('menuDetection', ('Cheat menu event fired: %s'):format(sig), true)
        end)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- VEHICLE SPAWN DETECTION (blacklisted models)
-- ─────────────────────────────────────────────────────────────────────────────
if Config.Detections.vehicleSpawn then
    CreateThread(function()
        while true do
            Wait(2000)
            if IsPedInAnyVehicle(playerPed, false) then
                local veh   = GetVehiclePedIsIn(playerPed, false)
                local model = GetEntityModel(veh)
                for _, bv in ipairs(Config.BlacklistedVehicles) do
                    if model == GetHashKey(bv) then
                        -- Only flag if they spawned into it (are the driver and PedId matches)
                        if GetPedInVehicleSeat(veh, -1) == playerPed then
                            Report('vehicleSpawn', ('Player driving blacklisted vehicle: %s'):format(bv), true)
                        end
                        break
                    end
                end
            end
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- NIGHT VISION / THERMAL VISION DETECTION
-- ─────────────────────────────────────────────────────────────────────────────
if Config.Detections.nightVision then
    CreateThread(function()
        while true do
            Wait(3000)
            if IsNightvisionActive() then
                Report('nightVision', 'Player has night vision active without valid item', false)
            end
        end
    end)
end

if Config.Detections.thermalVision then
    CreateThread(function()
        while true do
            Wait(3000)
            if IsThermalvisionActive() then
                Report('thermalVision', 'Player has thermal vision active without valid item', false)
            end
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- FALLING DAMAGE DETECTION
-- Detect if player takes no damage from large falls
-- ─────────────────────────────────────────────────────────────────────────────
if Config.Detections.fallingDamage then
    local wasFalling   = false
    local fallStartZ   = 0.0
    local fallStartHp  = 0

    CreateThread(function()
        while true do
            Wait(200)
            local pos = GetEntityCoords(playerPed)
            local hp  = GetEntityHealth(playerPed)

            if IsPedFalling(playerPed) and not wasFalling then
                wasFalling  = true
                fallStartZ  = pos.z
                fallStartHp = hp
            elseif not IsPedFalling(playerPed) and wasFalling then
                wasFalling = false
                local fallDist = fallStartZ - pos.z
                if fallDist > 8.0 then
                    -- Significant fall — if no HP lost, flag it
                    if hp >= fallStartHp then
                        Report('fallingDamage', ('Fell %.1f units with no damage taken'):format(fallDist), false)
                    end
                end
            end
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- COORD BOUNCE DETECTION (erratic position snapping)
-- ─────────────────────────────────────────────────────────────────────────────
if Config.Detections.coordBounce then
    local positions = {}
    CreateThread(function()
        while true do
            Wait(300)
            local pos = GetEntityCoords(playerPed)
            positions[#positions + 1] = pos
            if #positions > 5 then table.remove(positions, 1) end
            if #positions == 5 then
                local bounces = 0
                for i = 2, #positions do
                    local d = #(positions[i] - positions[i-1])
                    if d > 20.0 and d < Config.Thresholds.teleportDistance then
                        bounces = bounces + 1
                    end
                end
                if bounces >= 3 then
                    Report('coordBounce', 'Position bouncing erratically — possible desync exploit', false)
                    positions = {}
                end
            end
        end
    end)
end
