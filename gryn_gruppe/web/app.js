/* gryn_gruppe NUI: tablet (Overview / Progress / Jobs), black market, invite prompt, thermite minigame.
   All data comes from the server through client/*.lua; this file only draws it and posts what was clicked. */

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'gryn_gruppe';
const $ = (sel) => document.querySelector(sel);

async function post(name, body = {}) {
    try {
        const res = await fetch(`https://${RES}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body),
        });
        return await res.json();
    } catch (e) {
        return null;
    }
}

/* ---------- Icons (inline SVG, stroke style) ---------- */

const ICONS = {
    overview: '<path d="M3 3v18h18"/><path d="M7 16v-5M12 16V8M17 16v-8"/>',
    progress: '<circle cx="12" cy="8" r="6"/><path d="M15.5 13.5 17 22l-5-3-5 3 1.5-8.5"/>',
    jobs: '<path d="M10 17h4V5H2v12h3"/><path d="M14 9h4l4 4v4h-3"/><circle cx="7.5" cy="17.5" r="2.5"/><circle cx="16.5" cy="17.5" r="2.5"/>',
    exit: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5"/><path d="M21 12H9"/>',
    user: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
    briefcase: '<rect x="2" y="7" width="20" height="14" rx="2"/><path d="M16 7V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v2"/>',
    zap: '<path d="M13 2 3 14h9l-1 8 10-12h-9l1-8z"/>',
    dollar: '<path d="M12 2v20"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/>',
    gift: '<rect x="3" y="8" width="18" height="4" rx="1"/><path d="M12 8v13"/><path d="M19 12v7a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-7"/><path d="M7.5 8a2.5 2.5 0 0 1 0-5C11 3 12 8 12 8s1-5 4.5-5a2.5 2.5 0 0 1 0 5"/>',
    lock: '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    x: '<path d="M18 6 6 18M6 6l12 12"/>',
    crown: '<path d="m2 7 5 4 5-7 5 7 5-4-2 12H4z"/>',
    userPlus: '<circle cx="9" cy="8" r="4"/><path d="M2 21a7 7 0 0 1 14 0"/><path d="M19 8v6M16 11h6"/>',
    arrow: '<path d="M5 12h14M13 6l6 6-6 6"/>',
    shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
    star: '<path d="m12 2 3.1 6.3 6.9 1-5 4.9 1.2 6.8L12 17.8 5.8 21l1.2-6.8-5-4.9 6.9-1z"/>',
    box: '<path d="M21 8 12 3 3 8v8l9 5 9-5z"/><path d="M3 8l9 5 9-5M12 13v8"/>',
    bag: '<path d="M9 3h6l-2 4h-2z"/><path d="M8 8h8c3 3 4 6 4 9a4 4 0 0 1-4 4H8a4 4 0 0 1-4-4c0-3 1-6 4-9z"/>',
    flame: '<path d="M12 22c4 0 7-3 7-7 0-5-5-7-5-12-3 2-5 5-5 8-1-1-2-2-2-4-2 2-2 5-2 8 0 4 3 7 7 7z"/>',
    refresh: '<path d="M21 12a9 9 0 1 1-3-6.7L21 8"/><path d="M21 3v5h-5"/>',
    pin: '<path d="M12 22s7-6.2 7-12a7 7 0 0 0-14 0c0 5.8 7 12 7 12z"/><circle cx="12" cy="10" r="2.5"/>',
};
const icon = (name) => `<svg class="i" viewBox="0 0 24 24">${ICONS[name] || ''}</svg>`;

const UNLOCK_ICON = { task: 'briefcase', vehicle: 'jobs', item: 'box', money: 'dollar', xp: 'zap', cooldown: 'clock' };

/* ---------- Formatting ---------- */

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const money = (n) => '$' + Math.floor(n || 0).toLocaleString('en-US');
const num = (n) => Math.floor(n || 0).toLocaleString('en-US');

function dur(sec) {
    sec = Math.max(0, Math.ceil(sec));
    const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
    if (h > 0) return `${h}h ${String(m).padStart(2, '0')}m`;
    if (m > 0) return `${m}m ${String(s).padStart(2, '0')}s`;
    return `${s}s`;
}

// Live countdowns: <span data-until="epoch ms" data-done="text">
const until = (sec, doneText = 'Ready') =>
    `<span data-until="${Date.now() + sec * 1000}" data-done="${esc(doneText)}">${sec > 0 ? dur(sec) : esc(doneText)}</span>`;

setInterval(() => {
    document.querySelectorAll('[data-until]').forEach((el) => {
        const left = (Number(el.dataset.until) - Date.now()) / 1000;
        el.textContent = left > 0 ? dur(left) : el.dataset.done;
    });
}, 1000);

function greeting() {
    const h = new Date().getHours();
    return h < 12 ? 'Good Morning' : h < 18 ? 'Good Afternoon' : 'Good Evening';
}

/* ---------- Tablet ---------- */

const T = { data: null, page: 'overview', task: null, nearby: null, busy: false };

function initials(name) {
    return String(name || '?').split(/\s+/).map((p) => p[0]).join('').slice(0, 2).toUpperCase();
}

function renderTablet() {
    const d = T.data;
    if (!d) return;
    const p = d.player;

    document.querySelectorAll('.rail-btn[data-page]').forEach((b) => {
        b.innerHTML = icon(b.dataset.page);
        b.classList.toggle('active', b.dataset.page === T.page);
    });
    $('.rail-exit').innerHTML = icon('exit');

    const status = d.job
        ? `<span class="chip good"><span class="dot"></span>On a job</span>`
        : p.cooldown > 0
            ? `<div class="pill"><span class="k">Cooldown</span><span class="v">${until(p.cooldown)}</span></div>`
            : `<span class="chip good"><span class="dot"></span>Ready for dispatch</span>`;

    $('#topbar').innerHTML = `
        <div class="avatar">${icon('user')}</div>
        <div class="welcome">Welcome, <b>${esc(p.name)}</b></div>
        <span class="chip"><span class="dot"></span>Gruppe 6 Security</span>
        <div class="spacer"></div>
        ${status}
        <div class="pill"><span class="k">Level</span><span class="v">${p.level}</span></div>
        <div class="pill"><span class="k">Rep</span><span class="v">${num(p.reputation)}</span></div>`;

    const page = { overview: renderOverview, progress: renderProgress, jobs: renderJobs }[T.page];
    $('#page').innerHTML = page(d);
}

function levelBar(p) {
    const max = p.level >= p.maxLevel;
    const pct = max ? 100 : Math.min(100, (p.xpInto / Math.max(1, p.xpNeeded)) * 100);
    return `
        <div class="bar"><i style="width:${pct}%"></i></div>
        <div class="bar-meta">
            ${max ? '<span><b>Max level</b></span><span></span>'
                  : `<span><b>${num(p.xpInto)}</b> / ${num(p.xpNeeded)} XP</span><span>${num(p.xpNeeded - p.xpInto)} XP to level ${p.level + 1}</span>`}
        </div>`;
}

function renderOverview(d) {
    const p = d.player;
    const first = String(p.name).split(' ')[0];
    const dailyReady = p.dailyLeft <= 0;

    return `
        <div class="hello">
            <h1>${greeting()}, <span>${esc(first)}</span></h1>
            <p>Move the money, keep it safe, and bring the Stockade home.</p>
        </div>
        <div class="layout">
            <div class="col">
                <div class="card hero">
                    <div>
                        <div class="eyebrow">Current level</div>
                        <div class="big">Level ${p.level}<small>of ${p.maxLevel}</small></div>
                        ${levelBar(p)}
                    </div>
                    <div class="hero-stats">
                        <div><div class="eyebrow">Money bonus</div><div class="v accent">+${p.moneyBonus}%</div><div class="n">From your level</div></div>
                        <div><div class="eyebrow">XP bonus</div><div class="v accent">+${p.xpBonus}%</div><div class="n">From your level</div></div>
                        <div><div class="eyebrow">Reputation</div><div class="v">${num(p.reputation)}</div><div class="n">+${p.repBonus}% pay</div></div>
                    </div>
                </div>
                <div class="stats">
                    <div class="card stat"><div class="stat-ico">${icon('briefcase')}</div>
                        <div><div class="eyebrow">Jobs completed</div><div class="v">${num(p.jobsCompleted)}</div><div class="n">All time</div></div></div>
                    <div class="card stat"><div class="stat-ico">${icon('zap')}</div>
                        <div><div class="eyebrow">XP today</div><div class="v">${num(p.xpToday)}</div><div class="n">Resets in ${until(p.todayResetIn, 'soon')}</div></div></div>
                    <div class="card stat"><div class="stat-ico">${icon('dollar')}</div>
                        <div><div class="eyebrow">Money today</div><div class="v">${money(p.moneyToday)}</div><div class="n">Resets in ${until(p.todayResetIn, 'soon')}</div></div></div>
                </div>
            </div>
            <div class="col">
                <div class="card">
                    <div class="row"><div class="stat-ico">${icon('gift')}</div>
                        <div><h3>Daily reward</h3><div class="sub">One claim every 24 hours.</div></div></div>
                    <div class="daily-amounts">
                        <div class="mini"><div class="eyebrow">Cash</div><div class="v">${money(p.daily.money)}</div></div>
                        <div class="mini"><div class="eyebrow">XP</div><div class="v">${num(p.daily.xp)}</div></div>
                    </div>
                    ${dailyReady
                        ? `<button class="btn primary block" data-act="claimDaily">Claim reward ${icon('arrow')}</button>`
                        : `<button class="btn block" disabled>${icon('clock')} Ready in ${until(p.dailyLeft, 'a moment')}</button>`}
                </div>
                ${statusCard(d)}
            </div>
        </div>`;
}

function statusCard(d) {
    if (d.job) {
        const j = d.job;
        return `
            <div class="card active-job">
                <div class="eyebrow accent">Active job</div>
                <h3 style="margin-top:8px">${esc(j.label)}</h3>
                <div class="sub">${esc(objective(j))}</div>
                <button class="btn sm" style="margin-top:14px" data-page-go="jobs">Open job ${icon('arrow')}</button>
            </div>`;
    }
    const cd = d.player.cooldown;
    return `
        <div class="card">
            <h3>Status</h3>
            <div class="sub">${cd > 0 ? 'Dispatch will have work for you again soon.' : 'You are clear to take a run.'}</div>
            <div class="kv" style="margin-top:12px"><span>Cooldown</span><b>${until(cd)}</b></div>
            <div class="kv"><span>Crew</span><b>${d.group ? `${d.group.members.length} / ${d.group.max}` : 'Solo'}</b></div>
        </div>`;
}

function renderProgress(d) {
    const p = d.player;
    let current = 0;
    d.levels.forEach((c) => { if (c.level <= p.level) current = c.level; });

    const cards = d.levels.map((c) => {
        const state = c.level === current ? 'current' : c.level < p.level ? 'unlocked' : 'locked';
        const label = { current: 'Current', unlocked: 'Unlocked', locked: 'Locked' }[state];
        const xpText = state === 'locked' ? `${num(c.xp - p.xp)} XP to go` : `${num(c.xp)} XP total`;
        const lines = c.unlocks.length
            ? c.unlocks.map((u) => `<div class="unlock">${icon(UNLOCK_ICON[u.kind] || 'star')}${esc(u.label)}</div>`).join('')
            : '<div class="unlock">No new perks</div>';
        return `
            <div class="card level-card ${state}">
                <div class="head">
                    <div><div class="eyebrow">Level</div><div class="lvl">${c.level}</div><div class="xp">${xpText}</div></div>
                    <span class="state ${state}">${state === 'locked' ? icon('lock').replace('class="i"', 'class="i" style="width:11px;height:11px;vertical-align:-1px"') + ' ' : ''}${label}</span>
                </div>
                <div class="unlocks">${lines}</div>
            </div>`;
    }).join('');

    return `
        <div class="section-head">
            <div><div class="eyebrow accent">Progression</div><h2>Level ${p.level} of ${p.maxLevel}</h2>
                <p>Every level's unlocks, straight from dispatch. Bonuses replace the previous level's, they do not stack.</p></div>
            <div class="card" style="min-width:320px;padding:14px 18px">${levelBar(p)}</div>
        </div>
        <div class="levels">${cards}</div>`;
}

const PHASES = { atm: ['collect', 'deliver', 'return'], multibank: ['collect', 'return'], crate: ['collect', 'deliver', 'return'] };

function objective(j) {
    const site = (type) => (j.sites.find((s) => s.type === type && !s.done) || {}).label || '';
    if (j.phase === 'return') return 'Everything is delivered. Park the Stockade at HQ and return it.';
    if (j.task === 'atm') return j.phase === 'collect'
        ? `Collect the bags at ${site('bank')} and load them into the Stockade.`
        : 'Refill each marked ATM with one bag from the Stockade.';
    if (j.task === 'multibank') return 'Clear the marked banks in any order and hand the bags in at HQ.';
    return j.phase === 'collect'
        ? 'Pick up a crate at each marked location and load it into the Stockade.'
        : `Hand the crates to the client at ${site('dropoff')}.`;
}

function activeJobCard(j) {
    const phases = PHASES[j.task] || [];
    const at = phases.indexOf(j.phase);
    const c = j.counts;
    const unit = j.kind === 'crate' ? 'Crates' : 'Bags';
    return `
        <div class="card active-job">
            <div class="row" style="justify-content:space-between">
                <div class="eyebrow accent">Active job</div>
                ${j.timeLeft != null ? `<span class="chip warn"><span class="dot"></span>${until(j.timeLeft, 'Out of time')}</span>` : ''}
            </div>
            <h3 style="margin-top:8px;font-size:18px">${esc(j.label)}</h3>
            <div class="sub">${esc(objective(j))}</div>
            <div class="phase">${phases.map((_, i) => `<i class="${i <= at ? 'on' : ''}"></i>`).join('')}</div>
            <div style="margin-top:14px">
                <div class="kv"><span>${unit} delivered</span><b>${c.done} / ${c.total}</b></div>
                <div class="kv"><span>In the Stockade</span><b>${c.van}</b></div>
                <div class="kv"><span>Base pay</span><b>${money(j.payEstimate)}</b></div>
            </div>
        </div>`;
}

function taskCard(t, selected) {
    return `
        <button class="task ${t.locked ? 'locked' : ''} ${selected ? 'selected' : ''}" data-task="${t.key}" ${t.locked ? 'disabled' : ''}>
            <div><div class="diff ${t.difficultyKey}">${esc(t.difficulty)}</div><h4>${esc(t.label)}</h4></div>
            ${t.locked
                ? `<span class="lock-veil">${icon('lock')}Unlocks at level ${t.level}</span>`
                : `<div class="price"><div class="v">${money(t.payMin)} – ${money(t.payMax)}</div><div class="k">Base pay range</div></div>`}
            <div class="desc">${esc(t.description)}</div>
            <div class="task-meta">
                <div><div class="k">Deposit</div><div class="v">${money(t.deposit)}</div></div>
                <div><div class="k">Difficulty</div><div class="v">${esc(t.difficulty)}</div></div>
                <div><div class="k">Unlock level</div><div class="v">${t.level}</div></div>
                <div><div class="k">Time limit</div><div class="v">${t.timeLimit ? t.timeLimit + ' min' : 'None'}</div></div>
            </div>
        </button>`;
}

function groupCard(d) {
    const g = d.group;
    const p = d.player;
    const members = g ? g.members : [{ id: 0, name: p.name, leader: true, me: true }];
    const max = g ? g.max : p.maxGroup;
    const lead = !g || g.isLeader;
    const canInvite = lead && !d.job && members.length < max;

    let rows = members.map((m) => `
        <div class="member">
            <div class="ini">${esc(initials(m.name))}</div>
            <div><div class="nm">${esc(m.name)}${m.me ? ' (you)' : ''}</div>
                <div class="rl ${m.leader ? 'lead' : ''}">${m.leader ? 'Leader' : 'Member'}</div></div>
            ${g && g.isLeader && !m.me ? `<button class="x" data-kick="${m.id}" title="Kick">${icon('x')}</button>` : ''}
        </div>`).join('');
    for (let i = members.length; i < max; i++) {
        rows += `<div class="member"><div class="ini open">${icon('userPlus').replace('class="i"', 'class="i" style="width:14px;height:14px"')}</div><div class="rl">Open slot</div></div>`;
    }

    let nearby = '';
    if (T.nearby) {
        nearby = T.nearby.length
            ? `<div class="nearby">${T.nearby.map((n) => `
                <div class="member"><div class="ini">${esc(initials(n.name))}</div><div class="nm">${esc(n.name)}</div>
                    <button class="btn sm" style="margin-left:auto" data-invite="${n.id}">Invite</button></div>`).join('')}</div>`
            : `<div class="empty">Nobody nearby. Players within ${p.inviteDistance} m show up here.</div>`;
    }

    return `
        <div class="card">
            <div class="row" style="justify-content:space-between">
                <div><h3>Your crew</h3><div class="sub">Pay and XP split equally · +${p.groupBonus}% per extra member</div></div>
                <span class="chip">${members.length} / ${max}</span>
            </div>
            <div class="members">${rows}</div>
            ${canInvite ? `<button class="btn block" style="margin-top:12px" data-act="nearby">${icon(T.nearby ? 'refresh' : 'userPlus')} ${T.nearby ? 'Refresh nearby' : 'Invite nearby players'}</button>` : ''}
            ${nearby}
            ${g ? `<button class="btn block ghost-bad" style="margin-top:10px" data-act="leaveGroup">${icon('exit')} ${d.job ? 'Leave job' : 'Leave crew'}</button>` : ''}
        </div>`;
}

function renderJobs(d) {
    const tasks = d.tasks;
    if (!T.task || !tasks.find((t) => t.key === T.task && !t.locked)) {
        const first = tasks.find((t) => !t.locked);
        T.task = first ? first.key : null;
    }
    const sel = tasks.find((t) => t.key === T.task);
    const lead = !d.group || d.group.isLeader;

    let reason = '';
    if (d.job) reason = 'Your crew is already on a job.';
    else if (!lead) reason = 'Only the crew leader can start.';
    else if (d.player.cooldown > 0) reason = 'You are on cooldown.';
    else if (!sel) reason = 'No task unlocked yet.';
    const canStart = !reason;

    return `
        <div class="section-head">
            <div><div class="eyebrow accent">Dispatch</div><h2>Choose your run.</h2>
                <p>Pick a task, gather your crew, and the Stockade will be waiting at HQ.</p></div>
        </div>
        <div class="layout">
            <div class="col">
                ${d.job ? activeJobCard(d.job) : ''}
                <div class="tasks">${tasks.map((t) => taskCard(t, t.key === T.task && !d.job)).join('')}</div>
            </div>
            <div class="col">
                ${groupCard(d)}
                <div class="card">
                    <button class="btn primary xl block" data-act="startJob" ${canStart ? '' : 'disabled'}>
                        Start run ${icon('arrow')}
                    </button>
                    <div class="sub" style="margin-top:10px;text-align:center">
                        ${reason ? esc(reason) : `<b style="color:var(--text)">${esc(sel.label)}</b><br>${money(sel.deposit)} deposit from your bank, refunded on completion.`}
                    </div>
                </div>
            </div>
        </div>`;
}

async function tabletAction(action, arg) {
    if (T.busy) return;
    T.busy = true;
    const res = await post('tablet', { action, arg });
    T.busy = false;
    if (!res) return;
    if (action === 'nearby') {
        T.nearby = res.data || [];
        renderTablet();
    } else if (res.data) {
        T.data = res.data;
        renderTablet();
    }
}

$('#tablet').addEventListener('click', (e) => {
    const el = e.target.closest('[data-page],[data-page-go],[data-close],[data-task],[data-act],[data-kick],[data-invite]');
    if (!el) return;
    if (el.dataset.close !== undefined) return closeAll();
    if (el.dataset.page || el.dataset.pageGo) {
        T.page = el.dataset.page || el.dataset.pageGo;
        T.nearby = null;
        return renderTablet();
    }
    if (el.dataset.task) { T.task = el.dataset.task; return renderTablet(); }
    if (el.dataset.kick) return tabletAction('kick', Number(el.dataset.kick));
    if (el.dataset.invite) {
        T.nearby = T.nearby.filter((n) => String(n.id) !== el.dataset.invite);
        return tabletAction('invite', Number(el.dataset.invite));
    }
    const act = el.dataset.act;
    if (act === 'startJob') return tabletAction('startJob', T.task);
    if (act) return tabletAction(act);
});

/* ---------- Black market ---------- */

const M = { data: null, tab: 'buy', qty: {}, busy: false };

function renderMarket() {
    const d = M.data;
    if (!d) return;

    const buy = d.shop.map((s) => {
        const q = M.qty[s.index] || 1;
        return `
            <div class="card ware">
                <div class="top">
                    <div><span class="cur ${s.currency}">${s.currency === 'dirty' ? 'Dirty cash' : 'Clean cash'}</span><div class="nm">${esc(s.label)}</div></div>
                    <div class="price"><div class="v">${money(s.price)}</div><div class="k">Each</div></div>
                </div>
                <div class="art">${icon(s.item.includes('thermite') ? 'flame' : 'box')}</div>
                ${s.locked
                    ? `<div class="locked-note">${icon('lock')}${esc(s.locked)}</div>`
                    : `<div class="row">
                           <div class="qty"><button data-qty="${s.index}" data-d="-1">−</button><span>${q}</span><button data-qty="${s.index}" data-d="1">+</button></div>
                           <button class="btn primary" style="flex:1" data-buy="${s.index}">Buy ${money(s.price * q)}</button>
                       </div>`}
            </div>`;
    }).join('');

    const sell = d.stolen.length
        ? d.stolen.map((s) => `
            <div class="loot-row">
                <div class="ico">${icon(s.name.includes('crate') ? 'box' : 'bag')}</div>
                <div><div class="nm">${esc(s.label)}</div><div class="sb">Marked value ${money(s.value)} · slot ${s.slot}</div></div>
                <div class="amt"><div class="v">${money(s.price)}</div><div class="k">Clean cash</div></div>
                <button class="btn sm primary" data-sell="${s.slot}">Sell</button>
            </div>`).join('')
        : `<div class="empty">You have nothing worth fencing. Stolen Gruppe 6 bags and crates show up here.</div>`;

    $('#market').innerHTML = `
        <div class="market">
            <div class="market-head">
                <div><div class="eyebrow accent">Black market</div><h1>The back room</h1><p>Cash only. No receipts, no questions.</p></div>
                <div class="row">
                    <div class="pill"><span class="k">Cash</span><span class="v">${money(d.clean)}</span></div>
                    <div class="pill"><span class="k">Dirty</span><span class="v">${money(d.dirty)}</span></div>
                    <button class="close-x" data-close>${icon('x')}</button>
                </div>
            </div>
            <div class="toolbar">
                <div class="tabs">
                    <button class="tab ${M.tab === 'buy' ? 'active' : ''}" data-tab="buy">Buy</button>
                    <button class="tab ${M.tab === 'sell' ? 'active' : ''}" data-tab="sell">Sell (${d.stolen.length})</button>
                </div>
                <div class="sub">${M.tab === 'buy' ? `${d.shop.length} items on the table` : `Pays ${d.sellPercent}% of the marked value. Opening it yourself pays more, if it is not inked.`}</div>
            </div>
            <div class="scroll">${M.tab === 'buy' ? `<div class="goods">${buy}</div>` : sell}</div>
        </div>`;
}

async function marketAction(body) {
    if (M.busy) return;
    M.busy = true;
    const res = await post('market', body);
    M.busy = false;
    if (res && res.data) { M.data = res.data; renderMarket(); }
}

$('#market').addEventListener('click', (e) => {
    const el = e.target.closest('[data-close],[data-tab],[data-qty],[data-buy],[data-sell]');
    if (!el) return;
    if (el.dataset.close !== undefined) return closeAll();
    if (el.dataset.tab) { M.tab = el.dataset.tab; return renderMarket(); }
    if (el.dataset.qty) {
        const i = el.dataset.qty;
        M.qty[i] = Math.min(10, Math.max(1, (M.qty[i] || 1) + Number(el.dataset.d)));
        return renderMarket();
    }
    if (el.dataset.buy) return marketAction({ action: 'buy', index: Number(el.dataset.buy), amount: M.qty[el.dataset.buy] || 1 });
    if (el.dataset.sell) return marketAction({ action: 'sell', slot: Number(el.dataset.sell) });
});

/* ---------- Invite ---------- */

let inviteTimer = null;

function showInvite(info) {
    clearInterval(inviteTimer);
    const total = (info.timeout || 60) * 1000;
    const end = Date.now() + total;
    $('#invite').innerHTML = `
        <div class="eyebrow accent">Crew invite</div>
        <h2>${esc(info.from)} wants you in</h2>
        <p>Join their Gruppe 6 crew. Pay and XP are split equally between the crew.</p>
        <div class="timer"><i style="width:100%"></i></div>
        <div class="actions">
            <button class="btn" data-answer="0">Decline</button>
            <button class="btn primary" data-answer="1">Accept ${icon('arrow')}</button>
        </div>`;
    $('#invite').classList.remove('hidden');
    inviteTimer = setInterval(() => {
        const left = end - Date.now();
        $('#invite .timer > i').style.width = Math.max(0, (left / total) * 100) + '%';
        if (left <= 0) answerInvite(false);
    }, 250);
}

function answerInvite(accept) {
    clearInterval(inviteTimer);
    $('#invite').classList.add('hidden');
    post('respondInvite', { accept });
}

$('#invite').addEventListener('click', (e) => {
    const el = e.target.closest('[data-answer]');
    if (el) answerInvite(el.dataset.answer === '1');
});

/* ---------- Thermite minigame ---------- */

const G = { running: false };

function startMinigame(cfg) {
    const n = cfg.grid * cfg.grid;
    const targets = new Set();
    while (targets.size < Math.min(cfg.cells, n)) targets.add(Math.floor(Math.random() * n));
    Object.assign(G, { running: true, cfg, targets, found: new Set(), lives: cfg.mistakes, input: false, timer: null, end: 0 });

    const cells = Array.from({ length: n }, (_, i) => `<button class="cell" data-cell="${i}" disabled></button>`).join('');
    $('#minigame').innerHTML = `
        <div class="mg-head">
            <div><div class="eyebrow accent">Thermite</div><h2>Burn through the lock</h2></div>
            <div class="mg-lives">${Array.from({ length: cfg.mistakes + 1 }, () => '<i></i>').join('')}</div>
        </div>
        <p>Memorise the hot spots, then mark every one before the charge cools.</p>
        <div class="grid" style="grid-template-columns:repeat(${cfg.grid},1fr)">${cells}</div>
        <div class="timer"><i style="width:100%"></i></div>
        <div class="mg-status">Memorise the pattern</div>`;
    $('#minigame').classList.remove('hidden');

    const all = document.querySelectorAll('#minigame .cell');
    targets.forEach((i) => all[i].classList.add('lit'));

    setTimeout(() => {
        if (!G.running) return;
        all.forEach((c) => { c.classList.remove('lit'); c.disabled = false; });
        G.input = true;
        G.end = Date.now() + cfg.timeLimit;
        $('#minigame .mg-status').textContent = 'Mark the hot spots';
        G.timer = setInterval(() => {
            const left = G.end - Date.now();
            $('#minigame .timer > i').style.width = Math.max(0, (left / cfg.timeLimit) * 100) + '%';
            if (left <= 0) endMinigame(false);
        }, 100);
    }, cfg.showTime);
}

function endMinigame(success) {
    if (!G.running) return;
    G.running = false;
    G.input = false;
    clearInterval(G.timer);
    document.querySelectorAll('#minigame .cell').forEach((c, i) => {
        c.disabled = true;
        if (!success && G.targets.has(i) && !G.found.has(i)) c.classList.add('lit');
    });
    const st = $('#minigame .mg-status');
    st.textContent = success ? 'Lock burned through' : 'The charge fizzled out';
    st.className = 'mg-status ' + (success ? 'good' : 'bad');
    setTimeout(() => {
        $('#minigame').classList.add('hidden');
        post('minigameResult', { success });
    }, 1100);
}

$('#minigame').addEventListener('click', (e) => {
    const el = e.target.closest('[data-cell]');
    if (!el || !G.input || el.disabled) return;
    const i = Number(el.dataset.cell);
    el.disabled = true;
    if (G.targets.has(i)) {
        el.classList.add('hit');
        G.found.add(i);
        if (G.found.size === G.targets.size) endMinigame(true);
    } else {
        el.classList.add('miss');
        G.lives -= 1;
        const dots = document.querySelectorAll('#minigame .mg-lives i');
        const lost = dots.length - 1 - G.lives;
        dots.forEach((d, k) => d.classList.toggle('lost', k < lost));
        if (G.lives < 0) endMinigame(false);
    }
});

/* ---------- Open / close ---------- */

function closeAll() {
    $('#tablet').classList.add('hidden');
    $('#market').classList.add('hidden');
    T.nearby = null;
    post('close');
}

window.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    if (G.running) return;
    if (!$('#invite').classList.contains('hidden')) return answerInvite(false);
    if (!$('#tablet').classList.contains('hidden') || !$('#market').classList.contains('hidden')) closeAll();
});

window.addEventListener('message', (e) => {
    const { action, data } = e.data || {};
    switch (action) {
        case 'openTablet':
            T.data = data; T.page = 'overview'; T.nearby = null;
            $('#tablet').classList.remove('hidden');
            renderTablet();
            break;
        case 'tabletData':
            T.data = data;
            renderTablet();
            break;
        case 'openMarket':
            M.data = data; M.tab = 'buy'; M.qty = {};
            $('#market').classList.remove('hidden');
            renderMarket();
            break;
        case 'invite':
            showInvite(data);
            break;
        case 'minigame':
            startMinigame(data);
            break;
        case 'close':
            $('#tablet').classList.add('hidden');
            $('#market').classList.add('hidden');
            break;
    }
});

/* ---------- Browser preview (outside FiveM only): index.html?demo=overview|progress|jobs|market|invite|minigame ---------- */

(function demo() {
    if (typeof GetParentResourceName === 'function') return;
    const mode = new URLSearchParams(location.search).get('demo');
    if (!mode) return;
    document.body.style.background = 'radial-gradient(circle at 30% 20%, #3a3346, #15121b)';
    const tablet = {
        player: { name: 'Chris Envas', level: 7, maxLevel: 25, xp: 5480, xpInto: 1240, xpNeeded: 1791, moneyBonus: 5, xpBonus: 5,
            reputation: 23, repBonus: 2, jobsCompleted: 41, xpToday: 860, moneyToday: 14250, todayResetIn: 18500, cooldown: 0, dailyLeft: 0,
            daily: { money: 2500, xp: 250 }, groupBonus: 10, maxGroup: 4, inviteDistance: 20 },
        levels: [
            { level: 1, xp: 0, unlocks: [{ kind: 'task', label: 'Bank pickup & ATM run' }, { kind: 'vehicle', label: 'Stockade' }] },
            { level: 3, xp: 1100, unlocks: [{ kind: 'money', label: '+2% money' }, { kind: 'xp', label: '+2% XP' }] },
            { level: 5, xp: 2684, unlocks: [{ kind: 'task', label: 'Multi-bank collection' }, { kind: 'money', label: '+5% money' }, { kind: 'xp', label: '+5% XP' }, { kind: 'cooldown', label: '-5 min cooldown' }] },
            { level: 8, xp: 6720, unlocks: [{ kind: 'money', label: '+7% money' }, { kind: 'xp', label: '+7% XP' }] },
            { level: 10, xp: 10465, unlocks: [{ kind: 'task', label: 'Private crate delivery' }, { kind: 'money', label: '+10% money' }, { kind: 'xp', label: '+10% XP' }, { kind: 'cooldown', label: '-10 min cooldown' }] },
            { level: 15, xp: 27015, unlocks: [{ kind: 'money', label: '+15% money' }, { kind: 'xp', label: '+15% XP' }] },
            { level: 20, xp: 68196, unlocks: [{ kind: 'money', label: '+20% money' }, { kind: 'xp', label: '+20% XP' }, { kind: 'cooldown', label: '-12 min cooldown' }] },
            { level: 25, xp: 170668, unlocks: [{ kind: 'money', label: '+25% money' }, { kind: 'xp', label: '+25% XP' }, { kind: 'cooldown', label: '-15 min cooldown' }] },
        ],
        tasks: [
            { key: 'atm', label: 'Bank pickup & ATM run', description: 'Collect money bags from one bank, then refill an ATM with each bag.', difficulty: 'Easy', difficultyKey: 'easy', deposit: 2500, payMin: 1950, payMax: 3900, level: 1, locked: false },
            { key: 'multibank', label: 'Multi-bank collection', description: 'Clear several banks in any order and bring every bag back to HQ.', difficulty: 'Medium', difficultyKey: 'medium', deposit: 5000, payMin: 2625, payMax: 4375, level: 5, locked: false },
            { key: 'crate', label: 'Private crate delivery', description: 'Secure crates from private pickups and hand them to a waiting client.', difficulty: 'Hard', difficultyKey: 'hard', deposit: 10000, payMin: 6300, payMax: 10500, level: 10, locked: true, timeLimit: 30 },
        ],
        group: { id: 1, isLeader: true, max: 4, members: [{ id: 1, name: 'Chris Envas', leader: true, me: true }, { id: 2, name: 'Mad Ilnemican', leader: false }] },
        job: null,
    };
    if (['overview', 'progress', 'jobs'].includes(mode)) {
        window.postMessage({ action: 'openTablet', data: tablet });
        setTimeout(() => { T.page = mode; renderTablet(); }, 0);
    } else if (mode === 'job') {
        tablet.job = { id: 3, task: 'atm', label: 'Bank pickup & ATM run', phase: 'deliver', kind: 'bag', counts: { site: 0, van: 2, carried: 1, done: 1, total: 4 },
            sites: [{ id: 1, type: 'bank', label: 'Fleeca Legion Square', done: true }], payEstimate: 2600, carriers: {} };
        window.postMessage({ action: 'openTablet', data: tablet });
        setTimeout(() => { T.page = 'jobs'; renderTablet(); }, 0);
    } else if (mode === 'market') {
        window.postMessage({ action: 'openMarket', data: { clean: 4200, dirty: 31800, sellPercent: 70,
            shop: [{ index: 1, item: 'g6_thermite', label: 'Thermite charge', price: 15000, currency: 'dirty' },
                   { index: 2, item: 'lockpick', label: 'Advanced lockpick', price: 900, currency: 'clean', locked: 'Needs 20 reputation.' }],
            stolen: [{ slot: 4, name: 'g6_moneybag', label: 'G6 Money Bag', value: 3120, price: 2184 }, { slot: 9, name: 'g6_crate', label: 'G6 Crate', value: 7450, price: 5215 }] } });
    } else if (mode === 'invite') {
        window.postMessage({ action: 'invite', data: { from: 'Chris Envas', timeout: 60 } });
    } else if (mode === 'minigame') {
        window.postMessage({ action: 'minigame', data: { grid: 6, cells: 8, showTime: 60000, timeLimit: 15000, mistakes: 2 } });
    }
})();
