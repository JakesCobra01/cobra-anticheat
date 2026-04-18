-- =============================================
-- cobra-anticheat / client / advanced_detections.lua
-- Aimbot, Wallhack and Item Duplication detection
-- =============================================

local playerPed = PlayerPedId()

CreateThread(function()
    while true do
        Wait(1000)
        playerPed = PlayerPedId()
    end
end)

local function Report(detType, detail, isBlatant, extraData)
    TriggerServerEvent('cobra_ac:reportDetection', detType, detail, isBlatant, extraData)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- AIMBOT DETECTION
--
-- Strategy: Legitimate aiming is gradual and follows natural mouse movement.
-- Aimbot characteristics:
--   1. Snap-lock  — camera angle changes by a huge amount in a single frame
--                   then locks precisely onto a bone (head/chest)
--   2. Perfect tracking — camera heading matches target bone direction with
--                   near-zero variance across many frames while shooting
--   3. Bone precision — shots land on head/chest exclusively at rates far
--                   above what human accuracy allows
--   4. Zero-Z deviation — aimbot locks Z-axis perfectly; human aim drifts
-- ─────────────────────────────────────────────────────────────────────────────
if Config.Detections.aimbot then

    local SNAP_THRESHOLD_DEG    = Config.Thresholds.aimbotSnapDeg     -- degrees/frame
    local LOCK_VARIANCE_MAX     = Config.Thresholds.aimbotLockVariance -- heading variance
    local HEADSHOT_RATE_MAX     = Config.Thresholds.aimbotHeadshotRate -- 0.0-1.0
    local SAMPLE_WINDOW         = Config.Thresholds.aimbotSampleFrames -- frames to sample

    local lastCamHeading        = 0.0
    local lastCamPitch          = 0.0
    local snapFrames            = 0
    local shootingFrames        = 0
    local totalShots            = 0
    local headshotCount         = 0
    local headingHistory        = {}   -- ring buffer for lock-on variance
    local pitchHistory          = {}
    local frameIdx              = 0

    CreateThread(function()
        while true do
            Wait(0)
            local isShooting = IsPedShooting(playerPed)
            local camHeading = GetGameplayCamRelativeHeading()
            local camRot     = GetGameplayCamRot(2)
            local camPitch   = camRot.x

            local dHeading   = math.abs(camHeading - lastCamHeading)
            local dPitch     = math.abs(camPitch   - lastCamPitch)
            -- Wrap-around correction (359° → 0°)
            if dHeading > 180.0 then dHeading = 360.0 - dHeading end

            -- ── 1. SNAP DETECTION ─────────────────────────────────────────
            -- If camera snaps a huge angle AND player is aiming, flag it.
            if IsPedAiming(playerPed) and dHeading > SNAP_THRESHOLD_DEG then
                snapFrames = snapFrames + 1
            else
                snapFrames = math.max(0, snapFrames - 1)
            end

            if snapFrames >= Config.Thresholds.aimbotSnapFrames then
                snapFrames = 0
                Report('aimbot', ('Camera snap detected: %.1f° heading change in single frame'):format(dHeading), true, {
                    heading     = camHeading,
                    pitch       = camPitch,
                    deltaHeading = dHeading,
                    weapon      = GetSelectedPedWeapon(playerPed),
                })
            end

            -- ── 2. LOCK-ON VARIANCE (perfect tracking) ────────────────────
            -- While shooting, track heading variance. Real humans drift.
            if isShooting then
                shootingFrames = shootingFrames + 1
                frameIdx = (frameIdx % SAMPLE_WINDOW) + 1
                headingHistory[frameIdx] = camHeading
                pitchHistory[frameIdx]   = camPitch

                if shootingFrames >= SAMPLE_WINDOW then
                    -- Calculate standard deviation of heading during shooting burst
                    local sumH, sumP = 0.0, 0.0
                    for _, v in ipairs(headingHistory) do sumH = sumH + v end
                    for _, v in ipairs(pitchHistory)   do sumP = sumP + v end
                    local meanH = sumH / #headingHistory
                    local meanP = sumP / #pitchHistory
                    local varH  = 0.0
                    for _, v in ipairs(headingHistory) do varH = varH + (v - meanH)^2 end
                    varH = varH / #headingHistory

                    if varH < LOCK_VARIANCE_MAX then
                        Report('aimbot', ('Lock-on detected: heading variance %.4f (threshold %.4f) over %d frames while shooting'):format(
                            varH, LOCK_VARIANCE_MAX, SAMPLE_WINDOW), true, {
                            variance    = varH,
                            meanHeading = meanH,
                            weapon      = GetSelectedPedWeapon(playerPed),
                        })
                    end

                    -- Reset window
                    headingHistory = {}
                    pitchHistory   = {}
                    shootingFrames = 0
                end
            else
                if shootingFrames > 0 and shootingFrames < SAMPLE_WINDOW then
                    headingHistory = {}
                    pitchHistory   = {}
                end
                shootingFrames = 0
            end

            -- ── 3. HEADSHOT RATE ──────────────────────────────────────────
            -- Track headshots vs total shots. Sample over time.
            if IsPedShooting(playerPed) then
                totalShots = totalShots + 1
                -- Approximate headshot: check if nearest bone hit
                local target = GetEntityPlayerIsDriving(PlayerId()) -- not the vehicle
                -- Use weapon impact coordinates vs target head bone
                local hasHit, hitEntity, hitCoords = GetPedLastWeaponImpactCoord(playerPed)
                if hasHit then
                    -- Check if any nearby ped has their head bone near the impact
                    local peds = GetGamePool('CPed')
                    for _, ped in ipairs(peds) do
                        if ped ~= playerPed and IsPedAPlayer(ped) then
                            local headBone = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0) -- SKEL_Head
                            if #(hitCoords - headBone) < 0.3 then
                                headshotCount = headshotCount + 1
                                break
                            end
                        end
                    end
                end

                if totalShots >= Config.Thresholds.aimbotShotSample then
                    local rate = headshotCount / totalShots
                    if rate >= HEADSHOT_RATE_MAX then
                        Report('aimbot', ('Headshot rate %.0f%% (%d/%d shots) — well above human maximum'):format(
                            rate * 100, headshotCount, totalShots), true, {
                            headshotRate = rate,
                            totalShots   = totalShots,
                            headshotCount = headshotCount,
                            weapon       = GetSelectedPedWeapon(playerPed),
                        })
                    end
                    -- Rolling reset
                    totalShots    = 0
                    headshotCount = 0
                end
            end

            lastCamHeading = camHeading
            lastCamPitch   = camPitch
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- WALLHACK / ESP DETECTION
--
-- Wallhacks work by modifying rendering or using natives to reveal players
-- behind cover. We detect:
--   1. Shooting through solid geometry (bullet hits a player but the shooter
--      has no line-of-sight to that player)
--   2. Shooting at players who are completely out of normal render/sight range
--   3. Known ESP net-event patterns (resources broadcasting all player coords)
-- ─────────────────────────────────────────────────────────────────────────────
if Config.Detections.wallhack then

    -- ── 1. SHOOTING THROUGH WALLS ────────────────────────────────────────────
    CreateThread(function()
        while true do
            Wait(200)
            if IsPedShooting(playerPed) then
                local hasHit, hitCoords = GetPedLastWeaponImpactCoord(playerPed)
                if hasHit then
                    local myPos  = GetEntityCoords(playerPed)
                    local camPos = GetGameplayCamCoords()

                    -- Check if there is geometry between camera and the impact point
                    -- GetShapeTestResultEx: 1 = hit, 0 = clear
                    local rayHandle = StartShapeTestRay(
                        camPos.x, camPos.y, camPos.z,
                        hitCoords.x, hitCoords.y, hitCoords.z,
                        1,        -- 1 = Map collision (world geometry)
                        playerPed,
                        0
                    )
                    local _, hit, hitFinalCoords, _, hitEntity = GetShapeTestResult(rayHandle)

                    if hit == 1 then
                        -- There is a wall between camera and impact point
                        -- Check if the impact hit a player ped
                        local peds = GetGamePool('CPed')
                        for _, ped in ipairs(peds) do
                            if ped ~= playerPed and IsPedAPlayer(ped) then
                                if #(hitCoords - GetEntityCoords(ped)) < 2.0 then
                                    local targetServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(ped))
                                    Report('wallhack',
                                        ('Shot through wall geometry: hit player (SrvID %d) through solid surface at %.1f,%.1f,%.1f'):format(
                                            targetServerId, hitCoords.x, hitCoords.y, hitCoords.z),
                                        true,
                                        { targetServerId = targetServerId, hitCoords = { x = hitCoords.x, y = hitCoords.y, z = hitCoords.z } }
                                    )
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end)

    -- ── 2. TARGETING PLAYERS OUT OF LOS ──────────────────────────────────────
    -- If a player is actively aiming at another player who is completely
    -- behind cover (no clear LOS), that's a strong indicator of ESP/wallhack.
    CreateThread(function()
        while true do
            Wait(500)
            if IsPedAiming(playerPed) then
                local camPos  = GetGameplayCamCoords()
                local camFwd  = GetGameplayCamRot(2)
                local fwdVec  = RotationToDirection(camFwd)
                local aimEnd  = vector3(
                    camPos.x + fwdVec.x * 150.0,
                    camPos.y + fwdVec.y * 150.0,
                    camPos.z + fwdVec.z * 150.0
                )

                local peds = GetGamePool('CPed')
                for _, ped in ipairs(peds) do
                    if ped ~= playerPed and IsPedAPlayer(ped) then
                        local pedPos = GetEntityCoords(ped)
                        local dist   = #(GetEntityCoords(playerPed) - pedPos)

                        -- Only check peds that are within reasonable aim range
                        if dist < 100.0 then
                            -- Check if aim vector passes near this ped (within ~2m)
                            local toTarget   = pedPos - camPos
                            local dot        = toTarget.x * fwdVec.x + toTarget.y * fwdVec.y + toTarget.z * fwdVec.z
                            local projected  = vector3(camPos.x + fwdVec.x * dot, camPos.y + fwdVec.y * dot, camPos.z + fwdVec.z * dot)
                            local aimDeviation = #(projected - pedPos)

                            if aimDeviation < 2.5 then
                                -- Player is aimed at this ped — check LOS
                                local myPos = GetEntityCoords(playerPed)
                                local hasLOS = HasEntityClearLosToEntityInFront(playerPed, ped)
                                if not hasLOS then
                                    local targetSrvId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(ped))
                                    Report('wallhack',
                                        ('Aiming at player (SrvID %d) through solid cover at %.0f distance — no LOS'):format(
                                            targetSrvId, dist),
                                        false,
                                        { targetServerId = targetSrvId, distance = dist }
                                    )
                                end
                            end
                        end
                    end
                end
            end
        end
    end)

    -- ── 3. KNOWN ESP NET EVENT SIGNATURES ────────────────────────────────────
    -- Some ESP resources broadcast player coordinates to all clients.
    -- Hook into known patterns.
    local espSignatures = {
        'esp:updatePositions',
        'esp:playerList',
        'esp:allPlayers',
        'wallhack:coords',
        'radar:allPlayers',
        '__esp_broadcast',
    }
    for _, sig in ipairs(espSignatures) do
        AddEventHandler(sig, function()
            Report('wallhack', ('Known ESP broadcast event received: %s'):format(sig), true, {})
        end)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- ITEM DUPLICATION DETECTION
--
-- Duplication happens when players exploit inventory callbacks or trigger
-- server-side give/receive events in ways that create multiple items from
-- a single source. Client-side we detect:
--   1. Rapid inventory event firing (player firing item give/take events
--      faster than any legitimate UI interaction allows)
--   2. Known dupe exploit net event patterns
--   3. Monitoring QBCore item callbacks being triggered in quick succession
-- ─────────────────────────────────────────────────────────────────────────────
if Config.Detections.itemDupe then

    local itemEventCount = 0
    local itemEventTimer = GetGameTimer()
    local itemEventLog   = {}   -- track which events fired for detail

    -- Rate-limit sensitive: legitimate inventory transactions are at MOST
    -- 1-2 per second. Dupers fire them dozens of times per second.
    local function OnInventoryEvent(eventName)
        local now  = GetGameTimer()
        local diff = now - itemEventTimer

        if diff > Config.Thresholds.dupeWindowMs then
            itemEventCount = 0
            itemEventTimer = now
            itemEventLog   = {}
        end

        itemEventCount = itemEventCount + 1
        itemEventLog[#itemEventLog + 1] = eventName

        if itemEventCount >= Config.Thresholds.dupeEventMax then
            local logStr = table.concat(itemEventLog, ', ')
            Report('itemDupe',
                ('Inventory event flooding: %d events in %dms — Events: %s'):format(
                    itemEventCount, diff, logStr),
                true,
                { eventCount = itemEventCount, windowMs = diff, events = itemEventLog }
            )
            itemEventCount = 0
            itemEventLog   = {}
        end
    end

    -- Hook known QBCore / ox_inventory / qs-inventory item events
    local dupeEventHooks = {
        -- QBCore
        'QBCore:Server:AddItem',
        'QBCore:Server:RemoveItem',
        'inventory:server:GiveItem',
        'inventory:server:UsedItem',
        -- ox_inventory
        'ox_inventory:moveItem',
        'ox_inventory:swapItems',
        'ox_inventory:giveItem',
        -- qs-inventory
        'qs-inventory:server:UseItem',
        'qs-inventory:server:AddItem',
        -- Generic dupe exploit patterns
        'dupe:trigger',
        'exploit:inventory',
        'item:duplicate',
    }

    for _, eventName in ipairs(dupeEventHooks) do
        local name = eventName -- closure copy
        AddEventHandler(name, function()
            OnInventoryEvent(name)
        end)
    end

    -- ── Known dupe exploit net event signatures ───────────────────────────────
    local knownDupeEvents = {
        'dupe:bypass',
        'inv:dupe',
        'qb:dupe',
        'inventory:exploit',
    }
    for _, sig in ipairs(knownDupeEvents) do
        AddEventHandler(sig, function()
            Report('itemDupe', ('Known dupe exploit event fired: %s'):format(sig), true, {})
        end)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- MONEY DUPLICATION DETECTION
-- Triggers when the client fires money-add events suspiciously fast
-- ─────────────────────────────────────────────────────────────────────────────
if Config.Detections.moneyDupe then
    local moneyEventCount = 0
    local moneyEventTimer = GetGameTimer()

    local moneyEvents = {
        'QBCore:Server:AddMoney',
        'QBCore:Server:SetMoney',
        'banking:server:deposit',
        'banking:server:withdraw',
        'money:add',
        'money:set',
    }

    for _, eventName in ipairs(moneyEvents) do
        local name = eventName
        AddEventHandler(name, function()
            local now  = GetGameTimer()
            if (now - moneyEventTimer) > Config.Thresholds.dupeWindowMs then
                moneyEventCount = 0
                moneyEventTimer = now
            end
            moneyEventCount = moneyEventCount + 1
            if moneyEventCount >= Config.Thresholds.dupeEventMax then
                Report('moneyDupe',
                    ('Money event flooding: %d events in %dms — possible money dupe exploit'):format(
                        moneyEventCount, now - moneyEventTimer),
                    true, { eventName = name }
                )
                moneyEventCount = 0
            end
        end)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- HELPER: RotationToDirection (not a native, required for wallhack LOS check)
-- ─────────────────────────────────────────────────────────────────────────────
function RotationToDirection(rot)
    local rZ  = math.rad(rot.z)
    local rX  = math.rad(rot.x)
    local absX = math.abs(math.cos(rX))
    return vector3(
        -math.sin(rZ) * absX,
         math.cos(rZ) * absX,
         math.sin(rX)
    )
end
