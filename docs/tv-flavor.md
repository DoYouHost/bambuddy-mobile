# TV flavor and wall mode — plan and decisions

Status: **planning only, nothing implemented.** Written 2026-09-28 from a
planning discussion with the maintainer. Tracked on purpose (not under the
gitignored `docs/plans/`) so the decisions below survive between sessions.

**Order of work (D9, D10):** the always-on farm view is the point of all of
this. It ships first as a **wall mode in the existing `mobile` flavor** (§13) —
a phone or tablet on a stand, no new flavor, no pairing, no TV review. The `tv`
flavor comes after it and is built around a **camera wall with status
overlays** (§1, §6), because that is the only always-on view Google Play
accepts on a TV.

## 1. Goal and scope

A third Android flavor, `tv`, for Android TV / Google TV and Fire TV (Fire OS),
under the same Play listing and `applicationId` as the phone and the watch.

MVP is a **passive, read-only, always-on monitor** of the print farm. Further
features are explicitly deferred ("we will think about the next ones later").

In scope for the MVP:

1. **Camera wall (home screen, D10)** — one live camera tile per printer, each
   with a status overlay: name, state, progress bar, remaining time, layer
   x/y, HMS fault chip, connection lost. A printer without a camera gets a
   status-only tile in the same grid. This screen keeps the display on (§6).
   The overlay tile is the same widget as the wall mode's (§13), shared.
2. **Printer** — opened from a tile: full-screen camera and that printer's
   active faults.
3. **Queue** — read-only list, including `waitingReason`.
4. **Errors** — active HMS faults across all printers.
5. **Stats** — read-only summary.
6. **Settings** — server, language, hidden printers, disconnect, about.

Out of scope for the MVP: any write action (pause/stop/queue edits), a
`DreamService` screensaver, Amazon Appstore listing, notifications, FGS.

## 2. Decision log

| # | Decision | Date |
|---|---|---|
| D1 | Pairing = **A (QR on TV, phone sends over LAN) + D (manual entry on TV) as fallback.** No server-mediated flow, no Nearby Connections. | 2026-09-28 |
| D1a | Phone on **JWT with `api_keys:create`** → it mints a new read-only key dedicated to this TV and sends it. | 2026-09-28 |
| D1b | Phone on **JWT without `api_keys:create`**, or on an **API key** → the user scans the TV QR, then scans the QR of a key created by hand in the Bambuddy web panel; the phone forwards that key. | 2026-09-28 |
| D1c | **The phone never hands over its own key or token.** | 2026-09-28 |
| D2 | New deep-link host `bambuddy://tv-pair` — approved (additive; existing `bambuddy://config` and `bambuddy://widget` untouched). | 2026-09-28 |
| D3 | Pairing crypto and protocol may live in `app-shared` (new dependency allowed there). | 2026-09-28 |
| D4 | TV key scope: **`can_read_status` only, all printers** (`printer_ids = null`). Hiding printers is a **local TV preference** only. | 2026-09-28 |
| D5 | *(Superseded by D5′.)* Ambient Mode: **A + B only** — screen kept on only while the user has the camera open; everywhere else the TV may enter Ambient Mode, and the app explains how to lengthen/disable the system screensaver. | 2026-09-28 |
| D6 | D-pad focus layer: **our own**, in `dash_kit` — no `dpad` package. | 2026-09-28 |
| D7 | Devices without Google services must work. **Fire TV = APK only** (GitHub Releases / Obtainium), no Amazon Appstore. | 2026-09-28 |
| D8 | Security approval: the TV **may open a temporary listening port** for pairing (explicit "yes", 2026-09-28). Scope of that yes: the pairing listener as specified in §5.3 — nothing broader. | 2026-09-28 |
| D5′ | *Supersedes D5.* An app-only dashboard cannot keep a TV on (TV-BY), and without always-on a TV app has little point. So the TV's home screen is the **camera wall with status overlays**: live video the user opened keeps the screen on, which TV-BU/TV-BY allow. Other screens still let Ambient Mode in. | 2026-09-28 |
| D9 | **Wall mode on phone/tablet first** (§13), in the `mobile` flavor — the nearer, cheaper way to an always-on farm view. The TV flavor follows it. | 2026-09-28 |
| D10 | The TV flavor is **based on the camera wall** (D5′); its tile/overlay widget is shared with wall mode. | 2026-09-28 |
| D11 | Wall mode keeps the screen on through **our own method channel** in `MainActivity` (`FLAG_KEEP_SCREEN_ON` add/clear), not `wakelock_plus`: a new `…/window` channel registered with the existing `serve()` helper. Immersive mode stays in Dart (`SystemChrome`). | 2026-09-28 |
| D12 | **No fixed cap on live camera tiles**: as many as fit on the screen and as the bambuddy server sustains. The real limits are measured on the emulator (and against a real server) before the number is designed in. | 2026-09-28 |
| D13 | Wall mode ships **with the queue + errors panel from the start**, so the grid layout is designed once around it, not rebuilt later. The TV camera wall reuses the same layout. | 2026-09-28 |
| D14 | Wall mode has a **"Keep screen awake" setting**; the D11 channel applies it only while wall mode is on screen. | 2026-09-28 |
| D15 | Wall mode is **landscape only** — portrait makes no sense for a wall. No portrait layout is designed or tested. | 2026-09-28 |
| D16 | Below a width threshold the queue + errors panel **starts collapsed, with a control to expand it**; above it, it starts expanded. The threshold comes from the spike screenshots. | 2026-09-28 |
| D17 | Wall errors panel order: **most severe first, then printer name.** `HmsError` has no timestamp, so "newest" is dropped rather than tracked in the app. | 2026-09-28 |
| D18 | The wall's queue panel **polls the queue every 30 s** while wall mode is visible (the server pushes no queue add/delete/reorder event). | 2026-09-28 |
| D19 | Wall settings live **in the side panel**: a settings button swaps the panel between the farm view and the settings, and opens the panel on them from the rail. No floating card; a tap on the wall background does nothing, a tap on a tile opens that printer's camera. Leaving is a button in the settings, or Back. | 2026-09-28 |
| D20 | Panel header and rail end with the **same pair: settings, then expand/collapse last**, on every device (a tablet can collapse too). Rail counts are read-only. Every control is ≥ 48 dp. The panel body is **one scrolling list** (errors, then queue) under a pinned header — no "+N more". | 2026-09-28 |

## 3. Server facts this plan relies on

Checked against the bambuddy server at `0a81c864`:

- `POST /api-keys/` is gated on `Permission.API_KEYS_CREATE`
  (`backend/app/api/routes/api_keys.py:38`).
- `API_KEYS_CREATE/READ/UPDATE/DELETE` are in `_APIKEY_DENIED_PERMISSIONS`
  (`backend/app/core/auth.py` ~252): **an API-key session can never create,
  list or delete keys**, whatever its scopes. By design — a key must not
  out-rank or multiply itself.
- Default groups: only **Administrators** hold `api_keys:create`
  (`core/permissions.py`, `DEFAULT_GROUPS`); Operators and Viewers do not.
- `can_read_status` covers every `*_READ`, `CAMERA_VIEW`, stats, system and
  `WEBSOCKET_CONNECT` (`core/auth.py` ~60, 100, 128) — everything the MVP needs.
- JWTs live 24 h (`ACCESS_TOKEN_EXPIRE_MINUTES`, `core/auth.py:636`) and there
  is no refresh token — another reason the phone's session is never forwarded.
- The web panel renders a `bambuddy://config?v=1&url=…&key=…` QR for a created
  key (`frontend/src/utils/apiKeyQr.ts`); the app already parses it
  (`lib/features/setup/api_key_qr.dart`).
- Auth disabled on the server → no key at all; pairing carries only the URL.
- **The server already has a kiosk Cam Wall for TVs (#2531).**
  `GET /camwall/printers` (`backend/app/api/routes/camwall.py`) returns every
  printer, ordered by name, with only what a wall tile draws: `id`, `name`,
  `camera_rotation`, `connected`, `state`, `progress`, `remaining_time`,
  `layer_num`, `total_layers`, `hms_errors` (codes). Deliberately **no print
  filename, serial or IP** — a wall is on show in a shared room. It is gated
  by a long-lived **`camwall`**-scoped token, which also opens the camera
  streams (`STREAM_SCOPES` in `services/long_lived_tokens.py`).
- Long-lived tokens are minted by `POST /auth/tokens` (`routes/auth.py`,
  ~1720), gated on `CAMERA_VIEW` — which **Operators and Viewers hold too**
  (`core/permissions.py` 448, 508), not just admins. Max **365 days**, never
  infinite; **JWT only** (an API-key session reaches the route with no user and
  gets 403 "Long-lived tokens require authentication"); refused when auth is
  disabled. Scopes: `camera_stream`, `camwall`, `overlay` (the last includes the
  filename).
- Consequence, not yet a decision (§12): for a wall that only shows the camera
  wall, a `camwall` token is a narrower credential than a `can_read_status` API
  key and more users can mint one — but it expires (≤ 1 year) and reaches no
  queue, stats or fault detail, and the feed is polled, not pushed.

## 4. Google requirements (fetched 2026-09-28)

From [TV app quality](https://developer.android.com/docs/quality-guidelines/tv-app-quality)
(updated 2026-06-29) — Tier 3 "TV Ready" is what review checks:

- **TV-ML / TV-LM**: activity with `ACTION_MAIN` + `CATEGORY_LEANBACK_LAUNCHER`.
- **TV-MT**: `required="false"` for `touchscreen`, `faketouch`, `telephony`,
  `camera`, `nfc`, `location.gps`, `microphone`, `sensor`, `wifi` (some TVs are
  Ethernet-only). `CAMERA` permission implies `camera` + `camera.autofocus` —
  strip the permission in the `tv` manifest.
- **TV-LB / TV-BN**: 320×180 banner **containing the app name** (localize per
  language) + ≥160×160 icon.
- **TV-LO / TV-OV / TV-TR**: landscape only, no letterboxing, nothing cut off
  (overscan-safe margin: 48 dp left/right, 27 dp top/bottom), opaque background.
- **TV-DP / TV-DM**: fully usable with up/down/left/right/select/Back/Home; no
  reliance on a Menu key; focus clearly visible.
- **TV-DB**: repeated Back always ends at the TV home screen; no exit
  confirmation; Back never toggles.
- **TV-BU / TV-BY**: keep the screen on only for user-initiated video; never for
  automatic playback or animations.
  ([Ambient Mode](https://developer.android.com/training/tv/playback/ambient-mode),
  2026-09-08.)
- **TV-PS**: minSdk ≤ 31 — ours is 24.
- **TV-G1 / TV-G6**: AAB only; from 2026-08-01 both 32- and 64-bit and 16 KB
  page size. Our `_build` does not filter ABIs, so the AAB carries v7a/arm64/
  x86_64; **16 KB alignment of every native lib must be verified** (spike).
- **TV-G4**: at least one real TV screenshot; description mentions "Android TV".
- **TV-G5**: reviewer credentials — use the existing demo mode (`lib/core/demo`).
- Tier 2 (optional) TV-LI "login using mobile" — matches D1.

Publishing ([Distribute to Android TV](https://developer.android.com/training/tv/publishing/distribute),
2026-05-08): Play Console → Setup → Advanced settings → Form factors → Add
release type → Android TV; then releases go to the dedicated TV track (form
factor tracks are prefixed, like our `wear:internal`). **Exact track name
(`tv:internal`?) to be confirmed on the first upload** — the Play help page was
unreachable from the planning session.

Flutter: no official TV support; umbrella
[flutter/flutter#180542](https://github.com/flutter/flutter/issues/180542) (open,
P3) lists D-pad traversal through `TextField` throwing, focus loss, soft
keyboard not closing with Back on Fire TV, missing manifest docs.

## 5. Pairing

### 5.1 Phone-side flows

Entry: a "Pair a TV" action on the phone (settings, and the scanner recognising
a `bambuddy://tv-pair` QR).

1. Scan the TV QR (existing scanner, `lib/features/common/qr_scanner_screen.dart`).
   Parse it with a **pure function** + tests (basic, missing, odd input — AGENTS
   rule).
2. Decide the path:
   - **Server auth disabled** → payload = `{url}` only.
   - **JWT and the user holds `api_keys:create`** (D1a) →
     `POST /api-keys/` with `name: "TV – <device label> <date>"`, only
     `can_read_status: true`, every other scope false, `printer_ids: null`
     (reuse `ApiKeysRepository.create`). If sending to the TV then fails, delete
     the key just created (`api_keys:delete`, which the same user holds) so no
     orphan is left; if that delete fails too, tell the user which key to remove.
     *To verify during implementation: where the app already knows the user's
     permissions (e.g. `/auth/me`) — decide the path from that, not by trying
     the POST and reading a 403.*
   - **JWT without the permission, or an API-key session** (D1b) → guided
     screen: "In Bambuddy web: Settings → API keys → create a key with only
     *Read status* → show its QR", then scan that QR (`parseApiKeyQr`). Checks
     before sending: it is a `bb_` key; the URL in the QR (or, if absent, the
     phone's own server URL) is used; if the QR URL differs from the phone's
     server, warn and show both. Optionally probe the key (`GET /printers/`) so
     a mistyped/revoked key fails on the phone, not on the TV. **The scanned key
     is held in memory only and never persisted on the phone.**
3. Encrypt and send (§5.2), show the TV's result.
4. **Never** send the phone's own key or JWT (D1c) — enforced in code by the
   payload builder accepting only a key minted/scanned in this flow.
5. Diagnostics: pairing steps are logged by id only; the key, URL query and
   ciphertext are never recorded (see `docs/diagnostics-log.md` redaction).

### 5.2 Protocol (lives in `app-shared`, D3)

- TV generates an ephemeral X25519 key pair and a random pairing id per QR.
- QR: `bambuddy://tv-pair?v=1&h=<lan-ip>:<port>&k=<b64url TV pubkey>&c=<pairing id>`.
- Phone: ephemeral X25519 key pair → ECDH → HKDF-SHA256 (info binds `v`, `c`
  and both public keys) → AES-256-GCM over
  `{"v":1,"url":"…","key":"bb_…"|null,"label":"…"}`.
- Phone `POST http://<h>/pair/<c>` with `{"v":1,"pk":"<phone pubkey>","n":"<nonce>","ct":"<ciphertext>"}`.
- Why encrypt on a LAN that already carries the server traffic in cleartext: the
  pairing request is the one moment a key crosses the network towards a new
  device; a passive sniffer must not be able to lift it, and the TV's public key
  in the QR is what makes that possible without any server help.
- Candidate library: `cryptography` (pub.dev) — to be confirmed in the spike
  (pure Dart fallback on devices without the platform provider).

### 5.3 TV listener (D8 — exact scope of the approval)

- Opened **only while the pairing screen is visible**; closed on leave, on
  success, and after **120 s** (QR regenerated with a new key pair, id and port).
- Binds a random high port on the LAN interface; local IP from
  `NetworkInterface.list()` — **no new Android permission** (if one turns out to
  be needed, e.g. `ACCESS_WIFI_STATE`, stop and ask).
- Accepts exactly one route, `POST /pair/<c>`; anything else → 404 and close.
  Body limit ~4 KB. **Single use**: first valid message wins, listener closes.
- **5 failed attempts** (bad id, bad JSON, decrypt failure) → close and
  regenerate the QR.
- Before saving, the TV shows **"Connect to <server URL>?"** and waits for OK —
  so a device on the LAN that learned an old id cannot silently repoint the TV.
- Then it validates the URL (`normalizeBaseUrl`), probes the server with the
  key, stores the key in `flutter_secure_storage` and the URL in preferences
  (same stores as the phone), answers the phone with success/failure reason.
- Known limit: phone and TV must be on the same network; client isolation
  (guest Wi-Fi) breaks it → the screen offers D.

### 5.4 Fallback D — manual entry on the TV

- URL + either login/password (with "remember me", so the 24 h JWT renews on its
  own) or an API key. 2FA users are told a key is the better fit (a saved
  password cannot answer 2FA daily).
- Must be tested against the Flutter TV text-field issues and the Fire TV
  keyboard/Back bug (§4). Gboard voice input needs nothing from us.

### 5.5 Re-pairing and hidden printers

- Pairing again replaces the stored config. The TV cannot delete its old key
  (keys cannot manage keys); the phone flow tells the user to revoke the old
  "TV – …" key in the web panel. (Later: path D1a could offer to delete it.)
- Hidden printers: a local list of printer ids in `SharedPreferences` on the TV
  (new key, e.g. `tv.hiddenPrinterIds`); does not touch the key or the server.
  Unknown ids are ignored, so a printer deleted on the server needs no cleanup.

## 6. Ambient Mode and the always-on camera wall (D5′)

TV-BY, verbatim: *"When there is no user-initiated active video playback or
animation, the app does not prevent the device from going into Ambient Mode."*
The Ambient Mode page adds that automatic playback and animations must not set
`FLAG_KEEP_SCREEN_ON`.

- **Camera wall**: the user opens it, and it is live video → set
  `FLAG_KEEP_SCREEN_ON` while it is visible, clear it when it closes. The same
  for the full-screen camera. This is the always-on view.
- A wall where **no printer has a camera** is a dashboard, not video — do not
  keep the screen on there, and say so in the UI.
- Every other screen (queue, errors, stats, settings) lets the TV enter Ambient
  Mode. Settings explains where the TV's own screensaver timeout lives
  ("never" is device-dependent — check).
- **The camera-wall reading of TV-BY is ours, not Google's.** Only a review
  settles it, so phase 0 submits a minimal build to the Play TV review before
  the rest is built (§11). If Google rejects it, the Play build loses
  always-on and the question becomes whether the TV flavor is worth shipping
  as APK-only, where no Play rule applies (Fire TV, boxes without Play).
- Energy Saver (device power-off) cannot be prevented by any app.
- `DreamService` stays a later idea.

## 7. Architecture in this repo

- **Gradle** (`android/app/build.gradle.kts`): `create("tv")` in the `device`
  dimension with `versionCode = (flutter.versionCode ?: 0) + 100_000_000` — the
  band reserved in the `justfile` comment above `_bump`
  (102_000_000 .. 121_999_980). minSdk stays 24.
- **Asset prune** like `copyFlutterAssetsWear…`: gcode viewer, slicer schemas,
  whatever the TV entry point does not reach — verified by a check script, not
  assumed (same rule as the watch).
- **Native size**: the TV does not scan, so ML Kit (via `mobile_scanner`) is
  dead weight and a 16 KB-alignment risk — spike: can the `tv` variant exclude
  those JNI libs safely? `check_tv_apk.py` then asserts it.
- **`android/app/src/tv/AndroidManifest.xml`**: `LEANBACK_LAUNCHER` intent
  filter on `MainActivity`, `android.software.leanback required="true"` (TV
  APK only), the `required="false"` feature list from §4, `android:banner`,
  landscape, `configChanges="keyboard|keyboardHidden|navigation"`; remove
  CAMERA, FGS, notification, boot, battery-exemption permissions, the widgets,
  the FGS service, the notification-action receiver and the wear relay service
  (mirror of the `wear` manifest). Own `BrandedLaunch.kt`/launch theme.
- **Dart**: `lib/tv/main_tv.dart` (no FGS, notifications, widget, wear relay;
  WebSocket on), `lib/tv/…` screens and providers over `lib/core` + `lib/data`.
  Reconnect the socket on resume and on network change.
- **Diagnostics**: `session_facts.dart` reports `appFlavor`, so `tv` shows up in
  reports without changes. Every TV control gets a `logTag`
  (`tv.<area>.<thing>`); `log-coverage` stays at zero.
- **l10n**: all strings in the 5 locales, `just l10n-check`.

## 8. `app-shared` changes (D3, D6)

- `dash_ui`: focus tokens (ring colour/width, scale), TV type scale.
- `dash_kit`: a focusable wrapper with visible focus, directional traversal
  groups with memory (rail ↔ grid), an overscan-safe scaffold (48/27 dp), and
  focus-correct `confirmDialog`/`ButtonPair`.
- New package (working name `app_pairing`): QR payload, crypto, TV listener,
  phone sender — domain-free so lubelogger-mobile can reuse it.
- New tag (after v0.11.0), bumped in both apps.

## 9. Tooling, CI, release

- `justfile`: `build-tv`, `build-tv-aab`, `run-tv` (TV emulator AVD), `ship`
  and `ship-dev` build and publish the TV artifacts too; `_upload-assets` takes
  a third file (`app-tv-<name>.apk` for Obtainium/Fire TV).
- `tool/play_internal.py`: route by band — TV codes to the TV track (name per
  §4); `tool/aab_versions.py`: learn the TV band.
- CI (`ci.yml`): compile check for `tv`, plus `tool/check_tv_apk.py` (pruned
  assets, stripped components/permissions, leanback + banner present).
- Play: opt in to Android TV, banner and TV screenshots, "Android TV" in the
  description (5 languages), demo-mode credentials for the reviewer.
- Fire TV (D7): APK from GitHub Releases only. Fire OS devices only — newer Fire
  TV devices on Vega OS do not run Android apps (to confirm).
- Docs to update when this lands: AGENTS.md (flavor list, `--target
  lib/tv/main_tv.dart`), `docs/play-store-listing.md`, `docs/privacy-policy.md`
  (pairing is local-network only, nothing leaves the LAN).

## 10. Testing

- Pure-function tests: TV QR parser, payload builder (refuses anything but a
  minted/scanned key), protocol round trip, listener limits (single use, 5
  failures, TTL, body size).
- Phone flow tests for each path in §5.1, including the orphan-key cleanup.
- Widget tests on 1920×1080 and 960×540 (a `pumpTv` helper, like `pumpWear`),
  D-pad traversal driven by key events, Back reaching the root, nothing outside
  the overscan-safe area (an `expectOnGlass`-style assertion).
- Manual: Android TV emulator, one Google TV device, one Fire OS device.

## 11. Phases and estimate

| Phase | Content | Estimate |
|---|---|---|
| 0. Spike + early review | Flutter on TV emulator + Fire OS: focus, `TextField`, keyboard, WebSocket, several MJPEG streams at once; 16 KB check; ML Kit exclusion; `cryptography` on-device; LAN listener reachability. **Submit a minimal camera-wall build (screen kept on, demo mode for the reviewer) to the Play TV review** — go/no-go for D5′ before phases 1–5 | 2–3 days + review |
| 1. Infrastructure | Flavor, manifest, banner, `main_tv.dart`, justfile, Play scripts, CI + APK check | 3–4 days |
| 2. `app-shared` | Focus layer, TV scaffold, pairing package, tag | 4–6 days |
| 3. Pairing in both apps | Phone flows (§5.1), TV screen + listener + D, tests, security review | 3–4 days |
| 4. MVP screens | Camera wall (reusing the §13 tile) + 5 screens, l10n, log tags, widget tests | 6–9 days |
| 5. Play | Listing, screenshots, review submission | 1–2 days + review |
| **Total** | | **~4–5 weeks** (after wall mode, §13) |

## 12. Still open

1. Exact Play track name for TV (§4) — confirm on first upload.
2. Where the phone reads the user's permissions to pick path D1a vs D1b.
3. Whether Google TV lets a user choose a third-party screensaver (only matters
   if `DreamService` comes back).
4. Whether "never" is an available screensaver setting on target devices (B).
5. Vega OS vs Fire OS — confirm which current Fire TV devices can sideload.
6. ~~Camera grid in the MVP or after it~~ — settled by D10: it *is* the MVP.
7. TV credential: `can_read_status` API key (D4, pairing as in §5) or a
   `camwall` token (§3)? Or the key for the full app plus nothing else? Decide
   before phase 3.
8. If the Play review rejects the always-on camera wall: APK-only TV, or drop
   the TV flavor?
9. Tizen (Samsung TVs): assessed 2026-09-28, deferred. flutter-tizen supports
   Tizen 6.0+ (2021+ TVs) and has Tizen ports of our key plugins, but it is a
   separate toolchain (`.tpk`), distribution is Samsung TV Seller Office only
   (partner status outside the US, review "more than 4 weeks"), and there is no
   sideload path for end users. Revisit once the Android TV flavor exists.

## 13. Wall mode in the mobile flavor (D9) — first step

An always-on farm view on a phone or tablet on a stand. Phone apps are not
under the TV quality rules, so keeping the screen on is ordinary (navigation
and dashboard apps do it). No new flavor, no pairing — it runs in the app the
user is already signed in to, with the credentials it already has.

### 13.1 What it shows

- A grid of **printer tiles with status overlays** — name, state, progress bar,
  remaining time, layer x/y, HMS fault chip, "connection lost" — over the live
  camera when the printer has one, status-only otherwise. The same tile widget
  becomes the TV camera wall (D10), so it is written once.
- Data from the existing providers and WebSocket (full auth), not the
  `/camwall` feed: the app already has a push channel and richer data.
- **Landscape only (D15).** Entering wall mode locks the orientation to
  landscape (`SystemChrome.setPreferredOrientations` with both landscape
  directions, so a stand either way round works); leaving it restores the
  app's normal orientation — which is *unconstrained*: the manifest sets no
  `screenOrientation`, so restoring means `setPreferredOrientations([])`, never
  a portrait lock, and `SystemUiMode.edgeToEdge` for the bars. Both go in the
  screen's `dispose`, so every exit path (Back, a route replaced from under it)
  restores them. The grid adapts to the landscape width: e.g. 2–3
  columns on a phone, 3–5 on a tablet. Tap a tile for that printer's
  full-screen camera and back.
- **Queue + errors panel (D13)**, part of the layout from the first version:
  - *Errors*: active HMS faults across all printers, most severe first, each
    naming its printer; a fault also highlights its tile. Empty state is
    a quiet "no faults", not a hidden panel, so the layout does not jump.
    `HmsError` carries no timestamp (`printer_status.dart`), so "newest"
    cannot come from the data; ties break by printer name (D17).
  - *Queue*: the next items (name, target printer or model, `waitingReason`),
    in one scrolling list under the errors (D20). The server pushes no
    WebSocket event for a queue add, delete or reorder (only
    `queue_item_{acked,failed,uploading,upload_progress}`,
    `core/websocket.py`), and the app refreshes the queue only on print
    events (`ws_providers.dart`), so the panel **polls** the queue while wall
    mode is visible, every 30 s (D18).
  - Placement: a **side column** next to the grid, on every device (landscape
    only, D15). The grid is always laid out *next to* the panel, never under
    it — that is the reason to build them together.
  - **Collapsed below a width threshold (D16).** On a screen narrower than the
    threshold the column starts collapsed to a slim rail that still shows the
    fault and queue counts (a new fault stays visible as a count and as the
    highlighted tile); one tap/select expands it, another collapses it. When
    expanded, the grid reflows into the remaining width rather than being
    overlapped. At or above the threshold it starts expanded. The threshold is
    a logical-pixel width set from the spike screenshots, not a device
    category.
  - The user's last expand/collapse choice is remembered per device, so a
    phone the user wants expanded stays expanded.
  - Read-only: nothing in the panel acts on a printer.
- Wall mode settings (local, per device):
  - **Keep screen awake** (D14) — on by default, since an always-on wall is
    the point of the mode; off lets the device's own screen timeout apply
    while the wall is shown.
  - Which printers appear (like the TV's hidden list). New work: no
    hidden-printer setting exists in the app yet; a new prefs key.
  - Tiles show live video or status only.
  - Queue + errors panel shown or hidden (hidden removes the rail too).
  - These settings open inside the panel, not over the wall (D19).

### 13.2 Behaviour

- Entered explicitly (a "Wall mode" action in the dashboard's ⋮ menu); left
  with Back or the exit button in the panel settings (D19) — never by
  accident, never trapping the user.
- **Pushed on top of the dashboard (`context.push`), never `go`.** The
  dashboard owns the FGS start/stop and the three token refreshers
  (`dashboard_screen.dart`, its `AppLifecycleListener`); replacing it would
  silently stop background monitoring and token renewal. A test asserts the
  dashboard is still mounted under the wall.
- **Keeps the screen on only while wall mode is visible and "Keep screen
  awake" is on** (`FLAG_KEEP_SCREEN_ON` on the activity — needs no
  permission): set on enter, cleared on exit and when the setting is turned
  off. Not touched on background/resume — the flag only acts while the window
  is visible, so there is nothing to re-assert when the user comes back.
  Mechanism (D11): two handlers on the method-channel table `MainActivity.kt`
  already has — no new dependency. `wakelock_plus` would set the same flag on
  Android; it is not worth a package. The same channel serves the TV flavor.
- Immersive full screen (system bars hidden) while in wall mode.
- Survives what a wall screen meets for days: WebSocket reconnect after Wi-Fi
  drops, server restarts, camera streams reconnecting individually
  (`MjpegView` already retries on its own backoff and keeps the last frame).
- **JWT expiry (24 h).** A password session with "remember me" renews
  silently and the wall never notices. A 2FA session has no remember-me by
  design (`auth_service.dart`, `verifyTwoFactor`), nor does a session without
  it: when the dashboard poll meets the 401 it sets `authExpired`, and the
  dashboard — still mounted under the wall — answers with
  `context.go('/setup')`, which replaces the wall. That is the "sign in
  again" state; the wall's `dispose` restoring orientation, bars and the
  screen flag is what keeps the user from landing on a landscape-locked,
  immersive login screen. The sign-in-required dialog
  (`_showSignInRequired`) is raised only on first frame and on resume, which
  an always-on wall never has — so it is not what the wall relies on. An API
  key session never expires and can mint camera tokens (`CAMERA_VIEW` maps to
  `can_read_status`, `core/auth.py:100`) — worth a hint in the wall-mode
  settings for 2FA users.
- **Camera token refresh (~55 min) must not restart the streams.** The
  proactive refresher (`cameraTokenRefresherProvider`) re-mints before the
  60-min server TTL and the new token changes the `?token=` in every stream
  URL. `MjpegView.didUpdateWidget` treats any URL change as a new stream: it
  drops the socket and the last frame, so every tile would flash a spinner
  and reopen at once, hourly. The server checks the token only at connect
  (`RequireCameraStreamTokenIfAuthEnabled` is a route dependency; the fan-out
  generator never re-checks), so an open stream is unaffected. Change: when
  only the `token` parameter changed, keep the live connection and just use
  the new URL for the next reconnect; restart immediately only if the stream
  is down or retrying. This also fixes the same hourly blink in the
  full-screen camera view.
- Burn-in: static chrome is minimal; shift the overlay layout by a few pixels
  periodically (OLED phones/tablets).
- Live tiles (D12): every tile that fits on screen streams live — no designed-in
  cap. Two limits decide how many actually work, and both are **measured before
  the tile logic is finalised**:
  - *Device*: decoding N MJPEG streams at once — frame rate, CPU, memory, heat
    — on a low-end tablet emulator profile and on a real mid-range device.
  - *Server*: the bambuddy server fans each printer's camera out to every
    viewer over one upstream connection (`camera_fanout`, #1089), so N tiles
    cost N upstreams — one `ffmpeg` per RTSP printer (X1/H2/P2) or one
    chamber-image connection (A1/P1) — not N per viewer. Find where it starts
    dropping frames or refusing, with a real server and real printers (the
    emulator alone cannot show this).
  - *Frame rate*: the stream route takes `fps` (default 10; clamped to 5 on
    A1/P1, 30 otherwise, `routes/camera.py`). A low fps per tile is the
    obvious lever, **but the fan-out's fps is fixed by the first viewer**
    (`routes/camera.py`, note above `fanout_key`): a wall open 24/7 at 2 fps
    pins the phone's full-screen view and the web UI of that printer to 2 fps
    too. The spike measures fps per tile with that trap in mind.
  - Degrade instead of break: a tile whose stream fails or stalls falls back to
    a periodic snapshot with a "live paused" marker and retries; the rest of
    the wall is unaffected. If measurement shows a hard ceiling, it becomes a
    setting with a measured default rather than a guess.
- Screen pinning / kiosk lock is left to Android's own "app pinning"; no device
  owner mode.
- Not on the watch.

### 13.3 Work items

- `lib/features/wall/` — screen, tile/overlay widget, queue + errors panel,
  providers (reuse the dashboard's printer state, `QueueRepository`, the HMS
  catalogue and `mjpeg_view.dart`).
- Keep-screen-on channel handlers in `MainActivity.kt` + a Dart wrapper;
  immersive toggle scoped to the screen.
- New work the code does not have yet:
  - `MjpegView`: keep the connection when only the token changed (§13.2).
  - Snapshot fallback: an `Endpoints` constant for
    `GET /printers/{id}/camera/snapshot` and a polling tile.
  - Queue poll while the wall is visible.
  - Hidden-printer setting (prefs key + picker).
  - Burn-in shift timer.
- l10n in 5 locales (`just l10n-check`), `logTag` ids `wall.*`, `log-coverage`
  at zero.
- Tests: tile overlay states (printing, paused, idle, fault, offline, no
  camera, live paused), grid + panel at landscape phone and tablet sizes and
  at large system text, panel empty/overflow states, panel collapsed/expanded
  on each side of the width threshold, the rail's counts, the remembered
  choice, orientation locked on
  enter and restored on exit (including when `/setup` replaces the wall),
  keep-screen on/off on enter/exit and on toggling the setting (fake channel),
  dashboard still mounted under the wall, a token-only URL change not
  reopening the stream, reconnect paths.
- Docs: store listing mention (5 languages), `docs/logging-guide.md` ids.

### 13.4 Estimate

| Step | Estimate |
|---|---|
| Measurement spike (D12): N simultaneous MJPEG streams on emulator profiles + against a real server; keep-screen-on channel | 1–2 days |
| Tile/overlay widget + grid + settings | 2–3 days |
| Queue + errors panel and the shared layout (D13) | 2 days |
| Keep-screen-on, immersive, resilience (reconnects, token-only URL change in `MjpegView`, JWT expiry exit path) | 1–2 days |
| Snapshot fallback, queue poll, hidden printers, burn-in shift | 2–3 days |
| l10n, log tags, tests | 1–2 days |
| **Total** | **~2–3 weeks** |

### 13.5 Open for wall mode

1. ~~Keep-screen-on mechanism~~ — settled by D11 (own channel).
2. Live-tile limits and the snapshot fallback interval — numbers from the D12
   measurement; recorded here once measured.
3. ~~Grid only or with a panel~~ — settled by D13 (panel from the start).
4. ~~Panel in portrait~~ — no portrait (D15).
5. ~~Panel on narrow phones~~ — settled by D16 (collapsed below a threshold,
   expandable).
6. The D16 width threshold — pick from the spike screenshots.
7. ~~Error order~~ — settled by D17.
8. ~~Queue poll interval~~ — settled by D18.
9. Provisional values in the code, to confirm with the D12 measurement and
   the spike screenshots: the rail threshold (`panelExpandedFromWidth`, 960
   dp), a refused stream asked for again after 60 s (`restreamAfter`), the
   burn-in step (3 min round four offsets of 2 px). The snapshot interval
   (8 s) is the server's own camera wall's, not a guess.
10. "Panel shown or hidden" (§13.1) is not built: with the rail gone the wall
    loses its only way into its settings (D19), so it needs a design first —
    e.g. a lone settings button in a corner, or the setting only in the app
    settings.
