import 'package:collection/collection.dart';

import '../../core/models/printer_status.dart';
import '../../core/notifications/hms_catalog.dart';
import '../../data/printers_repository.dart';
import 'dashboard_filters.dart';

/// What the printer list is ordered by — the web's `SortOption`
/// (`PrintersPage.tsx`).
///
/// **The names are persisted values** (SharedPreferences); renaming one resets
/// that choice for every install.
enum PrinterSort { name, status, model, location, eta }

/// The order and its direction. Descending reverses the whole list, as the web
/// does, so ties come out reversed too.
class DashboardSort {
  const DashboardSort({this.by = PrinterSort.name, this.ascending = true});

  final PrinterSort by;
  final bool ascending;

  DashboardSort copyWith({PrinterSort? by, bool? ascending}) =>
      DashboardSort(by: by ?? this.by, ascending: ascending ?? this.ascending);

  /// Whether the list is cut into headed sections: by location, status or
  /// model. A name or a time left is one flat list.
  bool get grouped =>
      by == PrinterSort.status ||
      by == PrinterSort.model ||
      by == PrinterSort.location;
}

// ponytail: lower-cased compareTo for the web's localeCompare; collation only
// differs for accented names.
int _text(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

/// `HMS error > printing > idle > offline`, the web's `status` order. Paused
/// and finished count as idle here; the sections tell them apart.
int _statusRank(PrinterStatus? s) {
  if (!(s?.connected ?? false)) return 3;
  if (firstDisplayableHmsError(s!, describe: HmsCatalog.instance.describe) !=
      null) {
    return 0;
  }
  return s.state?.toUpperCase() == 'RUNNING' ? 1 : 2;
}

/// The web's `eta` tiers: printing with a time left, printing without, idle,
/// offline.
int _etaTier(PrinterStatus? s) {
  if (!(s?.connected ?? false)) return 3;
  if (s!.state?.toUpperCase() != 'RUNNING') return 2;
  return (s.remainingTime ?? 0) > 0 ? 0 : 1;
}

/// [printers] in [sort]'s order. Stable: equal printers keep the order the
/// server listed them in, which `List.sort` does not promise.
List<PrinterWithStatus> sortPrinters(
  List<PrinterWithStatus> printers,
  DashboardSort sort,
) {
  int byName(PrinterWithStatus a, PrinterWithStatus b) =>
      _text(a.printer.name, b.printer.name);
  String where(PrinterWithStatus p) => p.printer.location ?? '';

  // No location goes last, in the ascending order; descending turns it round.
  int byLocation(PrinterWithStatus a, PrinterWithStatus b) {
    final x = where(a);
    final y = where(b);
    if (x.isEmpty != y.isEmpty) return x.isEmpty ? 1 : -1;
    final c = _text(x, y);
    return c != 0 ? c : byName(a, b);
  }

  final sorted = [...printers];
  mergeSort(
    sorted,
    compare: (a, b) => switch (sort.by) {
      PrinterSort.name => byName(a, b),
      PrinterSort.model => _text(a.printer.model ?? '', b.printer.model ?? ''),
      PrinterSort.location => byLocation(a, b),
      PrinterSort.status => _statusRank(
        a.status,
      ).compareTo(_statusRank(b.status)),
      PrinterSort.eta => _etaOrder(a, b, byName),
    },
  );
  return sort.ascending ? sorted : sorted.reversed.toList();
}

int _etaOrder(
  PrinterWithStatus a,
  PrinterWithStatus b,
  int Function(PrinterWithStatus, PrinterWithStatus) byName,
) {
  final tier = _etaTier(a.status).compareTo(_etaTier(b.status));
  if (tier != 0) return tier;
  if (_etaTier(a.status) == 0) {
    final left = (a.status!.remainingTime ?? 0).compareTo(
      b.status!.remainingTime ?? 0,
    );
    if (left != 0) return left;
  }
  return byName(a, b);
}

/// One headed section of the list.
class PrinterGroup {
  const PrinterGroup({
    required this.key,
    required this.printers,
    this.name,
    this.bucket,
  });

  /// What the collapsed state is stored under, with the sort in front of it
  /// (`location:Workshop`): the same printers are grouped differently under
  /// another sort, and folding one should not fold the other.
  final String key;

  /// The location or model, or null for the section of printers that have
  /// none.
  final String? name;

  /// Set for a status section.
  final PrinterStatusBucket? bucket;
  final List<PrinterWithStatus> printers;
}

/// The sections of [sorted] (already in [sort]'s order), or null when the sort
/// is not a grouping.
///
/// Location and model sections follow the order their first printer comes in,
/// so a descending sort turns them round with the printers. Status sections
/// have a fixed order, error to offline, and descending turns that round —
/// the web's own comment says so.
List<PrinterGroup>? groupPrinters(
  List<PrinterWithStatus> sorted,
  DashboardSort sort,
) {
  if (!sort.grouped) return null;
  if (sort.by == PrinterSort.status) {
    final byBucket = groupBy(sorted, (p) => classifyPrinter(p.status));
    final order = [
      for (final b in _statusOrder)
        if (byBucket[b]?.isNotEmpty ?? false) b,
    ];
    return [
      for (final b in sort.ascending ? order : order.reversed)
        PrinterGroup(
          key: 'status:${b.name}',
          bucket: b,
          printers: byBucket[b]!,
        ),
    ];
  }
  final location = sort.by == PrinterSort.location;
  String? nameOf(PrinterWithStatus p) {
    final v = (location ? p.printer.location : p.printer.model) ?? '';
    return v.isEmpty ? null : v;
  }

  // A map keeps its insertion order, which is the order of first appearance.
  final byName = groupBy(sorted, nameOf);
  return [
    for (final e in byName.entries)
      PrinterGroup(
        key: '${sort.by.name}:${e.key ?? (location ? 'Ungrouped' : 'Unknown')}',
        name: e.key,
        printers: e.value,
      ),
  ];
}

const _statusOrder = [
  PrinterStatusBucket.error,
  PrinterStatusBucket.printing,
  PrinterStatusBucket.paused,
  PrinterStatusBucket.finished,
  PrinterStatusBucket.idle,
  PrinterStatusBucket.offline,
];
