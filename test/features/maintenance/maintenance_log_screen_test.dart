import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/maintenance.dart';
import 'package:bambuddy_mobile/data/maintenance_repository.dart';
import 'package:bambuddy_mobile/features/maintenance/maintenance_log_screen.dart';
import 'package:bambuddy_mobile/features/maintenance/maintenance_providers.dart';
import 'package:bambuddy_mobile/features/maintenance/maintenance_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../contract/sent_writes.dart';
import '../../helpers.dart';

/// The maintenance log screen (E1): printer chips, the rows of one printer, the
/// menu's export and cleanup, a long press to delete. The real notifier and
/// repository run over a mock server, so what is asserted is what it would be sent.
void main() {
  const x1c = PrinterMaintenanceOverview(printerId: 1, printerName: 'X1C');
  const p1s = PrinterMaintenanceOverview(printerId: 2, printerName: 'P1S');

  Map<String, Object?> row(
    int id, {
    String task = 'Lubricate rods',
    String? notes,
    String? who = 'morgan',
    int printer = 1,
  }) => {
    'id': id,
    'printer_id': printer,
    'printer_name': printer == 1 ? 'X1C' : 'P1S',
    'maintenance_type_id': 2,
    'maintenance_type_name': task,
    'hours_at_maintenance': 390.4,
    'notes': notes,
    'performed_by_username': who,
    'performed_at': '2026-11-20T09:30:00Z',
  };

  late _SavePicker picker;

  /// Whether the log screen is the one showing: a test turns it off to leave.
  final onScreen = ValueNotifier(true);
  late _Overview overview;

  setUp(() {
    picker = _SavePicker();
    FilePicker.platform = picker;
  });

  /// The screen with a server that holds [rows] for printer 1 and [rowsP1s] for
  /// printer 2, and the same preferences when a test opens it twice.
  Future<RequestLog> open(
    WidgetTester tester, {
    List<Map<String, Object?>>? rows,
    List<Map<String, Object?>> rowsP1s = const [],
    int? total,
    CurrentUser? user,
    double scale = 1,
    SharedPreferences? prefs,
    List<PrinterMaintenanceOverview> printers = const [x1c, p1s],
    Map<String, Object?> cleanupAnswer = const {'deleted': 12},
    Duration? exportDelay,
  }) async {
    onScreen.value = true;
    final shownRows = rows ?? [row(1, notes: 'Replaced the PTFE tube'), row(2)];
    final dio = testDio();
    final server = mockServer(dio)
      ..onGet(
        '/api/v1/maintenance/printers/1/log',
        (s) => s.reply(200, {
          'items': shownRows.take(50).toList(),
          'total': total ?? shownRows.length,
        }),
        queryParameters: {'limit': 50, 'offset': 0},
      )
      ..onGet(
        '/api/v1/maintenance/printers/1/log',
        (s) => s.reply(200, {
          'items': shownRows.skip(50).take(50).toList(),
          'total': total ?? shownRows.length,
        }),
        queryParameters: {'limit': 50, 'offset': 50},
      )
      ..onGet(
        '/api/v1/maintenance/printers/2/log',
        (s) => s.reply(200, {'items': rowsP1s, 'total': rowsP1s.length}),
        queryParameters: {'limit': 50, 'offset': 0},
      )
      ..onGet(
        '/api/v1/maintenance/printers/1/log/export',
        (s) => s.reply(
          200,
          utf8.encode('Performed at\n'),
          delay: exportDelay ?? Duration.zero,
          headers: {
            'content-disposition': [
              'attachment; filename="maintenance_log_X1C_20261124.csv"',
            ],
          },
        ),
      )
      ..onGet(
        '/api/v1/maintenance/log/export',
        (s) => s.reply(200, utf8.encode('Performed at\n')),
      )
      ..onDelete(
        '/api/v1/maintenance/log/1',
        (s) => s.reply(200, {'status': 'deleted'}),
      );
    // One route per age the dialog offers: a mock matches a query exactly.
    for (final days in const [30, 90, 180, 365]) {
      for (final path in const [
        '/api/v1/maintenance/printers/1/log',
        '/api/v1/maintenance/log',
      ]) {
        server.onDelete(
          path,
          (s) => s.reply(200, cleanupAnswer),
          queryParameters: {'older_than_days': days},
        );
      }
    }
    final log = captureRequests(dio);
    await tester.pumpWidget(
      ProviderScope(
        retry: neverRetry,
        overrides: [
          maintenanceRepositoryProvider.overrideWithValue(
            MaintenanceRepository(dio),
          ),
          maintenanceOverviewProvider.overrideWith(
            () => overview = _Overview(printers),
          ),
          maintenanceLogSupportedProvider.overrideWithValue(
            const AsyncData(true),
          ),
          sharedPreferencesProvider.overrideWithValue(prefs ?? await _prefs()),
          fakeServerProfileOverride(),
          currentUserOverride(user),
        ],
        child: plApp(
          ValueListenableBuilder(
            valueListenable: onScreen,
            builder: (_, on, _) =>
                on ? const MaintenanceLogScreen() : const Scaffold(),
          ),
          builder: textScaled(scale),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return log;
  }

  /// Lets requests finish without waiting out the snackbar, which
  /// `pumpAndSettle` would: it goes after four seconds.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> choose(WidgetTester tester, String logId) async {
    await tester.tap(byLogId('maintenance_log.menu'));
    await tester.pumpAndSettle();
    await tester.tap(byLogId(logId));
    await tester.pumpAndSettle();
  }

  const scales = [1.0, 1.5, 2.0];

  group('the list', () {
    for (final scale in scales) {
      testWidgets('shows the task, who, when and the comment, at $scale text', (
        tester,
      ) async {
        await open(tester, scale: scale);

        expect(find.text(pl.maintenanceLogTitle('X1C')), findsOneWidget);
        expect(find.text('Lubricate rods'), findsNWidgets(2));
        expect(find.textContaining('morgan'), findsNWidgets(2));
        expect(
          find.textContaining(pl.maintenanceLogHours(390)),
          findsNWidgets(2),
        );
        expect(find.text('Replaced the PTFE tube'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a key reset has no name to show and the row still reads', (
      tester,
    ) async {
      await open(tester, rows: [row(1, who: null)]);

      expect(find.textContaining('morgan'), findsNothing);
      expect(find.textContaining(pl.maintenanceLogHours(390)), findsOneWidget);
    });

    testWidgets('an empty log says so', (tester) async {
      await open(tester, rows: const []);

      expect(find.text(pl.maintenanceLogEmpty), findsOneWidget);
    });

    testWidgets('"load more" asks for the next page and goes with the last', (
      tester,
    ) async {
      final run = await open(
        tester,
        rows: [for (var i = 1; i <= 60; i++) row(i)],
      );
      expect(
        byLogId('maintenance_log.entry').evaluate(),
        hasLength(lessThan(60)),
      );
      // The list builds rows lazily: the button exists only once scrolled to.
      await tester.scrollUntilVisible(
        byLogId('maintenance_log.load_more'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text(pl.maintenanceLogLoadMore(50, 60)), findsOneWidget);

      await tester.tap(byLogId('maintenance_log.load_more'));
      await tester.pumpAndSettle();

      expect([
        for (final r in run.requests) r.queryParameters['offset'],
      ], containsAllInOrder([0, 50]));
      expect(byLogId('maintenance_log.load_more'), findsNothing);
    });
  });

  group('the printers', () {
    testWidgets('a chip shows that printer\'s log, and the choice is kept', (
      tester,
    ) async {
      final prefs = await _prefs();
      await open(
        tester,
        prefs: prefs,
        rowsP1s: [row(9, task: 'Clean the plate', printer: 2)],
      );

      await tester.tap(find.widgetWithText(ChoiceChip, 'P1S'));
      await tester.pumpAndSettle();

      expect(find.text(pl.maintenanceLogTitle('P1S')), findsOneWidget);
      expect(find.text('Clean the plate'), findsOneWidget);
      expect(prefs.getInt('maintenance_log_printer'), 2);
    });

    testWidgets('it opens on the printer that was open last', (tester) async {
      final prefs = await _prefs(<String, Object>{
        'maintenance_log_printer': 2,
      });
      await open(
        tester,
        prefs: prefs,
        rowsP1s: [row(9, task: 'Clean the plate', printer: 2)],
      );

      expect(find.text(pl.maintenanceLogTitle('P1S')), findsOneWidget);
      expect(find.text('Clean the plate'), findsOneWidget);
    });

    testWidgets('a remembered printer that is gone falls back to the first', (
      tester,
    ) async {
      final prefs = await _prefs(<String, Object>{
        'maintenance_log_printer': 77,
      });
      await open(tester, prefs: prefs);

      expect(find.text(pl.maintenanceLogTitle('X1C')), findsOneWidget);
    });
  });

  group('export', () {
    testWidgets('saves the CSV under the name the server gave it', (
      tester,
    ) async {
      await open(tester);

      await choose(tester, 'maintenance_log.export_printer');
      await settle(tester);

      expect(picker.saved, ['maintenance_log_X1C_20261124.csv']);
      expect(
        find.text(pl.maintenanceLogSaved('maintenance_log_X1C_20261124.csv')),
        findsOneWidget,
      );
    });

    testWidgets('all printers is the fleet\'s file, under a plain name', (
      tester,
    ) async {
      final run = await open(tester);

      await choose(tester, 'maintenance_log.export_all');
      await settle(tester);

      expect(run.paths.last, '/api/v1/maintenance/log/export');
      expect(picker.saved, ['maintenance-log.csv']);
    });

    testWidgets('backing out of the dialog says nothing', (tester) async {
      picker.answer = null;
      await open(tester);

      await choose(tester, 'maintenance_log.export_printer');
      await settle(tester);

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a dialog that fails says so', (tester) async {
      picker.fails = true;
      await open(tester);

      await choose(tester, 'maintenance_log.export_printer');
      await settle(tester);

      expect(find.text(pl.filePickerFailed), findsOneWidget);
    });

    testWidgets('a second export while the first is open does nothing', (
      tester,
    ) async {
      picker.gate = Completer<void>();
      await open(tester);

      await choose(tester, 'maintenance_log.export_printer');
      await tester.pump(const Duration(milliseconds: 100));
      await choose(tester, 'maintenance_log.export_printer');
      picker.gate!.complete();
      await settle(tester);

      expect(picker.opened, 1);
    });
  });

  group('cleanup', () {
    testWidgets('sends the chosen age for this printer, as recorded', (
      tester,
    ) async {
      final run = await open(tester);

      await choose(tester, 'maintenance_log.cleanup_printer');
      await tester.tap(
        find.widgetWithText(ChoiceChip, pl.maintenanceLogAge(90)),
      );
      await tester.pumpAndSettle();
      await tester.tap(byLogId('maintenance_log_cleanup.confirm'));
      await settle(tester);

      expectSentAsRecorded('maintenance_log_cleanup', writesOf(run.requests));
      expect(find.text(pl.maintenanceLogCleanedUp(12)), findsOneWidget);
    });

    testWidgets('starts at a year, the age that takes the least', (
      tester,
    ) async {
      final run = await open(tester);

      await choose(tester, 'maintenance_log.cleanup_printer');
      await tester.tap(byLogId('maintenance_log_cleanup.confirm'));
      await settle(tester);

      expect(writesOf(run.requests).single.query, {'older_than_days': 365});
    });

    testWidgets('all printers is the fleet\'s route', (tester) async {
      final run = await open(tester);

      await choose(tester, 'maintenance_log.cleanup_all');
      await tester.tap(byLogId('maintenance_log_cleanup.confirm'));
      await settle(tester);

      expect(writesOf(run.requests).single.path, '/api/v1/maintenance/log');
    });

    testWidgets('cancelling sends nothing', (tester) async {
      final run = await open(tester);

      await choose(tester, 'maintenance_log.cleanup_printer');
      await tester.tap(byLogId('maintenance_log_cleanup.cancel'));
      await settle(tester);

      expect(writesOf(run.requests), isEmpty);
    });

    testWidgets('nothing old enough says none were deleted', (tester) async {
      await open(tester, cleanupAnswer: const {'deleted': 0});

      await choose(tester, 'maintenance_log.cleanup_printer');
      await tester.tap(byLogId('maintenance_log_cleanup.confirm'));
      await settle(tester);

      expect(find.text(pl.maintenanceLogCleanedUp(0)), findsOneWidget);
    });

    for (final scale in scales) {
      testWidgets('the dialog fits, at $scale text', (tester) async {
        await open(tester, scale: scale);

        await choose(tester, 'maintenance_log.cleanup_all');

        expect(byLogId('maintenance_log_cleanup.confirm'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('delete one entry', () {
    testWidgets('a long press asks, then sends the delete, as recorded', (
      tester,
    ) async {
      final run = await open(tester);

      await tester.longPress(byLogId('maintenance_log.entry').first);
      await tester.pumpAndSettle();
      await tester.tap(byLogId('maintenance_log.delete_entry_confirm.confirm'));
      await settle(tester);

      expectSentAsRecorded(
        'maintenance_log_delete_entry',
        writesOf(run.requests),
      );
      expect(find.text(pl.maintenanceLogEntryDeleted), findsOneWidget);
    });

    testWidgets('backing out sends nothing', (tester) async {
      final run = await open(tester);

      await tester.longPress(byLogId('maintenance_log.entry').first);
      await tester.pumpAndSettle();
      await tester.tap(byLogId('maintenance_log.delete_entry_confirm.cancel'));
      await settle(tester);

      expect(writesOf(run.requests), isEmpty);
    });
  });

  group('without maintenance:delete', () {
    const reader = CurrentUser(
      id: 7,
      username: 'op',
      isAdmin: false,
      permissions: {Permissions.queueCreate},
    );

    testWidgets('the menu exports and offers no cleanup', (tester) async {
      await open(tester, user: reader);

      await tester.tap(byLogId('maintenance_log.menu'));
      await tester.pumpAndSettle();

      expect(byLogId('maintenance_log.export_printer'), findsOneWidget);
      expect(byLogId('maintenance_log.export_all'), findsOneWidget);
      expect(byLogId('maintenance_log.cleanup_printer'), findsNothing);
      expect(byLogId('maintenance_log.cleanup_all'), findsNothing);
    });

    testWidgets('a long press deletes nothing', (tester) async {
      final run = await open(tester, user: reader);

      await tester.longPress(byLogId('maintenance_log.entry').first);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(writesOf(run.requests), isEmpty);
    });
  });

  group('leaving and reloading', () {
    testWidgets('a short log still pulls to refresh', (tester) async {
      final run = await open(tester);

      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pumpAndSettle();

      expect(
        run.paths.where((p) => p.endsWith('/printers/1/log')),
        hasLength(2),
        reason: 'two rows do not fill the screen, and the pull still reloads',
      );
    });

    testWidgets('the next printer opens at its newest row, not mid-list', (
      tester,
    ) async {
      await open(
        tester,
        rows: [for (var i = 1; i <= 40; i++) row(i, task: 'first-$i')],
        rowsP1s: [
          for (var i = 1; i <= 40; i++) row(i, task: 'second-$i', printer: 2),
        ],
      );
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'P1S'));
      await tester.pumpAndSettle();

      expect(find.text('second-1'), findsOneWidget);
    });

    testWidgets('leaving while the cleanup dialog is open sends nothing', (
      tester,
    ) async {
      final run = await open(tester);

      await choose(tester, 'maintenance_log.cleanup_printer');
      onScreen.value = false;
      await tester.pump();
      await tester.tap(byLogId('maintenance_log_cleanup.confirm'));
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(writesOf(run.requests), isEmpty);
    });

    testWidgets('leaving while the delete is asked sends nothing', (
      tester,
    ) async {
      final run = await open(tester);

      await tester.longPress(byLogId('maintenance_log.entry').first);
      await tester.pumpAndSettle();
      onScreen.value = false;
      await tester.pump();
      await tester.tap(byLogId('maintenance_log.delete_entry_confirm.confirm'));
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(writesOf(run.requests), isEmpty);
    });

    testWidgets('leaving while the CSV is fetched opens no dialog', (
      tester,
    ) async {
      await open(tester, exportDelay: const Duration(seconds: 1));

      await choose(tester, 'maintenance_log.export_printer');
      onScreen.value = false;
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(picker.opened, 0);
    });

    testWidgets(
      'a printer that went while the dialog was open is not cleaned',
      (tester) async {
        final run = await open(tester);

        await choose(tester, 'maintenance_log.cleanup_printer');
        overview.replace(const [p1s]);
        await tester.pump();
        await tester.tap(byLogId('maintenance_log_cleanup.confirm'));
        await settle(tester);

        expect(writesOf(run.requests), isEmpty);
      },
    );

    testWidgets('all printers reloads the log that is on screen now', (
      tester,
    ) async {
      final run = await open(tester);

      await choose(tester, 'maintenance_log.cleanup_all');
      overview.replace(const [p1s]);
      await tester.pump();
      await tester.tap(byLogId('maintenance_log_cleanup.confirm'));
      await settle(tester);

      expect(writesOf(run.requests).single.path, '/api/v1/maintenance/log');
      expect(
        run.paths.where((p) => p.endsWith('/printers/2/log')),
        hasLength(2),
        reason: 'the first read, then the reload after the cleanup',
      );
    });
  });

  group('the entry point', () {
    Future<void> openMaintenance(WidgetTester tester, bool served) async =>
        tester.pumpWidget(
          ProviderScope(
            retry: neverRetry,
            overrides: [
              maintenanceOverviewProvider.overrideWith(
                () => _Overview(const [x1c]),
              ),
              maintenanceLogSupportedProvider.overrideWithValue(
                AsyncData(served),
              ),
              sharedPreferencesProvider.overrideWithValue(await _prefs()),
              noServerProfileOverride,
              currentUserOverride(),
            ],
            child: plApp(const MaintenanceScreen()),
          ),
        );

    testWidgets('an icon in the app bar, on a server that has the log', (
      tester,
    ) async {
      await openMaintenance(tester, true);
      await tester.pumpAndSettle();

      expect(byLogId('maintenance.log'), findsOneWidget);
    });

    testWidgets('and none on a server before it', (tester) async {
      await openMaintenance(tester, false);
      await tester.pumpAndSettle();

      expect(byLogId('maintenance.log'), findsNothing);
      expect(byLogId('maintenance.settings'), findsOneWidget);
    });
  });
}

Future<SharedPreferences> _prefs([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  return SharedPreferences.getInstance();
}

class _Overview extends MaintenanceOverviewNotifier {
  _Overview(this._list);

  final List<PrinterMaintenanceOverview> _list;

  @override
  Future<List<PrinterMaintenanceOverview>> build() async => _list;

  /// The overview as a reload would bring it.
  void replace(List<PrinterMaintenanceOverview> printers) =>
      state = AsyncData(printers);
}

/// A system save dialog that records what it was asked to save.
class _SavePicker extends FilePicker {
  /// Null is a cancelled dialog.
  String? answer = '/storage/saved.csv';
  bool fails = false;
  Completer<void>? gate;
  int opened = 0;
  final saved = <String>[];

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    opened++;
    await gate?.future;
    if (fails) throw Exception('no room');
    if (answer != null) saved.add(fileName!);
    return answer;
  }
}
