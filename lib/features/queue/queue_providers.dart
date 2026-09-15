import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/action_outcome.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/models/available_filament.dart';
import '../../core/models/printer.dart';
import '../../core/models/printer_status.dart';
import '../../core/models/queue_item.dart';
import '../../data/queue_repository.dart';
import '../../providers.dart';

/// One-shot live status for a printer (AMS slots, connectivity), keyed by id.
/// Used by the queue filament-mapping sheet to list loaded AMS filaments.
final printerStatusOnceProvider = FutureProvider.autoDispose
    .family<PrinterStatus?, int>(
      (ref, printerId) =>
          ref.watch(printersRepositoryProvider).fetchStatus(printerId),
    );

final queueProvider =
    AutoDisposeAsyncNotifierProvider<QueueNotifier, List<QueueItem>>(
      QueueNotifier.new,
    );

/// Print queue (M5). Shows only ACTIVE items (pending, scheduled, printing, paused)
/// sorted by `position` — history (completed/cancelled) lives in archive, not queue.
///
/// Reorder and delete are optimistic with rollback (M4's `ControlsNotifier` pattern):
/// UI responds immediately, error reverts change. Start/cancel change server state
/// (start triggers physical print!), so we fetch fresh list on success instead of guessing.
class QueueNotifier extends AutoDisposeAsyncNotifier<List<QueueItem>> {
  @override
  Future<List<QueueItem>> build() async {
    // Rebuild on server profile change (different key/permissions). No profile
    // (e.g. right after "change server", before the router swaps to /setup) →
    // apiClientProvider throws, so short-circuit to an empty queue instead.
    final profile = ref.watch(serverProfileProvider);
    if (profile == null) return const [];
    final all = await ref.read(queueRepositoryProvider).fetchActive();
    return _activeSorted(all);
  }

  static int _printingFirst(QueueItem i) =>
      i.statusKind == QueueItemStatusKind.printing ? 0 : 1;

  List<QueueItem> _activeSorted(List<QueueItem> items) {
    // Printing always on top (pinned, non-reorderable in UI), then rest by
    // `position` with `id` as tiebreaker: server defaults all to `position == 1`
    // until queue is arranged, so stable tiebreaker is needed or order is undefined.
    return items.where((i) => i.isActive).toList()..sort((a, b) {
      final byPrinting = _printingFirst(a).compareTo(_printingFirst(b));
      if (byPrinting != 0) return byPrinting;
      final byPos = a.position.compareTo(b.position);
      return byPos != 0 ? byPos : a.id.compareTo(b.id);
    });
  }

  /// Pull-to-refresh / refresh after mutation. Keeps previous list underneath
  /// (AsyncLoading with previous) so UI doesn't flicker with spinner.
  Future<void> refresh() async {
    // No profile (mid server-change) → nothing to fetch; mirrors [build].
    if (ref.read(serverProfileProvider) == null) return;
    state = const AsyncValue<List<QueueItem>>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(
      () async =>
          _activeSorted(await ref.read(queueRepositoryProvider).fetchActive()),
    );
  }

  /// Optimistic reorder (drag&drop). Indices in `onReorderItem` convention from
  /// `ReorderableListView` — `newIndex` is already adjusted for removing from
  /// `oldIndex`, so insert without additional correction. Send SEQUENTIAL positions
  /// 1..N in new order to server — "bulk update positions" endpoint expects target
  /// values, and all items default to `position == 1` (verified live, see reorder in
  /// contract). Error → rollback to pre-drag order, see [_inOrderOf].
  Future<ActionOutcome> reorder(int oldIndex, int newIndex) async {
    final current = state.valueOrNull;
    // No rows are rendered while the queue is unloaded, so there was nothing
    // to drag: nothing was sent and there is nothing to report.
    if (current == null || oldIndex == newIndex) return ActionOutcome.ok;

    final list = [...current];
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    state = AsyncValue.data(list); // optimistic

    final payload = [
      for (var i = 0; i < list.length; i++) (id: list[i].id, position: i + 1),
    ];
    try {
      await ref.read(queueRepositoryProvider).reorder(payload);
      return ActionOutcome.ok;
    } catch (e) {
      final live = state.valueOrNull;
      if (live != null) state = AsyncValue.data(_inOrderOf(current, live));
      if (e is! AppApiException) rethrow;
      return ActionOutcome.failed(e, action: 'queue.reorder');
    }
  }

  /// The rows as they are *now*, in the order [before] showed them — the
  /// rollback for both optimistic edits. Putting [before] itself back would
  /// also resurrect a row deleted, or finished by a refresh, while the request
  /// was in the air.
  ///
  /// Not [_activeSorted]: a reorder that succeeded leaves the rows' `position`
  /// fields as they were, so sorting by them would undo it.
  List<QueueItem> _inOrderOf(List<QueueItem> before, List<QueueItem> rows) {
    final slot = {for (final (i, item) in before.indexed) item.id: i};
    // A row a refresh brought in has no old slot and keeps its order behind
    // the known ones.
    final rank = {
      for (final (i, item) in rows.indexed)
        item.id: slot[item.id] ?? before.length + i,
    };
    return [...rows]..sort((a, b) {
      final byPrinting = _printingFirst(a).compareTo(_printingFirst(b));
      return byPrinting != 0 ? byPrinting : rank[a.id]!.compareTo(rank[b.id]!);
    });
  }

  /// Optimistic delete (swipe-to-delete). Error → restore item.
  ///
  /// [logId] is the control the user touched: the swipe is one door, the
  /// overflow menu's removal is the other, and a failure that reports as the
  /// swipe from either would send anyone reading the log to the wrong widget.
  Future<ActionOutcome> delete(
    int itemId, {
    String logId = 'queue.swipe_delete',
  }) async {
    final current = state.valueOrNull;
    if (current == null) return ActionOutcome.ok; // nothing rendered to swipe

    final index = current.indexWhere((i) => i.id == itemId);

    if (index >= 0) state = AsyncValue.data([...current]..removeAt(index));
    try {
      await ref.read(queueRepositoryProvider).delete(itemId);
      return ActionOutcome.ok;
    } catch (e) {
      // Any failure puts the row back; only a refusal is an answer.
      if (index >= 0) _putBack(current[index], current);
      if (e is! AppApiException) rethrow;
      return ActionOutcome.failed(e, action: logId);
    }
  }

  /// Rollback of one optimistic removal into the list as it is *now*, in the
  /// order the swipe was made on — see [_inOrderOf].
  void _putBack(QueueItem item, List<QueueItem> before) {
    final list = state.valueOrNull;
    // A refresh that landed meanwhile already holds the row the server kept.
    if (list == null || list.any((i) => i.id == item.id)) return;
    state = AsyncValue.data(_inOrderOf(before, [...list, item]));
  }

  /// Manually start item — triggers physical print. On success, fetch fresh list
  /// (status changes server-side).
  Future<ActionOutcome> start(int itemId) => _serverAction(
    () => ref.read(queueRepositoryProvider).start(itemId),
    'queue.start',
  );

  /// Cancel queue item. On success, refresh list.
  Future<ActionOutcome> cancel(int itemId) => _serverAction(
    () => ref.read(queueRepositoryProvider).cancel(itemId),
    'queue.cancel',
  );

  /// Stop the print a `printing` item is running, which also drops it from the
  /// queue — the only route that clears such a row. On success, refresh list.
  ///
  /// Not optimistic like [delete]: the server decides whether the row ends up
  /// `cancelled` or refuses outright, and the refreshed list is the answer.
  Future<ActionOutcome> stop(int itemId) => _serverAction(
    () => ref.read(queueRepositoryProvider).stop(itemId),
    'queue.stop',
  );

  /// Persist a filament→AMS-slot mapping without starting (e.g. for items the
  /// queue may auto-dispatch later). On success, refresh list.
  Future<ActionOutcome> saveMapping(int itemId, List<int> mapping) =>
      _serverAction(
        () => ref.read(queueRepositoryProvider).setAmsMapping(itemId, mapping),
        'queue.save_mapping',
      );

  /// Put [item] on the indicated (free) printer and start it — triggers a
  /// physical print. See [QueueRepository.startOnPrinter], which also undoes the
  /// assignment when the start is refused. [amsMapping] (optional) sets the
  /// filament→AMS-slot mapping before starting; `-1` entries mean "auto". On
  /// success, refresh list.
  Future<ActionOutcome> startOnPrinter(
    QueueItem item,
    int printerId, {
    List<int>? amsMapping,
  }) => _serverAction(
    () => ref
        .read(queueRepositoryProvider)
        .startOnPrinter(item, printerId, amsMapping: amsMapping),
    'queue.start_on_printer',
  );

  /// Run an arbitrary repository mutation, then refresh on success. Used by the
  /// Edit Queue Item screen, which builds its own `PATCH` body via
  /// [QueueRepository.updateItem]. Error → mapped [ActionOutcome].
  /// [logId] is the control the caller offered, so the seven mutations behind
  /// this notifier do not all report as one tag.
  Future<ActionOutcome> runOnRepository(
    Future<void> Function(QueueRepository repo) action,
    String logId,
  ) => _serverAction(() => action(ref.read(queueRepositoryProvider)), logId);

  Future<ActionOutcome> _serverAction(
    Future<void> Function() send,
    String logId,
  ) => runAction(send, logId: logId, onSuccess: refresh);
}

/// Candidate for target printer in "start next". Carries printer itself plus
/// whether it's currently online and has smart plug assigned — so UI can mark
/// OFFLINE printers (bambuddy will wake them before start).
typedef PrinterCandidate = ({Printer printer, bool online, bool hasPlug});

/// All printers regardless of state, for the Edit Queue Item target picker.
/// Unlike [availablePrintersProvider] it does NOT drop busy/printing printers,
/// so the item's currently-assigned printer is always present and selectable
/// (mirrors the web edit modal's `showInactive`).
final allPrintersProvider = FutureProvider.autoDispose<List<Printer>>((
  ref,
) async {
  final all = await ref.watch(printersRepositoryProvider).fetchAll();
  return [for (final p in all) p.printer];
});

/// Filaments loaded on active printers of a model, for the Edit Queue Item
/// filament-override dropdowns. Keyed by `(model, location)` — location `''`
/// means no filter.
final availableFilamentsProvider = FutureProvider.autoDispose
    .family<List<AvailableFilament>, (String, String)>(
      (ref, key) => ref
          .watch(printersRepositoryProvider)
          .fetchAvailableFilaments(
            key.$1,
            location: key.$2.isEmpty ? null : key.$2,
          ),
    );

/// Printers available to start next print on. Only exclude those ACTUALLY busy
/// (printing/paused) — OFFLINE printers stay in list because bambuddy will wake
/// them before start (with own smart plug or otherwise). Fetches printers + statuses
/// + plug map fresh on each call (autoDispose) because availability changes over time.
final availablePrintersProvider =
    FutureProvider.autoDispose<List<PrinterCandidate>>((ref) async {
      final all = await ref.watch(printersRepositoryProvider).fetchAll();

      // Plug assignments are optional enrichment — their absence/failure can't block
      // printer selection, so treat error as "no plugs".
      Set<int> printersWithPlug = const {};
      try {
        final plugs = await ref.read(smartPlugsRepositoryProvider).fetchPlugs();
        printersWithPlug = {
          for (final plug in plugs)
            if ((plug.enabled ?? true) && plug.printerId != null)
              plug.printerId!,
        };
      } on AppApiException {
        // Leave empty set — no plug markings
      }

      return [
        for (final p in all)
          if (!(p.status?.isPrinting ?? false) &&
              !(p.status?.isPaused ?? false))
            (
              printer: p.printer,
              online: p.status?.connected ?? false,
              hasPlug: printersWithPlug.contains(p.printer.id),
            ),
      ];
    });
