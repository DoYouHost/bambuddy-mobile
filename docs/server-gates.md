# Server gates — what each one is for

Every row of `ServerVersion.introducedIn`
([lib/core/api/server_version.dart](../lib/core/api/server_version.dart)) says
which bambuddy release introduced a capability. This file says **why that row
exists**, what an older server does without it, and what it costs to be on the
wrong side of the threshold. The enum keeps one line per member; the argument
lives here.

Read this before adding a gate — most of the work is deciding whether you need
one at all.

## When a version gate is the wrong tool

A threshold is the weakest of the three answers the app has. Prefer, in order:

1. **A refusal (403).** The route is there and this session may not use it — a
   question no version can answer.
2. **An observation.** The server revealed the capability in its own payload, or
   answered 404 to the whole route family. Same question answered outright
   rather than inferred from a number.
3. **The version table**, for before anything has been seen — and for the one
   case (`chamberMaxTargetC`) where nothing can ever be seen.

`ObservedCapability` implements that order. A gate is only load-bearing where
being wrong is expensive **before the first reply comes back**, or where the
server gives no sign at all.

The case that forces a gate is the **silent drop**: FastAPI models that do not
forbid extra fields take an unknown field, say nothing, and ignore it. A control
that appears to work and changes nothing is worse than no control, and no reply
distinguishes the two — so nothing can be observed and the version has to
decide.

## Reading the thresholds

- **Numeric base only** (`major, minor, patch, micro`). `supports()` compares
  nothing else, deliberately: a feature ships during its release's beta cycle,
  so `1.2.6b1` has to count as 1.2.6. The alternative takes `auto` away from a
  server that stores it.
- Most rows below landed *inside* the 1.2.6 beta cycle, which the numeric base
  cannot split any finer. Where that matters, the row says what being early
  costs.
- **One row is in the old numbering** (`printerSensorHistory`, `0.2.4.8`). The
  project renumbered the 0.2.5 cycle to 1.2.5 partway through; every 1.x
  outranks 0.2.4.8, so a single row covers both schemes. Written as `(1, 2, 4,
  8)` it would hide the chart on exactly the 0.2.4.x servers that serve the
  route.
- An unmapped feature answers **no**. That is a programming error —
  `server_version_test.dart` fails on a missing row — but answering no keeps the
  app on the contract every server generation accepts.

## The gates

### triStateCalibration — 1.2.5

Queue and settings store `bed_levelling` / `flow_cali` / `nozzle_offset_cali` as
`off`/`on`/`auto` instead of booleans. Sending `auto` to a server that stores
booleans is a **422**, so this one is refused rather than dropped.
`QueueRepository.triStateCapability` reads the real answer off the
payload and outranks the row.

### chamberTemp65 — 1.2.6 (server commit b04664c6)

`MAX_CHAMBER_TEMP_C` 60 → 65. The one gate that is a *value* rather than a
yes/no, and the one that can never be settled by observation: no response
reveals the ceiling, and the only probe would be a real command heating
somebody's chamber to ask a question. The bound is a `Query(le=…)`, so an older
server answers **422** for 61–65 rather than clamping. 60 whenever the version
is unknown.

### crossModelVariants — 1.2.6 (server #671)

`POST /library/variant-groups` and the `variants[]` field on queue create:
several sliced files, one job, whichever printer frees up first.
`LibraryRepository.variantsCapability` observes it and outranks the row.

### sliceLayoutOptions — 1.2.6 (server #2548)

`auto_orient` / `auto_arrange` on `SliceRequest`. **The reference silent drop:**
`SliceRequest` does not forbid unknown fields, so an older server drops these
without a word. The controls must be *hidden*, not merely left unsent.

### processOverrides — 1.2.6

`process_overrides` on `SliceRequest`, plus the `GET /slicer/preset-values` that
seeds the panel. Same silent-drop hazard as `sliceLayoutOptions`, but the
endpoint 404s on older servers, which `SlicerRepository` uses as the outranking
observation.

### printerSensorHistory — 0.2.4.8 (server commit 090c180e)

`GET /printer-sensor-history/{id}` — recorded nozzle / bed / chamber readings
behind the temperature tiles' chart shortcut. The route 404s before it, and
reading it also needs `printer_sensor_history:read`, so `HeaterHistoryRepository`
treats both answers as outranking the row: a version cannot see a permission.
See **Reading the thresholds** for why this row is in the old numbering.

### usersSlimListing — 1.2.6 (server #1894)

`GET /users/slim` — id + username only, so `created_by_id` can be shown as a
name.

**Listed for completeness; `StatsRepository` decides by probing and that must
not be replaced with this row.** Two reasons, both load-bearing:

- The route existing is not the same as *this session* being allowed to read it.
  A 1.2.6 server still answers 403 to a caller holding neither `users:read_slim`
  nor `users:read`; the probe covers both questions where a version answers only
  the first.
- Using the row to skip the attempt would resurrect the numbering trap: a server
  whose reported version parses below 1.2.6 while actually serving the route
  would be pinned to the full listing forever — which an API key is refused
  outright, removing exactly the picker #1894 added.

### printLogCostEnergy — 1.2.6 (server #2636, commit a08d3e62)

`cost` / `energy_kwh` / `energy_cost` on a print-log entry, and the `sort_by` /
`sort_dir` query params that go with them. Both halves are silent below it, in
the two different ways that make a gate necessary rather than optional:

- The three fields were written to the table all along but never named by the
  serialiser, so they arrive **absent** — which parses as `null`, exactly like a
  run made without a smart plug. Showing the columns anyway would put "no energy
  recorded" against every row of a server that records it.
- `sort_by` on an older server is an unknown query param, and FastAPI drops
  those: the list comes back `created_at desc` whatever was asked for.

### labelStartingPosition — 1.2.6 (server #2879)

`starting_position` on `POST /inventory/labels` / `POST /spoolman/labels` —
resume a part-used Avery sheet instead of always printing from slot 1.

Gated for the same reason as `sliceLayoutOptions`: `LabelRequest` forbids no
extra fields, so an older server takes the number, says nothing, and prints from
position 1 anyway. Nothing in the reply distinguishes the two — both are a valid
PDF — so there is no observation to prefer over the row. A 1.2.6b1 daily older
than the commit is told yes and prints from position 1, which is the same sheet
it prints today: being early costs a wasted sheet of labels, not a refused
request.

### printerFilesDownloadJob — 1.2.6 (server #2850)

`POST /printers/{id}/files/download-job` and the two routes that go with it — a
printer-file download prepared in the background instead of behind a held
request. A route family, so an older server answers **404** and
`PrinterFilesRepository` prefers that observation. Being early costs nothing
either way: the legacy `download-zip` is on every server, including the newest,
and is what the app falls back to.

### scheduledDryings — 1.2.6 (server #2638, commit d37ce94f)

`GET/POST/DELETE /scheduled-dryings` — a manual AMS drying run the scheduler
starts later. A route family, so `ScheduledDryingRepository` prefers the 404.
The gate exists for the moment before the first listing comes back: the drying
sheet has to decide whether to offer "Later" at all, and an offer that ends in a
404 costs the user a filled-in form.

### archivePrinterMedia — 1.2.6 (server #2853, commit 55cc64c8)

`GET /archives/{id}/printer-media` and the media-download token pair — the
recordings a finished print can still be given, off the printer's own storage. A
route family, so `ArchiveRepository` prefers the 404. Being early would cost a
sheet that opens onto nothing, so the archive hides the entry until this says
yes.

### locationHaSensors — 1.2.6 (server #2827, commit 54af3146)

`GET /location-ha-sensors/` and the per-location readings behind it — the
thermometer or hygrometer a storage location can be given, read through the
server's Home Assistant connection. A route family, so
`LocationSensorsRepository` prefers the 404. The gate only spares that one 404 on
a server known to be older: nothing is offered until the listing comes back
non-empty, so being early costs a request and never a control.

### spoolModelPresets — 1.2.6 (server commit a7b56333)

`GET/PUT /inventory/spools/{id}/filament-presets` and the Spoolman twin — the
slicer preset a spool uses on one printer *model*, instead of the one value it
carries for the whole fleet. A route pair, so `InventoryRepository` prefers the
404. Being early costs a section offering to write where the write would 404, so
the spool form hides it until this says yes.

## From latch to screen

How an answer is decided is `ObservedCapability` (above). How it reaches a
widget is one path, the same for every capability:

```
repository                      lib/providers.dart                     screen
ObservedCapability ──notifies──► capabilityGate(latch) ──────────────► .orFalse / .offer
  (watching / probe)               ▲                ▲                  settledGate (outside a build)
                        serverVersionProvider   serverContactEpochProvider
```

- **The latch lives in its repository** (`xCapability`) and is settled by the
  requests that repository already makes, through `watching(...)` with the
  `observing:` its handler warrants. A capability the server never shows
  (`printLogCostEnergy`, `labelStartingPosition`, `sliceLayoutOptions`) still
  gets a latch — never observed, so the version row decides — to keep one shape.
- **`capabilityGate`** turns it into a `Provider<AsyncValue<bool>>`, derived
  synchronously: no loading frame once the answer is known, and an observation
  reaches the screen the moment the latch records it — no invalidation, no
  `autoDispose` to "ask again". Loading only while the version read or a probe
  is out, and not even then for `whenUnknown: true` (the control is shown while
  unknown, so it is shown while waiting too). A repository that cannot be built
  (no profile) is `AsyncError`, which every reader folds into "no".
- **`serverVersionProvider`** is read once for the shell (`warmServerAnswers`
  in `root_scaffold.dart`) rather than by the first widget that needs it.
- **`serverContactEpochProvider`** counts regained contacts: bumped by
  `PrinterStatusesNotifier` on the first WebSocket frame or poll after a gap,
  including every return from the background. A version read or a probe that
  met no network is asked again once per bump — an app started away from the
  LAN recovers without a restart.
- **`refusalsForgottenProvider`** is bumped by the dashboard's pull-to-refresh:
  every gate drops the refusals its latch recorded before it. A control a 403
  hid never calls its route again, so a permission granted on the server would
  otherwise wait for a restart. Refusals only — a 404 is the server, and the
  repositories (with their data) stay.
- **A probe** (`ObservedCapability.unversioned(probe: …)`) is for a gate that
  hides an entry point nothing else asks about early — pipelines, whose drawer
  tile is built only when the drawer opens. Warm it in `warmServerAnswers`.
  Anything a screen fetches anyway needs no probe: the tag catalog, kept
  watched by the file manager, settles the tags latch.

Reading a gate:

| Situation | Read |
|---|---|
| Entry point to a route that may not exist | `.orFalse` — hidden while unknown |
| A button the user waits to press | `.offer` — disabled while unknown |
| Should be shown while unknown | `whenUnknown: true` on the **latch**, then `.orFalse` |
| Code outside a build | `await settledGate(container, gate)`, the container taken before the first `await`; a flow started unawaited reads an error as "no" (`.catchError((Object _) => false)`) |
| An async provider that depends on it | watch the gate and **stay loading** while it is unanswered — never resolve an empty value from "unknown" (`spoolPresetOverridesProvider`: a form seeds from it once and a save replaces the whole list) |

Combining: `a.and(b)` — a settled "no" on either side wins, an error is handed
on. It evaluates both sides, so a synchronous "no" that has to save a request
(`canUsePipelinesProvider` before the pipelines probe) is an `if` before the
watch, not the left side of `and`.

`capability_gate_shape_test.dart` fails on a `FutureProvider<bool>` gate and on
a `maybeWhen(data: (v) => v, …)` read.

Not on this path, on purpose: gates over `/settings` (`serverGate`, same idea
over one warmed fetch), permissions from `/auth/me` (enter a gate as a
synchronous input), and latches that choose *how* to call rather than whether a
control exists (download jobs, media token, `StatsRepository._hasSlimListing`).

## Adding a gate

1. Find out what an older server actually does: refuse (422/400), 404 the route,
   or take the field and ignore it. The server source at
   `reference/bambuddy` answers this; `model_config` / `extra` on the request
   schema is what decides between the last two.
2. If the server gives *any* sign, prefer `ObservedCapability` and give the row
   only as its fallback.
3. Add the enum member, a row in `introducedIn`, and a section here.
   `server_version_test.dart` fails on a member with no row, and its
   `supports()` test lists every 1.2.6 member — add yours there too.
4. Put the latch in the repository and route every call that can settle it
   through `watching(...)`. A 404 settles it only on a handler that raises no
   404 of its own — read the handler, then pass `observing: treat404AsAbsent`.
5. One line in the providers: `capabilityGate((ref) =>
   ref.watch(xRepositoryProvider).xCapability)`. Read it as in the table above.
6. A probe and a `warmServerAnswers` entry only if it hides an entry point that
   nothing fetches before the user reaches it.
7. Tests: the latch in the repository test, with a mocked version service — a
   latch test without one reads `false` from the start and proves nothing; the
   screen with `gate.overrideWithValue(const AsyncData(...))`.
