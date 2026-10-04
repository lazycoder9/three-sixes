// PROTOTYPE, throwaway. Issue #7.
// Everything the three table layouts share: drawing helpers, your dice, the Bid picker's state, sounds,
// the Room bar, lobby, Game over, banners, Reactions, dialogs, and the floating prototype bar.
// A layout registers itself in window.Variants as { name, mount(stage), render() } and only draws the table.
(() => {
  const T = window.Table, S = T.S;
  const root = document.documentElement;
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const params = new URLSearchParams(location.search);
  const calm = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  // ---- drawing helpers -------------------------------------------------------
  const PIPS = { 0: [], 1: [4], 2: [2, 6], 3: [2, 4, 6], 4: [0, 2, 6, 8], 5: [0, 2, 4, 6, 8], 6: [0, 2, 3, 5, 6, 8] };
  const pips = (n) => Array.from({ length: 9 }, (_, i) => `<i${PIPS[n].includes(i) ? ' class="on"' : ''}></i>`).join('');
  const die = (f, cls = '', style = '') => `<span class="die ${cls}"${style ? ` style="${style}"` : ''}>${pips(f)}</span>`;
  const blanks = (n, cls = '') => Array.from({ length: n }, () => die(0, 'is-down ' + cls)).join('');
  const bidn = (c, f, cls = '') => `<span class="bidn ${cls}"><b>${c}</b><i>&times;</i>${die(f)}</span>`;
  const token = (p, cls = '') => `<span class="token ${cls}" style="--c:${p.color}">${esc(p.name[0])}</span>`;
  const nm = (p) => (p.me ? 'You' : esc(p.name));
  const FACE = ['', 'one', 'two', 'three', 'four', 'five', 'six'];
  const NUM = ['no', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve'];
  const faces = (f, n) => FACE[f] + (n === 1 ? '' : f === 6 ? 'es' : 's');
  const words = (c, f) => `${NUM[c] || c} ${faces(f, c)}`;
  const up = (s) => s[0].toUpperCase() + s.slice(1);
  const tally = (n) => (n ? `<span class="tally" aria-label="${n} wins">${'<span class="five"><i></i><i></i><i></i><i></i></span>'.repeat(Math.floor(n / 5))}${n % 5 ? `<span>${'<i></i>'.repeat(n % 5)}</span>` : ''}</span>` : '');
  const awayTag = (p) => `away <span data-away="${p.away}"></span>`;
  const clock = (ms) => { const s = Math.max(0, Math.floor(ms / 1000)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; };

  // sentences every layout says the same way
  const who = (id) => (id === 'me' ? 'You' : esc(T.person(id).name));
  const sv = (id, one, you) => (id === 'me' ? you : one);          // "Timur takes", "You take"
  const lines = (r) => ({
    call: `${who(r.checker)} ${sv(r.checker, 'Checks', 'Check')}!`,
    count: r.n === 0 ? `Not a single ${FACE[r.bid.face]}.` : `${up(NUM[r.n] || String(r.n))} ${faces(r.bid.face, r.n)} on the table.`,
    verdict: r.stood ? 'The Bid stands.' : 'Bluff caught.',
    penalty: `${who(r.loser)} ${sv(r.loser, 'takes', 'take')} a Penalty die.`,
    out: r.knocked ? `That makes six. ${who(r.loser)} ${sv(r.loser, 'is', 'are')} Knocked out.` : '',
  });
  const waiting = () => {
    const g = S.game;
    if (S.sub === 'rolling') return 'Everyone rolls.';
    if (S.sub === 'reveal' || !g.turn) return '';
    return g.turn === 'me' ? 'Your turn.' : `Waiting for ${who(g.turn)}.`;
  };

  // replace an element's HTML only when it changed, so untouched pieces keep their place and don't re-animate
  const patch = (el, html) => { if (el && el._h !== html) { el.innerHTML = html; el._h = html; } };
  // a keyed list: children are reused by key, patched in place and re-ordered
  function keyed(box, items, keyOf, htmlOf, attrsOf, tag = 'div') {
    const have = new Map([...box.children].map((c) => [c.dataset.key, c]));
    let prev = null;
    items.forEach((it) => {
      const k = String(keyOf(it));
      let el = have.get(k);
      if (!el) { el = document.createElement(tag); el.dataset.key = k; }
      have.delete(k);
      patch(el, htmlOf(it));
      for (const [n, v] of Object.entries(attrsOf ? attrsOf(it) : {})) {
        if (n === 'class') { if (el.className !== v) el.className = v; } else if (el.getAttribute(n) !== String(v)) el.setAttribute(n, v);
      }
      const want = prev ? prev.nextSibling : box.firstChild;
      if (el !== want) box.insertBefore(el, want);
      prev = el;
    });
    have.forEach((el) => el.remove());
  }

  // ---- your dice: 3D cubes that roll at the start of every Round -------------
  const TURN = { 1: [0, 0], 6: [0, 180], 3: [0, -90], 4: [0, 90], 2: [-90, 0], 5: [90, 0] };
  const cubeHTML = () => `<span class="cube__tilt"><span class="cube__body">${[1, 2, 3, 4, 5, 6].map((n) => `<span class="cube__face die f${n}">${pips(n)}</span>`).join('')}</span></span>`;
  const setCube = (el, face, animate) => {
    const body = $('.cube__body', el);
    el._spins = (el._spins || 0) + (animate ? 1 : 0);
    if (!animate) body.style.transition = 'none';
    body.style.setProperty('--rx', TURN[face][0] + 720 * el._spins + 'deg');
    body.style.setProperty('--ry', TURN[face][1] + 1080 * el._spins + 'deg');
    if (!animate) { void body.offsetWidth; body.style.transition = ''; }
  };
  function hand(el) {
    if (!el) return;
    const mine = T.seesOwnDice() ? S.game.dice.me : null;
    const key = mine ? S.game.rid + ':' + mine.join('') : 'none';
    if (el._key === key) return;
    el._key = key;
    if (!mine) { el.innerHTML = ''; return; }
    el.innerHTML = mine.map(() => `<span class="slot"><span class="cube">${cubeHTML()}</span></span>`).join('');
    const roll = S.sub === 'rolling' && !calm;
    $$('.cube', el).forEach((c, i) => {
      if (!roll) return setCube(c, mine[i], false);
      setCube(c, 1 + ((mine[i] + 2) % 6), false);
      setTimeout(() => { setCube(c, mine[i], true); c.classList.add('is-rolling'); }, 40 + i * 90);
    });
  }

  // ---- the Bid you are about to make ------------------------------------------
  const pk = { count: 1, face: 6, key: '' };
  const bestFace = () => {
    const mine = T.seesOwnDice() ? S.game.dice.me : [];
    return [6, 5, 4, 3, 2, 1].sort((a, b) => mine.filter((x) => x === b).length - mine.filter((x) => x === a).length)[0];
  };
  function defaultRaise() {
    const g = S.game;
    if (!g.bid) return { count: 1, face: bestFace() };
    if (T.canRaise(g.bid.count + 1, g.bid.face)) return { count: g.bid.count + 1, face: g.bid.face };
    for (let f = 1; f <= 6; f++) if (T.minCount(f) <= T.total()) return { count: T.minCount(f), face: f };
    return null;
  }
  function picker() {
    const g = S.game, key = g.rid + ':' + (g.bid ? g.bid.count + 'x' + g.bid.face : 'open');
    if (pk.key !== key || !T.canRaise(pk.count, pk.face)) { pk.key = key; Object.assign(pk, defaultRaise() || {}); }
    return pk;
  }
  const setFace = (f) => { if (T.minCount(f) > T.total()) return; pk.face = f; pk.count = Math.min(T.total(), Math.max(pk.count, T.minCount(f))); };
  const stepCount = (d) => { pk.count = Math.max(T.minCount(pk.face), Math.min(T.total(), pk.count + d)); };
  // up to three one-tap Raises: the smallest step, one more of the same, one more of your best face
  function quick() {
    const g = S.game, tot = T.total(), out = [], add = (c, f) => { if (T.canRaise(c, f) && !out.some((o) => o.c === c && o.f === f)) out.push({ c, f }); };
    const mine = bestFace();
    if (!g.bid) { add(1, mine); add(2, mine); add(Math.max(1, Math.round(tot / 6)), mine); add(1, 6); return out.slice(0, 3); }
    const b = g.bid;
    if (b.face < 6) add(b.count, b.face + 1); else add(b.count + 1, 1);
    add(b.count + 1, b.face);
    add(T.minCount(mine), mine); add(b.count + 1, mine); add(b.count + 2, b.face);
    for (let f = 1; f <= 6 && out.length < 3; f++) add(T.minCount(f), f);
    return out.slice(0, 3);
  }

  // ---- sounds and haptics -------------------------------------------------------
  const sfx = (() => {
    let ctx, on = params.get('sound') !== 'off';
    const ac = () => { ctx = ctx || new (window.AudioContext || window.webkitAudioContext)(); if (ctx.state === 'suspended') ctx.resume(); return ctx; };
    const noise = (dur, freq, q, gain, when = 0) => {
      const c = ac(), len = Math.floor(c.sampleRate * dur), buf = c.createBuffer(1, len, c.sampleRate), d = buf.getChannelData(0);
      for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, 2.5);
      const src = c.createBufferSource(), f = c.createBiquadFilter(), g = c.createGain();
      src.buffer = buf; f.type = 'bandpass'; f.frequency.value = freq; f.Q.value = q; g.gain.value = gain;
      src.connect(f).connect(g).connect(c.destination); src.start(c.currentTime + when);
    };
    const thump = (freq, dur, gain, when = 0) => {
      const c = ac(), o = c.createOscillator(), g = c.createGain(), t = c.currentTime + when;
      o.frequency.setValueAtTime(freq, t); o.frequency.exponentialRampToValueAtTime(freq * .5, t + dur);
      g.gain.setValueAtTime(gain, t); g.gain.exponentialRampToValueAtTime(.001, t + dur);
      o.connect(g).connect(c.destination); o.start(t); o.stop(t + dur);
    };
    const tone = (freq, dur, gain, when = 0) => {
      const c = ac(), o = c.createOscillator(), g = c.createGain(), t = c.currentTime + when;
      o.type = 'triangle'; o.frequency.value = freq; g.gain.setValueAtTime(gain, t); g.gain.exponentialRampToValueAtTime(.001, t + dur);
      o.connect(g).connect(c.destination); o.start(t); o.stop(t + dur);
    };
    const sounds = {
      roll: () => { for (let i = 0; i < 9; i++) noise(.05, 1500 + Math.random() * 1800, 2, .5, i * .075 + Math.random() * .04); },  // dice on wood
      clack: () => noise(.045, 2400, 3, .55),                                                                                       // a Bid goes down
      knock: () => { thump(170, .11, .9); noise(.03, 800, 1, .5); thump(160, .11, .85, .17); noise(.03, 800, 1, .45, .17); },         // Check: knuckles on the table
      flip: () => { for (let i = 0; i < 5; i++) noise(.03, 3000, 4, .3, i * .06); },
      penalty: () => { thump(120, .22, .7); noise(.06, 1300, 2, .4, .04); },
      ouch: () => { thump(95, .3, .9); noise(.06, 1100, 2, .5, .04); },
      turn: () => { tone(660, .16, .12); tone(880, .22, .1, .11); },
      win: () => { [523, 659, 784, 1047].forEach((f, i) => tone(f, .3, .12, i * .12)); },
    };
    const buzz = { knock: [30, 60, 30], turn: [25], ouch: [90], penalty: [20], win: [30, 40, 30, 40, 60] };
    return {
      play(name) { if (!on) return; try { sounds[name]?.(); } catch (e) { /* no audio until the first tap */ } if (buzz[name]) navigator.vibrate?.(buzz[name]); },
      get on() { return on; },
      toggle() { on = !on; params.set('sound', on ? 'on' : 'off'); syncUrl(); return on; },
    };
  })();
  T.on('sfx', (name) => sfx.play(name));

  // ---- toasts and Reactions ------------------------------------------------------
  function toast(msg) {
    const box = $('.toasts'), t = document.createElement('div');
    t.className = 'toast'; t.textContent = msg; box.append(t);
    setTimeout(() => { t.classList.add('is-leaving'); setTimeout(() => t.remove(), 400); }, 3000);
  }
  T.on('toast', toast);
  T.on('react', (id, r) => {
    const layer = $('#rxlayer'), anchor = $$(`[data-anchor="${id}"]`).find((el) => el.offsetParent !== null) || $('.spec__chip');   // a Spectator in the closed list pops over the chip
    if (!anchor) return;
    $(`.rx[data-of="${id}"]`, layer)?.remove();            // a new one replaces the previous one
    const box = anchor.getBoundingClientRect(), el = document.createElement('div');
    el.className = 'rx' + (r.line ? ' is-line' : ''); el.dataset.of = id; el.textContent = r.emoji || r.line;
    if (anchor.closest('.spec')) {            // a Spectator: pop out beside the chip or the name, not over it
      el.classList.add('rx--side');
      el.style.left = box.right + 8 + 'px'; el.style.top = box.top + box.height / 2 + 'px';
    } else {
      el.style.left = Math.min(innerWidth - 50, Math.max(50, box.left + box.width / 2)) + 'px';
      el.style.top = Math.max(46, box.top + 8) + 'px';
    }
    layer.append(el);
    setTimeout(() => el.remove(), 3000);
  });

  // ---- shared screens ---------------------------------------------------------------
  const stage = () => $('#stage');
  function personRow(p) {
    const status = p.away ? awayTag(p) : p.sitOut ? 'sitting out' : '';
    return `${token(p)}<span class="who">${nm(p)}${p.id === S.hostId ? '<span class="hosttag">Host</span>' : ''}${status ? `<small>${status}</small>` : ''}</span>${tally(S.tally[p.id] || 0)}`;
  }
  function lobbyHTML() {
    const people = T.inRoom(), dealt = T.connected().filter((p) => !p.sitOut).length, host = T.person(S.hostId), me = T.person('me');
    const over = S.phase === 'over' && S.last;
    const placement = over ? `
      <div class="paper"><span class="tape" aria-hidden="true"></span>
        <h1>${S.last.placement[0] === 'me' ? 'You win!' : esc(T.person(S.last.placement[0]).name) + ' wins.'}</h1>
        <p class="faint">Final Placement, after ${S.last.rounds} Rounds</p>
        <ol class="placement">${S.last.placement.map((id, i) => { const p = T.person(id); return `<li data-anchor="${id}">${token(p)}<span${i === 0 ? ' class="circled"' : ''}>${p.me ? '<span class="hl">You</span>' : esc(p.name)}</span></li>`; }).join('')}</ol>
      </div>` : '';
    const start = T.iAmHost()
      ? `<div><button class="block block--primary block--big" data-act="start"${dealt < 2 ? ' disabled' : ''}>${over ? 'Next Game' : 'Start Game'}</button>
           <p class="lobby__wait" style="margin-top:10px;font-size:18px">${dealt < 2 ? 'A Game needs two people.' : `${dealt} people are dealt in. Seats are shuffled.`}</p></div>`
      : `<p class="lobby__wait">Waiting for ${esc(host.name)} to start ${over ? 'the next Game' : 'the Game'}.</p>`;
    return `<div class="lobby${over ? ' is-over' : ''}">
      <div class="over">${placement}
        <div class="paper"><span class="tape" aria-hidden="true"></span>
          <h1>${over ? 'Next Game' : "Who's playing"}</h1>
          <ul class="people">${people.map((p) => `<li data-person="${p.id}" data-anchor="${p.id}" class="${p.away ? 'is-away' : ''}"${T.iAmHost() && !p.me ? ' data-can tabindex="0" role="button"' : ''}>${personRow(p)}</li>`).join('')}</ul>
          <label class="tick"><input type="checkbox" data-act="sitout"${me.sitOut ? ' checked' : ''}>Sit out the next Game</label>
        </div>
      </div>
      <div class="lobby__side">
        <div><p class="lobby__label">Room code</p><span class="tiles">${[...'KQXT'].map((c) => `<span class="lettertile">${c}</span>`).join('')}</span></div>
        <button class="block" data-act="copy">Copy Room link</button>
        ${start}
      </div>
    </div>`;
  }

  function banners() {
    const out = [];
    const g = S.game, host = T.person(S.hostId);
    if (S.phase === 'play' && S.sub === 'bidding' && T.person(g.turn)?.away) {
      const p = T.person(g.turn);
      out.push(`<div class="banner sticky"><span><b>${esc(p.name)}</b> is on turn and ${awayTag(p)}. The table waits.</span>${T.iAmHost()
        ? `<button class="block block--dark block--small" data-act="remove" data-id="${p.id}">Remove ${esc(p.name)}</button>`
        : `<span class="faint">Only the Host can Remove.</span>`}</div>`);
    }
    if (host?.away && !S.left) {
      const v = S.vote, need = T.connected().length;
      out.push(v
        ? `<div class="banner sticky"><span><b>Pass Host now?</b> ${v.by === 'me' ? 'You' : esc(T.person(v.by).name)} asked. ${v.yes.length} of ${need} said yes. <span data-until="${v.endsAt}"></span> left.</span>${v.yes.includes('me')
          ? '<span class="faint">You said yes.</span>'
          : '<button class="block block--small" data-act="vote-yes">Yes</button><button class="block block--small" data-act="vote-no">No</button>'}</div>`
        : `<div class="banner sticky"><span><b>${esc(host.name)}</b>, the Host, is ${awayTag(host)}. The role passes on at 2:00.</span><button class="block block--small" data-act="vote-start"${Date.now() < S.voteCooldown ? ' disabled' : ''}>Pass Host now</button></div>`);
    }
    patch($('#banners'), out.join(''));
  }

  // Spectators: a quiet chip at the side that opens into a list of names
  let specOpen = false;
  function watching() {
    const box = $('#watching');
    if (S.phase !== 'play') return patch(box, '');
    const g = S.game, list = T.inRoom().filter((p) => !T.isPlaying(p.id));
    patch(box, list.length ? `<button class="spec__chip" data-act="spec" aria-expanded="${specOpen}">${list.length} Spectator${list.length === 1 ? '' : 's'}<i></i></button>${specOpen
      ? `<ul class="spec__list">${list.map((p) => `<li data-person="${p.id}" data-anchor="${p.id}"${p.away ? ' class="is-away"' : ''}>${token(p)}<span>${nm(p)}</span>${g.out.includes(p.id) ? '<small>out</small>' : p.away ? `<small>${awayTag(p)}</small>` : ''}</li>`).join('')}</ul>` : ''}` : '');
  }

  // ---- render -------------------------------------------------------------------------
  let mounted = '';
  function render() {
    const V = window.Variants[root.dataset.variant];
    root.dataset.phase = S.left ? 'left' : S.phase;
    banners();
    const want = S.left ? 'left' : S.phase === 'play' ? 'v' + root.dataset.variant : 'lobby';
    if (mounted !== want) { mounted = want; const st = stage(); st.innerHTML = ''; st._h = null; if (want[0] === 'v') V.mount(st); }
    watching();
    if (S.left) patch(stage(), `<div class="left"><div class="sticky"><h2>You left the Room.</h2><p>In the real thing this goes back to the home page. Your seat is gone and the Game carries on without you.</p><p style="margin-top:14px"><button class="block" data-act="rejoin">Back in, for the prototype</button></p></div></div>`);
    else if (S.phase === 'play') V.render();
    else { patch(stage(), lobbyHTML()); fitLobby(); }
    syncBar();
    tick();
  }
  // big windows get bigger chrome and a bigger lobby, so nothing sits small in a corner of a desktop
  function fit() {
    const wide = innerWidth > 900, z = Math.min(innerWidth / 1100, innerHeight / 800);
    root.style.setProperty('--zc', wide ? Math.max(1, Math.min(z, 1.3)).toFixed(3) : 1);
  }
  // the lobby is zoomed to fill what is left under the Room bar: up on a monitor, a touch down on a small laptop
  function fitLobby() {
    const el = $('.lobby'); if (!el) return;
    el.style.zoom = 1; el.style.marginTop = '';
    if (innerWidth <= 900) return;
    const r = el.getBoundingClientRect(), avail = innerHeight - (r.top + scrollY) - parseFloat(getComputedStyle(document.body).paddingBottom);
    const z = Math.max(.8, Math.min(innerWidth / 1100, avail / r.height, 1.7));
    el.style.zoom = z.toFixed(3);
    el.style.marginTop = Math.max(0, ((avail - r.height * z) * .4) / z) + 'px';      // sit a little above the middle of what is left
  }
  addEventListener('resize', () => { fit(); render(); });
  let queued = false;
  T.on('state', () => { if (queued) return; queued = true; requestAnimationFrame(() => { queued = false; render(); }); });
  function tick() {
    $$('[data-away]').forEach((el) => { el.textContent = clock(Date.now() - +el.dataset.away); });
    $$('[data-until]').forEach((el) => { el.textContent = clock(+el.dataset.until - Date.now()); });
  }
  setInterval(tick, 1000);

  // ---- actions ---------------------------------------------------------------------------
  const dialog = (id) => $('#' + id);
  const ACT = {
    raise: () => T.raise('me', pk.count, pk.face),
    check: () => T.check('me'),
    start: () => T.startGame(),
    copy: () => { navigator.clipboard?.writeText('https://three-sixes.usebotify.app/r/KQXT').catch(() => {}); toast('Room link copied'); },
    sitout: (el) => { T.person('me').sitOut = el.checked; T.emit(); },
    remove: (el) => { dialog('seat-dialog').close(); T.drop(el.dataset.id, 'removed'); },
    makehost: (el) => { dialog('seat-dialog').close(); T.passHost(el.dataset.id); },
    'vote-start': () => T.startVote('me'),
    'vote-yes': () => T.voteYes('me'),
    'vote-no': () => T.voteNo(),
    menu: () => {
      $('#menu-sound').textContent = sfx.on ? 'Sound is on' : 'Sound is off';
      $('#menu-turnhint').hidden = !T.myTurn();
      $('#menu-sit').hidden = S.phase !== 'play';
      $('#menu-sit').textContent = T.person('me').sitOut ? 'Sitting out the next Game' : 'Sit out the next Game';
      dialog('menu-dialog').showModal();
    },
    sound: () => { $('#menu-sound').textContent = sfx.toggle() ? 'Sound is on' : 'Sound is off'; sfx.play('clack'); },
    theme: () => { root.dataset.theme = root.dataset.theme === 'dark' ? 'light' : 'dark'; params.set('theme', root.dataset.theme); syncUrl(); },
    sit: () => { const me = T.person('me'); me.sitOut = !me.sitOut; ACT.menu(); T.emit(); },
    signin: () => { dialog('menu-dialog').close(); toast('Off to Google. Your seat shows as Away until you are back.'); },
    leave: () => { dialog('menu-dialog').close(); if (T.isPlaying('me')) dialog('leave-dialog').showModal(); else T.drop('me'); },
    'leave-yes': () => { dialog('leave-dialog').close(); T.drop('me'); },
    rejoin: () => { T.scene('lobby'); },
    spec: () => { specOpen = !specOpen; render(); },
    react: () => { const tray = $('#rxtray'); tray.hidden = !tray.hidden; },
    other: () => { otherPicker(); dialog('bid-dialog').showModal(); },
    'other-raise': () => { dialog('bid-dialog').close(); T.raise('me', pk.count, pk.face); },
  };
  // the stepper picker, also used inside the "Other" dialog of layout 3
  function stepper() {
    const p = picker(), tot = T.total();
    return `<div class="stepper">
        <div class="stepper__count"><button class="roundbtn" data-step="-1" aria-label="One fewer"${p.count <= T.minCount(p.face) ? ' disabled' : ''}>&minus;</button><b>${p.count}</b><button class="roundbtn" data-step="1" aria-label="One more"${p.count >= tot ? ' disabled' : ''}>+</button>${tot >= 20 ? `<button class="roundbtn roundbtn--five" data-step="5" aria-label="Five more"${p.count >= tot ? ' disabled' : ''}>+5</button>` : ''}</div>
        <span class="stepper__x">&times;</span>
        <div class="stepper__faces">${[1, 2, 3, 4, 5, 6].map((f) => `<button class="facebtn" data-face="${f}" aria-label="${faces(f, 2)}" aria-pressed="${p.face === f}"${T.minCount(f) > tot ? ' disabled' : ''}>${die(f)}</button>`).join('')}</div>
      </div>`;
  }
  function otherPicker() {
    patch($('#bid-dialog-body'), `${stepper()}<div class="row"><button class="block block--primary" data-act="other-raise">${S.game.bid ? 'Raise to' : 'Bid'} ${bidn(pk.count, pk.face)}</button><button class="block" data-dialog-close>Cancel</button></div>`);
  }

  document.addEventListener('click', (e) => {
    const closer = e.target.closest('[data-dialog-close]');
    if (closer) return closer.closest('dialog').close();
    if (e.target.matches('dialog[open]')) return e.target.close();
    const t = e.target.closest('[data-act], [data-raise], [data-face], [data-step], [data-cell], [data-rx], [data-person]');
    if (!$('#rxtray').hidden && !e.target.closest('#rxtray, [data-act="react"]')) $('#rxtray').hidden = true;
    if (!t || t.disabled) return;
    if (t.dataset.act) { if (t.dataset.act !== 'sitout') ACT[t.dataset.act]?.(t); return; }
    if (t.dataset.raise) { const [c, f] = t.dataset.raise.split(',').map(Number); return T.raise('me', c, f); }
    if (t.dataset.face) { setFace(+t.dataset.face); return repick(); }
    if (t.dataset.step) { stepCount(+t.dataset.step); return repick(); }
    if (t.dataset.cell) { const [c, f] = t.dataset.cell.split(',').map(Number); if (T.canRaise(c, f)) { pk.count = c; pk.face = f; } return repick(); }
    if (t.dataset.rx) {
      $('#rxtray').hidden = true;
      if (T.react('me', t.dataset.rx)) { const bars = $$('#rxbar, .rxnote'); bars.forEach((x) => x.classList.add('is-cooling')); setTimeout(() => bars.forEach((x) => x.classList.remove('is-cooling')), 2000); const b = $('[data-act="react"]'); b.classList.remove('cooling'); void b.offsetWidth; b.classList.add('cooling'); b.disabled = true; setTimeout(() => { b.disabled = false; b.classList.remove('cooling'); }, 2000); }
      return;
    }
    if (t.dataset.person && T.iAmHost() && t.dataset.person !== 'me') {
      const p = T.person(t.dataset.person), mid = T.isPlaying(p.id);
      $('#seat-dialog-body').innerHTML = `<h2>${esc(p.name)}</h2>
        <div class="stack">
          <button class="block" data-act="makehost" data-id="${p.id}"${p.away ? ' disabled' : ''}>Make ${esc(p.name)} the Host</button>
          <button class="block block--dark" data-act="remove" data-id="${p.id}">Remove from the Room</button>
        </div>
        <small>${mid ? `Removing a Player mid-Game Knocks them out and voids the Round. ` : ''}${esc(p.name)} can come back with the Room code, as a Spectator.</small>
        <div class="row"><button class="block" data-dialog-close>Cancel</button></div>`;
      dialog('seat-dialog').showModal();
    }
  });
  document.addEventListener('change', (e) => { if (e.target.dataset.act === 'sitout') ACT.sitout(e.target); });
  document.addEventListener('keydown', (e) => {
    if ((e.key === 'Enter' || e.key === ' ') && e.target.matches('[data-person][role="button"]')) { e.preventDefault(); e.target.click(); }
    const typing = e.target.matches?.('input, textarea, [contenteditable]');
    if (!typing && !$('dialog[open]') && (e.key === '[' || e.key === ']')) cycle(e.key === '[' ? -1 : 1);
  });
  const repick = () => { if (dialog('bid-dialog').open) otherPicker(); render(); };

  // ---- the floating prototype bar ----------------------------------------------------------
  const SCENES = [
    ['Lobby', 'lobby'], ['Your turn', 'my-turn'], ['You open the Round', 'my-open'], ['Others are playing', 'watching'],
    ['Check: Bluff caught', 'reveal-caught'], ['Check: the Bid stands', 'reveal-stood'],
    ['Player on turn is Away', 'away-turn'], ['Host is Away, the vote', 'host-away'],
    ["You're Knocked out", 'knocked-out'], ['Game over', 'over'], ['20 seats, 100 dice', 'hundred'],
  ];
  const keys = () => Object.keys(window.Variants);
  const syncUrl = () => history.replaceState(null, '', location.pathname + '?' + params);
  function setVariant(k) { root.dataset.variant = k; params.set('variant', k); syncUrl(); mounted = ''; render(); }
  function cycle(step) { const ks = keys(), i = ks.indexOf(root.dataset.variant); setVariant(ks[(i + step + ks.length) % ks.length]); }
  function runScene(key) { params.set('scene', key); T.scene(key); params.set('seats', S.opt.seats); params.set('host', S.opt.host); syncUrl(); }
  let bar;
  function syncBar() {
    if (!bar) return;
    const V = window.Variants[root.dataset.variant];
    $('.pbar__label', bar).innerHTML = `<b>${root.dataset.variant}</b><span class="pbar__name"> / ${V.name}</span>`;
    $$('[data-seats]', bar).forEach((b) => b.setAttribute('aria-pressed', +b.dataset.seats === S.opt.seats));
    $('[data-tog="host"]', bar).textContent = (S.hostId === 'me' ? '✓ ' : '') + 'You are the Host';
    $('[data-tog="spec"]', bar).textContent = (S.viewAs === 'spectator' ? '✓ ' : '') + 'See it as a Spectator';
  }
  function buildBar() {
    bar = document.createElement('div');
    bar.className = 'pbar';
    bar.innerHTML = `
      <button data-pbar="prev" aria-label="Previous layout" title="Previous layout ( [ )">&larr;</button>
      <span class="pbar__label"></span>
      <button data-pbar="next" aria-label="Next layout" title="Next layout ( ] )">&rarr;</button>
      <span class="pbar__sep"></span>
      <button data-pbar="scenes" aria-haspopup="true">Screens</button>
      <button data-pbar="min" aria-label="Hide or show this bar" title="Hide this bar">&#9662;</button>
      <div class="pbar__menu" hidden>
        ${SCENES.map(([label, key]) => `<button data-scene="${key}">${label}</button>`).join('')}
        <hr><div class="seatsrow">Seats ${[2, 4, 5, 6, 8, 12, 20].map((n) => `<button data-seats="${n}">${n}</button>`).join('')}</div>
        <button data-tog="host"></button><button data-tog="spec"></button><button data-tog="theme">Light or dark</button>
      </div>`;
    document.body.append(bar);
    const menu = $('.pbar__menu', bar);
    bar.addEventListener('click', (e) => {
      const b = e.target.closest('button'); if (!b) return;
      if (b.dataset.scene) { menu.hidden = true; return runScene(b.dataset.scene); }
      if (b.dataset.seats) { S.opt.seats = +b.dataset.seats; return runScene(params.get('scene') || 'my-turn'); }
      if (b.dataset.tog === 'host') { S.opt.host = S.hostId === 'me' ? 'other' : 'me'; return runScene(params.get('scene') || 'my-turn'); }
      if (b.dataset.tog === 'spec') { S.viewAs = S.viewAs === 'spectator' ? 'self' : 'spectator'; mounted = ''; return render(); }
      if (b.dataset.tog === 'theme') return ACT.theme();
      const a = b.dataset.pbar;
      if (a === 'prev') cycle(-1); if (a === 'next') cycle(1);
      if (a === 'scenes') menu.hidden = !menu.hidden;
      if (a === 'min') { const min = bar.classList.toggle('is-min'); document.body.classList.toggle('pbar-min', min); b.innerHTML = min ? '&#9652;' : '&#9662;'; menu.hidden = true; }
    });
    document.addEventListener('click', (e) => { if (!bar.contains(e.target)) menu.hidden = true; });
  }

  window.H = { $, $$, esc, pips, die, blanks, bidn, token, nm, faces, words, up, tally, awayTag, patch, keyed, hand, picker, pk, quick, stepper, who, sv, lines, waiting };
  window.Variants = window.Variants || {};

  document.addEventListener('DOMContentLoaded', () => {
    root.dataset.theme = params.get('theme') || 'light';
    root.dataset.variant = keys().includes(params.get('variant')) ? params.get('variant') : keys().includes('4') ? '4' : keys()[0];
    S.opt.seats = Math.max(2, Math.min(20, +params.get('seats') || 5));
    S.opt.host = params.get('host') === 'other' ? 'other' : 'me';
    $('#rxbar').innerHTML = $('#rxtray').innerHTML = T.REACTIONS.map((r) => `<button data-rx="${r.key}" class="${r.line ? 'is-line' : ''}" aria-label="${r.line || r.key}">${r.emoji || r.line}</button>`).join('');
    $$('[data-g]').forEach((el) => { el.innerHTML = '<svg viewBox="0 0 48 48" width="18" height="18" aria-hidden="true"><path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/><path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/><path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/><path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/></svg>'; });
    buildBar();
    fit();
    runScene(T.scenes.includes(params.get('scene')) ? params.get('scene') : 'my-turn');
  });
})();
