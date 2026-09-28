# How the Room process should deliver updates to each person's LiveView

This file goes one level deeper than [`research/realtime-architecture.md`](https://github.com/lazycoder9/three-sixes/blob/research/realtime-architecture/research/realtime-architecture.md), section 2 "How LiveViews receive updates". That file covers reconnects, Presence timing, crash and deploy, and randomness. This one does not repeat them. It lists facts and trade-offs for fan-out and does not pick an approach.

Terms follow `CONTEXT.md`: Room, Player, Spectator, Check, Round, Away.

**Versions checked (2026-09-28).** Phoenix 1.8.15, Phoenix LiveView 1.2.12, Phoenix.PubSub 2.3.0, Elixir 1.20.4. Source links point at those release tags, the same ones the earlier file used. Example apps are pinned to a commit or tag.

## Summary

- **"Multiplex" in Phoenix means one WebSocket per browser tab carries many channels.** Every LiveView on the page, nested ones included, is its own channel and its own server process on that one socket. Multiplexing saves connections. It does not make one server message reach many people. The fan-out to many people is Phoenix.PubSub.
- **The famous broadcast optimisations belong to Channels, not LiveView.** Channel "fastlane" encodes a broadcast once per serializer and writes it straight to each socket's transport process. `intercept` plus `handle_out` customises a broadcast per subscriber. The LiveView 1.2.12 source never subscribes with fastlane metadata and has no `handle_out`. A LiveView gets a plain Erlang message in `handle_info/2`, renders its own diff, and encodes it for its own socket.
- **Per-person customisation is the default in LiveView.** Each LiveView renders separately, so each can show something different. The real choice for 36s is where the per-person view is computed. It can happen in the Room, before the message leaves, or in each LiveView, after the message arrives. Only the first keeps other Players' dice out of LiveView processes.
- **At 30 people, efficiency does not decide it.** One LiveView render, diff and JSON encode of a 20-seat table took about 5 to 15 µs in a local microbenchmark. The update diff was 77 to 321 bytes against 1.5 KB for the first render. Thirty of those per game event is well under a millisecond of CPU. Template shape matters more than delivery mechanism; see section 1.5.
- **PubSub gives the sender no idea who is listening.** A broadcaster cannot learn that a subscriber died. Knowing when a person is Away needs something else, either the Room monitoring registered LiveView pids or Phoenix.Presence. Presence diffs come from a different process, so they are not ordered with Room messages.
- **Ordering holds only per sender.** Every PubSub path used here is a plain `send/2` from the process that broadcasts, run serially. If the Room is the only sender of game messages, each LiveView sees them in the order the Room sent them. Mixing senders, such as Presence, a LiveView broadcasting its own change, or a second process, drops that guarantee.
- **The core team's current default** is the Phoenix 1.8 generator pattern. The LiveView subscribes in `mount/3` to a topic scoped to the current user, receives a small event, and re-reads data through a scoped context function. Chris McCord's release post calls this "scoped data access (queries *and* PubSub!)". José Valim's Livebook, the largest open-source collaborative LiveView app, combines a registered-and-monitored client list, a PubSub topic for shared updates, and direct `send` to one client pid for client-specific output.

---

## 1. What the pieces do

### 1.1 Phoenix.PubSub

| Function | What it does | Source |
|---|---|---|
| `subscribe(pubsub, topic, opts)` | Registers the calling process in a `Registry` under `topic`. `:metadata` can be attached for custom dispatchers. Subscribing twice gives duplicate messages. | [pubsub.ex L190-L220](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/pubsub.ex#L190-L220) |
| `broadcast(pubsub, topic, msg)` | Sends to other nodes through the adapter, then dispatches locally | [L253-L271](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/pubsub.ex#L253-L271) |
| `broadcast_from(pubsub, pid, topic, msg)` | Same, but the default dispatcher skips `pid`, usually `self()` | [L273-L296](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/pubsub.ex#L273-L296), [L410-L416](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/pubsub.ex#L410-L416) |
| `local_broadcast` / `local_broadcast_from` | Dispatches on this node only, no adapter call | [L298-L334](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/pubsub.ex#L298-L334) |
| Custom dispatcher | A module whose `dispatch/3` gets every `{pid, metadata}` entry and the message. It decides what to send to whom. | [moduledoc L45-L60](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/pubsub.ex#L45-L60), [`:dispatcher` option](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/pubsub.ex#L154-L186) |

How local delivery works. `dispatch` calls `Registry.dispatch(pubsub, topic, {dispatcher, :dispatch, [from, message]})` in the caller, and the default dispatcher does `send(pid, message)` for each entry ([L400-L421](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/pubsub.ex#L400-L421)). `Registry.dispatch/4` "happens in the process that calls `dispatch/3` either serially or concurrently in case of multiple partitions". Its `:parallel` option "Defaults to `false`" ([Registry.dispatch/4](https://hexdocs.pm/elixir/Registry.html#dispatch/4)). PubSub calls the three-argument form, so dispatch is serial and every `send` comes from the broadcasting process.

On one node, `broadcast` and `local_broadcast` reach the same local subscribers. `broadcast` also sends one `{:forward_to_local, ...}` message to each remote PubSub shard found through `:pg` ([pg2.ex L16-L30](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/pubsub/pg2.ex#L16-L30)). The remote shard is picked by hashing the sender pid ([L43-L46](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/pubsub/pg2.ex#L43-L46)), so one sender's messages keep their order across nodes as well.

**Ordering.** Erlang preserves the order of signals from one sender to one receiver and promises nothing across senders ([Erlang reference manual, processes](https://www.erlang.org/doc/system/ref_man_processes.html)). With PubSub, "one sender" means the process that called `broadcast`.

**Copying.** "All data in messages sent between Erlang processes is copied, except for refc binaries and literals on the same Erlang node" ([Erlang efficiency guide, sending messages](https://www.erlang.org/doc/system/eff_guide_processes.html)). A broadcast of the full Game to 30 LiveViews puts 30 full copies, all dice included, on 30 process heaps.

**Delivery guarantee.** "Phoenix uses an at-most-once strategy when sending messages to clients. If the client is offline and misses the message, Phoenix won't resend it" ([Channels guide L503](https://github.com/phoenixframework/phoenix/blob/v1.8.15/guides/real_time/channels.md?plain=1#L503)). José Valim describes PubSub the same way in [You may not need Redis with Elixir](https://dashbit.co/blog/you-may-not-need-redis-with-elixir). A reconnecting LiveView is a new process that has missed everything. It must rebuild from the Room in `mount/3`.

Signal or data? PubSub carries any term. The Phoenix 1.8 generators send the changed record, `{:created | :updated | :deleted, %Post{}}`. The generated LiveView ignores the payload and re-reads the list through the scoped context ([phx.gen.live index.ex.eex L66-L69](https://github.com/phoenixframework/phoenix/blob/v1.8.15/priv/templates/phx.gen.live/index.ex.eex#L66-L69)). So the message is a "something changed" signal, and data comes from a scoped read. Section 2, option D maps this onto 36s.

### 1.2 Channels: fastlane, `intercept` and `handle_out`

A Channel process joins its topic by subscribing with this metadata: `{:fastlane, transport_pid, serializer, channel.__intercepts__()}` ([channel/server.ex L443-L444](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/channel/server.ex#L443-L444)). Endpoint and channel broadcasts use `Phoenix.Channel.Server` as the dispatcher. For each subscriber it does one of two things ([L94-L122](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/channel/server.ex#L94-L122)):

- If the event is intercepted, it sends the `%Broadcast{}` to the channel process, which runs `handle_out/3`.
- Otherwise it encodes the message with `serializer.fastlane!/1`, caches the encoded frame per serializer, and sends the bytes straight to the socket's transport process. The channel process never sees the message.

The PubSub docs describe this as fastlaning, "allowing messages broadcast to thousands or even millions of users to be encoded once and written directly to sockets instead of being encoded per channel" ([pubsub.ex L56-L60](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/pubsub.ex#L56-L60)).

`intercept` lets each channel rewrite or drop a broadcast for its own client ([channel.ex L174-L201](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/channel.ex#L174-L201)). The docs warn: "intercepting events can introduce significantly more overhead if a large number of subscribers must customize a message since the broadcast will be encoded N times instead of a single shared encoding" ([L512-L514](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/channel.ex#L512-L514)). The guide adds that "the `handle_out/3` callback will be called for every recipient of a message" ([Channels guide L373](https://github.com/phoenixframework/phoenix/blob/v1.8.15/guides/real_time/channels.md?plain=1#L373)).

For hidden information, `intercept` is filtering on the receiving side. The whole payload reaches every channel process before `handle_out` decides what to push. It is the Channels version of option A below.

### 1.3 None of that applies to LiveView (from source)

- `Phoenix.LiveView.Socket` routes `channel "lv:*", Phoenix.LiveView.Channel` ([socket.ex L94-L95](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/socket.ex#L94-L95)). `Phoenix.LiveView.Channel` is its own `use GenServer` ([channel.ex L3](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/channel.ex#L3)). It does not go through `Phoenix.Channel.Server.join`, which is where fastlane subscription happens.
- A search of `lib/` in phoenix_live_view 1.2.12 finds no `fastlane`, no `intercept`/`handle_out`, and no `PubSub.subscribe` call outside docs. LiveView never subscribes to your topics for you.
- Any message you send it lands in the catch-all `handle_info(msg, ...)`, which calls your `handle_info/2` and then `handle_result` ([channel.ex L383-L387](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/channel.ex#L383-L387)).
- `handle_changed` renders a diff and pushes it ([L945-L959](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/channel.ex#L945-L959)). `push/3` builds a `%Message{}` and does `send(transport_pid, serializer.encode!(message))` ([L1159-L1168](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/channel.ex#L1159-L1168)). Encoding is per LiveView, per message.
- There is no batching. Every message that changes assigns causes one render and one push. If nothing changed, nothing is rendered or sent ([render_diff L1113-L1147](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/channel.ex#L1113-L1147), [push_diff L1099-L1101](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/channel.ex#L1099-L1101)).

Fastlane would not help 36s anyway. Every LiveView renders different HTML, so there is no single encoded frame to share.

### 1.4 Multiplexing

- `Phoenix.Socket` is "A socket implementation that multiplexes messages over channels" ([socket.ex L3](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/socket.ex#L3)). The JS client says "A single connection is established to the server and channels are multiplexed over the connection" ([index.js L5-L7](https://github.com/phoenixframework/phoenix/blob/v1.8.15/assets/js/phoenix/index.js#L5-L7)).
- "One channel server lightweight process is created per client, per topic" ([Channels guide L63](https://github.com/phoenixframework/phoenix/blob/v1.8.15/guides/real_time/channels.md?plain=1#L63)).
- The LiveView client opens one Phoenix socket ([live_socket.ts L360](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/assets/js/phoenix_live_view/live_socket.ts#L360)). Every view, root or nested, joins its own `lv:<id>` channel on it ([view.ts L202](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/assets/js/phoenix_live_view/view.ts#L202)).
- A nested LiveView (`live_render/3`) "runs in a separate process than the parent". The guide calls it "a slightly expensive abstraction if all you want is to compartmentalize markup or events" ([welcome.md L278-L294](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/guides/introduction/welcome.md?plain=1#L278-L294)). LiveComponents "run in the same process as the parent LiveView" (same file, section "Live components to encapsulate additional state").

What this means for 36s:

- One browser tab is one WebSocket. Two tabs are two WebSockets and two LiveView processes. Multiplexing does not merge people or tabs, so it does not reduce fan-out work.
- A nested LiveView, for example a chat panel, is another process for the same person. If it also needs Room updates, it is another pid to subscribe or register. LiveComponents add no processes. A Room message to the parent LiveView can update them through assigns or `send_update`.
- The "disconnect all of a user's sockets" feature rides on the socket id. You set `live_socket_id` in the session and broadcast `"disconnect"` on it ([security-model.md L280-L291](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/guides/server/security-model.md?plain=1#L280-L291)). That is a tool for kicking a person. It is not a delivery channel.

### 1.5 What a LiveView update costs

Facts from the docs:

- After the first render, LiveView "will only resend the dynamic part if it changes". Tracking works on map fields, so `@user.name` can change without resending `@user.id` ([Assigns and HEEx, change tracking](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/guides/server/assigns-eex.md?plain=1#L23-L55)).
- `assign/3` is a no-op when the new value equals the old one ([utils.ex L33-L41](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/utils.ex#L33-L41)). Re-sending an identical view is cheap. No render happens and no frame is sent.
- In comprehensions, statics are sent once. By default the index tracks changes, and `:key` on the tag tracks by identity instead ([assigns-eex.md L271-L312](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/guides/server/assigns-eex.md?plain=1#L271-L312)).
- Variables in templates disable change tracking ([Common pitfalls](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/guides/server/assigns-eex.md?plain=1#L89-L160)).
- José Valim's [Supercharge your app: latency and rendering optimizations in Phoenix LiveView](https://dashbit.co/blog/latency-rendering-liveview) (Dashbit, 2023) explains how templates are compiled so only compact dynamic data travels. The post says "LiveView developers don't have to modify a single line of code to benefit from this."

**Local measurement.** This is an indicative microbenchmark I ran, not a published number. Setup was phoenix_live_view 1.2.12, OTP 28, Apple Silicon laptop, 18 schedulers, calling `Phoenix.LiveView.Diff.render/4` and `Jason.encode!/1` directly. The template is a 20-seat table, the current Bid, whose turn it is, and the viewer's own 5 dice. The update changes the Bid and the turn.

| Template variant | First render | Update diff | Render + diff + encode per update |
|---|---|---|---|
| Row class computed in the template, `class={p.id == @view.turn && "active"}` | 1,542 bytes | 321 bytes. All 20 rows resent, because every row depends on `@view.turn`. | ~14 µs |
| `active` precomputed per seat in the view, plus `:key={p.id}` | 1,542 bytes | 77 bytes. Only the two rows whose `active` flipped. | ~5 µs |

For 30 LiveViews that is roughly 0.15 to 0.45 ms of CPU per Room event, spread across schedulers. It leaves out process scheduling, WebSocket framing and TCP. A 36s Round has a few events a minute, so any approach below is fast enough. The larger lever is making `view_for` return data that is already derived, such as per-seat flags and counts. The template then does little work and diffs stay small. The script is in the appendix.

### 1.6 `temporary_assigns`, streams, `push_event`, `send_update`

| Tool | What it does | Where it could fit in 36s | Note for hidden dice or reconnects |
|---|---|---|---|
| `temporary_assigns` | Assigns "reset to their value after every render" ([phoenix_live_view.ex L251-L254](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view.ex#L251-L254)) | Rarely needed now. Streams replaced its main use. | In [Phoenix Dev Blog, Streams](https://fly.io/phoenix-files/phoenix-dev-blog-streams/) (2023), Chris McCord says the old temporary-assigns approach to collections "sucked even when it worked". |
| Streams | "managing large collections on the client without keeping the resources on the server" ([phoenix_live_view.ex L1848-L1852](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view.ex#L1848-L1852)) | A Bid log for the Round, or chat. Not the table, which is small and fully replaced. | A reconnect is a new LiveView with an empty stream. The Room must hand over the history again on mount. The Phoenix 1.8 generators refetch and `stream(..., reset: true)` on every change ([index.ex.eex L66-L69](https://github.com/phoenixframework/phoenix/blob/v1.8.15/priv/templates/phx.gen.live/index.ex.eex#L66-L69)). |
| `push_event/3` | Sends a payload to JS hooks and `window` listeners ([phoenix_live_view.ex L819-L874](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view.ex#L819-L874)) | Dice-roll or reveal animations | The payload reaches the browser as-is with no diffing, so anything in it can be read in devtools. It is sent once and not replayed on reconnect. Never carry state only in `push_event`. |
| `send_update/3` | Updates a LiveComponent. It accepts another LiveView's pid ([phoenix_live_view.ex L1509-L1580](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view.ex#L1509-L1580)). | The Room could target a component in a LiveView directly | This couples the Room, which is domain code, to web component module names. Sending one message to the LiveView and letting it update its components is looser coupling. |

### 1.7 Presence and Tracker as a delivery signal

- Presence computes diffs in a task and then calls `Phoenix.PubSub.local_broadcast` of a `%Phoenix.Socket.Broadcast{event: "presence_diff"}` **on the tracked topic** ([presence.ex L519-L536](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/presence.ex#L519-L536)). Every subscriber of that topic gets it, including LiveViews subscribed for game state.
- The sender is the Presence process, not the Room. A presence diff and a Room message can arrive in either order.
- `handle_metas/4` gives a server-side callback for joins and leaves. The documented example rebroadcasts with `local_broadcast` ([presence.ex L140-L190](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/presence.ex#L140-L190)). For the Room to learn about Away through Presence, a handler would have to forward to the Room. That is a third process between "LiveView died" and "Room knows".
- `Phoenix.Tracker` from phoenix_pubsub does tracking without the broadcasts, as the Presence moduledoc suggests ([presence.ex L12-L16](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/presence.ex#L12-L16)). Its value is cluster-wide replication. 36s runs on one node.
- Presence metadata is broadcast to every subscriber, so it must never hold dice. The earlier file already says this.

---

## 2. Delivery approaches for 36s

The criteria are:

- **(a)** Hidden dice. Can another Player's dice enter a LiveView process or reach a browser?
- **(b)** Latency and efficiency at ~30 people.
- **(c)** Knowing when a person has no live connections, which is Away.
- **(d)** Complexity.
- **(e)** Testability with `Phoenix.LiveViewTest`.

"Person" means a Player or a Spectator. `view_for(room, person)` is the pure projection already decided on.

### A. One Room topic, full Game state, each LiveView filters

The Room broadcasts the whole Game on `"room:CODE"`. Each LiveView calls `view_for` itself, or renders straight from the Game. This is what Fly.io's tictac demo does. `GameServer.broadcast_game_state/1` broadcasts `{:game_state, state}` on `"game:#{code}"` ([game_server.ex L185-L187](https://github.com/fly-apps/tictac/blob/2e5c5cd44a147e5b7b754860d187fcfda74cf74a/lib/tictac/game_server.ex#L185-L187)). The LiveView does `assign(:game, state)` ([play_live.ex L79-L86](https://github.com/fly-apps/tictac/blob/2e5c5cd44a147e5b7b754860d187fcfda74cf74a/lib/tictac_web/live/play_live.ex#L79-L86)). Tic-tac-toe has no hidden information.

- (a) Fails the "never enters a LiveView process" bar. Every LiveView heap holds every die. Browser safety depends on every template and every `push_event` payload. The Channels version of this, `intercept`, has the same property.
- (b) One broadcast, 30 full copies. Fine at this size.
- (c) Nothing. Needs Presence or registration.
- (d) Lowest. One message type.
- (e) Easy to drive. The leak test must check both the HTML and the LiveView state, because a die can sit unrendered in assigns.

### B. Per-person topics carrying the projected view

For each person, the Room computes `view_for(room, person)` and broadcasts it on a person-scoped topic such as `"room:CODE:person:ID"`. Spectators all see the same public view, so they can share `"room:CODE:spectators"` or each have a topic. This is the Phoenix 1.8 "scoped PubSub" idea applied to a Room, with the scope being the person ([schema_access_scope.ex.eex L1-L25](https://github.com/phoenixframework/phoenix/blob/v1.8.15/priv/templates/phx.gen.context/schema_access_scope.ex.eex#L1-L25)). LiveBeats uses per-user topics the same way: `"user:#{user_id}"`, with `subscribe/1` and `broadcast!/2` inside the context ([accounts.ex L10-L18](https://github.com/fly-apps/live_beats/blob/ac9780472e7019af274110a1cf71250a8d40c986/lib/live_beats/accounts.ex#L10-L18)).

- (a) Passes. A LiveView only ever receives its own person's view. The condition is that `mount/3` takes the person id from the server-side session, never from URL params or event params. If it took it from params, a Player could edit the URL and subscribe to another Player's topic. A browser cannot subscribe to PubSub topics itself unless the app defines a Channel that joins them.
- (b) N projections and N small broadcasts per event. PubSub handles several tabs and a stale-plus-new LiveView for free, because every subscriber of the topic gets the message.
- (c) Nothing. PubSub never tells the Room whether a topic has subscribers.
- (d) Low. The Room needs the list of person ids, which it has as seats and spectators. It does not need pids.
- (e) Good. A test process can subscribe to a person's topic and `assert_receive` the view, with no LiveView involved. `view_for` itself is a pure-function test.

### C. Room topic for the public view, plus a per-person topic for private data

This is the earlier file's "shape B". The public part, meaning counts, the Bid, the turn, and revealed dice after a Check, goes once on `"room:CODE"`. Each Player's own dice go on their person topic.

- (a) Passes, under the same session-identity rule as B.
- (b) Slightly fewer projections than B. Each LiveView gets two messages per event, and may render twice unless the Room sends the private part only when it changes.
- (c) Nothing, as in B.
- (d) Moderate. There are two message kinds and a merge step in the LiveView. `view_for` is no longer the single function that shapes what a person sees, because the public and private parts are separate. That is a partial conflict with the decision that `view_for` owns visibility.
- (e) As B.

### D. "Changed" signal, then each LiveView pulls its view

The Room broadcasts a content-free `{:room_changed, version}` on `"room:CODE"`. Each LiveView calls `Room.view_for(code, me)`, a `GenServer.call`, and assigns the result. This is the generator pattern from Phoenix 1.8: small event, then a scoped re-read ([index.ex.eex L66-L69](https://github.com/phoenixframework/phoenix/blob/v1.8.15/priv/templates/phx.gen.live/index.ex.eex#L66-L69), [scopes guide L172](https://github.com/phoenixframework/phoenix/blob/v1.8.15/guides/authn_authz/scopes.md?plain=1#L172), [Phoenix 1.8.0 released](https://www.phoenixframework.org/blog/phoenix-1-8-released)).

- (a) Passes, if the signal carries nothing secret and `me` comes from the session.
- (b) Each event costs one broadcast and then 30 calls queued in the Room mailbox, each running `view_for`. That is the same projection work as B plus 30 round trips. It is fine at 30 people. It is the only option here where every event makes all LiveViews block on the Room.
- (c) Nothing, unless the call also registers the caller.
- (d) Low in code. The costs are in behaviour. A LiveView that calls a dead or restarting Room crashes, as the earlier file notes. If the Room ever made a blocking call to a LiveView, the two could deadlock. Keep Room-to-LiveView traffic to `send`.
- (e) Good. The same `view_for` call serves mount and updates, so there is one code path to test.

### E. Direct sends to registered, monitored LiveView pids

This is "option C" in the earlier file. In `mount/3`, when connected, the LiveView calls `Room.join(code, person_id, self())`. The Room monitors the pid, records `pid => person_id`, and replies with the current `view_for`. After every event the Room sends each registered pid its own view. On `{:DOWN, ...}` the Room removes the pid. A person with no pids left is Away.

Livebook is the closest official-grade example. `Session.register_client/3` is a call that returns the current data ([session.ex L229-L244](https://github.com/livebook-dev/livebook/blob/v0.19.10/lib/livebook/session.ex#L229-L244)). The session monitors the client pid and keeps `client_pids_with_id` ([L1109-L1122](https://github.com/livebook-dev/livebook/blob/v0.19.10/lib/livebook/session.ex#L1109-L1122)). It turns `:DOWN` into a `:client_leave` operation ([L1714-L1724](https://github.com/livebook-dev/livebook/blob/v0.19.10/lib/livebook/session.ex#L1714-L1724)) and sends client-specific output with `send(client_pid, ...)` ([L1756-L1768](https://github.com/livebook-dev/livebook/blob/v0.19.10/lib/livebook/session.ex#L1756-L1768)).

- (a) Passes. Only the Room decides which view goes to which pid.
- (b) N projections and N sends. The fastest path, with no Registry lookup. Views should be computed once per person, not once per pid, and then sent to each of that person's pids.
- (c) Best of the options. `:DOWN` arrives the moment the LiveView process ends. That is immediate on a clean close and after the WebSocket timeout on a silent drop; the earlier file, section 6, has the timings. Several pids per person is a `%{person_id => MapSet.of(pids)}`. Away means the set is empty. Any grace-period timer is Room logic.
- (d) Moderate. The Room keeps pid bookkeeping, monitors, and cleanup. **Room restart is the sharp edge.** A restarted Room starts with no pids and sends nothing, while the LiveViews think they are still connected. Each LiveView must monitor the Room and, on `:DOWN`, look it up again and re-join, or give up and show "Room gone". With PubSub (B/C/D) the topic outlives the Room process, so a restarted Room reaches existing subscribers without any re-join.
- (e) Good. A test process can call `Room.join(code, id, self())` and `assert_receive` views. It can `Process.exit` a fake client to test Away. `live/2` in `Phoenix.LiveViewTest` starts a real LiveView process, so the Room monitors it exactly as in production.

### F. Hybrid: register-and-monitor for Away, PubSub for delivery

LiveViews join the Room as in E, which gives immediate Away and an atomic snapshot. They also subscribe to their person topic as in B, and the Room broadcasts views there. Livebook does this: `register_client` plus a monitor for presence, a `"sessions:#{id}"` topic for shared operations ([session.ex L2416-L2431](https://github.com/livebook-dev/livebook/blob/v0.19.10/lib/livebook/session.ex#L2416-L2431), [L2835-L2837](https://github.com/livebook-dev/livebook/blob/v0.19.10/lib/livebook/session.ex#L2835-L2837)), and direct `send` for per-client output.

- (a) Passes, as B.
- (b) Same as B.
- (c) Same as E.
- (d) The highest, with two mechanisms. It does soften E's restart edge. Delivery survives a Room restart, and only the Away bookkeeping needs re-joining.
- (e) As B and E.

### Not a separate option: Elixir `Registry` as the pubsub

`Registry` with duplicate keys can act as "a local, non-distributed, scalable PubSub" ([Registry, using as a PubSub](https://hexdocs.pm/elixir/Registry.html#module-using-as-a-pubsub)). Phoenix.PubSub is that plus cluster forwarding, so this is option B with fewer features. Entries vanish when the process exits, but dispatch "may return processes that are already dead", and nothing notifies anyone ([Registry](https://hexdocs.pm/elixir/Registry.html)). It does not solve Away.

---

## 3. Comparison

| | (a) Other Players' dice stay out of LiveView processes | (b) Cost per Room event, 30 people | (c) Away detection | (d) Complexity | (e) LiveViewTest | Survives Room restart without LiveView help |
|---|---|---|---|---|---|---|
| A. Room topic, full state | **No** | 1 broadcast, 30 full copies | Needs Presence or registration | Lowest | Easy; leak test must inspect LiveView state too | Yes |
| B. Per-person topics, projected | Yes, if id comes from session | N projections, N broadcasts | Needs Presence or registration | Low | Easy; subscribe in test | Yes |
| C. Public topic + private topic | Yes, if id comes from session | ~1 + N broadcasts, up to 2 renders per LiveView | Needs Presence or registration | Moderate; splits `view_for` | Easy | Yes |
| D. Signal, then pull | Yes, if signal is empty | 1 broadcast + N calls into the Room | Only if the call registers | Low code, blocking behaviour | Easy | Yes, but calls fail during restart |
| E. Direct send to monitored pids | Yes | N projections, N sends | **Immediate via `:DOWN`** | Moderate | Easy; fake clients are just `self()` | **No**, LiveViews must re-join |
| F. E for Away + B for delivery | Yes | As B | As E | Highest | Easy | Delivery yes, Away needs re-join |

In every row, latency at 30 people is dominated by the network, not the server. Section 1.5 has the numbers.

## 4. What the core team recommends, and what known apps do

| Source | Pattern | Fit to 36s |
|---|---|---|
| LiveView docs | Subscribe in `mount/3` only when `connected?/1`; update assigns in `handle_info/2` ([phoenix_live_view.ex L628-L654](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view.ex#L628-L654)). Events are "usually emitted by `Phoenix.PubSub`" ([welcome.md L19-L21](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/guides/introduction/welcome.md?plain=1#L19-L21)). | Baseline for A to D |
| LiveComponent docs | A component broadcasts on a board topic; the parent LiveView subscribes. "The advantage of using PubSub is that we get distributed updates out of the box." ([phoenix_live_component.ex L349-L371](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_component.ex#L349-L371)) | Shared, non-secret data |
| Phoenix 1.8 generators and scopes guide (Chris McCord) | Per-scope topic, small event, re-read through the scoped context. Presented as a security default. ([Phoenix 1.8.0 released](https://www.phoenixframework.org/blog/phoenix-1-8-released), [scopes guide](https://github.com/phoenixframework/phoenix/blob/v1.8.15/guides/authn_authz/scopes.md?plain=1#L128-L172)) | B or D, with person as scope |
| Channels docs | Plain broadcasts get fastlane automatically. Use `intercept` only when a socket must change or drop a message, and it costs one encode per subscriber ([channel.ex L505-L514](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/channel.ex#L505-L514)). | Not usable from LiveView |
| LiveView welcome guide | Prefer function components, then LiveComponents. Nested LiveViews are for isolation and "slightly expensive" ([welcome.md L278-L299](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/guides/introduction/welcome.md?plain=1#L278-L299)). | One LiveView per page keeps one pid per tab |
| Streams (Chris McCord, [Phoenix Dev Blog](https://fly.io/phoenix-files/phoenix-dev-blog-streams/)) | Streams for large or growing collections | Bid log or chat only |
| Livebook (José Valim / Dashbit), v0.19.10 | Register-and-monitor clients, PubSub topic for shared operations, direct `send` for per-client data. The LiveView keeps raw session data in socket private and renders a derived `data_view` assign ([session_live.ex L1290-L1301](https://github.com/livebook-dev/livebook/blob/v0.19.10/lib/livebook_web/live/session_live.ex#L1290-L1301)). Custom PubSub dispatcher that encodes once per encoder, fastlane-style ([session.ex L3254-L3284](https://github.com/livebook-dev/livebook/blob/v0.19.10/lib/livebook/session.ex#L3254-L3284)). | F, the closest real app to a Room server with per-client views |
| LiveBeats (Chris McCord, [blog post](https://fly.io/blog/livebeats/)) | Context modules own `subscribe`/`broadcast`, per-user topics, typed event structs ([media_library.ex L50-L52, L576-L578](https://github.com/fly-apps/live_beats/blob/ac9780472e7019af274110a1cf71250a8d40c986/lib/live_beats/media_library.ex#L576-L578)) | B |
| tictac (Mark Ericksen, Fly.io, [blog post](https://fly.io/blog/building-a-distributed-turn-based-game-system-in-elixir/)) | GenServer per game, full state on one game topic | A. Works because tic-tac-toe has no hidden state. |

I found no core-team post or official example that deals with per-player hidden information in a LiveView game. The closest official guidance is the scopes pattern: scope the topic and the read to the viewer. Livebook is the closest real app to "server process with per-client output".

## 5. Pitfalls, including ones that bear on decisions already made

1. **`view_for` owns visibility only if the Room is the only thing that talks to LiveViews about the game.** Presence diffs arrive on whatever topic you track, `%Broadcast{event: "presence_diff"}` on the tracked topic ([presence.ex L527-L535](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/presence.ex#L527-L535)). Track Presence on a separate topic, or not at all, so every game-shaped message still passes through `view_for`. A LiveView without a matching `handle_info` clause crashes on an unexpected message.
2. **"Away = no live connections left" needs registration with the Room, or Presence.** None of the PubSub-only options (A to D) tell the Room anything. Of the two, monitors in the Room (E or F) are immediate and come from the same process that owns the Game. Presence adds a task, a broadcast, and a handler hop, and its events are not ordered with Room messages.
3. **Identity must come from the session.** Per-person topics and `Room.join(code, person_id, self())` are safe only if `person_id` comes from the Plug session read in `mount/3`. URL params and event params can be edited by the user ([Security considerations](https://hexdocs.pm/phoenix_live_view/security-model.html)).
4. **Mount race.** With PubSub, subscribe before fetching the snapshot. Otherwise an event between "fetch" and "subscribe" is lost. Livebook does it in the other order: `register_client` returns data, then `subscribe` ([session_live.ex L20-L25](https://github.com/livebook-dev/livebook/blob/v0.19.10/lib/livebook_web/live/session_live.ex#L20-L25)). An operation broadcast between those two calls would not reach that client. With subscribe-first, older queued messages can arrive after the snapshot and briefly show stale state. A version number in every view lets the LiveView drop anything older than what it holds. E avoids both problems, because join, register and snapshot happen in one Room call.
5. **One sender, or no ordering.** Keep all game messages coming from the Room process. If the acting LiveView applies its own Bid on the spot and then uses `broadcast_from` to skip itself, it can drift from the Room's order. Let the actor's LiveView get its update from the Room like everyone else.
6. **The Room must never `GenServer.call` a LiveView.** LiveViews call the Room in D, E and F. A call in the other direction can deadlock. Use `send` only.
7. **No coalescing.** Each message that changes assigns causes one render and one frame (section 1.3). The Room should send one message per person per action, not several partial ones.
8. **Room restart.** With E, a restarted Room has no pids, so LiveViews must monitor the Room and re-join. With PubSub delivery, topics outlive the Room, but a restarted Room still has to rebuild state from the Postgres snapshot before its first broadcast. This connects to the earlier file's restart and snapshot pitfalls.
9. **`push_event` and streams are at-most-once.** A reconnect loses them. Anything the page needs after a remount must be in assigns built from the Room's current view.
10. **Nested LiveViews multiply pids per person.** If 36s adds a child LiveView that needs Room data, it must register or subscribe too, and the Away logic must count it. LiveComponents avoid this.
11. **Template shape costs more than delivery choice.** Expressions that compare every row with a changed assign resend every row (section 1.5). Put derived flags in `view_for`'s output and use `:key` on seat rows.

## 6. Testing notes

- `Phoenix.LiveViewTest` documents testing message handling as `send(view.pid, msg)` and then `render(view)` ([live_view_test.ex L145-L153](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/test/live_view_test.ex#L145-L153)). A Room message can be simulated the same way.
- In tests the transport is `ClientProxy`, whose serializer `encode!/1` returns the message unchanged ([client_proxy.ex L33-L36](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/test/client_proxy.ex#L33-L36)). `render(view)` is therefore built from the same diffs a browser would get. `assert_push_event` and `refute_push_event` cover hook payloads ([L1745-L1795](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/test/live_view_test.ex#L1745-L1795)).
- A leak test that matches the "never enters a LiveView process" bar can check the LiveView's server state too, because the LiveView is a GenServer. For example, look for other Players' dice in `:sys.get_state(view.pid)`. This is derived from `Phoenix.LiveView.Channel` being a GenServer ([channel.ex L3](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/channel.ex#L3)). It is not a documented LiveViewTest feature.
- For B, C and F, a test can subscribe to a person topic and `assert_receive` the view without any LiveView. For E, the test process can join as a fake client and `Process.exit/2` it to test Away.
- Sync point. After calling a Room action, which is a `GenServer.call` whose handler sends to LiveViews before replying, `render(view)` goes test → proxy → LiveView. On one node that reliably runs after the Room's `send` has landed. Erlang only formally guarantees order per sender pair, though. If a test turns out flaky, a `:sys.get_state(view.pid)` round trip after the action is a cheap barrier.

## Appendix: benchmark script

Run with `elixir diff_cost.exs`. It uses internal `Phoenix.LiveView.Diff` functions, so treat the numbers as indicative only.

```elixir
Mix.install([{:phoenix_live_view, "1.2.12"}, {:jason, "~> 1.4"}])

defmodule T do
  use Phoenix.Component
  attr :view, :map, required: true

  def table(assigns) do
    ~H"""
    <div id="table">
      <p id="bid">Current bid: {@view.bid.count} x {@view.bid.face} by {@view.bid.by}</p>
      <p id="turn">Turn: {@view.turn}</p>
      <ul id="players">
        <li :for={p <- @view.players} id={"p-#{p.id}"} class={p.id == @view.turn && "active"}>
          {p.name} - {p.dice_count} dice
          <span :if={p.away} class="away">away</span>
        </li>
      </ul>
      <div id="mine"><span :for={d <- @view.my_dice} class="die">{d}</span></div>
    </div>
    """
  end
end

alias Phoenix.LiveView.Diff
players = for i <- 1..20, do: %{id: i, name: "Player #{i}", dice_count: 5, away: false}
v1 = %{bid: %{count: 3, face: 4, by: 1}, turn: 2, players: players, my_dice: [1, 3, 3, 5, 6]}
v2 = %{v1 | bid: %{count: 4, face: 4, by: 2}, turn: 3}
socket = struct(Phoenix.LiveView.Socket, assigns: %{__changed__: %{}})

{diff1, prints, comps} =
  Diff.render(socket, T.table(%{view: v1, __changed__: nil}), Diff.new_fingerprints(), Diff.new_components())

step = fn ->
  {d, _, _} = Diff.render(socket, T.table(%{view: v2, __changed__: %{view: v1}}), prints, comps)
  Jason.encode!(d)
end

IO.puts("first render bytes: #{byte_size(Jason.encode!(diff1))}")
IO.puts("update diff bytes: #{byte_size(step.())}")
for _ <- 1..500, do: step.()
{us, _} = :timer.tc(fn -> for _ <- 1..5000, do: step.() end)
IO.puts("per update: #{Float.round(us / 5000, 1)} us")
```

The keyed variant swaps `class={p.id == @view.turn && "active"}` for `:key={p.id} class={p.active && "active"}`, adds `active: i == 2` to each seat, and sets `active: &1.id == 3` for every seat in `v2`.

## Sources

Official docs:

- Phoenix LiveView: [Phoenix.LiveView](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html), [Phoenix.LiveComponent](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveComponent.html), [Phoenix.LiveViewTest](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveViewTest.html), [Assigns and HEEx templates](https://hexdocs.pm/phoenix_live_view/assigns-eex.html), [Welcome](https://hexdocs.pm/phoenix_live_view/welcome.html), [Security considerations](https://hexdocs.pm/phoenix_live_view/security-model.html)
- Phoenix: [Channels guide](https://hexdocs.pm/phoenix/channels.html), [Scopes guide](https://hexdocs.pm/phoenix/scopes.html), [Phoenix.Channel](https://hexdocs.pm/phoenix/Phoenix.Channel.html), [Phoenix.Socket](https://hexdocs.pm/phoenix/Phoenix.Socket.html), [Phoenix.Presence](https://hexdocs.pm/phoenix/Phoenix.Presence.html)
- Phoenix.PubSub: [Phoenix.PubSub](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html)
- Elixir: [Registry](https://hexdocs.pm/elixir/Registry.html)
- Erlang/OTP: [Processes, signal ordering](https://www.erlang.org/doc/system/ref_man_processes.html), [Efficiency guide, processes](https://www.erlang.org/doc/system/eff_guide_processes.html)

Source code, at release tags:

- phoenix v1.8.15: [lib/phoenix/channel/server.ex](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/channel/server.ex), [lib/phoenix/channel.ex](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/channel.ex), [lib/phoenix/socket.ex](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/socket.ex), [lib/phoenix/presence.ex](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/presence.ex), [assets/js/phoenix/index.js](https://github.com/phoenixframework/phoenix/blob/v1.8.15/assets/js/phoenix/index.js), [priv/templates/phx.gen.live/index.ex.eex](https://github.com/phoenixframework/phoenix/blob/v1.8.15/priv/templates/phx.gen.live/index.ex.eex), [priv/templates/phx.gen.context/schema_access_scope.ex.eex](https://github.com/phoenixframework/phoenix/blob/v1.8.15/priv/templates/phx.gen.context/schema_access_scope.ex.eex), [guides/real_time/channels.md](https://github.com/phoenixframework/phoenix/blob/v1.8.15/guides/real_time/channels.md), [guides/authn_authz/scopes.md](https://github.com/phoenixframework/phoenix/blob/v1.8.15/guides/authn_authz/scopes.md)
- phoenix_live_view v1.2.12: [lib/phoenix_live_view/channel.ex](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/channel.ex), [lib/phoenix_live_view/socket.ex](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/socket.ex), [lib/phoenix_live_view/utils.ex](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/utils.ex), [lib/phoenix_live_view.ex](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view.ex), [lib/phoenix_live_component.ex](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_component.ex), [lib/phoenix_live_view/test/live_view_test.ex](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/test/live_view_test.ex), [lib/phoenix_live_view/test/client_proxy.ex](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/test/client_proxy.ex), [assets/js/phoenix_live_view/view.ts](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/assets/js/phoenix_live_view/view.ts), [assets/js/phoenix_live_view/live_socket.ts](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/assets/js/phoenix_live_view/live_socket.ts), [guides/](https://github.com/phoenixframework/phoenix_live_view/tree/v1.2.12/guides)
- phoenix_pubsub v2.3.0: [lib/phoenix/pubsub.ex](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/pubsub.ex), [lib/phoenix/pubsub/pg2.ex](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/pubsub/pg2.ex), [lib/phoenix/pubsub/supervisor.ex](https://github.com/phoenixframework/phoenix_pubsub/blob/v2.3.0/lib/phoenix/pubsub/supervisor.ex)

Core team and Fly.io / Dashbit posts:

- Chris McCord, [Phoenix 1.8.0 released](https://www.phoenixframework.org/blog/phoenix-1-8-released), 2025
- Chris McCord, [Phoenix Dev Blog, Streams](https://fly.io/phoenix-files/phoenix-dev-blog-streams/), 2023
- Chris McCord, [LiveBeats: Building a social music app with Phoenix LiveView](https://fly.io/blog/livebeats/), 2022
- José Valim, [Supercharge your app: latency and rendering optimizations in Phoenix LiveView](https://dashbit.co/blog/latency-rendering-liveview), 2023
- José Valim, [You may not need Redis with Elixir](https://dashbit.co/blog/you-may-not-need-redis-with-elixir)
- Gary Rennie, [The Road to 2 Million Websocket Connections in Phoenix](https://www.phoenixframework.org/blog/the-road-to-2-million-websocket-connections), 2015. PubSub sharding by subscriber pid.
- Mark Ericksen, [Building a Distributed Turn-Based Game System in Elixir](https://fly.io/blog/building-a-distributed-turn-based-game-system-in-elixir/), Fly.io, 2021
- Jason Stiebs, [A LiveView is a Process](https://fly.io/phoenix-files/a-liveview-is-a-process/), Fly.io, 2023. Mailbox is FIFO and handled one message at a time.

Example apps, pinned:

- Livebook v0.19.10: [lib/livebook/session.ex](https://github.com/livebook-dev/livebook/blob/v0.19.10/lib/livebook/session.ex), [lib/livebook_web/live/session_live.ex](https://github.com/livebook-dev/livebook/blob/v0.19.10/lib/livebook_web/live/session_live.ex)
- tictac @2e5c5cd: [lib/tictac/game_server.ex](https://github.com/fly-apps/tictac/blob/2e5c5cd44a147e5b7b754860d187fcfda74cf74a/lib/tictac/game_server.ex), [lib/tictac_web/live/play_live.ex](https://github.com/fly-apps/tictac/blob/2e5c5cd44a147e5b7b754860d187fcfda74cf74a/lib/tictac_web/live/play_live.ex)
- LiveBeats @ac97804: [lib/live_beats/accounts.ex](https://github.com/fly-apps/live_beats/blob/ac9780472e7019af274110a1cf71250a8d40c986/lib/live_beats/accounts.ex), [lib/live_beats/media_library.ex](https://github.com/fly-apps/live_beats/blob/ac9780472e7019af274110a1cf71250a8d40c986/lib/live_beats/media_library.ex)
