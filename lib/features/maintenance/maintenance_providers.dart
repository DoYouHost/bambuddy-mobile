import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/maintenance.dart';
import '../../providers.dart';

/// Maintenance action result returned to widget — it shows SnackBar
/// (notifier has no [BuildContext]). Analogous to queue (M5).
enum MaintenanceActionResult { ok, forbidden, error }

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
  Future<MaintenanceActionResult> perform(int itemId, {String? notes}) async {
    try {
      await ref.read(maintenanceRepositoryProvider).perform(itemId, notes: notes);
      await refresh();
      return MaintenanceActionResult.ok;
    } on AppApiException catch (e) {
      if (e is AuthException && e.code == AppErrorCode.forbidden) {
        return MaintenanceActionResult.forbidden;
      }
      return MaintenanceActionResult.error;
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
