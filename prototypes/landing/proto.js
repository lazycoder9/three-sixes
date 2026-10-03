// PROTOTYPE, throwaway. Shared behaviour for the three variants of issue #13:
// fake state, a hash router, forms that go nowhere, and the floating variant bar.
// Markup and styling stay in each variant file. Nothing here is production code.
(() => {
  const VARIANTS = [
    { key: 'a', name: 'Back Room' },
    { key: 'b', name: 'Loaded Dice' },
    { key: 'c', name: 'Pips' },
    // round two
    { key: 'd', name: 'Game Night' },
    { key: 'e', name: 'Score Pad' },
    { key: 'f', name: 'Sticker Sheet' },
    // round three: D, made cozier with paper from E
    { key: 'g', name: 'Kitchen Table' },
  ];
  const SCENES = [
    ['Landing', 'landing'],
    ['Join a Room', 'r/KQXT'],
    ['Join, name taken', 'r/KQXT', 'dupe'],
    ['Room has closed', 'r/GONE'],
    ['Sign in', 'signin'],
    ['Account', 'account', 'in'],
    ['Design system', 'system'],
  ];

  const data = {
    account: { nick: 'Dana', email: 'dana@example.com' },
    room: ['Timur', 'Dana', 'Malika', 'Aziz'],
    history: [
      { date: '2026-10-02', place: 1, order: ['Dana', 'Timur', 'Malika', 'Aziz', 'Sasha'] },
      { date: '2026-10-02', place: 3, order: ['Malika', 'Timur', 'Dana', 'Sasha', 'Aziz'] },
      { date: '2026-09-30', place: 2, order: ['Aziz', 'Dana', 'Timur', 'Malika'] },
      { date: '2026-09-26', place: 5, order: ['Timur', 'Sasha', 'Malika', 'Aziz', 'Dana', 'Kamila'] },
      { date: '2026-09-26', place: 1, order: ['Dana', 'Kamila', 'Timur', 'Aziz', 'Malika', 'Sasha'] },
      { date: '2026-09-19', place: 4, order: ['Malika', 'Aziz', 'Timur', 'Dana'] },
    ],
  };

  const root = document.documentElement;
  const params = new URLSearchParams(location.search);
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const current = (location.pathname.match(/([a-g])\.html$/) || [0, 'a'])[1];
  const state = { code: 'KQXT', nick: '', base: '', next: null, last: '' };

  // ---- dice ---------------------------------------------------------------
  const PIPS = { 0: [], 1: [4], 2: [2, 6], 3: [2, 4, 6], 4: [0, 2, 6, 8], 5: [0, 2, 4, 6, 8], 6: [0, 2, 3, 5, 6, 8] };
  const pips = (n) => Array.from({ length: 9 }, (_, i) => `<i${PIPS[n].includes(i) ? ' class="on"' : ''}></i>`).join('');
  const fillDie = (el, n) => { el.dataset.die = n; el.innerHTML = pips(n); };
  const dice = (scope = document) => $$('[data-die]', scope).forEach((el) => fillDie(el, +el.dataset.die));
  const cubeHTML = () =>
    `<span class="cube__tilt"><span class="cube__body">${[1, 2, 3, 4, 5, 6]
      .map((n) => `<span class="cube__face die f${n}">${pips(n)}</span>`).join('')}</span></span>`;
  const TURN = { 1: [0, 0], 6: [0, 180], 3: [0, -90], 4: [0, 90], 2: [-90, 0], 5: [90, 0] };
  const rollCube = (el, face) => {
    el._spins = (el._spins || 0) + 1;
    const body = $('.cube__body', el);
    body.style.setProperty('--rx', TURN[face][0] + 720 * el._spins + 'deg');
    body.style.setProperty('--ry', TURN[face][1] + 1080 * el._spins + 'deg');
  };
  const setCube = (el, face) => {
    const body = $('.cube__body', el);
    body.style.transition = 'none';
    body.style.setProperty('--rx', TURN[face][0] + 'deg');
    body.style.setProperty('--ry', TURN[face][1] + 'deg');
    void body.offsetWidth;
    body.style.transition = '';
  };

  // an honest roll of every cube inside `scope`; returns the faces and the best thing you could truthfully Bid
  const FACE = ['', 'one', 'two', 'three', 'four', 'five', 'six'];
  const COUNT = ['', 'one', 'two', 'three', 'four', 'five'];
  const bidWords = (count, face) => `${COUNT[count]} ${FACE[face]}${count > 1 ? (face === 6 ? 'es' : 's') : ''}`;
  const rollAll = (scope, forced) => {
    const cubes = $$('.cube', scope);
    const faces = cubes.map((_, i) => (forced ? forced[i] : 1 + Math.floor(Math.random() * 6)));
    cubes.forEach((c, i) => setTimeout(() => {
      rollCube(c, faces[i]);
      c.classList.remove('is-rolling'); void c.offsetWidth; c.classList.add('is-rolling');
    }, i * 120));
    let best = { count: 0, face: 0 };
    for (let f = 1; f <= 6; f++) {
      const n = faces.filter((x) => x === f).length;
      if (n >= best.count && n > 0) best = { count: n, face: f };
    }
    return { faces, ...best, words: bidWords(best.count, best.face) };
  };

  // ---- small helpers ------------------------------------------------------
  const ordinal = (n) => n + (['th', 'st', 'nd', 'rd'][n] || 'th');
  const fmtDate = (d) => new Date(d + 'T12:00').toLocaleDateString('en', { month: 'short', day: 'numeric' });
  const query = () => (params.toString() ? '?' + params : '');
  const syncUrl = () => history.replaceState(null, '', location.pathname + query() + location.hash);
  const go = (hash) => { location.hash = hash; };

  function toast(msg) {
    let box = $('.toasts');
    if (!box) { box = document.createElement('div'); box.className = 'toasts'; box.setAttribute('role', 'status'); document.body.append(box); }
    const t = document.createElement('div');
    t.className = 'toast';
    t.textContent = msg;
    box.append(t);
    setTimeout(() => { t.classList.add('is-leaving'); setTimeout(() => t.remove(), 400); }, 2600);
  }

  function fail(form, msg) {
    const slot = $('[data-error]', form);
    if (slot) slot.textContent = msg;
    form.classList.remove('is-error');
    void form.offsetWidth;
    form.classList.add('is-error');
  }
  const clearError = (form) => {
    form.classList.remove('is-error');
    const slot = $('[data-error]', form);
    if (slot) slot.textContent = '';
  };

  function setTheme(t) { root.dataset.theme = t; params.set('theme', t); syncUrl(); }
  function setAuth(a) { root.dataset.auth = a; params.set('auth', a); syncUrl(); syncBar(); }
  function setHost(h) { if (h) root.dataset.host = '1'; else delete root.dataset.host; }

  function bind() {
    const values = { code: state.code, nick: state.nick, 'nick-base': state.base, account: data.account.nick, email: data.account.email };
    $$('[data-bind]').forEach((el) => { el.textContent = values[el.dataset.bind] ?? ''; });
  }

  // ---- router -------------------------------------------------------------
  function screenFor(hash) {
    const h = hash.replace(/^#/, '') || 'landing';
    const m = h.match(/^r\/([a-z]{4})$/i);
    if (!m) return h;
    state.code = m[1].toUpperCase();
    return state.code === 'GONE' ? 'closed' : 'join';
  }

  function route() {
    let name = screenFor(location.hash);
    if (name === 'account' && root.dataset.auth !== 'in') { state.next = '#account'; location.replace('#signin'); return; }
    if (!$(`[data-screen~="${name}"]`, document.body)) name = 'landing';
    if (name === 'landing') setHost(false);
    if (name === 'signin' && !state.next && state.last.startsWith('#r/')) state.next = state.last;
    if (name === 'join') {
      root.dataset.join = 'form';
      const input = $('[data-nick-input]');
      if (root.dataset.auth === 'in' && !input.value) { input.value = data.account.nick; root.dataset.prefilled = '1'; }
      $$('[data-join-form]').forEach(clearError);
    }
    // scoped to <body>: <html> carries data-screen too, as a styling hook
    $$('[data-screen]', document.body).forEach((el) => { el.hidden = !el.dataset.screen.split(' ').includes(name); });
    root.dataset.screen = name;
    state.last = location.hash;
    bind();
    window.scrollTo(0, 0);
    document.dispatchEvent(new CustomEvent('proto:screen', { detail: name }));
  }

  // ---- forms --------------------------------------------------------------
  function nameTaken(name) {
    state.base = name;
    state.nick = name + ' 2';
    bind();
    root.dataset.join = 'dupe';
    document.dispatchEvent(new CustomEvent('proto:nick', { detail: state.nick }));
  }

  document.addEventListener('submit', (e) => {
    const form = e.target;
    e.preventDefault();
    if (form.matches('[data-code-form]')) {
      const cells = $$('[data-code-cell]', form);
      const code = cells.length ? cells.map((c) => c.value).join('') : $('[data-code-input]', form).value;
      if (code.length < 4) return fail(form, 'A Room code is four letters.');
      setHost(false);
      go('r/' + code);
      form.reset();
      cells.forEach((c) => c.classList.remove('is-filled'));
    }
    if (form.matches('[data-join-form]')) {
      const name = $('[data-nick-input]', form).value.trim();
      if (!name) return fail(form, 'Pick a Nickname first.');
      const taken = !root.dataset.host && data.room.some((n) => n.toLowerCase() === name.toLowerCase());
      if (taken) return nameTaken(name);
      state.nick = name;
      go('room');
    }
  });

  document.addEventListener('input', (e) => {
    const el = e.target;
    const form = el.closest('form');
    if (form) clearError(form);
    if (el.matches('[data-code-input]')) el.value = el.value.replace(/[^a-z]/gi, '').toUpperCase().slice(0, 4);
    if (el.matches('[data-code-cell]')) {
      const cells = $$('[data-code-cell]', form);
      const i = cells.indexOf(el);
      const letters = el.value.replace(/[^a-z]/gi, '').toUpperCase();
      if (letters.length > 1) {
        [...letters].slice(0, 4 - i).forEach((ch, k) => { cells[i + k].value = ch; });
        cells[Math.min(i + letters.length, 3)].focus();
      } else {
        el.value = letters;
        if (letters && cells[i + 1]) cells[i + 1].focus();
      }
      cells.forEach((c) => c.classList.toggle('is-filled', !!c.value));
    }
    if (el.matches('[data-nick-input]')) delete root.dataset.prefilled;
    if (el.matches('[data-nick-input]')) document.dispatchEvent(new CustomEvent('proto:nick', { detail: el.value.trim() }));
  });

  document.addEventListener('keydown', (e) => {
    const el = e.target;
    if (el.matches?.('[data-code-cell]') && e.key === 'Backspace' && !el.value) {
      const cells = $$('[data-code-cell]', el.closest('form'));
      const prev = cells[cells.indexOf(el) - 1];
      if (prev) { prev.value = ''; prev.classList.remove('is-filled'); prev.focus(); e.preventDefault(); }
    }
    const typing = el.matches?.('input, textarea, [contenteditable]');
    if (!typing && !$('dialog[open]') && (e.key === 'ArrowLeft' || e.key === 'ArrowRight')) cycle(e.key === 'ArrowLeft' ? -1 : 1);
  });
  document.addEventListener('focusin', (e) => { if (e.target.matches('[data-code-cell]')) e.target.select(); });

  // ---- actions ------------------------------------------------------------
  const busy = (btn, ms, done) => {
    btn.classList.add('is-loading'); btn.disabled = true;
    setTimeout(() => { btn.classList.remove('is-loading'); btn.disabled = false; done(); }, ms);
  };
  const randomCode = () => Array.from({ length: 4 }, () => 'BCDFHJKLMNPQRSTVWXZ'[Math.floor(Math.random() * 19)]).join('');
  const signedIn = () => {
    setAuth('in');
    toast('Signed in as ' + data.account.nick);
    const next = state.next || '#account';
    state.next = null;
    go(next);
  };

  const ACTIONS = {
    create: (btn) => busy(btn, 650, () => { setHost(true); $('[data-nick-input]').value = ''; go('r/' + randomCode()); }),
    google: (btn) => busy(btn, 900, signedIn),
    'dev-login': signedIn,
    theme: () => setTheme(root.dataset.theme === 'dark' ? 'light' : 'dark'),
    logout: () => $('#logout-dialog').showModal(),
    'logout-confirm': () => {
      $('#logout-dialog').close();
      setAuth('out');
      $('[data-nick-input]').value = '';
      delete root.dataset.prefilled;
      go('landing');
      toast('Logged out');
    },
    'edit-nick': () => {
      const input = $('[data-nick-input]');
      root.dataset.join = 'form';
      input.value = state.nick;
      input.focus(); input.select();
    },
    'enter-room': () => go('room'),
    'copy-link': () => {
      navigator.clipboard?.writeText('https://three-sixes.usebotify.app/r/' + state.code).catch(() => {});
      toast('Room link copied');
    },
    'toast-demo': () => toast('Room link copied'),
    'dialog-demo': () => $('#logout-dialog').showModal(),
  };

  document.addEventListener('click', (e) => {
    const closer = e.target.closest('[data-dialog-close]');
    if (closer) return closer.closest('dialog').close();
    if (e.target.matches('dialog[open]')) return e.target.close(); // backdrop
    const btn = e.target.closest('[data-action]');
    if (btn && ACTIONS[btn.dataset.action]) ACTIONS[btn.dataset.action](btn);
  });

  // ---- the floating variant bar ------------------------------------------
  function cycle(step) {
    const i = VARIANTS.findIndex((v) => v.key === current);
    const next = VARIANTS[(i + step + VARIANTS.length) % VARIANTS.length];
    location.href = next.key + '.html' + query() + location.hash;
  }
  let bar;
  function syncBar() {
    if (bar) $('[data-pbar="auth"]', bar).textContent = root.dataset.auth === 'in' ? 'Account' : 'Guest';
  }
  function buildBar() {
    const v = VARIANTS.find((x) => x.key === current);
    bar = document.createElement('div');
    bar.className = 'pbar';
    bar.innerHTML = `
      <button data-pbar="prev" aria-label="Previous variant">&larr;</button>
      <span class="pbar__label"><b>${v.key.toUpperCase()}</b><span class="pbar__name"> / ${v.name}</span></span>
      <button data-pbar="next" aria-label="Next variant">&rarr;</button>
      <span class="pbar__sep"></span>
      <button data-pbar="scenes" aria-haspopup="true">Screens</button>
      <button data-pbar="theme" aria-label="Switch light and dark">Theme</button>
      <button data-pbar="auth" title="Pretend to be a Guest or an Account"></button>
      <div class="pbar__menu" hidden>${SCENES.map((s, i) => `<button data-scene="${i}">${s[0]}</button>`).join('')}</div>`;
    document.body.append(bar);
    const menu = $('.pbar__menu', bar);
    bar.addEventListener('click', (e) => {
      const b = e.target.closest('button');
      if (!b) return;
      if (b.dataset.scene) {
        const [, hash, extra] = SCENES[b.dataset.scene];
        menu.hidden = true;
        setHost(false);
        if (extra === 'in') setAuth('in');
        if (location.hash === '#' + hash) route(); else go(hash);
        if (extra === 'dupe') setTimeout(() => { $('[data-nick-input]').value = 'Dana'; nameTaken('Dana'); }, 30);
        return;
      }
      const act = b.dataset.pbar;
      if (act === 'prev') cycle(-1);
      if (act === 'next') cycle(1);
      if (act === 'scenes') menu.hidden = !menu.hidden;
      if (act === 'theme') ACTIONS.theme();
      if (act === 'auth') { setAuth(root.dataset.auth === 'in' ? 'out' : 'in'); route(); }
    });
    document.addEventListener('click', (e) => { if (!bar.contains(e.target)) menu.hidden = true; });
    syncBar();
  }

  // ---- boot ---------------------------------------------------------------
  const G = '<svg viewBox="0 0 48 48" width="18" height="18" aria-hidden="true"><path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/><path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/><path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/><path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/></svg>';

  root.dataset.theme = params.get('theme') || root.dataset.defaultTheme || 'light';
  root.dataset.auth = params.get('auth') === 'in' ? 'in' : 'out';
  root.dataset.join = 'form';

  window.Proto = { data, state, $, $$, pips, fillDie, dice, cubeHTML, rollCube, setCube, rollAll, bidWords, ordinal, fmtDate, toast, go };

  document.addEventListener('DOMContentLoaded', () => {
    $$('[data-g]').forEach((el) => { el.innerHTML = G; });
    $$('[data-cube]').forEach((el) => { el.classList.add('cube'); el.innerHTML = cubeHTML(); });
    dice();
    buildBar();
    window.addEventListener('hashchange', route);
    route();
  });
})();
