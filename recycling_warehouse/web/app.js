/*
    recycling_warehouse - screen logic

    Lua sends messages with SendNUIMessage({ action = ..., ... }):
      setup   { text, ui }       text = Config.UIText, ui = Config.UI
      laptop  { data, status }   data from the server, status = { ok, text } after an action
      trader  { data, status }
      close

    Buttons send messages back to Lua with post('name', data) -> RegisterNUICallback in client.lua.
    The server re-checks everything; this file only displays and asks.
*/

const RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'recycling_warehouse';

let T = {};              // Config.UIText
let current = null;      // 'laptop' | 'trader' | null
let busy = false;        // true while waiting for Lua to answer a button press
const quantity = {};     // trader: chosen amount per material index

const $ = (id) => document.getElementById(id);

// ---------- helpers ----------

function post(name, data = {}) {
    return fetch(`https://${RESOURCE}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    }).catch(() => {});
}

// Fills %d / %s in order, like Lua's string.format. %% becomes %.
function fmt(text, ...args) {
    let i = 0;
    return String(text ?? '').replace(/%%|%[ds]/g, (m) => (m === '%%' ? '%' : String(args[i++] ?? '')));
}

// Makes text safe to put inside HTML.
function esc(value) {
    return String(value ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function duration(seconds) {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    return h > 0 ? `${h}h ${m}m` : `${m}m`;
}

function setStatus(id, status) {
    const el = $(id);
    el.textContent = status ? status.text : '';
    el.className = 'status' + (status ? (status.ok ? ' ok' : ' error') : '');
}

function setBusy(value) {
    busy = value;
    document.querySelectorAll('.window button:not([data-close])').forEach((b) => {
        if (value) b.disabled = true;
    });
}

// Box mark used when no logo is set.
const MARK_SVG = `<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    <path d="M21 8 12 3 3 8v8l9 5 9-5z"/><path d="m3 8 9 5 9-5"/><path d="M12 13v8"/>
</svg>`;

function applySetup(text, ui) {
    T = text || {};
    document.querySelectorAll('[data-text]').forEach((el) => { el.textContent = T[el.dataset.text] ?? ''; });
    document.querySelectorAll('[data-brand]').forEach((el) => { el.textContent = ui.brand || ''; });
    document.querySelectorAll('[data-logo]').forEach((el) => {
        el.innerHTML = ui.logo ? `<img src="${esc(ui.logo)}" alt="">` : MARK_SVG;
    });
    if (ui.accent) {
        document.documentElement.style.setProperty('--accent', ui.accent);
        document.documentElement.style.setProperty('--accent-glow', ui.accent + '59'); // ~35% alpha
    }
}

function show(screen) {
    current = screen;
    $('laptop').classList.toggle('hidden', screen !== 'laptop');
    $('trader').classList.toggle('hidden', screen !== 'trader');
}

function close() {
    show(null);
    setStatus('laptop-status', null);
    setStatus('trader-status', null);
}

// ---------- laptop ----------

function perkList(perks) {
    const items = [];
    if (perks.bonusBoxes > 0) items.push(fmt(T.perkBonusBoxes, perks.bonusBoxes));
    if (perks.tradeBonus > 0) items.push(fmt(T.perkTradeBonus, perks.tradeBonus));
    if (perks.rareChance > 0) items.push(fmt(T.perkRareChance, perks.rareChance));
    return items;
}

function renderLaptop(d) {
    // Shift state
    const pill = $('shift-pill');
    pill.textContent = d.onShift ? T.onShift : T.offShift;
    pill.classList.toggle('on', d.onShift);

    const shiftBtn = $('shift-button');
    shiftBtn.textContent = d.onShift ? T.endShift : T.startShift;
    shiftBtn.className = 'btn ' + (d.onShift ? 'btn-ghost' : 'btn-primary');
    shiftBtn.disabled = false;
    shiftBtn.onclick = () => {
        if (busy) return;
        setBusy(true);
        post(d.onShift ? 'endShift' : 'startShift');
    };

    // Level ring + XP
    $('level-value').textContent = d.level;
    const ring = $('level-ring');
    if (d.nextXp) {
        const into = d.xp - d.levelXp;
        const needed = d.nextXp - d.levelXp;
        ring.classList.remove('max');
        ring.style.setProperty('--progress', Math.min(100, (into / needed) * 100).toFixed(1));
        $('xp-text').textContent = fmt(T.xpProgress, into, needed);
    } else {
        ring.classList.add('max');
        $('xp-text').textContent = T.maxLevel;
    }

    // Perks
    const now = perkList(d.perks);
    $('perks-now').innerHTML = now.length
        ? now.map((p) => `<li>${esc(p)}</li>`).join('')
        : `<li class="muted">${esc(T.noPerks)}</li>`;

    const nextWrap = $('perks-next-wrap');
    if (d.nextPerks) {
        nextWrap.classList.remove('hidden');
        $('perks-next-title').textContent = fmt(T.perksNext, d.level + 1);
        const next = perkList(d.nextPerks);
        $('perks-next').innerHTML = next.map((p) => `<li>${esc(p)}</li>`).join('');
        if (!next.length) nextWrap.classList.add('hidden');
    } else {
        nextWrap.classList.add('hidden');
    }

    // Goals
    $('reset-text').textContent = fmt(T.resetsIn, duration(d.resetIn));
    const goals = $('goals');
    if (!d.goalsEnabled) {
        goals.innerHTML = `<div class="empty">${esc(T.goalsOff)}</div>`;
    } else if (!d.goals.length) {
        goals.innerHTML = `<div class="empty">${esc(T.goalsEmpty)}</div>`;
    } else {
        goals.innerHTML = d.goals.map((g) => {
            const pct = Math.min(100, (g.progress / g.target) * 100);
            let right = `<span class="goal-count">${g.progress} / ${g.target}</span>`;
            if (g.done && g.claimed) right = `<span class="tag great">${esc(T.claimed)}</span>`;
            if (g.done && !g.claimed) right = `<button class="btn btn-primary" data-claim="${g.index}" type="button">${esc(T.claim)}</button>`;

            return `<div class="goal${g.done ? ' complete' : ''}">
                <div class="goal-row"><span class="goal-title">${esc(g.text)}</span>${right}</div>
                <div class="bar"><div class="bar-fill${g.done ? ' done' : ''}" style="width:${pct}%"></div></div>
                <p class="goal-reward">${esc(fmt(T.reward, g.reward))}</p>
            </div>`;
        }).join('');

        goals.querySelectorAll('[data-claim]').forEach((b) => {
            b.onclick = () => {
                if (busy) return;
                setBusy(true);
                post('claimGoal', { index: Number(b.dataset.claim) });
            };
        });
    }

    // Market
    $('market').innerHTML = d.market.map((m) => `
        <div class="market-row">
            <span class="market-name">${esc(m.label)}</span>
            <span class="tag ${esc(m.rating)}">${esc(m.ratingLabel)}</span>
            <span class="market-rate">${esc(fmt(T.costEach, m.cost))} &middot; ${esc(fmt(T.getsEach, m.amount))}</span>
        </div>`).join('');

    // Stats
    const stats = [
        [d.stats.boxes, T.statBoxes],
        [d.stats.skillHits, T.statSkill],
        [d.stats.trades, T.statTrades],
        [d.stats.rareFinds, T.statRare],
        [d.stats.goalsCompleted, T.statGoals],
        [d.stats.shifts, T.statShifts],
    ];
    $('stats').innerHTML = stats.map(([value, label]) => `
        <div class="stat"><div class="stat-value">${Number(value).toLocaleString()}</div><div class="stat-label">${esc(label)}</div></div>`).join('');
}

// ---------- trader ----------

let traderData = null;

function renderTrader(d) {
    traderData = d;
    $('box-count').textContent = d.count;
    $('level-bonus').textContent = fmt(T.levelBonus, d.tradeBonus);
    $('level-bonus').classList.toggle('hidden', d.tradeBonus <= 0);
    $('trader-reset').textContent = fmt(T.resetsIn, duration(d.resetIn));

    $('materials').innerHTML = d.materials.map((m) => `
        <div class="material ${esc(m.rating)}" data-index="${m.index}">
            <div class="material-top">
                <span class="material-name">${esc(m.label)}</span>
                <span class="tag ${esc(m.rating)}">${esc(m.ratingLabel)}</span>
            </div>
            <p class="material-rate">${esc(fmt(T.costEach, m.cost))} &middot; ${esc(fmt(T.getsEach, m.amount))}</p>
            <div class="material-controls">
                <div class="stepper">
                    <button type="button" data-step="-1" aria-label="Less">&minus;</button>
                    <span data-qty></span>
                    <button type="button" data-step="1" aria-label="More">+</button>
                </div>
                <span class="material-total" data-total></span>
                <button class="btn btn-primary" type="button" data-trade></button>
            </div>
        </div>`).join('');

    d.materials.forEach((m) => {
        const card = document.querySelector(`.material[data-index="${m.index}"]`);
        card.querySelectorAll('[data-step]').forEach((b) => {
            b.onclick = () => {
                quantity[m.index] = (quantity[m.index] || 1) + Number(b.dataset.step);
                updateMaterial(m, card);
            };
        });
        card.querySelector('[data-trade]').onclick = () => {
            if (busy) return;
            setBusy(true);
            post('trade', { index: m.index, times: quantity[m.index] || 1 });
        };
        updateMaterial(m, card);
    });
}

// Keeps the amount between 1 and what the player can afford (and the config limit).
function updateMaterial(m, card) {
    const affordable = Math.floor(traderData.count / m.cost);
    const max = Math.max(1, Math.min(traderData.maxTimes, affordable));
    const qty = Math.min(Math.max(quantity[m.index] || 1, 1), max);
    quantity[m.index] = qty;

    const canAfford = traderData.count >= m.cost * qty;

    card.querySelector('[data-qty]').textContent = qty;
    card.querySelector('[data-step="-1"]').disabled = qty <= 1;
    card.querySelector('[data-step="1"]').disabled = qty >= max;
    card.querySelector('[data-total]').textContent = fmt(T.total, m.cost * qty, m.amount * qty, m.label);

    const tradeBtn = card.querySelector('[data-trade]');
    tradeBtn.textContent = canAfford ? T.trade : T.notEnough;
    tradeBtn.disabled = !canAfford;
}

// ---------- messages from Lua ----------

window.addEventListener('message', (event) => {
    const msg = event.data || {};

    switch (msg.action) {
        case 'setup':
            applySetup(msg.text, msg.ui || {});
            break;
        case 'laptop':
            busy = false;
            show('laptop');
            renderLaptop(msg.data);
            setStatus('laptop-status', msg.status);
            break;
        case 'trader':
            busy = false;
            show('trader');
            renderTrader(msg.data);
            setStatus('trader-status', msg.status);
            break;
        case 'close':
            close();
            break;
    }
});

// Close with Escape or the X buttons.
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && current) post('close');
});
document.querySelectorAll('[data-close]').forEach((b) => { b.onclick = () => post('close'); });
