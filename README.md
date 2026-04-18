# cobra-anticheat

**Cobra Development** — FiveM QBCore Anti-Cheat System  
Version 2.0.0

---

## What's New in v2.0

- Screenshots are now **embedded directly inside the detection embed** — one compact Discord card per alert, not two separate messages
- Full **unban UI** in the panel (online and offline players)
- **Offline ban** — ban a player by identifier even after they've left the server
- **General admin command logger** — QBCore admin commands (`/ban`, `/kick`, `/god`, `/noclip`, `/heal`, `/revive`, `/car`, `/tp`, `/setjob`, etc.) used by admins are now logged to both the audit log and a dedicated `#general-admin` Discord channel
- **txAdmin web panel actions** fully captured (ban, kick, warn, unban, restart, resource control)
- Renamed to `cobra-anticheat` under **Cobra Development** branding

---

## Detection Coverage

### Blatant (auto-action configurable)
- God Mode / Vehicle God Mode
- NoClip
- Explosion Spam
- Infinite Ammo
- Weapon & Vehicle Spawn (blacklisted)
- Invisibility
- Resource Injection
- Known Cheat Menu Signatures (Eulen, Lynx, Midnight, Absolute, Stix, Orbital, etc.)
- **Aimbot** — snap angle, lock-on variance, headshot rate
- **Wallhack / ESP** — shooting through geometry, aiming through cover, ESP broadcast events

### Suspicious (alert + optional action)
- Speed Hack (foot & vehicle, separate thresholds)
- Teleport
- Rapid Fire
- Health / Armour Regen
- Coord Bounce (desync exploit)
- Night Vision / Thermal Vision abuse
- No Fall Damage
- Super Jump

### Economy / Duplication
- **Item Duplication** — client-side event rate + server-side item velocity tracking
- **Money Duplication** — periodic balance polling + single-transaction spike detection

---

## Discord Channels (Config.Webhooks)

| Key           | Purpose                                              |
|---------------|------------------------------------------------------|
| `main`        | All alerts combined                                  |
| `blatant`     | Blatant cheat detections                             |
| `suspicious`  | Suspicious behaviour alerts                          |
| `bans`        | Bans, kicks, unbans                                  |
| `admin`       | AC panel actions (freeze, spectate, TP, etc.)        |
| `adminlog`    | **Complete audit log** — every action from every source |
| `generaladmin`| **General admin commands** — QBCore/ESX admin usage  |
| `screenshots` | Auto-screenshots (also embedded inside alert cards)  |
| `economy`     | Item and money duplication alerts                    |

---

## Screenshots in Embeds

Screenshots taken at the moment of detection are attached as `image` inside the detection embed itself using Discord's image field. This means:

- One message per alert, not two
- Screenshot is immediately visible beneath the player info without scrolling
- If `screenshot-basic` is not installed the embed sends cleanly without an image — no errors, no broken messages
- Blatant detections always screenshot; suspicious detections only screenshot once a player has `suspiciousFlagThreshold` (default: 3) total flags

---

## Admin Audit Log

Every admin action is captured regardless of where it originates:

| Source    | Examples                                                |
|-----------|---------------------------------------------------------|
| `panel`   | Freeze, spectate, TP, bring, screenshot, clear flags    |
| `command` | `/acban`, `/ackick`, `/acunban`, `/actp`, `/acbring`    |
| `txadmin` | Ban, kick, warn, unban, restart, resource start/stop    |
| `general` | `/ban`, `/kick`, `/god`, `/noclip`, `/heal`, `/car`, `/setjob`, etc. |
| `system`  | Resource start/stop events, AC stopped alert            |

All entries are:
- Stored in `adminlog.json` (survives restarts)
- Sent to `#adminlog` Discord channel
- General commands additionally sent to `#generaladmin` channel
- Viewable in the in-game panel Admin Log tab with source/action filtering and search

---

## Installation

1. Drop `cobra-anticheat` into your `resources` folder
2. Add to `server.cfg`:
   ```
   ensure cobra-anticheat
   ```
3. Fill in all webhook URLs in `config.lua`
4. Set `Config.ServerName` to your server name
5. Add admin license identifiers to `Config.CustomAdmins` or use ace permissions:
   ```
   add_ace group.cobraadmin anticheat.admin allow
   add_ace group.cobraadmin anticheat.view allow
   add_ace group.cobraadmin anticheat.kick allow
   add_ace group.cobraadmin anticheat.ban allow
   add_ace group.cobraadmin anticheat.unban allow
   add_ace group.cobraadmin anticheat.moderate allow
   add_principal identifier.license:YOURLIC group.cobraadmin
   ```
6. Restart server

---

## Dependencies

- `ox_lib` — notifications
- `screenshot-basic` — auto-screenshots (optional but strongly recommended)
- `oxmysql` — listed in manifest, not actively used in current version

---

## Chat Commands

| Command                        | Permission          | Description                        |
|-------------------------------|---------------------|------------------------------------|
| `/acpanel`                    | anticheat.view      | Open the admin panel               |
| `/acban [id] [mins] [reason]` | anticheat.ban       | Ban a player                       |
| `/acunban [identifier]`       | anticheat.unban     | Unban by identifier                |
| `/ackick [id] [reason]`       | anticheat.kick      | Kick a player                      |
| `/actp [id]`                  | anticheat.moderate  | Teleport to player                 |
| `/acbring [id]`               | anticheat.moderate  | Bring player to you                |
| `/acfreeze [id]`              | anticheat.moderate  | Freeze a player                    |
| `/acspectate [id]`            | anticheat.moderate  | Spectate a player                  |
| `/acscreenshot [id]`          | anticheat.moderate  | Take a manual screenshot           |
| `/acflags [id]`               | anticheat.view      | Show flag summary for a player     |
| `/achelp`                     | anticheat.view      | List all commands                  |

---

## Tuning Mode

All `Config.AutoActions` are set to `'alert'` by default. This means:

- Alerts fire and screenshots are taken
- No automated kicks or bans happen
- Monitor your Discord channels for several sessions to identify false positives
- Once a detection is confirmed reliable, change its value to `'kick'` or `'ban'`

Suggested tuning order (most reliable first):
1. `menuDetection` → `'ban'` (near-zero false positives)
2. `resourceInjection` → `'ban'`
3. `godMode` → `'kick'`
4. `infiniteAmmo` → `'kick'`
5. `invisibility` → `'kick'`
6. `noClip` → `'kick'`
7. `explosionSpam` → `'kick'`

---

## File Structure

```
cobra-anticheat/
├── fxmanifest.lua
├── config.lua
├── adminlog.json        (auto-created)
├── bans.json            (auto-created, only used if txAdmin disabled)
├── client/
│   ├── main.lua         — UI, heartbeat, admin receivers
│   ├── detections.lua   — Core detections
│   ├── advanced_detections.lua  — Aimbot, wallhack, dupe
│   └── noclip.lua       — Admin noclip tool
├── server/
│   ├── webhook.lua      — Discord embeds with screenshot baked in
│   ├── bans.lua         — txAdmin or fallback ban system
│   ├── adminlog.lua     — Full audit log + general command hooks
│   ├── dupe.lua         — Server-side economy protection
│   ├── main.lua         — Core server logic
│   └── commands.lua     — Chat commands
└── html/
    ├── index.html
    ├── css/style.css
    └── js/app.js
```

---

*Cobra Development — All resources prefixed `cobra-`*
