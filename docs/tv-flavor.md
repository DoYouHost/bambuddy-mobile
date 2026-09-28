# TV flavor — plan and decisions

Status: **planning only, nothing implemented.** Written 2026-09-28 from a
planning discussion with the maintainer. Tracked on purpose (not under the
gitignored `docs/plans/`) so the decisions below survive between sessions.

## 1. Goal and scope

A third Android flavor, `tv`, for Android TV / Google TV and Fire TV (Fire OS),
under the same Play listing and `applicationId` as the phone and the watch.

MVP is a **passive, read-only monitor** of the print farm. Further features are
explicitly deferred ("we will think about the next ones later").

In scope for the MVP:

1. **Farm** — grid of printer cards: state, progress, ETA, temperatures, HMS
   fault badge. Live over the WebSocket.
2. **Printer** — opened from a card: full-screen camera and that printer's
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
| D5 | Ambient Mode: **A + B only** — screen kept on only while the user has the camera open; everywhere else the TV may enter Ambient Mode, and the app explains how to lengthen/disable the system screensaver. | 2026-09-28 |
| D6 | D-pad focus layer: **our own**, in `dash_kit` — no `dpad` package. | 2026-09-28 |
| D7 | Devices without Google services must work. **Fire TV = APK only** (GitHub Releases / Obtainium), no Amazon Appstore. | 2026-09-28 |
| D8 | Security approval: the TV **may open a temporary listening port** for pairing (explicit "yes", 2026-09-28). Scope of that yes: the pairing listener as specified in §5.3 — nothing broader. | 2026-09-28 |

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

## 6. Ambient Mode and "screen on the wall" (D5)

- **A**: the full-screen camera (and a later camera grid) is user-initiated
  video → `FLAG_KEEP_SCREEN_ON` while it is visible, cleared when it closes.
- **B**: every other screen lets the TV enter Ambient Mode. Settings carries a
  short explanation of where the TV's own screensaver/timeout lives. Whether
  "never" is available is device-dependent — check on real devices.
- Not doing: keeping the screen on for the dashboard (breaks TV-BY, review
  risk). `DreamService` stays a later idea; open question whether Google TV even
  lets users pick a third-party screensaver.
- Energy Saver (device power-off) cannot be prevented by any app.

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
| 0. Spike | Flutter on TV emulator + Fire OS: focus, `TextField`, keyboard, WebSocket, MJPEG; 16 KB check; ML Kit exclusion; `cryptography` on-device; LAN listener reachability; first AAB on the TV track | 1–2 days |
| 1. Infrastructure | Flavor, manifest, banner, `main_tv.dart`, justfile, Play scripts, CI + APK check | 3–4 days |
| 2. `app-shared` | Focus layer, TV scaffold, pairing package, tag | 4–6 days |
| 3. Pairing in both apps | Phone flows (§5.1), TV screen + listener + D, tests, security review | 3–4 days |
| 4. MVP screens | 6 screens, l10n, log tags, widget tests | 7–10 days |
| 5. Play | Listing, screenshots, review submission | 1–2 days + review |
| **Total** | | **~4–5 weeks** |

## 12. Still open

1. Exact Play track name for TV (§4) — confirm on first upload.
2. Where the phone reads the user's permissions to pick path D1a vs D1b.
3. Whether Google TV lets a user choose a third-party screensaver (only matters
   if `DreamService` comes back).
4. Whether "never" is an available screensaver setting on target devices (B).
5. Vega OS vs Fire OS — confirm which current Fire TV devices can sideload.
6. Camera grid in the MVP or after it.
