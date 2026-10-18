// dg_cocaine lab minigames. Every game ends with finish(score 0-100) or cancel().
// The score is only a request: the server validates the session and decides the yield.

const RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'dg_cocaine';

const $ = (id) => document.getElementById(id);
const app = $('app'), game = $('game'), hint = $('hint'), timer = $('timer'), result = $('result');

let state = null; // { s: settings, openedAt, done, cleanup: [] }

function post(name, data) {
    return fetch(`https://${RESOURCE}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
    }).catch(() => {});
}

const clamp = (v, min, max) => Math.max(min, Math.min(max, v));
const rand = (min, max) => min + Math.random() * (max - min);

// 100-80 inside the zone (100 at its centre), then -4 per point outside it
function zoneScore(value, center, size) {
    const half = size / 2, d = Math.abs(value - center);
    if (d <= half) return 100 - (d / half) * 20;
    return Math.max(0, 80 - (d - half) * 4);
}

// Runs fn every frame with the seconds since the last frame, until the game is cleaned up
function loop(fn) {
    let last = performance.now(), id;
    const step = (now) => { fn((now - last) / 1000); last = now; id = requestAnimationFrame(step); };
    id = requestAnimationFrame(step);
    state.cleanup.push(() => cancelAnimationFrame(id));
}

// Countdown shown in the header; calls onEnd when it hits 0
function countdown(seconds, onEnd) {
    const end = performance.now() + seconds * 1000;
    const id = setInterval(() => {
        const left = Math.max(0, (end - performance.now()) / 1000);
        timer.textContent = left.toFixed(1) + 's';
        if (left <= 0) { clearInterval(id); onEnd(); }
    }, 100);
    state.cleanup.push(() => clearInterval(id));
}

function on(target, type, fn) {
    target.addEventListener(type, fn);
    state.cleanup.push(() => target.removeEventListener(type, fn));
}

function stopGame() {
    if (!state) return;
    state.cleanup.forEach((fn) => fn());
    state.cleanup = [];
}

function finish(score) {
    if (!state || state.done) return;
    state.done = true;
    stopGame();
    score = Math.round(clamp(score, 0, 100));
    result.textContent = `Score: ${score}%`;
    result.classList.remove('hidden');
    // Never send before the server's minimum time for this game
    const wait = Math.max(0, state.s.minTime * 1000 - (performance.now() - state.openedAt));
    setTimeout(() => post('finish', { score }), wait + 800);
}

function cancel() {
    if (!state || state.done) return;
    state.done = true;
    stopGame();
    post('cancel');
}

function close() {
    stopGame();
    state = null;
    app.classList.add('hidden');
}

// ---------------------------------------------------------------------------------------------
// Pour Balance / Pressure Gauge: hold (mouse on the button, or SPACE) to fill, release in the zone
// ---------------------------------------------------------------------------------------------
function holdGame(s, opts) {
    const vertical = opts.vertical;
    const gauge = document.createElement('div');
    gauge.className = 'gauge ' + (vertical ? 'vertical' : 'horizontal');
    const zone = document.createElement('div'); zone.className = 'zone';
    const fill = document.createElement('div'); fill.className = 'fill';
    gauge.append(zone, fill);

    const rounds = document.createElement('div'); rounds.className = 'rounds';
    const button = document.createElement('button'); button.className = 'action'; button.textContent = opts.button;
    game.append(gauge, rounds, button);

    const total = Math.max(1, s.rounds || 1);
    const scores = [];
    let level = 0, center = 0, holding = false, roundOver = false;

    const draw = () => {
        if (vertical) { fill.style.height = level + '%'; } else { fill.style.width = level + '%'; }
        rounds.textContent = total > 1 ? `Round ${Math.min(scores.length + 1, total)} / ${total}` : '';
    };

    const newRound = () => {
        level = 0; roundOver = false; holding = false;
        center = rand(opts.minCenter + s[opts.size] / 2, 95 - s[opts.size] / 2);
        const from = center - s[opts.size] / 2;
        if (vertical) { zone.style.bottom = from + '%'; zone.style.height = s[opts.size] + '%'; }
        else { zone.style.left = from + '%'; zone.style.width = s[opts.size] + '%'; }
        button.disabled = false;
        draw();
    };

    const release = () => {
        if (!holding || roundOver) return;
        holding = false; roundOver = true;
        button.classList.remove('active'); button.disabled = true;
        scores.push(zoneScore(level, center, s[opts.size]));
        if (scores.length >= total) {
            finish(scores.reduce((a, b) => a + b, 0) / scores.length);
        } else {
            const id = setTimeout(newRound, 700);
            state.cleanup.push(() => clearTimeout(id));
        }
    };
    const press = () => { if (!roundOver && !state.done) { holding = true; button.classList.add('active'); } };

    on(button, 'mousedown', press);
    on(window, 'mouseup', release);
    on(window, 'keydown', (e) => { if (e.code === 'Space' && !e.repeat) press(); });
    on(window, 'keyup', (e) => { if (e.code === 'Space') release(); });

    loop((dt) => {
        if (!holding) return;
        level = Math.min(100, level + s[opts.speed] * dt);
        draw();
        if (level >= 100) release(); // overflow / overshoot
    });

    newRound();
}

// ---------------------------------------------------------------------------------------------
// Slider Matching
// ---------------------------------------------------------------------------------------------
function slidersGame(s) {
    const sliders = [];
    for (let i = 0; i < Math.max(1, s.count); i++) {
        const target = Math.round(rand(10, 90));
        const row = document.createElement('div'); row.className = 'slider-row';
        const labels = document.createElement('div'); labels.className = 'labels';
        const track = document.createElement('div'); track.className = 'slider-track';
        const mark = document.createElement('div'); mark.className = 'target'; mark.style.left = target + '%';
        const input = document.createElement('input');
        input.type = 'range'; input.min = 0; input.max = 100; input.value = Math.round(rand(0, 100));
        const update = () => { labels.innerHTML = `<span>Mix ${i + 1}: ${input.value}</span><span>Target: ${target}</span>`; };
        on(input, 'input', update);
        update();
        track.append(mark, input);
        row.append(labels, track);
        game.append(row);
        sliders.push({ input, target });
    }

    const score = () => {
        const each = sliders.map(({ input, target }) => {
            const d = Math.abs(Number(input.value) - target);
            return d <= s.tolerance ? 100 : Math.max(0, 100 - (d - s.tolerance) * 4);
        });
        return each.reduce((a, b) => a + b, 0) / each.length;
    };

    const button = document.createElement('button'); button.className = 'action'; button.textContent = 'Confirm mix';
    on(button, 'click', () => finish(score()));
    game.append(button);
    countdown(s.timeLimit, () => finish(score()));
}

// ---------------------------------------------------------------------------------------------
// Mixing Grid
// ---------------------------------------------------------------------------------------------
function gridGame(s) {
    const size = Math.max(2, s.size);
    const cells = size * size;
    const clumpCount = clamp(s.clumps, 1, cells);
    const clumps = new Set();
    while (clumps.size < clumpCount) clumps.add(Math.floor(Math.random() * cells));

    let cleared = 0, misses = 0;
    const score = () => (cleared / clumpCount) * 100 - misses * (s.penalty || 0);

    const grid = document.createElement('div');
    grid.className = 'grid';
    grid.style.gridTemplateColumns = `repeat(${size}, 52px)`;
    for (let i = 0; i < cells; i++) {
        const cell = document.createElement('div');
        cell.className = 'cell' + (clumps.has(i) ? ' clump' : '');
        on(cell, 'mousedown', () => {
            if (state.done) return;
            if (cell.classList.contains('clump')) {
                cell.classList.replace('clump', 'cleared');
                cleared++;
                if (cleared >= clumpCount) finish(score());
            } else if (!cell.classList.contains('cleared')) {
                misses++;
                cell.classList.add('miss');
                setTimeout(() => cell.classList.remove('miss'), 250);
            }
        });
        grid.append(cell);
    }
    game.append(grid);
    countdown(s.timeLimit, () => finish(score()));
}

// ---------------------------------------------------------------------------------------------

const GAMES = {
    pour: {
        hint: 'Hold the button (or SPACE) to pour the gasoline. Release inside the green band.',
        start: (s) => holdGame(s, { vertical: true, size: 'band', speed: 'fillSpeed', minCenter: 15, button: 'Hold to pour' }),
    },
    sliders: {
        hint: 'Drag each slider onto its target, then confirm before time runs out.',
        start: slidersGame,
    },
    grid: {
        hint: 'Click every white clump to break it up. Clicking clean powder costs points.',
        start: gridGame,
    },
    pressure: {
        hint: 'Hold the button (or SPACE) to build pressure. Release in the green zone.',
        start: (s) => holdGame(s, { vertical: false, size: 'zone', speed: 'buildSpeed', minCenter: 40, button: 'Hold to press' }),
    },
};

function open(data) {
    const def = GAMES[data.game];
    if (!def) return post('cancel');

    stopGame();
    state = { s: data.settings || {}, openedAt: performance.now(), done: false, cleanup: [] };
    $('title').textContent = data.title || 'Lab';
    hint.textContent = def.hint;
    timer.textContent = '';
    game.innerHTML = '';
    result.classList.add('hidden');
    app.classList.remove('hidden');
    def.start(state.s);
}

window.addEventListener('message', (e) => {
    const data = e.data || {};
    if (data.action === 'open') open(data);
    else if (data.action === 'close') close();
});

window.addEventListener('keydown', (e) => { if (e.key === 'Escape') cancel(); });
$('close').addEventListener('click', cancel);
