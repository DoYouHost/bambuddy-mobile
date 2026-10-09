import 'package:collection/collection.dart';

import '../../core/models/printer_status.dart';
import '../../data/printers_repository.dart';
import 'dashboard_filters.dart';

/// What the printer list is ordered by — the web's `SortOption`
/// (`PrintersPage.tsx`).
///
/// **The names are persisted values** (SharedPreferences); renaming one resets
/// that choice for every install.
enum PrinterSort { name, status, model, location, eta }

/// The order and its direction. Errors first, then printing, down to offline,
/// until the user picks another. Descending reverses the whole list, as the web
/// does, so ties come out reversed too.
class DashboardSort {
  const DashboardSort({this.by = PrinterSort.status, this.ascending = true});

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

// ponytail: lower-cased compareTo standing in for the web's localeCompare, with
// the raw strings as tie-break so "Alpha" and "alpha" keep one order whichever
// way the list arrived. It compares UTF-16 code units, so an accented letter
// sorts after "z" instead of beside its base letter; real collation needs the
// intl package's Collator-like support, which Dart does not ship.
int _text(String a, String b) {
  final c = a.toLowerCase().compareTo(b.toLowerCase());
  return c != 0 ? c : a.compareTo(b);
}

/// Error, printing, idle, offline — the web's `status` order, read off the
/// same buckets the sections use so the order inside a section and the sections
/// agree. Paused and finished count as idle here; the sections tell them apart.
int _statusRank(PrinterStatus? s) => switch (classifyPrinter(s)) {
  PrinterStatusBucket.error => 0,
  PrinterStatusBucket.printing => 1,
  PrinterStatusBucket.offline => 3,
  _ => 2,
};

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

  // Printing with a time left comes by that time, the other tiers by name.
  int byEta(PrinterWithStatus a, PrinterWithStatus b) {
    final tier = _etaTier(a.status).compareTo(_etaTier(b.status));
    if (tier != 0) return tier;
    if (_etaTier(a.status) == 0) {
      final left = a.status!.remainingTime!.compareTo(b.status!.remainingTime!);
      if (left != 0) return left;
    }
    return byName(a, b);
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
      PrinterSort.eta => byEta(a, b),
    },
  );
  return sort.ascending ? sorted : sorted.reversed.toList();
}

/// One headed section of the list.
class PrinterGroup {
  const PrinterGroup({
    required this.by,
    required this.key,
    required this.printers,
    this.name,
    this.bucket,
  });

  /// The sort that made this section.
  final PrinterSort by;

  /// What the collapsed state is stored under, with the sort in front of it
  /// (`location:Workshop`): the same printers are grouped differently under
  /// another sort, and folding one should not fold the other. The section of
  /// printers with no location or model has an empty name (`location:`), so a
  /// location that is really called "Ungrouped" is a section of its own.
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
          by: sort.by,
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
        by: sort.by,
        key: '${sort.by.name}:${e.key ?? ''}',
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
