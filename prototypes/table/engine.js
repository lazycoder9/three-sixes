// PROTOTYPE, throwaway. Issue #7: the game table.
// A fake Room and a real-enough Game: the locked ruleset, bots that Bid and Check, Away, the Host vote,
// Reactions. Everything lives in memory in this tab. None of this is production code; the real rules
// core will be Elixir. It exists so the three table layouts can be judged while a Game is actually running.
(() => {
  const NAMES = ['Timur', 'Malika', 'Aziz', 'Sasha', 'Kamila', 'Rustam', 'Lola', 'Bek', 'Nodira', 'Farrukh', 'Zara', 'Oleg', 'Madina', 'Jamshid', 'Aziza', 'Daniyar', 'Sevara', 'Ilya', 'Nargiza', 'Anvar', 'Dilnoza'];
  const COLORS = ['#D5452F', '#1F5F66', '#B9860F', '#6B3F2A', '#7A4B7C', '#5E7B3A', '#2F4A7A', '#B5652B'];
  // the proposed final set of Reactions: five faces, three lines
  const REACTIONS = [
    { key: 'lol', emoji: '😂' }, { key: 'gasp', emoji: '😱' }, { key: 'hmm', emoji: '🤨' }, { key: 'clap', emoji: '👏' }, { key: 'fire', emoji: '🔥' },
    { key: 'noway', line: 'No way' }, { key: 'checkit', line: 'Check it!' }, { key: 'gg', line: 'GG' },
  ];

  const subs = { state: new Set(), react: new Set(), toast: new Set(), sfx: new Set() };
  const on = (ch, fn) => subs[ch].add(fn);
  const fire = (ch, ...a) => subs[ch].forEach((fn) => fn(...a));
  const emit = () => fire('state');

  const S = {
    opt: { seats: 5, host: 'me' },
    phase: 'lobby',          // lobby | play | over
    sub: null,               // rolling | bidding | reveal
    people: [], hostId: 'me', tally: {}, game: null, last: null,
    vote: null, voteCooldown: 0, left: false, viewAs: 'self', lastReact: {},
  };

  let timers = [];
  const later = (fn, ms) => { const id = setTimeout(() => { timers = timers.filter((t) => t !== id); fn(); }, ms); timers.push(id); return id; };
  const clearTimers = () => { timers.forEach(clearTimeout); timers = []; };
  const rnd = (n) => Math.floor(Math.random() * n);
  const pick = (a) => a[rnd(a.length)];
  const shuffle = (a) => { const b = a.slice(); for (let i = b.length - 1; i > 0; i--) { const j = rnd(i + 1); [b[i], b[j]] = [b[j], b[i]]; } return b; };

  // ---- people ---------------------------------------------------------------
  const person = (id) => S.people.find((p) => p.id === id);
  const inRoom = () => S.people.filter((p) => !p.left);
  const connected = () => inRoom().filter((p) => !p.away);
  const name = (id) => { const p = person(id); return p ? (p.me ? 'You' : p.name) : '?'; };
  const iAmHost = () => S.hostId === 'me';

  // ---- rules ----------------------------------------------------------------
  const alive = (g = S.game) => g.seats.filter((id) => !g.out.includes(id));
  const total = (g = S.game) => alive(g).reduce((n, id) => n + g.n[id], 0);
  const nextAlive = (id, g = S.game) => {
    let i = g.seats.indexOf(id);
    for (let k = 0; k < g.seats.length; k++) { i = (i + 1) % g.seats.length; if (!g.out.includes(g.seats[i])) return g.seats[i]; }
    return null;
  };
  // the lowest count a Raise to this face may have
  const minCount = (face, g = S.game) => (!g.bid ? 1 : face > g.bid.face ? g.bid.count : g.bid.count + 1);
  const canRaise = (count, face, g = S.game) => face >= 1 && face <= 6 && count >= minCount(face, g) && count <= total(g);
  const anyRaise = (g = S.game) => [1, 2, 3, 4, 5, 6].some((f) => minCount(f, g) <= total(g));
  const isPlaying = (id) => S.phase === 'play' && S.game.seats.includes(id) && !S.game.out.includes(id);
  const myTurn = () => S.phase === 'play' && S.sub === 'bidding' && S.game.turn === 'me';
  const seesOwnDice = () => isPlaying('me') && S.viewAs !== 'spectator';

  function startGame() {
    const dealt = connected().filter((p) => !p.sitOut).map((p) => p.id);
    if (dealt.length < 2) return;
    clearTimers();
    const seats = shuffle(dealt);
    S.game = { seats, n: Object.fromEntries(seats.map((id) => [id, 1])), dice: {}, out: [], round: 0, bid: null, bids: [], turn: null, reveal: null, rid: 0 };
    S.phase = 'play'; S.last = null;
    newRound(pick(seats));
  }

  function newRound(opener) {
    const g = S.game;
    g.round += 1; g.rid = Math.random(); g.bid = null; g.bids = []; g.reveal = null; g.turn = opener;
    alive().forEach((id) => { g.dice[id] = Array.from({ length: g.n[id] }, () => 1 + rnd(6)).sort(); });
    S.sub = 'rolling';
    fire('sfx', 'roll'); emit();
    const rid = g.rid;
    later(() => { if (S.game !== g || g.rid !== rid) return; S.sub = 'bidding'; if (g.turn === 'me') fire('sfx', 'turn'); emit(); think(); }, 1500);
  }

  function raise(by, count, face) {
    const g = S.game;
    if (S.phase !== 'play' || S.sub !== 'bidding' || g.turn !== by || !canRaise(count, face)) return false;
    g.bid = { count, face, by }; g.bids.push(g.bid); g.turn = nextAlive(by);
    fire('sfx', 'clack'); if (g.turn === 'me') fire('sfx', 'turn');
    emit(); think();
    return true;
  }

  function check(by) {
    const g = S.game;
    if (S.phase !== 'play' || S.sub !== 'bidding' || g.turn !== by || !g.bid) return false;
    const b = g.bid;
    const n = alive().flatMap((id) => g.dice[id]).filter((f) => f === b.face).length;
    const stood = n >= b.count;
    const loser = stood ? by : b.by;
    g.reveal = { bid: b, checker: by, bidder: b.by, n, stood, loser, knocked: g.n[loser] + 1 >= 6, step: 0 };
    S.sub = 'reveal'; g.turn = null;
    fire('sfx', 'knock'); emit();
    const rid = g.rid, ok = () => S.game === g && g.rid === rid;
    later(() => { if (!ok()) return; g.reveal.step = 1; fire('sfx', 'flip'); emit(); }, 1100);
    later(() => { if (!ok()) return; g.reveal.step = 2; emit(); }, 2700);
    later(() => {
      if (!ok()) return;
      g.reveal.step = 3; g.n[loser] += 1;
      if (g.reveal.knocked) g.out.push(loser);
      fire('sfx', loser === 'me' ? 'ouch' : 'penalty'); emit(); botsReact(g.reveal);
    }, 4300);
    later(() => { if (!ok()) return; if (alive().length <= 1) return finish(); newRound(g.out.includes(loser) ? nextAlive(loser) : loser); }, 8200);
    return true;
  }

  function finish() {
    const g = S.game;
    const winner = alive()[0];
    S.tally[winner] = (S.tally[winner] || 0) + 1;
    S.last = { placement: [winner, ...g.out.slice().reverse()], rounds: g.round };
    S.phase = 'over'; S.sub = null;
    fire('sfx', 'win'); emit();
  }

  // ---- bots -------------------------------------------------------------------
  // chance that at least k of n unseen dice show one given face
  const tail = (n, k) => {
    if (k <= 0) return 1; if (k > n) return 0;
    let p = 0, c = 1;
    for (let i = 0; i <= n; i++) { if (i >= k) p += c * Math.pow(1 / 6, i) * Math.pow(5 / 6, n - i); c = (c * (n - i)) / (i + 1); }
    return p;
  };
  function think() {
    const g = S.game, id = g.turn, p = person(id);
    if (S.sub !== 'bidding' || !p || !p.bot || p.away) return;
    const rid = g.rid;
    later(() => { if (S.game === g && g.rid === rid && g.turn === id && S.sub === 'bidding' && !person(id).away) botMove(id); }, 1300 + rnd(1600));
  }
  function botMove(id) {
    const g = S.game, mine = g.dice[id], tot = total(), unseen = tot - mine.length;
    const have = (f) => mine.filter((x) => x === f).length;
    if (!g.bid) {
      const f = [1, 2, 3, 4, 5, 6].sort((a, b) => have(b) - have(a) || Math.random() - .5)[0];
      return raise(id, Math.max(1, Math.min(tot, have(f) + Math.round((unseen / 6) * (.5 + Math.random() * .7)))), f);
    }
    const pTrue = tail(unseen, g.bid.count - have(g.bid.face));
    const options = [1, 2, 3, 4, 5, 6].map((f) => ({ f, c: minCount(f) })).filter((o) => o.c <= tot)
      .map((o) => ({ ...o, p: tail(unseen, o.c - have(o.f)) })).sort((a, b) => b.p - a.p);
    if (!options.length || pTrue < .26 + Math.random() * .22 || options[0].p < .1) return check(id);
    const o = options.length > 1 && Math.random() < .2 ? options[1] : options[0];
    raise(id, o.c, o.f);
  }
  function botsReact(r) {
    const bots = connected().filter((p) => p.bot);
    shuffle(bots).slice(0, Math.min(bots.length, 1 + rnd(2))).forEach((p, i) => later(() => {
      const keys = r.knocked ? ['gasp', 'gg', 'lol'] : r.stood ? ['clap', 'gasp', 'noway'] : ['lol', 'fire', 'hmm', 'noway'];
      react(p.id, pick(keys));
    }, 300 + i * 700 + rnd(500)));
  }

  // ---- leaving, removing, Host, Away -----------------------------------------
  function drop(id, why) {
    const p = person(id); if (!p || p.left) return;
    p.left = true; p.away = null;
    const g = S.game;
    if (S.vote) S.vote = null;
    if (S.phase === 'play' && g.seats.includes(id) && !g.out.includes(id)) {
      // leaving mid-Game: Knocked out on the spot, the Round is voided, the next Player opens a fresh one
      g.out.push(id); clearTimers();
      fire('toast', `${p.me ? 'You' : p.name} ${why === 'removed' ? 'was removed' : 'left'}. Round voided.`);
      if (alive().length <= 1) finish(); else newRound(nextAlive(id));
    } else if (!p.me) fire('toast', `${p.name} ${why === 'removed' ? 'was removed' : 'left'}.`);
    if (S.hostId === id) passHost();
    if (p.me) { S.left = true; clearTimers(); }
    emit();
  }
  function passHost(to) {
    const pool = connected().filter((p) => p.id !== S.hostId);
    const next = to || (pool.length ? pick(pool).id : null);
    if (!next) return;
    S.hostId = next; S.vote = null;
    fire('toast', `${name(next)} ${next === 'me' ? 'are' : 'is'} the Host now.`);
    emit();
  }
  function setAway(id, away, ago = 0) {
    const p = person(id); if (!p) return;
    p.away = away ? Date.now() - ago : null;
    if (!away && id === S.hostId) S.vote = null;
    emit();
    if (!away && S.phase === 'play' && S.game.turn === id) think();
  }
  function startVote(by) {
    if (S.vote || !person(S.hostId)?.away || Date.now() < S.voteCooldown) return;
    S.vote = { by, yes: [by], endsAt: Date.now() + 30000 };
    connected().filter((p) => p.bot && p.id !== by).forEach((p) => later(() => voteYes(p.id), 900 + rnd(3200)));
    emit();
  }
  function voteYes(id) {
    const v = S.vote; if (!v || v.yes.includes(id)) return;
    v.yes.push(id);
    if (connected().every((p) => v.yes.includes(p.id))) return passHost();
    emit();
  }
  function voteNo() { if (!S.vote) return; S.vote = null; S.voteCooldown = Date.now() + 30000; fire('toast', 'The vote failed. The Host stays for now.'); emit(); }
  // once a second: the 2-minute Host timer and the 30-second vote window
  setInterval(() => {
    const host = person(S.hostId);
    if (S.vote && Date.now() > S.vote.endsAt) voteNo();
    if (host?.away && Date.now() - host.away > 120000) passHost();
  }, 1000);

  function react(id, key) {
    const now = Date.now();
    if (now - (S.lastReact[id] || 0) < 2000) return false;   // one every 2 s
    S.lastReact[id] = now;
    fire('react', id, REACTIONS.find((r) => r.key === key));
    return true;
  }

  // ---- scenes: jump the Room to a state worth looking at --------------------
  function room(n) {
    clearTimers();
    const host = S.opt.host;
    S.people = [{ id: 'me', name: 'Dana', me: true, color: COLORS[0] }];
    for (let i = 1; i < n; i++) S.people.push({ id: 'p' + i, name: NAMES[i - 1], bot: true, color: COLORS[i % COLORS.length] });
    if (n <= 12) {   // two people who are in the Room but not in the Game
      S.people.push({ id: 'w1', name: NAMES[n - 1], bot: true, color: COLORS[(n + 1) % COLORS.length], sitOut: true });
      S.people.push({ id: 'w2', name: NAMES[n], bot: true, color: COLORS[(n + 3) % COLORS.length], sitOut: true });
    }
    S.hostId = host === 'me' || n < 2 ? 'me' : 'p1';
    S.tally = { me: 1, p1: 2 }; if (n > 3) S.tally.p3 = 1;
    Object.assign(S, { phase: 'lobby', sub: null, game: null, last: null, vote: null, voteCooldown: 0, left: false, lastReact: {} });
  }
  function midGame({ counts, turn, bids = [], dice }) {
    const n = S.opt.seats;
    const seats = ['me', ...Array.from({ length: n - 1 }, (_, i) => 'p' + (i + 1))];
    const pattern = [2, 1, 3, 2, 1, 4, 2, 3, 1, 2];
    const g = { seats, n: {}, dice: {}, out: [], round: 5, bid: null, bids: [], turn, reveal: null, rid: Math.random() };
    seats.forEach((id, i) => { g.n[id] = counts ? counts(i) : pattern[i % pattern.length]; g.dice[id] = Array.from({ length: g.n[id] }, () => 1 + rnd(6)).sort(); });
    if (dice) dice(g);
    S.game = g; S.phase = 'play'; S.sub = 'bidding';
    bids.forEach(([by, count, face]) => { g.bid = { count, face, by }; g.bids.push(g.bid); });
    return g;
  }
  const last = (k) => 'p' + (S.opt.seats - k);     // the Players just before you in turn order
  const SCENES = {
    'lobby': () => room(S.opt.seats),
    'my-turn': () => {
      room(S.opt.seats);
      const n = S.opt.seats, g = midGame({ turn: 'me' }), base = Math.max(1, Math.round(total(g) / 6));
      const bids = n > 2 ? [[last(2), base, 2], [last(1), base, 4]] : [['p1', base, 4]];
      bids.forEach(([by, count, face]) => { g.bid = { count, face, by }; g.bids.push(g.bid); });
    },
    'my-open': () => { room(S.opt.seats); midGame({ turn: 'me' }); },
    'watching': () => { room(S.opt.seats); midGame({ turn: 'p1' }); think(); },
    'reveal-caught': () => revealScene(false),
    'reveal-stood': () => revealScene(true),
    'away-turn': () => {
      S.opt.host = 'me'; room(S.opt.seats);
      const who = S.opt.seats > 2 ? 'p2' : 'p1', g = midGame({ turn: who }), base = Math.max(1, Math.round(total(g) / 6));
      g.bid = { count: base, face: 5, by: 'me' }; g.bids.push(g.bid);
      person(who).away = Date.now() - 102000;
    },
    'host-away': () => {
      S.opt.host = 'other'; room(Math.max(3, S.opt.seats)); S.opt.seats = Math.max(3, S.opt.seats);
      midGame({ turn: 'p2' }); person('p1').away = Date.now() - 82000;
      think(); later(() => startVote('p2'), 1600);
    },
    'knocked-out': () => {
      room(Math.max(3, S.opt.seats)); S.opt.seats = Math.max(3, S.opt.seats);
      const g = midGame({ turn: 'p1' }); g.out = ['me']; g.n.me = 6; g.dice.me = [];
      think();
    },
    'over': () => {
      room(S.opt.seats);
      const g = midGame({ turn: null });
      g.out = shuffle(g.seats.filter((id) => id !== 'p1')); S.game = g; finish();
    },
    'hundred': () => { S.opt.seats = 20; room(20); const g = midGame({ turn: 'me', counts: () => 5 }); g.bid = { count: 17, face: 3, by: 'p19' }; g.bids.push({ count: 16, face: 5, by: 'p18' }, g.bid); },
  };
  function revealScene(stood) {
    room(S.opt.seats);
    const g = midGame({ turn: 'me' });
    const sixes = alive(g).flatMap((id) => g.dice[id]).filter((f) => f === 6).length;
    // make the Bid one too many (Bluff caught) or exactly right (the Bid stands)
    let count = stood ? Math.max(1, sixes) : sixes + 1;
    if (stood && sixes === 0) { g.dice.p1[0] = 6; count = 1; }
    if (count > total(g)) { g.dice.p1[0] = 1; count = total(g); }
    const by = last(1);
    g.bid = { count, face: 6, by }; g.bids.push({ count: Math.max(1, count - 1), face: 6, by: S.opt.seats > 2 ? last(2) : by }, g.bid);
    emit();
    later(() => check('me'), 900);
  }
  function scene(key) { SCENES[key](); S.sceneKey = key; emit(); }

  window.Table = {
    S, REACTIONS, on, emit, person, inRoom, connected, name, iAmHost,
    alive, total, nextAlive, minCount, canRaise, anyRaise, isPlaying, myTurn, seesOwnDice,
    startGame, raise, check, drop, passHost, setAway, startVote, voteYes, voteNo, react, scene, scenes: Object.keys(SCENES),
  };
})();
