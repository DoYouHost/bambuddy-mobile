import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/printer_location.dart';
import '../../providers.dart';

/// Every location the server knows, those only printers carry included.
final printerLocationsProvider =
    FutureProvider.autoDispose<List<PrinterLocation>>(
      (ref) => ref.watch(printerLocationsRepositoryProvider).list(),
    );

/// The four orders of the web page's sort menu.
enum LocationSort { nameAsc, nameDesc, countAsc, countDesc }

final locationSortProvider = StateProvider.autoDispose<LocationSort>(
  (_) => LocationSort.nameAsc,
);

final hideEmptyLocationsProvider = StateProvider.autoDispose<bool>(
  (_) => false,
);

/// Case-insensitive, with a run of digits compared as a number, so `Rack 2`
/// comes before `Rack 10` — the server sorts the listing that way
/// (`natural_sort_key`) and the web page re-sorts with the same rule.
int compareLocationNames(String a, String b) {
  final left = _chunks(a);
  final right = _chunks(b);
  for (var i = 0; i < left.length && i < right.length; i++) {
    final x = left[i];
    final y = right[i];
    final nx = int.tryParse(x);
    final ny = int.tryParse(y);
    final c = nx != null && ny != null ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return left.length.compareTo(right.length);
}

final _digitRuns = RegExp(r'\d+|\D+');

List<String> _chunks(String s) => [
  for (final m in _digitRuns.allMatches(s.toLowerCase())) m.group(0)!,
];

/// What the list shows: [query] is a substring of the name, [hideEmpty] drops
/// the locations with no printer, and a tie on the count falls back to the
/// name, as on the web page.
List<PrinterLocation> arrangeLocations(
  List<PrinterLocation> all, {
  String query = '',
  bool hideEmpty = false,
  LocationSort sort = LocationSort.nameAsc,
}) {
  final q = query.trim().toLowerCase();
  final shown = [
    for (final l in all)
      if ((q.isEmpty || l.name.toLowerCase().contains(q)) &&
          (!hideEmpty || l.printerCount > 0))
        l,
  ];
  int byName(PrinterLocation a, PrinterLocation b) =>
      compareLocationNames(a.name, b.name);
  int byCount(PrinterLocation a, PrinterLocation b, int sign) {
    final c = sign * a.printerCount.compareTo(b.printerCount);
    return c != 0 ? c : byName(a, b);
  }

  shown.sort(
    (a, b) => switch (sort) {
      LocationSort.nameAsc => byName(a, b),
      LocationSort.nameDesc => byName(b, a),
      LocationSort.countAsc => byCount(a, b, 1),
      LocationSort.countDesc => byCount(a, b, -1),
    },
  );
  return shown;
}
