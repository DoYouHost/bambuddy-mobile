import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/plate_list.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/data/print_log_repository.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/features/archive/archive_runs.dart';
import 'package:bambuddy_mobile/features/archive/print_outcome.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../contract/sent_writes.dart';
import '../../helpers.dart';

const _archive = Archive(
  id: 5,
  filename: 'bag.gcode.3mf',
  status: 'completed',
  printName: 'Bag dispenser',
  runCount: 2,
  createdById: 7,
);

/// A run as the archive redesign lists it.
Map<String, dynamic> _run(int id, {String status = 'completed', int? by = 7}) =>
    {
      'id': id,
      'archive_id': 5,
      'status': status,
      'created_at': '2026-11-0${id}T10:00:00',
      'started_at': '2026-11-0${id}T10:00:00',
      'printer_name': 'X1 Carbon',
      'user_verdict': null,
      'user_verdict_source': null,
      'confirm_requested': true,
      'notes': null,
      'photos': <String>[],
      'timelapse_path': null,
      'created_by_id': by,
    };

CurrentUser _user(Set<String> permissions) => CurrentUser(
  id: 7,
  username: 'op',
  isAdmin: false,
  permissions: permissions,
);

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late RequestLog sent;

  setUp(() {
    dio = testDio();
    adapter = mockServer(dio);
    sent = captureRequests(dio);
  });

  Future<void> pump(
    WidgetTester tester, {
    required List<Map<String, dynamic>> runs,
    bool perPrint = true,
    CurrentUser? user,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    adapter.onGet(
      '/api/v1/archives/5/runs',
      (s) => s.reply(200, {'items': runs, 'total': runs.length}),
    );
    await tester.pumpWidget(
      ProviderScope(
        retry: neverRetry,
        overrides: [
          noServerProfileOverride,
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserOverride(user),
          currencySymbolProvider.overrideWithValue('€'),
          archiveRepositoryProvider.overrideWithValue(ArchiveRepository(dio)),
          printLogRepositoryProvider.overrideWithValue(PrintLogRepository(dio)),
          plateListProvider.overrideWith((ref, key) async => PlateList.none),
          archiveRunsSupportedProvider.overrideWithValue(AsyncData(perPrint)),
          printOutcomeSupportedProvider.overrideWithValue(
            const AsyncData(true),
          ),
        ],
        child: plApp(
          Scaffold(
            body: SingleChildScrollView(
              child: ArchiveRunsSection(
                archive: _archive,
                onPhotos: (_) {},
                onVideo: (_) {},
                onReprint: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(byLogId('archive.run').first);
    await tester.pumpAndSettle();
  }

  testWidgets('a server before the redesign is offered neither write', (
    tester,
  ) async {
    await pump(tester, runs: [_run(1)], perPrint: false);

    expect(byLogId('archive.run.outcome'), findsNothing);
    expect(byLogId('archive.run.edit_note'), findsNothing);
  });

  testWidgets('only a completed print is asked how it came out', (
    tester,
  ) async {
    await pump(tester, runs: [_run(1, status: 'failed')]);

    expect(byLogId('archive.run.outcome'), findsNothing);
    expect(byLogId('archive.run.edit_note'), findsOneWidget);
  });

  testWidgets('update-own writes a note on its own print only', (tester) async {
    await pump(
      tester,
      runs: [_run(1, by: 99)],
      user: _user(const {Permissions.archivesUpdateOwn}),
    );

    expect(byLogId('archive.run.edit_note'), findsNothing);
    expect(
      byLogId('archive.run.outcome'),
      findsOneWidget,
      reason: 'the verdict is checked against the archive, not the print',
    );
  });

  testWidgets('without update rights neither is offered', (tester) async {
    await pump(tester, runs: [_run(1)], user: _user(const {}));

    expect(byLogId('archive.run.outcome'), findsNothing);
    expect(byLogId('archive.run.edit_note'), findsNothing);
  });

  testWidgets('the note goes to that print and the list reloads', (
    tester,
  ) async {
    adapter.onPatch(
      '/api/v1/print-log/2',
      (s) => s.reply(200, {..._run(2), 'notes': 'Lids fit'}),
      data: Matchers.any,
    );
    await pump(tester, runs: [_run(2), _run(1)]);

    await tester.tap(byLogId('archive.run.edit_note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Lids fit');
    await tester.tap(byLogId('archive.run.note_prompt.save'));
    await tester.pumpAndSettle();

    expectSentAsRecorded('archive_run_note', writesOf(sent.requests));
    expect(find.text(pl.archiveRunNoteSaved), findsOneWidget);
    expect(
      sent.requests.where((r) => r.path.endsWith('/archives/5/runs')),
      hasLength(2),
      reason: 'the list is read again after the write',
    );
  });

  testWidgets('a verdict from a print\'s sheet names that print', (
    tester,
  ) async {
    adapter
      ..onGet(
        '/api/v1/archives/5',
        (s) => s.reply(200, {
          'id': 5,
          'filename': 'bag.gcode.3mf',
          'status': 'completed',
          'confirm_requested': true,
          'user_verdict': null,
          'photos': <String>[],
        }),
        queryParameters: {'run_id': 1},
      )
      ..onGet(
        '/api/v1/archives/5',
        (s) => s.reply(200, {
          'id': 5,
          'filename': 'bag.gcode.3mf',
          'status': 'completed',
          'confirm_requested': true,
          'user_verdict': null,
        }),
      )
      ..onPatch(
        '/api/v1/archives/5',
        (s) => s.reply(200, {
          'id': 5,
          'filename': 'bag.gcode.3mf',
          'status': 'completed',
          'confirm_requested': true,
          'user_verdict': 'good',
        }),
        data: Matchers.any,
      );
    await pump(tester, runs: [_run(1)]);

    await tester.tap(byLogId('archive.run.outcome'));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('outcome.good'));
    await tester.pumpAndSettle();

    expectSentAsRecorded('archive_run_verdict', writesOf(sent.requests));
    expect(find.text(pl.outcomeSavedGood), findsOneWidget);
  });
}
