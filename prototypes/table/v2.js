// PROTOTYPE, throwaway. Layout 2: "The pad".
// The whole table is one notebook page: a row per Player in turn order, their dice as pencil squares,
// and what each one last said written beside them. It reads top to bottom and scrolls, so 20 seats cost nothing.
// The picker is a grid of every Bid you may make, with the ones you may not make crossed out.
// Check is written on the page in red pencil.
(() => {
  const T = window.Table, S = T.S, H = window.H;

  function row(id) {
    const g = S.game, r = g.reveal, p = T.person(id);
    const gone = g.out.includes(id) && !(r && r.loser === id);
    let dice = '';
    if (!gone) {
      if (r && r.step >= 1) dice = g.dice[id].map((f) => H.die(f, 'is-flip ' + (f === r.bid.face ? 'is-hit' : 'is-miss'))).join('') + (r.step >= 3 && r.loser === id ? '<b class="plus red">+1</b>' : '');
      else dice = '<i class="sq"></i>'.repeat(g.n[id]);
    }
    const said = [...g.bids].reverse().find((b) => b.by === id);
    const tag = gone ? 'out' : p.away ? H.awayTag(p) : '';
    return `<span class="row__mark">${g.turn === id && S.sub === 'bidding' ? '&rarr;' : ''}</span>${H.token(p)}
      <span class="row__name">${p.me ? '<span class="hl">You</span>' : H.esc(p.name)}${tag ? `<small>${tag}</small>` : ''}</span>
      <span class="row__dice">${dice}</span>
      <span class="row__said${said && said === g.bid ? ' is-now' : ''}">${said && !gone ? H.bidn(said.count, said.face) : ''}</span>`;
  }

  function head() {
    const g = S.game, r = g.reveal;
    let main;
    if (S.sub === 'rolling') main = `<p class="scrawl v2__big">Everyone rolls.</p>`;
    else if (r) {
      const L = H.lines(r);
      main = r.step === 0 ? `<p class="scrawl red v2__big slam"><span class="circled">${L.call}</span></p>`
        : r.step === 1 ? `<p class="faint">the Bid was</p>${H.bidn(r.bid.count, r.bid.face, 'bidn--big')}`
          : `<p class="scrawl v2__big">${L.count}</p><p class="scrawl red v2__big">${L.verdict}</p>${r.step >= 3 ? `<p>${L.penalty} ${L.out}</p>` : ''}`;
    } else if (!g.bid) main = `<p class="scrawl v2__big">${H.who(g.turn)} ${H.sv(g.turn, 'opens', 'open')} the Round.</p>`;
    else main = `<p class="faint">${g.bid.by === 'me' ? 'your' : H.who(g.bid.by) + "'s"} Bid</p>${H.bidn(g.bid.count, g.bid.face, 'bidn--big')}`;
    return `<div class="v2__top"><h2>Round ${g.round}</h2><span class="faint">${T.total()} dice on the table</span></div><div class="v2__bid">${main}</div>`;
  }

  function act() {
    const g = S.game;
    if (!T.seesOwnDice()) return `<div class="paper paper--scrap note">You're watching. ${H.waiting()}</div>`;
    if (!T.myTurn()) return H.waiting() ? `<div class="paper paper--scrap note">${H.waiting()}</div>` : '';
    const p = H.picker(), tot = T.total(), from = g.bid ? g.bid.count : 1;
    const rows = [];
    for (let c = from; c <= tot; c++) {
      rows.push(`<div class="grid2__row"><b>${c} &times;</b>${[1, 2, 3, 4, 5, 6].map((f) => {
        const ok = T.canRaise(c, f), on = p.count === c && p.face === f;
        return `<button class="cell${ok ? '' : ' no'}${on ? ' on' : ''}" data-cell="${c},${f}" aria-label="${H.words(c, f)}"${ok ? '' : ' disabled'} aria-pressed="${on}"></button>`;
      }).join('')}</div>`);
    }
    return `<div class="paper paper--scrap sheet2">
        <p class="scrawl">${g.bid ? 'Raise it, or Check it.' : 'You open. Make a Bid.'}</p>
        <div class="grid2">
          <div class="grid2__row grid2__head"><b></b>${[1, 2, 3, 4, 5, 6].map((f) => `<span>${H.die(f)}</span>`).join('')}</div>
          <div class="grid2__body" id="v2-grid">${rows.join('')}</div>
        </div>
        <div class="acts">
          <button class="block block--primary block--big" data-act="raise">${g.bid ? 'Raise to' : 'Bid'} ${H.bidn(p.count, p.face)}</button>
          ${g.bid ? '<button class="checkpen" data-act="check">Check!</button>' : ''}
        </div>
      </div>`;
  }

  window.Variants['2'] = {
    name: 'The pad',
    mount(stage) {
      stage.innerHTML = `<div class="v2">
        <div class="paper v2__page"><span class="tape" aria-hidden="true"></span><div id="v2-head"></div><ol class="v2__rows" id="v2-rows"></ol></div>
        <div class="v2__side" data-anchor="me"><div class="hand" id="v2-hand"></div><div id="v2-act"></div></div>
      </div>`;
    },
    render() {
      const g = S.game, r = g.reveal;
      H.patch(H.$('#v2-head'), head());
      const box = H.$('#v2-rows');
      box.classList.toggle('is-tight', g.seats.length > 8);
      H.keyed(box, g.seats, (id) => id, row, (id) => ({
        class: ['row', g.turn === id && S.sub === 'bidding' && 'is-turn', T.person(id).away && 'is-away', g.out.includes(id) && !(r && r.loser === id) && 'is-out', r && r.step >= 3 && r.loser === id && 'is-loser'].filter(Boolean).join(' '),
        'data-person': id, 'data-anchor': id,
      }), 'li');
      H.hand(H.$('#v2-hand'));
      const old = H.$('#v2-grid'), top = old ? old.scrollTop : 0;      // keep the grid where it was scrolled to
      H.patch(H.$('#v2-act'), act());
      const grid = H.$('#v2-grid'); if (grid) grid.scrollTop = top;
    },
  };
})();
