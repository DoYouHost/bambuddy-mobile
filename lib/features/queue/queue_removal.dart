import '../../core/api/action_outcome.dart';
import '../../core/models/queue_item.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/server_refusal.dart';

/// How an item leaves the queue. The server splits that across three routes,
/// each refusing what it does not handle (`print_queue.py`), so offering only
/// one of them left a `printing` row with no way out at all (issue #35).
enum QueueRemoval {
  /// `POST /queue/{id}/cancel` — accepted for a `pending` item alone.
  cancel,

  /// `POST /queue/{id}/stop` while the machine is printing it: this aborts a
  /// physical job.
  stopPrint,

  /// `POST /queue/{id}/stop` for a row the printer is not showing as running.
  ///
  /// An unreachable printer belongs here rather than with [stopPrint]: the
  /// server cannot deliver a stop to it either, and answers "Queue item
  /// cancelled (printer was offline)". Hence wording that claims only that the
  /// print is not *shown* as running, true for FAILED, IDLE and no contact
  /// alike.
  stopAbandoned,

  /// `DELETE /queue/{id}` — refused for `printing` and accepted for every
  /// other status, including the ones this app has no case for (`skipped`).
  delete,
}

/// Which removal [status] accepts. [printerBusy] is `PrinterStatus.isPrinting`
/// for the item's printer and only picks between the two `/stop` wordings,
/// never the route; no status at all counts as not busy, which is what an
/// offline printer degrades to (`PrinterStatus.mergedWith`).
QueueRemoval queueRemovalFor(
  QueueItemStatusKind status, {
  required bool printerBusy,
}) =>
    switch (status) {
      QueueItemStatusKind.pending ||
      QueueItemStatusKind.scheduled =>
        QueueRemoval.cancel,
      // The server has no `paused` status — it keeps such a job `printing` —
      // so the model's tolerance for one must not fall through to `delete`.
      QueueItemStatusKind.printing || QueueItemStatusKind.paused =>
        printerBusy ? QueueRemoval.stopPrint : QueueRemoval.stopAbandoned,
      _ => QueueRemoval.delete,
    };

/// The queue screen's one way from an [ActionOutcome] to a sentence.
String? queueWriteMessage(AppLocalizations l10n, ActionOutcome outcome) =>
    outcomeRefusal(l10n, outcome, _rules);

/// Three routes, three phrasings of "that is not the status I found", and one
/// thing the user has to do about it.
final _rules = <RefusalRule>[
  for (final phrase in const [
    'cannot cancel item with status',
    'can only stop items that are printing',
    'cannot delete item that is currently printing',
  ])
    ([phrase], (l10n) => l10n.queueRemovalStatusChanged),
];
