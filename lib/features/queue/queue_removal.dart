import '../../core/api/action_outcome.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/models/queue_item.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';

/// How an item leaves the queue — one decision, because no single route takes
/// every status and the app used to offer only one of them.
///
/// The server splits the job across three routes, each refusing what it does
/// not handle (`print_queue.py`): `/cancel` accepts a `pending` item alone,
/// `/stop` a `printing` one alone, and `DELETE` everything except `printing`.
/// The queue's overflow menu offered `/cancel` for all of them, so a row the
/// server held as `printing` — a print that had failed on the machine, its row
/// never reconciled — answered 400 to the only button there was, and the
/// pinned printing card carries no swipe either. That is issue #35: an item
/// with no way out.
enum QueueRemoval {
  /// `POST /queue/{id}/cancel` — the item is still waiting its turn.
  cancel,

  /// `POST /queue/{id}/stop` while the machine is genuinely printing it.
  /// Destructive in the physical sense: it aborts the job on the printer.
  stopPrint,

  /// `POST /queue/{id}/stop` for a row the printer is not showing as running —
  /// the queue says `printing`, the machine says FAILED or IDLE, or the server
  /// has lost contact with it and reports no state at all. Same route, but
  /// nothing is aborted that the app can see, so the user is offered a removal
  /// rather than a stop. Calling it "stop the print" is what confused the
  /// reporter.
  ///
  /// The unreachable printer belongs here rather than with [stopPrint]: the
  /// server cannot deliver a stop to it either, and says so in the answer —
  /// "Queue item cancelled (printer was offline)". So the wording claims only
  /// that the print is not *shown* as running, which stays true whichever of
  /// the three it is.
  stopAbandoned,

  /// `DELETE /queue/{id}` — accepted for every status but `printing`, so it is
  /// the correct route for the terminal ones and for any the app has not seen.
  delete,
}

/// Which removal [status] accepts, given whether the printer is actually busy.
///
/// [printerBusy] is `PrinterStatus.isPrinting` for the item's printer, and
/// only separates the two `/stop` cases — never which route is sent. A printer
/// the app has no status for counts as not busy: an offline one is dropped to
/// no state at all on disconnect (`PrinterStatus.mergedWith`), and that is the
/// case [QueueRemoval.stopAbandoned] is worded for.
QueueRemoval queueRemovalFor(
  QueueItemStatusKind status, {
  required bool printerBusy,
}) =>
    switch (status) {
      QueueItemStatusKind.pending ||
      QueueItemStatusKind.scheduled =>
        QueueRemoval.cancel,
      // `paused` rides with `printing` because the server has no such status
      // of its own — it keeps a paused job `printing` and the pause lives in
      // the printer's state. A server that did set it would refuse `/stop`,
      // and [queueRemovalMessage] is what explains that.
      QueueItemStatusKind.printing || QueueItemStatusKind.paused =>
        printerBusy ? QueueRemoval.stopPrint : QueueRemoval.stopAbandoned,
      _ => QueueRemoval.delete,
    };

/// What the user reads when a removal was refused.
///
/// All three routes refuse on the same ground — the row moved on between the
/// list being drawn and the button being pressed — and each words it
/// differently. The status alone cannot say that: a 400 localizes to "server
/// returned error 400", which is the whole of what the reporter's screen told
/// them. Known refusals are localized, an unknown one is quoted, and no detail
/// falls back to the code. Mirrors `sliceRefusalMessage`
/// (`features/slicer/slice_refusal.dart`).
String? queueRemovalMessage(AppLocalizations l10n, ActionOutcome outcome) =>
    switch (outcome) {
      ActionOk() => null,
      ActionFailed(:final error) => _refusal(l10n, error),
    };

String _refusal(AppLocalizations l10n, AppApiException error) {
  final detail = error.detail;
  if (detail == null || detail.trim().isEmpty) return error.localized(l10n);
  return _localizedRefusal(l10n, detail) ?? detail;
}

/// The server's own wording, matched loosely (`contains`, case-folded) so a
/// version that rewords the tail or names a different status still lands.
String? _localizedRefusal(AppLocalizations l10n, String detail) {
  final d = detail.toLowerCase();
  if (d.contains('cannot cancel item with status') ||
      d.contains('can only stop items that are printing') ||
      d.contains('cannot delete item that is currently printing')) {
    return l10n.queueRemovalStatusChanged;
  }
  return null;
}
