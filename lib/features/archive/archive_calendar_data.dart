import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/archive.dart';
import '../../core/models/print_log_entry.dart';
import '../../providers.dart';

/// One print on the calendar: a run, or an archive that stands for its one
/// print (printed before runs were logged, or on a server without the route).
typedef CalendarPrint = ({
  Archive archive,
  int? runId,
  String status,
  DateTime date,
  String? colors,
});

/// Statuses an archive printed before each print was logged can carry: its
/// one print's outcome (`PRINTED` in the web's `CalendarView`).
const _printed = {'completed', 'failed', 'aborted', 'cancelled', 'stopped'};

/// The prints of [year]/[month] in local time, oldest first, among [archives]
/// (the list's filters already applied) — `CalendarView.tsx`'s `prints`.
///
/// Each run lands on the day it ended, under the archive it belongs to; a run
/// whose archive the filters hid is left out. An archive with no logged run
/// stands for its one print. [runs] null is a server without
/// `/archives/prints`: then every printed archive stands for its one print,
/// which is all such a server can place.
List<CalendarPrint> calendarPrints(
  List<Archive> archives,
  List<PrintLogEntry>? runs,
  int year,
  int month,
) {
  final byId = {for (final a in archives) a.id: a};
  final list = <CalendarPrint>[
    for (final run in runs ?? const <PrintLogEntry>[])
      if (byId[run.archiveId] case final archive?)
        (
          archive: archive,
          runId: run.id,
          status: run.status,
          date: (run.completedAt ?? run.createdAt).toLocal(),
          colors: run.filamentColor ?? archive.filamentColor,
        ),
    for (final archive in archives)
      if ((runs == null || archive.runCount == 0) &&
          _printed.contains(archive.status))
        if (archive.completedAt ?? archive.createdAt case final at?)
          (
            archive: archive,
            runId: null,
            status: archive.status,
            date: at.toLocal(),
            colors: archive.filamentColor,
          ),
  ];
  return list
      .where((p) => p.date.year == year && p.date.month == month)
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));
}

/// Every print that ended in one month, for one printer or all: the calendar's
/// read. Null from a server without the route.
final archiveMonthPrintsProvider = FutureProvider.autoDispose
    .family<List<PrintLogEntry>?, ({int year, int month, int? printerId})>((
      ref,
      key,
    ) {
      return ref
          .watch(archiveRepositoryProvider)
          .printsBetween(
            DateTime(key.year, key.month),
            DateTime(key.year, key.month + 1, 0),
            printerId: key.printerId,
          );
    });
