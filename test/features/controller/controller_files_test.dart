import 'dart:async';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/format/duration_format.dart';
import 'package:bambuddy_mobile/core/models/library_file.dart';
import 'package:bambuddy_mobile/core/models/library_folder.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_files.dart';
import 'package:bambuddy_mobile/features/controller/controller_screen.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/files/file_manager_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

const _window = MethodChannel('page.codeberg.morganmlgman.bambuddy/window');

/// A library the test drives: a fixed tree, and a record of what was asked of it.
class _Library extends FileManagerNotifier {
  _Library({
    this.folders = const [],
    this.filesByFolder = const {},
    this.failWith,
    this.gate,
    this.startFolderId,
    this.openFailsWith,
    this.openGate,
    this.refreshGate,
  });

  final List<LibraryFolder> folders;

  /// Files by folder id; the root is `null`.
  final Map<int?, List<LibraryFile>> filesByFolder;

  /// What the listing fails with, when it does.
  final Object? failWith;

  /// Held until completed, to look at the loading state.
  final Completer<void>? gate;

  /// The folder the library opens in; one the tree does not hold, to see the
  /// way out of it.
  final int? startFolderId;

  /// What a step into a folder fails with, after the first listing succeeded.
  final Object? openFailsWith;

  /// Holds a step into a folder, and a refresh, until completed.
  final Completer<void>? openGate;
  final Completer<void>? refreshGate;

  /// How often the library was built, which is how often it is fetched.
  final builds = <int>[];

  /// How often it was let go of.
  final disposals = <int>[];

  /// What the tab asked of it, in order.
  final calls = <String>[];

  @override
  Future<FileManagerState> build() async {
    builds.add(builds.length + 1);
    ref.onDispose(() => disposals.add(disposals.length + 1));
    await gate?.future;
    if (failWith != null) throw failWith!;
    return FileManagerState(
      allFolders: folders,
      currentFolderId: startFolderId,
      files: filesByFolder[startFolderId] ?? const [],
    );
  }

  @override
  Future<void> openFolder(int? folderId) async {
    calls.add('open $folderId');
    final before = state;
    if (openGate != null || openFailsWith != null) {
      state = const AsyncLoading<FileManagerState>().copyWithPrevious(before);
      await openGate?.future;
      if (openFailsWith != null) {
        state = AsyncError<FileManagerState>(
          openFailsWith!,
          StackTrace.empty,
        ).copyWithPrevious(before);
        return;
      }
    }
    state = AsyncData(
      before.requireValue.copyWith(
        currentFolderId: folderId,
        clearCurrentFolder: folderId == null,
        files: filesByFolder[folderId] ?? const [],
      ),
    );
  }

  @override
  Future<void> refresh() async {
    calls.add('refresh');
    final gate = refreshGate;
    if (gate == null) return;
    final before = state;
    state = const AsyncLoading<FileManagerState>().copyWithPrevious(before);
    await gate.future;
    state = before;
  }
}

LibraryFile _file(
  int id,
  String filename, {
  String type = 'gcode',
  String? model,
  int? seconds,
  double? grams,
  String? printName,
}) => LibraryFile(
  id: id,
  filename: filename,
  fileType: type,
  fileSize: 2048,
  printCount: 0,
  printName: printName,
  slicedForModel: model,
  printTimeSeconds: seconds,
  filamentUsedGrams: grams,
);

void main() {
  setUpAll(loadAppFonts);

  late _Library library;

  Future<void> pump(
    WidgetTester tester, {
    _Library? lib,
    String? model = 'P1S',
    Size size = const Size(844, 390),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_window, (call) async => null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, (_) async {
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_window, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    library = lib ?? _Library();
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          fixedDashboardOverride(
            DashboardState(
              printers: [
                PrinterWithStatus(
                  printer: Printer(id: 1, name: 'X1C Warsztat', model: model),
                  status: const PrinterStatus(
                    id: 1,
                    connected: true,
                    state: 'IDLE',
                  ),
                ),
              ],
            ),
          ),
          inertStatusesOverride,
          inertSmartPlugsOverride,
          fileManagerProvider.overrideWith(() => library),
        ],
        child: plApp(const ControllerScreen(printerId: 1)),
      ),
    );
    await settle(tester);
  }

  Future<void> select(WidgetTester tester, ControllerTab tab) async {
    await tester.tap(byLogId(tab.logId));
    await settle(tester);
  }

  Future<void> openFiles(WidgetTester tester) =>
      select(tester, ControllerTab.files);

  group('the tab', () {
    testWidgets('Files sits between Filament and Settings', (tester) async {
      await pump(tester);

      final tabs = ControllerTab.values;
      expect(
        tabs.indexOf(ControllerTab.files),
        tabs.indexOf(ControllerTab.filament) + 1,
      );
      expect(
        tabs.indexOf(ControllerTab.settings),
        tabs.indexOf(ControllerTab.files) + 1,
      );
      expect(find.text(pl.controllerTabFiles), findsOneWidget);
      expect(find.byType(ControllerFiles), findsNothing);

      await openFiles(tester);

      expect(find.byType(ControllerFiles), findsOneWidget);
    });

    testWidgets('nothing is fetched until Files is first selected', (
      tester,
    ) async {
      await pump(tester);

      await select(tester, ControllerTab.heat);
      await select(tester, ControllerTab.filament);

      expect(library.builds, isEmpty);

      await openFiles(tester);

      expect(library.builds, hasLength(1));
    });

    testWidgets('leaving Files and coming back does not start over', (
      tester,
    ) async {
      await pump(tester);

      await openFiles(tester);
      await select(tester, ControllerTab.heat);
      await openFiles(tester);
      await select(tester, ControllerTab.move);
      await openFiles(tester);

      expect(library.builds, hasLength(1));
    });

    testWidgets('leaving the controller lets the library go', (tester) async {
      await pump(tester);
      await openFiles(tester);
      expect(library.disposals, isEmpty);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(library.disposals, hasLength(1));
    });

    testWidgets('a keyboard does not resize the body', (tester) async {
      await pump(tester);
      await openFiles(tester);
      final before = tester.getSize(find.byType(ControllerFiles));

      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      addTearDown(tester.view.resetViewInsets);
      await settle(tester);

      expect(tester.getSize(find.byType(ControllerFiles)), before);
    });
  });

  group('the listing', () {
    _Library tree() => _Library(
      folders: const [
        LibraryFolder(id: 1, name: 'Alpha', fileCount: 3),
        LibraryFolder(id: 2, name: 'Bravo', fileCount: 1),
      ],
      filesByFolder: {
        null: [
          _file(
            10,
            'benchy.gcode.3mf',
            model: 'P1S',
            seconds: 11520,
            grams: 45,
          ),
          _file(11, 'vase.gcode.3mf', model: 'H2D', seconds: 600, grams: 9),
          _file(12, 'bracket.stl', type: 'stl'),
        ],
      },
    );

    testWidgets('folders come first, then files', (tester) async {
      await pump(tester, lib: tree());
      await openFiles(tester);

      final folders = byLogId('controller.files.folder');
      final files = byLogId('controller.files.file');
      final lastFolder = tester.getRect(folders.last);
      final firstFile = tester.getRect(files.first);

      expect(folders, findsNWidgets(2));
      expect(files, findsNWidgets(3));
      // In reading order: a row further down, or further along the same row.
      expect(
        firstFile.top > lastFolder.top ||
            (firstFile.top == lastFolder.top &&
                firstFile.left > lastFolder.left),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a folder says how many items it holds', (tester) async {
      await pump(tester, lib: tree());
      await openFiles(tester);

      expect(find.text(pl.fmFolderItems(3)), findsOneWidget);
      expect(find.text(pl.fmFolderItems(1)), findsOneWidget);
    });

    testWidgets('a sliced file shows its time and its filament', (
      tester,
    ) async {
      await pump(tester, lib: tree());
      await openFiles(tester);

      expect(find.textContaining('45 g'), findsOneWidget);
      expect(find.textContaining(formatSeconds(pl, 11520)), findsOneWidget);
    });

    testWidgets('a print name stands in for the file name', (tester) async {
      await pump(
        tester,
        lib: _Library(
          filesByFolder: {
            null: [_file(1, 'x.gcode.3mf', printName: 'Test boat')],
          },
        ),
      );
      await openFiles(tester);

      expect(find.text('Test boat'), findsOneWidget);
      expect(find.text('x.gcode.3mf'), findsNothing);
    });

    testWidgets('only a file this printer cannot take, or a model, is marked', (
      tester,
    ) async {
      await pump(tester, lib: tree());
      await openFiles(tester);

      expect(find.text('H2D'), findsOneWidget);
      expect(find.text(pl.controllerFileNotSliced), findsOneWidget);
      // The H2D chip and the unsliced one carry the warning; the P1S chip none.
      expect(find.byIcon(Icons.warning_amber_rounded), findsNWidgets(2));
    });

    testWidgets('a printer of the same family takes the file too', (
      tester,
    ) async {
      await pump(tester, lib: tree(), model: 'X1C');
      await openFiles(tester);

      expect(find.byIcon(Icons.warning_amber_rounded), findsNWidgets(2));
    });

    testWidgets('a printer of an unknown model blocks no file', (tester) async {
      await pump(tester, lib: tree(), model: null);
      await openFiles(tester);

      // Only the unsliced file is marked: nothing can be said of the model.
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });
  });

  group('moving about', () {
    _Library tree() => _Library(
      folders: const [
        LibraryFolder(id: 1, name: 'Alpha'),
        LibraryFolder(id: 3, name: 'Charlie', parentId: 1),
      ],
      filesByFolder: {
        null: [_file(10, 'benchy.gcode.3mf', model: 'P1S')],
        1: [_file(20, 'tower.gcode.3mf', model: 'P1S')],
        3: [],
      },
    );

    testWidgets('a folder opens, and the path says where the user is', (
      tester,
    ) async {
      await pump(tester, lib: tree());
      await openFiles(tester);
      expect(find.text(pl.fmRoot), findsOneWidget);

      await tester.tap(find.text('Alpha'));
      await settle(tester);

      expect(library.calls, ['open 1']);
      expect(find.text('tower.gcode.3mf'), findsOneWidget);
      expect(find.text('benchy.gcode.3mf'), findsNothing);
      expect(find.textContaining('${pl.fmRoot}  /  Alpha'), findsOneWidget);
    });

    testWidgets('Up is off at the root', (tester) async {
      await pump(tester, lib: tree());
      await openFiles(tester);

      final up = tester.widget<FilledButton>(
        find.descendant(
          of: byLogId('controller.files.up'),
          matching: find.byType(FilledButton),
        ),
      );

      expect(up.onPressed, isNull);
    });

    testWidgets('Up goes to the parent, and from the first level to the root', (
      tester,
    ) async {
      await pump(tester, lib: tree());
      await openFiles(tester);
      await tester.tap(find.text('Alpha'));
      await settle(tester);
      await tester.tap(find.text('Charlie'));
      await settle(tester);

      await tester.tap(byLogId('controller.files.up'));
      await settle(tester);
      await tester.tap(byLogId('controller.files.up'));
      await settle(tester);

      expect(library.calls, ['open 1', 'open 3', 'open 1', 'open null']);
      expect(find.text('benchy.gcode.3mf'), findsOneWidget);
    });

    testWidgets('an empty folder says it is empty', (tester) async {
      await pump(tester, lib: tree());
      await openFiles(tester);
      await tester.tap(find.text('Alpha'));
      await settle(tester);
      await tester.tap(find.text('Charlie'));
      await settle(tester);

      expect(find.text(pl.fmEmpty), findsOneWidget);
    });

    testWidgets('Sort steps through the six orders and comes round', (
      tester,
    ) async {
      await pump(tester, lib: tree());
      await openFiles(tester);
      final labels = [
        pl.fmSortDateNewest,
        pl.fmSortDateOldest,
        pl.fmSortNameAZ,
        pl.fmSortNameZA,
        pl.fmSortSizeLargest,
        pl.fmSortSizeSmallest,
      ];

      for (final label in labels) {
        expect(find.text(label), findsOneWidget);
        await tester.tap(byLogId('controller.files.sort'));
        await settle(tester);
      }

      expect(find.text(labels.first), findsOneWidget);
    });

    testWidgets('Refresh asks the library to refresh', (tester) async {
      await pump(tester, lib: tree());
      await openFiles(tester);

      await tester.tap(byLogId('controller.files.refresh'));
      await settle(tester);

      expect(library.calls, ['refresh']);
    });
  });

  group('when something goes wrong after the first listing', () {
    _Library tree({
      Object? openFailsWith,
      Completer<void>? openGate,
      Completer<void>? refreshGate,
    }) => _Library(
      folders: const [
        LibraryFolder(id: 1, name: 'Alpha'),
        LibraryFolder(id: 2, name: 'Bravo'),
      ],
      filesByFolder: {
        null: [_file(10, 'benchy.gcode.3mf', model: 'P1S')],
      },
      openFailsWith: openFailsWith,
      openGate: openGate,
      refreshGate: refreshGate,
    );

    FilledButton button(WidgetTester tester, String id) =>
        tester.widget<FilledButton>(
          find.descendant(of: byLogId(id), matching: find.byType(FilledButton)),
        );

    testWidgets('a failed step into a folder says so, not the old folder', (
      tester,
    ) async {
      await pump(tester, lib: tree(openFailsWith: Exception('down')));
      await openFiles(tester);

      await tester.tap(find.text('Alpha'));
      await settle(tester);

      expect(find.text(pl.connectFailed), findsOneWidget);
      expect(find.text('benchy.gcode.3mf'), findsNothing);
    });

    testWidgets('while a step is under way Up and the folders wait', (
      tester,
    ) async {
      final gate = Completer<void>();
      await pump(tester, lib: tree(openGate: gate));
      await openFiles(tester);

      await tester.tap(find.text('Alpha'));
      await tester.pump();
      await tester.tap(find.text('Bravo'), warnIfMissed: false);
      await tester.pump();

      expect(library.calls, ['open 1']);
      expect(button(tester, 'controller.files.up').onPressed, isNull);

      gate.complete();
      await settle(tester);
    });

    testWidgets('Up pressed twice does not step to the same folder twice', (
      tester,
    ) async {
      final gate = Completer<void>();
      await pump(
        tester,
        lib: _Library(
          folders: const [
            LibraryFolder(id: 1, name: 'Alpha'),
            LibraryFolder(id: 3, name: 'Charlie', parentId: 1),
          ],
          startFolderId: 3,
          openGate: gate,
        ),
      );
      await openFiles(tester);

      await tester.tap(byLogId('controller.files.up'));
      await tester.pump();
      expect(button(tester, 'controller.files.up').onPressed, isNull);
      await tester.tap(byLogId('controller.files.up'), warnIfMissed: false);
      await tester.pump();

      // The second press would have read Charlie again and sent Alpha again,
      // where the user meant the root.
      expect(library.calls, ['open 1']);

      gate.complete();
      await settle(tester);
    });

    testWidgets('a folder the tree does not hold still has a way up', (
      tester,
    ) async {
      await pump(tester, lib: _Library(startFolderId: 7));
      await openFiles(tester);

      expect(button(tester, 'controller.files.up').onPressed, isNotNull);

      await tester.tap(byLogId('controller.files.up'));
      await settle(tester);

      expect(library.calls, ['open null']);
    });

    testWidgets('Refresh is off while nothing is loaded', (tester) async {
      await pump(tester, lib: _Library(failWith: Exception('down')));
      await openFiles(tester);

      expect(button(tester, 'controller.files.refresh').onPressed, isNull);
    });

    testWidgets('a refresh shows its progress and then is over', (
      tester,
    ) async {
      final gate = Completer<void>();
      await pump(tester, lib: tree(refreshGate: gate));
      await openFiles(tester);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.tap(byLogId('controller.files.refresh'));
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(button(tester, 'controller.files.refresh').onPressed, isNull);
      // The listing stays while it is refreshed.
      expect(find.text('benchy.gcode.3mf'), findsOneWidget);

      gate.complete();
      await settle(tester);

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(button(tester, 'controller.files.refresh').onPressed, isNotNull);
    });
  });

  group('when the listing is not there', () {
    testWidgets('it shows a spinner while the library loads', (tester) async {
      final gate = Completer<void>();
      await pump(tester, lib: _Library(gate: gate));
      await tester.tap(byLogId(ControllerTab.files.logId));
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete();
      await settle(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a library with nothing in it says so', (tester) async {
      await pump(tester);
      await openFiles(tester);

      expect(find.text(pl.fmEmpty), findsOneWidget);
    });

    testWidgets('a server that cannot be reached offers to try again', (
      tester,
    ) async {
      await pump(tester, lib: _Library(failWith: Exception('down')));
      await openFiles(tester);

      expect(find.text(pl.connectFailed), findsOneWidget);
      final before = library.builds.length;

      await tester.tap(byLogId('controller.files.retry'));
      await settle(tester);

      expect(library.builds.length, greaterThan(before));
    });

    testWidgets('a refused account is told so, with nothing to retry', (
      tester,
    ) async {
      await pump(
        tester,
        lib: _Library(
          failWith: const AuthException(
            AppErrorCode.forbidden,
            detail: 'library:read',
          ),
        ),
      );
      await openFiles(tester);

      expect(find.textContaining('library:read'), findsOneWidget);
      expect(byLogId('controller.files.retry'), findsNothing);
      expect(find.text(pl.connectFailed), findsNothing);
    });
  });

  group('on a small screen', () {
    testWidgets('long names in a narrow window overflow nothing', (
      tester,
    ) async {
      await pump(
        tester,
        size: const Size(740, 320),
        lib: _Library(
          folders: const [
            LibraryFolder(
              id: 1,
              name:
                  'Bardzo długa nazwa folderu, która nie mieści się w kafelku',
              fileCount: 12,
            ),
          ],
          filesByFolder: {
            null: [
              _file(
                1,
                'ogromny_model_z_bardzo_dluga_nazwa_pliku_dla_drukarki.gcode.3mf',
                model: 'Bambu Lab X1 Carbon',
                seconds: 360000,
                grams: 1234,
              ),
            ],
          },
        ),
      );
      await openFiles(tester);

      expect(tester.takeException(), isNull);
    });
  });
}
