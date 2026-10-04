// PROTOTYPE, throwaway. Layout 3: "Your seat".
// The table as you see it from your chair: your dice and your moves take the bottom half,
// the others are a strip across the top, and the Bid sits between as the last thing anyone said.
// The picker is one tap: up to three ready-made Raises, with "Other" for anything else.
// The Check reveal pools every die into six columns, so you count the Bid's column against the Bid.
// Check is the tomato block.
(() => {
  const T = window.Table, S = T.S, H = window.H;

  function chair(id, compact) {
    const g = S.game, r = g.reveal, p = T.person(id);
    const gone = g.out.includes(id) && !(r && r.loser === id);
    const pen = r && r.step >= 3 && r.loser === id;      // the Penalty die lands on the loser's pile
    const dice = gone ? '' : compact ? `<b class="chair__n">${g.n[id]}</b>${H.die(0, pen ? 'is-penalty' : 'is-down')}` : H.blanks(g.n[id] - (pen ? 1 : 0)) + (pen ? H.die(0, 'is-penalty') : '');
    const tag = gone ? 'out' : p.away ? H.awayTag(p) : g.turn === id && S.sub === 'bidding' ? 'on turn' : '';
    return `${H.token(p)}<span class="chair__name">${H.nm(p)}</span><span class="chair__dice">${dice}</span><small>${tag}</small>`;
  }

  function hist(r) {
    const g = S.game, all = g.seats.filter((id) => g.dice[id] && (!g.out.includes(id) || r.loser === id)).flatMap((id) => g.dice[id].map((f) => ({ f, c: T.person(id).color })));
    const tiny = all.length > 40;
    return `<div class="hist${tiny ? ' hist--tiny' : ''}">${[1, 2, 3, 4, 5, 6].map((f) => {
      const col = all.filter((d) => d.f === f), isBid = f === r.bid.face;
      return `<div class="col${isBid ? ' is-bid' : ''}">
        <div class="col__dice">${col.map((d, i) => H.die(f, 'is-flip', `--o:${d.c};animation-delay:${Math.min(i * 40, 600)}ms`)).join('')}</div>
        <b class="col__n">${r.step >= 2 || !isBid ? col.length : '?'}</b>${H.die(f, 'col__face')}
      </div>`;
    }).join('')}</div>`;
  }

  function mid() {
    const g = S.game, r = g.reveal;
    if (S.sub === 'rolling') return `<div class="paper paper--scrap said"><p class="faint">Round ${g.round}</p><p class="scrawl">Everyone rolls.</p></div>`;
    if (r) {
      const L = H.lines(r);
      if (r.step === 0) return `<div class="paper paper--scrap said"><p class="scrawl red slam">${L.call}</p>${H.bidn(r.bid.count, r.bid.face, 'bidn--big')}</div>`;
      return `<div class="paper paper--scrap reveal3">
        <p class="faint">the Bid was ${H.bidn(r.bid.count, r.bid.face)}</p>
        ${hist(r)}
        ${r.step >= 2 ? `<p class="scrawl">${L.count} <span class="red">${L.verdict}</span></p>` : '<p class="scrawl faint">counting</p>'}
        ${r.step >= 3 ? `<p>${L.penalty} ${L.out}</p>` : ''}
      </div>`;
    }
    if (!g.bid) return `<div class="paper paper--scrap said"><p class="scrawl">${H.who(g.turn)} ${H.sv(g.turn, 'opens', 'open')} the Round.</p><p class="faint">${T.total()} dice on the table</p></div>`;
    const trail = g.bids.slice(-4, -1);
    return `<div class="paper paper--scrap said">
      <p class="faint">${H.who(g.bid.by)} ${H.sv(g.bid.by, 'says', 'say')}</p>
      ${H.bidn(g.bid.count, g.bid.face, 'bidn--big')}
      <p class="faint">${T.total()} dice on the table</p>
      ${trail.length ? `<p class="trail">${trail.map((b) => `<s>${H.who(b.by)} ${H.bidn(b.count, b.face)}</s>`).join('')}</p>` : ''}
    </div>`;
  }

  function act() {
    const g = S.game;
    if (!T.myTurn()) return H.waiting() ? `<p class="scrawl v3__wait">${H.waiting()}</p>` : '';
    return `<p class="scrawl">${g.bid ? 'Your turn. Raise it, or Check it.' : 'You open. Make a Bid.'}</p>
      <div class="quick">${H.quick().map((o) => `<button class="block block--big" data-raise="${o.c},${o.f}" aria-label="${g.bid ? 'Raise to' : 'Bid'} ${H.words(o.c, o.f)}">${H.bidn(o.c, o.f)}</button>`).join('')}<button class="block block--big" data-act="other">Other</button></div>
      ${g.bid ? '<button class="block block--primary block--big block--wide" data-act="check">Check</button>' : ''}`;
  }

  let lastTurn = null;
  window.Variants['3'] = {
    name: 'Your seat',
    mount(stage) {
      stage.innerHTML = `<div class="v3">
        <div class="v3__strip" id="v3-strip"></div>
        <div class="v3__mid" id="v3-mid"></div>
        <div class="paper v3__mat" id="v3-mat" data-anchor="me"><span class="tape" aria-hidden="true"></span><div class="hand" id="v3-hand"></div><div id="v3-act"></div></div>
        <div class="paper paper--scrap note" id="v3-note" hidden></div>
      </div>`;
      lastTurn = null;
    },
    render() {
      const g = S.game, r = g.reveal, n = g.seats.length, mine = T.seesOwnDice();
      // the others, in turn order, starting with whoever plays after you
      const start = g.seats.includes('me') ? g.seats.indexOf('me') + 1 : 0;
      const order = g.seats.map((_, i) => g.seats[(start + i) % n]).filter((id) => id !== 'me' || !mine);
      const strip = H.$('#v3-strip');
      H.keyed(strip, order, (id) => id, (id) => chair(id, n > 8), (id) => ({
        class: ['chair', n > 8 && 'chair--compact', g.turn === id && S.sub === 'bidding' && 'is-turn', T.person(id).away && 'is-away', g.out.includes(id) && !(r && r.loser === id) && 'is-out',
          g.bid && g.bid.by === id && !r && 'is-bidder', r && r.step >= 3 && r.loser === id && 'is-loser'].filter(Boolean).join(' '),
        'data-person': id, 'data-anchor': id,
      }));
      if (g.turn !== lastTurn) { lastTurn = g.turn; const el = strip.querySelector('.is-turn'); if (el && strip.scrollWidth > strip.clientWidth) strip.scrollTo({ left: el.offsetLeft - strip.clientWidth / 2 + el.offsetWidth / 2, behavior: 'smooth' }); }
      H.patch(H.$('#v3-mid'), mid());
      H.$('#v3-mat').hidden = !mine;
      H.$('#v3-note').hidden = mine;
      H.patch(H.$('#v3-note'), `You're watching. ${H.waiting()}`);
      H.hand(H.$('#v3-hand'));
      H.patch(H.$('#v3-act'), act());
    },
  };
})();
