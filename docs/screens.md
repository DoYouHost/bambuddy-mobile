# Screens — the decisions behind the dashboard, maintenance, statistics, login and locations

One section per feature. What each does is in the code; this file keeps the
decisions that cannot be re-derived from it and the traps that cost a debugging
session. Billing and Finance have [their own file](billing.md), the single-printer
controller [another](single-printer-controller.md).

## Dashboard: printer status and smart plugs

### Merging a frame never blanks a known value

`PrinterStatus.mergedWith(previous)` gives every field the new frame does not carry
(`null`) the last known value. REST and the WebSocket carry disjoint subsets, and
before the socket connects the only source is the five-second poll, whose snapshot
of a booting printer is partial. Overwriting would blank progress, temperatures and
fans to "—" and restore them on the next poll. A value that really changes always
arrives non-null (`connected: false`, a fan at `0`), so inheriting catches a missing
field and never a change. `temperatures` merge per key, so a sensor missing from a
frame keeps its tile.

**The one exception is `connected: false`.** The server keeps the last telemetry of
a dropped printer, so the frame still says "printing at 60 %". `_clearedIfOffline`
drops the live state (job, progress, temperatures, fans, light, door, speed) and
keeps what survives a power-off: identity and hardware, the AMS inventory, `hmsErrors`
(so [PrintMonitor](notification-rules.md) does not re-alert a known fault on
reconnect) and `awaitingPlateClear`. The last one is bambuddy's own database flag, not
printer state, and the control that releases it must stay reachable on a printer
that switched itself off.

### The OFFLINE card

`PrinterCard` collapses to a header (greyed icon, name, red OFFLINE chip) when the
status is missing or `connected != true`. The expanded state survives and returns
with the printer. The summary header counts only **connected** printers as printing.

The collapse is debounced by `OfflineDebounce` (`lib/core/printers/offline_debounce.dart`,
15 s), shared with the offline alert so the card and the notification agree.
`connected` flickers: after power is cut at a plug the socket says `false` at once
while the poll lane still says `true`, so a naive card folded and unfolded every
poll. Each fresh `connected: true` cancels the countdown. Not debounced: a printer
that is offline when the card first builds (it is *adopted*, not an event), and the
first frame after the line to the server came up (`inTouchSince`), where nothing
could contradict it. A frame with `connected == null` says nothing about
reachability and is never read as offline.

### Smart plugs (`/api/v1/smart-plugs/`)

- `GET /smart-plugs/` lists the plugs with `printer_id` (the plug-to-printer map in
  one call), `enabled`, `last_state`, `show_on_printer_card`, `show_in_switchbar`.
- `GET /smart-plugs/{id}/status` returns `{state, reachable, device_name, energy}`;
  live watts are `energy.power`.
- `POST /smart-plugs/{id}/control` takes a JSON body `{"action": "on"|"off"|"toggle"}`
  (not a query string). A 403 means the key lacks the permission, and the notifier
  keeps a sticky `forbidden` flag.
- **Plug state is not on the WebSocket.** `SmartPlugsNotifier` polls every 5 s
  (`smartPlugPollInterval`), paused in the background like the dashboard, with an
  optimistic toggle that rolls back.
- An **MQTT plug is monitor-only**: bambuddy subscribes and never publishes, so
  `control` answers 400 (`isMonitorOnly`); a Home Assistant `script.` entity runs
  rather than switches. The card's power button goes to the plug the server would call
  the printer's main plug (`SmartPlug.compareAsMainPlug`, a port of
  `_main_plug_rank`), not the first one listed — an exhaust fan is a plug too.

UI decisions, reached over several rounds; ask before changing them:

- The control is a **square icon button in the card's header row**, with no text and
  no plug name; watts and state live in the tooltip. Not a Switch, not a row under
  the controls.
- It stays visible **while the printer is OFFLINE** (card collapsed): remote power-on
  is how a sleeping printer is woken.
- The button is disabled during a print (tooltip says why); switching goes through
  `confirmAndSwitchPlug`, which asks first and marks power-off as destructive. The
  same function serves the printer card and the controller.
- The header's "N W" is the sum over every polled (enabled) plug, not just the
  card-visible ones.

Tests: a provider that polls needs an inert override (`_InertStatuses`,
`_InertSmartPlugs` in `test/helpers.dart`, applied by the shared harness), or the
test hangs on the timer.

## Edit printer and printer locations

**Edit printer** is the web's form, `AddPrinterScreen(printer:)`, opened by a **long
press on the card's name**, hidden when `canUpdatePrintersProvider` is false (an API
key never holds `printers:update`). Alternatives were considered and rejected: an icon
on the card, the locations screen, the server settings hub.

The wear-cost field (cost per hour of printing, #694) is offered only when
`GET /printers` carries the key `wear_cost_per_hour` at all (`Printer.servesWearCost`):
an older server would take it on a `PATCH` and drop it without a word. It is an
observation of the answer, not a version row. The "most expensive" record adds
filament, energy and wear, as the web does.

**Locations** (`/locations`, server 1.2.6; gate in [server-gates.md](server-gates.md))
is reached from the printer form, add or edit: the location field is a combo of the
managed names plus the names printers already carry (free text allowed, the server
adds it to the list) with a "Manage locations" button under it. There is deliberately
no entry in the dashboard's filter sheet.

Deviations from the web kept on purpose:

- The locations screen's hide-empty and sort are not persisted (web: `localStorage`),
  while the dashboard's own filters, sort and folded sections are (`DashboardView`).
- The dashboard banner's "N printing" counts `PREPARE` and `PAUSE` as printing
  (`PrinterStatus.isPrinting`); the status filter's "printing" chip counts `RUNNING`
  only, with pausing in a bucket of its own and preparing in idle
  (`classifyPrinter`, the web's `classifyPrinterStatus`).
- The web reverses location and model sections twice on a descending sort; the app
  reverses once.

## Maintenance

The Maintenance tab (fourth bottom-bar branch) is a **status view only**: per-printer
overview, progress bar, "Mark done" (resets the counter) and history. Everything
configurable lives on `/settings/maintenance` (gear in the app bar). That split is a
maintainer decision; do not merge settings back into the status screen.

Contract (`/api/v1/maintenance/*`):

- Used: `overview`, `printers/{id}`, `items/{id}/perform` (body `{notes}`),
  `items/{id}/history`, `items/{id}` (`PATCH`: `{enabled}` mutes, `{custom_interval_hours}`
  overrides the interval and `null` restores the default — the route applies exactly
  the fields sent), `types*` and `printers/{pid}/assign/{tid}`.
- `MaintenanceTypeCreate/Update`: `name`, `default_interval_hours >= 1`,
  `interval_type` `hours|days`, `icon`, `wiki_url`. **A custom type must be assigned
  to each printer** (`POST .../assign/{tid}`) or it never appears.
- `DELETE types/{id}` removes a custom type and only hides a system one;
  `POST types/restore-defaults` brings the hidden ones back.
- In `MaintenanceStatus`: `is_due`, `is_warning`, `hours_until_due` (negative =
  overdue), `interval_hours`, `hours_since_maintenance`.

**Icons** are bambuddy's Lucide names (`iconMap` in `MaintenancePage.tsx`), 21 of
them. `maintenance_icons.dart` maps each to a Material glyph and the picker keeps the
web's order; keep index parity when adding one. An unknown name falls back to a wrench.

**Due alerts.** `due` is computed by the server and is not in WebSocket frames, so
`MaintenanceMonitor` polls the overview over REST every 30 minutes
(`_maintenanceCheckInterval`), in the same foreground-service isolate as the other
alerts ([foreground-service.md](foreground-service.md)). Already-notified item ids are
kept in SharedPreferences (`maintenance_notified_due_ids`), which survives an isolate
restart and re-arms an item once it stops being due. After every print
`PrintMonitor` also sends one summary reminder, independent of the finish-alert
preferences. The "Mark done" notification button runs in the background through
`handleMaintenanceAction`; how that isolate rebuilds its client and avoids losing the
dedup set is in [notification-delivery.md](notification-delivery.md).

## Statistics

`lib/features/stats/`. Totals come from `GET /archives/stats`; the web's richer
widgets (activity heatmap, records, colours, usage over time, histograms) are
computed in the app from the slim archive list (`archiveSlimProvider`, same date
filter), so no extra contract was needed. Charts use `fl_chart`. Cost is a bare
number: the contract carries no currency symbol. "Most expensive" is filament +
energy + wear, as the web's `RecordsWidget` adds it up.

**Navigation:** the bottom bar is full at five tabs, so an app-level screen goes in
the dashboard drawer (`_AppDrawer`), not on the bar.

**Trap — a blank screen with no error.** `Row(crossAxisAlignment: stretch)` directly
in a vertical `ListView` throws "RenderBox was not laid out" (unbounded cross axis),
then a cascade of null-check errors, and the whole screen renders empty. Wrap the
row in `IntrinsicHeight` (`statistics_screen.dart` does). The app has no custom
`ErrorWidget.builder`, so the failure shows **no red screen**, and its log appears
under `flutter run` only, not in `adb logcat`.

## Two-factor login

A password login on an account with 2FA (TOTP, mailed code or backup code) answers
`requires_2fa` with a `pre_auth_token`, and `POST /auth/2fa/verify` finishes it
(`lib/core/auth/two_factor.dart`, `auth_service.dart`). Two things are invisible in
the contract:

1. **The token is bound to an HttpOnly cookie, `2fa_challenge`**
   (`peek_pre_auth_token` in `mfa.py`). Dio has no cookie jar, so the app copies the
   cookie from the login response's `Set-Cookie` into a `Cookie` header on every
   `/2fa/*` call (`TwoFactorChallenge.cookieHeader`). Without it every correct code
   answers "Invalid or expired pre-auth token". A missing cookie on a token issued
   with a binding is the signature of a reverse proxy stripping `Set-Cookie`, which
   `AuthProbe` logs. `POST /2fa/email/send` also **consumes the token and returns a
   new one**: carry it forward (`withToken`), and keep the old one if the send failed.
2. **The token lives five minutes** (`PRE_AUTH_TOKEN_TTL`) and the body never says
   so. Finding out at the moment of sending the code was a bug caught live (a code
   screen still open after eight minutes), so the controller counts down itself from
   the moment the answer arrived (`TwoFactorChallenge.lifetime`): later than the
   server started, so it never cuts a live challenge short.

Out of scope on purpose: OIDC (a browser and a redirect) and enabling or disabling
2FA from the phone. A session with 2FA cannot be renewed in the background, so the
password is **not remembered** after such a login, and a silent re-login that meets
`requires_2fa` stops trying, forgets the saved credentials and raises the
`twoFactorRequired` sign-in reason with its own message.

**A throwaway server to test any auth change** (no need to touch a real one):

```sh
docker run -d --name bambuddy-2fa -p 8000:8000 -v ./data:/app/data ghcr.io/maziggy/bambuddy:latest
```

Run the setup wizard, enable authentication, turn on TOTP in Settings, and feed the
base32 secret shown there to `oathtool --totp -b <secret>` — no authenticator app
needed. An Android emulator reaches the host at `10.0.2.2:8000`.

## Bug report recording bar

The report feature itself is documented in [diagnostics-log.md](diagnostics-log.md)
and [logging-guide.md](logging-guide.md); the bar lives in the shared package
`app_report_ui` ([shared-packages.md](shared-packages.md)). One trap for whoever
touches how it is mounted: it is placed in `MaterialApp.builder`, **above the
`Navigator`**, so there is no `Overlay` there and a `tooltip:` inside it throws.
Use a `Semantics` label, and in a test mount the widget through `builder:`, not
`home:`.
