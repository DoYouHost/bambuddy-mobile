import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import '../../core/printers/printer_bucket.dart';
import 'dashboard_sort.dart';
import 'dashboard_view_store.dart';

/// Dashboard filter state — applied client-side over the already-fetched roster
/// (no extra network calls). Defaults: show everything.
class DashboardFilters {
  const DashboardFilters({
    this.status = PrinterStatusBucket.all,
    this.hideOffline = false,
    this.location,
  });

  /// Single selected status bucket; [PrinterStatusBucket.all] = no status filter.
  final PrinterStatusBucket status;

  /// Hide offline printers regardless of [status]. Ignored when the user
  /// explicitly picks the offline bucket (that selection is the intent).
  final bool hideOffline;

  /// Only the printers filed under exactly this location; null = every
  /// location. Compared as stored, as the web's filter does.
  final String? location;

  /// Count of active (non-default) filters — drives the filter-button badge.
  int get activeCount =>
      (status != PrinterStatusBucket.all ? 1 : 0) +
      (hideOffline ? 1 : 0) +
      (location != null ? 1 : 0);

  /// Whether a printer in [bucket], filed under [printerLocation], passes this
  /// filter.
  bool matches(PrinterStatusBucket bucket, [String? printerLocation]) {
    if (location != null && (printerLocation ?? '') != location) return false;
    if (status != PrinterStatusBucket.all && bucket != status) return false;
    if (hideOffline &&
        status != PrinterStatusBucket.offline &&
        bucket == PrinterStatusBucket.offline) {
      return false;
    }
    return true;
  }

  /// [location] is set to the argument, so null clears it — a plain optional
  /// could not tell "leave it" from "all locations".
  DashboardFilters copyWith({
    PrinterStatusBucket? status,
    bool? hideOffline,
    Object? location = _keep,
  }) => DashboardFilters(
    status: status ?? this.status,
    hideOffline: hideOffline ?? this.hideOffline,
    location: identical(location, _keep) ? this.location : location as String?,
  );

  static const _keep = Object();
}

/// The locations a printer is filed under, sorted as the web sorts them — the
/// options of the location filter.
List<String> printerLocationsOf(Iterable<String?> locations) => ({
  for (final l in locations)
    if (l != null && l.isNotEmpty) l,
}.toList()..sort());

final dashboardFiltersProvider = StateProvider.autoDispose<DashboardFilters>(
  (ref) => ref.watch(dashboardViewStoreProvider).filters,
);

final dashboardSortProvider = StateProvider.autoDispose<DashboardSort>(
  (ref) => ref.watch(dashboardViewStoreProvider).sort,
);

/// The collapsed sections, by [PrinterGroup.key].
final dashboardCollapsedGroupsProvider = StateProvider.autoDispose<Set<String>>(
  (ref) => ref.watch(dashboardViewStoreProvider).collapsed,
);
