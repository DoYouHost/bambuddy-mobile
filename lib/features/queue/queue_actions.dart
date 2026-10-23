import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/app_context.dart';
import '../../core/models/printer.dart';
import '../../core/models/queue_item.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/plate_clear.dart';
import '../dashboard/ws_providers.dart';
import 'queue_mapping_sheet.dart';
import 'queue_providers.dart';
import 'queue_removal.dart';

/// Shared start flow for a queue item, used by the FAB and the ⋮ Start action:
/// assign a printer if the item has none, then the filament-mapping screen
/// (pre-filled, not enforced), then start. Aborts silently if the user backs
/// out of either step.
/// Starts [item], and makes sure a failure is something the user can see.
///
/// The flow runs from a button callback, so anything that escapes it goes to
/// the zone: the print does not start, and the user — who has just picked a
/// printer and mapped the AMS — is told nothing at all. Every step inside words
/// its own refusals; this is the net under the ones nobody predicted.
///
/// [onPrinter] is the printer a job without one starts on, in place of the
/// picker: the controller's. [dialogScale] is the controller body's factor, for
/// the mapping dialog it opens.
Future<void> startQueueItem(
  BuildContext context,
  WidgetRef ref,
  QueueItem item,
  AppLocalizations l10n, {
  int? onPrinter,
  double? dialogScale,
}) async {
  // This flow spans a printer picker, the mapping sheet, a confirmation and two
  // requests, and the row that started it can be gone before any of those come
  // back: the list rebuilds on every WS refresh, and a removed item shrinks it.
  // See [detachFrom].
  final handles = detachFrom(context);
  try {
    await _sendQueuedPrint(
      context,
      ref,
      item,
      l10n,
      handles,
      onPrinter: onPrinter,
      dialogScale: dialogScale,
    );
  } on AppApiException catch (error) {
    showApiFailure(handles.messenger, error, l10n, action: 'queue.start');
  } on Object catch (error, stack) {
    handles.messenger.snack(l10n.connectFailed);
    // Reported rather than swallowed: `ErrorProbe` writes the `err/uncaught`
    // record a bug report about this is read from, and it is the only thing
    // that says *what* failed. Catching without this would trade a silent
    // failure for an unexplainable one, and take the debug console with it.
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'bambuddy queue',
        context: ErrorDescription('starting a queued print'),
      ),
    );
  }
}

Future<void> _sendQueuedPrint(
  BuildContext context,
  WidgetRef ref,
  QueueItem item,
  AppLocalizations l10n,
  DetachedHandles handles, {
  required int? onPrinter,
  required double? dialogScale,
}) async {
  final (:providers, :messenger) = handles;
  // A job with alternatives picks its printer at dispatch, and the server
  // refuses to put one on it (`print_queue.py::update_queue_item`, 400), so it
  // is released as it stands — what the web's Start does for every job.
  if (item.isCrossModel) {
    final result = await providers.read(queueProvider.notifier).start(item.id);
    messenger.snack(queueWriteMessage(l10n, result) ?? l10n.queuePrintStarted);
    return;
  }
  // Only offered with a printer on the job, so it never reaches the picker.
  final claims = providers.read(startClaimsJobProvider(item.createdById));
  var printerId = item.printerId ?? onPrinter;
  if (printerId == null) {
    final printer = await _pickQueuePrinter(context, ref, l10n);
    if (printer == null || !context.mounted) return;
    printerId = printer.id;
  }
  final mapping = claims
      ? const <int>[]
      : await showQueueMappingSheet(
          context,
          item: item,
          printerId: printerId,
          confirmLabel: l10n.queueStart,
          dialogScale: dialogScale,
        );
  if (mapping == null) return; // backed out of mapping → abort

  // Plate-clear gate: when the scheduler requires it and this printer still has
  // a finished job on the plate, confirm + acknowledge (clear-plate) before
  // sending — otherwise the scheduler would hold the print anyway.
  if (await _awaitingPlateClear(providers, printerId)) {
    if (!context.mounted) return;
    final confirmed = await confirmDialog(
      context,
      id: 'queue.plate_clear_confirm',
      title: l10n.plateClearTitle,
      message: l10n.plateClearBody,
      confirmLabel: l10n.plateClearConfirm,
    );
    if (!confirmed) return;
    try {
      await providers
          .read(printerCommandsRepositoryProvider)
          .clearPlate(printerId);
      // The cached status has to hear about it here as much as on the card. The
      // server pushes no frame for a printer with no MQTT client, so on the
      // printer this gate exists for the next start inside the poll window would
      // read the stale `true`, ack a gate that is already down, and take the
      // route's 400 as a reason not to start the print at all.
      providers
          .read(printerStatusesProvider.notifier)
          .plateGateAcknowledged(printerId);
    } on AppApiException catch (e) {
      showApiFailure(
        messenger,
        e,
        l10n,
        action: 'queue.plate_clear',
        message:
            recordPlateClearRefusal(
              providers.read(offlinePlateClearProvider.notifier),
              e.detail,
            )
            ? l10n.plateClearNeedsOnline
            : null,
      );
      return;
    }
  }

  // One thing the container does not guarantee: `queueProvider` is autoDispose,
  // so it outlives this row only because the tab badge in `RootScaffold` keeps
  // it listened to.
  final notifier = providers.read(queueProvider.notifier);
  final result = claims
      ? await notifier.start(item.id)
      : await notifier.startOnPrinter(item, printerId, amsMapping: mapping);
  messenger.snack(queueWriteMessage(l10n, result) ?? l10n.queuePrintStarted);
}

/// Whether [printerId] still has a finished job on the plate AND the scheduler
/// requires plate-clear confirmation — i.e. we must acknowledge clearance
/// before sending. Best-effort: unknown state → no confirmation.
///
/// Prefers the last-known cached status: it survives the printer going offline
/// (`mergedWith` keeps `awaiting_plate_clear` through a disconnect on purpose),
/// whereas a fresh REST fetch can degrade to null for a powered-off printer and
/// wrongly skip the ack. Acking an offline printer is valid — clear-plate is a
/// pure server flag (no MQTT / no online requirement), so the scheduler
/// dispatches the pending job once the printer wakes. Falls back to a fresh
/// fetch only when the printer isn't cached.
///
/// Reads through the container rather than a `WidgetRef` because it runs after
/// the mapping sheet, by which time the row that opened it may be disposed —
/// see [startQueueItem].
Future<bool> _awaitingPlateClear(
  ProviderContainer providers,
  int printerId,
) async {
  final gateEnabled = await settledGate(providers, requirePlateClearProvider);
  if (!gateEnabled) return false;
  final cached = providers.read(printerStatusesProvider)[printerId];
  if (cached != null) {
    return plateClearPending(cached, gateEnabled: () => gateEnabled);
  }
  try {
    final st = await providers
        .read(printersRepositoryProvider)
        .fetchStatus(printerId);
    return plateClearPending(st, gateEnabled: () => gateEnabled);
  } on AppApiException {
    return false;
  }
}

/// Printer picker for the start flow. OFFLINE printers are selectable too —
/// bambuddy wakes them before start. Returns null on cancel / no candidates.
Future<Printer?> _pickQueuePrinter(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final List<PrinterCandidate> candidates;
  try {
    candidates = await ref.read(availablePrintersProvider.future);
  } on AppApiException catch (e) {
    showApiFailure(messenger, e, l10n, action: 'queue.pick_printer');
    return null;
  }
  if (!context.mounted) return null;
  if (candidates.isEmpty) {
    messenger.snack(l10n.queueNoFreePrinters);
    return null;
  }
  return dashSheet<Printer>(
    context,
    scrollControlled: false,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(DashSpace.lg),
            child: Text(
              l10n.pickPrinterTitle,
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
          ),
          for (final c in candidates)
            _PrinterCandidateTile(
              candidate: c,
              onTap: () => Navigator.pop(ctx, c.printer),
            ),
        ],
      ),
    ),
  );
}

/// Printer entry in "start next" picker: name, status (online/offline), and plug
/// icon if printer has smart plug assigned (bambuddy will wake it before start).
/// No explanatory text.
class _PrinterCandidateTile extends StatelessWidget {
  const _PrinterCandidateTile({required this.candidate, required this.onTap});

  final PrinterCandidate candidate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = DashTokens.of(context);
    final p = candidate.printer;
    final offline = !candidate.online;

    return ListTile(
      leading: Icon(
        offline ? Icons.print_disabled_outlined : Icons.print_outlined,
        color: offline ? theme.disabledColor : null,
      ),
      title: Text(p.name),
      subtitle: Text(
        offline ? l10n.offline : l10n.online,
        style: theme.textTheme.bodySmall?.copyWith(
          color: offline ? theme.disabledColor : theme.colorScheme.primary,
        ),
      ),
      trailing: candidate.hasPlug
          ? Icon(Icons.power, color: t.accentGreenInk, size: 20)
          : null,
      onTap: onTap,
    ).tagged('queue.printer_option');
  }
}

/// Confirms, then sends the removal [queueRemovalFor] picked for [item].
///
/// Only [QueueRemoval.cancel] goes straight through: it takes an item that
/// has not started, and undoing it is re-queueing. The other three either
/// abort a running print or drop a row the server will not hand back, so
/// each asks first, in the wording that matches what it actually does.
Future<void> removeFromQueue(
  BuildContext context,
  QueueNotifier notifier,
  ScaffoldMessengerState messenger,
  AppLocalizations l10n, {
  required QueueItem item,
  required QueueRemoval removal,
}) async {
  if (removal != QueueRemoval.cancel) {
    final stopping = removal == QueueRemoval.stopPrint;
    final confirmed = await confirmDialog(
      context,
      id: 'queue.remove_confirm',
      title: stopping ? l10n.queueStopTitle : l10n.queueRemoveStoppedTitle,
      message: stopping ? l10n.queueStopBody : l10n.queueRemoveStoppedBody,
      confirmLabel: stopping ? l10n.queueStopConfirm : l10n.queueDeleteConfirm,
      destructive: true,
    );
    if (!confirmed) return;
  }
  final result = switch (removal) {
    QueueRemoval.cancel => await notifier.cancel(item.id),
    QueueRemoval.stopPrint ||
    QueueRemoval.stopAbandoned => await notifier.stop(item.id),
    QueueRemoval.delete => await notifier.delete(
      item.id,
      logId: 'queue.action.cancel',
    ),
  };
  final failure = queueWriteMessage(l10n, result);
  if (failure != null) {
    messenger.snack(failure);
    return;
  }
  final done = switch (removal) {
    QueueRemoval.stopPrint => l10n.queueStopped,
    QueueRemoval.stopAbandoned || QueueRemoval.delete => l10n.queueRemoved,
    // Cancelling a waiting item stays quiet, as it was before: the row
    // leaving the list is the whole confirmation.
    QueueRemoval.cancel => null,
  };
  if (done != null) messenger.snack(done);
}
