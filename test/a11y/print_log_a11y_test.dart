import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/print_log_entry.dart';
import 'package:bambuddy_mobile/features/print_log/print_log_providers.dart';
import 'package:bambuddy_mobile/features/print_log/print_log_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets for the print log: the list, its sort
/// and overflow menus, the filter sheet (chosen, with the date range picker
/// open), the run sheet in each state a run can be in, and the confirmations
/// behind clear and delete. The harness and the rules are in a11y_harness.dart.
/// Not covered: the picked date range's chip and clear button, which need a
/// range chosen inside the platform calendar dialog (its day cells carry no
/// stable finder here).
///
/// Demo rows by name: 'Bracket v3 (deleted archive)' (orphan, failed, a cause),
/// 'Bag dispenser' (completed), 'Box – plate 2' (failed, a cause the picker
/// does not list), 'Test cube' (orphan, cancelled).

const _orphan = 'Bracket v3 (deleted archive)';
const _completed = 'Bag dispenser';
const _failed = 'Box – plate 2';
const _cancelled = 'Test cube';

/// A log that answers [state] instead of the demo's server.
class _Log extends PrintLogNotifier {
  _Log(this._state);

  final Future<PrintLogState> Function() _state;

  @override
  Future<PrintLogState> build() => _state();

  @override
  Future<void> refresh() async {}

  @override
  Future<void> loadMore() async {}
}

PrintLogEntry _run(int id, String name, String status, {String? reason}) =>
    PrintLogEntry(
      id: id,
      status: status,
      createdAt: DateTime(2026, 10, 20, 9, 59),
      startedAt: DateTime(2026, 10, 20, 10),
      completedAt: DateTime(2026, 10, 20, 11, 30),
      durationSeconds: 5400,
      printName: name,
      printerName: 'X1C-01',
      filamentType: 'PLA',
      filamentUsedGrams: 42.3,
      cost: 1.1,
      energyKwh: 0.4,
      failureReason: reason,
      createdByUsername: 'demo',
    );

void main() {
  a11ySurface(
    'print log',
    home: () => const PrintLogScreen(),
    shows: find.text(_completed),
  );

  a11ySurface(
    'print log, empty',
    demo: false,
    overrides: [
      printLogProvider.overrideWith(
        () => _Log(() async => const PrintLogState(items: [], total: 0)),
      ),
    ],
    home: () => const PrintLogScreen(),
    shows: find.text(pl.printLogEmpty),
  );

  a11ySurface(
    'print log, search with no matches',
    home: () => const PrintLogScreen(),
    arrange: (tester) async {
      await tester.enterText(find.byType(TextField).first, 'zzzz');
      await a11ySettle(tester, const Duration(seconds: 2));
    },
    shows: find.text(pl.printLogNoMatches),
  );

  a11ySurface(
    'print log, load failed',
    demo: false,
    overrides: [
      printLogProvider.overrideWith(
        () => _Log(
          () async => throw const ApiException(AppErrorCode.serverUnreachable),
        ),
      ),
    ],
    home: () => const PrintLogScreen(),
    shows: find.text(pl.retry),
  );

  a11ySurface(
    'print log, more pages to load',
    demo: false,
    overrides: [
      printLogProvider.overrideWith(
        () => _Log(
          () async => PrintLogState(
            items: [
              _run(1, 'Benchy', 'completed'),
              _run(2, 'Calibration cube', 'failed', reason: 'warping'),
            ],
            total: 80,
          ),
        ),
      ),
    ],
    home: () => const PrintLogScreen(),
    shows: byLogId('print_log.load_more'),
  );

  a11ySurface(
    'print log, sort menu',
    home: () => const PrintLogScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('print_log.sort')),
    shows: find.text(pl.printLogSortDirection),
  );

  a11ySurface(
    'print log, overflow menu',
    home: () => const PrintLogScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('print_log.menu')),
    shows: find.text(pl.printLogClear),
  );

  // --- Filters ---

  a11ySurface(
    'print log filters',
    home: () => const PrintLogScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('print_log.filters')),
    shows: find.text(pl.printLogFilterStatus),
  );

  a11ySurface(
    'print log filters, chosen',
    home: () => const PrintLogScreen(),
    arrange: (tester) async {
      await a11yTap(tester, byLogId('print_log.filters'));
      await a11yTap(tester, byLogId('print_log.filters.status.failed'));
    },
    shows: byLogId('print_log.filters.clear'),
  );

  a11ySurface(
    'print log filters, date range picker',
    home: () => const PrintLogScreen(),
    arrange: (tester) async {
      await a11yTap(tester, byLogId('print_log.filters'));
      await a11yTap(tester, byLogId('print_log.filters.dates'));
    },
    shows: find.byType(DateRangePickerDialog),
  );

  // --- Run sheet ---

  for (final (name, what) in [
    (_completed, 'completed'),
    (_failed, 'failed, a cause the picker does not list'),
    (_orphan, 'orphan, failed, a cause'),
    (_cancelled, 'orphan, cancelled'),
  ]) {
    a11ySurface(
      'print log run sheet, $name ($what)',
      home: () => const PrintLogScreen(),
      arrange: (tester) => a11yTap(tester, find.text(name)),
      shows: byLogId('sheet.print_log_classify'),
    );
  }

  a11ySurface(
    'print log run sheet, a status the server cannot write',
    demo: false,
    overrides: [
      printLogProvider.overrideWith(
        () => _Log(
          () async => PrintLogState(
            items: [_run(5, 'Stopped print', 'aborted')],
            total: 1,
          ),
        ),
      ),
    ],
    home: () => const PrintLogScreen(),
    arrange: (tester) => a11yTap(tester, find.text('Stopped print')),
    shows: find.text(pl.printLogStatusOneWay(pl.printLogStatusAborted)),
  );

  a11ySurface(
    'print log run sheet, changed and ready to save',
    home: () => const PrintLogScreen(),
    arrange: (tester) async {
      await a11yTap(tester, find.text(_completed));
      await a11yTap(tester, find.byType(DropdownMenu<String>).last);
      await a11yTap(tester, find.text(pl.printLogStatusFailed).last);
    },
    shows: find.text(pl.printLogCountsAsFailure),
  );

  a11ySurface(
    'print log run sheet, cause menu open',
    home: () => const PrintLogScreen(),
    arrange: (tester) async {
      await a11yTap(tester, find.text(_failed));
      await a11yTap(tester, find.byType(DropdownMenu<String>).first);
    },
    shows: find.text(pl.printLogNoClassification),
  );

  a11ySurface(
    'print log run sheet, status menu open',
    home: () => const PrintLogScreen(),
    arrange: (tester) async {
      await a11yTap(tester, find.text(_completed));
      await a11yTap(tester, find.byType(DropdownMenu<String>).last);
    },
    shows: find.text(pl.printLogStatusFailed),
  );

  // --- Confirmations ---

  a11ySurface(
    'print log delete run dialog',
    home: () => const PrintLogScreen(),
    arrange: (tester) async {
      await a11yTap(tester, find.text(_completed));
      await a11yTap(tester, byLogId('print_log.classify.delete'));
    },
    shows: find.text(pl.printLogDeleteBody),
  );

  a11ySurface(
    'print log clear dialog',
    home: () => const PrintLogScreen(),
    arrange: (tester) async {
      await a11yTap(tester, byLogId('print_log.menu'));
      await a11yTap(tester, find.text(pl.printLogClear));
    },
    shows: find.text(pl.printLogClearTitle),
  );

  a11ySurface(
    'print log clear dialog, under a filter',
    home: () => const PrintLogScreen(),
    arrange: (tester) async {
      await a11yTap(tester, byLogId('print_log.filters'));
      await a11yTap(tester, byLogId('print_log.filters.status.failed'));
      // The sheet is dismissed by a tap on its scrim, then the menu opens.
      await tester.tapAt(const Offset(200, 40));
      await a11ySettle(tester, const Duration(milliseconds: 700));
      await a11yTap(tester, byLogId('print_log.menu'));
      await a11yTap(tester, find.text(pl.printLogClear));
    },
    shows: find.text(pl.printLogClearBodyFiltered),
  );
}
