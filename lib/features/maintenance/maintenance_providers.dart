import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/maintenance.dart';
import '../../core/api/action_outcome.dart';
import '../../data/maintenance_repository.dart';
import '../../providers.dart';

final maintenanceOverviewProvider =
    AsyncNotifierProvider.autoDispose<
      MaintenanceOverviewNotifier,
      List<PrinterMaintenanceOverview>
    >(MaintenanceOverviewNotifier.new);

/// Maintenance overview for all printers (M7). List grouped by printer
/// comes straight from server; "perform" (mark done) resets counter server-side,
/// so on success we fetch fresh state instead of guessing.
class MaintenanceOverviewNotifier
    extends AsyncNotifier<List<PrinterMaintenanceOverview>> {
  @override
  Future<List<PrinterMaintenanceOverview>> build() async {
    // Rebuild on server profile change (different key/permissions). No profile
    // (e.g. right after "change server", before the router swaps to /setup) →
    // apiClientProvider throws, so short-circuit to an empty list instead.
    final profile = ref.watch(serverProfileProvider);
    if (profile == null) return const [];
    return ref.read(maintenanceRepositoryProvider).fetchOverview();
  }

  /// Pull-to-refresh / refresh after mutation. Keeps previous list underneath
  /// (AsyncLoading with previous) so UI doesn't flicker with spinner.
  Future<void> refresh() async {
    // No profile (mid server-change) → nothing to fetch; mirrors [build].
    if (ref.read(serverProfileProvider) == null) return;
    state = const AsyncLoading<List<PrinterMaintenanceOverview>>();
    final next = await AsyncValue.guard(
      () => ref.read(maintenanceRepositoryProvider).fetchOverview(),
    );
    if (!ref.mounted) return;
    state = next;
  }

  /// Marks task as done (reset counter). On success, refresh list (state changes server-side).
  Future<ActionOutcome> perform(int itemId, {String? notes}) =>
      _run('maintenance.perform', (repo) => repo.perform(itemId, notes: notes));

  /// Mutes/unmutes a task (server `enabled`). Disabled tasks stop counting and
  /// alerting. Refreshes on success.
  Future<ActionOutcome> setEnabled(int itemId, bool enabled) => _run(
    'maintenance.mute',
    (repo) => repo.updateItem(itemId, enabled: enabled),
  );

  /// Sets a per-printer interval override (hours), or clears it (back to the
  /// type default) when [hours] is null.
  Future<ActionOutcome> setInterval(int itemId, double? hours) => _run(
    'maintenance.interval',
    (repo) => repo.updateItem(
      itemId,
      customIntervalHours: hours,
      clearInterval: hours == null,
    ),
  );

  /// Runs a mutation, maps permission errors, and refreshes on success.
  /// [action] is the control the user touched, in the `logTag` vocabulary —
  /// one tag for all of them would make the log record say which screen failed
  /// but not what the user was trying to do.
  Future<ActionOutcome> _run(
    String action,
    Future<void> Function(MaintenanceRepository) mutate,
  ) => runAction(
    () => mutate(ref.read(maintenanceRepositoryProvider)),
    logId: action,
    onSuccess: refresh,
  );
}

final maintenanceTypesProvider =
    AsyncNotifierProvider.autoDispose<
      MaintenanceTypesNotifier,
      List<MaintenanceType>
    >(MaintenanceTypesNotifier.new);

/// Maintenance types catalog (Settings tab): system defaults + custom tasks.
/// CRUD mutates server-side and refreshes; type changes affect per-printer
/// status too, so those actions also invalidate [maintenanceOverviewProvider].
class MaintenanceTypesNotifier extends AsyncNotifier<List<MaintenanceType>> {
  @override
  Future<List<MaintenanceType>> build() async {
    final profile = ref.watch(serverProfileProvider);
    if (profile == null) return const [];
    return ref.read(maintenanceRepositoryProvider).fetchTypes();
  }

  Future<void> refresh() async {
    if (ref.read(serverProfileProvider) == null) return;
    state = const AsyncLoading<List<MaintenanceType>>();
    final next = await AsyncValue.guard(
      () => ref.read(maintenanceRepositoryProvider).fetchTypes(),
    );
    if (!ref.mounted) return;
    state = next;
  }

  /// Creates a custom type and assigns it to [printerIds] (custom types only
  /// show on printers they're assigned to). Refreshes types + overview.
  Future<ActionOutcome> create(
    MaintenanceTypeDraft draft,
    List<int> printerIds,
  ) => _run('maintenance.type_create', (repo) async {
    final type = await repo.createType(draft);
    for (final pid in printerIds) {
      await repo.assignType(pid, type.id);
    }
  }, invalidateOverview: true);

  Future<ActionOutcome> editType(int typeId, MaintenanceTypeDraft draft) =>
      _run(
        'maintenance.type_edit',
        (repo) => repo.updateType(typeId, draft),
        invalidateOverview: true,
      );

  Future<ActionOutcome> delete(int typeId) => _run(
    'maintenance.type_delete',
    (repo) => repo.deleteType(typeId),
    invalidateOverview: true,
  );

  Future<ActionOutcome> restoreDefaults() => _run(
    'maintenance.restore_defaults',
    (repo) => repo.restoreDefaults(),
    invalidateOverview: true,
  );

  /// See [MaintenanceOverviewNotifier._run] for why [action] is per-mutation.
  Future<ActionOutcome> _run(
    String action,
    Future<void> Function(MaintenanceRepository) mutate, {
    bool invalidateOverview = false,
  }) => runAction(
    () => mutate(ref.read(maintenanceRepositoryProvider)),
    logId: action,
    onSuccess: () async {
      await refresh();
      if (invalidateOverview) ref.invalidate(maintenanceOverviewProvider);
    },
  );
}

/// Total print time (hours) of printer from maintenance overview. Data is historical
/// (server counts independent of WS), so available even when printer OFFLINE — allows
/// dashboard card to show after collapse. Null = no data/not loaded yet (UI hides row).
final printerTotalPrintHoursProvider = Provider.autoDispose
    .family<double?, int>((ref, printerId) {
      final overview = ref.watch(maintenanceOverviewProvider).value;
      if (overview == null) return null;
      for (final p in overview) {
        if (p.printerId == printerId) return p.totalPrintHours;
      }
      return null;
    });

/// Task completion history — loaded on demand (bottom-sheet). Autodispose + family
/// by `itemId` since we load it point-wise for selected item.
final maintenanceHistoryProvider = FutureProvider.autoDispose
    .family<List<MaintenanceHistoryEntry>, int>(
      (ref, itemId) =>
          ref.watch(maintenanceRepositoryProvider).fetchHistory(itemId),
    );

/// What the log screen shows: the entries loaded so far, newest first, how many
/// the server holds in all, and where the next page starts (rows the server sent,
/// which can be more than [entries] when one did not parse).
typedef MaintenanceLogView = ({
  List<MaintenanceLogEntry> entries,
  int total,
  int nextOffset,
});

final maintenanceLogProvider = AsyncNotifierProvider.autoDispose
    .family<MaintenanceLogNotifier, MaintenanceLogView, int>(
      MaintenanceLogNotifier.new,
    );

/// A printer's log of resets, a page at a time (`GET /maintenance/printers/{id}/log`).
/// Deleting and cleaning up change what the server holds, so both reload the
/// first page instead of guessing which rows are gone.
class MaintenanceLogNotifier extends AsyncNotifier<MaintenanceLogView> {
  MaintenanceLogNotifier(this.arg);

  /// The printer.
  final int arg;

  /// The epoch of the page being asked for, or null when none is: a page whose
  /// list has been reloaded since is no reason to refuse the next one.
  int? _loadingMoreEpoch;

  /// Counts the reloads: a page asked for before one and answered after it is
  /// about a list that is gone, and must not be written over the new one.
  int _epoch = 0;

  @override
  Future<MaintenanceLogView> build() async {
    // No profile (mid server-change): nothing to ask, as in the siblings.
    if (ref.watch(serverProfileProvider) == null) {
      return (entries: const <MaintenanceLogEntry>[], total: 0, nextOffset: 0);
    }
    return _firstPage();
  }

  Future<MaintenanceLogView> _firstPage() async {
    final page = await ref.read(maintenanceRepositoryProvider).fetchLog(arg);
    return (entries: page.items, total: page.total, nextOffset: page.received);
  }

  /// More rows are on the server than have been asked for.
  bool get hasMore {
    final view = state.value;
    return view != null && view.nextOffset < view.total;
  }

  /// The next page, added under the loaded rows. A tap while one is in the air,
  /// or while the list is reloading or failed to, does nothing. A reset made
  /// between two pages moves every row down by one, so the last row of a page
  /// can come again at the top of the next: rows already shown are skipped by
  /// id.
  Future<ActionOutcome> loadMore({required String logId}) async {
    final view = state.value;
    if (view == null ||
        state.isLoading ||
        state.hasError ||
        _loadingMoreEpoch == _epoch ||
        !hasMore) {
      return ActionOutcome.ok;
    }
    final epoch = _loadingMoreEpoch = _epoch;
    try {
      return await runAction(() async {
        final page = await ref
            .read(maintenanceRepositoryProvider)
            .fetchLog(arg, offset: view.nextOffset);
        // The list was reloaded, or is being, meanwhile: [view] is gone.
        // Written only over the list the page was asked for.
        if (!ref.mounted || epoch != _epoch || !identical(state.value, view)) {
          return;
        }
        final shown = {for (final e in view.entries) e.id};
        state = AsyncData((
          entries: [
            ...view.entries,
            for (final e in page.items)
              if (!shown.contains(e.id)) e,
          ],
          total: page.total,
          // Nothing came back though more is said to be there: rows went
          // meanwhile, and the end is reached.
          nextOffset: page.received == 0
              ? page.total
              : view.nextOffset + page.received,
        ));
      }, logId: logId);
    } finally {
      if (_loadingMoreEpoch == epoch) _loadingMoreEpoch = null;
    }
  }

  /// Reloads the first page for a pull-to-refresh: the old rows stay underneath
  /// and a failure becomes the state, for the screen's retry.
  Future<void> refresh() async {
    if (ref.read(serverProfileProvider) == null) return;
    final epoch = ++_epoch;
    state = const AsyncLoading<MaintenanceLogView>();
    final next = await AsyncValue.guard(_firstPage);
    if (!ref.mounted || epoch != _epoch) return;
    state = next;
  }

  /// [refresh] for after a write, which throws: a write that landed and a list
  /// that could not be reloaded is not a success to report. The failure is the
  /// state too, because it may have overtaken a [refresh] that is waiting for an
  /// answer it will now never write.
  Future<void> _reload() async {
    final epoch = ++_epoch;
    try {
      final view = await _firstPage();
      if (!ref.mounted || epoch != _epoch) return;
      state = AsyncData(view);
    } on Object catch (error, stack) {
      if (ref.mounted && epoch == _epoch) {
        state = AsyncError<MaintenanceLogView>(error, stack);
      }
      rethrow;
    }
  }

  /// Deletes one entry (`DELETE /maintenance/log/{id}`). The task's last reset
  /// stays as it is.
  Future<ActionOutcome> deleteEntry(int entryId, {required String logId}) =>
      runAction(
        () => ref.read(maintenanceRepositoryProvider).deleteLogEntry(entryId),
        logId: logId,
        onSuccess: _reload,
      );

  /// Drops the entries older than [days] days: this printer's, or those of
  /// every printer the caller may see when [allPrinters]. [deleted] says how
  /// many went.
  Future<({ActionOutcome outcome, int deleted})> cleanUp(
    int days, {
    required String logId,
    bool allPrinters = false,
  }) async {
    var deleted = 0;
    final outcome = await runAction(
      () async {
        deleted = await ref
            .read(maintenanceRepositoryProvider)
            .cleanUpLog(
              olderThanDays: days,
              printerId: allPrinters ? null : arg,
            );
      },
      logId: logId,
      onSuccess: _reload,
    );
    return (outcome: outcome, deleted: deleted);
  }
}
