/*
 * SmartQueue front end.
 * This file only calls the API, which only calls stored procedures and views.
 * There is no scoring, sorting, wait-time or assignment logic here.
 */

const ICONS = {
  plus: '<svg class="i" viewBox="0 0 24 24"><path d="M12 5v14M5 12h14"/></svg>',
  search: '<svg class="i" viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>',
  queue: '<svg class="i" viewBox="0 0 24 24"><path d="M4 6h16M4 12h16M4 18h10"/></svg>',
  bell: '<svg class="i" viewBox="0 0 24 24"><path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10 21a2 2 0 0 0 4 0"/></svg>',
  pulse: '<svg class="i" viewBox="0 0 24 24"><path d="M3 12h4l3-8 4 16 3-8h4"/></svg>',
  spark: '<svg class="i" viewBox="0 0 24 24"><path d="M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M5.6 18.4l2.1-2.1M16.3 7.7l2.1-2.1"/></svg>',
  grid: '<svg class="i" viewBox="0 0 24 24"><rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/></svg>',
  file: '<svg class="i" viewBox="0 0 24 24"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5M9 13h6M9 17h6"/></svg>',
  chart: '<svg class="i" viewBox="0 0 24 24"><path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/></svg>',
  calendar: '<svg class="i" viewBox="0 0 24 24"><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/></svg>',
  users: '<svg class="i" viewBox="0 0 24 24"><circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><circle cx="17" cy="9" r="2.5"/><path d="M15.5 14.5a5 5 0 0 1 6 5"/></svg>',
  sliders: '<svg class="i" viewBox="0 0 24 24"><path d="M4 7h10M18 7h2M4 17h4M12 17h8"/><circle cx="16" cy="7" r="2"/><circle cx="10" cy="17" r="2"/></svg>',
  shield: '<svg class="i" viewBox="0 0 24 24"><path d="M12 3 4 6v6c0 5 3.5 8 8 9 4.5-1 8-4 8-9V6z"/><path d="m9 12 2 2 4-4"/></svg>',
  book: '<svg class="i" viewBox="0 0 24 24"><path d="M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2z"/><path d="M4 19a2 2 0 0 1 2-2h13"/></svg>',
  lock: '<svg class="i" viewBox="0 0 24 24"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>',
  out: '<svg class="i" viewBox="0 0 24 24"><path d="M10 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h4M15 8l5 4-5 4M20 12H9"/></svg>',
  x: '<svg class="i" viewBox="0 0 24 24"><path d="M6 6l12 12M18 6 6 18"/></svg>',
  check: '<svg class="i" viewBox="0 0 24 24"><path d="m5 12 4 4L19 6"/></svg>',
  warn: '<svg class="i" viewBox="0 0 24 24"><path d="M12 3 2 21h20z"/><path d="M12 10v5M12 18h.01"/></svg>',
  info: '<svg class="i" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/></svg>',
  clock: '<svg class="i" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>',
  user: '<svg class="i" viewBox="0 0 24 24"><circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/></svg>',
  stetho: '<svg class="i" viewBox="0 0 24 24"><path d="M6 3v6a5 5 0 0 0 10 0V3"/><path d="M11 14v2a4 4 0 0 0 8 0v-3"/><circle cx="19" cy="11" r="2"/></svg>',
  desk: '<svg class="i" viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8M12 16v4"/></svg>',
  inbox: '<svg class="i" viewBox="0 0 24 24"><path d="M4 13h4l2 3h4l2-3h4"/><path d="M5 5h14l2 8v6H3v-6z"/></svg>',
  refresh: '<svg class="i" viewBox="0 0 24 24"><path d="M20 12a8 8 0 1 1-2.3-5.7"/><path d="M20 4v5h-5"/></svg>',
  play: '<svg class="i" viewBox="0 0 24 24"><path d="M7 4v16l13-8z"/></svg>',
  pause: '<svg class="i" viewBox="0 0 24 24"><path d="M8 5v14M16 5v14"/></svg>',
  undo: '<svg class="i" viewBox="0 0 24 24"><path d="M9 14 4 9l5-5"/><path d="M4 9h11a5 5 0 0 1 0 10h-3"/></svg>',
  trash: '<svg class="i" viewBox="0 0 24 24"><path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/></svg>',
};

const NAV = {
  receptionist: [
    ['register', 'Register patient', 'plus'],
    ['search', 'Find patient', 'search'],
  ],
  nurse: [
    ['admit', 'Admit patient', 'pulse'],
    ['queue', 'Live queue', 'queue'],
    ['alerts', 'Alerts', 'bell'],
  ],
  doctor: [
    ['mine', 'My queue', 'stetho'],
    ['similar', 'Similar cases', 'spark'],
  ],
  admin: [
    ['dashboard', 'Dashboard', 'grid'],
    ['visits', 'Visits', 'file'],
    ['reports', 'Reports', 'chart'],
    ['roster', 'Shift roster', 'calendar'],
    ['people', 'People', 'users'],
    ['alerts', 'Alerts', 'bell'],
    ['settings', 'Policies', 'sliders'],
  ],
  auditor: [
    ['audit', 'Audit log', 'book'],
    ['scores', 'Score ledger', 'shield'],
  ],
};

const ROLE_META = {
  receptionist: { hint: 'Register and find patients', icon: 'desk', user: 'receptionist_user', password: 'Reception@123' },
  nurse: { hint: 'Admit, reassess, discharge', icon: 'pulse', user: 'nurse_user', password: 'Nurse@123' },
  doctor: { hint: 'Clinical queue, no contact details', icon: 'stetho', user: 'doctor_user', password: 'Doctor@123' },
  admin: { hint: 'Roster, reports, policies', icon: 'sliders', user: 'admin_user', password: 'Admin@123' },
  auditor: { hint: 'Change log only', icon: 'shield', user: 'auditor_user', password: 'Auditor@123' },
};

const WORDMARK = '<div class="logo">SmartQueue<i></i></div>';

function clockText(date) {
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false });
}

const state = {
  role: null,
  dbUser: null,
  page: null,
  timer: null,
  charts: [],
  queueSnap: '',
  selectedEncounter: null,
  pageToken: 0,
  pageAbort: null,
  queueFocus: null,
};

const app = document.getElementById('app');

/* ---------- helpers ---------- */

function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, (ch) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[ch]));
}

function icon(name) { return ICONS[name] || ''; }

function esi(n, big = false) {
  if (n === null || n === undefined || n === '') return '';
  return `<span class="esi esi-${esc(n)} ${big ? 'big' : ''}">ESI ${esc(n)}</span>`;
}

function pill(status) {
  if (!status) return '';
  return `<span class="pill ${esc(status)}">${esc(String(status).replace('_', ' '))}</span>`;
}

function initials(name) {
  return String(name || '?').replace(/^Dr\.?\s*/i, '').split(/\s+/).map((w) => w[0]).join('').slice(0, 2).toUpperCase();
}

function parseDate(value) {
  if (!value) return null;
  const date = new Date(String(value).replace(' ', 'T'));
  return Number.isNaN(date.getTime()) ? null : date;
}

function since(value) {
  const date = parseDate(value);
  if (!date) return '';
  const mins = Math.max(0, Math.round((Date.now() - date.getTime()) / 60000));
  if (mins < 60) return `${mins} min`;
  return `${Math.floor(mins / 60)} h ${mins % 60} m`;
}

function fmtTime(value) {
  const date = parseDate(value);
  return date ? date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : esc(value);
}

function fmtDateTime(value) {
  const date = parseDate(value);
  return date ? date.toLocaleString([], { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }) : esc(value);
}

function localDate(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function requestSignal() {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(new DOMException('timeout', 'TimeoutError')), 15000);
  const page = state.pageAbort;
  if (page) {
    const leave = () => ctrl.abort(new DOMException('leave', 'AbortError'));
    if (page.signal.aborted) leave();
    else page.signal.addEventListener('abort', leave, { once: true });
  }
  ctrl.signal.addEventListener('abort', () => clearTimeout(timer), { once: true });
  return ctrl.signal;
}

async function api(path, options = {}) {
  let res;
  try {
    res = await fetch(path, {
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json' },
      ...options,
      signal: options.signal || requestSignal(),
      body: options.body ? JSON.stringify(options.body) : undefined,
    });
  } catch (err) {
    if (err.name === 'AbortError') {
      const quiet = new Error('cancelled');
      quiet.cancelled = true;
      throw quiet;
    }
    if (err.name === 'TimeoutError') throw new Error('The server took too long to answer. Try again.');
    throw new Error('Could not reach the server. Try again.');
  }
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || 'Request failed');
  return data;
}

function toast(message, ok = false) {
  if (!message || message === 'cancelled') return;
  const host = document.getElementById('toasts');
  const el = document.createElement('div');
  el.className = `toast ${ok ? 'ok' : 'err'}`;
  el.innerHTML = `${icon(ok ? 'check' : 'warn')}<div>${esc(message)}</div><button type="button" aria-label="Dismiss">×</button>`;
  el.querySelector('button').onclick = () => el.remove();
  host.appendChild(el);
  setTimeout(() => el.remove(), ok ? 4500 : 9000);
}

function clearTimer() {
  if (state.timer) clearInterval(state.timer);
  state.timer = null;
  state.charts.forEach((chart) => chart.destroy());
  state.charts = [];
  closeDrawer();
}

function skeleton(n = 4) {
  return `<div class="skel">${'<div></div>'.repeat(n)}</div>`;
}

function empty(text, iconName = 'inbox') {
  return `<div class="empty">${icon(iconName)}<span>${esc(text)}</span></div>`;
}

const ESI_KEYS = new Set(['ESI', 'Old_Score', 'New_Score', 'Old_ESI', 'New_ESI', 'Most_Critical_ESI', 'ESI_Level']);
const STATUS_KEYS = new Set(['Current_Status', 'Doctor_Status', 'Status']);
const TIME_KEYS = new Set(['Arrival_Time', 'Check_out_Time', 'Changed_At', 'History_At', 'Created_At', 'Deleted_At', 'Assigned_Time', 'Vitals_At']);

function label(key) {
  return String(key).replace(/_/g, ' ').replace(/\b(id)\b/i, 'ID');
}

function cell(key, value) {
  if (value === null || value === undefined || value === '') return '<td class="faint">—</td>';
  if (ESI_KEYS.has(key)) return `<td>${esi(value)}</td>`;
  if (STATUS_KEYS.has(key)) return `<td>${pill(value)}</td>`;
  if (TIME_KEYS.has(key)) return `<td style="white-space:nowrap">${fmtDateTime(value)}</td>`;
  if (typeof value === 'object') {
    return `<td><details><summary>View JSON</summary><pre>${esc(JSON.stringify(value, null, 1))}</pre></details></td>`;
  }
  if (typeof value === 'number' && !Number.isInteger(value)) return `<td>${value.toFixed(2)}</td>`;
  return `<td>${esc(value)}</td>`;
}

function table(rows, columns) {
  if (!rows || !rows.length) return empty('Nothing to show.');
  const cols = columns || Object.keys(rows[0]).map((key) => [key, label(key)]);
  const head = cols.map(([, text]) => `<th>${esc(text)}</th>`).join('');
  const body = rows.map((row) => `<tr>${cols.map(([key]) => cell(key, row[key])).join('')}</tr>`).join('');
  return `<div class="table-wrap"><table><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table></div>`;
}

function field(name, text, opts = {}) {
  const type = opts.type || 'text';
  const unit = opts.unit ? `<em>${esc(opts.unit)}</em>` : '';
  const extra = opts.placeholder ? `placeholder="${esc(opts.placeholder)}"` : '';
  const max = opts.max ? `max="${esc(opts.max)}"` : '';
  const input = `<input name="${esc(name)}" type="${esc(type)}" ${type === 'number' ? 'step="any"' : ''} ${extra} ${max} ${opts.optional ? '' : 'required'}>`;
  return `<label class="${opts.wide ? 'wide' : ''}">${esc(text)}<span class="unit">${input}${unit}</span></label>`;
}

function vitalsFields() {
  return `
    <div class="vitals-grid wide">
      ${field('hr', 'Heart rate', { unit: 'bpm', placeholder: '60–100' })}
      ${field('spo2', 'SpO2', { unit: '%', placeholder: '95–100' })}
      ${field('temp', 'Temperature', { unit: '°C', placeholder: '36.5' })}
      ${field('sys', 'Systolic BP', { unit: 'mmHg', placeholder: '120' })}
      ${field('dia', 'Diastolic BP', { unit: 'mmHg', placeholder: '80' })}
      ${field('pain', 'Pain', { unit: '0–10', placeholder: '0' })}
    </div>`;
}

function statIcon(label) {
  const text = String(label).toLowerCase();
  if (/critical|alert|risk/.test(text)) return 'warn';
  if (/doctor/.test(text)) return 'stetho';
  if (/time|wait|longest|aging/.test(text)) return 'clock';
  if (/visit|record/.test(text)) return 'file';
  if (/patient|people|active/.test(text)) return 'users';
  if (/score|deleted/.test(text)) return 'shield';
  if (/department/.test(text)) return 'grid';
  return 'chart';
}

function stats(items) {
  return `<div class="stats">${items.map((it) => {
    const chip = it.tone === 'danger' ? '<span class="chip-d danger">Attention</span>' : '';
    return `
    <div class="stat ${it.tone || ''}">
      <div class="stat-top"><span class="ic">${icon(it.icon || statIcon(it.k))}</span>${chip}</div>
      <div class="k">${esc(it.k)}</div>
      <div class="v">${esc(it.v)}${it.unit ? `<small>${esc(it.unit)}</small>` : ''}</div>
    </div>`;
  }).join('')}</div>`;
}

/* ---------- drawer ---------- */

function openDrawer(title, sub, bodyHtml) {
  const drawer = document.getElementById('drawer');
  const scrim = document.getElementById('scrim');
  if (!drawer) return;
  drawer.innerHTML = `
    <div class="drawer-head">
      <div><h2>${title}</h2><div class="sub">${sub}</div></div>
      <button class="iconbtn" id="drawer-close" type="button" aria-label="Close">${icon('x')}</button>
    </div>
    <div class="drawer-body">${bodyHtml}</div>`;
  drawer.classList.add('open');
  scrim.classList.add('open');
  document.getElementById('drawer-close').onclick = closeDrawer;
  scrim.onclick = closeDrawer;
}

function closeDrawer() {
  const drawer = document.getElementById('drawer');
  const scrim = document.getElementById('scrim');
  if (drawer) drawer.classList.remove('open');
  if (scrim) scrim.classList.remove('open');
  state.selectedEncounter = null;
  document.querySelectorAll('.ticket.selected').forEach((el) => el.classList.remove('selected'));
}

/* ---------- boot / login / shell ---------- */

function pinTabs() {
  const vv = window.visualViewport;
  const raw = vv ? window.innerHeight - vv.height - vv.offsetTop : 0;
  const lift = Math.max(0, Math.min(140, Math.round(raw)));
  document.documentElement.style.setProperty('--tab-lift', lift + 'px');
  const bar = document.querySelector('.side');
  const fixed = bar && getComputedStyle(bar).position === 'fixed';
  document.documentElement.style.setProperty('--tabbar', (fixed ? bar.offsetHeight : 0) + 'px');
}

function watchTabs() {
  if (watchTabs.done) return;
  watchTabs.done = true;
  let frame = 0;
  const schedule = () => {
    if (!frame) frame = requestAnimationFrame(() => { frame = 0; pinTabs(); });
  };
  if (window.visualViewport) {
    window.visualViewport.addEventListener('resize', schedule);
    window.visualViewport.addEventListener('scroll', schedule);
  }
  window.addEventListener('orientationchange', schedule);
  pinTabs();
}

async function boot() {
  watchTabs();
  try {
    const me = await api('/api/me');
    state.role = me.role;
    state.dbUser = me.dbUser;
    state.page = NAV[me.role][0][0];
    renderShell();
  } catch {
    renderLogin();
  }
}

function renderLogin() {
  clearTimer();
  app.innerHTML = `
    <section class="login">
      <div class="login-left">
        ${WORDMARK}
        <div class="login-body">
          <h1>Welcome back<span id="hello-role">, Nurse</span>!</h1>
          <p class="sub">We are glad to see you again! Please enter your details.</p>
          <div class="roles" id="role-list"></div>
          <div class="or">or</div>
          <form class="login-form" id="login-form">
            <label>Username<input id="dbuser" type="text" autocomplete="username" spellcheck="false" placeholder="nurse_user"></label>
            <label>Password<input id="password" type="password" required autocomplete="current-password" placeholder="Enter your password"></label>
            <div class="row">
              <span class="remember"><input type="checkbox" checked> Remember me</span>
              <button type="button" class="link" id="need-help">Need help?</button>
            </div>
            <div class="help-card" id="login-help" hidden>
              <b>Five accounts, one per role</b>
              <p>Type a username, or tap a row and it fills in. Passwords are filled for the demo.</p>
              <div id="help-list"></div>
            </div>
            <button class="btn block" type="submit">Login</button>
            <div class="login-error" id="login-error"></div>
          </form>
          <p class="login-foot">SmartQueue · Hospital Emergency Management System</p>
        </div>
      </div>
      <div class="login-right">
        <div class="art">
          <img src="/img/login.jpg" alt="">
          <div class="glass serving">
            <div class="top"><span class="chip-d ok"><span class="dot"></span> Now serving</span><span class="k">Cardiology</span></div>
            <div class="row"><b>Rohan M.</b>${esi(1)}</div>
            <div class="k">Dr. Sameer Patil · Room 4</div>
          </div>
          <div class="glass mini">
            <div class="top"><b>Live queue</b><span class="chip-d outline">${icon('clock')} 3 waiting</span></div>
            <div class="q"><span class="n">1</span><span>Kavya I.</span>${esi(2)}</div>
            <div class="q"><span class="n">2</span><span>Priya N.</span>${esi(3)}</div>
            <div class="q"><span class="n">3</span><span>Arjun D.</span>${esi(4)}</div>
          </div>
          <div class="caption">
            <h2>The most critical patient is always seen first.</h2>
            <p>Vitals go in, priority comes out. The queue reorders itself the moment anything changes.</p>
          </div>
        </div>
      </div>
    </section>`;
  const roles = Object.keys(NAV);
  let selected = 'nurse';
  const list = document.getElementById('role-list');
  const password = document.getElementById('password');
  const dbuser = document.getElementById('dbuser');
  const knownPasswords = new Set(Object.values(ROLE_META).map((meta) => meta.password));
  function roleFromUser(value) {
    const name = String(value || '').trim().toLowerCase().split('@')[0];
    return roles.find((role) => ROLE_META[role].user === name) || null;
  }
  function paintTiles() {
    list.innerHTML = roles.map((role) => `
      <button type="button" class="role-tile ${role === selected ? 'active' : ''}" data-role="${role}" title="${esc(ROLE_META[role].hint)}">
        ${icon(ROLE_META[role].icon)}<span class="rn">${esc(role[0].toUpperCase() + role.slice(1))}</span>
      </button>`).join('');
    const hello = document.getElementById('hello-role');
    hello.textContent = selected ? `, ${selected[0].toUpperCase()}${selected.slice(1)}` : '';
    list.querySelectorAll('[data-role]').forEach((btn) => btn.addEventListener('click', () => {
      applyRole(btn.dataset.role);
    }));
  }
  function applyRole(role, { fillUser = true, fillPassword = true } = {}) {
    selected = role;
    if (fillUser) dbuser.value = ROLE_META[role].user;
    if (fillPassword) password.value = ROLE_META[role].password;
    paintTiles();
  }
  applyRole('nurse');
  dbuser.addEventListener('input', () => {
    const role = roleFromUser(dbuser.value);
    if (!role) {
      selected = null;
      paintTiles();
      return;
    }
    if (role === selected) return;
    applyRole(role, { fillUser: false, fillPassword: !password.value || knownPasswords.has(password.value) });
  });
  document.getElementById('need-help').onclick = () => {
    const card = document.getElementById('login-help');
    card.hidden = !card.hidden;
  };
  document.getElementById('help-list').innerHTML = roles.map((role) => {
    const meta = ROLE_META[role];
    const label = role[0].toUpperCase() + role.slice(1);
    return `<button type="button" class="help-row" data-role="${role}"><b>${esc(label)}</b><span>${esc(meta.user)}</span><span class="pw">${esc(meta.password)}</span></button>`;
  }).join('');
  document.getElementById('help-list').onclick = (event) => {
    const row = event.target.closest('[data-role]');
    if (!row) return;
    applyRole(row.dataset.role);
    document.getElementById('login-help').hidden = true;
    password.focus();
  };
  document.getElementById('login-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    const button = event.target.querySelector('button[type="submit"]');
    const role = roleFromUser(dbuser.value);
    const error = document.getElementById('login-error');
    if (!role) {
      error.textContent = 'No account by that username. Open Need help for the five accounts.';
      return;
    }
    button.disabled = true;
    try {
      const me = await api('/api/login', { method: 'POST', body: { role, password: password.value } });
      state.role = me.role;
      state.dbUser = me.dbUser;
      state.page = NAV[me.role][0][0];
      renderShell();
    } catch (err) {
      document.getElementById('login-error').textContent = err.message;
      button.disabled = false;
    }
  });
}

function renderShell() {
  clearTimer();
  const SHORT = { register: 'Register', search: 'Find', admit: 'Admit', queue: 'Queue', mine: 'Queue', similar: 'Similar', dashboard: 'Home', roster: 'Roster', settings: 'Policies', audit: 'Audit', scores: 'Scores' };
  const items = NAV[state.role].map(([id, text, ic]) =>
    `<button type="button" data-page="${id}" class="${id === state.page ? 'active' : ''}">${icon(ic)}<span>${esc(text)}</span><small class="short">${esc(SHORT[id] || text)}</small></button>`).join('');
  app.innerHTML = `
    <div class="shell"><div class="frame">
      <aside class="side">
        ${WORDMARK}
        <nav>${items}</nav>
        <div class="foot">
          <button class="btn ghost" id="logout" type="button">${icon('out')} Sign out</button>
        </div>
      </aside>
      <div class="workarea">
        <header class="topbar">
          <h1 id="title"></h1>
          <div class="right">
            <div class="live" id="live" hidden><span class="dot"></span><span>Live</span><span class="live-time" id="live-label"></span></div>
            <div class="who">
              <div class="av">${esc(state.role[0].toUpperCase())}</div>
              <div><b>${esc(state.role)}</b><span title="${esc(state.dbUser || '')}">${esc(state.dbUser || '')}</span></div>
            </div>
            <button class="iconbtn logout-m" id="logout-m" type="button" title="Sign out" aria-label="Sign out">${icon('out')}</button>
          </div>
        </header>
        <main class="main">
                    <div id="content"></div>
        </main>
      </div>
    </div></div>
    <div class="scrim" id="scrim"></div>
    <aside class="drawer" id="drawer"></aside>`;
  const signOut = async () => {
    try { await api('/api/logout', { method: 'POST' }); } catch { /* leave the page even if the server is down */ }
    state.role = null;
    renderLogin();
  };
  document.getElementById('logout').onclick = signOut;
  document.getElementById('logout-m').onclick = signOut;
  document.querySelectorAll('[data-page]').forEach((btn) => btn.addEventListener('click', () => {
    if (btn.dataset.page === state.page) return;
    state.page = btn.dataset.page;
    showPage();
  }));
  showPage();
}

function showPage() {
  if (state.page !== 'queue') state.queueFocus = null;
  if (state.pageAbort) state.pageAbort.abort();
  state.pageAbort = new AbortController();
  clearTimer();
  state.pageToken += 1;
  document.querySelectorAll('nav [data-page]').forEach((btn) => {
    btn.classList.toggle('active', btn.dataset.page === state.page);
  });
  const pages = {
    register: pageRegister, search: pageSearch,
    admit: pageAdmit, queue: pageQueue, alerts: pageAlerts,
    mine: pageMine, similar: pageSimilar,
    dashboard: pageDashboard, visits: pageVisits, reports: pageReports,
    roster: pageRoster, people: pagePeople, settings: pageSettings,
    audit: pageAudit, scores: pageScores,
  };
  const run = pages[state.page];
  if (run) run();
  pinTabs();
}

function heading(title, live = false) {
  document.getElementById('title').textContent = title;
  document.getElementById('live').hidden = !live;
}

function still(token) {
  return token === state.pageToken;
}

function content(html) {
  const el = document.getElementById('content');
  if (el) el.innerHTML = html;
}

function watch(fn, ms) {
  let busy = false;
  const run = () => {
    if (busy) return;
    busy = true;
    Promise.resolve()
      .then(fn)
      .catch(() => {})
      .finally(() => { busy = false; });
  };
  run();
  state.timer = setInterval(run, ms);
}

function tick() {
  const el = document.getElementById('live-label');
  if (el) el.textContent = '· ' + clockText(new Date());
}

/* ---------- Reception ---------- */

function pageRegister() {
  heading('Register a patient');
  content(`
    <div class="grid two">
      <form class="card form-grid" id="reg">
        <div class="card-head wide"><h2>${icon('plus')} New patient</h2></div>
        ${field('name', 'Full name', { wide: true, placeholder: 'Asha Verma' })}
        ${field('phone', 'Phone', { placeholder: '98XXXXXXXX' })}
        ${field('dob', 'Date of birth', { type: 'date', max: localDate(new Date()) })}
        ${field('email', 'Email', { type: 'email', wide: true, optional: true, placeholder: 'optional' })}
        <div class="wide actions"><button class="btn" type="submit">${icon('check')} Register patient</button></div>
      </form>
      <div class="card tight">
        <div class="card-head"><div><h2>Recently registered</h2><div class="sub" id="recent-sub">Newest first</div></div></div>
        <div id="recent" style="padding:0 18px 6px">${skeleton(3)}</div>
      </div>
    </div>`);
  const STATUS_TAG = { 'In queue': 'warn', Discharged: 'ok', Registered: '' };
  const token = state.pageToken;
  async function loadRecent(highlightId) {
    try {
      const data = await api('/api/patients/recent');
      if (!still(token)) return;
      const rows = data.rows || [];
      const recent = document.getElementById('recent');
      if (!recent) return;
      document.getElementById('recent-sub').textContent = rows.length ? `Newest first · ${rows.length} shown` : 'Newest first';
      recent.innerHTML = rows.length ? rows.map((row) => `
        <div class="person ${Number(row.Patient_ID) === Number(highlightId) ? 'new' : ''}">
          <div class="l"><div class="av">${esc(initials(row.Name))}</div>
            <div><b>${esc(row.Name)}</b>${Number(row.Patient_ID) === Number(highlightId) ? ' <span class="tag ok">Just added</span>' : ''}
              <div class="sub"><span>#${esc(row.Patient_ID)}</span><span>· ${esc(row.Phone)}</span><span>· age ${esc(row.Age)}</span></div></div></div>
          <span class="tag ${STATUS_TAG[row.Status] || ''}">${esc(row.Status)}</span>
        </div>`).join('') : empty('No patients registered yet.', 'user');
    } catch (err) {
      if (!still(token) || err.cancelled) return;
      const recent = document.getElementById('recent');
      if (recent) recent.innerHTML = empty(err.message, 'warn');
    }
  }
  loadRecent();
  document.getElementById('reg').onsubmit = async (event) => {
    event.preventDefault();
    const body = Object.fromEntries(new FormData(event.target));
    try {
      const data = await api('/api/patients', { method: 'POST', body });
      const row = (data.sets[0] || [])[0] || {};
      toast(`${row.Name || body.name} registered as patient ${row.Patient_ID}.`, true);
      event.target.reset();
      event.target.querySelector('input[name=name]').focus();
      loadRecent(row.Patient_ID);
    } catch (err) { toast(err.message); }
  };
}

function pageSearch() {
  heading('Find a patient');
  content(`
    <div class="card">
      <form class="toolbar" id="find" style="margin-bottom:0">
        <div class="search" style="flex:1">${icon('search')}<input name="q" placeholder="Name, phone or email" autocomplete="off" autofocus><div class="suggest" id="suggest" hidden></div></div>
        <button class="btn" type="submit">Search</button>
      </form>
    </div>
    <div class="card" id="hits" style="margin-top:16px">${empty('Type a name, phone or email and press Search.', 'search')}</div>`);
  const input = document.querySelector('#find input[name=q]');
  const box = document.getElementById('suggest');
  const cols = [['Patient_ID', 'ID'], ['Name', 'Name'], ['Phone', 'Phone'], ['Email', 'Email'], ['Date_of_Birth', 'Date of birth']];
  let suggestions = [];
  let cursor = -1;
  let debounce = null;
  let lastQuery = '';

  function hideSuggest() { box.hidden = true; box.innerHTML = ''; suggestions = []; cursor = -1; }
  function mark(text, q) {
    const s = String(text ?? '');
    const i = s.toLowerCase().indexOf(q.toLowerCase());
    if (i < 0 || !q) return esc(s);
    return `${esc(s.slice(0, i))}<mark>${esc(s.slice(i, i + q.length))}</mark>${esc(s.slice(i + q.length))}`;
  }
  function paintSuggest(q) {
    if (!suggestions.length) { hideSuggest(); return; }
    box.hidden = false;
    box.innerHTML = suggestions.map((row, i) => `
      <button type="button" class="opt ${i === cursor ? 'active' : ''}" data-i="${i}">
        <span class="av">${esc(initials(row.Name))}</span>
        <span class="t"><b>${mark(row.Name, q)}</b><small>${mark(row.Phone, q)}${row.Email ? ` · ${mark(row.Email, q)}` : ''}</small></span>
      </button>`).join('');
    box.querySelectorAll('.opt').forEach((el) => el.onmousedown = (event) => { event.preventDefault(); pick(Number(el.dataset.i)); });
  }
  function pick(i) {
    const row = suggestions[i];
    if (!row) return;
    input.value = row.Name;
    hideSuggest();
    document.getElementById('hits').innerHTML = table([row], cols);
  }
  input.oninput = () => {
    const q = input.value.trim();
    clearTimeout(debounce);
    if (q.length < 2) { hideSuggest(); return; }
    debounce = setTimeout(async () => {
      lastQuery = q;
      try {
        const data = await api('/api/patients/search?q=' + encodeURIComponent(q));
        if (q !== lastQuery || input.value.trim() !== q) return;
        suggestions = data.rows.slice(0, 8);
        cursor = -1;
        paintSuggest(q);
      } catch (_) { hideSuggest(); }
    }, 180);
  };
  input.onkeydown = (event) => {
    if (box.hidden) return;
    if (event.key === 'ArrowDown') { event.preventDefault(); cursor = (cursor + 1) % suggestions.length; paintSuggest(input.value.trim()); }
    else if (event.key === 'ArrowUp') { event.preventDefault(); cursor = (cursor - 1 + suggestions.length) % suggestions.length; paintSuggest(input.value.trim()); }
    else if (event.key === 'Enter' && cursor >= 0) { event.preventDefault(); pick(cursor); }
    else if (event.key === 'Escape') { hideSuggest(); }
  };
  input.onblur = () => setTimeout(hideSuggest, 120);
  document.getElementById('find').onsubmit = async (event) => {
    event.preventDefault();
    hideSuggest();
    const q = new FormData(event.target).get('q');
    document.getElementById('hits').innerHTML = skeleton(3);
    try {
      const data = await api('/api/patients/search?q=' + encodeURIComponent(q));
      document.getElementById('hits').innerHTML = data.rows.length
        ? table(data.rows, cols)
        : empty(`No patient matches “${q}”.`, 'search');
    } catch (err) { toast(err.message); document.getElementById('hits').innerHTML = empty(err.message, 'warn'); }
  };
}

/* ---------- Nurse ---------- */

function pageAdmit() {
  heading('Admit a patient');
  content(`
    <div class="grid two">
      <form class="card form-grid" id="admit">
        <div class="card-head wide"><h2>${icon('pulse')} Triage intake</h2></div>
        <label class="wide">Patient<select name="patient_id" id="patient" required><option value="">Loading…</option></select></label>
        <label class="wide">Presenting symptoms<textarea name="symptoms" required placeholder="severe chest pain and sweating"></textarea></label>
        ${vitalsFields()}
        <div class="wide actions"><button class="btn" type="submit">${icon('check')} Admit and score</button></div>
      </form>
      <div class="stack">
        <div class="card" id="admit-result">${empty('The triage result will appear here.', 'pulse')}</div>
        <details class="guide">
          <summary>How ESI levels are decided</summary>
          <div class="body">
            <div>${esi(1)} SpO2 &lt; 90, systolic &lt; 80, heart rate &gt; 150 or &lt; 40</div>
            <div>${esi(2)} SpO2 90–93, heart rate 120–150 or pain ≥ 8</div>
            <div>${esi(3)} Temperature ≥ 39 or pain 5–7</div>
            <div>${esi(4)} Pain 3–4</div>
            <div>${esi(5)} Everything else</div>
          </div>
        </details>
      </div>
    </div>`);
  const token = state.pageToken;
  async function loadPatients() {
    const data = await api('/api/admittable');
    if (!still(token)) return;
    const select = document.getElementById('patient');
    if (!select) return;
    select.innerHTML = data.rows.map((row) =>
      `<option value="${esc(row.Patient_ID)}">${esc(row.Name)} · age ${esc(row.Age)}</option>`).join('')
      || '<option value="">No registered patient is waiting to be admitted</option>';
  }
  loadPatients().catch((err) => toast(err.message));
  document.getElementById('admit').onsubmit = async (event) => {
    event.preventDefault();
    const body = Object.fromEntries(new FormData(event.target));
    const button = event.target.querySelector('button[type=submit]');
    button.disabled = true;
    try {
      const data = await api('/api/admit', { method: 'POST', body });
      const row = (data.sets[0] || [])[0];
      if (row) {
        document.getElementById('admit-result').innerHTML = `
          <div class="card-head"><h2>${icon('check')} Placed in the queue</h2></div>
          <div class="result">
            <div class="num">#${esc(row.Queue_Position)}<small>Position</small></div>
            <div>
              <h3>${esc(row.Patient_Name)}</h3>
              <div class="meta">${esi(row.ESI)}<span>${esc(row.Doctor_Name)} · ${esc(row.Doctor_Role)}</span><span>${esc(row.Department_Name)}</span></div>
              <div class="meta" style="margin-top:8px">${icon('clock')}<span>Estimated wait ${esc(row.Est_Wait_Time)} min · encounter ${esc(row.Encounter_ID)}</span></div>
            </div>
          </div>`;
        toast(`${row.Patient_Name} is ESI ${row.ESI} with ${row.Doctor_Name}, position ${row.Queue_Position}.`, true);
      }
      event.target.reset();
      await loadPatients();
    } catch (err) { toast(err.message); }
    button.disabled = false;
  };
}

function laneHtml(list) {
  const first = list[0];
  return `
    <section class="lane" data-doctor="${esc(first.Doctor_ID)}" data-dept="${esc(first.Department_Name)}">
      <div class="lane-head">
        <div><h3>${esc(first.Doctor_Name)}</h3><div class="dept">${esc(first.Department_Name)} · ${pill(first.Doctor_Status)}</div></div>
        <span class="n">${list.length}</span>
      </div>
      ${list.map((row) => `
        <button type="button" class="ticket e${esc(row.ESI)} ${Number(state.selectedEncounter) === Number(row.Encounter_ID) ? 'selected' : ''}" data-enc="${esc(row.Encounter_ID)}">
          <div class="pos">${esc(row.Queue_Position)}</div>
          <div class="pt-name"><b>${esc(row.Patient_Name)}</b><small title="${esc(row.Initial_Symptoms)}">${esc(row.Initial_Symptoms)}</small></div>
          <div class="right">${esi(row.ESI)}<small>${icon('clock')} wait ${esc(row.Est_Wait_Time)} min</small><small>arrived ${since(row.Arrival_Time)} ago</small></div>
        </button>`).join('')}
    </section>`;
}

function queueBoard(rows) {
  const groups = new Map();
  rows.forEach((row) => {
    if (!groups.has(row.Doctor_ID)) groups.set(row.Doctor_ID, []);
    groups.get(row.Doctor_ID).push(row);
  });
  if (!groups.size) return `<div class="card">${empty('The waiting room is empty.', 'inbox')}</div>`;
  return `<div class="board-wrap"><div class="lanes">${[...groups.values()].map(laneHtml).join('')}</div></div>`;
}

function reassessDrawer(row) {
  state.selectedEncounter = row.Encounter_ID;
  document.querySelectorAll('.ticket').forEach((el) => el.classList.toggle('selected', Number(el.dataset.enc) === Number(row.Encounter_ID)));
  openDrawer(esc(row.Patient_Name), `${esc(row.Doctor_Name)} · ${esc(row.Department_Name)} · encounter ${esc(row.Encounter_ID)}`, `
    <div class="facts">
      <div class="fact"><div class="k">Priority</div><div class="v">${esi(row.ESI)}</div></div>
      <div class="fact"><div class="k">Position</div><div class="v">#${esc(row.Queue_Position)}</div></div>
      <div class="fact"><div class="k">Arrived</div><div class="v">${fmtTime(row.Arrival_Time)} · ${since(row.Arrival_Time)} ago</div></div>
      <div class="fact"><div class="k">Estimated wait</div><div class="v">${esc(row.Est_Wait_Time)} min</div></div>
    </div>
    <div class="fact"><div class="k">Symptoms</div><div class="v" style="font-weight:500">${esc(row.Initial_Symptoms)}</div></div>
    <div class="divider"></div>
    <h3>Reassess with new vitals</h3>
    <form class="form-grid" id="reassess">
      <input type="hidden" name="encounter_id" value="${esc(row.Encounter_ID)}">
      ${vitalsFields()}
      <div class="wide actions"><button class="btn" type="submit">${icon('refresh')} Save and re-score</button></div>
    </form>
    <div class="divider"></div>
    <h3>Finish the visit</h3>
    <button class="btn ghost block" id="discharge" type="button">${icon('out')} Discharge ${esc(row.Patient_Name)}</button>
    <p class="muted" style="font-size:12.5px">Closes the visit and removes the patient from ${esc(row.Doctor_Name)}'s queue.</p>`);
  document.getElementById('reassess').onsubmit = async (event) => {
    event.preventDefault();
    const body = Object.fromEntries(new FormData(event.target));
    try {
      const data = await api('/api/reassess', { method: 'POST', body });
      const out = (data.sets[0] || [])[0];
      toast(out ? `${row.Patient_Name} is now ESI ${out.ESI}, position ${out.Queue_Position}.` : 'Reassessed.', true);
      closeDrawer();
      document.dispatchEvent(new Event('queue:refresh'));
    } catch (err) { toast(err.message); }
  };
  document.getElementById('discharge').onclick = async () => {
    try {
      await api('/api/discharge', { method: 'POST', body: { encounter_id: row.Encounter_ID } });
      toast(`${row.Patient_Name} discharged and removed from the queue.`, true);
      closeDrawer();
      document.dispatchEvent(new Event('queue:refresh'));
    } catch (err) { toast(err.message); }
  };
}

function pageQueue() {
  const token = state.pageToken;
  heading('Live queue', true);
  content(`<div id="qstats"></div><div id="board">${skeleton(3)}</div>`);
  let rows = [];
  async function refresh() {
    const data = await api('/api/queue');
    if (token !== state.pageToken) return;
    rows = data.rows;
    const snap = JSON.stringify(rows.map((row) => [row.Encounter_ID, row.Queue_Position, row.ESI]));
    const critical = rows.filter((row) => Number(row.ESI) <= 2).length;
    const doctors = new Set(rows.map((row) => row.Doctor_ID)).size;
    const longest = rows.reduce((max, row) => {
      const date = parseDate(row.Arrival_Time);
      return date ? Math.max(max, Math.round((Date.now() - date.getTime()) / 60000)) : max;
    }, 0);
    document.getElementById('qstats').innerHTML = stats([
      { k: 'Patients waiting', v: rows.length },
      { k: 'Critical (ESI 1–2)', v: critical, tone: critical ? 'danger' : '' },
      { k: 'Doctors with a queue', v: doctors, tone: 'accent' },
      { k: 'Longest time in queue', v: longest, unit: 'min' },
    ]);
    document.getElementById('board').innerHTML = queueBoard(rows);
    if (state.queueSnap && state.queueSnap !== snap) {
      document.querySelectorAll('.ticket').forEach((el) => el.classList.add('flash'));
    }
    state.queueSnap = snap;
    if (state.selectedEncounter && !rows.some((row) => Number(row.Encounter_ID) === Number(state.selectedEncounter))) {
      closeDrawer();
    }
    document.querySelectorAll('.ticket').forEach((el) => el.addEventListener('click', () => {
      const row = rows.find((item) => Number(item.Encounter_ID) === Number(el.dataset.enc));
      if (row) reassessDrawer(row);
    }));
    applyQueueFocus();
    tick();
  }
  watch(async () => {
    try { await refresh(); }
    catch (err) {
      if (!still(token) || err.cancelled) return;
      toast(err.message);
      content(`<div class="card">${empty(err.message, 'warn')}</div>`);
    }
  }, 3000);
  if (state.queueHandler) document.removeEventListener('queue:refresh', state.queueHandler);
  state.queueHandler = () => refresh().catch(() => {});
  document.addEventListener('queue:refresh', state.queueHandler);
}

async function pageAlerts() {
  const token = state.pageToken;
  const admin = state.role === 'admin';
  heading('Alerts');
  content(skeleton(3));
  const data = await api('/api/alerts').catch((err) => { toast(err.message); return { rows: [] }; });
  if (!still(token)) return;
  const rows = data.rows || [];
  const open = rows.filter((row) => !Number(row.Is_Resolved));
  const html = rows.length ? `<div class="alert-list">${rows.map((row) => `
    <div class="alert ${Number(row.Is_Resolved) ? 'resolved' : ''}">
      <div class="ic">${icon(Number(row.Is_Resolved) ? 'check' : 'warn')}</div>
      <div>
        <div class="msg">${esc(row.Message)}</div>
        <div class="when"><span class="tag ${Number(row.Is_Resolved) ? '' : 'warn'}">${esc(String(row.Alert_Type).replace('_', ' '))}</span><span>${fmtDateTime(row.Created_At)}</span>${row.Doctor_Name ? `<span>· ${esc(row.Doctor_Name)}</span>` : ''}${row.Department_Name ? `<span>· ${esc(row.Department_Name)}</span>` : ''}</div>
      </div>
      ${admin && !Number(row.Is_Resolved) ? `<button class="btn sm ghost" type="button" data-resolve="${esc(row.Alert_ID)}">${icon('check')} Resolve</button>` : (Number(row.Is_Resolved) ? '<span class="tag ok">Resolved</span>' : `<button class="tag warn open-alert" type="button" data-open="${esc(row.Alert_ID)}">Open</button>`)}
    </div>`).join('')}</div>` : `<div class="card">${empty('No alerts right now.', 'bell')}</div>`;
  content(`${rows.length ? `<div class="card-head" style="margin-bottom:12px"><div><h2>${open.length ? `${open.length} open` : 'All clear'}</h2><div class="sub">${rows.length} raised in total</div></div></div>` : ''}${html}`);
  document.querySelectorAll('[data-resolve]').forEach((btn) => btn.addEventListener('click', async () => {
    try {
      await api('/api/alerts/' + btn.dataset.resolve + '/resolve', { method: 'POST', body: {} });
      toast('Alert resolved.', true);
      pageAlerts();
    } catch (err) { toast(err.message); }
  }));
  document.querySelectorAll('[data-open]').forEach((btn) => btn.addEventListener('click', () => {
    const row = rows.find((item) => String(item.Alert_ID) === btn.dataset.open);
    if (!row) return;
    state.queueFocus = {
      doctorId: row.Doctor_ID || null,
      department: row.Department_Name || '',
    };
    state.page = 'queue';
    showPage();
  }));
}

function applyQueueFocus() {
  const focus = state.queueFocus;
  if (!focus) return;
  let first = null;
  document.querySelectorAll('.lane').forEach((lane) => {
    const hit = focus.doctorId
      ? Number(lane.dataset.doctor) === Number(focus.doctorId)
      : lane.dataset.dept === focus.department;
    lane.classList.toggle('focus', hit);
    if (hit && !first) first = lane;
  });
  if (first) first.scrollIntoView({ block: 'nearest', inline: 'center' });
}

/* ---------- Doctor ---------- */

async function pageMine() {
  const token = state.pageToken;
  heading('My queue', true);
  content(skeleton(3));
  const doctors = await api('/api/doctors').catch((err) => { toast(err.message); return { rows: [] }; });
  if (token !== state.pageToken) return;
  const list = doctors.rows;
  const onDuty = list.filter((row) => row.Current_Status !== 'Off_Duty');
  let current = (list.find((row) => row.Current_Status === 'Busy') || onDuty[0] || list[0] || {}).Doctor_ID;
  content(`
    <div class="card" style="margin-bottom:16px"><div class="chips" id="docs"></div></div>
    <div id="clinical">${skeleton(3)}</div>`);
  function paintChips() {
    document.getElementById('docs').innerHTML = list.map((row) => `
      <button type="button" class="chip ${Number(row.Doctor_ID) === Number(current) ? 'active' : ''}" data-doc="${esc(row.Doctor_ID)}">
        <span class="sd ${esc(row.Current_Status)}"></span>${esc(row.Doctor_Name)}<span class="muted" style="font-size:12px">${esc(row.Department_Name)}</span>
      </button>`).join('');
    document.querySelectorAll('[data-doc]').forEach((btn) => btn.addEventListener('click', () => {
      current = btn.dataset.doc;
      paintChips();
      refresh().catch((err) => toast(err.message));
    }));
  }
  async function refresh() {
    if (token !== state.pageToken) return;
    const host = document.getElementById('clinical');
    if (!host) return;
    if (!current) { host.innerHTML = `<div class="card">${empty('No doctors found.')}</div>`; return; }
    const data = await api('/api/clinical?doctor_id=' + encodeURIComponent(current));
    if (token !== state.pageToken) return;
    const doc = list.find((row) => Number(row.Doctor_ID) === Number(current)) || {};
    const rows = data.rows;
    const html = rows.length ? `<div class="pt-list">${rows.map((row) => `
      <article class="pt e${esc(row.ESI)}">
        <div class="pos">${esc(row.Queue_Position)}</div>
        <div>
          <div class="top">
            <div><b>${esc(row.Patient_Name)}</b><div class="sub">Age ${esc(row.Age)} · arrived ${fmtTime(row.Arrival_Time)} (${since(row.Arrival_Time)} ago) · vitals ${fmtTime(row.Vitals_At)}</div></div>
            <div class="actions">${esi(row.ESI)}<span class="tag">${icon('clock')} ${esc(row.Est_Wait_Time)} min</span></div>
          </div>
          <div class="sym">${esc(row.Initial_Symptoms)}</div>
          <div class="vitals">
            <div class="vt"><div class="k">Heart rate</div><div class="v">${esc(row.Heart_Rate)}<small>bpm</small></div></div>
            <div class="vt"><div class="k">SpO2</div><div class="v">${esc(row.SpO2)}<small>%</small></div></div>
            <div class="vt"><div class="k">BP</div><div class="v">${esc(row.Blood_Pressure)}</div></div>
            <div class="vt"><div class="k">Temp</div><div class="v">${esc(row.Temperature)}<small>°C</small></div></div>
            <div class="vt"><div class="k">Pain</div><div class="v">${esc(row.Pain_Scale)}<small>/10</small></div></div>
          </div>
        </div>
      </article>`).join('')}</div>` : `<div class="card">${empty(`${doc.Doctor_Name || 'This doctor'} has nobody waiting.`, 'inbox')}</div>`;
    const worst = rows.length ? Math.min(...rows.map((row) => Number(row.ESI))) : null;
    const box = document.getElementById('clinical');
    if (!box) return;
    box.innerHTML = `
      <div class="card-head" style="margin-bottom:12px"><div><h2>${esc(doc.Doctor_Name || '')}</h2>
        <div class="sub">${rows.length} waiting${worst ? ` · most critical ESI ${worst}` : ''} · ${esc(String(doc.Current_Status || '').replace('_', ' '))}</div></div>
      </div>${html}`;
    tick();
  }
  paintChips();
  watch(() => refresh().catch((err) => { if (still(token) && !err.cancelled) toast(err.message); }), 3000);
}

function pageSimilar() {
  const token = state.pageToken;
  heading('Similar cases');
  content(`
    <div class="card">
      <form class="toolbar" id="sim" style="margin-bottom:0">
        <div class="search" style="flex:1">${icon('search')}<input name="q" value="chest pain" required></div>
        <button class="btn" type="submit">Search</button>
      </form>
    </div>
    <div class="card" id="hits" style="margin-top:16px">${empty('Describe the presentation and search past and current encounters.', 'spark')}</div>`);
  document.getElementById('sim').onsubmit = async (event) => {
    event.preventDefault();
    const q = new FormData(event.target).get('q');
    document.getElementById('hits').innerHTML = skeleton(3);
    try {
      const data = await api('/api/similar?q=' + encodeURIComponent(q));
      if (!still(token)) return;
      const hits = document.getElementById('hits');
      if (!hits) return;
      hits.innerHTML = data.rows.length
        ? table(data.rows, [['Relevance', 'Relevance'], ['Patient_Name', 'Patient'], ['Initial_Symptoms', 'Symptoms'], ['ESI', 'ESI'], ['Department', 'Department'], ['Doctor_Name', 'Doctor'], ['Arrival_Time', 'Arrived'], ['Status', 'Status']])
        : empty(`No encounter matches “${q}”.`, 'search');
    } catch (err) {
      if (!still(token) || err.cancelled) return;
      toast(err.message);
      const hits = document.getElementById('hits');
      if (hits) hits.innerHTML = empty(err.message, 'warn');
    }
  };
}

/* ---------- Admin ---------- */

function chart(canvas, config) {
  const item = new Chart(canvas, config);
  state.charts.push(item);
}

const FONT = '"Plus Jakarta Sans", system-ui, sans-serif';
const TICKS = { color: '#8a8a93', font: { family: FONT, size: 11 } };
const ORANGES = ['#ff8a3d', '#ffa461', '#ffc08a', '#ffdcbd', '#ffe9d6'];
const CHART_DEFAULTS = {
  maintainAspectRatio: false,
  plugins: { legend: { display: false } },
  scales: {
    x: { grid: { display: false }, border: { display: false }, ticks: TICKS },
    y: { grid: { color: '#f0f0f3' }, border: { display: false }, ticks: { ...TICKS, precision: 0 } },
  },
};

async function pageDashboard() {
  const token = state.pageToken;
  heading('Department dashboard', true);
  let view = 'dept';
  let data = null;
  const chartTitle = { dept: 'Waiting by department', esi: 'Queue by ESI', hours: 'Arrivals by hour' };
  content(`<div id="dstats"></div>
    <div class="card" style="margin-bottom:18px">
      <div class="card-head"><h2 id="ctitle">${chartTitle.dept}</h2>
        <div class="card-tabs" id="ctabs">
          <button type="button" data-v="dept" class="active">Departments</button>
          <button type="button" data-v="esi">ESI</button>
          <button type="button" data-v="hours">Arrivals</button>
        </div>
      </div>
      <div class="chart-box tall"><canvas id="c1"></canvas></div>
    </div>
    <div class="card tight"><div class="card-head"><h2>Doctor workload</h2></div><div id="work"></div></div>`);
  function paintChart() {
    if (!data) return;
    state.charts.forEach((item) => item.destroy());
    state.charts = [];
    document.getElementById('ctitle').textContent = chartTitle[view];
    const canvas = document.getElementById('c1');
    if (view === 'dept') {
      chart(canvas, {
        type: 'bar',
        data: { labels: data.load.map((row) => row.Department), datasets: [{ data: data.load.map((row) => Number(row.Patients_Waiting)), backgroundColor: data.load.map((row, i) => ORANGES[Math.min(i, ORANGES.length - 1)]), borderRadius: 8, barPercentage: .5 }] },
        options: CHART_DEFAULTS,
      });
    } else if (view === 'esi') {
      chart(canvas, {
        type: 'doughnut',
        data: { labels: data.esi.map((row) => 'ESI ' + row.ESI), datasets: [{ data: data.esi.map((row) => Number(row.Patients_Waiting)), backgroundColor: data.esi.map((row) => ({ 1: '#e0462f', 2: '#ff8a3d', 3: '#f2b705', 4: '#9acd4c', 5: '#1f9d5b' }[row.ESI])), borderWidth: 3, borderColor: '#ffffff', borderRadius: 6 }] },
        options: { maintainAspectRatio: false, cutout: '70%', plugins: { legend: { position: 'right', labels: { boxWidth: 8, boxHeight: 8, usePointStyle: true, color: '#3b3b40', font: { family: FONT, size: 12 }, padding: 14 } } } },
      });
    } else {
      chart(canvas, {
        type: 'bar',
        data: { labels: data.hours.map((row) => String(row.Hour_Of_Day).padStart(2, '0') + ':00'), datasets: [{ data: data.hours.map((row) => Number(row.Arrivals)), backgroundColor: '#ffc08a', hoverBackgroundColor: '#ff8a3d', borderRadius: 8, barPercentage: .5 }] },
        options: CHART_DEFAULTS,
      });
    }
  }
  document.querySelectorAll('#ctabs button').forEach((btn) => btn.onclick = () => {
    view = btn.dataset.v;
    document.querySelectorAll('#ctabs button').forEach((b) => b.classList.toggle('active', b === btn));
    paintChart();
  });
  async function refresh() {
    data = await api('/api/dashboard');
    if (!still(token) || !document.getElementById('dstats')) return;
    const waiting = data.load.reduce((sum, row) => sum + Number(row.Patients_Waiting || 0), 0);
    const critical = data.load.reduce((sum, row) => sum + Number(row.Critical_Waiting || 0), 0);
    const onDuty = data.workload.filter((row) => row.Current_Status !== 'Off_Duty').length;
    document.getElementById('dstats').innerHTML = stats([
      { k: 'Patients waiting', v: waiting },
      { k: 'Critical waiting', v: critical, tone: critical ? 'danger' : '' },
      { k: 'Doctors on duty', v: onDuty, unit: `of ${data.workload.length}`, tone: 'accent' },
      { k: 'Departments with a queue', v: data.load.filter((row) => Number(row.Patients_Waiting) > 0).length },
    ]);
    paintChart();
    document.getElementById('work').innerHTML = table(data.workload, [
      ['Doctor_Name', 'Doctor'], ['Doctor_Role', 'Role'], ['Department_Name', 'Department'], ['Current_Status', 'Status'],
      ['Active_Patients', 'Waiting'], ['Avg_ESI', 'Avg ESI'], ['Most_Critical_ESI', 'Most critical'],
    ]);
    tick();
  }
  watch(() => refresh().catch((err) => { if (!err.cancelled) toast(err.message); }), 10000);
}

async function pageVisits() {
  const token = state.pageToken;
  heading('Visits');
  content(skeleton(4));
  const data = await api('/api/visits').catch((err) => { toast(err.message); return { rows: [] }; });
  if (!still(token)) return;
  const rows = data.rows;
  const active = rows.filter((row) => row.Status === 'Active').length;
  function paint(filter = '') {
    const q = filter.trim().toLowerCase();
    const shown = q ? rows.filter((row) => JSON.stringify(row).toLowerCase().includes(q)) : rows;
    document.getElementById('vt').innerHTML = table(shown, [
      ['Encounter_ID', 'Visit'], ['Patient_Name', 'Patient'], ['Phone', 'Phone'], ['Email', 'Email'], ['Doctor_Name', 'Doctor'],
      ['Department_Name', 'Department'], ['Arrival_Time', 'Arrived'], ['Check_out_Time', 'Checked out'], ['Status', 'Status'], ['Length_Of_Stay_Min', 'Stay (min)'],
    ]);
  }
  content(`${stats([{ k: 'Visits recorded', v: rows.length }, { k: 'Currently active', v: active, tone: 'accent' }, { k: 'Discharged', v: rows.length - active }])}
    <div class="card tight">
      <div class="card-head"><h2>All visits</h2>
        <div class="search" style="min-width:260px;position:relative">${icon('search')}<input id="vfilter" placeholder="Filter by name, doctor, department" style="padding-left:36px"></div></div>
      <div id="vt"></div>
    </div>`);
  paint();
  document.getElementById('vfilter').oninput = (event) => paint(event.target.value);
}

function pageReports() {
  heading('Reports');
  const today = localDate(new Date());
  const week = localDate(new Date(Date.now() - 6 * 86400000));
  const titles = {
    daily: ['Summary', 'ESI mix', 'Departments', 'Doctors above the average'],
    weekly: ['Daily arrivals', 'ESI totals', 'Departments with more than one arrival'],
    doctor: ['Compared with the hospital', 'Visits', 'Score changes'],
  };
  let kind = 'daily';
  const results = {};
  const prompt = empty('Pick a period and run the report.', 'chart');
  content(`
    <div class="tabs" id="rtabs">
      <button type="button" data-k="daily" class="active">Daily</button>
      <button type="button" data-k="weekly">Weekly</button>
      <button type="button" data-k="doctor">Doctor</button>
    </div>
    <div class="card"><form class="toolbar" id="rform" style="margin-bottom:0"></form></div>
    <div id="report" class="stack" style="margin-top:16px">${prompt}</div>`);
  let doctorOptions = '<option value="">Loading…</option>';
  api('/api/doctors').then((data) => {
    doctorOptions = data.rows.map((row) => `<option value="${esc(row.Doctor_ID)}">${esc(row.Doctor_Name)} · ${esc(row.Department_Name)}</option>`).join('');
    if (kind === 'doctor') paintForm();
  }).catch(() => {});
  function paintForm() {
    const form = document.getElementById('rform');
    if (kind === 'daily') form.innerHTML = `<label>Date<input type="date" name="date" value="${today}"></label><button class="btn" type="submit">${icon('play')} Run report</button>`;
    if (kind === 'weekly') form.innerHTML = `<label>Week starting<input type="date" name="start" value="${week}"></label><button class="btn" type="submit">${icon('play')} Run report</button>`;
    if (kind === 'doctor') form.innerHTML = `
      <label>Doctor<select name="doctor_id">${doctorOptions}</select></label>
      <label>From<input type="date" name="from" value="${week}"></label>
      <label>To<input type="date" name="to" value="${today}"></label>
      <button class="btn" type="submit">${icon('play')} Run report</button>`;
  }
  paintForm();
  document.querySelectorAll('#rtabs button').forEach((btn) => btn.onclick = () => {
    kind = btn.dataset.k;
    document.querySelectorAll('#rtabs button').forEach((b) => b.classList.toggle('active', b === btn));
    paintForm();
    document.getElementById('report').innerHTML = results[kind] || prompt;
  });
  document.getElementById('rform').onsubmit = async (event) => {
    event.preventDefault();
    const body = new FormData(event.target);
    let url = '';
    if (kind === 'daily') url = '/api/reports/daily?date=' + body.get('date');
    if (kind === 'weekly') url = '/api/reports/weekly?start=' + body.get('start');
    if (kind === 'doctor') url = `/api/reports/doctor?doctor_id=${body.get('doctor_id')}&from=${body.get('from')}&to=${body.get('to')}`;
    document.getElementById('report').innerHTML = skeleton(3);
    try {
      const data = await api(url);
      const sets = data.sets || [];
      const ran = kind;
      results[ran] = sets.length
        ? sets.map((rows, index) => `<div class="card tight"><div class="card-head"><h2>${esc(titles[ran][index] || 'Result ' + (index + 1))}</h2></div>${table(rows)}</div>`).join('')
        : `<div class="card">${empty('The procedure returned no rows for that period.')}</div>`;
      if (kind === ran) document.getElementById('report').innerHTML = results[ran];
    } catch (err) { toast(err.message); document.getElementById('report').innerHTML = `<div class="card">${empty(err.message, 'warn')}</div>`; }
  };
}

async function pageRoster() {
  const token = state.pageToken;
  heading('Shift roster');
  content(skeleton(3));
  const fromS = localDate(new Date());
  const toS = localDate(new Date(Date.now() + 6 * 86400000));
  let pack;
  try {
    pack = await Promise.all([
      api(`/api/roster?from=${fromS}&to=${toS}`),
      api('/api/doctors'),
      api('/api/meta'),
    ]);
  } catch (err) {
    if (!still(token) || err.cancelled) return;
    toast(err.message);
    content(`<div class="card">${empty(err.message, 'warn')}</div>`);
    return;
  }
  if (!still(token)) return;
  const [roster, doctors, meta] = pack;
  const days = [];
  for (let i = 0; i < 7; i += 1) days.push(localDate(new Date(Date.now() + i * 86400000)));
  const byDay = new Map(days.map((d) => [d, new Map()]));
  roster.rows.forEach((row) => {
    const d = String(row.Shift_Date).slice(0, 10);
    if (!byDay.has(d)) byDay.set(d, new Map());
    const shifts = byDay.get(d);
    if (!shifts.has(row.Shift_Name)) shifts.set(row.Shift_Name, { start: row.Start_Time, end: row.End_Time, docs: [] });
    shifts.get(row.Shift_Name).docs.push(row);
  });
  const shiftOrder = meta.shifts.map((s) => s.Shift_Name);
  content(`
    <div class="card" style="margin-bottom:16px">
      <form class="toolbar" id="assign" style="margin-bottom:0">
        <label>Doctor<select name="doctor_id">${doctors.rows.map((row) => `<option value="${esc(row.Doctor_ID)}">${esc(row.Doctor_Name)} · ${esc(row.Department_Name)}</option>`).join('')}</select></label>
        <label>Shift<select name="shift_id">${meta.shifts.map((row) => `<option value="${esc(row.Shift_ID)}">${esc(row.Shift_Name)} ${esc(String(row.Start_Time).slice(0, 5))}–${esc(String(row.End_Time).slice(0, 5))}</option>`).join('')}</select></label>
        <label>Date<input type="date" name="shift_date" value="${fromS}" required></label>
        <button class="btn" type="submit">${icon('plus')} Assign shift</button>
      </form>
    </div>
    <div class="cal">${days.map((d) => {
      const date = new Date(d + 'T00:00:00');
      const shifts = byDay.get(d) || new Map();
      const keys = [...shifts.keys()].sort((a, b) => shiftOrder.indexOf(a) - shiftOrder.indexOf(b));
      return `<div class="day ${d === fromS ? 'today' : ''}">
        <div class="d"><small>${date.toLocaleDateString([], { weekday: 'short' })}</small>${date.toLocaleDateString([], { day: 'numeric', month: 'short' })}</div>
        ${keys.length ? keys.map((k) => `<div class="shift-block"><div class="sh">${esc(k)} · ${esc(String(shifts.get(k).start).slice(0, 5))}</div>
          ${shifts.get(k).docs.map((row) => `<div class="doc"><span style="color:var(--ink);font-weight:600">${esc(String(row.Doctor_Name).replace(/^Dr\.?\s*/, ''))}</span><span>${esc(row.Department_Name)}</span></div>`).join('')}</div>`).join('')
          : '<div class="muted" style="font-size:12.5px">No shifts</div>'}
      </div>`;
    }).join('')}</div>`);
  document.getElementById('assign').onsubmit = async (event) => {
    event.preventDefault();
    try {
      await api('/api/shifts', { method: 'POST', body: Object.fromEntries(new FormData(event.target)) });
      toast('Shift assigned.', true);
      pageRoster();
    } catch (err) { toast(err.message); }
  };
}

async function pagePeople() {
  const token = state.pageToken;
  heading('People');
  content(skeleton(4));
  const [doctors, meta] = await Promise.all([api('/api/doctors'), api('/api/meta')]).catch((err) => { toast(err.message); return [{ rows: [] }, { departments: [], patients: [], deleted: [] }]; });
  if (!still(token)) return;
  let tab = 'doctors';
  let filter = '';
  content(`
    <div class="toolbar" style="justify-content:space-between;align-items:center">
      <div class="tabs" id="ptabs" style="margin:0">
        <button type="button" data-t="doctors" class="active">Doctors <span class="count">${doctors.rows.length}</span></button>
        <button type="button" data-t="patients">Patients <span class="count">${meta.patients.length}</span></button>
        <button type="button" data-t="deleted">Deleted <span class="count">${meta.deleted.length}</span></button>
      </div>
      <div class="search" style="width:280px">${icon('search')}<input id="pfilter" placeholder="Filter list"></div>
    </div>
    <div class="grid two">
      <div class="card" id="plist"></div>
      <div class="card">
        <div class="card-head"><h2>Add</h2>
          <div class="card-tabs" id="addtabs">
            <button type="button" data-f="add-doc" class="active">Doctor</button>
            <button type="button" data-f="add-dep">Department</button>
          </div>
        </div>
        <form class="stack" id="add-doc">
          <label>Name<input name="name" placeholder="Dr. Name" required></label>
          <div class="form-grid">
            <label>Role<select name="role"><option>Junior Doctor</option><option>Resident</option><option>Consultant</option><option>Senior Consultant</option></select></label>
            <label>Department<select name="department_id">${meta.departments.map((row) => `<option value="${esc(row.Department_ID)}">${esc(row.Name)}</option>`).join('')}</select></label>
          </div>
          <label>Specialization<input name="specialization" placeholder="Trauma" required></label>
          <button class="btn" type="submit" style="margin-top:6px">${icon('plus')} Add doctor</button>
          <p class="muted" style="font-size:12px;text-align:center">New doctors are off duty until a shift is assigned.</p>
        </form>
        <form class="stack hidden" id="add-dep">
          <label>Name<input name="name" placeholder="Neurology" required></label>
          <label>Description<input name="description" placeholder="optional"></label>
          <button class="btn" type="submit" style="margin-top:6px">${icon('plus')} Add department</button>
        </form>
      </div>
    </div>`);
  document.querySelectorAll('#addtabs button').forEach((btn) => btn.onclick = () => {
    document.querySelectorAll('#addtabs button').forEach((b) => b.classList.toggle('active', b === btn));
    document.getElementById('add-doc').classList.toggle('hidden', btn.dataset.f !== 'add-doc');
    document.getElementById('add-dep').classList.toggle('hidden', btn.dataset.f !== 'add-dep');
  });
  function paintList() {
    const q = filter.toLowerCase();
    const host = document.getElementById('plist');
    if (tab === 'doctors') {
      const rows = doctors.rows.filter((row) => !q || `${row.Doctor_Name} ${row.Department_Name} ${row.Doctor_Role}`.toLowerCase().includes(q));
      host.innerHTML = rows.length ? rows.map((row) => `
        <div class="person"><div class="l"><div class="av">${esc(initials(row.Doctor_Name))}</div><div><b>${esc(row.Doctor_Name)}</b><div class="sub"><span>${esc(row.Doctor_Role)}</span><span>· ${esc(row.Department_Name)}</span>${pill(row.Current_Status)}</div></div></div>
        <button class="btn sm danger" data-del-doc="${esc(row.Doctor_ID)}">${icon('trash')} Delete</button></div>`).join('') : empty('No doctors match.');
    }
    if (tab === 'patients') {
      const rows = meta.patients.filter((row) => !q || `${row.Name} ${row.Phone}`.toLowerCase().includes(q));
      host.innerHTML = rows.length ? rows.map((row) => `
        <div class="person"><div class="l"><div class="av">${esc(initials(row.Name))}</div><div><b>${esc(row.Name)}</b><div class="sub"><span>${esc(row.Phone)}</span>${row.Email ? `<span>· ${esc(row.Email)}</span>` : ''}</div></div></div>
        <button class="btn sm danger" data-del-pat="${esc(row.Patient_ID)}">${icon('trash')} Delete</button></div>`).join('') : empty('No patients match.');
    }
    if (tab === 'deleted') {
      const rows = meta.deleted.filter((row) => !q || `${row.Name} ${row.Person_Type}`.toLowerCase().includes(q));
      host.innerHTML = rows.length ? rows.map((row) => `
        <div class="person"><div class="l"><div class="av">${esc(initials(row.Name))}</div><div><b>${esc(row.Name)}</b><div class="sub"><span class="tag">${esc(row.Person_Type)}</span><span>deleted ${fmtDateTime(row.Deleted_At)}</span></div></div></div>
        <button class="btn sm ghost" data-restore="${esc(row.Person_Type)}:${esc(row.Person_ID)}">${icon('undo')} Restore</button></div>`).join('') : empty('Nobody is deleted.', 'check');
    }
    async function act(path) {
      try { await api(path, { method: 'POST', body: {} }); toast('Saved.', true); pagePeople(); }
      catch (err) { toast(err.message); }
    }
    host.querySelectorAll('[data-del-doc]').forEach((btn) => btn.onclick = () => act('/api/people/doctor/' + btn.dataset.delDoc + '/delete'));
    host.querySelectorAll('[data-del-pat]').forEach((btn) => btn.onclick = () => act('/api/people/patient/' + btn.dataset.delPat + '/delete'));
    host.querySelectorAll('[data-restore]').forEach((btn) => btn.onclick = () => {
      const [kind, id] = btn.dataset.restore.split(':');
      act('/api/people/' + kind.toLowerCase() + '/' + id + '/restore');
    });
  }
  paintList();
  document.querySelectorAll('#ptabs button').forEach((btn) => btn.onclick = () => {
    tab = btn.dataset.t;
    document.querySelectorAll('#ptabs button').forEach((b) => b.classList.toggle('active', b === btn));
    paintList();
  });
  document.getElementById('pfilter').oninput = (event) => { filter = event.target.value; paintList(); };
  document.getElementById('add-doc').onsubmit = async (event) => {
    event.preventDefault();
    try {
      await api('/api/doctors', { method: 'POST', body: Object.fromEntries(new FormData(event.target)) });
      toast('Doctor added. Status stays Off duty until a shift is assigned.', true);
      pagePeople();
    } catch (err) { toast(err.message); }
  };
  document.getElementById('add-dep').onsubmit = async (event) => {
    event.preventDefault();
    try {
      await api('/api/departments', { method: 'POST', body: Object.fromEntries(new FormData(event.target)) });
      toast('Department added.', true);
      pagePeople();
    } catch (err) { toast(err.message); }
  };
}

const CONFIG_LABEL = {
  audit_archive_days: 'Audit retention (days)',
  default_consult_minutes: 'Default consultation (minutes)',
  dept_critical_threshold: 'Department critical limit',
  doctor_queue_threshold: 'Doctor queue limit',
};

const CONFIG_HELP = {
  audit_archive_days: 'Audit entries older than this are archived once a month.',
  default_consult_minutes: 'Used for wait estimates when a doctor has no visit history yet.',
  dept_critical_threshold: 'Alert when more critical patients than this are waiting in one department.',
  doctor_queue_threshold: 'Alert when one doctor has more patients than this waiting.',
};

async function pageSettings() {
  const token = state.pageToken;
  heading('Policies');
  content(skeleton(2));
  const meta = await api('/api/meta').catch((err) => { toast(err.message); return { config: [], aging: [] }; });
  if (!still(token)) return;
  if (!meta.config || !meta.aging) {
    content(`<div class="card">${empty('Policies could not be loaded.', 'warn')}</div>`);
    return;
  }
  content(`
    <div class="grid even">
      <form class="card" id="cfg">
        <div class="card-head"><h2>${icon('sliders')} Thresholds</h2><button class="btn sm" type="submit">Save</button></div>
        ${meta.config.map((row) => `<div class="kv"><div><div class="k">${esc(CONFIG_LABEL[row.Config_Key] || row.Config_Key)}</div><div class="d">${esc(CONFIG_HELP[row.Config_Key] || '')}</div></div><input name="${esc(row.Config_Key)}" value="${esc(row.Config_Value)}"></div>`).join('')}
      </form>
      <form class="card" id="age">
        <div class="card-head"><div><h2>${icon('clock')} Aging</h2><div class="sub">Minutes a patient may wait before being moved up one level.</div></div><button class="btn sm" type="submit">Save</button></div>
        ${meta.aging.map((row) => `<div class="kv"><div><div class="k">${esi(row.ESI_Level)}</div></div><input name="esi-${esc(row.ESI_Level)}" value="${esc(row.Max_Wait_Minutes)}"></div>`).join('')}
        <div class="actions" style="margin-top:18px">
          <button class="btn" id="run-age" type="button">${icon('play')} Run aging now</button>
          <button class="btn ghost" id="pause-age" type="button">${icon('pause')} Pause</button>
          <button class="btn ghost" id="resume-age" type="button">${icon('play')} Resume</button>
        </div>
      </form>
    </div>
    <div id="aged" style="margin-top:16px"></div>`);
  document.getElementById('cfg').onsubmit = async (event) => {
    event.preventDefault();
    const body = Object.fromEntries(new FormData(event.target));
    try {
      for (const [key, value] of Object.entries(body)) await api('/api/config', { method: 'POST', body: { key, value } });
      toast('Thresholds saved.', true);
    } catch (err) { toast(err.message); }
  };
  document.getElementById('age').onsubmit = async (event) => {
    event.preventDefault();
    const body = Object.fromEntries(new FormData(event.target));
    try {
      for (const [key, value] of Object.entries(body)) await api('/api/aging', { method: 'POST', body: { esi: Number(key.split('-')[1]), minutes: Number(value) } });
      toast('Aging policy saved.', true);
    } catch (err) { toast(err.message); }
  };
  document.getElementById('run-age').onclick = async () => {
    try {
      const data = await api('/api/aging/run', { method: 'POST', body: {} });
      const rows = data.sets[0] || [];
      document.getElementById('aged').innerHTML = `<div class="card tight"><div class="card-head"><div><h2>Escalated this run</h2><div class="sub">${rows.length ? 'These patients were moved up one level.' : 'Nobody was past their limit.'}</div></div></div>${table(rows, [['Encounter_ID', 'Encounter'], ['Patient_Name', 'Patient'], ['Old_ESI', 'Was'], ['New_ESI', 'Now']])}</div>`;
      toast(rows.length ? `${rows.length} patient${rows.length > 1 ? 's' : ''} escalated and the queue was rebuilt.` : 'Nobody was past their limit.', true);
    } catch (err) { toast(err.message); }
  };
  document.getElementById('pause-age').onclick = async () => {
    try { await api('/api/aging/toggle', { method: 'POST', body: { on: false } }); toast('Automatic aging paused.', true); } catch (err) { toast(err.message); }
  };
  document.getElementById('resume-age').onclick = async () => {
    try { await api('/api/aging/toggle', { method: 'POST', body: { on: true } }); toast('Automatic aging resumed.', true); } catch (err) { toast(err.message); }
  };
}

/* ---------- Auditor ---------- */

function pageAudit() {
  const token = state.pageToken;
  heading('Audit log');
  content(`
    <div class="card">
      <form class="toolbar" id="filt" style="margin-bottom:0">
        <label>Table<input name="table" placeholder="Wait_List"></label>
        <label>Action<select name="action"><option value="">Any</option><option>INSERT</option><option>UPDATE</option><option>DELETE</option></select></label>
        <label>From<input type="date" name="from"></label>
        <label>To<input type="date" name="to"></label>
        <button class="btn" type="submit">${icon('search')} Filter</button>
      </form>
    </div>
    <div class="card tight" id="log" style="margin-top:16px">${skeleton(4)}</div>`);
  async function load(params = '') {
    const data = await api('/api/audit' + params);
    if (!still(token)) return;
    const log = document.getElementById('log');
    if (!log) return;
    log.innerHTML = `<div class="card-head"><div><h2>Latest ${data.rows.length} changes</h2><div class="sub">Newest first</div></div></div>${table(data.rows, [
      ['Audit_ID', 'ID'], ['Changed_At', 'When'], ['Table_Name', 'Table'], ['Record_ID', 'Record'],
      ['Action', 'Action'], ['Changed_By', 'User'], ['Old_Data', 'Before'], ['New_Data', 'After'],
    ])}`;
  }
  load().catch((err) => {
    if (!still(token) || err.cancelled) return;
    toast(err.message);
    const log = document.getElementById('log');
    if (log) log.innerHTML = empty(err.message, 'warn');
  });
  document.getElementById('filt').onsubmit = async (event) => {
    event.preventDefault();
    const qs = new URLSearchParams(Object.fromEntries(new FormData(event.target))).toString();
    document.getElementById('log').innerHTML = skeleton(4);
    try { await load('?' + qs); } catch (err) { toast(err.message); document.getElementById('log').innerHTML = empty(err.message, 'warn'); }
  };
}

async function pageScores() {
  const token = state.pageToken;
  heading('Score ledger');
  content(skeleton(4));
  const data = await api('/api/score-audit').catch((err) => { toast(err.message); return { rows: [] }; });
  if (!still(token)) return;
  const escalated = data.rows.filter((row) => /Escalated/i.test(row.History_Notes || '')).length;
  content(`${stats([{ k: 'Score events', v: data.rows.length }, { k: 'Aging escalations', v: escalated, tone: escalated ? 'danger' : '' }])}
    <div class="card tight">${table(data.rows, [['History_ID', 'ID'], ['History_At', 'When'], ['Patient_Name', 'Patient'], ['Encounter_ID', 'Encounter'], ['Old_Score', 'Was'], ['New_Score', 'Now'], ['History_Notes', 'Reason']])}</div>`);
}

boot();
