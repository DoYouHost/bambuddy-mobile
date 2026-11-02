# Server contract traps

How the bambuddy server really behaves, as opposed to what a reader of the API
would assume. The server source is in `reference/bambuddy` (see AGENTS.md).
**Read it before parsing a new field, touching the WebSocket client or choosing a
feature that must work with an API key.**

## A version number proves nothing

Bambuddy renumbered the `0.2.5` cycle to `1.2.5` mid-way (`0.2.5bN` is a beta of
`1.2.5`), and in the `1.2.6` cycle **every** daily build reports `1.2.6b1`, so features
that landed mid-cycle cannot be told apart by number. **Decide the shape of the
contract from what the server actually sends** (presence of a key, type of a field);
keep the version only as a "nothing seen yet" fallback. Pick the probe from a
**later** commit than the feature in question. The reasoning, the observation →
version → fallback order and every gate's probe are in
[server-gates.md](server-gates.md).

## Times are UTC, even without `Z`

The rule and the helpers are in AGENTS.md and `lib/core/models/json_utils.dart`. The
trap that is not: `serialize_utc_datetime` appends `Z` unconditionally, so the
response to `PATCH /queue/{id}` carries `scheduled_time: "…T16:00:00+00:00Z"` — an
offset and a `Z` together, which `DateTime.tryParse` rejects (null). The same value
on `GET` is fine. Timezone tests only bite with a non-zero offset; the
zone-independent assertion is `isUtc, isFalse`.

A `date_from`/`date_to` that is a calendar day (`YYYY-MM-DD`: archive stats, slim,
failures, supplier and material-number stats) is a day in the server's own `TZ`
unless the request carries `tz`, an IANA zone (server `day_zone`, `local_time.py`).
Every such read goes through `withDayZone`; older servers ignore the parameter. The
print log takes instants instead and needs no zone.

## WebSocket

- Path `wss://host/api/v1/ws` — one multiplexed connection for all printers.
- **Auth since v0.2.4.8 (GHSA-r2qv):** the server requires `?token=` on the handshake
  (validated before `accept()`); the header alone is NOT enough. The token comes from
  `POST /auth/ws-token` (~60 min), via `WsTokenService` and `queryToken` in
  `WsClient`. The app ALSO sends the header, as a fallback for old servers (mint 404 →
  token null → header-only).
- Frame: `{"type":"printer_status","printer_id":N,"data":{…}}` — the field is
  **`data`**, not `status`; `data` has no `id`, `parseWsMessage` injects it.
- `data.temperatures` also carries `*_heating` / `*_target` booleans and the metadata
  `chamber_target_set_time`; the parser skips keys ending in `_time`.
- Heartbeat: client `{"type":"ping"}` about every 30 s, server `pong`.
- **`printer_status` is sent ONLY on change** (dedup by `status_key`). An idle printer
  pushes nothing — 30 s of silence is normal, not a failure. An AMS change broadcast
  deliberately bypasses dedup. While printing, a frame about every 1.1 s (nozzle
  oscillation of ±1–2 °C alone changes `status_key`).
- After a stop by the user the `print_complete` frame carries status `FAILED` (the
  server maps a user stop to it), not `FINISH`; `stg_cur_name` disappears. What the
  monitor sees in `gcode_state` is a different question — see "Print end" in
  [notification-rules.md](notification-rules.md).
- Handled besides `printer_status`: `print_start/complete`, `plate_not_empty`,
  `archive_updated`, `print_confirm_request`, `pipeline_run_updated`,
  `inventory_changed` / `spool_assignment_changed`, `announcements_changed`
  (`ws_messages.dart`). Not handled: `queue_item_uploading`,
  `queue_item_upload_progress`, `queue_item_acked`, `spool_usage_logged`.
- Codes 4000–4008 in the frontend bundle are printer HMS codes, not WebSocket close
  codes.
- Fixture: `test/fixtures/ws_printer_status.json`.

## Auth: what authenticates with what

- **Thumbnails and media do not use the ordinary session header.** Since 1.2.5.5 it is
  a media token (JWT), the `X-API-Key` header (key), or a camera token (older
  server); the only entry point is `MediaAuth`.
- **Check what an API key can do before choosing a feature.** The key is the
  recommended connection mode and the server fails closed on its allowlist, so a
  feature built on a denied permission is dead for the likeliest session. Judge
  **per surface (router prefix), not per route**: `tool/server-ref-diff.sh` prints
  the verdict (`full` / `read-only` / `partial` / `no` / `unresolved`). Readable but
  not writable is a smaller feature (show the readings, configure on the server),
  not a dead one; reject only what is write-only in its purpose.
- **An API key can never do administration**, although `/auth/me` may return an admin
  role for one — do not gate the UI on that field. The closed list lives in
  `backend/app/core/auth.py`: `_APIKEY_DENIED_PERMISSIONS` **and** the absence of an
  entry in `_APIKEY_SCOPE_BY_PERMISSION` (fail closed) — check both. It does not
  depend on the checkboxes when a key is created, so do not advise "add permission X"
  without checking that X can be granted at all. Met so far: `PRINTERS_UPDATE`
  (needed for `PUT /printers/{id}/slot-presets/…`) is denied, so the app skips that
  call when `authMode == apiKey`. Writes blocked for a key are not only settings:
  `SMART_PLUGS_CREATE/UPDATE/DELETE` too (all `/location-ha-sensors/*` writes hang on
  them; reads pass).
- **Twin routes of the two inventory backends have DIFFERENT gates.**
  `POST /inventory/spools/from-slot` sits on `INVENTORY_UPDATE` → scope
  `can_manage_inventory`, so a key passes; its Spoolman counterpart
  `POST /spoolman/spools/from-slot` (note: NOT under `/spoolman/inventory/`) sits on
  `FILAMENTS_UPDATE`, which is not on the allowlist at all → 403 for every key. For
  duplicated features check both routes separately; do not assume parity.
- **A key cannot exceed its owner** (1.2.6+): besides the scope,
  `owner.has_permission(...)` is checked, and keys without an owner (old ones,
  `user_id IS NULL`) run on the flags alone.

## Queue and archive

- **Reorder:** every item defaults to `position == 1` and `POST /queue/reorder`
  expects target positions → send SEQUENTIAL 1..N in the new order (a permutation of
  the existing values is all ones = a no-op).
- `POST /queue/{id}/start` **takes no printer**: to start on a specific one, `PATCH
  printer_id` first, then start. **Not on a job with alternatives** (#671, `variants`):
  that PATCH is a 400, so Start sends the bare `/start` and the scheduler picks the
  candidate. `POST /queue/` answers such a job with `variants: []`; only a read shows
  them (`queue_cross_model_contract_test.dart`).
- **Queueing an archive again** (reprint, add to queue) needs `queue:create` and
  `archives:reprint_all`, or `reprint_own` on the user's own print, never an ownerless
  one (`_assert_can_queue_archive`). The app gates on `archiveReprintBlockProvider`,
  which reads the archive's `created_by_id` (`archive_reprint_contract_test.dart`).
- `GET /archives/search` needs q ≥ 2 characters (422) and **returns 500 on short,
  common terms** (`co`, `X2`, `X2D`) while longer ones work — a server bug; the
  client degrades to a mild message.
- **Leaving the queue is three routes** (`/cancel` pending only, `/stop` printing only,
  `DELETE` everything but printing), and a filament type list does not pair with its
  colour list by index: both in [queue-and-pipelines.md](queue-and-pipelines.md).

## Clearing HMS errors does not clear a standing fault

`POST /printers/{id}/hms/clear` answers `200 {"success": true}` once the command is
**published**. The server sends `clean_print_error` (the on-screen dialog, the 8-char
`print_error` channel) and empties its own `state.hms_errors`, but rebuilds that list from
every report that carries an `hms` array (`bambu_mqtt.py`, the `"hms" in data` branch). A
16-char `hms[]` fault whose cause is still there is reported again within a second or two,
so the 200 proves nothing. Pinned by `test/contract/hms_clear_contract_test.dart`
(issue #56: AMS feed resistance, three clears, three 200s, the fault never left).

Nothing marks a fault as standing or one-off: `actions` says which buttons the printer's
screen offers, `severity` what the fault stops, and neither says whether it will return.
The one reliable split is the channel. So the app does not predict: the clear also asks the
printer to republish (`PrinterCommandsRepository.clearHmsErrors`), then
`hmsStillReported` (`lib/core/printers/hms_readback.dart`) reads the status back up to
three times 1.5 s apart and the toast says how many faults are still listed. The phone
reads it with `fetchStatus` (`ControlsNotifier.clearHmsErrors`), the watch with its own
`getFleet` (`WearActions.clearHmsErrors`) — the relay protocol is unchanged, and a
cached fleet counts as unreadable.

REST, not the socket, because a change in faults alone moves no field of the server's
`status_key` (`main.py`), so an idle printer broadcasts nothing for it.

## An unknown route answers 404 **or** 405

The SPA catch-all is declared as `@app.get("/{full_path:path}")` (`main.py::serve_spa`).
A `POST` to a path the server does not have therefore matches that path with the wrong
method, which Starlette treats as a partial match and answers **405**, never its own 404.
Any "route is absent" probe on a non-`GET` request has to read both
(`CachedTokenService._routeMissing`); one that reads only 404 never fires on an old
server. (A `GET` under `api/` gets the catch-all's own 404.)

Whether a 404 may *record* absence in a latch at all depends on the handler: see
[server-gates.md](server-gates.md#when-a-404-may-record-absence).

## Media credentials

Thumbnails, plate previews, timelapses, print photos, project covers and similar image
routes were moved off the camera stream token by server #3025 (thirteen routes, from
server 1.2.5.5). The camera token costs `camera:view` to mint, and the
new media token carries no identity the route can check, so the old arrangement forced
a camera permission on anyone who wanted a thumbnail. `MediaAuthService`
(`lib/core/api/media_auth.dart`) picks **one of three** credentials:

1. **Server with `POST /auth/media-token`, signed in as a user:** the media token, in
   `?token=`.
2. **Same server, API key:** the `X-API-Key` header. The mint *works* for a key but returns
   a token with an empty username, which `_user_from_media_token` rejects with 401. The
   routes accept the header directly, and `Image.network` (`headers:`) and
   `VideoPlayerController.networkUrl` (`httpHeaders:`) can carry it.
3. **Older server:** the camera token, the only one those builds accept.

- **Detect by the mint's answer, never by version** (404 or 405, see above). The verdict is
  cached (`routeAbsent`) so a page of tiles does not ask an old server for a missing route
  once each. It is cleared by `invalidate()` **and** by `auth(forceRefresh: true)`, so the
  foreground-service isolate, which never calls `invalidate`, still notices a server
  upgraded under it.
- The camera stream routes (`/camera/stream`, snapshot) stay on `CameraTokenService`: a
  separate token and a separate permission.
- **A credential with two halves must not be handed to the call site as two halves.**
  Token in the URL or header: a call site that sees only `source.url` sends no credential
  on a key session, gets 401, and a swallowed `catch` leaves a blank preview while every
  test passes (the timelapse editor did exactly that). Hence `timelapsePlayer()` in
  `timelapse_url.dart` is the only player constructor, with a source scan in
  `timelapse_player_test.dart`.
- **Retry on 401, never on 403.** On these routes every expired credential is a 401
  (`_user_from_media_token`); a 403 is a permission verdict a fresh mint cannot change.
  `MediaAuthImageRecovery` can catch both only because it keeps a latch and fires once;
  `mediaBytes` has no latch and retries 401 alone, or it would double every refused
  request in a background isolate.
- Server-side consequence: archive thumbnails now pass `require_media_token_ownership`, so
  a user without the "all" permission may get a 403 on someone else's row where the camera
  token used to show everything. Intended.

## A 400's detail takes two halves

For a rule the app does not re-implement (the slice route's three 400s, "cannot delete the
last admin user"), the sentence explaining the refusal exists only in the response's
`detail`. Showing it takes **both**:

1. The repository keeps it: `guardKeepingDetail` / `mapDioExceptionKeepingDetail`, which
   keeps `detail` for **400 and 422 only** (a 403's detail is kept by every caller; a 404's
   is dropped, so tell 404s apart by context). A route whose refusals are other statuses
   uses plain `guard`; the resume route is one.
2. The feature words it. `AppApiExceptionL10n.localized` quotes `detail` for 403 only, so a
   400 still reads "error 400" until the feature passes the error through `serverRefusal`
   (`lib/l10n/server_refusal.dart`) with a `RefusalRule` table: a known refusal is matched
   by lower-cased needles and shown from the ARB, an unknown one **quotes the server's
   English** (the most informative thing on screen), and no `detail` falls back to
   `localized`. Order in the table is specificity (see `sliceRefusalMessage`).

Only `AppErrorCode.badResponse` is ever quoted: other failures carry a Dio message
("Connecting timed out") that must not reach the user untranslated.

## Deliberate deviations from the web

The web is the default ([AGENTS.md](../AGENTS.md)); these are the places the app follows
the server's rule or its own on purpose, each decided with the options in front of the
maintainer. Add to the list instead of deviating silently.

- **Start on an ownerless job** is offered to `queue:update_own` (the server claims it,
  server #1670); the web greys it. `queue_providers.dart`.
- **Upload is hidden in a read-only external library folder** (the server answers 403); the
  web offers it. `file_manager_screen.dart`.
- **Linking or unlinking a project's folder** needs `library:update_all`, the server's rule;
  the web has no such control on the project page. `project_detail_sections.dart`.
- **Printer edit, model "Not set"** sends `model: null` and clears the model; the web omits
  the key (`form.model || undefined`) and keeps the old one. `printer_create.dart`.
- **Nozzle-rack picker** keeps the app's two warnings ("the pick no longer fits", "no
  position holds this nozzle"), which the web lacks. `queue_mapping_sheet.dart`.
- **Billing**: no `created_at` on a manual print, a ledger row cannot be taken off its
  center, an empty budget amount means no budget, the ledger pages with "load more"
  instead of page buttons, and the personal center's edit sends only the budget. See
  [billing.md](billing.md).
- **"Dismiss all" reads the status back** and says "the printer still reports N errors"
  when the fault returned; the web shows its "cleared" toast on the 200 alone.
  Phone and watch. [The section above](#clearing-hms-errors-does-not-clear-a-standing-fault).
