import 'dart:async';
import 'dart:convert';

import 'package:bambuddy_mobile/core/ams/color_names.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:dio/dio.dart';
import 'package:bambuddy_mobile/features/controller/controller_prints.dart';
import 'package:bambuddy_mobile/features/controller/controller_queue.dart';
import 'package:bambuddy_mobile/features/common/color_catalog.dart';
import 'package:bambuddy_mobile/features/queue/queue_mapping_sheet.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../contract/sent_writes.dart';
import '../../helpers.dart';
import '../queue/queue_fakes.dart';
import 'controller_harness.dart';

QueueItem _job(
  int id, {
  int? printerId = controllerTestPrinterId,
  String? targetModel,
  String status = 'pending',
  List<Map<String, Object?>> variants = const [],
  int? createdById,
}) => QueueItem.fromJson(
  _jobJson(
    id,
    printerId: printerId,
    targetModel: targetModel,
    status: status,
    variants: variants,
    createdById: createdById,
  ),
);

Map<String, dynamic> _jobJson(
  int id, {
  int? printerId = controllerTestPrinterId,
  String? targetModel,
  String status = 'pending',
  List<Map<String, Object?>> variants = const [],
  int? createdById,
}) => {
  ...readFixture('queue_item.json') as Map<String, dynamic>,
  'id': id,
  'archive_name': 'Job $id',
  'printer_id': printerId,
  'target_model': targetModel,
  'status': status,
  'variants': variants,
  'created_by_id': createdById,
};

const _alternatives = [
  {
    'library_file_id': 1,
    'filename': 'a.3mf',
    'target_model': 'P1S',
    'position': 0,
  },
  {
    'library_file_id': 2,
    'filename': 'b.3mf',
    'target_model': 'X1C',
    'position': 1,
  },
];

void main() {
  group('queueForPrinter', () {
    List<int> ids(List<QueueItem> items, {String? model = 'P1S'}) => [
      for (final i in queueForPrinter(items, printerId: 1, model: model)) i.id,
    ];

    test('keeps the jobs pinned to it and those for its model', () {
      expect(
        ids([
          _job(1),
          _job(2, printerId: null, targetModel: 'P1S'),
          _job(3, printerId: 2),
          _job(4, printerId: null, targetModel: 'X1C'),
        ]),
        [1, 2],
      );
    });

    test('matches the model in any case, as the server does', () {
      expect(ids([_job(1, printerId: null, targetModel: 'p1s')]), [1]);
    });

    test('with no model known, only the pinned jobs', () {
      expect(
        ids([
          _job(1),
          _job(2, printerId: null, targetModel: 'P1S'),
        ], model: null),
        [1],
      );
    });

    test('a job for no printer and no model is not this printer\'s', () {
      expect(ids([_job(1, printerId: null)]), isEmpty);
    });

    test('a cross-model job is matched by its first candidate only', () {
      // The server mirrors the first candidate onto `target_model` and filters
      // on that alone (`print_queue.py::list_queue`).
      expect(
        ids([
          _job(1, printerId: null, targetModel: 'P1S', variants: _alternatives),
        ]),
        [1],
      );
      expect(
        ids([
          _job(1, printerId: null, targetModel: 'P1S', variants: _alternatives),
        ], model: 'X1C'),
        isEmpty,
      );
    });

    test('an empty queue is empty', () {
      expect(ids(const []), isEmpty);
    });
  });

  group('the Queue view', () {
    late FakeQueue queue;

    Future<void> open(
      WidgetTester tester,
      List<QueueItem> items, {
      CurrentUser? user,
      FakeQueue? fake,
      bool warm = false,
    }) async {
      queue = fake ?? FakeQueue(items);
      await pumpControllerScreen(
        tester,
        overrides: [
          queueProvider.overrideWith(() => queue),
          requirePlateClearProvider.overrideWithValue(const AsyncData(false)),
          // The mapping step with nothing to map: one confirm button.
          printRequirementsProvider.overrideWith((ref, key) async => const []),
          mappingStatusProvider.overrideWith((ref, printerId) async => null),
          if (user != null) currentUserOverride(user),
        ],
      );
      if (warm) {
        // Loaded before the view opens, as the nav badge keeps it in the app.
        ProviderScope.containerOf(
          tester.element(find.byType(MaterialApp)),
        ).listen(queueProvider, (_, _) {});
        await settle(tester);
      }
      await openPrintsView(tester, ControllerPrintsView.queue);
    }

    Future<void> openJob(WidgetTester tester, int id) async {
      await tester.tap(find.text('Job $id'));
      await settle(tester);
    }

    testWidgets('lists this printer\'s jobs and the ones for its model', (
      tester,
    ) async {
      await open(tester, [
        _job(10, status: 'printing'),
        _job(11),
        _job(12, printerId: null, targetModel: 'P1S'),
        _job(13, printerId: 2),
        _job(14, printerId: null, targetModel: 'X1C'),
      ]);

      expect(find.text('Job 10'), findsOneWidget);
      expect(find.text('Job 11'), findsOneWidget);
      expect(find.text('Job 12'), findsOneWidget);
      expect(find.text('Job 13'), findsNothing);
      expect(find.text('Job 14'), findsNothing);
      expect(find.text(pl.controllerQueueCount(3)), findsOneWidget);
    });

    testWidgets('numbers its jobs in a round chip legible from a stand', (
      tester,
    ) async {
      await open(tester, [_job(11), _job(12)]);

      for (final place in ['1', '2']) {
        final number = find.descendant(
          of: byLogId('controller.queue.job'),
          matching: find.text(place),
        );
        expect(
          tester
              .getSize(
                find
                    .ancestor(of: number, matching: find.byType(Container))
                    .first,
              )
              .width,
          28,
          reason: place,
        );
        expect(tester.widget<Text>(number).style?.fontSize, 13);
      }
    });

    testWidgets('nothing queued for it says so', (tester) async {
      await open(tester, [_job(13, printerId: 2)]);

      expect(find.text(pl.controllerQueueEmpty), findsOneWidget);
    });

    testWidgets('a job for its model starts here, with no printer picker', (
      tester,
    ) async {
      await open(tester, [_job(12, printerId: null, targetModel: 'P1S')]);
      await openJob(tester, 12);

      await tester.tap(byLogId('controller.queue.dialog.start'));
      await settle(tester);
      expect(find.text(pl.pickPrinterTitle), findsNothing);
      // The mapping step, confirmed as it stands.
      await tester.tap(find.widgetWithText(FilledButton, pl.queueStart).last);
      await settle(tester);

      expect(queue.started, [(item: 12, printer: controllerTestPrinterId)]);
    });

    testWidgets('Remove takes a waiting job out without asking twice', (
      tester,
    ) async {
      await open(tester, [_job(11)]);
      await openJob(tester, 11);

      await tester.tap(byLogId('controller.queue.dialog.remove'));
      await settle(tester);

      expect(queue.cancelled, [11]);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('a job with alternatives is not started here, and says why', (
      tester,
    ) async {
      await open(tester, [
        _job(15, printerId: null, targetModel: 'P1S', variants: _alternatives),
      ]);
      await openJob(tester, 15);

      expect(
        buttonAt(tester, 'controller.queue.dialog.start').onPressed,
        isNull,
      );
      expect(find.text(pl.controllerQueueCrossModel), findsOneWidget);
    });

    testWidgets('an ownerless job for its model is not an update-own user\'s '
        'to start', (tester) async {
      // Putting this printer on it is a PATCH the server refuses them (403).
      await open(
        tester,
        [_job(12, printerId: null, targetModel: 'P1S')],
        user: const CurrentUser(
          id: 7,
          username: 'op',
          isAdmin: false,
          permissions: {
            Permissions.queueUpdateOwn,
            Permissions.queueStartUnreviewed,
          },
        ),
      );
      await openJob(tester, 12);

      expect(
        buttonAt(tester, 'controller.queue.dialog.start').onPressed,
        isNull,
      );
      expect(find.text(pl.controllerQueueNoStart), findsOneWidget);
    });

    testWidgets('the job on the plate offers nothing to do', (tester) async {
      await open(tester, [_job(10, status: 'printing')]);
      await openJob(tester, 10);

      expect(byLogId('controller.queue.dialog.start'), findsNothing);
      expect(byLogId('controller.queue.dialog.remove'), findsNothing);
    });

    testWidgets('a job that started while its dialog was open is left alone', (
      tester,
    ) async {
      await open(tester, [_job(11)]);
      await openJob(tester, 11);

      queue.replace([_job(11, status: 'printing')]);
      await tester.pump();
      await tester.tap(byLogId('controller.queue.dialog.remove'));
      await settle(tester);

      // Not even asked: a stop's confirmation would be the next thing open.
      expect(find.byType(Dialog), findsNothing);
      expect(queue.cancelled, isEmpty);
      expect(queue.stopped, isEmpty);
    });

    testWidgets('a job put on another printer meanwhile is not started here', (
      tester,
    ) async {
      await open(tester, [_job(12, printerId: null, targetModel: 'P1S')]);
      await openJob(tester, 12);

      queue.replace([_job(12, printerId: 2)]);
      await tester.pump();
      await tester.tap(byLogId('controller.queue.dialog.start'));
      await settle(tester);

      // Not even the mapping step, which would be for the other printer.
      expect(byLogId('queue_mapping.confirm'), findsNothing);
      expect(queue.started, isEmpty);
      expect(queue.startedAsIs, isEmpty);
    });

    testWidgets('the poll asks nothing while an answer is still coming', (
      tester,
    ) async {
      final slow = _SlowQueue([_job(11)]);
      await open(tester, const [], fake: slow, warm: true);
      expect(slow.refreshes, 1);

      await tester.pump(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 10));

      expect(slow.refreshes, 1);
    });

    testWidgets('a queue that failed before is asked again on entry', (
      tester,
    ) async {
      final failing = _FailsFirstQueue([_job(11)]);
      await open(tester, const [], fake: failing, warm: true);

      expect(failing.refreshes, 1);
      expect(find.text('Job 11'), findsOneWidget);
    });

    testWidgets('opening the view refreshes the queue once it is built', (
      tester,
    ) async {
      // A refresh writes the provider before it awaits, and a write while the
      // tree builds throws: the view opens from a tab tap, mid-build.
      final writing = _WritingQueue([_job(11)]);
      await open(tester, const [], fake: writing, warm: true);

      expect(tester.takeException(), isNull);
      expect(writing.refreshes, 1);
      expect(find.text('Job 11'), findsOneWidget);
    });
  });

  /// The requests Start really sends, through the app's own queue notifier and
  /// repository, recorded for `controller_prints_contract_test.dart` to replay
  /// on a live server.
  group('what Start sends', () {
    Future<void> start(
      WidgetTester tester,
      Map<String, dynamic> job,
      String name,
    ) async {
      final dio = testDio();
      final log = captureRequests(dio);
      dio.httpClientAdapter = ScriptedAdapter(
        (o) => ResponseBody.fromString(
          jsonEncode(
            o.method == 'GET' && o.path == Endpoints.queue
                ? (o.queryParameters['status'] == 'pending' ? [job] : const [])
                : const <String, Object?>{},
          ),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );
      await pumpControllerScreen(
        tester,
        model: 'X1C',
        overrides: [
          fakeServerProfileOverride(),
          queueRepositoryProvider.overrideWithValue(QueueRepository(dio)),
          requirePlateClearProvider.overrideWithValue(const AsyncData(false)),
          printRequirementsProvider.overrideWith(
            (ref, key) async => const [
              FilamentRequirement(slotId: 1, type: 'PLA', color: '#FF0000'),
            ],
          ),
          mappingStatusProvider.overrideWith(
            (ref, printerId) async => const PrinterStatus(
              id: controllerTestPrinterId,
              ams: [
                AmsUnit(
                  id: 0,
                  trays: [
                    AmsTray(id: 0, trayType: 'PETG', trayColor: '00FF00FF'),
                    AmsTray(id: 1, trayType: 'PLA', trayColor: 'FF0000FF'),
                  ],
                ),
              ],
            ),
          ),
          mappingInventoryRemainProvider.overrideWith(
            (ref, printerId) async => (
              grams: const <int, double>{},
              spools: const <int, SlotSpool>{},
            ),
          ),
          colorNameCatalogProvider.overrideWith(
            (ref) async => ColorCatalog.empty,
          ),
          mappingFilamentNamesProvider.overrideWith((ref) async => const {}),
        ],
      );
      await openPrintsView(tester, ControllerPrintsView.queue);
      await tester.tap(find.text('Job ${job['id']}'));
      await settle(tester);
      await tester.tap(byLogId('controller.queue.dialog.start'));
      await settle(tester);
      await tester.tap(byLogId('queue_mapping.confirm'));
      await settle(tester);

      expectSentAsRecorded(name, writesOf(log.requests));
    }

    testWidgets('a job pinned here', (tester) async {
      await start(tester, _jobJson(11), 'controller_start_pinned');
    });

    testWidgets('a job for this model', (tester) async {
      await start(
        tester,
        _jobJson(12, printerId: null, targetModel: 'X1C'),
        'controller_start_for_model',
      );
    });
  });
}

/// A queue whose refresh writes its state at once, as the real one does.
class _WritingQueue extends FakeQueue {
  _WritingQueue(super.items);

  int refreshes = 0;

  @override
  Future<void> refresh() async {
    refreshes++;
    state = const AsyncLoading<List<QueueItem>>();
    state = AsyncData(await build());
  }
}

/// A queue whose first answer is a failure, as after a dropped connection.
class _FailsFirstQueue extends _WritingQueue {
  _FailsFirstQueue(super.items);

  bool _failed = false;

  @override
  Future<List<QueueItem>> build() async {
    if (!_failed) {
      _failed = true;
      throw const ApiException(AppErrorCode.connectionError);
    }
    return super.build();
  }
}

/// A queue whose refresh never answers, as on a connection that hangs.
class _SlowQueue extends FakeQueue {
  _SlowQueue(super.items);

  int refreshes = 0;

  @override
  Future<void> refresh() {
    refreshes++;
    state = const AsyncLoading<List<QueueItem>>();
    return Completer<void>().future;
  }
}
