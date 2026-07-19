import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/printer_status.dart';
import '../../core/notifications/hms_catalog.dart';

/// Coarse status buckets a printer can fall into on the dashboard — mirrors the
/// web app's `classifyPrinterStatus` so both clients group printers the same way.
enum PrinterStatusBucket { all, printing, idle, paused, finished, error, offline }

/// Classify a printer's live [status] into one bucket. Priority mirrors the web:
/// offline (no connection) wins, then error (state FAILED or a displayable HMS
/// error), then the print state. Unknown/other states fall back to idle.
/// Never returns [PrinterStatusBucket.all] (that's the "no filter" sentinel).
PrinterStatusBucket classifyPrinter(PrinterStatus? status) {
  if (!(status?.connected ?? false)) return PrinterStatusBucket.offline;
  // Error = the same displayable HMS errors the card surfaces, or a FAILED
  // terminal state. Reuses [hmsIsDisplayable] + the catalog so the filter and
  // the card agree on what counts as an actionable error.
  final hasError = (status!.hmsErrors ?? const <HmsError>[]).any(
    (e) => hmsIsDisplayable(e, description: HmsCatalog.instance.describe(e)),
  );
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
  });

  /// Single selected status bucket; [PrinterStatusBucket.all] = no status filter.
  final PrinterStatusBucket status;

  /// Hide offline printers regardless of [status]. Ignored when the user
  /// explicitly picks the offline bucket (that selection is the intent).
  final bool hideOffline;

  /// Count of active (non-default) filters — drives the filter-button badge.
  int get activeCount =>
      (status != PrinterStatusBucket.all ? 1 : 0) + (hideOffline ? 1 : 0);

  /// Whether a printer in [bucket] passes this filter.
  bool matches(PrinterStatusBucket bucket) {
    if (status != PrinterStatusBucket.all && bucket != status) return false;
    if (hideOffline &&
        status != PrinterStatusBucket.offline &&
        bucket == PrinterStatusBucket.offline) {
      return false;
    }
    return true;
  }

  DashboardFilters copyWith({
    PrinterStatusBucket? status,
    bool? hideOffline,
  }) =>
      DashboardFilters(
        status: status ?? this.status,
        hideOffline: hideOffline ?? this.hideOffline,
      );
}

final dashboardFiltersProvider = StateProvider.autoDispose<DashboardFilters>(
  (_) => const DashboardFilters(),
);
