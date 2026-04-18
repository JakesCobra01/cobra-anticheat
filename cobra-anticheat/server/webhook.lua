-- =============================================
-- cobra-anticheat / server / webhook.lua
-- Discord webhook sender
--
-- Key design: screenshots are embedded INSIDE the detection embed
-- (using Discord's image field) rather than sent as separate messages.
-- This means each alert is a single compact card with the screenshot
-- visible immediately beneath the fields — no second message needed.
--
-- Cobra Development
-- =============================================

local cooldowns       = {}  -- [src_detType] = gameTimer
local ssScreenCooldown = {} -- [src] = gameTimer  (per-player screenshot throttle)

-- ── Low-level sender ──────────────────────────────────────────────────────────

---@param webhook string
---@param payload table
local function SendWebhook(webhook, payload)
    if not webhook or webhook == '' or webhook == 'YOUR_WEBHOOK_URL_HERE' then return end
    PerformHttpRequest(webhook, function() end, 'POST',
        json.encode(payload),
        { ['Content-Type'] = 'application/json' }
    )
end

---@param webhook string
---@param embed   table
local function SendEmbed(webhook, embed)
    SendWebhook(webhook, {
        username   = Config.ServerName .. ' | Cobra Anti-Cheat',
        avatar_url = '',
        embeds     = { embed },
    })
end

-- ── Cooldown helpers ──────────────────────────────────────────────────────────

local function CheckCooldown(src, detType, ms)
    local key = tostring(src) .. '_' .. detType
    local now = GetGameTimer()
    if cooldowns[key] and (now - cooldowns[key]) < ms then return false end
    cooldowns[key] = now
    return true
end

local function CheckSsCooldown(src)
    local now = GetGameTimer()
    local cd  = Config.Screenshots.cooldown or 30000
    if ssScreenCooldown[src] and (now - ssScreenCooldown[src]) < cd then return false end
    ssScreenCooldown[src] = now
    return true
end

-- ── QBCore job helper ─────────────────────────────────────────────────────────

local function GetPlayerJob(src)
    local ok, QBCore = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if not ok or not QBCore then return 'N/A', 'N/A' end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return 'N/A', 'N/A' end
    local job = Player.PlayerData.job
    return (job and job.name or 'N/A'), (job and job.label or 'N/A')
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function CoordMapLink(x, y, z)
    return ('https://www.gta5-map.com/?lat=%.0f&lng=%.0f'):format(y * -1, x)
end

local function SessionDuration(joinTime)
    if not joinTime then return 'N/A' end
    local s = os.time() - joinTime
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    local sc = s % 60
    if h > 0 then return ('%dh %dm %ds'):format(h, m, sc) end
    if m > 0 then return ('%dm %ds'):format(m, sc) end
    return ('%ds'):format(sc)
end

local function GetFlagSummary(src)
    local counts = flagCounts and flagCounts[src] or {}
    if not next(counts) then return '`None`' end
    local lines = {}; local total = 0
    for k, v in pairs(counts) do
        lines[#lines + 1] = ('`%-22s` ×%d'):format(k, v)
        total = total + v
    end
    table.sort(lines)
    return table.concat(lines, '\n') .. ('\n**Total flags: %d**'):format(total)
end

local WEAPON_LABELS = {
    [GetHashKey('WEAPON_PISTOL')]        = 'Pistol',
    [GetHashKey('WEAPON_COMBATPISTOL')]  = 'Combat Pistol',
    [GetHashKey('WEAPON_SMG')]           = 'SMG',
    [GetHashKey('WEAPON_ASSAULTRIFLE')] = 'Assault Rifle',
    [GetHashKey('WEAPON_SNIPERRIFLE')]  = 'Sniper Rifle',
    [GetHashKey('WEAPON_HEAVYSNIPER')] = 'Heavy Sniper',
    [GetHashKey('WEAPON_MINIGUN')]      = 'Minigun',
    [GetHashKey('WEAPON_RPG')]          = 'RPG',
    [GetHashKey('WEAPON_KNIFE')]        = 'Knife',
    [GetHashKey('WEAPON_UNARMED')]      = 'Unarmed',
}
local function WeaponName(hash)
    if not hash or hash == 0 then return 'Unarmed' end
    return WEAPON_LABELS[hash] or ('Hash:0x%08X'):format(hash)
end

local function VehicleInfo(src)
    local ped = GetPlayerPed(src)
    if not IsPedInAnyVehicle(ped, false) then return 'On Foot' end
    local veh   = GetVehiclePedIsIn(ped, false)
    local model = GetEntityModel(veh)
    local speed = math.floor(GetEntitySpeed(veh) * 3.6) -- km/h
    return ('Model: `0x%08X` | Speed: `%d km/h`'):format(model, speed)
end

local function OnlineAdmins()
    local c = 0
    for _, s in ipairs(GetPlayers()) do
        if IsACAdmin(tonumber(s)) then c = c + 1 end
    end
    return c
end

-- ── Rich player field builder ─────────────────────────────────────────────────
-- Returns the full field array used in all detection embeds.

local function BuildRichFields(src, joinTime)
    local name    = GetPlayerName(src) or 'Unknown'
    local ping    = GetPlayerPing(src)
    local ped     = GetPlayerPed(src)
    local coords  = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local health  = math.max(0, GetEntityHealth(ped) - 100)
    local armour  = GetPedArmour(ped)
    local weapon  = GetSelectedPedWeapon(ped)
    local online  = #GetPlayers()
    local jobName, jobLabel = GetPlayerJob(src)

    local idents = {}
    for _, t in ipairs({ 'license', 'license2', 'steam', 'discord', 'fivem', 'xbl', 'live', 'ip' }) do
        local v = GetPlayerIdentifierByType(src, t)
        if v then idents[#idents + 1] = '`' .. v .. '`' end
    end

    local mapLink = CoordMapLink(coords.x, coords.y, coords.z)

    return {
        { name = '👤 Player',          value = '`' .. name .. '`',                                     inline = true  },
        { name = '🆔 Server ID',       value = '`' .. src .. '`',                                      inline = true  },
        { name = '📶 Ping',            value = '`' .. ping .. 'ms`',                                   inline = true  },
        { name = '❤️ Health',         value = '`' .. health .. '/100`',                               inline = true  },
        { name = '🛡️ Armour',        value = '`' .. armour .. '/100`',                               inline = true  },
        { name = '🔫 Weapon',          value = '`' .. WeaponName(weapon) .. '`',                       inline = true  },
        { name = '📍 Coordinates',     value = ('`%.2f, %.2f, %.2f`'):format(coords.x, coords.y, coords.z), inline = true  },
        { name = '🧭 Heading',         value = ('`%.1f°`'):format(heading),                            inline = true  },
        { name = '🚗 Vehicle',         value = VehicleInfo(src),                                        inline = true  },
        { name = '⏱️ Session',        value = SessionDuration(joinTime),                              inline = true  },
        { name = '🌐 Population',      value = ('`%d online`'):format(online),                         inline = true  },
        { name = '👮 Admins Online',   value = ('`%d admin(s)`'):format(OnlineAdmins()),               inline = true  },
        { name = '💼 Job',             value = ('`%s` (%s)'):format(jobName, jobLabel),                inline = true  },
        { name = '🗺️ Map',           value = ('[View Location](%s)'):format(mapLink),                 inline = true  },
        { name = '\u{200B}',           value = '\u{200B}',                                              inline = true  },
        { name = '🪪 Identifiers',    value = table.concat(idents, '\n'),                              inline = false },
        { name = '⚑ Prior Flags',     value = GetFlagSummary(src),                                     inline = false },
    }
end

-- ── Screenshot-inside-embed ───────────────────────────────────────────────────
-- Takes a screenshot and CALLS the provided callback with the URL (or nil).
-- The caller then attaches it as embed.image.url before sending — one message.
--
-- If screenshot-basic is not installed or disabled, callback is called with nil
-- and the embed is sent without an image (graceful degradation).

---@param src      number
---@param callback fun(url: string|nil)
local function CaptureScreenshot(src, callback)
    if not Config.Screenshots.enabled then callback(nil); return end
    if GetResourceState('screenshot-basic') ~= 'started' then
        print('[cobra-anticheat] screenshot-basic not running — embed will have no image.')
        callback(nil)
        return
    end
    if not CheckSsCooldown(src) then callback(nil); return end

    exports['screenshot-basic']:requestClientScreenshot(src, {
        encoding = Config.Screenshots.encoding or 'jpg',
        quality  = Config.Screenshots.quality  or 0.90,
    }, function(err, url)
        if err or not url then
            print(('[cobra-anticheat] Screenshot error (SrvID %d): %s'):format(src, tostring(err)))
            callback(nil)
        else
            callback(url)
        end
    end)
end

-- ── Public alert functions ────────────────────────────────────────────────────

--- BLATANT detection alert — screenshot baked into same embed
function SendBlatantAlert(src, detType, detail, extraData)
    if not CheckCooldown(src, detType, 20000) then return end

    local joinTime = playerData and playerData[src] and playerData[src].joinTime or nil
    local fields   = BuildRichFields(src, joinTime)

    fields[#fields + 1] = { name = '🚨 Detection',     value = ('`%s`'):format(detType),  inline = true  }
    fields[#fields + 1] = { name = '📋 Detail',         value = detail or 'N/A',            inline = false }

    if extraData and next(extraData) then
        local lines = {}
        for k, v in pairs(extraData) do
            lines[#lines + 1] = ('**%s**: `%s`'):format(k, type(v)=='table' and json.encode(v) or tostring(v))
        end
        if #lines > 0 then
            fields[#fields + 1] = { name = '🔬 Technical Data', value = table.concat(lines, '\n'), inline = false }
        end
    end

    fields[#fields + 1] = { name = '🕐 Detected (UTC)', value = os.date('!%Y-%m-%d %H:%M:%S'), inline = false }

    -- Take screenshot FIRST, then build+send the embed with image attached
    CaptureScreenshot(src, function(imageUrl)
        local embed = {
            title       = '🚨 BLATANT CHEAT — ' .. detType:upper(),
            description = ('Player **%s** (SrvID: **%d**) flagged for blatant cheating.'):format(
                GetPlayerName(src) or 'Unknown', src),
            color       = Config.Colors.blatant,
            fields      = fields,
            footer      = { text = ('Cobra Anti-Cheat | %s'):format(Config.ServerName) },
            timestamp   = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        }
        -- Attach screenshot directly in embed if we got one
        if imageUrl then
            embed.image = { url = imageUrl }
            fields[#fields + 1] = { name = '📸 Screenshot', value = '_Captured at moment of detection_', inline = false }
        end

        SendEmbed(Config.Webhooks.main,    embed)
        SendEmbed(Config.Webhooks.blatant, embed)
    end)
end

--- SUSPICIOUS behaviour alert — screenshot embedded after flag threshold
function SendSuspiciousAlert(src, detType, detail, extraData)
    if not CheckCooldown(src, detType, 30000) then return end

    local joinTime = playerData and playerData[src] and playerData[src].joinTime or nil
    local fields   = BuildRichFields(src, joinTime)

    fields[#fields + 1] = { name = '🔍 Detection',     value = ('`%s`'):format(detType),  inline = true  }
    fields[#fields + 1] = { name = '📋 Detail',         value = detail or 'N/A',            inline = false }

    if extraData and next(extraData) then
        local lines = {}
        for k, v in pairs(extraData) do
            lines[#lines + 1] = ('**%s**: `%s`'):format(k, type(v)=='table' and json.encode(v) or tostring(v))
        end
        if #lines > 0 then
            fields[#fields + 1] = { name = '🔬 Technical Data', value = table.concat(lines, '\n'), inline = false }
        end
    end

    fields[#fields + 1] = { name = '🕐 Detected (UTC)', value = os.date('!%Y-%m-%d %H:%M:%S'), inline = false }

    -- Only screenshot once flags reach the threshold
    local totalFlags = 0
    if flagCounts and flagCounts[src] then
        for _, v in pairs(flagCounts[src]) do totalFlags = totalFlags + v end
    end
    local wantScreenshot = totalFlags >= (Config.Screenshots.suspiciousFlagThreshold or 3)

    local function SendIt(imageUrl)
        local embed = {
            title       = '⚠️ SUSPICIOUS BEHAVIOUR — ' .. detType:upper(),
            description = ('Player **%s** (SrvID: **%d**) exhibiting suspicious behaviour.'):format(
                GetPlayerName(src) or 'Unknown', src),
            color       = Config.Colors.suspicious,
            fields      = fields,
            footer      = { text = ('Cobra Anti-Cheat | %s'):format(Config.ServerName) },
            timestamp   = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        }
        if imageUrl then
            embed.image = { url = imageUrl }
            fields[#fields + 1] = { name = '📸 Screenshot', value = '_Captured at moment of detection_', inline = false }
        end
        SendEmbed(Config.Webhooks.main,       embed)
        SendEmbed(Config.Webhooks.suspicious, embed)
    end

    if wantScreenshot then
        CaptureScreenshot(src, SendIt)
    else
        SendIt(nil)
    end
end

--- BAN alert — screenshot baked in
function SendBanAlert(src, reason, adminName, duration)
    local joinTime = playerData and playerData[src] and playerData[src].joinTime or nil
    local fields   = BuildRichFields(src, joinTime)
    local durStr   = (not duration or duration == 0) and '**Permanent**' or (duration .. ' minutes')
    fields[#fields + 1] = { name = '🔨 Reason',    value = reason,                           inline = false }
    fields[#fields + 1] = { name = '📅 Duration',  value = durStr,                           inline = true  }
    fields[#fields + 1] = { name = '👮 Issued By', value = adminName or 'Cobra Anti-Cheat', inline = true  }
    fields[#fields + 1] = { name = '🕐 Time (UTC)',value = os.date('!%Y-%m-%d %H:%M:%S'),   inline = true  }

    CaptureScreenshot(src, function(imageUrl)
        local embed = {
            title       = '🔨 PLAYER BANNED',
            description = ('**%s** (SrvID: %d) has been banned.'):format(GetPlayerName(src) or 'Unknown', src),
            color       = Config.Colors.ban,
            fields      = fields,
            footer      = { text = ('Cobra Anti-Cheat | %s'):format(Config.ServerName) },
            timestamp   = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        }
        if imageUrl then embed.image = { url = imageUrl } end
        SendEmbed(Config.Webhooks.main, embed)
        SendEmbed(Config.Webhooks.bans, embed)
    end)
end

--- KICK alert
function SendKickAlert(src, reason, adminName)
    if not Config.Webhooks.bans or Config.Webhooks.bans == 'YOUR_WEBHOOK_URL_HERE' then return end
    local name = GetPlayerName(src) or 'Unknown'
    local embed = {
        title     = '👢 PLAYER KICKED',
        color     = Config.Colors.suspicious,
        fields    = {
            { name = '👤 Player',  value = '`' .. name .. '` (ID: ' .. src .. ')', inline = true  },
            { name = '📋 Reason', value = reason,                                   inline = true  },
            { name = '👮 By',     value = adminName or 'System',                   inline = true  },
            { name = '🕐 Time',   value = os.date('!%Y-%m-%d %H:%M:%S'),          inline = false },
        },
        footer    = { text = ('Cobra Anti-Cheat | %s'):format(Config.ServerName) },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    }
    SendEmbed(Config.Webhooks.bans, embed)
end

--- UNBAN alert
function SendUnbanAlert(adminSrc, targetIdentifier)
    local adminName = (adminSrc and adminSrc ~= 0 and GetPlayerName(adminSrc)) or 'System'
    local embed = {
        title     = '✅ Player Unbanned',
        color     = Config.Colors.unban,
        fields    = {
            { name = '🪪 Identifier',  value = '`' .. targetIdentifier .. '`', inline = true  },
            { name = '👮 Unbanned By', value = '`' .. adminName .. '`',         inline = true  },
            { name = '🕐 Time (UTC)', value = os.date('!%Y-%m-%d %H:%M:%S'),  inline = false },
        },
        footer    = { text = ('Cobra Anti-Cheat | %s'):format(Config.ServerName) },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    }
    SendEmbed(Config.Webhooks.bans,     embed)
    SendEmbed(Config.Webhooks.adminlog, embed)
end

--- ADMIN ACTION alert
function SendAdminAlert(adminSrc, action, targetSrc, detail)
    local adminName = (adminSrc and adminSrc ~= 0 and GetPlayerName(adminSrc)) or 'System'
    local adminIds  = {}
    if adminSrc and adminSrc ~= 0 then
        for _, t in ipairs({ 'license', 'discord', 'steam', 'fivem' }) do
            local v = GetPlayerIdentifierByType(adminSrc, t)
            if v then adminIds[#adminIds + 1] = '`' .. v .. '`' end
        end
    end

    local fields = {
        { name = '👮 Admin',     value = ('`%s` (SrvID: %s)'):format(adminName, tostring(adminSrc or 'N/A')), inline = true  },
        { name = '⚡ Action',    value = ('`%s`'):format(action),                                              inline = true  },
        { name = '🕐 Time UTC', value = os.date('!%Y-%m-%d %H:%M:%S'),                                       inline = true  },
    }
    if #adminIds > 0 then
        fields[#fields + 1] = { name = '🪪 Admin IDs', value = table.concat(adminIds, '\n'), inline = false }
    end
    if targetSrc and GetPlayerName(targetSrc) then
        local tname   = GetPlayerName(targetSrc)
        local tcoords = GetEntityCoords(GetPlayerPed(targetSrc))
        local tids    = {}
        for _, t in ipairs({ 'license', 'discord', 'steam' }) do
            local v = GetPlayerIdentifierByType(targetSrc, t)
            if v then tids[#tids + 1] = '`' .. v .. '`' end
        end
        fields[#fields + 1] = { name = '🎯 Target',     value = ('`%s` (SrvID: %d)'):format(tname, targetSrc), inline = true  }
        fields[#fields + 1] = { name = '📍 Target Pos', value = ('`%.1f, %.1f, %.1f`'):format(tcoords.x, tcoords.y, tcoords.z), inline = true }
        fields[#fields + 1] = { name = '📶 Ping',       value = ('`%dms`'):format(GetPlayerPing(targetSrc)),  inline = true  }
        if #tids > 0 then
            fields[#fields + 1] = { name = '🪪 Target IDs', value = table.concat(tids, '\n'), inline = false }
        end
    end
    if detail then
        fields[#fields + 1] = { name = '📋 Detail', value = detail, inline = false }
    end

    local embed = {
        title     = '🛡️ Admin Action — ' .. action,
        color     = Config.Colors.admin,
        fields    = fields,
        footer    = { text = ('Cobra Anti-Cheat | %s'):format(Config.ServerName) },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    }
    SendEmbed(Config.Webhooks.admin,    embed)
    SendEmbed(Config.Webhooks.adminlog, embed)
    if LogAdminAction then
        LogAdminAction(adminSrc, action, targetSrc, detail, 'panel')
    end
end

--- Manual admin screenshot — baked into one embed
function SendAdminScreenshot(adminSrc, targetSrc)
    if GetResourceState('screenshot-basic') ~= 'started' then
        TriggerClientEvent('cobra_ac:notify', adminSrc, 'screenshot-basic resource not found.', 'error')
        return
    end
    local adminName  = GetPlayerName(adminSrc)  or 'Unknown Admin'
    local targetName = GetPlayerName(targetSrc) or 'Unknown'

    exports['screenshot-basic']:requestClientScreenshot(targetSrc, {
        encoding = Config.Screenshots.encoding or 'jpg',
        quality  = Config.Screenshots.quality  or 0.90,
    }, function(err, url)
        if err or not url then
            TriggerClientEvent('cobra_ac:notify', adminSrc, 'Screenshot failed: ' .. tostring(err), 'error')
            return
        end

        local tped    = GetPlayerPed(targetSrc)
        local tcoords = GetEntityCoords(tped)
        local tids    = {}
        for _, t in ipairs({ 'license', 'discord', 'steam', 'fivem', 'ip' }) do
            local v = GetPlayerIdentifierByType(targetSrc, t)
            if v then tids[#tids + 1] = '`' .. v .. '`' end
        end

        local embed = {
            title       = '📸 Admin Screenshot',
            description = ('**%s** captured **%s** (SrvID: %d)'):format(adminName, targetName, targetSrc),
            color       = Config.Colors.admin,
            image       = { url = url },
            fields      = {
                { name = '👮 Admin',      value = ('`%s` (SrvID: %d)'):format(adminName, adminSrc),   inline = true  },
                { name = '🎯 Target',     value = ('`%s` (SrvID: %d)'):format(targetName, targetSrc), inline = true  },
                { name = '🕐 Time (UTC)',value = os.date('!%Y-%m-%d %H:%M:%S'),                      inline = true  },
                { name = '📍 Coords',    value = ('`%.1f, %.1f, %.1f`'):format(tcoords.x, tcoords.y, tcoords.z), inline = false },
                { name = '🪪 IDs',       value = table.concat(tids, '\n'),                             inline = false },
                { name = '⚑ Flags',      value = GetFlagSummary(targetSrc),                           inline = false },
            },
            footer    = { text = ('Cobra Anti-Cheat | %s'):format(Config.ServerName) },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        }
        SendEmbed(Config.Webhooks.admin,    embed)
        SendEmbed(Config.Webhooks.adminlog, embed)

        TriggerClientEvent('cobra_ac:notify', adminSrc, 'Screenshot sent to Discord ✓', 'success')
        LogAdminAction(adminSrc, 'SCREENSHOT', targetSrc, 'Manual admin screenshot', 'panel')
    end)
end
