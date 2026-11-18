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

### The Panda Breath (#1466)

A BIQU Panda Breath chamber heater bound to a printer arrives as `panda_breath`
on its status. The server writes the key into every status, with `null` when no
heater is bound, so the field is replaced on each frame, never inherited. An older
server sends no key, so no heater shows and no `ServerFeature` gate is needed; the
`POST /printers/{id}/panda-breath` route arrived together with the field.

The heater runs without the printer, so it outlives the OFFLINE collapse. On a
connected card it is the last tile of the temperature grid, as on the web. On the
collapsed card the grid is gone, so it shows as a row with its own on/off switch.
It appears in one of the two places at a time, never both. A heater the server
reports `online: false` shows a dash, not its last reading, and offers no controls.
The sheet sends one change per request, as the route accepts. Like the web, a
command that goes through closes the sheet with "Sent", and the new state comes
with the next frame. The server's `panda_breath_enabled` switch has no screen in
the app: with it off, the server sends `null` and nothing shows.

### A filament slot row (#64)

The material alone cannot tell slots apart: most users load one material, and three
white PLAs all read `PLA`. A row (`_FilamentRow`) therefore leads with the slot's
name and puts its colour on the line below. The slot number sits inside the
swatch, inked black or white by whichever has the higher contrast (`_inkOn`):
`ThemeData.estimateBrightnessForColor` switches to black only above luminance
0.34, while contrast flips near 0.18, and of 26 typical filament colours it left 9
under 4.5:1, green and orange at 2.9:1.

- **Name**: the preset bambuddy saved when the slot was configured
  (`GET /printers/{id}/slot-presets`, one request per card, present on 1.2.5),
  as the web's slot card leads with it, but only while `slotPresetDescribesTray`
  says it still describes the tray; else the spool assigned to the slot
  (`AssignedSpools.spoolOf`, the chain of `fillOf` without its weight conditions,
  so a spool with no label weight still names it), else `tray_sub_brands`, else
  `tray_type`. A spool the preset pushed out of the name gets a third line in the
  colour's style, so "Generic PLA" in a slot holding an eSun spool shows both.
- **Saving a preset** sends the slot's `tray_info_idx` with it. Without it the
  server records none, and a slot reconfigured on the printer keeps a name that
  no longer describes it.
- **Colour**: the spool's `color_name`, else the catalogue's name for the hex. The
  web's hover card uses the catalogue only; the spool's own name comes first here
  because it is what the user wrote to tell those spools apart, and the queue's
  mapping sheet already does the same.

A slot is its tray id, not its place in the report (`AmsUnit.slotAt`, the web's
`trayForSlot`): an AMS can report only some trays or report them out of order, and
the row's number, fill, name, preset and every slot action follow the id. Only ids
that do not tell the trays apart fall back to the position.

The name is one line by decision: wrapped, a row at 200 % text turned into a block
of text with no hierarchy. A material chip was tried and dropped: the name already
carries the material.

### Nozzle figures (#1908)

A nozzle reports its own wear, print time (`p_t`), status code, temperature rating and
serial in `nozzle_rack`, and the web lists them in a hover card. A phone has no hover, so
two taps open the same rows (`NozzleFigures`, `printer_card_nozzle.dart`), in the web's
order: diameter, type, flow, status, wear, print time, max temp, serial, filament.

- **A rack chip opens a sheet** (`showNozzleSheet`). An empty dock is not a button: the web
  shows a line for it, and there is nothing to show. The touch target is 48 dp, the chip's
  40 plus half the old gap on each side, so the row is no wider than before.
- **A hotend's temperature sheet ends with a "Nozzle" section** (`_NozzleSection`) of four
  rows: diameter, flow, wear, print time. The tile's hardware index is the entry's id: 0 is
  the right head (`nozzle_2`), 1 the left. The sheet already names the hotend, and its
  status is the "Activate" control above, so the rest of the card is left out. A printer is
  dual when it reports `nozzle_2` **or** lists a non-empty id 1: a frame can carry the list
  before the temperature, and the one decision then drives the tile's target index, its
  nozzle switch and its figures. An empty entry proves nothing (a stub), which is argued
  from the H3C capture listing no id 1, not measured on a single-nozzle printer.
- **A figure the nozzle did not report is not a row.** A null print time is older firmware
  or a server before 1.3.1 (the key is absent, 1.3.0 measured), and "0h" would say the
  nozzle never printed; a reported 0 is a row. Max temp 0 and an empty serial are "not set".
- **Material and flow are ported from the web, not from `highFlowFromCode`.**
  `nozzleMaterialOf` is `nozzleTypeName` and `nozzleHighFlowStated` is `nozzleFlowName`: a
  code naming neither `HH` nor `HS` (`HT01`) has no flow row, where `highFlowFromCode` calls
  it standard to rule a queue pick in or out. An unknown type is shown as the printer sent it.
- **Reads only**, so an API key sees all of it (`PRINTERS_READ`).

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

### AI failure detection (`/obico/printer-status`, `/octoeverywhere/printer-status`)

The server watches a print through the camera with one of two providers, Obico
(#1546) or OctoEverywhere (#3169), and the web shows the verdict as a badge on the
printer card. Here it is one item of the print panel's meta row
([ai_detection_item.dart](../lib/features/dashboard/widgets/ai_detection_item.dart)):
an eye and one word, in the class's colour. Read only.

- **Which provider answers is the web's rule** (`aiPrinterStatus` in `PrintersPage.tsx`):
  OctoEverywhere when it is enabled, otherwise Obico. The server refuses to enable
  both (`routes/settings.py`). A server from before OctoEverywhere (1.2.5.7 and
  older) 404s that route and Obico answers alone; one from before Obico's
  `printer-status` (1.2.5 and 1.2.5.1, which have only the `settings:read`
  `/obico/status`) 404s both and the card shows nothing
  (`AiDetectionRepository.fetch`).
- **A feed, not a `capabilityGate`**, for the same reason as the linked apps: the
  payload is the answer, and a 404 or a 403 on either route reads as "nothing to
  show". Neither handler looks up a row by id.
- **`printers:read` is enough**, which a key holds as `can_read_status`. The routes
  were made for the cards and carry no configuration. Without `settings:read` the
  server withholds the reason of an error (it can name a configured URL) and still
  sends the `error` class, so "Not checking" shows either way and only the sentence
  behind it loses its reason.
- **An unknown class is "Starting", never "Safe".** Collapsing everything that is
  not a failure into a green badge is what made a print nothing was looking at read
  as healthy (server #2952). The same for the measurement: Obico's score and
  OctoEverywhere's print quality are quoted only beside a verdict.
- **The two providers are told apart by the `print_quality` key**, as the web does
  (`'print_quality' in aiDetection`): OctoEverywhere sends it as null before its
  first result, Obico never sends it.
- **Polling follows what there is to see** (`aiDetectionProvider`). The print panels
  are its only watchers, so it exists while something prints. Detection that is off
  is asked about once, and again on regained contact and pull-to-refresh; detection
  that is on is re-read every 10 s like the web, while the app is in the foreground
  and the dashboard is the tab on screen (`dashboardWatchedProvider`, which the
  smart-plug poll runs on too). That flag lives outside the notifier because the
  notifier comes and goes with the prints, and one born while the user sits on
  another tab has to start silent.
- **Deviations from the web.** No grey "Idle" badge between prints: the card is
  tall already and the item would say nothing. No detail dialog (frames analysed,
  the settings link): a tap on the item shows the web badge's `title` sentence as a
  tooltip, which is also what a screen reader says. Configuring a provider, its
  history and its test-connection are settings and stay in the web UI. The collapsed
  card, the controller and the watch do not show it.
- Seen on 1.2.5 (neither route), 1.2.5.7 (Obico only) and `dev` at 1.3.2b1
  (both): `ai_detection_contract_test.dart` passes on the last two and, on
  1.2.5, runs only the test that the app reads nothing.
  No print reached the detection loop there, so an entry of `per_printer` is
  checked against the shapes `get_per_printer` builds in both services, not
  against a live one.

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
- That one classification (`lib/core/printers/printer_bucket.dart`) is also what the
  home-screen widgets (`WidgetStatus.keyFor`) and the watch (`wearStateOf`) name a
  printer by: a failed job is finished, a fault is error, an unreported connection is
  offline. What they do with a job — progress, ETA, pause and stop — follows
  `PrinterStatus.isJobActive`, not the bucket, so a printing machine with a fault
  keeps its Stop. Progress is `PrinterStatus.progressPercent` everywhere: the server
  sends a percentage, never a fraction.
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

## Linked apps (`/api/v1/external-links/`)

The web sidebar's other apps (Bambuddy Orders, Spoolman, a wiki), with the count each
app reports for itself. One drawer tile, one screen, read only
([external_links_screen.dart](../lib/features/links/external_links_screen.dart)).

- **The write is not ours.** `PUT /external-links/badge` is for the app a link points at
  (`can_send_notifications`); this app is never that app. Creating, editing and ordering a
  link are outside the API-key scope allowlist and stay in the web UI.
- **Reading is `external_links:read`, a key holds it as `can_read_status`.** The tile is
  gated on that permission and on the list being non-empty; a 403 or a 404 on the list
  both read as "no links" (`ExternalLinksRepository.fetch`), because the list handler
  looks up no row by id. This is a feed, not a `capabilityGate`: the screen needs the
  payload anyway, as Manyfold's tab does ([server-gates.md](server-gates.md)).
  `externalLinksProvider` is warmed by the shell so the tile is in the drawer's first
  frame, and re-read when the drawer opens, because a count moves while the app stays open.
- **A count is hidden at 0 and when absent**, and capped at `99+`, as the web's sidebar
  does (`Layout.tsx`, `badge_count ?? 0`). The server drops a count ten minutes after its
  app last reported (`BADGE_FRESH_FOR`), so an absent one means "stopped reporting", not
  zero. The pill is amber, as on the web. The drawer tile carries the sum of all counts.
- **Deviations from the web.** Every link opens in the browser: the web shows the ones with
  `open_in_new_tab` off in a frame, which a phone has no place for. A link's Lucide icon
  name is not mapped to a Material icon; an uploaded picture is drawn through `MediaImage`
  and the name's first letter stands in when there is none, while it loads and when it
  cannot be drawn (an SVG, which `Image.network` does not decode). Order is the server's
  `sort_order`, not the user's own sidebar order.
- **A URL can carry a login** (`http://user:pass@host`). It is opened but never shown or
  logged: `ExternalLink.address` is host and port only. A scheme other than http(s) is
  refused by `openWebLink` before anything is launched.
- Seen on `:latest` (1.2.5.7) and `:daily` (1.3.1b1): the route and the list exist on
  both; only `daily` has `badge_count` and `PUT /badge`. `external_links_contract_test.dart`
  passes on both and skips the badge half on the older one.

## Bug report recording bar

The report feature itself is documented in [diagnostics-log.md](diagnostics-log.md)
and [logging-guide.md](logging-guide.md); the bar lives in the shared package
`app_report_ui` ([dependency-upgrades.md](dependency-upgrades.md#shared-packages-app-shared)). One trap for whoever
touches how it is mounted: it is placed in `MaterialApp.builder`, **above the
`Navigator`**, so there is no `Overlay` there and a `tooltip:` inside it throws.
Use a `Semantics` label, and in a test mount the widget through `builder:`, not
`home:`.
