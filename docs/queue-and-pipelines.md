# Queue, orders, pipelines and the slice screen

What the server does on these surfaces that the schema does not say. Bulk edit and the
resume banner have their own file: [queue-bulk-and-resume.md](queue-bulk-and-resume.md);
billing's effect on queue writes is in [billing.md](billing.md).

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
