-- =============================================
-- cobra-anticheat / server / bans.lua
-- Ban & kick enforcement — txAdmin or fallback bans.json
-- Cobra Development
--
-- FiveM note: Config is a shared global populated by config.lua.
-- Do NOT read Config at module top-level (outside a function).
-- All Config access here is inside functions called after resource start.
-- =============================================

-- ── Identifier helpers ────────────────────────────────────────────────────────

function GetAllIdentifiers(src)
    local ids = {}
    for _, t in ipairs({ 'license', 'license2', 'steam', 'discord', 'fivem', 'xbl', 'live', 'ip' }) do
        local v = GetPlayerIdentifierByType(src, t)
        if v then ids[#ids + 1] = v end
    end
    return ids
end

function GetPrimaryIdentifier(src)
    return GetPlayerIdentifierByType(src, 'license')
        or GetPlayerIdentifierByType(src, 'license2')
        or GetPlayerIdentifierByType(src, 'steam')
        or GetPlayerIdentifierByType(src, 'fivem')
end

-- ── txAdmin API wrapper ───────────────────────────────────────────────────────

local function TxCall(fn, data)
    if GetResourceState('monitor') ~= 'started' then
        print(('[cobra-anticheat] WARNING: txAdmin monitor not running — cannot call %s'):format(fn))
        return nil
    end
    local ok, result = pcall(function()
        return exports['monitor'][fn](exports['monitor'], data)
    end)
    if not ok then
        print(('[cobra-anticheat] txAdmin export "%s" error: %s'):format(fn, tostring(result)))
        return nil
    end
    return result
end

local function PrefixReason(reason)
    return Config.TxAdmin.reasonPrefix .. reason
end

local function MinutesToISO(minutes)
    if not minutes or minutes <= 0 then return nil end
    if minutes < 1440 then return 'PT' .. minutes .. 'M' end
    local days = math.floor(minutes / 1440)
    local rem  = minutes % 1440
    return rem == 0 and ('P' .. days .. 'D') or ('P' .. days .. 'DT' .. rem .. 'M')
end

-- ── txAdmin actions ───────────────────────────────────────────────────────────

local function TxBan(src, reason, adminName, duration)
    local ids = GetAllIdentifiers(src)
    if #ids == 0 then
        print('[cobra-anticheat] TxBan: no identifiers for source ' .. src); return
    end
    TxCall('banPlayer', {
        author      = adminName,
        reason      = PrefixReason(reason),
        identifiers = ids,
        expiration  = MinutesToISO(duration),
    })
    Wait(200)
    if GetPlayerName(src) then
        DropPlayer(src, Config.Bans.banMessage .. '\nReason: ' .. reason)
    end
end

local function TxKick(src, reason, adminName)
    TxCall('kickPlayer', {
        author = adminName,
        reason = PrefixReason(reason),
        ids    = { tostring(src) },
    })
end

local function TxUnban(identifier, adminName)
    local result = TxCall('unbanPlayer', { author = adminName, identifier = identifier })
    return result ~= nil
end

-- ── Fallback bans.json ────────────────────────────────────────────────────────

local localBans = {}

local function LoadLocalBans()
    local raw = LoadResourceFile(GetCurrentResourceName(), 'bans.json')
    if raw and raw ~= '' then
        local ok, data = pcall(json.decode, raw)
        if ok and data then
            localBans = data
            local c = 0; for _ in pairs(localBans) do c = c + 1 end
            print('[cobra-anticheat] Fallback mode: loaded ' .. c .. ' bans.')
        end
    end
end

local function SaveLocalBans()
    local ok, enc = pcall(json.encode, localBans)
    if ok then SaveResourceFile(GetCurrentResourceName(), 'bans.json', enc, -1) end
end

local function LocalBan(src, reason, adminName, duration)
    local ids     = GetAllIdentifiers(src)
    local expires = (duration and duration > 0) and (os.time() + duration * 60) or 0
    local entry   = { reason=reason, adminName=adminName, expires=expires,
                      timestamp=os.time(), playerName=GetPlayerName(src) or 'Unknown' }
    for _, id in ipairs(ids) do localBans[id] = entry end
    SaveLocalBans()
    DropPlayer(src, Config.Bans.banMessage .. '\nReason: ' .. reason)
end

local function LocalUnban(identifier)
    if localBans[identifier] then
        localBans[identifier] = nil; SaveLocalBans(); return true
    end
    return false
end

-- ── playerConnecting hook (fallback only) ─────────────────────────────────────
-- Registered inside onServerResourceStart so Config is guaranteed to exist.

local function RegisterConnectingHook()
    AddEventHandler('playerConnecting', function(_, _, deferrals)
        local src = source
        deferrals.defer()
        Wait(0)
        local now = os.time()
        for _, id in ipairs(GetAllIdentifiers(src)) do
            local b = localBans[id]
            if b then
                if b.expires == 0 or b.expires > now then
                    deferrals.done(
                        ('[Cobra AC] You are banned.\nReason: %s\nDuration: %s\nAppeal: discord.gg/yourserver')
                        :format(b.reason, b.expires == 0 and 'Permanent'
                            or ('Expires: ' .. os.date('%Y-%m-%d %H:%M', b.expires)))
                    )
                    return
                else
                    localBans[id] = nil; SaveLocalBans()
                end
            end
        end
        deferrals.done()
    end)
end

-- ── Init — deferred to guarantee Config is available ─────────────────────────

AddEventHandler('onServerResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if Config.TxAdmin.enabled then
        print('[cobra-anticheat] txAdmin integration enabled — bans route through txAdmin monitor.')
    else
        LoadLocalBans()
        RegisterConnectingHook()
        print('[cobra-anticheat] Fallback ban mode active — using local bans.json.')
    end
end)

-- ── Public API ────────────────────────────────────────────────────────────────

function BanPlayer(src, reason, adminSrc, duration)
    local adminName = (adminSrc and adminSrc ~= 0 and GetPlayerName(adminSrc))
        or Config.TxAdmin.autoAuthor
    SendBanAlert(src, reason, adminName, duration)
    if Config.TxAdmin.enabled then
        TxBan(src, reason, adminName, duration)
    else
        LocalBan(src, reason, adminName, duration)
    end
end

function KickPlayer(src, reason, adminSrc)
    local adminName = (adminSrc and adminSrc ~= 0 and GetPlayerName(adminSrc))
        or Config.TxAdmin.autoAuthor
    SendAdminAlert(adminSrc or 0, 'KICK', src, reason)
    if Config.TxAdmin.enabled then
        TxKick(src, reason, adminName)
    else
        DropPlayer(src, Config.Bans.kickMessage .. '\nReason: ' .. reason)
    end
end

function UnbanPlayer(identifier, adminSrc)
    local adminName = (adminSrc and adminSrc ~= 0 and GetPlayerName(adminSrc)) or 'Admin'
    SendUnbanAlert(adminSrc, identifier)
    if Config.TxAdmin.enabled then
        local ok = TxUnban(identifier, adminName)
        if not ok then
            print('[cobra-anticheat] TxUnban returned nil for: ' .. identifier)
        end
        return ok
    else
        return LocalUnban(identifier)
    end
end
