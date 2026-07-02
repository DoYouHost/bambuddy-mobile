import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/printer.dart';
import '../../core/models/printer_status.dart';
import '../../core/models/queue_item.dart';
import '../../providers.dart';

/// One-shot live status for a printer (AMS slots, connectivity), keyed by id.
/// Used by the queue filament-mapping sheet to list loaded AMS filaments.
final printerStatusOnceProvider =
    FutureProvider.autoDispose.family<PrinterStatus?, int>(
  (ref, printerId) =>
      ref.watch(printersRepositoryProvider).fetchStatus(printerId),
);

/// Queue action result returned to widget — it shows the SnackBar
/// (notifier has no [BuildContext]). Similar to M4 controls.
enum QueueActionResult { ok, forbidden, error }

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
    final all = await ref.read(queueRepositoryProvider).fetch();
    return _activeSorted(all);
  }

  List<QueueItem> _activeSorted(List<QueueItem> items) {
    // Printing always on top (pinned, non-reorderable in UI), then rest by
    // `position` with `id` as tiebreaker: server defaults all to `position == 1`
    // until queue is arranged, so stable tiebreaker is needed or order is undefined.
    int printingFirst(QueueItem i) =>
        i.statusKind == QueueItemStatusKind.printing ? 0 : 1;
    return items.where((i) => i.isActive).toList()
      ..sort((a, b) {
        final byPrinting = printingFirst(a).compareTo(printingFirst(b));
        if (byPrinting != 0) return byPrinting;
        final byPos = a.position.compareTo(b.position);
        return byPos != 0 ? byPos : a.id.compareTo(b.id);
      });
  }

  /// Pull-to-refresh / refresh after mutation. Keeps previous list underneath
  /// (AsyncLoading with previous) so UI doesn't flicker with spinner.
  Future<void> refresh() async {
    state = const AsyncValue<List<QueueItem>>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(
      () async => _activeSorted(await ref.read(queueRepositoryProvider).fetch()),
    );
  }

  /// Optimistic reorder (drag&drop). Indices in `onReorderItem` convention from
  /// `ReorderableListView` — `newIndex` is already adjusted for removing from
  /// `oldIndex`, so insert without additional correction. Send SEQUENTIAL positions
  /// 1..N in new order to server — "bulk update positions" endpoint expects target
  /// values, and all items default to `position == 1` (verified live, see reorder in
  /// contract). Error → rollback to pre-drag state.
  Future<QueueActionResult> reorder(int oldIndex, int newIndex) async {
    final current = state.valueOrNull;
    if (current == null) return QueueActionResult.error;
    if (oldIndex == newIndex) return QueueActionResult.ok;

    final list = [...current];
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    state = AsyncValue.data(list); // optymistycznie

    final payload = [
      for (var i = 0; i < list.length; i++) (id: list[i].id, position: i + 1),
    ];
    try {
      await ref.read(queueRepositoryProvider).reorder(payload);
      return QueueActionResult.ok;
    } on AppApiException catch (e) {
      state = AsyncValue.data(current); // rollback
      return _mapError(e);
    }
  }

  /// Optimistic delete (swipe-to-delete). Error → restore item.
  Future<QueueActionResult> delete(int itemId) async {
    final current = state.valueOrNull;
    if (current == null) return QueueActionResult.error;

    state = AsyncValue.data(
      current.where((i) => i.id != itemId).toList(),
    );
    try {
      await ref.read(queueRepositoryProvider).delete(itemId);
      return QueueActionResult.ok;
    } on AppApiException catch (e) {
      state = AsyncValue.data(current); // rollback
      return _mapError(e);
    }
  }

  /// Manually start item — triggers physical print. On success, fetch fresh list
  /// (status changes server-side).
  Future<QueueActionResult> start(int itemId) =>
      _serverAction(() => ref.read(queueRepositoryProvider).start(itemId));

  /// Cancel queue item. On success, refresh list.
  Future<QueueActionResult> cancel(int itemId) =>
      _serverAction(() => ref.read(queueRepositoryProvider).cancel(itemId));

  /// Persist a filament→AMS-slot mapping without starting (e.g. for items the
  /// queue may auto-dispatch later). On success, refresh list.
  Future<QueueActionResult> saveMapping(int itemId, List<int> mapping) =>
      _serverAction(
          () => ref.read(queueRepositoryProvider).setAmsMapping(itemId, mapping));

  /// Assign indicated (free) printer and start item — triggers physical print.
  /// `start` doesn't take printer, so first PATCH `printer_id`, then POST `start`.
  /// [amsMapping] (optional) sets the filament→AMS-slot mapping before starting;
  /// `-1` entries mean "auto". On success, refresh list.
  Future<QueueActionResult> startOnPrinter(
    int itemId,
    int printerId, {
    List<int>? amsMapping,
  }) =>
      _serverAction(() async {
        final repo = ref.read(queueRepositoryProvider);
        await repo.assignPrinter(itemId, printerId);
        if (amsMapping != null && amsMapping.isNotEmpty) {
          await repo.setAmsMapping(itemId, amsMapping);
        }
        await repo.start(itemId);
      });

  Future<QueueActionResult> _serverAction(Future<void> Function() send) async {
    try {
      await send();
      await refresh();
      return QueueActionResult.ok;
    } on AppApiException catch (e) {
      return _mapError(e);
    }
  }

  QueueActionResult _mapError(AppApiException e) {
    if (e is AuthException && e.code == AppErrorCode.forbidden) {
      return QueueActionResult.forbidden;
    }
    return QueueActionResult.error;
  }
}

/// Candidate for target printer in "start next". Carries printer itself plus
/// whether it's currently online and has smart plug assigned — so UI can mark
/// OFFLINE printers (bambuddy will wake them before start).
typedef PrinterCandidate = ({Printer printer, bool online, bool hasPlug});

/// Printers available to start next print on. Only exclude those ACTUALLY busy
/// (printing/paused) — OFFLINE printers stay in list because bambuddy will wake
/// them before start (with own smart plug or otherwise). Fetches printers + statuses
/// + plug map fresh on each call (autoDispose) because availability changes over time.
final availablePrintersProvider =
    FutureProvider.autoDispose<List<PrinterCandidate>>(
  (ref) async {
    final all = await ref.watch(printersRepositoryProvider).fetchAll();

    // Plug assignments are optional enrichment — their absence/failure can't block
    // printer selection, so treat error as "no plugs".
    Set<int> printersWithPlug = const {};
    try {
      final plugs = await ref.read(smartPlugsRepositoryProvider).fetchPlugs();
      printersWithPlug = {
        for (final plug in plugs)
          if ((plug.enabled ?? true) && plug.printerId != null) plug.printerId!,
      };
    } on AppApiException {
      // Leave empty set — no plug markings
    }

    return [
      for (final p in all)
        if (!(p.status?.isPrinting ?? false) && !(p.status?.isPaused ?? false))
          (
            printer: p.printer,
            online: p.status?.connected ?? false,
            hasPlug: printersWithPlug.contains(p.printer.id),
          ),
    ];
  },
);
