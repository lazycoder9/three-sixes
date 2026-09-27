# Real-time architecture for 36s in Phoenix LiveView

Research for [issue #4](https://github.com/lazycoder9/three-sixes/issues/4). This file lists facts and trade-offs. It does not pick an architecture; that is the job of [#6 Architecture and testing seam](https://github.com/lazycoder9/three-sixes/issues/6).

Terms follow `CONTEXT.md` (Bid, Raise, Check, Round, Game, Penalty die, Knocked out).

**Versions checked (2026-09-28):** Phoenix 1.8.15, Phoenix LiveView 1.2.12, Phoenix.PubSub 2.3.0, Elixir 1.20.4, Erlang/OTP 29.1.1. Source links point at those release tags. The Hex package sources were compared with the GitHub tags and are identical.

## Summary

- **Room process.** A GenServer per room, started under a DynamicSupervisor and named through a Registry, is the standard OTP building block. Registry is local to one node. A restarted GenServer runs `init/1` again and starts with empty state unless it reloads it from somewhere.
- **Updates.** Phoenix.PubSub delivers plain Erlang messages to subscribed processes (LiveViews). A local broadcast is a `send/2` from the broadcasting process, so messages from one room process arrive in the order they were sent. A room topic and per-player delivery can be combined.
- **Presence.** Phoenix.Presence removes an entry as soon as the tracked process exits. It has no grace period. A reconnect creates a new process and a new entry, and for a while the old and new entries can exist at the same time under the same key.
- **Hidden dice.** Socket assigns stay on the server. The browser receives only what the template renders, plus anything sent on purpose (`push_event`, event replies, the LiveView session token). A die that is rendered and then hidden with CSS has still been sent. The LiveView session token is signed, not encrypted.
- **Crash and deploy.** In-memory room state is lost when the room process dies and on every deploy. Elixir releases do not support hot code upgrades out of the box. The options are: accept the loss, snapshot to the database (or to ETS for crash-only safety), or hand off between clustered nodes, which needs third-party libraries.
- **Mobile reconnects.** The server cannot tell "phone locked" from "network gone" from "tab closed". A clean close ends the LiveView at once. A silent drop is noticed only after the WebSocket idle timeout (60 s after the last received data by default). The Phoenix JS client does not reconnect while the page is hidden, and it reconnects immediately when the page becomes visible again.
- **Randomness.** `:rand` (and `Enum.random/1`) uses `exsss` by default. The docs say it is not cryptographically strong. `:crypto.rand_seed_s/0` plugs a strong generator into the same `:rand` API. `:rand` state is per process, so seeding the test process does not seed a room process.

---

## 1. One process per room

### What OTP provides

- **GenServer** holds state in a process. The default child `:restart` is `:permanent`. A process can be named with `{:via, module, term}`, and Elixir's `Registry` is "a local, decentralized and scalable registry" for dynamic names. ([GenServer](https://hexdocs.pm/elixir/GenServer.html))
- **Registry** is "A local, decentralized and scalable key-value process storage". It supports `{:via, Registry, {registry, key}}` naming. "Each entry in the registry is associated to the process that has registered the key. If the process crashes, the keys associated to that process are automatically removed." ([Registry](https://hexdocs.pm/elixir/Registry.html))
- **DynamicSupervisor** starts children on demand with `start_child/2`. `:max_restarts` defaults to 3 within `:max_seconds` 5. If a child restarts more often than that, the supervisor itself exits. `:max_children` (default `:infinity`) caps the number of children; when the cap is hit `start_child/2` returns `{:error, :max_children}`. ([DynamicSupervisor](https://hexdocs.pm/elixir/DynamicSupervisor.html))
- **Restart values** ([Supervisor, child specification](https://hexdocs.pm/elixir/Supervisor.html)):
  - `:permanent`: always restarted.
  - `:temporary`: never restarted.
  - `:transient`: restarted only if it exits with a reason other than `:normal`, `:shutdown` or `{:shutdown, term}`.
- **Shutdown.** Workers get 5000 ms by default. A child must trap exits for `terminate/2` to run on shutdown. `terminate/2` "is not guaranteed" to run when a GenServer exits. ([Supervisor](https://hexdocs.pm/elixir/Supervisor.html), [GenServer](https://hexdocs.pm/elixir/GenServer.html))
- **Monitors.** `Process.monitor/1` delivers `{:DOWN, ref, :process, pid, reason}` when the target dies, and delivers it at once with `:noproc` if the target is already gone. ([Erlang reference manual, processes](https://www.erlang.org/doc/system/ref_man_processes.html))

### How the pieces fit (the common pattern, not a decision)

A LiveView looks the room up by code through the Registry. It calls or casts to the room process for actions (Bid, Raise, Check), and receives state changes as messages (section 2). The room process owns the Game state and the dice.

### Alternatives

| Option | What it means | Trade-off |
|---|---|---|
| Room GenServer (above) | One process serialises all actions for a room | One place enforces turn order and rules. State is in memory, so see section 5. |
| State in each LiveView | No room process; LiveViews sync through PubSub | No single authority, so there are races on who acted first. Every LiveView holds the full state, including all dice. A poor fit for a turn-based game with hidden information. |
| Database as source of truth | Every action is a DB transaction; PubSub only notifies | Survives crash and deploy. Every Bid is a write. Turn order needs row locks or optimistic concurrency. |
| Cluster-wide registry (`:global`, or third-party Horde) | Room reachable from any node | Needed only for multi-node hosting. `Registry` does not do this. |

### Pitfalls

- **Restart gives empty state.** A `:permanent` or `:transient` room that crashes is restarted with its original start arguments, and `init/1` builds fresh state. Without a reload step (section 5), a restart produces an empty room under the old code. That may be worse than no restart, because players see a room that exists but has forgotten the Game.
- **One supervisor for all rooms.** If rooms crash more than 3 times in 5 s in total, the default DynamicSupervisor limits take the supervisor down, and every room goes with it. Limits are per supervisor, not per room. ([DynamicSupervisor](https://hexdocs.pm/elixir/DynamicSupervisor.html))
- **Do not link a room to a LiveView.** A room started with `start_link` from a LiveView dies when that player's LiveView dies. Start rooms under the DynamicSupervisor, and have LiveViews monitor them rather than link. (LiveView's own docs warn about links for the same reason: ["A note on linked processes"](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view.ex#L175-L213).)
- **Calling a dead room crashes the caller.** `GenServer.call/3` to a process that does not exist, or that dies during the call, exits the calling LiveView. The LiveView then crashes and the client rejoins, which runs `mount/3` again. If `mount/3` also calls the dead room, the client goes into a crash and rejoin loop.
- **Registry is single-node.** With two nodes that are not clustered, or during an overlapping deploy, a room code may exist on node A while a reconnecting player lands on node B. See section 5 and the open "Hosting & deployment" item on the map.

## 2. How LiveViews receive updates

### Facts

- A LiveView is a process. `mount/3` runs twice: once for the plain HTTP render and once when the WebSocket connects ([`mount/3` docs](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view.ex#L236-L237)). `connected?/1` is the documented way "to conditionally perform stateful work, such as subscribing to pubsub topics" ([source](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view.ex#L628-L654)).
- `Phoenix.PubSub.subscribe/2` registers the calling process for a topic. `broadcast/3` sends to every subscriber across the cluster, and `local_broadcast/3` sends to this node only. "Duplicate subscriptions for a Pid/topic pair are allowed and will cause duplicate events to be sent" ([pubsub.ex](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/pubsub.ex#L190-L212), [hexdocs](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html)).
- Local delivery is a plain `send(pid, message)` from the broadcasting process (`Registry.dispatch` in the caller) ([pubsub.ex](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/pubsub.ex#L400-L420)). The default adapter, PG2, uses distributed Erlang to reach other nodes.
- Erlang ordering: "if an entity sends multiple signals to the same destination entity, the order is preserved". There is no ordering guarantee between different senders. ([Erlang reference manual](https://www.erlang.org/doc/system/ref_man_processes.html))
- The LiveView reacts in `handle_info/2`, updates assigns, and LiveView sends a diff to the browser.

### Topic shapes and their trade-offs

| Shape | How it works | For | Against |
|---|---|---|---|
| A. One room topic, full state | The room broadcasts the whole Game, including every die. Each LiveView shows only its own player's dice. | Simplest. One message type. | Every LiveView process holds every player's dice. It never reaches the browser unless it is rendered or pushed, but one template mistake or debug `inspect(@game)` leaks it. Hidden-dice safety depends on each template. |
| B. Room topic for public state plus per-player delivery | The room broadcasts a public view (dice counts, current Bid, whose turn, revealed dice after a Check). It sends each player's own dice on a per-player topic (e.g. `room:CODE:player:ID`) or straight to that player's LiveView pid. | A LiveView never holds other players' dice before a Check. Safety sits in one place, the room's projection function. Easy to test at the room boundary. | Two message kinds. Ordering holds only because both come from the same room process (see the Erlang rule above). |
| C. Room sends to known pids | LiveViews register with the room, which monitors them. The room sends each one a view built for that player. No PubSub for game state. | Same safety as B. The room also learns of disconnects at once from `:DOWN` (section 3), without Presence. | The room keeps a subscriber list and must handle several pids per player (two tabs, or an old and a new LiveView during a reconnect). |

### Pitfalls

- Subscribe only when `connected?(socket)` is true. Otherwise the static-render request subscribes for nothing, and subscribing twice in one process produces duplicate messages.
- After a reconnect, the new LiveView starts empty (section 6). It must fetch the current state from the room in `mount/3`, not wait for the next broadcast.

## 3. Phoenix.Presence

### Facts

- Presence tracks processes under a topic and a key and broadcasts `presence_diff` events with `joins` and `leaves`. Several entries (`metas`) can sit under one key, for example one per tab. `track/4` can track any pid, including a LiveView's `self()`. ([Phoenix.Presence](https://hexdocs.pm/phoenix/Phoenix.Presence.html), [source](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/presence.ex))
- Server-side Elixir clients can implement `init/1` and `handle_metas/4` to get join and leave callbacks. The documented example rebroadcasts them with `local_broadcast`. ([same](https://hexdocs.pm/phoenix/Phoenix.Presence.html))
- The tracker links to each tracked pid ([shard.ex L318](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/tracker/shard.ex#L318)). When the pid exits, it drops the presence and reports a leave diff straight away ([shard.ex L217-L219, L340-L346](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/tracker/shard.ex#L217-L219)). **There is no grace period for a process that exits.**
- Timing parameters (`broadcast_period` 1500 ms, `down_period` about 30 s, `permdown_period` 20 min) apply only to whole nodes going away in a cluster, not to single clients. On a graceful node shutdown, other nodes keep that node's presences until `down_period` unless `permdown_on_shutdown: true` is set. ([tracker.ex](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/tracker.ex#L73-L96), [shard.ex defaults](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/tracker/shard.ex#L109-L114))

### Behaviour on reconnect

1. The socket closes cleanly, so the LiveView stops with `{:shutdown, :closed}` ([LV channel.ex L107-L116](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/channel.ex#L107-L116)). Presence broadcasts a **leave** at once.
2. The client reconnects, a new LiveView process mounts and tracks again, and Presence broadcasts a **join** with a new `phx_ref`.

So a short network blip shows up as leave followed by join. If the old connection died silently, the old LiveView is still alive until the server timeout (section 6) while the new one has already joined. Both metas sit under the same key, and the later leave of the old one does not mean the player left.

### Pitfalls

- Treat "no metas left under this key" as offline, not "a leave diff arrived".
- Any "wait N seconds before marking a Player as gone" rule is application logic, typically a timer in the room process. Presence does not provide it. This matters directly for #5.
- Presence tells you who is connected. It is not the seat list, and it should not decide whose turn it is.
- Presence metadata goes to every subscriber and may be pushed to clients. Never put dice in it.

## 4. Hidden dice: what reaches the browser

### Facts

- "Socket assigns are stateful values kept on the server side" ([LiveView life-cycle](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view.ex#L10-L44)).
- On first render LiveView sends "all of the static and dynamic parts of the template". After that it "will only resend the dynamic part if it changes" ([Assigns and HEEx templates](https://hexdocs.pm/phoenix_live_view/assigns-eex.html)). Assigns that are never rendered are never sent.
- Other things that go over the wire when the code sends them: `push_event/3` payloads (delivered to JS hooks and `window` listeners, see [`push_event/3`](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view.ex#L819-L850)), `{:reply, map, socket}` from `handle_event/3`, `phx-value-*` and other DOM attributes, and JS command arguments rendered into attributes.
- The plain HTTP (static) render is a full HTML page. Whatever the template shows for that request is in the page source.
- The LiveView session (the `:session` option of `live_session`/`live_render`) is put into the page as a token made with `Phoenix.Token.sign` ([static.ex L357-L407](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/static.ex#L357-L407)). The Phoenix.Token docs: "unless the token is encrypted, it is not safe to use this token to store private information ... as it can be trivially decoded" ([token.ex](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/token.ex#L1-L15)).
- Security guide: authorize in `mount/3` (it covers both the HTTP and the connected render) and on every `handle_event/3`. "An attacker can use browser developer tools or custom scripts to send any payload to your LiveView" ([Security considerations](https://hexdocs.pm/phoenix_live_view/security-model.html)).

### What this means for 36s

- The guarantee comes from *what is rendered or pushed per connection*, not from PubSub. PubSub messages travel between server processes and never reach the browser by themselves.
- A Player's own dice may be rendered. Other Players' dice may be rendered only after a Check reveals them. Before a Check, render counts ("3 dice"), not hidden values.
- Topic shapes B and C (section 2) keep other players' dice out of the LiveView process entirely, so a template mistake cannot leak them. With shape A, safety depends on every template and hook payload.
- `handle_event/3` must derive "who is acting" from the server-side identity set in `mount/3` (session), never from event params.

### Pitfalls

- Rendering all dice and hiding the others with CSS (`hidden`, `opacity-0`, a closed `<details>`) sends them to the browser.
- A data attribute for a JS roll animation (`data-faces=...`) or a `push_event` that carries the full table leaks everything.
- Putting dice or seat secrets in the LiveView `:session` exposes them, because it is signed but readable.
- Debug output such as `<pre>{inspect(@game)}</pre>` or error pages in dev.
- The room→LiveView message boundary is the natural place for a test: render one Player's view and assert that another Player's dice values do not appear in the HTML. That test belongs to #6.

## 5. In-memory state on crash and deploy

### Facts

- A crashed process loses its state. After a restart, `init/1` runs again (section 1).
- An ETS table dies with its owner unless an heir is set: "When the process terminates, the table is automatically destroyed". `{heir, Pid, HeirData}` passes the table to a local heir process ([ets](https://www.erlang.org/doc/apps/stdlib/ets.html)). ETS survives a room crash if another process owns it or is its heir. It does not survive a node restart.
- Elixir releases do **not** support hot code upgrades out of the box. "this feature is not supported out of the box by Elixir releases" ([Mix.Tasks.Release](https://hexdocs.pm/mix/Mix.Tasks.Release.html)). A normal deploy stops the VM, and on SIGTERM supervision trees stop in reverse start order.
- On shutdown Phoenix drains sockets. It notifies clients in batches (default 10,000 per batch, 2000 ms apart, 30 s maximum) so that they reconnect ([endpoint.ex `:drainer`](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/endpoint.ex#L832-L857)). The server closes with WebSocket code 1012 "Service Restart" ([socket.ex L577-L580](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/socket.ex#L577-L580)). The JS client treats any close code other than 1000 as "reconnect".
- LiveView's deployment guide: "Your LiveView *may* still have state that will be lost in this transition". It recommends keeping state in URL params or the database. Form inputs are recovered automatically on reconnect. ([Deployments and recovery](https://hexdocs.pm/phoenix_live_view/deployments.html))

### Options

| Option | Survives room crash | Survives deploy | Cost |
|---|---|---|---|
| Accept the loss | No | No | Nothing. The UI must handle "room gone" after a reconnect. |
| ETS owned by another process, or with an heir | Yes | No | Small. The room reloads from ETS in `init/1`. |
| Snapshot to the database (after each action, or at the end of each Round) | Yes | Yes | A schema and a write per snapshot. The room is started lazily from the snapshot when a player reconnects and the Registry lookup misses. Rolled dice must be in the snapshot, or the Round is re-rolled on restore, which is a rules decision. |
| Save in `terminate/2` on shutdown | No (crash) | Only on a graceful stop | The room must trap exits and finish within the `:shutdown` timeout (5000 ms default). Not called on a kill or a crash. |
| Hand-off to another node (clustered, rolling deploy) | Maybe | Yes | Needs clustering plus a distributed registry or supervisor (`:global`, or third-party Horde). The most complex option. |

### Pitfalls

- A deploy on a single node always ends every live room unless state is snapshotted. After the restart, players' LiveViews reconnect and `mount/3` finds no room.
- The snapshot interval is also the rollback window. "End of Round" snapshots lose the Bids of the current Round.
- Two unclustered nodes running side by side during a deploy split rooms between them (section 1).

## 6. Reconnection on mobile browsers

### Client defaults (phoenix.js 1.8.15, LiveView 1.2.12)

| Setting | Default | Source |
|---|---|---|
| Heartbeat interval | 30,000 ms | [socket.js L166](https://github.com/phoenixframework/phoenix/blob/v1.8.15/assets/js/phoenix/socket.js#L166) |
| Heartbeat timeout (no reply, then reconnect) | another `heartbeatIntervalMs` after sending | [socket.js L506-L514, L690-L695](https://github.com/phoenixframework/phoenix/blob/v1.8.15/assets/js/phoenix/socket.js#L690-L695) |
| Socket reconnect backoff | 10, 50, 100, 150, 200, 250, 500, 1000, 2000 ms, then 5000 ms | [socket.js L174-L180](https://github.com/phoenixframework/phoenix/blob/v1.8.15/assets/js/phoenix/socket.js#L174-L180) |
| Channel (LiveView) rejoin backoff | 1000, 2000, 5000 ms, then 10,000 ms | [socket.js L167-L173](https://github.com/phoenixframework/phoenix/blob/v1.8.15/assets/js/phoenix/socket.js#L167-L173) |
| Reconnect while page is hidden | **Skipped** ("Not reconnecting as page is hidden!") | [socket.js L192-L199](https://github.com/phoenixframework/phoenix/blob/v1.8.15/assets/js/phoenix/socket.js#L192-L199) |
| Page becomes visible, or Chrome `resume` fires | Reconnects immediately if the socket had dropped | [socket.js L143-L165, L213-L220](https://github.com/phoenixframework/phoenix/blob/v1.8.15/assets/js/phoenix/socket.js#L143-L165) |
| `pagehide` / `pageshow` | Disconnects on `pagehide`, reconnects on `pageshow`. LiveView reloads the page when it is restored from the back/forward cache. | [socket.js L143-L156](https://github.com/phoenixframework/phoenix/blob/v1.8.15/assets/js/phoenix/socket.js#L143-L156), [live_socket.ts L1138-L1150](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/assets/js/phoenix_live_view/live_socket.ts#L1138-L1150) |
| `phx-disconnected` JS commands | Run after 500 ms | [constants.ts L101](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/assets/js/phoenix_live_view/constants.ts#L101), [bindings guide](https://hexdocs.pm/phoenix_live_view/bindings.html) |
| LongPoll fallback | New apps set `longPollFallbackMs: 2500` in `app.js` | phx_new 1.8.15 template `templates/phx_assets/app.js.eex` |
| LiveView session token lifetime | 14 days (`@max_session_age 1_209_600`) | [static.ex L18](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/static.ex#L18) |

Server side: the WebSocket `:timeout` is "the timeout for keeping websocket connections open after it last received data, defaults to 60_000ms" ([endpoint.ex L1018-L1019](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/endpoint.ex#L1018-L1019)). When the transport process ends, the LiveView process stops with `{:shutdown, :closed}` ([LV channel.ex L107-L116](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/channel.ex#L107-L116)). `terminate/2` runs only if the LiveView traps exits ([L292-L298](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view.ex#L292-L298)). An explicit leave gives `{:shutdown, :left}`.

On reconnect, a **new** LiveView process runs `mount/3` and `handle_params/3` again. "If at any point during the stateful life-cycle a crash is encountered, or the client connection drops, the client gracefully reconnects to the server, calling `mount/3` and `handle_params/3` again" ([life-cycle](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view.ex#L36-L44)). Nothing in the old LiveView's assigns carries over.

### Browser side

- Chrome's Page Lifecycle API: in the **frozen** state "the browser suspends execution of freezable tasks ... JavaScript timers and fetch callbacks don't run". **Discarded** pages run no JavaScript. Chrome's advice is to "close any open Web Socket connections" on freeze. Mobile browsers may freeze or discard background tabs. Safari does not implement these events. ([Page Lifecycle API](https://developer.chrome.com/docs/web-platform/page-lifecycle-api))
- iOS Safari's handling of background WebSockets is not documented in any primary source I found. Treat "the socket may close, or silently stop, at any time after the page is hidden" as the working assumption, and verify on real phones (#7 prototype or #5).

### What the server sees (derived from the facts above)

| Situation | Server sees | How fast |
|---|---|---|
| Socket closed cleanly (tab closed, `pagehide`, OS closes the connection with a proper close) | Transport exits, LiveView stops `{:shutdown, :closed}`, Presence leave | Immediately |
| Connection dies silently (phone asleep, Wi-Fi→cellular switch, frozen tab) | Nothing until the idle timeout, then as above | 60 s after the last data received, so 30–60 s after the drop with 30 s heartbeats |
| Player returns | New WebSocket, new LiveView, `mount/3`, new Presence join. The old LiveView may still be alive if its connection died silently. | Immediately on visibility if the client knows the socket dropped. Otherwise after the client's heartbeat timeout (up to about 30 s after the next heartbeat is sent). Backoff starts at 10 ms. |
| Deploy | Server sends 1012 close, client reconnects with backoff to whatever is listening | Drain up to 30 s, then the restart gap of the host |

### Pitfalls

- The server cannot tell backgrounding from network loss from leaving. Only an explicit action (a "Leave" button handled in `handle_event/3`) marks a deliberate leave. This bears on #5's "leaving on purpose vs dropping" question.
- For up to 60 s, a Player can have two live LiveView processes (old and silently dead, new and live). The room must accept this. Two tabs cause the same situation.
- A hidden page does not reconnect, so a backgrounded Player stays disconnected however long the Game waits. A turn timer (#5) is the only way the Game moves on.
- Identity across reconnects has to come from something that survives a new process: the Plug session cookie read in `mount/3`, or URL params. Not assigns.

## 7. Server-side dice randomness

### Facts

- `:rand`'s default algorithm is `exsss` (Xorshift116**), chosen for speed and "good enough" statistics. "The builtin random number generator algorithms are not cryptographically strong. If a cryptographically strong random number generator is needed, use for example `crypto:rand_seed_s/0` or `crypto:rand_seed_alg_s/1`." ([rand](https://www.erlang.org/doc/apps/stdlib/rand.html))
- Without explicit seeding, the state lives in the **process dictionary** and is seeded automatically from "the node name, the calling `pid/0`, the system time, and a system unique integer" ([rand `seed/1`](https://www.erlang.org/doc/apps/stdlib/rand.html)).
- `:rand.uniform/1` "generates uniformly distributed random integers ... without bias". `:rand.uniform_s/2` takes and returns an explicit state instead. ([rand](https://www.erlang.org/doc/apps/stdlib/rand.html))
- `Enum.random/1` uses `:rand`. It can be made deterministic with `:rand.seed(:exsss, {100, 101, 102})` in the same process ([Enum.random/1](https://hexdocs.pm/elixir/Enum.html#random/1)).
- `:crypto.rand_seed/0` and `rand_seed_s/0` create a `:rand` generator backed by crypto (in the process dictionary, or returned as state). After that, the normal `:rand.uniform` calls draw from the strong source. `:crypto.strong_rand_bytes/1` returns raw strong bytes. `:crypto.rand_uniform` is deprecated. ([crypto](https://www.erlang.org/doc/apps/crypto/crypto.html))

### Trade-offs

| Generator | Unpredictable to players | Reproducible in tests | Notes |
|---|---|---|---|
| `:rand` default (`exsss`) | Not guaranteed (docs: not cryptographically strong) | Yes, with `:rand.seed/2` | Practical risk for a private friends game is low but not quantified in the docs. |
| `:crypto.rand_seed_s/0` plus `:rand.uniform_s/2` | Yes | Not with this generator. Tests swap in a seeded `:rand` state or a stub. | Same `:rand` API, so the swap is small. |
| `:crypto.strong_rand_bytes/1` by hand | Yes | No | Needs rejection sampling to avoid modulo bias for d6. The `:rand` plug-in already handles this. |

### Pitfalls

- `:rand` state is per process. `:rand.seed` in an ExUnit test process does **not** affect a room GenServer. Deterministic tests need the room to take its generator (or its state, or a roll function) as input. This is input for #6 ("How randomness is made deterministic in tests").
- Roll on the server only. Never accept dice values or a seed from the client (see the security guide in section 4).

---

## Pitfalls that change other tickets

**For #5 Disconnects and reconnection**

- Presence has no grace period: a leave fires the moment a LiveView exits. Any "wait before treating as gone" must be a timer the room owns.
- A silent drop is seen only after 60 s, the default WebSocket `:timeout`, which is configurable. A hidden page does not reconnect by itself. So "their turn, but disconnected" needs a turn timer, and presence alone is not enough.
- A Player can briefly have two LiveViews (the old one silently dead, the new one live) under one Presence key. Decide what "the Player's seat" is: pids, or an identity from the session.
- A deliberate leave can only be told apart from a drop by an explicit UI action.
- Guest identity has to live in the Plug session cookie (or the URL) to survive reconnects. The LiveView `:session` token is signed, not encrypted.

**For #6 Architecture and testing seam**

- A restarted room process has empty state unless it reloads it. Decide the restart strategy together with the persistence choice: `:temporary` (let it die and show "room gone") or `:transient` plus a reload step.
- A single-node deploy loses every live Game unless snapshots exist. Snapshots that include rolled dice mean the persistence schema holds secret data.
- The hidden-dice guarantee is easiest to hold and test if the room produces a per-Player projection (shapes B and C in section 2). One LiveView test can then assert that another Player's dice never appear in the rendered HTML.
- Randomness must be injected into the room process to be deterministic in tests, because `:rand` state is per process.

**For the map's "Hosting & deployment" item**

- `Registry` is single-node. Two unclustered nodes, including overlap during a rolling deploy, split rooms. Single node plus accept-or-snapshot is the simple path. Multi-node needs clustering and a distributed registry.

## Sources

Official docs:

- Phoenix LiveView: [Phoenix.LiveView](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html), [Assigns and HEEx templates](https://hexdocs.pm/phoenix_live_view/assigns-eex.html), [Security considerations](https://hexdocs.pm/phoenix_live_view/security-model.html), [Deployments and recovery](https://hexdocs.pm/phoenix_live_view/deployments.html), [Bindings](https://hexdocs.pm/phoenix_live_view/bindings.html), [JavaScript interoperability](https://hexdocs.pm/phoenix_live_view/js-interop.html)
- Phoenix: [Phoenix.Presence](https://hexdocs.pm/phoenix/Phoenix.Presence.html), [Phoenix.Endpoint](https://hexdocs.pm/phoenix/Phoenix.Endpoint.html), [Phoenix.Token](https://hexdocs.pm/phoenix/Phoenix.Token.html)
- Phoenix.PubSub: [Phoenix.PubSub](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html), [Phoenix.Tracker](https://hexdocs.pm/phoenix_pubsub/Phoenix.Tracker.html)
- Elixir: [GenServer](https://hexdocs.pm/elixir/GenServer.html), [Registry](https://hexdocs.pm/elixir/Registry.html), [DynamicSupervisor](https://hexdocs.pm/elixir/DynamicSupervisor.html), [Supervisor](https://hexdocs.pm/elixir/Supervisor.html), [Enum.random/1](https://hexdocs.pm/elixir/Enum.html#random/1), [Mix.Tasks.Release](https://hexdocs.pm/mix/Mix.Tasks.Release.html)
- Erlang/OTP: [rand](https://www.erlang.org/doc/apps/stdlib/rand.html), [crypto](https://www.erlang.org/doc/apps/crypto/crypto.html), [ets](https://www.erlang.org/doc/apps/stdlib/ets.html), [Processes (signal ordering, monitors)](https://www.erlang.org/doc/system/ref_man_processes.html)
- Browser: [Page Lifecycle API (Chrome for Developers)](https://developer.chrome.com/docs/web-platform/page-lifecycle-api)

Source code (release tags):

- phoenix v1.8.15: [assets/js/phoenix/socket.js](https://github.com/phoenixframework/phoenix/blob/v1.8.15/assets/js/phoenix/socket.js), [lib/phoenix/socket.ex](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/socket.ex), [lib/phoenix/endpoint.ex](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/endpoint.ex), [lib/phoenix/presence.ex](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/presence.ex), [lib/phoenix/token.ex](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/token.ex)
- phoenix_live_view v1.2.12: [lib/phoenix_live_view.ex](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view.ex), [lib/phoenix_live_view/channel.ex](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/channel.ex), [lib/phoenix_live_view/static.ex](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/static.ex), [assets/js/phoenix_live_view/live_socket.ts](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/assets/js/phoenix_live_view/live_socket.ts), [assets/js/phoenix_live_view/constants.ts](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/assets/js/phoenix_live_view/constants.ts)
- phoenix_pubsub v2.3.0: [lib/phoenix/pubsub.ex](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/pubsub.ex), [lib/phoenix/tracker.ex](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/tracker.ex), [lib/phoenix/tracker/shard.ex](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/tracker/shard.ex)
- phx_new 1.8.15 Hex package: `templates/phx_assets/app.js.eex` (`longPollFallbackMs: 2500`), `templates/phx_web/endpoint.ex.eex` (longpoll transport enabled for LiveView)
