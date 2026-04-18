Config = {}

-- =============================================
-- DISCORD WEBHOOKS
-- =============================================
Config.Webhooks = {
    -- All detection alerts (mirrors blatant + suspicious)
    main        = 'YOUR_WEBHOOK_URL_HERE',
    -- Blatant cheats only (aimbot, god mode, cheat menus, etc.)
    blatant     = 'YOUR_WEBHOOK_URL_HERE',
    -- Suspicious behaviour only (speed, teleport, coord bounce, etc.)
    suspicious  = 'YOUR_WEBHOOK_URL_HERE',
    -- Bans and kicks
    bans        = 'YOUR_WEBHOOK_URL_HERE',
    -- Admin actions from our panel/commands
    admin       = 'YOUR_WEBHOOK_URL_HERE',
    -- DEDICATED admin audit log (ALL admin actions incl. txAdmin web panel)
    adminlog    = 'YOUR_WEBHOOK_URL_HERE',
    -- Item and money duplication alerts
    economy        = 'YOUR_WEBHOOK_URL_HERE',
    -- General (non-AC) admin actions: QBCore admin cmds, txAdmin routine actions
    -- Recommended: separate private channel so staff can review day-to-day usage
    generaladmin   = 'YOUR_WEBHOOK_URL_HERE',
}

-- Discord embed colour codes (decimal)
Config.Colors = {
    blatant    = 15158332,  -- Red
    suspicious = 16744272,  -- Orange
    info       = 3447003,   -- Blue
    ban        = 10038562,  -- Dark Red
    unban      = 3066993,   -- Green
    admin      = 9807270,   -- Grey
}

Config.ServerName = 'Paradise Island'  -- ← Change this to your server name. Shown in all Discord embeds.

-- =============================================
-- ADMIN PERMISSIONS
-- =============================================
-- Ace permission: add_principal identifier.license:xxxx group.anticheat
Config.AcePermission = 'anticheat.admin'

-- Custom admins by license identifier (fallback if no ace perms)
Config.CustomAdmins = {
    'license:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX',
    'license:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX',
}

-- Permission tiers for UI actions
Config.Permissions = {
    -- Can view the panel
    view       = 'anticheat.view',
    -- Can kick players
    kick       = 'anticheat.kick',
    -- Can ban players
    ban        = 'anticheat.ban',
    -- Can unban players
    unban      = 'anticheat.unban',
    -- Can freeze/spectate/teleport
    moderate   = 'anticheat.moderate',
    -- Can change config at runtime
    superadmin  = 'anticheat.superadmin',
}

-- =============================================
-- DETECTION TOGGLES
-- =============================================
Config.Detections = {
    -- ── Blatant ──
    godMode             = true,   -- Detect invincibility flag
    explosionSpam       = true,   -- Too many explosions in short time
    weaponSpawn         = true,   -- Spawning weapons not in whitelist
    vehicleSpawn        = true,   -- Spawning vehicles flagged
    infiniteAmmo        = true,   -- Ammo never decreases
    superJump           = true,   -- Unrealistic jump height
    invisibility        = true,   -- Player alpha check
    noClip              = true,   -- Detect noclip movement
    resourceInjection   = true,   -- Unknown resources starting
    entitySpam          = true,   -- Creating excessive entities
    blacklistedWeapons  = true,   -- RPG/minigun/etc in non-whitelisted jobs
    playerBlips         = true,   -- Forced blips on all players
    menuDetection       = true,   -- Known cheat menu exports/events

    -- ── Suspicious ──
    speedHack           = true,   -- Vehicle/foot speed exceeding thresholds
    teleport            = true,   -- Sudden position change
    rapidFire           = true,   -- Fire rate exceeding weapon max
    healthRegen         = true,   -- Health jumping up rapidly
    armourRegen         = true,   -- Armour jumping up rapidly
    vehicleGodMode      = true,   -- Vehicle health not decreasing
    spectateAbuse       = true,   -- Spectating others via native
    coordBounce         = true,   -- Position bouncing erratically
    nightVision         = true,   -- Toggling night vision suspiciously
    thermalVision       = true,   -- Toggling thermal vision suspiciously
    fallingDamage       = true,   -- No fall damage taken

    -- ── Aimbot ──
    aimbot              = true,   -- Snap angle / lock-on variance / headshot-rate heuristics
    aimbotLockOn        = true,   -- Native lock-on beyond normal range or through walls

    -- ── Wallhack ──
    wallhack            = true,   -- Shooting or aiming through solid geometry with no LoS

    -- ── Economy / Duplication ──
    itemDupe            = true,   -- Rapid identical item additions flagged server-side
    moneyDupe           = true,   -- Cash/bank balance spikes inconsistent with earnings
}

-- =============================================
-- THRESHOLDS
-- =============================================
Config.Thresholds = {

    -- ── General movement ─────────────────────────────────────────────
    -- Max on-foot speed before speed hack fires (m/s)
    footSpeedMax           = 12.0,
    -- Max vehicle speed before speed hack fires (m/s)
    -- Raise this if you run supercar events (e.g. 120.0)
    vehicleSpeedMax        = 95.0,
    -- Teleport: position jump distance in one 500ms poll tick (units)
    teleportDistance       = 250.0,
    -- Super jump: max upward velocity (m/s) for a legitimate jump
    superJumpVelocity      = 12.0,
    -- NoClip: consecutive suspicious frames before flagging
    noClipFrames           = 30,

    -- ── Explosions & rapid fire ───────────────────────────────────────
    -- Max player-caused explosions before spam flag fires
    explosionMax           = 5,
    -- Time window for explosion spam (ms)
    explosionInterval      = 3000,
    -- Max shots per second before rapid-fire flag fires
    rapidFireMax           = 20,

    -- ── Health / armour ──────────────────────────────────────────────
    -- Max HP gained per poll interval before regen flag fires
    healthRegenMax         = 10,

    -- ── Entities ─────────────────────────────────────────────────────
    -- Max entities a player may create per second
    entitySpamMax          = 10,

    -- ── Aimbot ───────────────────────────────────────────────────────
    -- Degrees/frame camera snap that is considered humanly impossible
    -- while actively aiming. Lower = more sensitive (try 60-90).
    aimbotSnapDeg          = 75.0,
    -- How many consecutive snap frames needed before flagging
    aimbotSnapFrames       = 3,
    -- Heading variance threshold for lock-on tracking detection.
    -- A value below this during sustained fire = near-perfect tracking.
    -- Lower = more sensitive. Legitimate players vary ~2-5 units.
    aimbotLockVariance     = 0.08,
    -- Frame sample window for lock-on variance measurement
    aimbotSampleFrames     = 45,
    -- Minimum shots in window before headshot-rate check runs
    aimbotShotSample       = 20,
    -- Headshot rate (0.0-1.0) above which aimbot is flagged
    -- 0.85 = 85% headshots in the sample — well above human ceiling of ~40%
    aimbotHeadshotRate     = 0.85,

    -- ── Wallhack ─────────────────────────────────────────────────────
    -- Max range (metres) for LoS shooting checks
    wallhackMaxRange       = 120.0,
    -- Minimum consecutive through-wall hits before flagging
    wallhackMinHits        = 3,

    -- ── Duplication (client-side event rate) ─────────────────────────
    -- Time window for inventory event rate check (ms)
    dupeWindowMs           = 2000,
    -- Max inventory-related events in that window before flagging
    dupeEventMax           = 12,

    -- ── Duplication (server-side item tracking) ───────────────────────
    -- Window to watch net item additions of the same item (ms)
    dupeItemWindow         = 5000,
    -- Net quantity of same item added in that window before flagging
    dupeItemMaxQty         = 5,
    -- Single-transaction cash spike that triggers money dupe alert (£)
    dupeMoneySpike         = 50000,
}

-- =============================================
-- AUTO-ACTION ON DETECTION
-- =============================================
-- 'alert'   = webhook alert only (no action taken against player)
-- 'kick'    = kick via txAdmin + webhook alert
-- 'ban'     = permanent ban via txAdmin + webhook alert
--
-- !! TUNING MODE — all set to 'alert' !!
-- Monitor your Discord webhook channels for a few days to check for
-- false positives before enabling kicks/bans on any detection.
-- Once satisfied with a detection, change its value to 'kick' or 'ban'.
Config.AutoActions = {
    -- Blatant
    godMode            = 'alert',
    explosionSpam      = 'alert',
    weaponSpawn        = 'alert',
    vehicleSpawn       = 'alert',
    infiniteAmmo       = 'alert',
    superJump          = 'alert',
    invisibility       = 'alert',
    noClip             = 'alert',
    resourceInjection  = 'alert',
    entitySpam         = 'alert',
    blacklistedWeapons = 'alert',
    menuDetection      = 'alert',
    -- Suspicious
    speedHack          = 'alert',
    teleport           = 'alert',
    rapidFire          = 'alert',
    healthRegen        = 'alert',
    armourRegen        = 'alert',
    vehicleGodMode     = 'alert',
    coordBounce        = 'alert',
    nightVision        = 'alert',
    thermalVision      = 'alert',
    fallingDamage      = 'alert',
    -- Aimbot
    aimbot             = 'alert',
    aimbotLockOn       = 'alert',
    -- Wallhack
    wallhack           = 'alert',
    -- Economy / Duplication
    itemDupe           = 'alert',
    moneyDupe          = 'alert',
}

-- =============================================
-- WHITELISTS
-- =============================================

-- Jobs that are allowed blacklisted weapons (e.g. military event jobs)
Config.WeaponJobWhitelist = {
    'police',
    'ambulance',
    'mechanic',
    'army',
}

-- Weapons that flag an alert if spawned by non-whitelisted jobs
Config.BlacklistedWeapons = {
    'WEAPON_MINIGUN',
    'WEAPON_RPG',
    'WEAPON_RAILGUN',
    'WEAPON_HOMINGLAUNCHER',
    'WEAPON_GRENADELAUNCHER',
    'WEAPON_EMPLAUNCHER',
    'WEAPON_COMPACTLAUNCHER',
    'WEAPON_FIREWORK',
    'WEAPON_RAYMINIGUN',
    'WEAPON_RAYCARBINE',
    'WEAPON_RAYPISTOL',
}

-- Vehicles that are flagged if spawned outside event/admin context
Config.BlacklistedVehicles = {
    'hydra',
    'lazer',
    'b11strikeforce',
    'nokota',
    'rogue',
    'pyro',
    'molotok',
    'besra',
    'rhino',
    'halftrack',
    'apc',
    'insurgent',
    'technical',
}

-- Resources that are allowed to start dynamically (add yours here)
Config.AllowedResources = {
    'cobra-anticheat',   -- Always keep this resource whitelisted
    'mapmanager',
    'spawnmanager',
    'sessionmanager',
}

-- =============================================
-- KNOWN CHEAT MENU SIGNATURES
-- =============================================
-- These are known exported events / net events used by public cheat menus
Config.CheatSignatures = {
    -- Eulen
    '__cfx_export_Eulen_Whitelist_isWhitelisted',
    -- Lynx
    'lynx:init',
    'lynx:trigger',
    -- BX/Midnight
    'midnight:client',
    -- Absolute
    'abs:trigger',
    -- Stix/Quasar leak
    'stix:init',
    -- Orbital
    'orbital:callback',
    -- Generic executor patterns
    'cheat:bypass',
    'exploit:init',
    'menu:open',
    'inject:payload',
}

-- =============================================
-- TXADMIN INTEGRATION
-- =============================================
-- When enabled, all kicks and bans route through txAdmin so everything
-- appears in ONE ban list (txAdmin web panel). No need to check a
-- separate bans.json. Unbanning is done from txAdmin or /acunban.
--
-- Requirements:
--   txAdmin >= 7.0  (bundled with FXServer builds >= 7290)
--
-- How it works:
--   BanPlayer()  -> TxActionBan()  -> exports['monitor']:addBan()
--   KickPlayer() -> TxActionKick() -> exports['monitor']:kickPlayer()
--   The local bans.json is NOT touched while this is enabled.
Config.TxAdmin = {
    -- Master switch. true = use txAdmin bans. false = use built-in bans.json.
    enabled      = true,

    -- Prefix on every auto-action reason so you can filter in txAdmin easily.
    reasonPrefix = '[AC] ',

    -- Author name shown in txAdmin logs for automated actions.
    autoAuthor   = 'Cobra Anti-Cheat',
}

-- =============================================
-- BAN SETTINGS (fallback if TxAdmin.enabled = false)
-- =============================================
Config.Bans = {
    -- Default ban duration for auto-bans in minutes (0 = permanent)
    defaultDuration = 0,
    -- Message shown to a kicked player
    kickMessage     = '[Cobra AC] You have been removed from the server.,
    -- Message shown to a banned player
    banMessage      = '[Cobra AC] You have been banned. Appeal at discord.gg/yourserver',
}

-- =============================================
-- SCREENSHOT SETTINGS
-- =============================================
Config.Screenshots = {
    -- Auto-screenshot the player at moment of detection (requires screenshot-basic resource)
    enabled       = true,
    -- Only screenshot on blatant detections (set false to also screenshot suspicious)
    blatantOnly   = false,
    -- Image encoding: 'jpg' or 'png'
    encoding      = 'jpg',
    -- JPEG quality 0.0-1.0
    quality       = 0.90,
    -- Cooldown between auto-screenshots per player (ms) — avoid spamming
    cooldown      = 30000,
    -- For SUSPICIOUS (non-blatant) detections: only screenshot once a player
    -- has accumulated this many total flags. Prevents noise on first flags.
    suspiciousFlagThreshold = 3,
}

-- =============================================
-- ADMIN LOG SETTINGS
-- =============================================
Config.AdminLog = {
    -- Log ALL admin commands (including chat commands like /acban /ackick)
    logCommands       = true,
    -- Log txAdmin actions relayed through monitor events
    logTxAdmin        = true,
    -- Keep an in-memory rolling log of the last N actions (shown in panel)
    memoryLimit       = 500,
    -- Also write the log to a file on disk (admin_log.json)
    writeToDisk       = true,
    -- Redact IP addresses in log file for GDPR compliance
    redactIPs         = true,
}

-- =============================================
-- ECONOMY PROTECTION
-- =============================================
Config.Economy = {
    -- Cash balance jump in one transaction that triggers an alert (£)
    cashSpikeThreshold  = 50000,
    -- Bank balance jump in one transaction that triggers an alert (£)
    bankSpikeThreshold  = 100000,
    -- Minimum balance needed before monitoring kicks in (avoids fresh-spawn noise)
    minBalanceToTrack   = 1000,
    -- Items that are high-value and should be monitored for duplication
    -- Add any item name from qs-inventory / ox_inventory
    watchedItems = {
        'money', 'black_money', 'gold_bar', 'diamond', 'coke', 'meth',
        'weed', 'crack', 'heroin', 'pistol', 'rifle', 'smg',
        'lockpick', 'advancedlockpick', 'repairkit',
    },
    -- Max single-transaction cash gain before flagging (does not block, just alerts)
    cashSpikeThreshold  = 50000,
    -- Max single-transaction bank gain before flagging
    bankSpikeThreshold  = 100000,
    -- Minimum balance to start tracking (avoid false positives on fresh spawns)
    minBalanceToTrack   = 1000,
}

-- =============================================
-- UI SETTINGS
-- =============================================
Config.UI = {
    -- Keybind to open admin panel (admin only)
    openKey = 'F6',
    -- How often client sends a heartbeat to server (ms)
    heartbeatInterval = 5000,
    -- How often detections are polled (ms)
    detectionInterval = 1000,
}
