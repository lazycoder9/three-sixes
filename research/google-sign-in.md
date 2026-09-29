# Google sign-in for 36s (Phoenix 1.8, LiveView)

Research for [issue #11](https://github.com/lazycoder9/three-sixes/issues/11). This file lists facts and trade-offs. It does not make the decision.

Terms follow `CONTEXT.md` (Guest, Account, Room, Nickname, Away). It builds on settled decisions: a Guest id lives in the Plug session cookie; each Room is a GenServer that a LiveView joins once in `mount` as "person X" (X from the Plug session); the Room monitors the LiveView and sends it a per-person view ([ADR 0001](../docs/adr/0001-room-process-holds-live-game-state.md)).

**Versions checked (2026-09-29):** Phoenix 1.8.15, Phoenix LiveView 1.2.12, Plug 1.20.3, ueberauth 0.10.8, ueberauth_google 0.12.1, assent 0.3.1, oidcc 3.9.0, oidcc_plug 0.5.1. Release dates are from the Hex API (`https://hex.pm/api/packages/<name>`). Source links point at those tags or at the default branch where noted.

## Summary

- **Libraries.** ueberauth + ueberauth_google is the best-known option but slow to release: ueberauth 0.10.8 shipped in Feb 2024 and ueberauth_google 0.12.1 in Nov 2023, though both repos still get commits. It uses the OAuth2 code flow plus Google's userinfo endpoint and does not validate an ID token. assent 0.3.1 (Jun 2025) treats Google as OpenID Connect, validates the ID token, and is plain functions rather than a plug. oidcc (+ oidcc_plug) is OpenID-certified and actively released, but it is heavier. None of them replaces `mix phx.gen.auth`; they all sit beside it or beside hand-written session code.
- **phx.gen.auth** in 1.8 generates magic-link email login, optional passwords, a DB-backed session token, a `Scope` struct, `on_mount` hooks and `live_socket_id` handling. For Google-only you would delete about half of it (email login, registration, settings, notifier). What stays useful is the session-token table, the scope, the LiveView hooks and the logout disconnect. Its `renew_session` clears the whole session, so it would also wipe the Guest id unless you copy that across on purpose.
- **Switching identity mid-Room.** Sending the tab to Google is a full-page navigation. The browser closes the WebSocket, the LiveView process stops with `{:shutdown, :closed}`, and the Room gets `:DOWN`. The seat is **Away** for as long as the person is on Google's pages. After the callback, a controller redirects back to the Room URL and a new LiveView mounts. The connected mount reads the session from the cookie at WebSocket connect time, so it sees the Account. There is no way to change the identity of the open LiveView through the cookie alone.
- **Other open tabs** stay connected as the Guest until their socket reconnects. If the sign-in callback clears the session and deletes the CSRF token (as phx.gen.auth does), a reconnecting tab fails the CSRF check, gets `"stale"`, and does a full page reload. That reload mounts it as the Account. Broadcasting `"disconnect"` on a Guest `live_socket_id` forces this at once.
- **Guest-to-Account merge.** The usual pattern (Firebase, Supabase, Devise's guest-user recipe) is: keep the anonymous id until sign-in, then reassign its records to the permanent id. If the permanent account already exists, merge or pick a winner in app code. In 36s this happens in the OAuth callback, before the session is cleared.
- **Google Cloud.** With only `openid email profile`, an app left in **Testing** has no test-user list, shows no warning, and its sign-ins do not expire after 7 days. Google states this exception explicitly. App verification is not required for non-sensitive scopes. Brand verification is needed only to show the app name and logo; without it, users see the app's domain. A privacy policy URL is required once the app is public, and homepage, privacy and terms links are "required for all external production apps". Google requires separate Cloud projects per deployment tier.
- **Secrets** go in `config/runtime.exs` from env vars (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`), as the Phoenix deployment guide recommends. Google now shows a client secret only once, when it is created.
- **Pitfalls to flag.** In-app browsers that use embedded webviews (some messaging apps) get `disallowed_useragent` from Google. Use `sub`, not email, as the Google identity key. Store and validate a local `return_to` path. A shared device can hand one person's Guest history to another person's Account.

---

## 1. Library options

### Facts per library

| Library | Latest on Hex | Repo activity | How it works | Notes |
|---|---|---|---|---|
| [ueberauth](https://github.com/ueberauth/ueberauth) + [ueberauth_google](https://github.com/ueberauth/ueberauth_google) | 0.10.8 (2024-02-27); ueberauth_google 0.12.1 (2023-11-14) | ueberauth: last commit 2026-09-18, 30 open issues. ueberauth_google: last commit 2026-07-24 (README), previous code commit 2024-02-22 | A plug in a controller handles `/auth/:provider` (request) and `/auth/:provider/callback`. It uses the OAuth2 code flow via the `oauth2` package, then calls `https://www.googleapis.com/oauth2/v3/userinfo` with the access token. `uid_field` defaults to `:sub` | Default scope is `"email"`; set `default_scope: "openid email profile"`. It does not validate an ID token, and there is no nonce or PKCE code in the strategy ([google.ex](https://github.com/ueberauth/ueberauth_google/blob/master/lib/ueberauth/strategy/google.ex)). CSRF `state` is kept in a separate `ueberauth.state_param` cookie, `SameSite=Lax` by default ([strategy.ex](https://github.com/ueberauth/ueberauth/blob/master/lib/ueberauth/strategy.ex)) |
| [assent](https://github.com/pow-auth/assent) | 0.3.1 (2025-06-20) | Last commit 2026-06-12, 4 open issues. `main` has unreleased changes (requires Elixir 1.15/OTP 26, removes the Finch adapter) ([CHANGELOG](https://github.com/pow-auth/assent/blob/main/CHANGELOG.md)) | Two plain functions: `authorize_url/1` returns `%{url, session_params}`, and `callback/2` takes the params plus the stored `session_params`. You store `session_params` in the Plug session yourself ([README](https://github.com/pow-auth/assent/blob/main/README.md)) | `Assent.Strategy.Google` is built on `Assent.Strategy.OIDC.Base` ([google.ex](https://github.com/pow-auth/assent/blob/main/lib/assent/strategies/google.ex)). It validates the ID token per OIDC Core, supports `nonce` and PKCE (`code_verifier: true`), and compares `state` in constant time ([oidc.ex](https://github.com/pow-auth/assent/blob/main/lib/assent/strategies/oidc.ex), [oauth2.ex](https://github.com/pow-auth/assent/blob/main/lib/assent/strategies/oauth2.ex)). HTTP via `Req` if present, else `:httpc`. It fetches the discovery document on each call unless you pass `:openid_configuration` |
| [oidcc](https://github.com/erlef/oidcc) + [oidcc_plug](https://github.com/erlef/oidcc_plug) | oidcc 3.9.0 (2026-08-30); oidcc_plug 0.5.1 (2026-08-04) | Erlang Ecosystem Foundation Security WG project, last push 2026-09-27 | A provider-configuration worker in your supervision tree caches the discovery document and keys. Plugs handle authorize and callback | "OpenID Certified ... of multiple Relaying Party conformance profiles" ([README](https://github.com/erlef/oidcc_plug/blob/main/README.md)). Ships an igniter generator (`mix oidcc_plug.gen.controller`). More moving parts than 36s needs for one provider |
| [openid_connect](https://github.com/DockYard/openid_connect) (DockYard) | 1.0.1 (2026-01-07) | 1.0.0 was the first release since 0.2.2 in 2019 | Generic OIDC client | Smaller community. Named for completeness |
| [pow_assent](https://github.com/pow-auth/pow_assent) | 0.4.18 (2024-02-17) | Tied to the Pow auth framework | Pow + assent integration | Pow is an alternative to phx.gen.auth, not a companion to it. Not a fit here |
| Google Identity Services ("Sign in with Google" button / One Tap) | n/a (Google-hosted JS) | n/a | Google's JS returns an ID token, either posted to your `login_uri` (redirect mode) or to a JS callback (popup mode) ([HTML reference](https://developers.google.com/identity/gsi/web/reference/html-reference)) | The server must check the `g_csrf_token` double-submit cookie and verify the JWT signature, `aud`, `iss` and `exp` ([verify guide](https://developers.google.com/identity/gsi/web/guides/verify-google-id-token)). Google lists no Elixir library. Adds a third-party script, which cuts against "JS only where unavoidable" |

### Where each fits next to `mix phx.gen.auth`

`mix phx.gen.auth` in 1.8 generates ([task docs](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/mix/tasks/phx.gen.auth.ex), [guide](https://github.com/phoenixframework/phoenix/blob/v1.8.15/guides/authn_authz/mix_phx_gen_auth.md)):

- `users` (unique `email`, nullable `hashed_password`, `confirmed_at`) and `users_tokens` (token, context, `authenticated_at`) ([migration template](https://github.com/phoenixframework/phoenix/blob/v1.8.15/priv/templates/phx.gen.auth/migration.ex.eex)). Session tokens last 14 days ([schema_token template](https://github.com/phoenixframework/phoenix/blob/v1.8.15/priv/templates/phx.gen.auth/schema_token.ex.eex)).
- Magic-link login, opt-in password, email change, sudo mode, and an email notifier that only logs until you wire up a mailer.
- A `Scope` struct (`%Scope{user: ...}`, `for_user(nil) -> nil`) ([scope template](https://github.com/phoenixframework/phoenix/blob/v1.8.15/priv/templates/phx.gen.auth/scope.ex.eex)).
- `UserAuth` ([auth template](https://github.com/phoenixframework/phoenix/blob/v1.8.15/priv/templates/phx.gen.auth/auth.ex.eex)): `log_in_user/3` (renew session, store token, set `live_socket_id`, redirect to `user_return_to`), `log_out_user/1` (delete token, broadcast `"disconnect"` on `live_socket_id`, renew session), a remember-me cookie (`SameSite=Lax`, 14 days), `on_mount` hooks (`:mount_current_scope`, `:require_authenticated`, `:require_sudo_mode`), and `disconnect_sessions/1`. The `live_socket_id` is per token: `"users_sessions:#{Base.url_encode64(token)}"`.

Facts that matter for a Google-only + Guest app:

- None of the email-login, registration, settings, confirmation or notifier code applies to Google-only. The session-token, scope, `on_mount` and disconnect code does apply.
- An OAuth library's callback ends by calling something like `log_in_user/3` with a user found or created by Google `sub`. The OAuth library and phx.gen.auth do not overlap.
- The generated `renew_session/2` runs `delete_csrf_token()`, `configure_session(renew: true)` and `clear_session()`. Its own comment says to fetch any session data you want to keep before clearing and put it back afterwards. The Guest id is exactly such data.
- The generated `fetch_current_scope_for_user` assigns `nil` scope for anonymous visitors. The Phoenix [Scopes guide](https://github.com/phoenixframework/phoenix/blob/v1.8.15/guides/authn_authz/scopes.md) shows a hand-written scope keyed by a per-session id stored with `put_session`, which is the Guest shape. A 36s scope could carry both (for example `%Scope{guest_id: ..., account: nil | %Account{}}`). This is an inference from the guide, not something the generator produces.
- The generator raises a trap for mixed login methods (password + magic link, credential pre-stuffing). With Google as the only method, that trap does not arise.

Trade-off: running the generator and deleting the email parts gives tested session-token code (revocable tokens, reissue after 7 days, logout disconnect). Writing it by hand is maybe a hundred lines, but you have to redo those details yourself.

## 2. Switching identity while a LiveView is live

### What happens to the open LiveView

1. The Guest clicks "Sign in with Google". This must be a real page navigation (plain `<a href>` or `redirect/2`), because the OAuth request route is a controller that answers with a 302 to Google. LiveView's `redirect/2` "rel[ies] on instructing client to perform a `window.location` update ... The whole page will be reloaded and all state will be discarded. Calling redirect shuts down the LiveView channel." ([phoenix_live_view.ex](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view.ex#L1104-L1116))
2. The page unloads and the WebSocket closes. The LiveView channel process monitors its transport and stops with `{:shutdown, :closed}` when the transport goes down ([channel.ex](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/channel.ex#L107-L116)).
3. The Room gets `:DOWN` for that pid. Under ADR 0001 the person is **Away** while they have no live LiveViews. They stay Away for the whole time on Google's account chooser and consent pages, which depends on the user.
4. Google redirects the browser to `/auth/google/callback` with a GET. The session cookie is sent, because `SameSite=Lax` cookies go with top-level cross-site navigations that use a safe method ([MDN Set-Cookie](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Set-Cookie)). The Phoenix 1.8 endpoint template sets `same_site: "Lax"` ([endpoint template](https://github.com/phoenixframework/phoenix/blob/v1.8.15/installer/templates/phx_web/endpoint.ex.eex)).
5. The callback controller signs the person in (merge, renew session, store token) and redirects to the stored Room path.
6. The Room page does a static render, then connects. The connected mount gets `Map.merge(socket_session, verified_user_session)`, where `socket_session` is read from the cookie **at WebSocket connect time** ([channel.ex](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/channel.ex#L1307-L1343), [transport.ex](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/socket/transport.ex#L515-L527)). The signed `data-phx-session` token holds only the `live_session` `:session` option map, not the cookie ([static.ex](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/static.ex#L47-L51)). So the new mount sees the Account and joins the Room as the Account.

Answer to the ticket's question: the signing-in tab gets a full page reload, not just a reconnect. That follows from OAuth's redirect, not from LiveView.

### Other tabs on the same device

- A second tab in the same Room keeps its WebSocket, and its LiveView still claims the Guest id. Nothing tells it the cookie changed.
- When that socket reconnects, Phoenix loads the session from the cookie and checks the page's `_csrf_token` against it. If the check fails, `connect_info.session` is `nil` ([transport.ex](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/socket/transport.ex#L515-L574)). The LiveView join then replies `"stale"` ([channel.ex](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/channel.ex#L1173-L1247)), and the JS client falls back to a full page request ([view.ts](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/assets/js/phoenix_live_view/view.ts#L1288-L1328)).
- phx.gen.auth's `renew_session` calls `delete_csrf_token()`, so after sign-in every old tab's CSRF token is invalid. Their next reconnect becomes a reload, and the reload mounts as the Account.
- To make that happen at once instead of "whenever the socket next drops", put a `live_socket_id` in Guest sessions too (for example `"guest:<id>"`). The sign-in callback then calls `Endpoint.broadcast("guest:<id>", "disconnect", %{})`. `Phoenix.LiveView.Socket.id/1` reads `live_socket_id` from the cookie session ([socket.ex](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/lib/phoenix_live_view/socket.ex#L103)). The [LiveView security guide](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.12/guides/server/security-model.md) describes the same broadcast for logout: "the client will attempt to reestablish the connection and re-execute the mount/3 callback".
- If the callback kept the CSRF token instead of deleting it, a reconnecting tab would mount as the Account without a reload. That departs from the generator's fixation hygiene (next section).

### Return path

- Store the Room path in the session before redirecting to Google, as phx.gen.auth does with `user_return_to` ([auth template](https://github.com/phoenixframework/phoenix/blob/v1.8.15/priv/templates/phx.gen.auth/auth.ex.eex)). Alternatively, pass it as a query param to the request route and store it there. Read it in the callback **before** `clear_session()`.
- `Phoenix.Controller.redirect(to: ...)` accepts only local paths and raises on unsafe ones. Use `:external` for anything else ([controller.ex](https://github.com/phoenixframework/phoenix/blob/v1.8.15/lib/phoenix/controller.ex#L475-L516)). Still, validate the stored value (for example, that it matches the Room route) rather than trusting a query param.
- The OAuth `state` parameter is separate. Google calls it the way to "prevent CSRF as called out in the OAuth2 Specification" ([web-server guide](https://developers.google.com/identity/protocols/oauth2/web-server)). Both ueberauth and assent generate and check it.

### `configure_session(renew: true)` and session fixation

- OWASP: "The session ID must be renewed or regenerated by the web application after any privilege level change within the associated user session." ([Session Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html#renew-the-session-id-after-any-privilege-level-change))
- Plug: `:renew` "generates a new session id for the cookie" ([conn.ex](https://github.com/elixir-plug/plug/blob/v1.20.3/lib/plug/conn.ex#L1830-L1861)). With the default cookie store there is no server-side session id (`Plug.Session.COOKIE.put/4` ignores the sid), so the protection comes from `clear_session()` and from keeping a revocable server-side token in the session. phx.gen.auth does both.
- Consequence for 36s: a Guest cookie holds no server-side token. Any copy of it stays valid as that Guest for as long as the Guest id is honoured. After a merge, the Guest id is tied to an Account. Whether an old copy of the cookie can still act as that Guest needs a rule (see section 3).

### `live_socket_id` and logout

- phx.gen.auth sets `live_socket_id` per session token. `log_out_user/1` broadcasts `"disconnect"` on it, then renews the session ([auth template](https://github.com/phoenixframework/phoenix/blob/v1.8.15/priv/templates/phx.gen.auth/auth.ex.eex)). Every LiveView on that login reconnects, fails auth or CSRF, and reloads.
- For 36s, logout inside a Room turns the person from the Account back into a Guest on the same Room page. That is the reverse re-key, and it needs a fresh Guest id (section 3).

### How the rejoining LiveView tells the Room to re-key the seat

The LiveView can only present what is in the session (ADR: never URL params). Options, none chosen:

| Option | How | For | Against |
|---|---|---|---|
| A. Carry both ids in the session | The callback copies `guest_id` across `clear_session()` (per the generator's comment) and stores the Account token. The LiveView joins with `person: {:account, a}, was: {:guest, g}`. The Room moves g's seat to a if g is seated | Room logic is local and simple | The session keeps the Guest id after sign-in, so you need a rule for when it stops being honoured |
| B. Room asks the database | The callback records `guest g -> account a` (the merge). The LiveView joins as `{:account, a}`. The Room checks whether any seated Guest now belongs to a | Session holds only the Account | A DB lookup on join, and the Room must know to look |
| C. Callback tells the Room directly | The callback, after the merge, sends `{:rekey, g, a}` to every Room where g is seated (Registry lookup or a `person:g` PubSub topic Rooms subscribe to). The LiveView then joins as a plain Account | Re-key happens even before the LiveView returns, and other tabs of g can be moved in the same step | Needs a person-to-Room index. The callback reaches into Room processes |

Whichever option you pick, the Room also needs rules for:

- **Existing pids for g** (other tabs): move them under a, or let the forced reconnect replace them.
- **Account already seated in the same Room** (for example a on a phone and g on a laptop): two seats for one person. Pick one, or refuse the merge.
- **Nickname:** the Account's saved Nickname versus the one the Guest used in this Room.

### Can the Away blip be avoided?

Only by not navigating the Room tab away:

- **New tab** (`<a target="_blank" href="/auth/google?...">`, no custom JS): the Room tab stays connected as the Guest. The callback runs in the new tab, merges and re-keys (option C), and broadcasts `"disconnect"` on the Guest socket id. The Room tab then reloads (if the CSRF token was deleted) or remounts seamlessly (if it was kept). The new tab ends on the Room or on a "signed in" page.
- **Google Identity Services popup/One Tap:** the ID token comes back to JS on the page. You then need a same-origin `fetch` to a controller to set the cookie, and server-side JWT checks ([verify guide](https://developers.google.com/identity/gsi/web/guides/verify-google-id-token)). This means more JS and a Google script.
- GIS **redirect** mode `POST`s the credential to `login_uri` from Google's page ([HTML reference](https://developers.google.com/identity/gsi/web/reference/html-reference)). That is a cross-site POST, so a `SameSite=Lax` session cookie is **not** sent ([MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Set-Cookie)). The callback would not see the Guest id, and Phoenix's `protect_from_forgery` would have to be skipped for that route. The OAuth code flow uses a GET callback and has neither problem.

## 3. Merging a device's Guest id into an Account

### Patterns in primary sources

- **Firebase** (anonymous auth): sign in anonymously, then `linkWithCredential` to upgrade. "If the call to `link` succeeds, the user's new account can access the anonymous account's Firebase data" ([anonymous auth](https://firebase.google.com/docs/auth/web/anonymous-auth)). "Account linking will fail if the credentials are already linked to another user account. In this situation, you must handle merging the accounts and associated data as appropriate for your app" ([account linking](https://firebase.google.com/docs/auth/web/account-linking)).
- **Supabase** (anonymous sign-ins): convert with `linkIdentity({provider: 'google'})`. If the identity already belongs to another user, sign in to that user and reassign the anonymous user's rows, with "merge, overwrite, or custom logic" for conflicts ([anonymous sign-ins](https://supabase.com/docs/guides/auth/auth-anonymous)).
- **Devise wiki, "How To: Create a guest user"** (Rails): keep `guest_user_id` in the session. A `logging_in` hook moves the guest's records to `current_user`, then destroys the guest ([wiki](https://github.com/heartcombo/devise/wiki/How-To:-Create-a-guest-user)). Of the three, this is closest to 36s: a server-rendered app, a Guest id in the session cookie, and the merge at login.
- **Phoenix**: the phx.gen.auth `renew_session` comment tells you to carry wanted session data across the clear ([auth template](https://github.com/phoenixframework/phoenix/blob/v1.8.15/priv/templates/phx.gen.auth/auth.ex.eex)). The Scopes guide shows a per-session scope id ([scopes.md](https://github.com/phoenixframework/phoenix/blob/v1.8.15/guides/authn_authz/scopes.md)). I found no Phoenix guide that covers guest-to-account merge directly.

All three differ on when the permanent id is created, but they share one shape:

1. Keep the anonymous id until sign-in.
2. At sign-in, if the provider identity is new, create the Account and attach the anonymous records. This is the plain upgrade.
3. If the Account already exists, reassign the anonymous records to it and resolve conflicts in app code.

### Choices this leaves for 36s

- **Where Guest history lives.** Rows keyed by `guest_id` (Game results, Placements) can be reassigned with `UPDATE ... SET account_id = a WHERE guest_id = g` in one transaction inside the callback. Alternatively, a `guests` table with a nullable `account_id` means reads join through it, and "takeover" is one row update.
- **Claimed Guest ids.** After g is merged into a, what happens if the same browser later signs in as b? This happens if the Guest id survived in the session (option A) or a copy of the cookie did. Firebase and Supabase refuse to link an identity twice. The simple rule is "a Guest id merges once".
- **After logout, issue a new Guest id.** Otherwise play after logout on that device is attributed to a Guest id that already belongs to the Account. phx.gen.auth's `renew_session` + `clear_session` already drops the id; the Guest plug then mints a new one.
- **Shared devices.** Takeover moves whatever Guest history is on the device to whoever signs in. On a shared computer, person B signing in claims person A's Guest games. The docs above treat this as app policy. Flag it for the human decision.
- **Identity key.** Google: "you shouldn't use the `email` field in the ID token as a unique identifier for a user. Always use the `sub` field as it is unique to a Google Account even if the user changes their email address" ([Google OIDC](https://developers.google.com/identity/openid-connect/openid-connect)). Keep a unique index on `google_sub`. If you keep email, treat it as display or contact data. phx.gen.auth's schema makes `email` unique and required, so decide whether that stays.

## 4. Google Cloud setup (`openid email profile` only)

### The console as it exists now

OAuth settings live in the **Google Auth Platform** section of the Cloud console. Its pages are Overview, Branding, Audience, Clients, Data Access and Verification Center ([Get started](https://support.google.com/cloud/answer/15544987)). You create a client from the Clients page: "Click **Create Client**. Select the **Web application** application type" and add authorized redirect URIs ([web-server guide](https://developers.google.com/identity/protocols/oauth2/web-server), console: `https://console.developers.google.com/auth/clients`).

### Audience: user type and publishing status

- **External** "available to any user with a Google Account". **Internal** is only for projects in a Google Cloud Organization, and it limits sign-in to that organization ([Manage App Audience](https://support.google.com/cloud/answer/15549945)). Friends outside the team mean External.
- **Testing**: "limited to up to 100 test users ... Authorizations by a test user will expire seven days from the time of consent." Then comes the exception that matters for 36s: "The only exception to this behavior is if your app requests a subset of the following: name, email address, and user profile (through the userinfo.email, userinfo.profile, openid scopes or their OpenID Connect equivalents). For such requests, your users do not need to be in the trusted user list, they will not see a warning message, and their authorizations will not expire after 7 days. If your app uses Sign in with Google to authenticate users then this exception also applies." ([Manage App Audience](https://support.google.com/cloud/answer/15549945))
- The same exception is in the refresh-token docs: a Testing project "is issued a refresh token expiring in 7 days, unless the only OAuth scopes requested are a subset of name, email address, and user profile" ([OAuth 2.0 overview](https://developers.google.com/identity/protocols/oauth2)). 36s needs no refresh token for sign-in anyway.
- **In production**: "available to any user with a Google Account", after pressing **Publish app**. It "may be subject to verification before its name and logo are displayed ... or before it may request authorization of sensitive or restricted scopes" ([Manage App Audience](https://support.google.com/cloud/answer/15549945)).
- The unverified-app user cap (100 users) applies only to apps that show the unverified-app screen, which happens with unapproved sensitive or restricted scopes ([Unverified apps](https://support.google.com/cloud/answer/7454865)). It does not apply here.

### Verification, branding, privacy policy, homepage

- "If your app utilizes only non-sensitive scopes, it is not mandatory for your app to complete the app verification process. However, if you want your app to display an app name and logo on the OAuth consent screen, you will need to complete a lighter-weight verification process known as 'brand-verification'." ([OAuth App Verification Help Center](https://support.google.com/cloud/answer/13463073))
- "Without verification, only your application domain will be visible to users." Brand verification is started from the Branding page, "usually completes in a few minutes", and must be published within 7 days ([Manage OAuth App Branding](https://support.google.com/cloud/answer/15549049)).
- Homepage, privacy policy and terms links: "It is recommended that you provide these links ... Note: These links are required for all external production apps. You will not be able to submit your app for verification if it is missing these links." A homepage must be on a verified domain you own, must describe the app, and "can not be only a login page" ([Manage OAuth App Branding](https://support.google.com/cloud/answer/15549049)). All domains used must be listed as **Authorized domains**.
- Google API Services User Data Policy: "You must publish a privacy policy that fully documents how your application interacts with user data. You must list the privacy policy URL in your OAuth client configuration when your application is made available to the public." It also requires you to "disclose all user data that you access, use, store, delete, or share" ([User Data Policy](https://developers.google.com/terms/api-services-user-data-policy)).
- **Deletion statement:** these pages do not require a self-service account-deletion feature for non-sensitive scopes. The privacy policy must say what you store and delete. This fits the settled "no self-service deletion in the MVP", provided the policy explains how to ask for deletion.
- **Unclear from the docs:** whether the console actually blocks **Publish app** when the links are missing, or whether "required" only bites at verification. I could not test this without a project.

### Google's definition of "production" and separate projects

"An app is considered to be for personal use if it's not shared with anyone else or will be used by fewer than 100 people (all of whom are known personally to you)" and is then not "production". "Some policies and requirements only apply to production apps. For this reason, you must create separate projects in the Google Cloud Console for each deployment tier, such as development, staging, and production." ([OAuth 2.0 Policies](https://developers.google.com/identity/protocols/oauth2/policies)) A team-and-friends 36s may fall under "personal use". Separate dev and prod projects are still required.

### Redirect URIs

Rules from the [web-server guide](https://developers.google.com/identity/protocols/oauth2/web-server):

- HTTPS only, except localhost ("Localhost URIs (including localhost IP address URIs) are exempt").
- No raw IPs except localhost, and no wildcards.
- No fragments, no userinfo, no path traversal, no open redirects.
- `redirect_uri_mismatch` if "the `http` or `https` scheme, case, and trailing slash" differ.

So:

- Dev project: `http://localhost:4000/auth/google/callback`.
- Prod project: `https://<host>/auth/google/callback`.

ueberauth builds the callback URL from the request unless `callback_url` is set ([ueberauth_google README](https://github.com/ueberauth/ueberauth_google/blob/master/README.md)). Behind a TLS-terminating proxy, the built URL can come out as `http://...` and fail to match. assent takes an explicit `redirect_uri`.

### Other Google facts worth knowing

- **Client secrets** are shown in full only once, at creation. After that the console shows the last four characters. A client can have at most two secrets, for rotation. Clients unused for six months are deleted automatically, with an email 30 days before ([Manage OAuth Clients](https://support.google.com/cloud/answer/15549257)).
- **Embedded webviews are blocked**: "A developer must not direct a Google OAuth 2.0 authorization request to an embedded user-agent" ([Policies](https://developers.google.com/identity/protocols/oauth2/policies)). Google notes that another app's choice to open your links in a webview (for example a messaging app) can break your sign-in, and the user sees `disallowed_useragent` ([Google Developers Blog, 2021](https://developers.googleblog.com/en/upcoming-security-changes-to-googles-oauth-20-authorization-endpoint-in-embedded-webviews/)). Room links shared in chat apps may open in such a browser. Guests can still play, but sign-in fails there.
- **Scope string**: "The scope parameter must begin with the `openid` value and then include the `profile` value, the `email` value, or both." Use `sub`; check `email_verified` if email is used; `hd` is present only for Workspace users ([Google OIDC](https://developers.google.com/identity/openid-connect/openid-connect)).

## 5. Secrets

- Phoenix: "The general recommendation is to keep those in environment variables and load them into your application. This is done in `config/runtime.exs` ... which is responsible for loading secrets and configuration from environment variables at boot time." ([Deployment guide](https://github.com/phoenixframework/phoenix/blob/v1.8.15/guides/deployment/deployment.md)) The releases guide adds that "secrets like database credentials and API keys should not be compiled into the image" and that env vars should be read in `runtime.exs`, "not scattered throughout your code" ([Releases guide](https://github.com/phoenixframework/phoenix/blob/v1.8.15/guides/deployment/releases.md)). The generated `runtime.exs` raises if `SECRET_KEY_BASE` is missing in prod ([runtime.exs template](https://github.com/phoenixframework/phoenix/blob/v1.8.15/installer/templates/phx_single/config/runtime.exs.eex)). `System.fetch_env!/1` gives the same fail-fast for the Google vars.
- Google: "You must never commit client credentials into publicly available code repositories" ([Policies](https://developers.google.com/identity/protocols/oauth2/policies)).
- **ueberauth caveat.** `Ueberauth.Strategy.Google.OAuth.client/1` reads `client_id` and `client_secret` with `Application.get_env` at request time ([oauth.ex](https://github.com/ueberauth/ueberauth_google/blob/master/lib/ueberauth/strategy/google/oauth.ex)), so setting them in `runtime.exs` works. But `plug Ueberauth` builds its provider routes in `init/1` ([ueberauth.ex](https://github.com/ueberauth/ueberauth/blob/master/lib/ueberauth.ex)), and controller plugs are initialised at compile time. Provider options under `providers:` (scope, `callback_url`) belong in compile-time config. Putting them in `runtime.exs` may not take effect in a release. This is an inference from the source; verify it when building.
- **assent** takes config as a keyword list at each call, so reading `Application.fetch_env!` at call time avoids the question.
- Dev: a local `.env` loaded by the shell, or `config/dev.exs` reading env vars. Keep the dev and prod clients in separate Cloud projects (section 4).

---

## Pitfalls

1. **The signing-in tab is Away during the Google round trip.** This is unavoidable with a same-tab redirect. See section 2 for the new-tab option.
2. **Other tabs keep the Guest identity** until their socket reconnects. Use a Guest `live_socket_id` + `"disconnect"` broadcast, and re-key all of the Guest's pids in the Room.
3. **`clear_session()` wipes the Guest id and `return_to`.** Read both first. Decide explicitly whether the Guest id survives sign-in.
4. **An Account that is already seated in the same Room** gives two seats for one person. Needs a rule.
5. **A Guest id should merge once**, and logout should mint a new Guest id.
6. **Shared devices** hand Guest history to whoever signs in.
7. **Use `sub`, not email**, as the Google key.
8. **Embedded in-app browsers** get `disallowed_useragent`.
9. **Callback URL behind a proxy** must match exactly (scheme, trailing slash).
10. **GIS redirect mode POSTs cross-site**, so the Lax session cookie is not sent. Prefer the code flow with a GET callback.
11. **ueberauth_google does not validate an ID token**, and the request phase accepts `scope`/`prompt` from query params. The userinfo call over TLS with a fresh access token is a common pattern, but it is weaker than full OIDC.
12. **Client secret is shown only once** in the console. Save it at creation.
13. **Unused OAuth clients are deleted after 6 months.** This matters for a dev client left idle.

## Options at a glance

| | ueberauth + ueberauth_google | assent (Google OIDC) | oidcc + oidcc_plug | Hand-rolled on `oauth2`/`Req` |
|---|---|---|---|---|
| Latest release | 0.10.8 / 0.12.1 (2024 / 2023) | 0.3.1 (2025-06), unreleased work on main | 3.9.0 / 0.5.1 (2026) | n/a |
| Shape | Controller plug + callback | Two functions; you store `session_params` | Supervised config worker + plugs | Your own |
| ID token validated | No (userinfo endpoint) | Yes, plus nonce/PKCE | Yes (certified RP) | Only if you build it |
| Fit with phx.gen.auth | Callback calls `log_in_user` | Same | Same | Same |
| Config / secrets | client id/secret at runtime; provider options compile-time | Per call | Worker config at boot | Per call |
| Weight for one provider | Light | Light | Heaviest | Lightest code, most risk |

On session code: use phx.gen.auth's token/scope/`on_mount`/disconnect pieces with the email parts removed, or write the same by hand.

**What the facts favour for 36s (input to a human decision, not a decision):** assent's Google strategy fits best. It is small, validates the ID token, has more recent releases than ueberauth_google, and takes config per call, which suits `runtime.exs`. Pair it with the session-token, scope and `on_mount` parts of `phx.gen.auth` (email parts deleted), with the Scope extended to carry the Guest id. ueberauth is the close second if its wider tutorial base matters more than its release gap. On Google's side, the facts favour an External app with only `openid email profile`. That works in Testing with no user list and no 7-day expiry, and brand verification plus homepage and privacy policy links come in when publishing. For the mid-Room switch, the same-tab redirect is the simplest, but it makes the seat Away during the round trip. The new-tab variant avoids that with no custom JS, at the cost of a Room-side re-key triggered by the callback.
