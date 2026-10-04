// PROTOTYPE, throwaway. Layout 1: "Round table".
// Seats sit in a ring with the Bid on a scrap in the middle, the way a table looks from above.
// You are at the bottom and turn order runs clockwise. The picker is two dials: a count and a face.
// Check is the dark walnut block.
(() => {
  const T = window.Table, S = T.S, H = window.H;

  function seat(id, compact) {
    const g = S.game, r = g.reveal, p = T.person(id);
    const gone = g.out.includes(id) && !(r && r.loser === id);
    let dice = '';
    if (!gone) {
      if (r && r.step >= 1) dice = g.dice[id].map((f) => H.die(f, 'is-flip ' + (f === r.bid.face ? 'is-hit' : 'is-miss'))).join('') + (r.step >= 3 && r.loser === id ? H.die(0, 'is-penalty') : '');
      else if (id === 'me' && T.seesOwnDice()) dice = '';        // your own dice are the big ones right below
      else dice = compact ? `<b class="seat__n">${g.n[id]}</b>${H.die(0, 'is-down')}` : H.blanks(g.n[id]);
    }
    const said = [...g.bids].reverse().find((b) => b.by === id);
    const chip = said && !r && (!compact || said === g.bid) ? `<span class="seat__said${said === g.bid ? ' is-now' : ''}">${H.bidn(said.count, said.face)}</span>` : '';
    const tag = gone ? 'out' : p.away ? H.awayTag(p) : '';
    return `${H.token(p)}<span class="seat__name">${H.nm(p)}</span><span class="seat__dice">${dice}</span>${tag ? `<small>${tag}</small>` : ''}${chip}`;
  }

  function mid() {
    const g = S.game, r = g.reveal, tot = T.total();
    const table = `<p class="faint">${tot} dice on the table</p>`;
    if (S.sub === 'rolling') return `<p class="faint">Round ${g.round}</p><p class="scrawl">Everyone rolls.</p>`;
    if (r) {
      const L = H.lines(r);
      if (r.step === 0) return `<p class="scrawl red slam">${L.call}</p>${H.bidn(r.bid.count, r.bid.face)}`;
      if (r.step === 1) return `${H.bidn(r.bid.count, r.bid.face)}<p class="faint">counting the ${H.faces(r.bid.face, 2)}</p>`;
      return `<p class="scrawl">${L.count}</p><p class="scrawl red">${L.verdict}</p>${r.step >= 3 ? `<p class="mid__small">${L.penalty} ${L.out}</p>` : ''}`;
    }
    if (!g.bid) return `<p class="scrawl">${H.who(g.turn)} ${H.sv(g.turn, 'opens', 'open')} the Round.</p>${table}`;
    return `<p class="faint">${H.who(g.bid.by)} ${H.sv(g.bid.by, 'bids', 'bid')}</p>${H.bidn(g.bid.count, g.bid.face, 'bidn--big')}${table}`;
  }

  function panel() {
    const g = S.game;
    if (!T.seesOwnDice()) return `<div class="paper paper--scrap note">You're watching. ${H.waiting()}</div>`;
    if (!T.myTurn()) return H.waiting() ? `<div class="paper paper--scrap note">${H.waiting()}</div>` : '';
    const p = H.picker();
    return `<div class="paper paper--scrap v1__pick">
        <p class="scrawl">${g.bid ? 'Raise it, or Check it.' : 'You open. Make a Bid.'}</p>
        ${H.stepper()}
        <div class="acts">
          <button class="block block--primary block--big" data-act="raise">${g.bid ? 'Raise to' : 'Bid'} ${H.bidn(p.count, p.face)}</button>
          ${g.bid ? '<button class="block block--dark block--big" data-act="check">Check</button>' : ''}
        </div>
      </div>`;
  }

  window.Variants['1'] = {
    name: 'Round table',
    mount(stage) {
      stage.innerHTML = `<div class="v1">
        <div class="ring"><div class="paper paper--scrap ring__mid" id="v1-mid"></div><div id="v1-seats"></div></div>
        <div class="v1__me" data-anchor="me"><div class="hand" id="v1-hand"></div><div id="v1-panel"></div></div>
      </div>`;
    },
    render() {
      const g = S.game, n = g.seats.length, compact = n > 8;
      const start = g.seats.includes('me') ? g.seats.indexOf('me') : 0;
      const order = g.seats.map((_, i) => g.seats[(start + i) % n]);
      H.keyed(H.$('#v1-seats'), order, (id) => id, (id) => seat(id, compact), (id) => {
        const a = ((90 + (order.indexOf(id) * 360) / n) * Math.PI) / 180, p = T.person(id), r = g.reveal;
        const cls = ['seat', compact && 'seat--compact', g.turn === id && S.sub === 'bidding' && 'is-turn', p.away && 'is-away',
          g.out.includes(id) && !(r && r.loser === id) && 'is-out', r && r.step >= 3 && r.loser === id && 'is-loser', id === 'me' && 'is-me'].filter(Boolean).join(' ');
        return { class: cls, style: `--x:${Math.cos(a).toFixed(4)};--y:${Math.sin(a).toFixed(4)}`, 'data-person': id, 'data-anchor': id };
      });
      H.patch(H.$('#v1-mid'), mid());
      H.hand(H.$('#v1-hand'));
      H.patch(H.$('#v1-panel'), panel());
    },
  };
})();
