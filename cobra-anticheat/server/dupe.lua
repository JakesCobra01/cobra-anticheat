-- =============================================
-- cobra-anticheat / server / dupe.lua
-- Item & Money Duplication Detection
-- Cobra Development
-- =============================================

local itemLog        = {}
local moneyLog       = {}
local whitelistActive = {}

-- ── Config locals (resolved after resource start, not at parse time) ──────────
-- Never read Config at module top-level — it may not be populated yet.
-- All Config access happens inside functions called after ResourceStart.

local ITEM_WINDOW, ITEM_MAX_QTY, MONEY_SPIKE, MIN_BALANCE

local function InitConfig()
    ITEM_WINDOW   = Config.Thresholds.dupeItemWindow
    ITEM_MAX_QTY  = Config.Thresholds.dupeItemMaxQty
    MONEY_SPIKE   = Config.Thresholds.dupeMoneySpike
    MIN_BALANCE   = Config.Economy.minBalanceToTrack
end

-- ── Whitelisted earning events ────────────────────────────────────────────────

local MONEY_WHITELIST_EVENTS = {
    'QBCore:Server:OnPaycheck',
    'esx:payday',
    'qb-banking:server:payment',
    'qb-banking:server:depositMoney',
    'cobra_paychecks:server:collectPaycheck',
    'banking:server:addMoney',
}

for _, evName in ipairs(MONEY_WHITELIST_EVENTS) do
    AddEventHandler(evName, function()
        local src = source
        if src and src ~= 0 then
            whitelistActive[src] = GetGameTimer()
        end
    end)
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function IsWhitelisted(src)
    local t = whitelistActive[src]
    if not t then return false end
    if (GetGameTimer() - t) < 3000 then return true end
    whitelistActive[src] = nil
    return false
end

local function GetQBPlayer(src)
    local ok, QBCore = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if not ok or not QBCore then return nil end
    return QBCore.Functions.GetPlayer(src)
end

local function GetPlayerBalance(src)
    local Player = GetQBPlayer(src)
    if not Player then return 0, 0 end
    return Player.Functions.GetMoney('cash') or 0,
           Player.Functions.GetMoney('bank') or 0
end

-- ── Item duplication detection ────────────────────────────────────────────────

local function TrackItemAdd(src, itemName, qty)
    if not Config.Detections.itemDupe then return end

    local watched = false
    for _, w in ipairs(Config.Economy.watchedItems) do
        if w == itemName then watched = true; break end
    end
    if not watched then return end

    itemLog[src] = itemLog[src] or {}
    itemLog[src][itemName] = itemLog[src][itemName]
        or { qty = 0, firstTime = GetGameTimer(), txns = {} }

    local entry = itemLog[src][itemName]
    local now   = GetGameTimer()

    if (now - entry.firstTime) > ITEM_WINDOW then
        entry.qty       = 0
        entry.firstTime = now
        entry.txns      = {}
    end

    entry.qty = entry.qty + qty
    entry.txns[#entry.txns + 1] = { qty = qty, time = now }

    if entry.qty >= ITEM_MAX_QTY then
        local detail = ('Item "%s" added ×%d (net +%d) within %dms — possible dupe'):format(
            itemName, #entry.txns, entry.qty, ITEM_WINDOW)

        itemLog[src][itemName] = nil
        SendSuspiciousAlert(src, 'itemDupe', detail)

        if Config.Webhooks.economy and Config.Webhooks.economy ~= 'YOUR_WEBHOOK_URL_HERE' then
            local fields = {
                { name = '👤 Player',    value = '`'..(GetPlayerName(src) or '?')..'` (ID: '..src..')', inline = true  },
                { name = '📦 Item',      value = '`'..itemName..'`',                                    inline = true  },
                { name = '🔢 Net Added', value = '`+'..entry.qty..'`',                                  inline = true  },
                { name = '🔁 Txn Count', value = '`'..#entry.txns..'`',                                 inline = true  },
                { name = '⏱ Window',     value = ITEM_WINDOW..'ms',                                     inline = true  },
                { name = '🕐 Time',      value = os.date('!%Y-%m-%d %H:%M:%S'),                         inline = false },
                { name = '🪪 License',   value = '`'..(GetPlayerIdentifierByType(src,'license') or 'N/A')..'`', inline = false },
            }
            PerformHttpRequest(Config.Webhooks.economy, function() end, 'POST',
                json.encode({
                    username = Config.ServerName .. ' | Cobra Anti-Cheat',
                    embeds   = {{ title='📦 ITEM DUPLICATION DETECTED', color=16744272,
                                  fields=fields, footer={ text='Cobra Anti-Cheat | '..Config.ServerName },
                                  timestamp=os.date('!%Y-%m-%dT%H:%M:%SZ') }}
                }),
                { ['Content-Type'] = 'application/json' })
        end

        local action = Config.AutoActions.itemDupe
        if action == 'ban' then
            BanPlayer(src, 'Auto-ban: item duplication ('..itemName..')', nil, 0)
        elseif action == 'kick' then
            KickPlayer(src, 'Auto-kick: item duplication', nil)
        end
    end
end

local function TrackItemRemove(src, itemName, qty)
    if not itemLog[src] or not itemLog[src][itemName] then return end
    itemLog[src][itemName].qty = math.max(0, itemLog[src][itemName].qty - qty)
end

-- ── Money duplication detection ───────────────────────────────────────────────

local function SnapshotBalance(src)
    if not Config.Detections.moneyDupe then return end
    local cash, bank = GetPlayerBalance(src)
    moneyLog[src] = { cash = cash, bank = bank, lastCheck = GetGameTimer() }
end

local function CheckBalanceSpike(src)
    if not Config.Detections.moneyDupe then return end
    if IsWhitelisted(src) then return end
    local prev = moneyLog[src]
    if not prev or not prev.cash then return end

    local cash, bank = GetPlayerBalance(src)
    if cash < MIN_BALANCE and bank < MIN_BALANCE then return end

    local cashDiff = cash - (prev.cash or 0)
    local bankDiff = bank - (prev.bank or 0)

    local function FlagMoney(kind, amount)
        local ids = {}
        for _, t in ipairs({ 'license', 'discord', 'steam', 'fivem', 'ip' }) do
            local v = GetPlayerIdentifierByType(src, t)
            if v then ids[#ids + 1] = '`'..v..'`' end
        end
        local detail = ('£%s spike of £%s (prev: £%s → now: £%s)'):format(
            kind, tostring(amount),
            tostring(prev[kind:lower()] or 0),
            tostring(kind == 'Cash' and cash or bank))

        SendSuspiciousAlert(src, 'moneyDupe', detail)

        if Config.Webhooks.economy and Config.Webhooks.economy ~= 'YOUR_WEBHOOK_URL_HERE' then
            local fields = {
                { name='👤 Player',   value='`'..(GetPlayerName(src) or '?')..'` (ID: '..src..')', inline=true  },
                { name='💰 Type',     value=kind,                    inline=true  },
                { name='📈 Spike',    value='£'..tostring(amount),   inline=true  },
                { name='🏦 Cash Now', value='£'..tostring(cash),     inline=true  },
                { name='🏦 Bank Now', value='£'..tostring(bank),     inline=true  },
                { name='🕐 Time',     value=os.date('!%Y-%m-%d %H:%M:%S'), inline=false },
                { name='🪪 IDs',      value=table.concat(ids, '\n'), inline=false },
            }
            PerformHttpRequest(Config.Webhooks.economy, function() end, 'POST',
                json.encode({
                    username = Config.ServerName .. ' | Cobra Anti-Cheat',
                    embeds   = {{ title='💰 MONEY DUPLICATION DETECTED', color=15158332,
                                  fields=fields, footer={ text='Cobra Anti-Cheat | '..Config.ServerName },
                                  timestamp=os.date('!%Y-%m-%dT%H:%M:%SZ') }}
                }),
                { ['Content-Type'] = 'application/json' })
        end

        local action = Config.AutoActions.moneyDupe
        if action == 'ban' then
            BanPlayer(src, 'Auto-ban: money duplication (£'..tostring(amount)..' '..kind..')', nil, 0)
        elseif action == 'kick' then
            KickPlayer(src, 'Auto-kick: money duplication', nil)
        end
    end

    if cashDiff > Config.Economy.cashSpikeThreshold then FlagMoney('Cash', cashDiff) end
    if bankDiff > Config.Economy.bankSpikeThreshold then FlagMoney('Bank', bankDiff) end

    moneyLog[src].cash = cash
    moneyLog[src].bank = bank
end

-- ── Inventory event hooks ─────────────────────────────────────────────────────

AddEventHandler('QBCore:Server:AddItem',    function(src, n, q) TrackItemAdd(src, n, q) end)
AddEventHandler('QBCore:Server:RemoveItem', function(src, n, q) TrackItemRemove(src, n, q) end)

AddEventHandler('ox_inventory:itemAdded', function(inv, slot, item, amount)
    local src = tonumber(inv)
    if src and src > 0 then TrackItemAdd(src, item, amount or 1) end
end)
AddEventHandler('ox_inventory:itemRemoved', function(inv, slot, item, amount)
    local src = tonumber(inv)
    if src and src > 0 then TrackItemRemove(src, item, amount or 1) end
end)

-- ── Periodic balance polling ──────────────────────────────────────────────────

CreateThread(function()
    while true do
        Wait(10000)
        for _, rawSrc in ipairs(GetPlayers()) do
            local src = tonumber(rawSrc)
            if src then
                if not moneyLog[src] then SnapshotBalance(src)
                else CheckBalanceSpike(src) end
            end
        end
    end
end)

AddEventHandler('playerJoining', function()
    local src = source
    SetTimeout(3000, function() SnapshotBalance(src) end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    itemLog[src]  = nil
    moneyLog[src] = nil
end)

-- ── Init — deferred until after resource fully starts ─────────────────────────
-- This guarantees Config is populated before we cache its values.

AddEventHandler('onServerResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    InitConfig()
    print('[cobra-anticheat] dupe.lua initialised.')
end)
