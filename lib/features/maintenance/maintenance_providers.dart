import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/maintenance.dart';
import '../../core/api/action_outcome.dart';
import '../../data/maintenance_repository.dart';
import '../../providers.dart';

final maintenanceOverviewProvider = AutoDisposeAsyncNotifierProvider<
    MaintenanceOverviewNotifier, List<PrinterMaintenanceOverview>>(
  MaintenanceOverviewNotifier.new,
);

/// Maintenance overview for all printers (M7). List grouped by printer
/// comes straight from server; "perform" (mark done) resets counter server-side,
/// so on success we fetch fresh state instead of guessing.
class MaintenanceOverviewNotifier
    extends AutoDisposeAsyncNotifier<List<PrinterMaintenanceOverview>> {
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
    state = const AsyncValue<List<PrinterMaintenanceOverview>>.loading()
        .copyWithPrevious(state);
    state = await AsyncValue.guard(
      () => ref.read(maintenanceRepositoryProvider).fetchOverview(),
    );
  }

  /// Marks task as done (reset counter). On success, refresh list (state changes server-side).
  Future<ActionOutcome> perform(int itemId, {String? notes}) =>
      _run(
        'maintenance.perform',
        (repo) => repo.perform(itemId, notes: notes),
      );

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
  ) async {
    try {
      await mutate(ref.read(maintenanceRepositoryProvider));
      await refresh();
      return ActionOutcome.ok;
    } on AppApiException catch (e) {
      return ActionOutcome.failed(e, action: action);
    }
  }
}

final maintenanceTypesProvider = AutoDisposeAsyncNotifierProvider<
    MaintenanceTypesNotifier, List<MaintenanceType>>(
  MaintenanceTypesNotifier.new,
);

/// Maintenance types catalog (Settings tab): system defaults + custom tasks.
/// CRUD mutates server-side and refreshes; type changes affect per-printer
/// status too, so those actions also invalidate [maintenanceOverviewProvider].
class MaintenanceTypesNotifier
    extends AutoDisposeAsyncNotifier<List<MaintenanceType>> {
  @override
  Future<List<MaintenanceType>> build() async {
    final profile = ref.watch(serverProfileProvider);
    if (profile == null) return const [];
    return ref.read(maintenanceRepositoryProvider).fetchTypes();
  }

  Future<void> refresh() async {
    if (ref.read(serverProfileProvider) == null) return;
    state = const AsyncValue<List<MaintenanceType>>.loading()
        .copyWithPrevious(state);
    state = await AsyncValue.guard(
      () => ref.read(maintenanceRepositoryProvider).fetchTypes(),
    );
  }

  /// Creates a custom type and assigns it to [printerIds] (custom types only
  /// show on printers they're assigned to). Refreshes types + overview.
  Future<ActionOutcome> create(
    MaintenanceTypeDraft draft,
    List<int> printerIds,
  ) =>
      _run('maintenance.type_create', (repo) async {
        final type = await repo.createType(draft);
        for (final pid in printerIds) {
          await repo.assignType(pid, type.id);
        }
      }, invalidateOverview: true);

  Future<ActionOutcome> editType(
    int typeId,
    MaintenanceTypeDraft draft,
  ) =>
      _run('maintenance.type_edit', (repo) => repo.updateType(typeId, draft),
          invalidateOverview: true);

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
  }) async {
    try {
      await mutate(ref.read(maintenanceRepositoryProvider));
      await refresh();
      if (invalidateOverview) ref.invalidate(maintenanceOverviewProvider);
      return ActionOutcome.ok;
    } on AppApiException catch (e) {
      return ActionOutcome.failed(e, action: action);
    }
  }
}

/// Total print time (hours) of printer from maintenance overview. Data is historical
/// (server counts independent of WS), so available even when printer OFFLINE — allows
/// dashboard card to show after collapse. Null = no data/not loaded yet (UI hides row).
final printerTotalPrintHoursProvider =
    Provider.autoDispose.family<double?, int>((ref, printerId) {
  final overview = ref.watch(maintenanceOverviewProvider).valueOrNull;
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
