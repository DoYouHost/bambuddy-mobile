# Why `lib/providers.dart` is shaped the way it is

The providers that carry a decision, and the reasons behind it. The code keeps
one line per provider; the reasoning is here. Capability gates have their own
document: [server-gates.md](server-gates.md).

## Identity and permissions

`currentUserProvider` answers "who is signed in, and what may they do". `null`
means *nobody known*: no profile yet, a server with auth switched off, or a
`/auth/me` that did not answer. Login hands its own `user` over through
`CurrentUserNotifier.adopt` **before** saving the profile, so signing in costs
no extra request, and `build` consumes it once. A session restored at start-up
(profile loaded from settings, no login) is what the `GET /auth/me` is for. A
no-auth server answers 401 there (`auth.py::get_current_user_info`): there is no
identity behind an anonymous session and nothing it could be restricted from;
the demo backend does serve `/auth/me`, so it stays included.

Three gates read it, and they disagree on purpose:

| Provider | Unknown identity | API-key session |
|---|---|---|
| `permissionProvider(p)` | **`true`** | whatever `/auth/me` says |
| `identifiedPermissionProvider(p)` | `false` | **`false`** |
| `canUpdatePrintersProvider` | `true` | **`false`** |

- **`permissionProvider` answers `true` whenever the identity is unknown** (no
  profile, still loading, auth off server-side, a failed `/auth/me`, a response
  without `permissions`). The server is the only enforcer, so a permissive
  unknown leaves a screen reachable rather than hiding one the user is entitled
  to. An empty `permissions` list is *not* unknown: that is a user whose groups
  grant nothing, and they are refused. A screen that would rather not flash an
  entry and take it away watches `currentUserProvider` and handles `loading`
  itself. `isAdminProvider` follows the same rule.
- **`identifiedPermissionProvider` is the gate for anything administrative**: the
  opposite on an unknown identity (nothing administrative is offered when nobody
  can say who is signed in). An API-key session is refused outright,
  `CurrentUser.isAdmin` or not: the server denies a key every administrative
  permission (`_check_apikey_permissions`, `core/auth.py`), and what `/auth/me`
  says about a key never described that gate. Hence the decision on the auth mode
  rather than on the payload.
- **`canUpdatePrintersProvider`**: `printers:update` is outside the key scope
  allowlist, so an API-key session never may change a printer; decided on the
  auth mode like the one above. Unlike it, an unknown identity answers yes: the
  server is the enforcer, and a server without auth has nobody to refuse.

## The client and the teardown frame

`apiClientProvider` throws without a profile, by design: routes without a profile
redirect to `/setup`, so the UI never touches it when null. The exception is the
transient frame between "change server" clearing the profile and the router
redirecting: the non-`autoDispose` repositories watching it are still mounted
under the drawer and would rebuild into that throw. `_lastApiClient` is the
most recently built client for exactly that frame. It is never used for a
request (its consumers are guarded or about to unmount) and is replaced with the
next profile. In debug it prints when it is reused, because anywhere but the
teardown frame that means a consumer reads the client without a null-profile
guard and would hit the previous server.

## Token refreshers

Proactive, so REST and the WebSocket handshake do not hit a 401 we would only
retry reactively. None of them runs itself: the UI keeps them alive and drives
them per lifecycle, and the service isolate takes over in the background.

- `tokenRefresherProvider`: silent re-login just before expiry. `null` for the
  other two auth modes (an API key is static, a no-auth server has nothing to
  expire).
- `cameraTokenRefresherProvider`: re-mints the camera stream token before its
  client TTL lapses, so the live view does not hit a 401 first; the reactive
  re-mint on 401 stays the safety net. Demo has no token to refresh.
- `mediaAuthRefresherProvider`: the same for the media credential behind
  thumbnails, covers, photos and timelapses, so a scrolled list does not flash a
  page of broken tiles while the reactive recovery re-mints. UI-only: the FGS
  isolate's cover fetch re-mints reactively. A no-op while the credential is a
  header, which does not expire (`MediaAuthService.expiresAt` is null there and
  the refresher just ticks on its fallback delay).

## Versions

- **`serverVersionProvider`** is for a synchronous reader. Warmed by the shell at
  start and asked again on every regained contact: a read that failed while the
  network was down would otherwise wait out the service's retry window. Re-running
  costs nothing once known (`ServerVersionService` caches it) and keeps the
  previous value up meanwhile, so nothing blinks. `null` is "the server did not
  say".
- **`appVersionProvider`** is a provider rather than a future held in each
  widget's `State`, which is how three screens did it: `PackageInfo.fromPlatform`
  hands back a fresh future on every call, so a `FutureBuilder` given one
  re-enters `waiting` and flashes its placeholder, and a `State` only avoids that
  for as long as the widget lives, which for the drawer footer is one opening.
  Cached in the container, the answer is there synchronously from the second read
  on.
- **`serverVersionLabelProvider`** (drawer footer): `null` is "nobody knows" (too
  old to serve `/updates/version`, unreachable, or a reply the parser made nothing
  of), and with no profile it answers `null` rather than letting
  `apiClientProvider` throw. It is `autoDispose` **with a link kept on success**
  because the two halves answer two different failures. Kept unconditionally, a
  drawer opened once in a lift reads "unknown" until the app is killed; disposed
  unconditionally, every reopening starts at `AsyncLoading`, the flash
  `appVersionProvider` exists to avoid. An answer cannot go stale without the
  server restarting, and an unknown released puts the service's retry within reach
  of the next opening. The no-profile return is synchronous on purpose (a future
  would put a loading frame in front of a known answer), and `keepAlive` is taken
  *before* the await: it belongs to the build, the provider may be disposed while
  the read is in flight, and closing a link afterwards is safe while taking one is
  not.
- **`chamberMaxTargetProvider`** is a *value*, not a gate: 65 from 1.2.6, 60
  before it and whenever the version is not known yet; never a loading state. It
  and `labelStartingPositionProvider` are the two with nothing to observe; every
  other capability provider asks a repository, which has seen the server's own
  answers, and that outranks reasoning from a version number
  (`ServerVersion.chamberMaxTargetC`).
- **`triStateCalibrationProvider`** drives whether the print form offers an
  `auto` position: while loading, or when nothing knows, the form stays on two
  states and no `auto` is sent to a server that would reject it. It asks the queue
  repository, not the version service, for the reason in
  [server-gates.md](server-gates.md) (`triStateCalibration`).

## Repositories that must not be `autoDispose`

- `pipelinesRepositoryProvider` caches whether the routes are there at all;
  throwing that away between screens would put the entry point back to guessing.
  It is rebuilt with `apiClientProvider`, so a new server or new credentials get
  a fresh answer.
- `serverSettingsRepositoryProvider` carries the 403 latch that tells the queue
  settings screen a write was refused; that answer must survive leaving the
  screen to look at what it said.
- `inventoryRepositoryProvider` is a facade over the chosen source, usable before
  the server has said which one: its calls wait for the answer. A failed answer is
  not kept (the next call asks again, so Retry and pull-to-refresh recover once
  the server is back), but only a *settled* failure: one still being asked again
  is awaited, not doubled. Code that needs the backend itself reads
  `InventoryRepository.backend` for the same reason, never
  `inventoryBackendProvider`'s future.

## Billing

- **`printableCostCentersProvider` answers `null` for a session the server will
  not list for, and `[]` for a user with nothing to print to.** The two read
  alike in a list and need opposite words: an API key on a server before #3256
  is answered 401 by `GET /finance/cost-centers/mine` (the permission checks hand
  a key no user) and only a browser gets around that, while an empty list is
  fixed by an administrator granting a center. Every other failure is an
  `AsyncError`, which the form offers to retry.
- **It filters as the web does** (active and `can_print`) and asks nothing while
  billing is off, so a server without billing sees no request for it.
- **autoDispose**, so each form opens on the budget as it stands; a center's
  `budget_available` moves with every queued job.
- **An edit of an item that already has a center never waits for it.** The
  server keeps the stored center on a PATCH that omits it, so an API key that
  cannot list centers still edits what was queued with one.

- **The personal finance screen reads the same list unfiltered.**
  `myCostCentersProvider` keeps the centers the user may *see* but not print
  with, because the budget a member cannot use is still theirs to look at; the
  print form's provider drops them. The ledger is paged on the wire
  (`financeTransactionsProvider`, 50 a page, fetched ahead of the scroll), and
  the type and center filters narrow the rows already loaded — the endpoint
  filters on neither, so a filter that matches nothing on this page is not proof
  that nothing matches.
- **The drawer entry needs `identifiedPermissionProvider`, not
  `permissionProvider`**: no API key can hold `cost_centers:read_own`, and an
  unknown identity must not offer a screen the server will refuse.

## Server settings

- **`ServerSettingsNotifier.adopt`** takes the map a write answered with.
  `PUT /settings/` replies with the whole of `AppSettings`, so a second `GET` after
  every save can only confirm what is known, and it can *fail*, which would drop
  every flag in the app back to nothing right after a save had succeeded.
- **`refresh`** keeps what is already known if the read fails. `fetch` degrades a
  failure to an empty map, and the route answers with the full schema whenever it
  answers at all, so an empty map can only mean the read did not land; letting it
  overwrite a good one turns a dropped packet into a screen with nothing on it.
- **`serverGate` vs `serverValue`.** A *gate* decides whether a control exists, so
  a caller must tell "not answered yet" from "answered, and the answer is no":
  reading such a flag as `false` while `/settings` is in flight shows a screen
  missing a button the server does offer. It is derived synchronously, because a
  `FutureProvider` reports a loading frame even for a future already complete; it
  keeps the last answer up during a refetch and hands on an error rather than
  reading "off". A caller outside a build wants `settledGate`. A *value* (a
  symbol, a limit, a set of presets) resolves immediately against the fallback the
  server itself would have used: nothing is hidden while the settings are in
  flight, because a spinner in the middle of a price column is worse than the
  default it replaces.
