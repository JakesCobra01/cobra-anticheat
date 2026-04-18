/* ============================================================
   cobra-anticheat / html / js / app.js  v2.0
   Cobra Development
   ============================================================ */
'use strict';

// ── State ─────────────────────────────────────────────────────────────────────
let playerList    = [];
let alertLog      = [];
let adminLog      = [];
let bansToday     = 0;
let adminActions  = 0;
let selectedPlayer  = null;
let selectedFrozen  = false;

// ── Detection registry ────────────────────────────────────────────────────────
const DETECTIONS = {
  godMode:            { label: 'God Mode',              category: 'BLATANT'    },
  explosionSpam:      { label: 'Explosion Spam',         category: 'BLATANT'    },
  weaponSpawn:        { label: 'Weapon Spawn',           category: 'BLATANT'    },
  vehicleSpawn:       { label: 'Vehicle Spawn',          category: 'BLATANT'    },
  infiniteAmmo:       { label: 'Infinite Ammo',          category: 'BLATANT'    },
  superJump:          { label: 'Super Jump',             category: 'BLATANT'    },
  invisibility:       { label: 'Invisibility',           category: 'BLATANT'    },
  noClip:             { label: 'NoClip',                 category: 'BLATANT'    },
  resourceInjection:  { label: 'Resource Injection',    category: 'BLATANT'    },
  entitySpam:         { label: 'Entity Spam',            category: 'BLATANT'    },
  blacklistedWeapons: { label: 'Blacklisted Weapon',    category: 'BLATANT'    },
  menuDetection:      { label: 'Cheat Menu',            category: 'BLATANT'    },
  aimbot:             { label: 'Aimbot',                 category: 'BLATANT'    },
  aimbotLockOn:       { label: 'Aimbot Lock-On',        category: 'BLATANT'    },
  wallhack:           { label: 'Wallhack / ESP',         category: 'BLATANT'    },
  speedHack:          { label: 'Speed Hack',             category: 'SUSPICIOUS' },
  teleport:           { label: 'Teleport',               category: 'SUSPICIOUS' },
  rapidFire:          { label: 'Rapid Fire',             category: 'SUSPICIOUS' },
  healthRegen:        { label: 'Health Regen',           category: 'SUSPICIOUS' },
  armourRegen:        { label: 'Armour Regen',           category: 'SUSPICIOUS' },
  vehicleGodMode:     { label: 'Vehicle God Mode',       category: 'SUSPICIOUS' },
  coordBounce:        { label: 'Coord Bounce',           category: 'SUSPICIOUS' },
  nightVision:        { label: 'Night Vision Abuse',     category: 'SUSPICIOUS' },
  thermalVision:      { label: 'Thermal Vision Abuse',   category: 'SUSPICIOUS' },
  fallingDamage:      { label: 'No Fall Damage',         category: 'SUSPICIOUS' },
  itemDupe:           { label: 'Item Duplication',       category: 'ECONOMY'    },
  moneyDupe:          { label: 'Money Duplication',      category: 'ECONOMY'    },
};

const LOG_COLORS = {
  BAN:'red', KICK:'orange', UNBAN:'green', WARN:'orange',
  FREEZE:'accent', UNFREEZE:'accent', SPECTATE:'dim', 'STOP SPECTATE':'dim',
  SCREENSHOT:'dim', 'TELEPORT TO':'accent', BRING:'accent',
  'CLEAR FLAGS':'orange', 'PANEL OPEN':'dim',
  TXADMIN_BAN:'red', TXADMIN_KICK:'orange', TXADMIN_WARN:'orange',
  TXADMIN_UNBAN:'green', TXADMIN_RESTART:'red', TXADMIN_RESOURCE:'dim',
  GENERAL_CMD:'accent', RESOURCE_START:'orange', RESOURCE_STOP:'orange',
  'AC STOPPED':'red',
};

const LOG_SOURCE = {
  panel:   { icon:'🖥️',  label:'Panel'   },
  command: { icon:'💬',  label:'Command' },
  txadmin: { icon:'🔧',  label:'txAdmin' },
  general: { icon:'🎮',  label:'General' },
  system:  { icon:'🤖',  label:'System'  },
};

// ── NUI message handler ───────────────────────────────────────────────────────
window.addEventListener('message', (e) => {
  const d = e.data;
  if (!d || !d.type) return;
  switch (d.type) {
    case 'openPanel':
      playerList = d.playerList || [];
      if (d.adminLog) adminLog = d.adminLog;
      openPanel(); renderPlayerList(); renderAdminLog();
      break;
    case 'closePanel':    closePanel();                             break;
    case 'updatePlayerList':
      playerList = d.playerList || [];
      renderPlayerList(); updateSidebarStats();
      if (selectedPlayer) {
        const u = playerList.find(p => p.id === selectedPlayer.id);
        if (u) { selectedPlayer = u; renderModalFlags(u); }
      }
      break;
    case 'newAlert':      pushAlert(d.alert);                      break;
    case 'receiveAdminLog':
      adminLog = d.log || [];
      renderAdminLog(); updateSidebarStats();
      break;
  }
});

// ── Panel ─────────────────────────────────────────────────────────────────────
function openPanel() {
  document.getElementById('overlay').classList.remove('hidden');
  renderConfigTab(); updateSidebarStats();
}
function closePanel() {
  document.getElementById('overlay').classList.add('hidden');
  closeModal(); sendAction('closeUI', {});
}

// ── Tabs ──────────────────────────────────────────────────────────────────────
document.querySelectorAll('.nav-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    const tab = btn.dataset.tab;
    document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.tab-pane').forEach(p => p.classList.remove('active'));
    btn.classList.add('active');
    document.getElementById('tab-' + tab).classList.add('active');
    if (tab === 'adminlog') refreshAdminLog();
  });
});

// ── Sidebar stats ─────────────────────────────────────────────────────────────
function updateSidebarStats() {
  document.getElementById('stat-online').textContent       = playerList.length;
  document.getElementById('stat-bans').textContent         = bansToday;
  document.getElementById('stat-adminactions').textContent = adminLog.length;
  const flagged = playerList.filter(p => getTotalFlags(p) > 0).length;
  document.getElementById('stat-flagged').textContent      = flagged;
  document.getElementById('badge-players').textContent     = playerList.length;
  const ab = document.getElementById('badge-alerts');
  ab.textContent = alertLog.length;
  ab.className   = alertLog.length > 0 ? 'badge red' : 'badge';
  const lb = document.getElementById('badge-adminlog');
  lb.textContent = adminLog.length;
  lb.className   = adminLog.length > 0 ? 'badge orange' : 'badge';
}

// ── Player list ───────────────────────────────────────────────────────────────
function getTotalFlags(p) {
  return p.flags ? Object.values(p.flags).reduce((a,b) => a+b, 0) : 0;
}
function pingCls(ping) { return ping<80?'good':ping<180?'medium':'bad'; }

function renderPlayerList() {
  const grid   = document.getElementById('player-list');
  const search = document.getElementById('player-search').value.toLowerCase();
  const list   = playerList.filter(p =>
    p.name.toLowerCase().includes(search) || String(p.id).includes(search));

  if (!list.length) { grid.innerHTML = '<div class="empty-state">No players connected.</div>'; updateSidebarStats(); return; }

  grid.innerHTML = list.map(p => {
    const total   = getTotalFlags(p);
    const cls     = total>=5 ? 'player-card high-flags' : total>0 ? 'player-card flagged' : 'player-card';
    const coords  = p.coords ? `${p.coords.x.toFixed(0)}, ${p.coords.y.toFixed(0)}, ${p.coords.z.toFixed(0)}` : 'N/A';
    const entries = p.flags ? Object.entries(p.flags).sort((a,b) => b[1]-a[1]) : [];
    const chips   = entries.slice(0,4).map(([k,v]) => {
      const d = DETECTIONS[k];
      return `<span class="flag-chip${d&&d.category==='BLATANT'?' blatant':''}">${d?d.label:k} ×${v}</span>`;
    }).join('') + (entries.length>4 ? `<span class="flag-chip">+${entries.length-4}</span>` : '');

    return `<div class="${cls}" onclick="openPlayerModal(${p.id})">
      <div class="pc-top">
        <div><div class="pc-name" title="${escHtml(p.name)}">${escHtml(p.name)}</div>
        <div class="pc-id">ID: ${p.id}</div></div>
        <span class="pc-ping ${pingCls(p.ping)}">${p.ping}ms</span>
      </div>
      <div class="pc-coords">📍 ${coords}</div>
      <div class="pc-flags">${chips}</div>
    </div>`;
  }).join('');
  updateSidebarStats();
}

document.getElementById('player-search').addEventListener('input', renderPlayerList);
function refreshList() { sendAction('refreshList', {}); }

// ── Player modal ──────────────────────────────────────────────────────────────
function openPlayerModal(id) {
  const p = playerList.find(p => p.id === id);
  if (!p) return;
  selectedPlayer = p;
  selectedFrozen = false;
  document.getElementById('freeze-label').textContent = 'Freeze';
  document.getElementById('modal-player-name').textContent = `${p.name} (ID: ${p.id})`;
  const c = p.coords;
  document.getElementById('modal-info').innerHTML = `
    <div>🪪 <b>License:</b> ${escHtml(p.license||'N/A')}</div>
    <div>💬 <b>Discord:</b> ${escHtml(p.discord||'N/A')}</div>
    <div>📍 <b>Coords:</b> ${c?`${c.x.toFixed(2)}, ${c.y.toFixed(2)}, ${c.z.toFixed(2)}`:'N/A'}</div>
    <div>📶 <b>Ping:</b> ${p.ping}ms</div>
    <div>⏱️ <b>Joined:</b> ${p.joinTime?new Date(p.joinTime*1000).toLocaleTimeString():'N/A'}</div>
    <div>⚑ <b>Total Flags:</b> ${getTotalFlags(p)}</div>`;
  renderModalFlags(p);
  document.getElementById('action-modal').classList.remove('hidden');
}

function renderModalFlags(p) {
  const el = document.getElementById('modal-flags');
  if (!p.flags || !Object.keys(p.flags).length) {
    el.innerHTML = '<div class="no-flags">No flags recorded.</div>'; return;
  }
  el.innerHTML = Object.entries(p.flags).sort((a,b)=>b[1]-a[1]).map(([k,v]) => {
    const d = DETECTIONS[k];
    return `<div class="flag-item">
      <div><span class="flag-item-name">${d?d.label:k}</span>
      <span class="flag-cat ${d?d.category.toLowerCase():''}">${d?d.category:''}</span></div>
      <span class="flag-item-count${v>=5?' high':''}" >×${v}</span>
    </div>`;
  }).join('');
}

function closeModal() { document.getElementById('action-modal').classList.add('hidden'); selectedPlayer = null; }

function modalAction(action) {
  if (!selectedPlayer) return;
  sendAction(action, { targetId: selectedPlayer.id });
}

function toggleFreeze() {
  if (!selectedPlayer) return;
  selectedFrozen = !selectedFrozen;
  document.getElementById('freeze-label').textContent = selectedFrozen ? 'Unfreeze' : 'Freeze';
  sendAction('freeze', { targetId: selectedPlayer.id, frozen: selectedFrozen });
}

// Kick / ban modals
function openKickModal()  { document.getElementById('kick-reason').value=''; document.getElementById('kick-modal').classList.remove('hidden'); }
function closeKickModal() { document.getElementById('kick-modal').classList.add('hidden'); }
function confirmKick() {
  if (!selectedPlayer) return;
  sendAction('kick', { targetId: selectedPlayer.id, reason: document.getElementById('kick-reason').value.trim()||'Kicked by admin' });
  closeKickModal(); closeModal();
}

function openBanModal()  { document.getElementById('ban-reason').value=''; document.getElementById('ban-duration').value='0'; document.getElementById('ban-modal').classList.remove('hidden'); }
function closeBanModal() { document.getElementById('ban-modal').classList.add('hidden'); }
function confirmBan() {
  if (!selectedPlayer) return;
  sendAction('ban', { targetId: selectedPlayer.id,
    reason:   document.getElementById('ban-reason').value.trim()||'Banned by admin',
    duration: parseInt(document.getElementById('ban-duration').value)||0 });
  bansToday++; closeBanModal(); closeModal();
}

document.getElementById('action-modal').addEventListener('click', function(e) { if (e.target===this) closeModal(); });

// ── Unban / offline ban ───────────────────────────────────────────────────────
function submitUnban() {
  const id = document.getElementById('unban-identifier').value.trim();
  if (!id) return;
  sendAction('unban', { identifier: id });
  document.getElementById('unban-identifier').value = '';
}

function submitOfflineBan() {
  const id       = document.getElementById('offlineban-id').value.trim();
  const reason   = document.getElementById('offlineban-reason').value.trim() || 'Banned by admin';
  const duration = parseInt(document.getElementById('offlineban-duration').value) || 0;
  if (!id) return;
  sendAction('offlineBan', { identifier: id, reason, duration });
  document.getElementById('offlineban-id').value     = '';
  document.getElementById('offlineban-reason').value = '';
}

// ── Alerts ────────────────────────────────────────────────────────────────────
function pushAlert(alert) {
  alert.time = alert.time || new Date().toLocaleTimeString();
  alertLog.unshift(alert);
  if (alertLog.length > 300) alertLog.pop();
  renderAlerts(); updateSidebarStats();
}

function renderAlerts() {
  const el     = document.getElementById('alert-log');
  const filter = document.getElementById('alert-filter').value;
  const items  = alertLog.filter(a =>
    filter==='all' || (filter==='blatant' && a.isBlatant) || (filter==='suspicious' && !a.isBlatant));
  if (!items.length) { el.innerHTML='<div class="empty-state">No alerts match this filter.</div>'; return; }
  el.innerHTML = items.map(a => {
    const cls  = a.isBlatant ? 'blatant' : 'suspicious';
    const icon = a.isBlatant ? '🚨' : '⚠️';
    return `<div class="alert-entry ${cls}">
      <div class="alert-icon ${cls}">${icon}</div>
      <div class="alert-body">
        <div class="alert-top">
          <span class="alert-type ${cls}">${escHtml(a.detType||'Detection')}</span>
          <span class="alert-time">${a.time}</span>
        </div>
        <div class="alert-player">Player: ${escHtml(a.playerName||'?')} (ID: ${a.playerId||'?'})</div>
        <div class="alert-detail">${escHtml(a.detail||'')}</div>
      </div>
    </div>`;
  }).join('');
}
document.getElementById('alert-filter').addEventListener('change', renderAlerts);
function clearAlerts() { alertLog=[]; renderAlerts(); updateSidebarStats(); }

// ── Admin log ─────────────────────────────────────────────────────────────────
function refreshAdminLog() { sendAction('requestAdminLog', { limit: 200 }); }

function renderAdminLog() {
  const el     = document.getElementById('adminlog-list');
  const filter = document.getElementById('adminlog-filter').value;
  const search = (document.getElementById('adminlog-search').value||'').toLowerCase();
  const items  = adminLog.filter(e => {
    if (filter !== 'all' && e.source !== filter) return false;
    if (search && !((e.adminName||'').toLowerCase().includes(search) ||
                    (e.action||'').toLowerCase().includes(search)     ||
                    (e.detail||'').toLowerCase().includes(search)))   return false;
    return true;
  });

  if (!items.length) { el.innerHTML='<div class="empty-state">No entries match the filter.</div>'; return; }

  el.innerHTML = items.map(e => {
    const src     = LOG_SOURCE[e.source] || { icon:'❓', label: e.source||'?' };
    const color   = LOG_COLORS[e.action] || 'dim';
    const target  = e.targetName && e.targetName!=='N/A'
      ? `<span class="al-target">→ ${escHtml(e.targetName)}${e.targetId?' (ID:'+e.targetId+')':''}</span>` : '';
    const detail  = e.detail ? `<div class="al-detail">${escHtml(e.detail)}</div>` : '';
    return `<div class="adminlog-entry">
      <div class="al-source source-${e.source||'system'}" title="${src.label}">${src.icon}</div>
      <div class="al-body">
        <div class="al-top">
          <span class="al-action color-${color}">${escHtml(e.action)}</span>
          <span class="al-admin">${escHtml(e.adminName||'System')}</span>
          ${target}
          <span class="al-time">${e.timestampFmt||''}</span>
        </div>
        ${detail}
      </div>
    </div>`;
  }).join('');
}
document.getElementById('adminlog-filter').addEventListener('change', renderAdminLog);
document.getElementById('adminlog-search').addEventListener('input', renderAdminLog);

// ── Config tab ────────────────────────────────────────────────────────────────
function renderConfigTab() {
  const groups = { BLATANT:[], SUSPICIOUS:[], ECONOMY:[] };
  Object.entries(DETECTIONS).forEach(([k,v]) => (groups[v.category]||groups.BLATANT).push({key:k,...v}));
  document.getElementById('config-grid').innerHTML =
    Object.entries(groups).map(([cat, items]) =>
      `<div class="config-category-header">${cat}</div>` +
      items.map(d => `<div class="config-item">
        <div><div class="config-name">${d.label}</div><div class="config-tag">${d.key}</div></div>
        <span class="toggle-pill on">ACTIVE</span>
      </div>`).join('')
    ).join('');

  document.getElementById('threshold-grid').innerHTML = [
    ['Foot Speed Max','12.0 m/s'],['Vehicle Speed Max','95.0 m/s'],
    ['Teleport Distance','250 units'],['Explosion Limit','5 / 3s'],
    ['Rapid Fire Max','20 shots/s'],['Aimbot Snap Angle','75°/frame'],
    ['Aimbot Snap Frames','3 frames'],['Aimbot HS Rate','85%'],
    ['Aimbot Sample Frames','45 frames'],['Wallhack Range','120m'],
    ['Wallhack Min Hits','3 hits'],['Dupe Event Window','2000ms'],
    ['Dupe Event Max','12 events'],['Item Dupe Window','5000ms'],
    ['Item Max Qty','×5'],['Cash Spike','£50,000'],['Bank Spike','£100,000'],
  ].map(([n,v]) => `<div class="threshold-item"><span class="threshold-name">${n}</span><span class="threshold-val">${v}</span></div>`).join('');
}

// ── NUI action sender ─────────────────────────────────────────────────────────
function sendAction(action, payload) {
  fetch(`https://${GetParentResourceName()}/ac_action`, {
    method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({ action, ...payload }),
  }).catch(()=>{});
}
function GetParentResourceName() {
  return window.GetParentResourceName ? window.GetParentResourceName() : 'cobra-anticheat';
}

function escHtml(s) {
  if (s===null||s===undefined) return '';
  const d = document.createElement('div');
  d.textContent = String(s); return d.innerHTML;
}
