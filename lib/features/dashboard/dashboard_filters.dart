import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/printer_status.dart';
import '../../core/notifications/hms_catalog.dart';
import 'dashboard_sort.dart';
import 'dashboard_view_store.dart';

/// Coarse status buckets a printer can fall into on the dashboard — mirrors the
/// web app's `classifyPrinterStatus` so both clients group printers the same way.
enum PrinterStatusBucket {
  all,
  printing,
  idle,
  paused,
  finished,
  error,
  offline,
}

/// Classify a printer's live [status] into one bucket. Priority mirrors the web:
/// offline (no connection) wins, then error (state FAILED or a displayable HMS
/// error), then the print state. Unknown/other states fall back to idle.
/// Never returns [PrinterStatusBucket.all] (that's the "no filter" sentinel).
PrinterStatusBucket classifyPrinter(PrinterStatus? status) {
  if (!(status?.connected ?? false)) return PrinterStatusBucket.offline;
  // Error = the same displayable HMS errors the card surfaces, or a FAILED
  // terminal state — through the shared filter, so the two cannot drift.
  final hasError =
      firstDisplayableHmsError(
        status!,
        describe: HmsCatalog.instance.describe,
      ) !=
      null;
  if (hasError) return PrinterStatusBucket.error;
  switch (status.state?.toUpperCase()) {
    case 'RUNNING':
    case 'PREPARE':
      return PrinterStatusBucket.printing;
    case 'PAUSE':
    case 'PAUSED':
      return PrinterStatusBucket.paused;
    case 'FINISH':
    case 'FINISHED':
      return PrinterStatusBucket.finished;
    case 'FAILED':
      return PrinterStatusBucket.error;
    default:
      return PrinterStatusBucket.idle;
  }
}

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
