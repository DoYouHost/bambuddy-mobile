# Queue: bulk edit and resume after failure

Two routes the web uses on its queue page and the app did not: `PATCH /queue/bulk`
and `POST /queue/printer/{id}/resume`. Neither needs a version gate — bulk has been
there since v0.1.x, resume since v0.2.4.8 — and both sit behind `can_queue`, so an
API key has them.

## Bulk edit

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
([queue-and-pipelines.md](queue-and-pipelines.md#batch-orders-orders)).

## Resume after failure

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
