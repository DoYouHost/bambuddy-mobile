import 'package:bambuddy_mobile/core/models/library_file.dart';
import 'package:bambuddy_mobile/core/models/library_stats.dart';
import 'package:bambuddy_mobile/core/models/library_tag.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/features/files/file_manager_providers.dart';
import 'package:bambuddy_mobile/features/files/file_manager_screen.dart';
import 'package:bambuddy_mobile/features/pipelines/pipelines_providers.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';

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
}) => LibraryFile(
  id: id,
  filename: filename,
  fileType: fileType,
  fileSize: 1024,
  printCount: 0,
  isExternal: isExternal,
  variantCount: variantCount,
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
        find.text('Usuń'),
        sheet,
        const Offset(0, -60),
      );
      expect(find.text('Usuń'), findsOneWidget);
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

      expect(find.text('Potnij'), findsOneWidget);
      expect(find.text('Drukuj'), findsNothing);
    });

    testWidgets('slicing is not offered when the server has it switched off', (
      tester,
    ) async {
      final file = _file();
      await pump(tester, file: file, slicerEnabled: false);
      await openFileSheet(tester, file);
      expect(find.text('Potnij'), findsNothing);
    });

    testWidgets('a gcode file offers printing, not slicing', (tester) async {
      // Already sliced: there is nothing to re-slice, so the row is gone.
      final file = _file(filename: 'ready.gcode', fileType: 'gcode');
      await pump(tester, file: file);
      await openFileSheet(tester, file);

      expect(find.text('Drukuj'), findsOneWidget);
      expect(find.text('Potnij'), findsNothing);
    });

    testWidgets('a server with tags offers the tag action', (tester) async {
      final file = _file();
      await pump(tester, file: file);
      await openFileSheet(tester, file);
      expect(find.textContaining('Tagi'), findsOneWidget);
    });

    testWidgets('a server with no tag routes hides the tag action', (
      tester,
    ) async {
      final file = _file();
      await pump(tester, file: file, tags: null);
      await openFileSheet(tester, file);
      expect(find.textContaining('tag'), findsNothing);
      expect(find.textContaining('Tagi'), findsNothing);
    });
  });

  testWidgets('an older server loses the tag controls once, not every visit', (
    tester,
  ) async {
    // The catalog dies with the screen; the latch lives in the repository.
    // Before, every visit showed the controls and then took them away.
    final dio = testDio();
    DioAdapter(dio: dio).onGet(
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
      await tester.tap(find.byTooltip('Sortuj według'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
