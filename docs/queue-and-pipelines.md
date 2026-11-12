# Queue, orders, pipelines and the slice screen

What the server does on these surfaces that the schema does not say. Billing's effect on
queue writes is in [billing.md](billing.md).

## Leaving the queue: three routes, not one

`print_queue.py` splits it, and each route refuses what the others handle. All three are
stable from `v0.1.2-bugfix` on, so none needs a version gate or a probe.

| Route | Accepts | Refusal (400) |
|---|---|---|
| `POST /queue/{id}/cancel` | `pending` only | `Cannot cancel item with status '<X>'` |
| `POST /queue/{id}/stop` | `printing` only | `Can only stop items that are printing, current status: '<X>'` |
| `DELETE /queue/{id}` | everything except `printing` | `Cannot delete item that is currently printing` |

`queueRemovalFor` (`lib/features/queue/queue_removal.dart`) maps a status to a route;
offering only one left a `printing` row with no way out (issue #35). All the refusals
read as one sentence, `queueRemovalStatusChanged`, because the user's remedy is the same:
the row changed under them, reload.

- The server sets `pending, printing, completed, failed, skipped, cancelled`. There is
  **no `paused`**: a paused print stays `printing` and the pause lives in the printer's
  state. The model tolerates `paused` and `scheduled` anyway, and neither may fall
  through to `delete`.
- `/stop` records the row as `cancelled` **whether or not the stop reached the
  printer**. With the printer offline it answers `Queue item cancelled (printer was
  offline)` and also closes the linked archive (server #2603). The UI words that case as
  "not shown as running" (`QueueRemoval.stopAbandoned`), never as "stopped".
- `dispatching_at` is not in the response schema, so a row mid-dispatch reads `pending`
  and `/cancel` works. That is the intended way out.
- An API key passes `require_ownership_permission` with scope `can_queue` and counts as
  `can_modify_all`, so a 400 here proves authorisation **succeeded**.

## The history: one page from the server, or everything from an older one

`GET /queue/history` (#2960) sorts (`sort_by` date/name/printer, `reverse`) and pages
on the server; `items` is the page followed by the other runs of the batches on it,
so a batch row still counts all of them. "Show more" asks for a longer first page,
as the web does, not the next one. An older server reads the path as
`/queue/{item_id}` and answers 422; `QueueRepository.fetchHistoryPage` then falls back
to the four `?status=` reads for good and the screen sorts and pages them itself
(`serverOrdered: false`), without asking again on a new order. Clearing follows the
same latch: `POST /queue/history/clear` once the route has answered, else one
`DELETE` per row. The contract test reads both generations and replays the clear
button's recorded write on `daily`.

## A queue item's filament type and colour do not pair by index

`filament_type` and `filament_color` on a queue item are comma-joined lists the server
builds separately, and they diverge in both directions (the server paths are named in the
comment above `_requirements()` in `queue_edit_screen.dart`):

- the MQTT fallback (`main.py::_extract_filament_data_from_mqtt`) skips empty slots for
  types, and filters empty **colours** on the colour join alone, so a spool without an RFID
  colour shifts every later colour by one;
- the archive extractor deduplicates both lists independently, so two colours of one
  material give one type and two colours;
- the columns are capped (50 characters for types, 200 for colours).

Neither string says which slot a token belonged to, so the app cannot repair it. It pairs
by position, runs to the longer list, and shows an em dash for a slot with a colour and
no type. A shifted colour in the prefilled override is the known cost. Refusing to pair
whenever the lengths differ was rejected: a shortened list does not say where it was
shortened, so it would also blank rows that are right today. The real fix is server-side
(the same filter on both joins); it has not been reported upstream.

## The filament chips on a queue row

`resolveQueueFilaments` (`lib/features/queue/queue_filaments.dart`) ports the web's
function of the same name in `QueuePage.tsx`. The plate metadata decides which slots
the job uses (`used_in_plate` and `used_grams > 0`), each slot's queue override
replaces only that slot (#3132), and where `ams_mapping` names a tray the chip shows
the tray's live filament and label (`A1 · PETG · Blue`). Before the plates arrive,
or for a file without them, the overrides and then the item's own colour stand in.

A mapped tray gets the warning chip (`A2 · Empty · White`) only when the printer
**positively** reports it empty (`AmsTray.emptyKind` is `empty`): the scheduler
dispatches a stored mapping as-is, so a spool unloaded after queueing sends the job to
an empty slot. Offline, a unit gone, an external input (it sends no presence signal)
and a spool nobody named (#2527) say nothing. Not ported: the backup-spool hand-over
while printing, which needs the status's `tray_change_log`.

## Batch orders (`/orders`)

The screen lists `/queue/batches`: orders with per-plate targets and progress, and
groupings of queue items. `external_source` / `external_ref` exist for integrations (a
retried create from a shop connector gets 409); on a phone they are only a label on the
card. Which route arrived when is in [server-gates.md](server-gates.md) (`batchListing`,
`batchGrouping`, `batchOrders`); before 0.2.3 `/queue/batches` falls into
`GET /queue/{item_id}` and answers **422**.

- **Ownership answers 404, not 403.** Every batch write except `DELETE` is checked
  against the batch's owner and a stranger's batch is "not found" unless the caller holds
  `queue:update_all`; `DELETE` needs `queue:delete_all` for any batch. The 404's `detail`
  is dropped by `mapDioExceptionKeepingDetail`, so tell the cases apart by context
  (`ordersErrGone`), not by text.
- `POST /queue/batches` floors `quantity` at 1 even when it assigned nothing. Count the
  grouped items from `pending_count` + `printing_count`.
- A fulfilled order that is reopened flips straight back to `completed`
  (`refresh_batch_status`), so Reopen is offered only while `remaining_count > 0`.
- **Dispatch has no server-side guard against two concurrent requests**; a second one sent
  before the first commits counts the same owed runs and queues them twice.
  `ordersInFlightProvider` (app-wide, not per card, because a filter switch rebuilds the
  cards) is the only protection, and the edit form takes the same slot so nothing races
  its save.
- Dispatched clones lose their cost center: see
  [billing.md](billing.md#where-a-job-still-cannot-get-one).
- "Group as batch" lives here (the Orders screen's button), not in the queue's selection
  bar.

## Bulk edit and resume after failure

Bulk edit (`PATCH /queue/bulk`) and resume after failure
(`POST /queue/printer/{id}/resume`) are two routes the web's queue page uses. Neither
needs a version gate — bulk has been there since v0.1.x, resume since v0.2.4.8 — and
both sit behind `can_queue`, so an API key has them.

### Bulk edit

**The route answers 200 for work it did not do.** It changes `pending` rows and
only counts the rest (`print_queue.py::bulk_update_queue_items`): rows that are not
pending, rows a dispatch worker has claimed (`dispatching_at`, which the app cannot
see), rows the caller does not own without `queue:update_all`, and rows where
clearing `manual_start` needs a start right the caller lacks. The screen therefore
ends on `queueBulkSummary` — "updated N", then "skipped M" — never on a bare "done".

**A key that was not sent is not touched.** `QueueBulkChanges` carries thirteen
nullable settings, the same thirteen as the web's modal, and `toJson` leaves the
null ones out. The printer is the one three-way field (`kQueueUpdateUnset` leaves
it, `null` unassigns, an `int` assigns). `PrintQueueBulkUpdate` has no
`target_model`, so an "any X" item given a printer here keeps its model, where the
single edit clears it. The web behaves the same.

Where the app differs from the web, each follows the print form's own rule for the
same setting rather than the web modal:

- `auto` is a segment only on a tri-state server, and is **omitted** — never sent as
  a boolean — on an older one (`CalibrationOption.toWire`).
- "Ask for the outcome" is offered only where `queueOutcomeProvider` says the server
  reads it (an older server drops the field silently); the injection row only while
  the server holds snippets.
- There is no "no change" segment. A row with nothing picked is unchanged, and
  tapping the picked value again puts it back: a fourth segment would not fit a
  360 dp screen in every shipped language, and a dash has no accessible name.
- Segment order is Auto / On / Off, as in `QueueCalibrationRow`.

**Selection** is a provider (`queueSelectionProvider`), not the screen's state: the
cards that draw it are rebuilt by every poll. Long press starts it (the archive's
gesture) and only a `pending` row can be picked. An item that stops being pending
leaves the selection by itself, or the count in the bar would promise more than the
route can change. The selection is dropped only after a successful apply, so a
refused edit can be corrected and sent again.

Not built: the web's selection bar also has "Cancel selected" (ask before adding it).
"Group as batch" exists, but on the Orders screen, not in the selection bar
([Batch orders](#batch-orders-orders)).

### Resume after failure

A job queued with `require_previous_success` is skipped when the print before it
fails, with `error_message == 'Previous print failed or was aborted'`
(`kPreviousFailureGate`; the scheduler writes it and the resume route restores by
the same exact comparison). Any other skip reason keeps its own handling.

**The banner needs a request of its own.** The queue the app shows is
`pending` + `printing` (`QueueRepository.fetchActive`), so a skipped row is not in
it. `queueSkippedProvider` asks `GET /queue/?status=skipped`, is reloaded by every
`QueueNotifier.refresh`, and answers nothing for a user without `queue:update_all`
— the route's own requirement and the web's — so the request is not made for them.
`gateBlockedPrinters` is the web's grouping: per printer, by name, skipped rows
with no printer ignored.

Resume goes through plain `guard`, not `guardKeepingDetail`: that keeps `detail` for 400
and 422 only, and this route's refusals are a 403 and a 404.

The route is idempotent: a second call returns zeros. `acknowledged` counts the
failed prints that stopped holding the gate, `restored` the jobs that are `pending`
again; the toast reads `restored`.

Testing: the contract test checks the shape, the 403 for `update_own`, the 404 for a
missing printer and the idempotence, but cannot create a real gate — that needs the
scheduler to skip a job behind a print that fails over FTP. The demo seeds one on the
P1S (items 104–106) so the banner can be seen and the route exercised.

**An "any model" job is not skipped, it waits.** The scheduler passes over a printer
of the model whose last print failed and tries the next; when every free one is
held, the job stays `pending` with `waiting_reason == kModelGateWaitReason`
(`MODEL_GATE_WAIT_REASON`). It never reaches `queueSkippedProvider`, so
`gateBlockedModels` reads the active queue instead — the web's branches: pending, no
printer, a target model, that exact reason. Its banner calls
`POST /queue/model/{model}/resume`, which acknowledges the failures on every printer
of the model the caller may use and restores nothing; the toast is the plain "Queue
resumed". A server older than the route never writes the reason, so the banner and
the route arrive together. The demo's item 108 (any P1S) waits behind the same failed
print; the contract test replays the banner's recorded write on the seeded X1C.

## Slicer pipelines

The routes are `/slicer-pipelines` and `/pipeline-runs`. Presence and permission are
**observed, not versioned**: every pipeline route landed in one server commit and first
shipped as 0.2.4.9, before the renumbering to 1.2.5, so a threshold in either scheme is
wrong for the other. The wire schemas (`schemas/slicer_pipeline.py`,
`schemas/pipeline_run.py`) have no per-version differences the app handles, so
compatibility is only "the routes exist" plus "this session may use them". What a key can
do is in [api-keys-and-settings.md](api-keys-and-settings.md#pipelines).

`PipelinesRepository` holds **three** latches, not one, because a refusal to author is the
normal state of a key session and must not take the rest away:

| Latch | Provider | Settled by |
|---|---|---|
| `readCapability` | `pipelinesSupportedProvider` | the list route (a probe, warmed at start); owns *presence* |
| `runCapability` | `canRunPipelinesProvider` | a 403 on run, cancel or retry |
| `writeCapability` | `canWritePipelinesProvider` | a 403 on create, update, delete or clear |

`canRun` and `canWrite` are "supported **and** their own latch". The pipelines probe races
`/auth/me`: a session without `pipelines:read` sends one probe and meets a 403 before its
permission is known. That is accepted, since waiting would serialise two round trips in
front of the drawer entry.

### Runs: the socket covers slicing only

`pipeline_run_updated` is sent from `routes/pipeline_runs.py` at five transitions: run
created, `slicing`, a failed slice, `dispatching`, and `POST /{id}/cancel`.
`print_scheduler.py` never touches a `PipelineRun`: when a print starts, finishes or
fails, only the `PrintQueueItem` changes. Past `dispatching` the run's status and its
`copies_*` counters exist **only as a roll-up computed on each GET** (`_materialise_run`),
and the event goes to `broadcast_to_user(run.created_by)`, so a session hears only about
runs it started (an install without auth has no `created_by` and broadcasts globally).

Consequences:

- The runs screen's 4 s poll (`pipeline_runs_screen.dart`) is **not** a redundancy to
  remove when the socket is healthy; without it a run stays on `dispatching` forever. It
  runs only while a run is non-terminal and the app is in the foreground.
- `?status=` filters the stored SQL column, i.e. the snapshot, not the roll-up. The filter
  sheet says so.

## The slice screen

- **A refused `POST …/slice` needs two things to reach the user.** The route answers 400
  for three different reasons (a STEP file, a wrong format, an archive without a retained
  model), and `guardKeepingDetail` (used by `SlicerRepository._enqueue`) keeps the
  `detail`. That alone changes nothing on screen; see
  [server-contract-traps.md](server-contract-traps.md#a-400s-detail-takes-two-halves).
  The rules are `sliceRefusalMessage` in `slice_screen.dart`.
- Rule order is load-bearing: `must be stl` comes **before** `step`, because the
  archive route's format refusal reads "must be STL, 3MF, or STEP" and names STEP without
  being about it (`slice_refusal_test.dart` covers it).
- `guard_nozzle_class_reslice` is a no-op on the server (kept "for call-site
  compatibility"); cross-class conversion runs as a two-pass conversion in
  `_run_slicer_with_fallback`. There is no 400 to word.
- A refusal that happens **during** the slice is not a 400: it sits on the job as
  `error_detail` and the progress dialog already shows it.
- **Preset filtering follows the web.** Process and filament presets are filtered with
  `presetCompatibility` (`lib/core/slicer/preset_compatibility.dart`, a port of the web's
  `slicerPrinterMatch.ts`) with no exemption for imported presets, and an empty result
  falls back to the whole list (web #2982: a wrong preset can be changed, an empty list
  cannot). The owned-fleet printer filter goes through the model registry
  (`isConnectedModelPreset`), not a token match: a fleet stored as codes (`X1C`) never
  matched "X1 Carbon" by token. A printer change keeps the filament picks the new printer
  can still use (web #1325).
- The one place it still differs on purpose: the filament sheet's model chips use
  `presetFitsPrinterModel`, a user-chosen facet with no web counterpart.
