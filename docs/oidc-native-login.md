# OIDC login in the app — two upstream PRs

Goal: a user whose bambuddy server signs in through OIDC (Authelia, PocketID, …)
can sign in to the app the same way, and stays signed in without the app
storing a password.

Server reference: `reference/bambuddy` at `d2ea32ef6` (2026-10-06). All paths
below are relative to `backend/app/`.

CONTRIBUTING.md:28-35 — **no assigned issue = no PR**. Each PR below starts as
its own issue, waits for maziggy's agreement and assignment, and ships with a
companion `bambuddy-wiki` PR.

## Where the server is today

- `GET /auth/oidc/authorize/{id}` (`api/routes/mfa.py:1683`) stores
  `state` + `nonce` + server-side PKCE verifier in an `AuthEphemeralToken`
  (`OIDC_STATE`, 10 min) and returns `auth_url`.
- `GET /auth/oidc/callback` (`mfa.py:1766`) consumes the state atomically
  (`DELETE … RETURNING`), exchanges the code with the IdP, resolves the user,
  stores a 2-minute single-use `OIDC_EXCHANGE` token and redirects to the
  **hardcoded** `{external_url}/login#oidc_token=…` (`mfa.py:2158`). Errors go
  to `{external_url}/?oidc_error=<code>`.
- `POST /auth/oidc/exchange` (`mfa.py:2179`) consumes the exchange token and
  answers `LoginResponse` — the same shape as `/auth/login`, including
  `requires_2fa` + `pre_auth_token` + the `2fa_challenge` cookie.
- No refresh token for the SPA/app session. Two neighbours to cite as
  precedent: `LongLivedToken` (`models/long_lived_token.py` — per-user,
  hashed, revocable, 365-day cap, camera scope only) and **connected apps**
  (`api/routes/connected_apps.py`) — an existing PKCE auth-code flow with an
  exact-match redirect and a **consent screen** in the SPA
  (`/connect/authorize`). It is not usable by the app as is: `/connect/token`
  needs a client secret (a public client cannot keep one) and returns the
  user's identity, never a Bambuddy token — by design (module docstring).
- JWT lifetime = `session_max_hours` (default 24 h,
  clamp 1–720 h, `core/auth.py:727`). Revocation is per-`jti`
  (`revoked_jti` rows) plus the per-user epoch `password_changed_at`: a JWT
  whose `iat` predates it is refused (`core/auth.py:1184`). The epoch is bumped
  by change-password (`routes/users.py:598`), forgot-password confirm
  (`routes/auth.py:1245`) and admin 2FA reset (`mfa.py:1311`) — **not** by an
  admin setting a password through `PATCH /users/{id}` (`users.py:320-326`),
  deactivation (`users.py:336-337`) or role/group changes. It is `NULL` for
  every user created after the back-fill (`POST /users` `users.py:160-166`,
  OIDC auto-create, LDAP provisioning), and `NULL` means "fresh".
- SQLite runs without `PRAGMA foreign_keys` (`core/database.py:15-23`), so
  `ON DELETE CASCADE` never fires; `delete_user` removes dependants by hand
  (`users.py:498-537`) because `users.id` has no AUTOINCREMENT and the next
  user inherits the highest freed id.

Two gaps follow: the callback cannot return to an app, and an OIDC user (no
password) cannot be silently re-logged in by the app the way local users are
today (`AuthService.silentReLogin`).

---

## PR 1 — OIDC for native clients (redirect + client PKCE)

Size: ~0.5–1 day with tests. Independent of PR 2: with
`session_max_hours=720` the app is usable on PR 1 alone (re-SSO monthly).

### API change (all additive, web flow byte-for-byte unchanged)

`GET /auth/oidc/authorize/{id}` gains three optional query params:

| param | rule |
|---|---|
| `client_redirect` | must **exactly** equal one entry of a module constant `NATIVE_CLIENT_REDIRECTS = frozenset({"bambuddy://oidc"})`; anything else → 400. No prefix/pattern matching, no admin-editable list. |
| `code_challenge` | required when `client_redirect` is set (400 otherwise); `^[A-Za-z0-9_-]{43}$` (S256 output). |
| `code_challenge_method` | must be `S256` when present; `plain` refused. |

`OIDCAuthorizeResponse` gains `client_redirect: str | None` echoing the accepted
value. It is the app's feature probe: an older server ignores unknown query
params and answers without the field, so the app must not open the browser
(the flow would end on the web `/login` and strand the user in the tab).

### Storage

Two nullable columns on `auth_ephemeral_tokens` (`models/auth_ephemeral.py`),
added through `run_migrations` (`core/database.py:1842`) with `ALTER TABLE …
ADD COLUMN` the way existing columns are:

- `client_redirect String(64)`
- `client_code_challenge String(64)`

Set on the `OIDC_STATE` row at authorize; returned by the callback's
`DELETE … RETURNING`; carried on the `OIDC_CONSENT` row (see Callback);
copied onto the `OIDC_EXCHANGE` row on Continue. New `TokenType` member:
`OIDC_CONSENT = "oidc_consent"`.

### Callback

- Success with a native state: **do not redirect to the scheme directly.**
  Render a server-origin consent interstitial — "Sign in to the Bambuddy
  mobile app as `<username>`? [Continue] [Cancel]" — and only the Continue
  button navigates to `{client_redirect}#oidc_token=<token>` (fragment, same
  reason as H-4). Without it any app on the phone can start its own native
  flow (authorize is unauthenticated), ride the browser's silent IdP session
  and receive a valid token for its own verifier — RFC 8252 §8.6 client
  impersonation, which PKCE does not cover. Precedent: the connected-apps
  consent screen. Cancel → `{client_redirect}#oidc_error=cancelled`.
  The exchange token is minted only on Continue, so a page left open does not
  hold a live credential. Between the two the callback stores a new
  `AuthEphemeralToken` of type `OIDC_CONSENT` (2 min TTL) carrying
  `username`, `client_redirect` and `client_code_challenge`; its random token
  is the hidden field of the Continue/Cancel form, and `POST
  /auth/oidc/consent {consent_token, action: "continue" | "cancel"}` consumes
  it atomically (`DELETE … RETURNING`) in both cases. `continue` mints
  `OIDC_EXCHANGE` with the challenge copied over; `cancel` mints nothing and
  redirects to `{client_redirect}#oidc_error=cancelled`. The interstitial
  sends `X-Frame-Options: DENY` / `frame-ancestors 'none'` (no clickjacking
  of Continue) and `Cache-Control: no-store`.
- User auto-create, auto-link and group sync keep happening in the callback,
  before consent. Deliberate: they act on the victim's own IdP identity with
  the IdP's own claims and happen identically on the victim's next web
  sign-in. Open question for maziggy: an unsolicited flow through a *second*
  provider with auto-link can create a link the user never asked for, and the
  callback refuses auto-link once any link exists (`mfa.py:1985-1999`).
  Deferring link/create/sync to Continue for native flows fixes that, at the
  cost of splitting the callback.
- Errors **after** the state row was consumed: redirect to
  `{client_redirect}#oidc_error=<code>` so the app can close the tab and show
  the error. Errors before (missing params, invalid/expired state) have no
  trusted client to return to and keep going to the web error URL.
- The IdP `error` branch (`mfa.py:1778-1780`) returns **before** the state is
  consumed today. It must consume the state when one is present, or a user
  who presses Cancel at Authelia is stranded on the web error page inside the
  Custom Tab.
- The redirect URL itself is never taken from the request at callback time —
  only from the state row, which only the allowlist could have written.

### Exchange

- `OIDCExchangeRequest` gains `code_verifier: str | None`
  (`^[A-Za-z0-9._~-]{43,128}$`, RFC 7636 §4.1).
- Add `client_code_challenge` to the `RETURNING` of the existing atomic
  consume. If it is set: verifier required, compare
  `base64url(sha256(verifier))` with `hmac.compare_digest`; missing or wrong →
  401 `"Invalid or expired OIDC exchange token"` (same message as an unknown
  token, no oracle). The token is already deleted, so a wrong verifier burns
  it — one attempt only.
- If the row has no challenge (web flow) and a verifier **is** supplied →
  the same 401. Rule: `(row.client_code_challenge is None) != (body.code_verifier
  is None)` → 401, checked right after the consume, so the token is burned.
  Ignoring a stray verifier would be the PKCE downgrade of RFC 9700 §4.8: an
  attacker mints a web-flow token for their own account (it is in the
  `Location` of their own callback, `mfa.py:2158`), pushes
  `bambuddy://oidc#oidc_token=<it>` into the victim's app while a flow is
  pending (explicit VIEW intent from a malicious app, or a link), the app
  sends its own verifier, the server ignores it, and the victim works inside
  the attacker's account — a Bambu Cloud sign-in made there lands on the
  attacker's user row (`api/routes/cloud.py:194-203`). The SPA never sends a
  verifier, so the web flow is unaffected.

### What it defends against

- **Open redirect / token theft via crafted link** — exact-match allowlist; the
  callback only reads the redirect from the consumed state row.
- **Custom-scheme hijack of the real app's flow** (another Android app
  registering `bambuddy://`, receiving the fragment) — the stolen
  `oidc_token` is useless without the verifier, which never leaves the app
  that started the flow (RFC 8252 §8.1).
- **A malicious app starting its own flow** (§8.6) — PKCE does nothing here;
  the consent interstitial is the defence: the user sees a sign-in they did
  not ask for. Residual risk (user clicks Continue anyway) goes in the wiki:
  native SSO trusts the app that owns `bambuddy://` on that phone.
- **Login CSRF / session injection** (attacker's token pushed into the
  victim's app) — every token the app can redeem is bound to a challenge,
  and the victim's verifier matches only the victim's own flow: an attacker's
  native token fails the comparison, an attacker's web token fails the
  "verifier supplied, no challenge" rule. The app-side "flow pending" check
  only narrows the timing; it cannot tell tokens apart, since the fragment
  carries nothing else.
- Unchanged: IdP-side PKCE, nonce, state single-use, 2 min exchange TTL.

### Tests (`backend/tests/integration/test_advanced_auth_api.py` style)

1. Authorize with no new params → response identical to today, no
   `client_redirect` in the row.
2. `client_redirect` not in allowlist (incl. `bambuddy://oidc/x`,
   `bambuddy://oidc?x`, `BAMBUDDY://oidc`, `https://evil`) → 400.
3. `client_redirect` without `code_challenge` → 400; `plain` method → 400;
   malformed challenge → 400.
4. Callback success with native state → 200 interstitial, no exchange token
   in the DB yet; Continue → 302 to `bambuddy://oidc#oidc_token=…`; Cancel →
   `#oidc_error=cancelled` with no exchange row created; the consent token is
   single-use in both directions (Cancel then Continue with it → 400).
5. Callback IdP error (`error=access_denied` + valid native state) → 302 to
   `bambuddy://oidc#oidc_error=…` and the state is consumed; invalid state →
   web error URL.
6. Exchange: right verifier → `LoginResponse`; wrong / missing verifier → 401
   **and** a retry with the right verifier → 401 (token burned).
7. Exchange of a web-flow token **with** a verifier → 401, and the token is
   burned (a retry without the verifier → 401). Web-flow token without a
   verifier → works as today.
8. 2FA user via native flow → `requires_2fa` + `pre_auth_token`, then
   `/2fa/verify` completes.

### Docs (bambuddy-wiki)

OIDC page: "Mobile app sign-in" — nothing to configure at the IdP (its
`redirect_uri` stays the server callback); `external_url` must be the address
the phone's browser reaches the server on.

### App side (this repo, after PR 1 merges)

- Public `GET /auth/oidc/providers` → SSO buttons on the login screen.
- Tap → generate `state`-independent `code_verifier` (32 random bytes,
  base64url) → `GET /oidc/authorize/{id}?client_redirect=bambuddy://oidc&code_challenge=…`.
  No `client_redirect` echo → show "server too old for app SSO", stop.
- Open `auth_url` with `url_launcher` `LaunchMode.inAppBrowserView` (Custom
  Tab; dependency already present).
- **New web-reachable entry point** → AGENTS.md security gate, needs an
  explicit yes. `MainActivity` is already exported
  (`AndroidManifest.xml:64-67`), so any installed app can send it a VIEW
  intent today, and Flutter hands the URI's path to GoRouter. A BROWSABLE
  filter on it would extend that to every web page (`bambuddy://oidc/<any
  route>`). Plan: a small dedicated callback activity (not a
  `FlutterActivity`) holding the `bambuddy://oidc` filter, which passes only
  the fragment to the running `MainActivity` and finishes — routes stay off
  the web, and no second Flutter instance without the in-memory verifier is
  started.
- Accept the callback only while a flow is pending (verifier in memory,
  started < 10 min ago); otherwise ignore it. Clear the verifier after one use.
- `POST /oidc/exchange {oidc_token, code_verifier}` → existing
  `LoginResponse` handling, including the 2FA screen.
- Log: control tags per logging-guide; never log `oidc_token`, verifier or the
  fragment.

---

## PR 2 — refresh tokens (opt-in per login)

Size: ~2–3 days with tests. Only clients that ask get one; the web never asks,
so the browser session model does not change.

### API

- `LoginRequest`, `OIDCExchangeRequest`, `TwoFAVerifyRequest` gain
  `want_refresh: bool = False`. The token is issued only by the call that
  issues the access token (so a 2FA user gets it from `/2fa/verify`, not from
  the first step).
- The family's `auth_method` must survive the 2FA step: `/2fa/verify` only
  gets a username back (`mfa.py:1150-1158`). Add a nullable `auth_method`
  column to the PRE_AUTH row and reuse its `provider_id` for OIDC: set at
  `/auth/login` (`'ldap' if ldap_user else 'local'`, `api/routes/auth.py:606`)
  and `/oidc/exchange` (`'oidc'` + provider, `mfa.py:2235`), copied when
  `/2fa/email/send` re-issues the row (`mfa.py:1127`), returned by
  `consume_pre_auth_token`. Not `user.auth_source`: auto-link leaves a linked
  local account `'local'` (`mfa.py:2000-2009`).
- `LoginResponse` **and `TwoFAVerifyResponse`** (`schemas/auth.py:287` — a
  separate model, `access_token` + `user` only) gain
  `refresh_token: str | None = None`.
- `POST /auth/refresh {refresh_token}` → `{access_token, refresh_token}`
  (rotated). Unauthenticated route; the token is the credential.
- `POST /auth/logout` accepts an optional `{refresh_token}` body → revoke its
  family.

### Storage — new table `refresh_tokens`

| column | note |
|---|---|
| `id` | PK |
| `user_id` | FK `users.id` — **plus** an explicit delete in `delete_user` (`users.py:498-537`); the cascade does not fire on SQLite |
| `username` | copied at login; refresh refuses when it no longer matches the row behind `user_id` (id reuse) |
| `auth_method` | `local` / `ldap` / `oidc` — what the family was obtained with |
| `provider_id` | OIDC families only |
| `jti` | of the JWT minted with this row, so revoking the family can also revoke the JWTs it already handed out |
| `family_id` | random hex, one per login |
| `token_hash` | `sha256(token)` hex, unique, indexed — 256-bit random token, so no slow hash needed |
| `family_created_at` | login time, copied to every rotation |
| `created_at` | naive UTC, like `users.created_at` (`models/user.py:35`) — or every comparison happens in SQL; mixing aware and naive raises on PostgreSQL |
| `used_at` | set when rotated; non-null = spent |
| `successor_id` | the row that replaced this one; `NULL` while unspent |
| `revoked_at` | |

### `/auth/refresh` checks, in order

Everything that can end the family is checked **before** the spent/reuse
logic, so a grace hit can never mint for a dead family or user.

1. Look up by hash. Unknown → 401.
2. Family revoked → 401.
3. `now > family_created_at + cap` → 401, where cap is `refresh_max_days`, or
   `refresh_external_max_days` for `auth_method in (ldap, oidc)`.
4. `now - MAX(created_at) over the family > refresh_idle_days` → 401. Idle is
   a property of the family (its newest row = its last rotation), not of the
   presented row: a spent token shown late must still reach step 8 and
   revoke a family a thief keeps alive.
5. User missing, `is_active = false`, `user.username != family.username` or
   `user.created_at > family_created_at` → 401 (deleted user whose id was
   handed to someone else).
6. `password_changed_at` set and `family_created_at < password_changed_at`
   (seconds-truncated, as `_is_token_fresh`) → 401. `NULL` = no epoch.
7. `auth_method = local` and local login is now disabled
   (`local_login_enabled` setting, `api/routes/auth.py:531-547`, env bypass
   `BAMBUDDY_LOCAL_LOGIN` honoured) → 401.
7b. `auth_method = oidc`: the provider must still exist and be enabled, and a
   `UserOIDCLink` for this user and provider must still exist; `auth_method =
   ldap`: `_get_ldap_settings(db)` must not be `None` → otherwise 401. Covers
   provider disable, provider delete (whose links go by ORM cascade,
   `models/oidc_provider.py:160-163` — a hook in the unlink route would never
   see it) and LDAP switched off, with no hook at any of those sites.
8. Spent (`used_at` set):
   - within `REFRESH_REUSE_GRACE` (30 s) of `used_at`, and its successor
     (`successor_id`) is still unspent → **replace** it: mark the successor
     spent (`used_at=now`, no successor of its own), insert a new successor,
     point `successor_id` at it, return it (200). Invariant: a family has
     **exactly one** unspent token at any time — no fork, no amplification.
     Covers a lost 200 (client retries with the old token). If the old token
     was stolen and replayed inside the window, the legitimate holder's
     successor is now spent, so its next use after the window revokes the
     family — detection survives, it is only delayed. (Replaying the original
     successor would need its plaintext, which is never stored.)
   - within the window but the successor is already spent, **or has no
     successor** (a row replaced by an earlier grace hit) → treat as "later".
   - later → revoke the whole family **and the `jti` of each of its rows**
     (existing `revoke_jti`, `core/auth.py:1207`), log a warning (theft
     signal), 401. Without the jtis the thief keeps the JWT already minted,
     up to `session_max_hours`.
9. Unspent, in one transaction: insert the successor first, then
   `UPDATE … SET used_at=now, successor_id=:new WHERE id=? AND used_at IS
   NULL`; rowcount 0 → roll back, re-select the row and go to step 8. A row
   spent by rotation therefore always has its `successor_id` — no window
   where another worker sees `used_at` set and `successor_id` empty (only a
   row replaced in step 8 has none, and step 8 treats that as "later"). Mint
   a JWT with `exp = min(now + session_max, family_created_at + cap)` — so a
   refresh on the last day of a family cannot stretch access by another
   `session_max_hours` (up to 720 h) — store its `jti` on the new row,
   commit. Step 8's
   replacement uses the same conditional `UPDATE … WHERE used_at IS NULL` on
   the successor, so two grace hits cannot both replace it.

### Revocation hooks PR 2 must add (not optional)

- `PATCH /users/{id}` with `password` → bump `password_changed_at`
  (`users.py:326`). Today an admin resetting a compromised account leaves the
  attacker's JWT alive ≤24 h; with refresh tokens it would be ≤90 days.
- `PATCH /users/{id}` with `is_active=false` → bump it too. Deactivation
  already refuses the JWT (`core/auth.py:1482-1483`, `1520-1524`) and step 5
  refuses refresh; the bump is what stops a later re-activation from bringing
  old JWTs and families back.
- `delete_user` → delete the user's refresh rows explicitly.
- OIDC unlink, provider disable/delete, LDAP off → no hook; step 7b checks
  them at refresh time.

Settings (admin, next to `session_max_hours`): `refresh_idle_days` (default
30, clamp 1–90), `refresh_max_days` (default 90, clamp 1–365), `refresh_external_max_days`
(default 7, clamp 1–30). Prune rows past
the absolute cap opportunistically on login, as the ephemeral tables do.

### Open questions for maziggy

- Default on or behind an admin switch? (Plan: on, since it is opt-in per
  client and bounded by both caps.)
- Re-check the IdP on refresh (keep the IdP refresh token, call it each time)
  vs local-only checks? Plan: local-only — no new secret stored, refresh does
  not depend on the IdP being up; an IdP-side block takes effect at the
  absolute cap or when an admin deactivates the user in bambuddy.
- LDAP and OIDC families are never re-checked against the directory/IdP.
  Plan: for `auth_method in (ldap, oidc)` cap the family at
  `refresh_external_max_days` (default 7) instead of `refresh_max_days`, so
  a block made only in the directory/IdP takes effect within
  `refresh_external_max_days` (the JWT `exp` is capped at the family end, step
  9). Disabling the provider or LDAP in bambuddy takes effect at the next
  refresh (step 7b). Alternative: re-validate
  against the IdP (stores its refresh token) — see the previous question.

### Tests

1. Login without `want_refresh` → no token (web unchanged); with → token.
2. 2FA login: first step has no token, `/2fa/verify` with `want_refresh` has.
3. OIDC exchange with `want_refresh` → token.
4. Refresh rotates; old token within 30 s → 200 with a replacement, the
   first successor is now spent; after 30 s → 401 and the family is revoked.
4a. Spent token within 30 s for a deactivated user / expired family → 401,
   no token minted (order of checks).
5. Idle cap, absolute cap, inactive user.
5a. Delete user M, create user V who gets M's id → M's refresh token 401
   (explicit delete, and the username/created_at guard on its own).
6. Password change / forgot-password confirm / admin 2FA reset / **admin
   `PATCH` password** / **deactivation** → refresh 401.
6a. `local_login_enabled=false` → `local` family 401, `oidc` family still
   works; with `BAMBUDDY_LOCAL_LOGIN=true` the `local` family works.
6b. LDAP/OIDC family past `refresh_external_max_days` → 401; a JWT minted
   on its last day expires at the family end, not `session_max_hours` later.
6c. LDAP+TOTP login → `ldap` family; OIDC+TOTP login of an auto-linked
   local admin while local login is off → `oidc` family, refresh works.
6d. Provider disabled / provider deleted / link removed / LDAP disabled →
   refresh of the matching family 401.
6e. Spent token presented after `refresh_idle_days` while a thief kept the
   family rotating → family revoked (idle measured on the family).
7. Logout with refresh body → family dead; logout without → family alive.
8. Two concurrent refreshes with the same token → both 200, and afterwards
   the family has exactly one unspent row (the second response's token);
   the first response's token is spent.
8a. Replay a spent token 50× inside the window → still exactly one unspent
   row in the family.
8b. Stolen-old-token replay inside the window → the legitimate successor's
   next use after the window → 401, the whole family is revoked, and the JWT
   the thief got from the replay is refused (jti revoked).

### App side (this repo, after PR 2 merges)

- Ask `want_refresh` only behind the Remember-me opt-in (off by default,
  `lib/features/setup/setup_screen.dart:33`, `auth_service.dart:119-130`), for
  every login path (decided 2026-10-10): password, SSO (the checkbox also
  governs the SSO buttons, `/oidc/exchange`) and 2FA (`/2fa/verify`).
  Unchecked, the session ends with its JWT.
  2FA logins are not remembered today only because a saved password cannot
  renew a 2FA session (`auth_service.dart:221-224`); a refresh token can,
  since its family is created after the code was verified. The cost is a
  "trust this device" window without a 2FA prompt, bounded by the family
  caps and cut by an admin 2FA reset (`mfa.py:1311` bumps the epoch, step 6).
  Rewrite that doc comment on `verifyTwoFactor` when PR 2 lands. Store
  `refresh_token` in `flutter_secure_storage`.
- `ProactiveTokenRefresher.refresh` → `/auth/refresh`. A transport error
  keeps the old token and retries (the server's grace answers it).
- Serialize refresh across every `AuthService` instance — today there are
  four, each calling `silentReLogin` on its own, which is harmless with a
  password and is exactly the race rotation punishes:
  UI (`lib/providers.dart:379`, `lib/features/dashboard/ws_providers.dart:67`,
  `lib/core/auth/token_refresher.dart:165`), foreground service
  (`lib/core/notifications/print_monitor_task_handler.dart:229`, `294`),
  notification-callback isolate (`lib/core/notifications/background_api.dart:218`),
  wear relay engine (`lib/core/watch/wear_relay_engine.dart:44`). The watch's
  own logins come on top and need a family of their own. Grace window is the
  backstop, not the plan — outside 30 s a race still revokes the family.
- **Migration of existing installs** (AGENTS.md compatibility gate): on a
  server that answers `refresh_token`, the next `silentReLogin` with the saved
  password asks `want_refresh`, stores the token, and deletes the saved
  password — **on the watch too**: the phone pushes the saved password there
  (`lib/core/watch/watch_config_sync.dart:129-131`) and `apply()` never
  clears it (`147-152`). Older server → today's behaviour untouched. Needs an explicit yes
  before implementing.
