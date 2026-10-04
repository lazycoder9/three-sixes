// PROTOTYPE, throwaway. Layout 4: "Table and seat", layouts 1 and 3 merged, then tuned from feedback.
// From 1: the table's shape, and the count. On a Check every die turns over where it sits and the ones
//         that match the Bid light up, yours included.
// From 3: your seat is a notebook page with your dice on it.
// The picker offers only the next Raises, in two rows: what is left at the Bid's count, and every face at one more.
//      One tap Raises. Keys: 1 to 6 Raise with that face, the arrows (or + and -) step the count up, C Checks.
// The page is small, so the table gets the height. On a desktop everything is sized from one unit, --u,
// worked out from the window so the whole thing fits without scrolling.
(() => {
  const T = window.Table, S = T.S, H = window.H, ALL = [1, 2, 3, 4, 5, 6];

  // ---- the Raises on offer -------------------------------------------------------
  // Bid 3 x 4 offers 3 x 5 and 3 x 6, then 4 x anything. The second row can be stepped higher for a jump.
  let bump = 0, bumpKey = '';
  function rows() {
    const g = S.game, tot = T.total(), b = g.bid, key = g.rid + ':' + (b ? b.count + 'x' + b.face : 'open');
    if (key !== bumpKey) { bumpKey = key; bump = 0; }
    const min = b ? b.count + 1 : 1;
    bump = Math.max(0, Math.min(tot - min, bump));
    const out = [];
    if (b && b.face < 6) out.push({ count: b.count, faces: ALL.filter((f) => f > b.face) });
    if (min <= tot) out.push({ count: min + bump, faces: ALL, step: tot > min, atMax: min + bump >= tot });
    return out;
  }

  function seat(id, compact) {
    const g = S.game, r = g.reveal, p = T.person(id);
    const gone = g.out.includes(id) && !(r && r.loser === id);
    let dice = '';
    if (!gone) {
      // on a Check the dice turn over where they sit, and the ones that match the Bid light up
      if (r && r.step >= 1) dice = g.dice[id].map((f) => H.die(f, 'is-flip ' + (f === r.bid.face ? 'is-hit' : 'is-miss'))).join('') + (r.step >= 3 && r.loser === id ? H.die(0, 'is-penalty') : '');
      else dice = compact ? `<b class="seat__n">${g.n[id]}</b>${H.die(0, 'is-down')}` : H.blanks(g.n[id]);
    }
    const said = [...g.bids].reverse().find((b) => b.by === id);
    const chip = said && !r && (!compact || said === g.bid) ? `<span class="seat__said${said === g.bid ? ' is-now' : ''}">${H.bidn(said.count, said.face)}</span>` : '';
    const tag = gone ? 'out' : p.away ? H.awayTag(p) : '';
    return `${H.token(p)}<span class="seat__name">${H.nm(p)}</span><span class="seat__dice">${dice}</span>${tag ? `<small>${tag}</small>` : ''}${chip}`;
  }

  function mid() {
    const g = S.game, r = g.reveal, table = `<p class="faint">${T.total()} dice on the table</p>`;
    if (S.sub === 'rolling') return `<p class="faint">Round ${g.round}</p><p class="scrawl">Everyone rolls.</p>`;
    if (r) {
      const L = H.lines(r);
      if (r.step === 0) return `<p class="scrawl red slam">${L.call}</p>${H.bidn(r.bid.count, r.bid.face)}`;
      // the count is written the way a Bid is, not in words: the Bid on top, what the table really holds below it, big
      const found = `<p class="mid__bid faint">Bid ${H.bidn(r.bid.count, r.bid.face)}</p>
        <p class="mid__found${r.step >= 2 ? ' slam' : ''}" aria-label="${r.step >= 2 ? L.count : 'counting'}">${H.bidn(r.step >= 2 ? r.n : '?', r.bid.face)}</p>`;
      if (r.step === 1) return found;
      const pen = r.step >= 3 ? `<p class="mid__pen">${H.who(r.loser)} <b>+</b>${H.die(0, 'is-penalty')}${r.knocked ? '<em class="red">Knocked out</em>' : ''}</p>` : '';
      return `${found}<p class="scrawl red">${L.verdict}</p>${pen}`;
    }
    if (!g.bid) return `<p class="scrawl">${H.who(g.turn)} ${H.sv(g.turn, 'opens', 'open')} the Round.</p>${table}`;
    return `<p class="faint">${H.who(g.bid.by)} ${H.sv(g.bid.by, 'bids', 'bid')}</p>${H.bidn(g.bid.count, g.bid.face)}${table}`;
  }

  function opts() {
    const g = S.game, my = T.myTurn(), rs = rows(), verb = g.bid ? 'Raise to' : 'Bid';
    if (!rs.length) return `<div class="opts${S.sub === 'bidding' ? '' : ' is-hidden'}"><p class="faint">Nothing higher is left to say.</p></div>`;
    return `<div class="opts${my ? '' : ' is-off'}${S.sub === 'bidding' ? '' : ' is-hidden'}">${rs.map((r) => `<div class="orow"><b>${r.count} &times;</b>${ALL.map((f) => (r.faces.includes(f)
      ? `<button class="pickdie"${my ? ` data-raise="${r.count},${f}"` : ' disabled'} aria-label="${verb} ${H.words(r.count, f)}">${H.die(f)}</button>`
      : '<span class="pickgap"></span>')).join('')}<span class="orow__step">${r.step
      ? `${bump ? '<button class="roundbtn" data-bump="-1" aria-label="One fewer">&minus;</button>' : ''}<button class="roundbtn" data-bump="1" aria-label="One more"${r.atMax ? ' disabled' : ''}>+</button>` : ''}</span></div>`).join('')}</div>`;
  }

  function act() {
    const g = S.game, my = T.myTurn();
    const head = my ? (g.bid ? 'Your turn. Raise it, or Check it.' : 'You open. Make a Bid.') : H.waiting() || '&nbsp;';
    return `<p class="scrawl v4__head${my ? '' : ' faint'}">${head}</p>
      ${opts()}
      <button class="block block--primary block--big v4__check" data-act="check"${my && g.bid ? '' : ' disabled'}>Check<kbd>C</kbd></button>
      <p class="keys"><span><kbd>1</kbd> to <kbd>6</kbd> Raise with that face</span><span><kbd>&larr;</kbd> <kbd>&rarr;</kbd> count</span></p>`;
  }

  const step = (d) => { bump = Math.max(0, bump + d); T.emit(); };
  document.addEventListener('click', (e) => { const b = e.target.closest('[data-bump]'); if (b && !b.disabled && T.myTurn()) step(+b.dataset.bump); });
  document.addEventListener('keydown', (e) => {
    if (document.documentElement.dataset.variant !== '4' || !T.myTurn() || e.metaKey || e.ctrlKey || e.altKey) return;
    if (document.querySelector('dialog[open]') || e.target.matches?.('input, textarea, [contenteditable]')) return;
    const g = S.game, k = e.key;
    if (k >= '1' && k <= '6') {
      // the cheapest Raise on offer with that face; once you have stepped the count up, the stepped row
      const f = +k, rs = rows(), r = (bump ? null : rs.find((x) => x.faces.includes(f))) || rs[rs.length - 1];
      if (r && r.faces.includes(f) && T.canRaise(r.count, f)) { e.preventDefault(); T.raise('me', r.count, f); }
    } else if (k === 'ArrowRight' || k === '+' || k === '=') { e.preventDefault(); step(1); }
    else if (k === 'ArrowLeft' || k === '-' || k === '_') { e.preventDefault(); step(-1); }
    else if ((k === 'c' || k === 'C') && g.bid) { e.preventDefault(); T.check('me'); }
  });

  // seats spaced evenly along the edge of the table, not by angle: on a wide, low table equal angles
  // would bunch everyone up at the two ends. ratio is the ellipse's width over its height.
  function ringPoints(n, ratio) {
    const N = 720, cum = [0]; let px = 0, py = 1;
    for (let i = 1; i <= N; i++) { const t = Math.PI / 2 + (i / N) * 2 * Math.PI, x = ratio * Math.cos(t), y = Math.sin(t); cum.push(cum[i - 1] + Math.hypot(x - px, y - py)); px = x; py = y; }
    return Array.from({ length: n }, (_, k) => { const i = cum.findIndex((c) => c >= (k / n) * cum[N]), t = Math.PI / 2 + (i / N) * 2 * Math.PI; return [Math.cos(t), Math.sin(t)]; });
  }
  // a crowded table is a long one: two straight sides and two round ends, so nobody is squeezed at the ends
  function longTable(n, a, b) {
    if (a <= b * 1.3) return ringPoints(n, a / b);
    const s = a - b, arc = Math.PI * b, P = 4 * s + 2 * arc;
    return Array.from({ length: n }, (_, k) => {
      let d = (k / n) * P;
      if (d < s) return [-d / a, 1];
      d -= s; if (d < arc) return [(-s - b * Math.sin(d / b)) / a, Math.cos(d / b)];
      d -= arc; if (d < 2 * s) return [(-s + d) / a, -1];
      d -= 2 * s; if (d < arc) return [(s + b * Math.sin(d / b)) / a, -Math.cos(d / b)];
      return [(s - (d - arc)) / a, 1];
    });
  }

  // Reactions sit by your hand: faces first, then the short line, then the two long ones
  const RX = ['lol', 'gasp', 'hmm', 'clap', 'fire', 'gg', 'noway', 'checkit'].map((k) => T.REACTIONS.find((r) => r.key === k));

  window.Variants['4'] = {
    name: 'Table and seat',
    mount(stage) {
      stage.innerHTML = `<div class="v4">
        <div class="v4__table"><div id="v4-seats"></div><div class="paper paper--scrap v4__mid" id="v4-mid"></div></div>
        <div class="v4__bottom">
          <div class="paper v4__mat" id="v4-mat" data-anchor="me"><span class="tape" aria-hidden="true"></span><div class="hand" id="v4-hand"></div><div id="v4-act"></div></div>
          <div class="paper paper--scrap note" id="v4-note" hidden></div>
          <div class="sticky rxnote" aria-label="Send a Reaction">${RX.map((r) => `<button data-rx="${r.key}" class="${r.line ? 'is-line' : ''}" aria-label="${r.line || r.key}">${r.emoji || r.line}</button>`).join('')}</div>
        </div>
      </div>`;
    },
    render() {
      // fit the window: what is left under the Room bar and any banner, shared between the table and your page
      const box = H.$('.v4'), narrow = innerWidth <= 720;
      if (narrow) { box.style.removeProperty('--u'); box.style.minHeight = ''; } else {
        const pad = parseFloat(getComputedStyle(document.body).paddingBottom), side = innerWidth >= 1000;   // room for Reactions beside your page
        const avail = innerHeight - (H.$('#stage').getBoundingClientRect().top + scrollY) - pad - 4;
        const u = Math.max(.75, Math.min(innerWidth / 1100, side ? (innerWidth - 120) / 1118 : 9, (avail - (side ? 62 : 124)) / 596, 1.8));
        box.style.setProperty('--u', u.toFixed(3) + 'px'); box.style.minHeight = Math.max(0, avail) + 'px';
      }
      const g = S.game, r = g.reveal, n = g.seats.length, mine = T.seesOwnDice(), compact = n > 8 || (narrow && n > 5);
      // your place at the table is the gap at the bottom, where your page lies
      const start = g.seats.includes('me') ? g.seats.indexOf('me') : 0;
      const order = g.seats.map((_, i) => g.seats[(start + i) % n]);
      const shown = order.filter((id) => id !== 'me' || !mine);
      // on a narrow screen a small table is an arc across the top, which leaves the middle free for the Bid
      const arc = narrow && mine && shown.length <= 4, spread = Math.min(50, 150 / Math.max(1, shown.length - 1));
      const tb = H.$('.v4__table').getBoundingClientRect(), u1 = parseFloat(box.style.getPropertyValue('--u')) || 1;
      const sw = narrow ? (compact ? 52 : 88) : (compact ? 66 : 128) * u1, sh = narrow ? (compact ? 58 : 92) : (compact ? 70 : 118) * u1;
      const a = Math.max(1, (tb.width - sw) / 2), b = Math.max(1, (tb.height - sh) / 2);
      const ring = arc ? null : compact ? longTable(n, a, b) : ringPoints(n, Math.max(1, a / b));
      const at = (id) => { if (!arc) return ring[order.indexOf(id)]; const t = ((270 + (shown.indexOf(id) - (shown.length - 1) / 2) * spread) * Math.PI) / 180; return [Math.cos(t), Math.sin(t)]; };
      H.keyed(H.$('#v4-seats'), shown, (id) => id, (id) => seat(id, compact), (id) => {
        const [x, y] = at(id), p = T.person(id);
        const cls = ['seat', compact && 'seat--compact', g.turn === id && S.sub === 'bidding' && 'is-turn', p.away && 'is-away',
          g.out.includes(id) && !(r && r.loser === id) && 'is-out', r && r.step >= 3 && r.loser === id && 'is-loser'].filter(Boolean).join(' ');
        return { class: cls, style: `--x:${x.toFixed(4)};--y:${y.toFixed(4)}`, 'data-person': id, 'data-anchor': id };
      });
      H.$('.v4__table').classList.toggle('is-ring', !arc);
      H.patch(H.$('#v4-mid'), mid());

      const mat = H.$('#v4-mat');
      mat.hidden = !mine; mat.classList.toggle('is-turn', T.myTurn());
      H.$('#v4-note').hidden = mine;
      H.patch(H.$('#v4-note'), `You're watching. ${H.waiting()}`);
      // your own dice take part in the count too: matches light up, and a Penalty die lands next to them
      const hand = H.$('#v4-hand');
      H.hand(hand);
      const counting = !!(r && r.step >= 1) && mine;
      [...hand.querySelectorAll('.slot:not(.slot--pen)')].forEach((el, i) => {
        const hit = counting && g.dice.me[i] === r.bid.face;
        el.classList.toggle('is-hit', hit); el.classList.toggle('is-miss', counting && !hit);
      });
      if (mine && r && r.step >= 3 && r.loser === 'me' && !hand.querySelector('.slot--pen')) hand.insertAdjacentHTML('beforeend', `<span class="slot slot--pen">${H.die(0, 'is-penalty')}</span>`);
      H.patch(H.$('#v4-act'), act());
    },
  };
})();
