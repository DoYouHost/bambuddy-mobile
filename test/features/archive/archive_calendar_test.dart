import 'package:bambuddy_mobile/core/format/datetime_format.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/print_log_entry.dart';
import 'package:bambuddy_mobile/features/archive/archive_calendar.dart';
import 'package:bambuddy_mobile/features/archive/archive_calendar_data.dart';
import 'package:bambuddy_mobile/features/archive/archive_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// 3 November 2026, a Tuesday. November 2026 starts on a Sunday.
final _today = DateTime(2026, 11, 3, 12);

Archive _archive(int id, {String status = 'completed', int runCount = 1}) =>
    Archive(
      id: id,
      filename: 'a$id.3mf',
      printName: 'Print $id',
      status: status,
      runCount: runCount,
      completedAt: DateTime(2026, 11, 2, 9),
      filamentColor: '#000000',
    );

PrintLogEntry _run(int id, int archiveId, DateTime ended, {String? status}) =>
    PrintLogEntry(
      id: id,
      archiveId: archiveId,
      status: status ?? 'completed',
      createdAt: ended,
      completedAt: ended,
    );

void main() {
  late List<({int year, int month, int? printerId})> asked;

  setUp(() => asked = []);

  Future<List<Archive>> pump(
    WidgetTester tester, {
    List<Archive>? archives,
    List<PrintLogEntry>? Function(int month)? runs,
    double textScale = 1.0,
    ValueChanged<Archive>? onOpen,
    int? printerId,
  }) async {
    final list =
        archives ?? [_archive(1, runCount: 3), _archive(2, runCount: 1)];
    await tester.pumpWidget(
      ProviderScope(
        retry: neverRetry,
        overrides: [
          noServerProfileOverride,
          archiveMonthPrintsProvider.overrideWith((ref, key) async {
            asked.add(key);
            return runs == null
                ? [
                    _run(1, 1, DateTime(2026, 11, 3, 8)),
                    _run(2, 1, DateTime(2026, 11, 3, 15), status: 'failed'),
                    _run(3, 1, DateTime(2026, 11, 10, 9)),
                    _run(4, 2, DateTime(2026, 11, 10, 10)),
                  ]
                : runs(key.month);
          }),
        ],
        child: plApp(
          Scaffold(
            body: SingleChildScrollView(
              child: ArchiveCalendar(
                archives: list,
                printerId: printerId,
                today: _today,
                onOpen: onOpen ?? (_) {},
              ),
            ),
          ),
          builder: textScaled(textScale),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return list;
  }

  // The day number comes first in its cell, before a count that can read the
  // same, and days run in order, so the first match is the day itself.
  Finder day(int d) => find
      .descendant(
        of: byLogId('archive.calendar.day'),
        matching: find.text('$d'),
      )
      .first;

  String title(WidgetTester tester, DateTime month) => DateTimeFormats.of(
    tester.element(find.byType(ArchiveCalendar)),
  ).monthYear(month);

  testWidgets('opens on this month with its totals', (tester) async {
    await pump(tester);

    expect(find.text(title(tester, DateTime(2026, 11))), findsOneWidget);
    expect(find.text(pl.archiveCalendarPrints), findsOneWidget);
    // Four prints: three completed, one failed.
    expect(
      find.descendant(of: find.byType(Row), matching: find.text('4')),
      findsWidgets,
    );
    expect(asked.single, (year: 2026, month: 11, printerId: null));
  });

  testWidgets('weeks start where the locale starts them', (tester) async {
    await pump(tester);

    // Polish weeks start on Monday, so Sunday the 1st sits in the last column.
    final first = tester.getTopLeft(day(1));
    final second = tester.getTopLeft(day(2));
    expect(second.dy, greaterThan(first.dy), reason: 'the 2nd starts row two');
    expect(first.dx, greaterThan(second.dx));
  });

  testWidgets('a day lists its prints and a print opens its archive', (
    tester,
  ) async {
    final opened = <Archive>[];
    await pump(tester, onOpen: opened.add);
    expect(find.text(pl.archiveCalendarSelectDay), findsOneWidget);

    await tester.tap(day(3));
    await tester.pumpAndSettle();

    expect(byLogId('archive.calendar.print'), findsNWidgets(2));
    expect(find.text(pl.printLogStatusFailed), findsOneWidget);
    await tester.ensureVisible(byLogId('archive.calendar.print').first);
    await tester.tap(byLogId('archive.calendar.print').first);
    expect(opened.single.id, 1);
  });

  testWidgets('a day without prints says so, a second tap closes it', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(day(5));
    await tester.pumpAndSettle();
    expect(find.text(pl.archiveCalendarNoPrints), findsOneWidget);

    await tester.tap(day(5));
    await tester.pumpAndSettle();
    expect(find.text(pl.archiveCalendarSelectDay), findsOneWidget);
  });

  testWidgets('months move both ways and today comes back', (tester) async {
    await pump(tester, runs: (_) => const []);

    await tester.tap(byLogId('archive.calendar.previous'));
    await tester.pumpAndSettle();
    expect(find.text(title(tester, DateTime(2026, 10))), findsOneWidget);

    await tester.tap(byLogId('archive.calendar.next'));
    await tester.tap(byLogId('archive.calendar.next'));
    await tester.pumpAndSettle();
    expect(find.text(title(tester, DateTime(2026, 12))), findsOneWidget);

    await tester.tap(byLogId('archive.calendar.today'));
    await tester.pumpAndSettle();
    expect(find.text(title(tester, DateTime(2026, 11))), findsOneWidget);
    expect(asked.map((k) => k.month), containsAll([10, 11, 12]));
  });

  testWidgets('the printer filter reaches the read', (tester) async {
    await pump(tester, printerId: 4);

    expect(asked.single.printerId, 4);
  });

  testWidgets('without the route every printed archive is one print', (
    tester,
  ) async {
    await pump(tester, runs: (_) => null);

    await tester.tap(day(2));
    await tester.pumpAndSettle();

    expect(byLogId('archive.calendar.print'), findsNWidgets(2));
  });

  testWidgets('a day is a 48 dp target on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester);

    final cell = tester.getSize(byLogId('archive.calendar.day').first);
    expect(cell.width, greaterThanOrEqualTo(48));
    expect(cell.height, greaterThanOrEqualTo(48));
  });

  for (final scale in const [1.0, 1.5, 2.0]) {
    testWidgets('the month and a picked day fit at text $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester, textScale: scale);

      await tester.tap(day(3));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(byLogId('archive.calendar.print'), findsNWidgets(2));
    });
  }

  testWidgets('the app bar switches the archive between list and calendar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        retry: neverRetry,
        overrides: [
          noServerProfileOverride,
          sharedPreferencesProvider.overrideWithValue(store),
          archiveListOverride([_archive(1)]),
          archiveMonthPrintsProvider.overrideWith((ref, key) async => const []),
        ],
        child: plApp(const ArchiveScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ArchiveCalendar), findsNothing);

    await tester.tap(byLogId('archive.view_toggle'));
    await tester.pumpAndSettle();
    expect(find.byType(ArchiveCalendar), findsOneWidget);

    await tester.tap(byLogId('archive.view_toggle'));
    await tester.pumpAndSettle();
    expect(find.byType(ArchiveCalendar), findsNothing);
  });
}
