import 'package:bambuddy_mobile/core/models/cost_center.dart';
import 'package:bambuddy_mobile/core/models/library_file.dart';
import 'package:bambuddy_mobile/core/models/library_folder.dart';
import 'package:bambuddy_mobile/core/models/library_stats.dart';
import 'package:bambuddy_mobile/core/models/library_tag.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/files/file_manager_providers.dart';
import 'package:bambuddy_mobile/features/files/file_manager_screen.dart';
import 'package:bambuddy_mobile/features/pipelines/pipelines_providers.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_edit_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';
import '../queue/queue_form_harness.dart';

class _FakeNotifier extends FileManagerNotifier {
  _FakeNotifier(this._state);
  final FileManagerState _state;

  @override
  Future<FileManagerState> build() async => _state;
}

LibraryFile _file({
  int id = 1,
  String filename = 'thing.3mf',
  String fileType = '3mf',
  bool isExternal = false,
  int variantCount = 0,
  int photoCount = 0,
  String? externalUrl,
}) => LibraryFile(
  id: id,
  filename: filename,
  fileType: fileType,
  fileSize: 1024,
  printCount: 0,
  isExternal: isExternal,
  variantCount: variantCount,
  photoCount: photoCount,
  externalUrl: externalUrl,
);

void main() {
  /// Pumps the screen with one file in the listing.
  ///
  /// [tags] null models a server with no tag routes, which hides the tag UI.
  Future<void> pump(
    WidgetTester tester, {
    required LibraryFile file,
    bool slicerEnabled = true,
    bool canRunPipelines = true,
    List<LibraryTag>? tags = const [],
    bool fileExtras = false,
    Size size = const Size(411, 866),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpPhone(
      tester,
      const FileManagerScreen(),
      overrides: [
        noServerProfileOverride,
        fileManagerProvider.overrideWith(
          () => _FakeNotifier(FileManagerState(files: [file])),
        ),
        libraryStatsProvider.overrideWith((ref) async => const LibraryStats()),
        libraryTagsProvider.overrideWith((ref) async => tags),
        libraryTagsSupportedProvider.overrideWithValue(AsyncData(tags != null)),
        slicerEnabledProvider.overrideWithValue(AsyncValue.data(slicerEnabled)),
        canRunPipelinesProvider.overrideWithValue(AsyncData(canRunPipelines)),
        libraryFileExtrasProvider.overrideWithValue(AsyncData(fileExtras)),
      ],
    );
    await tester.pumpAndSettle();
  }

  /// Opens the per-file action sheet.
  Future<void> openFileSheet(WidgetTester tester, LibraryFile file) async {
    await tester.tap(find.text(file.displayName));
    await tester.pumpAndSettle();
  }

  group('the run-with-pipeline action', () {
    testWidgets(
      'is offered on a sliceable file when the server has pipelines',
      (tester) async {
        final file = _file();
        await pump(tester, file: file);
        await openFileSheet(tester, file);

        expect(tester.takeException(), isNull);
        expect(
          find.byIcon(Icons.layers_outlined),
          findsOneWidget,
          reason: 'the slice action proves the sheet thinks the file sliceable',
        );
        expect(find.byIcon(Icons.account_tree_outlined), findsOneWidget);
      },
    );

    testWidgets('stays away on a server without the pipeline routes', (
      tester,
    ) async {
      final file = _file();
      await pump(tester, file: file, canRunPipelines: false);
      await openFileSheet(tester, file);

      expect(find.byIcon(Icons.account_tree_outlined), findsNothing);
    });

    testWidgets(
      'appears once the gate settles after the sheet is already open',
      (tester) async {
        // The sheet is built in its own route, so a gate read from the screen's
        // `ref` cannot rebuild it. The gate can still be unanswered when the
        // sheet opens (the probe is out), so reading it once at build time hides
        // the action on a server that does have pipelines.
        final gate = StateProvider<AsyncValue<bool>>(
          (_) => const AsyncLoading(),
        );
        final file = _file();
        await pumpPhone(
          tester,
          const FileManagerScreen(),
          overrides: [
            noServerProfileOverride,
            fileManagerProvider.overrideWith(
              () => _FakeNotifier(FileManagerState(files: [file])),
            ),
            libraryStatsProvider.overrideWith(
              (ref) async => const LibraryStats(),
            ),
            libraryTagsProvider.overrideWith((ref) async => const []),
            slicerEnabledProvider.overrideWithValue(AsyncValue.data(true)),
            canRunPipelinesProvider.overrideWith((ref) => ref.watch(gate)),
          ],
        );
        await tester.pumpAndSettle();
        await openFileSheet(tester, file);

        expect(
          find.byIcon(Icons.account_tree_outlined),
          findsNothing,
          reason: 'nothing is claimed before the server has answered',
        );

        ProviderScope.containerOf(
          tester.element(find.byType(FileManagerScreen)),
        ).read(gate.notifier).state = const AsyncData(
          true,
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.account_tree_outlined), findsOneWidget);
      },
    );
  });

  group('selection mode', () {
    /// The screen in selection mode, its variants gate the real one over a
    /// repository whose latch the test drives.
    Future<LibraryRepository> pumpSelecting(
      WidgetTester tester, {
      bool? variantsSeen,
    }) async {
      final repo = LibraryRepository(testDio());
      if (variantsSeen != null) {
        repo.variantsCapability.observe(present: variantsSeen);
      }
      final file = _file();
      await pumpPhone(
        tester,
        const FileManagerScreen(),
        overrides: [
          noServerProfileOverride,
          libraryRepositoryProvider.overrideWithValue(repo),
          fileManagerProvider.overrideWith(
            () => _FakeNotifier(
              FileManagerState(
                files: [file],
                selectionMode: true,
                selected: {file.id},
              ),
            ),
          ),
          libraryStatsProvider.overrideWith(
            (ref) async => const LibraryStats(),
          ),
          libraryTagsProvider.overrideWith((ref) async => const []),
          // The repository is real here; its tag probe must not go out.
          libraryTagsSupportedProvider.overrideWithValue(const AsyncData(true)),
          slicerEnabledProvider.overrideWithValue(AsyncValue.data(true)),
          canRunPipelinesProvider.overrideWithValue(const AsyncData(false)),
        ],
      );
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('a server whose listing had variants offers grouping', (
      tester,
    ) async {
      await pumpSelecting(tester, variantsSeen: true);

      expect(byLogId('files.group_variants'), findsOneWidget);
    });

    testWidgets('an older listing, or none yet, offers no grouping', (
      tester,
    ) async {
      await pumpSelecting(tester, variantsSeen: false);
      expect(byLogId('files.group_variants'), findsNothing);
    });

    testWidgets('a listing that lands with the bar open updates it', (
      tester,
    ) async {
      // Asked once per opening before; a listing fetched meanwhile only
      // counted the next time selection mode started.
      final repo = await pumpSelecting(tester);
      expect(byLogId('files.group_variants'), findsNothing);

      repo.variantsCapability.observe(present: true);
      await tester.pumpAndSettle();

      expect(byLogId('files.group_variants'), findsOneWidget);
    });
  });

  group('add to queue (#3112)', () {
    const queuePath = '/api/v1/library/files/add-to-queue';

    /// Selection mode over one file, both repositories real on [dio].
    Future<void> pumpQueueing(
      WidgetTester tester, {
      required Dio dio,
      required bool canTarget,
      Set<int> selected = const {1},
      bool billing = false,
      List<Override> extra = const [],
      LibraryFile? grouped,
      QueueRepository? queue,
    }) async {
      final file =
          grouped ?? _file(filename: 'thing.gcode.3mf', fileType: 'gcode');
      await pumpPhone(
        tester,
        const FileManagerScreen(),
        overrides: [
          noServerProfileOverride,
          libraryRepositoryProvider.overrideWithValue(LibraryRepository(dio)),
          printersRepositoryProvider.overrideWithValue(PrintersRepository(dio)),
          if (queue != null) queueRepositoryProvider.overrideWithValue(queue),
          libraryQueueTargetProvider.overrideWithValue(AsyncData(canTarget)),
          fileManagerProvider.overrideWith(
            () => _FakeNotifier(
              FileManagerState(
                files: [file],
                selectionMode: grouped == null,
                selected: grouped == null ? selected : const {},
              ),
            ),
          ),
          libraryStatsProvider.overrideWith(
            (ref) async => const LibraryStats(),
          ),
          libraryTagsProvider.overrideWith((ref) async => const []),
          libraryTagsSupportedProvider.overrideWithValue(const AsyncData(true)),
          slicerEnabledProvider.overrideWithValue(AsyncValue.data(true)),
          canRunPipelinesProvider.overrideWithValue(const AsyncData(false)),
          serverUiFlagsProvider.overrideWith(
            (ref) async => {'billing_enabled': billing},
          ),
          serverSettingsOverride(const {}),
          ...extra,
        ],
      );
      await tester.pumpAndSettle();
    }

    // The bulk route takes no cost center, so on a billing server each file is
    // its own `POST /queue/`, charged to the center asked for.
    const lab = CostCenter(id: 5, name: 'Lab');
    const mine = CostCenter(id: 3, name: 'demo', isPrivate: true);
    final centersOverride = printableCostCentersProvider.overrideWith(
      (ref) async => const [mine, lab],
    );

    /// A queue repository over [dio] that answers every create with 200.
    ({QueueRepository repo, RequestLog log}) queueOn(Dio dio) {
      final log = captureRequests(dio);
      mockServer(dio)
        ..onGet(
          '/api/v1/updates/version',
          (s) =>
              s.reply(200, {'version': '0.2.4.9', 'repo': 'maziggy/bambuddy'}),
        )
        ..onPost(
          '/api/v1/queue/',
          (s) => s.reply(200, null),
          data: Matchers.any,
        );
      return (repo: QueueRepository(dio, ServerVersionService(dio)), log: log);
    }

    /// Every write that left, whichever route it took.
    List<String> writes(RequestLog log) => [
      for (final r in log.requests)
        if (r.method != 'GET') '${r.method} ${r.path}',
    ];

    List<Map<String, dynamic>> creates(RequestLog log) => [
      for (final r in log.requests)
        if (r.method == 'POST' && r.path == '/api/v1/queue/')
          r.data as Map<String, dynamic>,
    ];

    testWidgets(
      'on a billing server each file is charged to the center picked',
      (tester) async {
        final dio = testDio();
        final (:repo, :log) = queueOn(dio);
        await pumpQueueing(
          tester,
          dio: dio,
          canTarget: false,
          billing: true,
          selected: const {1, 2},
          queue: repo,
          extra: [centersOverride],
        );

        await tester.tap(byLogId('files.add_to_queue'));
        await tester.pumpAndSettle();
        expect(find.text(pl.fmQueueCostCenterTitle(2)), findsOneWidget);
        expect(find.text(pl.queueCostCenterPersonal('demo')), findsOneWidget);

        await tester.tap(find.text('Lab'));
        await tester.pumpAndSettle();

        final bodies = creates(log);
        expect([for (final b in bodies) b['library_file_id']], [1, 2]);
        expect([for (final b in bodies) b['cost_center_id']], [5, 5]);
        expect(find.text(pl.fmAddedToQueue), findsOneWidget);
      },
    );

    testWidgets('backing out of the center sheet queues nothing', (
      tester,
    ) async {
      final dio = testDio();
      final (:repo, :log) = queueOn(dio);
      await pumpQueueing(
        tester,
        dio: dio,
        canTarget: false,
        billing: true,
        selected: const {1, 2},
        queue: repo,
        extra: [centersOverride],
      );

      await tester.tap(byLogId('files.add_to_queue'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(byLogId('sheet.queue_cost_center'), findsNothing);
      expect(writes(log), isEmpty);
      expect(find.text(pl.fmAddedToQueue), findsNothing);
    });

    testWidgets('a session that cannot list its centers is told so', (
      tester,
    ) async {
      final dio = testDio();
      final (:repo, :log) = queueOn(dio);
      await pumpQueueing(
        tester,
        dio: dio,
        canTarget: false,
        billing: true,
        selected: const {1, 2},
        queue: repo,
        extra: [printableCostCentersProvider.overrideWith((ref) async => null)],
      );

      await tester.tap(byLogId('files.add_to_queue'));
      await tester.pumpAndSettle();

      expect(find.text(pl.queueBillingCostCentersRefused), findsOneWidget);
      expect(byLogId('sheet.queue_cost_center'), findsNothing);
      expect(writes(log), isEmpty);
    });

    testWidgets('a user with no center to print on is told so', (tester) async {
      final dio = testDio();
      final (:repo, :log) = queueOn(dio);
      await pumpQueueing(
        tester,
        dio: dio,
        canTarget: false,
        billing: true,
        selected: const {1, 2},
        queue: repo,
        extra: [
          printableCostCentersProvider.overrideWith((ref) async => const []),
        ],
      );

      await tester.tap(byLogId('files.add_to_queue'));
      await tester.pumpAndSettle();

      expect(find.text(pl.queueBillingNoCostCenter), findsOneWidget);
      expect(writes(log), isEmpty);
    });

    testWidgets('a file the server refuses does not stop the others', (
      tester,
    ) async {
      final dio = testDio();
      final log = captureRequests(dio);
      mockServer(dio)
        ..onGet(
          '/api/v1/updates/version',
          (s) =>
              s.reply(200, {'version': '0.2.4.9', 'repo': 'maziggy/bambuddy'}),
        )
        ..onPost(
          '/api/v1/queue/',
          (s) => s.reply(200, null),
          data: {'library_file_id': 1, 'quantity': 1, 'cost_center_id': 5},
        )
        ..onPost(
          '/api/v1/queue/',
          (s) => s.reply(400, {
            'detail': 'Estimated cost is required for cost center prints',
          }),
          data: {'library_file_id': 2, 'quantity': 1, 'cost_center_id': 5},
        )
        ..onPost(
          '/api/v1/queue/',
          (s) => s.reply(200, null),
          data: {'library_file_id': 3, 'quantity': 1, 'cost_center_id': 5},
        );
      await pumpQueueing(
        tester,
        dio: dio,
        canTarget: false,
        billing: true,
        selected: const {1, 2, 3},
        queue: QueueRepository(dio, ServerVersionService(dio)),
        extra: [centersOverride],
      );

      await tester.tap(byLogId('files.add_to_queue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lab'));
      await tester.pumpAndSettle();

      expect(creates(log), hasLength(3));
      expect(
        find.text(
          pl.fmAddedToQueuePartial(2, 3, pl.queueBillingEstimateRequired),
        ),
        findsOneWidget,
      );
    });

    testWidgets('files that all fail say why, in the user\'s words', (
      tester,
    ) async {
      final dio = testDio();
      mockServer(dio)
        ..onGet(
          '/api/v1/updates/version',
          (s) =>
              s.reply(200, {'version': '0.2.4.9', 'repo': 'maziggy/bambuddy'}),
        )
        ..onPost(
          '/api/v1/queue/',
          (s) => s.reply(400, {'detail': 'Cost center is inactive'}),
          data: Matchers.any,
        );
      await pumpQueueing(
        tester,
        dio: dio,
        canTarget: false,
        billing: true,
        selected: const {1, 2},
        queue: QueueRepository(dio, ServerVersionService(dio)),
        extra: [centersOverride],
      );

      await tester.tap(byLogId('files.add_to_queue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lab'));
      await tester.pumpAndSettle();

      expect(find.text(pl.queueBillingCostCenterInactive), findsOneWidget);
      expect(find.text(pl.fmAddedToQueue), findsNothing);
    });

    testWidgets('on a billing server a group is queued on the center picked', (
      tester,
    ) async {
      final dio = testDio();
      final (:repo, :log) = queueOn(dio);
      mockServer(dio).onGet(
        '/api/v1/library/variant-groups/by-file/1',
        (s) => s.reply(200, {
          'id': 9,
          'name': 'Benchy',
          'members': [
            {
              'library_file_id': 1,
              'target_model': 'X1C',
              'filename': 'a.3mf',
              'position': 0,
            },
            {
              'library_file_id': 2,
              'target_model': 'P1S',
              'filename': 'b.3mf',
              'position': 1,
            },
          ],
        }),
      );
      final file = _file(variantCount: 2);
      await pumpQueueing(
        tester,
        dio: dio,
        canTarget: false,
        billing: true,
        grouped: file,
        queue: repo,
        extra: [centersOverride],
      );

      await tester.tap(find.text(file.displayName));
      await tester.pumpAndSettle();
      await tester.tap(byLogId('file_actions.queue_variants'));
      await tester.pumpAndSettle();
      expect(find.text(pl.fmQueueCostCenterTitle(1)), findsOneWidget);
      await tester.tap(find.text('Lab'));
      await tester.pumpAndSettle();

      final body = creates(log).single;
      expect(body['cost_center_id'], 5);
      expect(body['variants'], hasLength(2));
    });

    testWidgets('on a billing server the file sheet opens the print form', (
      tester,
    ) async {
      await setUpQueueForm();
      final dio = testDio();
      mockServer(dio);
      final file = _file();
      await pumpQueueing(
        tester,
        dio: dio,
        canTarget: false,
        billing: true,
        grouped: file,
        extra: [
          ...queueFormOverrides(),
          printableCostCentersProvider.overrideWith((ref) async => const []),
        ],
      );

      await tester.tap(find.text(file.displayName));
      await tester.pumpAndSettle();
      await tester.tap(byLogId('file_actions.add_to_queue'));
      await tester.pumpAndSettle();

      expect(find.byType(QueueEditScreen), findsOneWidget);
    });

    testWidgets('a job queued through the form ends the selection', (
      tester,
    ) async {
      await setUpQueueForm();
      usePhoneWindow(tester, dp: 2400);
      final dio = testDio();
      mockServer(dio);
      await pumpQueueing(
        tester,
        dio: dio,
        canTarget: false,
        billing: true,
        extra: [
          ...queueFormOverrides(),
          printableCostCentersProvider.overrideWith(
            (ref) async => const [CostCenter(id: 1, name: 'Alice')],
          ),
        ],
      );
      expect(byLogId('files.add_to_queue'), findsOneWidget);

      await tester.tap(byLogId('files.add_to_queue'));
      await tester.pumpAndSettle();
      await openQueueFormPrinterSelect(tester);
      await tester.tap(byLogId('queue_edit.printer').first);
      await tester.pumpAndSettle();
      await submitQueueForm(tester);

      expect(find.byType(QueueEditScreen), findsNothing);
      expect(
        byLogId('files.add_to_queue'),
        findsNothing,
        reason: 'the selection bar goes with the selection',
      );
    });

    testWidgets('on a billing server one file opens the print form', (
      tester,
    ) async {
      // The form carries the cost center picker the bulk route has no field for.
      await setUpQueueForm();
      final dio = testDio();
      mockServer(dio);
      await pumpQueueing(
        tester,
        dio: dio,
        canTarget: false,
        billing: true,
        extra: [
          ...queueFormOverrides(),
          printableCostCentersProvider.overrideWith((ref) async => const []),
        ],
      );

      await tester.tap(byLogId('files.add_to_queue'));
      await tester.pumpAndSettle();

      expect(find.byType(QueueEditScreen), findsOneWidget);
      expect(byLogId('sheet.queue_cost_center'), findsNothing);
    });

    testWidgets('asks where, offering only active printers and their models', (
      tester,
    ) async {
      final dio = testDio();
      mockServer(dio)
        ..onGet(
          '/api/v1/printers/',
          (s) => s.reply(200, [
            {'id': 7, 'name': 'Lab', 'model': 'X1C', 'is_active': true},
            {'id': 8, 'name': 'Shed', 'model': 'P1S', 'is_active': false},
          ]),
        )
        ..onPost(
          queuePath,
          (s) => s.reply(200, {
            'added': [{}],
            'errors': [],
          }),
          data: {
            'file_ids': [1],
            'printer_id': 7,
          },
        );
      await pumpQueueing(tester, dio: dio, canTarget: true);

      await tester.tap(byLogId('files.add_to_queue'));
      await tester.pumpAndSettle();

      expect(find.text(pl.queueEditAnyModel('X1C')), findsOneWidget);
      expect(find.text(pl.queueEditAnyModel('P1S')), findsNothing);
      expect(find.text('Shed'), findsNothing);

      await tester.tap(find.text('Lab'));
      await tester.pumpAndSettle();

      expect(find.text(pl.fmAddedToQueue), findsOneWidget);
    });

    testWidgets('only inactive printers: nothing to choose, nothing asked', (
      tester,
    ) async {
      final dio = testDio();
      mockServer(dio)
        ..onGet(
          '/api/v1/printers/',
          (s) => s.reply(200, [
            {'id': 8, 'name': 'Shed', 'model': 'P1S', 'is_active': false},
          ]),
        )
        ..onPost(
          queuePath,
          (s) => s.reply(200, {
            'added': [{}],
            'errors': [],
          }),
          data: {
            'file_ids': [1],
          },
        );
      await pumpQueueing(tester, dio: dio, canTarget: true);

      await tester.tap(byLogId('files.add_to_queue'));
      await tester.pumpAndSettle();

      expect(byLogId('sheet.queue_target'), findsNothing);
      expect(find.text(pl.fmAddedToQueue), findsOneWidget);
    });

    testWidgets(
      'a partial batch counts what was selected, not what came back',
      (tester) async {
        final dio = testDio();
        mockServer(dio).onPost(
          queuePath,
          (s) => s.reply(200, {
            'added': [{}],
            'errors': [
              {
                'file_id': 2,
                'error':
                    'File was sliced for P1S and cannot be dispatched to X1C '
                    'printers',
              },
              // Unreadable, so it is no reason — but it is still a file.
              {'file_id': 3},
            ],
          }),
          data: {
            'file_ids': [1, 2, 3],
          },
        );
        await pumpQueueing(
          tester,
          dio: dio,
          canTarget: false,
          selected: {1, 2, 3},
        );

        await tester.tap(byLogId('files.add_to_queue'));
        await tester.pumpAndSettle();

        final l = pl;
        expect(
          find.text(l.fmAddedToQueuePartial(1, 3, l.fmQueueErrWrongModel)),
          findsOneWidget,
        );
      },
    );

    testWidgets('an older server is not asked, and gets the plain request', (
      tester,
    ) async {
      final dio = testDio();
      mockServer(dio).onPost(
        queuePath,
        (s) => s.reply(200, {
          'added': [{}],
          'errors': [],
        }),
        data: {
          'file_ids': [1],
        },
      );
      await pumpQueueing(tester, dio: dio, canTarget: false);

      await tester.tap(byLogId('files.add_to_queue'));
      await tester.pumpAndSettle();

      expect(byLogId('sheet.queue_target'), findsNothing);
      expect(find.text(pl.fmAddedToQueue), findsOneWidget);
    });

    testWidgets('a batch that queued nothing says why, in the user\'s words', (
      tester,
    ) async {
      // Before #3112 this was a 200, and the screen said "Added to queue".
      final dio = testDio();
      mockServer(dio).onPost(
        queuePath,
        (s) => s.reply(200, {
          'added': [],
          'errors': [
            {
              'file_id': 1,
              'filename': 'thing.3mf',
              'error':
                  'Not a sliced file. Only .gcode or .gcode.3mf files can be '
                  'printed.',
            },
          ],
        }),
        data: {
          'file_ids': [1],
        },
      );
      await pumpQueueing(tester, dio: dio, canTarget: false);

      await tester.tap(byLogId('files.add_to_queue'));
      await tester.pumpAndSettle();

      expect(find.text(pl.fmAddedToQueue), findsNothing);
      expect(find.text(pl.fmQueueErrNotSliced), findsOneWidget);
    });
  });

  group('photos, link and notes (#3077)', () {
    testWidgets('the sheet offers the details where the server has them', (
      tester,
    ) async {
      final file = _file();
      await pump(tester, file: file, fileExtras: true);
      await openFileSheet(tester, file);

      expect(byLogId('file_actions.details'), findsOneWidget);
    });

    testWidgets('an older server gets no details entry', (tester) async {
      final file = _file();
      await pump(tester, file: file);
      await openFileSheet(tester, file);

      expect(byLogId('file_actions.details'), findsNothing);
    });

    testWidgets('the tile marks photos and a link', (tester) async {
      await pump(
        tester,
        file: _file(photoCount: 3, externalUrl: 'https://example.com'),
      );

      expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.byIcon(Icons.link), findsOneWidget);
      expect(find.byIcon(Icons.notes), findsNothing);
    });
  });

  group('the listing', () {
    testWidgets('renders a file from the state', (tester) async {
      await pump(tester, file: _file(filename: 'bracket.3mf'));
      expect(find.text('bracket.3mf'), findsOneWidget);
    });
  });

  group('the file action sheet fits', () {
    testWidgets('a model file with variants, the tallest case', (tester) async {
      // The combination that overflowed: slice, two variant rows, tags, and the
      // three local-file actions, over a 56px thumbnail header. As a Column this
      // reported "RenderFlex overflowed by 35 pixels" and the last actions were
      // unreachable.
      final file = _file(variantCount: 2);
      await pump(tester, file: file);
      await openFileSheet(tester, file);

      expect(
        tester.takeException(),
        isNull,
        reason: 'the sheet must scroll rather than overflow',
      );
    });

    testWidgets('the last action is reachable by scrolling', (tester) async {
      // Not just "no exception": the point of the fix is that the actions past
      // the fold can actually be got at.
      final file = _file(variantCount: 2);
      await pump(tester, file: file);
      await openFileSheet(tester, file);

      final sheet = find.byType(BottomSheet);
      await tester.dragUntilVisible(
        find.text(pl.fmDelete),
        sheet,
        const Offset(0, -60),
      );
      expect(find.text(pl.fmDelete), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a short viewport does not overflow either', (tester) async {
      // Landscape-ish height, where even fewer rows stop fitting.
      final file = _file(variantCount: 2);
      await pump(tester, file: file, size: const Size(411, 520));
      await openFileSheet(tester, file);
      expect(tester.takeException(), isNull);
    });
  });

  group('what the sheet offers', () {
    testWidgets('a sliceable model offers slicing, not printing', (
      tester,
    ) async {
      // A 3MF that is not gcode cannot be printed as-is, and the slice gate is
      // on: `canSlice = slicerEnabled && !file.isPrintable`.
      final file = _file();
      await pump(tester, file: file);
      await openFileSheet(tester, file);

      expect(find.text(pl.sliceAction), findsOneWidget);
      expect(find.text(pl.fmPrint), findsNothing);
    });

    testWidgets('slicing is not offered when the server has it switched off', (
      tester,
    ) async {
      final file = _file();
      await pump(tester, file: file, slicerEnabled: false);
      await openFileSheet(tester, file);
      expect(find.text(pl.sliceAction), findsNothing);
    });

    testWidgets('a gcode file offers printing, not slicing', (tester) async {
      // Already sliced: there is nothing to re-slice, so the row is gone.
      final file = _file(filename: 'ready.gcode', fileType: 'gcode');
      await pump(tester, file: file);
      await openFileSheet(tester, file);

      expect(find.text(pl.fmPrint), findsOneWidget);
      expect(find.text(pl.sliceAction), findsNothing);
    });

    testWidgets('a server with tags offers the tag action', (tester) async {
      final file = _file();
      await pump(tester, file: file);
      await openFileSheet(tester, file);
      expect(find.textContaining(pl.fmTags), findsOneWidget);
    });

    testWidgets('a server with no tag routes hides the tag action', (
      tester,
    ) async {
      final file = _file();
      await pump(tester, file: file, tags: null);
      await openFileSheet(tester, file);
      expect(find.textContaining('tag'), findsNothing);
      expect(find.textContaining(pl.fmTags), findsNothing);
    });
  });

  testWidgets('an older server loses the tag controls once, not every visit', (
    tester,
  ) async {
    // The catalog dies with the screen; the latch lives in the repository.
    // Before, every visit showed the controls and then took them away.
    final dio = testDio();
    mockServer(dio).onGet(
      '/api/v1/library/tags',
      (s) => s.reply(404, {'detail': 'Not Found'}),
    );
    final sent = captureRequests(dio);
    final repo = LibraryRepository(dio);

    Future<void> visit() async {
      await pumpPhone(
        tester,
        const FileManagerScreen(),
        overrides: [
          noServerProfileOverride,
          libraryRepositoryProvider.overrideWithValue(repo),
          fileManagerProvider.overrideWith(
            () => _FakeNotifier(FileManagerState(files: [_file()])),
          ),
          libraryStatsProvider.overrideWith(
            (ref) async => const LibraryStats(),
          ),
          slicerEnabledProvider.overrideWithValue(AsyncValue.data(true)),
          canRunPipelinesProvider.overrideWithValue(const AsyncData(false)),
        ],
      );
      await tester.pumpAndSettle();
    }

    await visit();
    expect(byLogId('files.tag_filter'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await visit();

    expect(byLogId('files.tag_filter'), findsNothing);
    expect(
      sent.paths.where((p) => p == '/api/v1/library/tags'),
      hasLength(1),
      reason: 'the answer outlives the screen that asked',
    );
  });

  group('the sort sheet fits', () {
    testWidgets('six options do not overflow', (tester) async {
      await pump(tester, file: _file());
      await tester.tap(find.byTooltip(pl.fmSortBy));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('folder rights (#3201)', () {
    const mine = LibraryFolder(id: 1, name: 'Mine');
    const theirs = LibraryFolder(
      id: 2,
      name: 'Theirs',
      canWrite: false,
      canRename: false,
      canDelete: false,
    );
    const mount = LibraryFolder(
      id: 3,
      name: 'NAS',
      isExternal: true,
      externalReadonly: true,
    );
    final file = _file();

    Future<void> pumpAt(WidgetTester tester, {int? folderId}) async {
      await pumpPhone(
        tester,
        const FileManagerScreen(),
        overrides: [
          noServerProfileOverride,
          fileManagerProvider.overrideWith(
            () => _FakeNotifier(
              FileManagerState(
                allFolders: const [mine, theirs, mount],
                currentFolderId: folderId,
                files: [file],
              ),
            ),
          ),
          libraryStatsProvider.overrideWith(
            (ref) async => const LibraryStats(),
          ),
          libraryTagsProvider.overrideWith((ref) async => const []),
          libraryTagsSupportedProvider.overrideWithValue(
            const AsyncData(false),
          ),
          slicerEnabledProvider.overrideWithValue(const AsyncData(true)),
          canRunPipelinesProvider.overrideWithValue(const AsyncData(true)),
          libraryFileExtrasProvider.overrideWithValue(const AsyncData(false)),
        ],
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a folder the user may not touch offers no actions', (
      tester,
    ) async {
      await pumpAt(tester);
      Finder actionsOf(String name) => find.descendant(
        of: find.ancestor(
          of: find.text(name),
          matching: byLogId('files.folder'),
        ),
        matching: byLogId('files.folder_actions'),
      );
      expect(actionsOf('Theirs'), findsNothing);
      expect(actionsOf('Mine'), findsOneWidget);
    });

    testWidgets('only writable folders are move targets', (tester) async {
      await pumpAt(tester);
      await tester.tap(find.text(file.displayName));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        byLogId('file_actions.move'),
        find.byType(BottomSheet),
        const Offset(0, -60),
      );
      await tester.tap(byLogId('file_actions.move'));
      await tester.pumpAndSettle();

      expect(byLogId('files.move_target'), findsOneWidget);
      expect(
        find.descendant(
          of: byLogId('files.move_target'),
          matching: find.text('Mine'),
        ),
        findsOneWidget,
      );
      expect(find.text(pl.fmRoot), findsWidgets);
    });

    testWidgets('nothing can be added inside a folder that is not writable', (
      tester,
    ) async {
      await pumpAt(tester, folderId: 2);
      expect(byLogId('files.create'), findsNothing);
    });

    testWidgets('a read-only mount takes a subfolder, not an upload', (
      tester,
    ) async {
      await pumpAt(tester, folderId: 3);
      await tester.tap(byLogId('files.create'));
      await tester.pumpAndSettle();
      expect(byLogId('files.new_folder'), findsOneWidget);
      expect(byLogId('files.upload'), findsNothing);
    });

    testWidgets('a writable folder keeps the add button', (tester) async {
      await pumpAt(tester, folderId: 1);
      expect(byLogId('files.create'), findsOneWidget);
    });
  });
}
