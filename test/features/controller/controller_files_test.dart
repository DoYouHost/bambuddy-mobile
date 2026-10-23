import 'dart:async';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/format/duration_format.dart';
import 'package:bambuddy_mobile/core/models/library_file.dart';
import 'package:bambuddy_mobile/core/models/library_folder.dart';
import 'package:bambuddy_mobile/core/models/library_stats.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_file_dialog.dart';
import 'package:bambuddy_mobile/features/controller/controller_files.dart';
import 'package:bambuddy_mobile/features/controller/controller_print.dart';
import 'package:bambuddy_mobile/features/controller/controller_screen.dart';
import 'package:bambuddy_mobile/features/files/file_manager_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import 'controller_harness.dart';

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
  Future<void> setQuery(String q) async {
    calls.add('query $q');
    state = AsyncData(
      state.requireValue.copyWith(
        query: q,
        allFiles: [for (final files in filesByFolder.values) ...files],
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

/// A repository that records what the tab asked of it and answers at the
/// test's pace.
class _Repo extends LibraryRepository {
  _Repo() : super(testDio());

  final deleted = <int>[];
  final uploads = <({String path, String name, int? folderId})>[];

  /// What a delete and an upload fail with, when they do.
  Object? deleteFails;
  Object? uploadFails;

  /// Holds an upload, after its first progress report, until completed.
  Completer<void>? uploadGate;

  @override
  Future<void> deleteFile(int fileId) async {
    if (deleteFails != null) throw deleteFails!;
    deleted.add(fileId);
  }

  @override
  Future<void> uploadFile({
    required String filePath,
    required String filename,
    int? folderId,
    void Function(double? progress)? onProgress,
  }) async {
    uploads.add((path: filePath, name: filename, folderId: folderId));
    onProgress?.call(0.25);
    await uploadGate?.future;
    if (uploadFails != null) throw uploadFails!;
  }
}

/// The system picker, answering what the test says: a file, or nothing.
class _Picker extends FilePicker {
  _Picker(this.answer);

  /// Null is a cancelled dialog.
  PlatformFile? answer;
  Completer<void>? gate;
  int opened = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    opened++;
    await gate?.future;
    final file = answer;
    return file == null ? null : FilePickerResult([file]);
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
  bool external = false,
  int? folderId,
}) => LibraryFile(
  id: id,
  filename: filename,
  isExternal: external,
  folderId: folderId,
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
    List<Override> extra = const [],
  }) async {
    library = lib ?? _Library();
    await pumpControllerScreen(
      tester,
      model: model,
      size: size,
      overrides: [fileManagerProvider.overrideWith(() => library), ...extra],
    );
  }

  Future<void> select(WidgetTester tester, ControllerTab tab) async {
    await tester.tap(byLogId(tab.logId));
    await settle(tester);
  }

  /// The Prints tab opens on its Files view.
  Future<void> openFiles(WidgetTester tester) =>
      select(tester, ControllerTab.prints);

  group('the tab', () {
    testWidgets('Prints sits between Filament and Settings', (tester) async {
      await pump(tester);

      final tabs = ControllerTab.values;
      expect(
        tabs.indexOf(ControllerTab.prints),
        tabs.indexOf(ControllerTab.filament) + 1,
      );
      expect(
        tabs.indexOf(ControllerTab.settings),
        tabs.indexOf(ControllerTab.prints) + 1,
      );
      expect(find.text(pl.controllerTabPrints), findsOneWidget);
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
      expect(buttonAt(tester, 'controller.files.up').onPressed, isNull);

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
      expect(buttonAt(tester, 'controller.files.up').onPressed, isNull);
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

      expect(buttonAt(tester, 'controller.files.up').onPressed, isNotNull);

      await tester.tap(byLogId('controller.files.up'));
      await settle(tester);

      expect(library.calls, ['open null']);
    });

    testWidgets('Refresh is off while nothing is loaded', (tester) async {
      await pump(tester, lib: _Library(failWith: Exception('down')));
      await openFiles(tester);

      expect(buttonAt(tester, 'controller.files.refresh').onPressed, isNull);
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
      expect(buttonAt(tester, 'controller.files.refresh').onPressed, isNull);
      // The listing stays while it is refreshed.
      expect(find.text('benchy.gcode.3mf'), findsOneWidget);

      gate.complete();
      await settle(tester);

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(buttonAt(tester, 'controller.files.refresh').onPressed, isNotNull);
    });
  });

  group('when the listing is not there', () {
    testWidgets('it shows a spinner while the library loads', (tester) async {
      final gate = Completer<void>();
      await pump(tester, lib: _Library(gate: gate));
      await tester.tap(byLogId(ControllerTab.prints.logId));
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

  group('the file dialog', () {
    _Library tree({List<LibraryFolder> folders = const []}) => _Library(
      folders: folders,
      filesByFolder: {
        null: [
          _file(
            10,
            'benchy.gcode.3mf',
            model: 'P1S',
            seconds: 11520,
            grams: 45,
          ),
          _file(11, 'vase.gcode.3mf', model: 'H2D'),
          _file(12, 'bracket.stl', type: 'stl'),
          _file(13, 'mounted.gcode.3mf', model: 'P1S', external: true),
        ],
      },
    );

    Future<void> openDialog(WidgetTester tester, String name) async {
      await tester.tap(find.text(name));
      await settle(tester);
    }

    Finder dialogButton(String id) =>
        find.descendant(of: byLogId(id), matching: find.byType(FilledButton));

    bool enabled(WidgetTester tester, String id) =>
        tester.widget<FilledButton>(dialogButton(id)).onPressed != null;

    testWidgets('a tap on a file opens its dialog with what is known of it', (
      tester,
    ) async {
      await pump(tester, lib: tree());
      await openFiles(tester);
      expect(find.byType(Dialog), findsNothing);

      await openDialog(tester, 'benchy.gcode.3mf');

      final dialog = find.byType(Dialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('benchy.gcode.3mf')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.textContaining('45 g')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('P1S')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text(pl.fmPrint)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text(pl.fmDelete)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'the close icon closes it, and nothing is asked of the server',
      (tester) async {
        final repo = _Repo();
        await pump(
          tester,
          lib: tree(),
          extra: [libraryRepositoryProvider.overrideWithValue(repo)],
        );
        await openFiles(tester);
        await openDialog(tester, 'benchy.gcode.3mf');

        await tester.tap(byLogId('controller.files.dialog.close'));
        await settle(tester);

        expect(find.byType(Dialog), findsNothing);
        expect(repo.deleted, isEmpty);
        expect(library.calls, isNot(contains('refresh')));
      },
    );

    testWidgets('Print opens the print screen for that file', (tester) async {
      await pump(tester, lib: tree());
      await openFiles(tester);
      await openDialog(tester, 'benchy.gcode.3mf');
      expect(enabled(tester, 'controller.files.dialog.print'), isTrue);

      await tester.tap(byLogId('controller.files.dialog.print'));
      await settle(tester);

      expect(find.byType(Dialog), findsNothing);
      final screen = tester.widget<ControllerPrintScreen>(
        find.byType(ControllerPrintScreen),
      );
      expect(screen.file.id, 10);
      expect(screen.printer.id, 1);
    });

    testWidgets('a model, not G-code, cannot be printed, and says why', (
      tester,
    ) async {
      await pump(tester, lib: tree());
      await openFiles(tester);

      await openDialog(tester, 'bracket.stl');

      expect(enabled(tester, 'controller.files.dialog.print'), isFalse);
      expect(find.text(pl.controllerFileReasonNotSliced), findsOneWidget);
    });

    testWidgets('a file sliced for another model says which', (tester) async {
      await pump(tester, lib: tree());
      await openFiles(tester);

      await openDialog(tester, 'vase.gcode.3mf');

      expect(enabled(tester, 'controller.files.dialog.print'), isFalse);
      expect(find.text(pl.controllerFileReasonModel('H2D')), findsOneWidget);
    });

    testWidgets('a printer of an unknown model blocks no sliced file', (
      tester,
    ) async {
      await pump(tester, lib: tree(), model: null);
      await openFiles(tester);

      await openDialog(tester, 'vase.gcode.3mf');

      expect(enabled(tester, 'controller.files.dialog.print'), isTrue);
    });

    test(
      'a printer missing from the roster blocks a file that would print',
      () {
        final file = _file(1, 'a.gcode.3mf', model: 'P1S');

        expect(
          filePrintBlock(file, printerKnown: false, printerModel: 'P1S'),
          FilePrintBlock.printerGone,
        );
        expect(
          filePrintBlock(file, printerKnown: true, printerModel: 'P1S'),
          isNull,
        );
        // Gone outranks the rest: nothing else can be said of no printer.
        expect(
          filePrintBlock(
            _file(2, 'b.stl', type: 'stl'),
            printerKnown: false,
            printerModel: null,
          ),
          FilePrintBlock.printerGone,
        );
      },
    );

    testWidgets('a file on a host mount has no Delete', (tester) async {
      await pump(tester, lib: tree());
      await openFiles(tester);

      await openDialog(tester, 'mounted.gcode.3mf');

      expect(byLogId('controller.files.dialog.delete'), findsNothing);
      expect(byLogId('controller.files.dialog.print'), findsOneWidget);
    });

    for (final (name, folder) in const [
      (
        'a folder the account may not write to',
        LibraryFolder(id: 1, name: 'Shared', canWrite: false),
      ),
      (
        'a read-only mount',
        LibraryFolder(id: 1, name: 'Shared', externalReadonly: true),
      ),
      (
        'an external folder',
        LibraryFolder(id: 1, name: 'Shared', isExternal: true),
      ),
    ]) {
      testWidgets('a file in $name has no Delete', (tester) async {
        await pump(
          tester,
          lib: _Library(
            folders: [folder],
            startFolderId: 1,
            filesByFolder: {
              1: [_file(10, 'benchy.gcode.3mf', model: 'P1S', folderId: 1)],
            },
          ),
        );
        await openFiles(tester);

        await openDialog(tester, 'benchy.gcode.3mf');

        expect(byLogId('controller.files.dialog.delete'), findsNothing);
      });
    }

    testWidgets('Delete asks first, and a no deletes nothing', (tester) async {
      final repo = _Repo();
      await pump(
        tester,
        lib: tree(),
        extra: [libraryRepositoryProvider.overrideWithValue(repo)],
      );
      await openFiles(tester);
      await openDialog(tester, 'benchy.gcode.3mf');

      await tester.tap(byLogId('controller.files.dialog.delete'));
      await settle(tester);
      expect(
        find.text(pl.fmDeleteFileConfirm('benchy.gcode.3mf')),
        findsOneWidget,
      );

      await tester.tap(
        find.text(
          MaterialLocalizations.of(
            tester.element(find.byType(ControllerFiles)),
          ).cancelButtonLabel,
        ),
      );
      await settle(tester);

      expect(repo.deleted, isEmpty);
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('a confirmed Delete removes the file, refreshes and closes', (
      tester,
    ) async {
      final repo = _Repo();
      await pump(
        tester,
        lib: tree(),
        extra: [libraryRepositoryProvider.overrideWithValue(repo)],
      );
      await openFiles(tester);
      await openDialog(tester, 'benchy.gcode.3mf');

      await tester.tap(byLogId('controller.files.dialog.delete'));
      await settle(tester);
      await tester.tap(find.text(pl.fmDelete).last);
      await settle(tester);

      expect(repo.deleted, [10]);
      expect(library.calls, contains('refresh'));
      expect(find.byType(Dialog), findsNothing);
      expect(find.text(pl.fmDeleted), findsOneWidget);
    });

    testWidgets('a refused Delete keeps the dialog and says so', (
      tester,
    ) async {
      final repo = _Repo()
        ..deleteFails = const ApiException(
          AppErrorCode.forbidden,
          statusCode: 403,
        );
      await pump(
        tester,
        lib: tree(),
        extra: [libraryRepositoryProvider.overrideWithValue(repo)],
      );
      await openFiles(tester);
      await openDialog(tester, 'benchy.gcode.3mf');

      await tester.tap(byLogId('controller.files.dialog.delete'));
      await settle(tester);
      await tester.tap(find.text(pl.fmDelete).last);
      await settle(tester);

      expect(repo.deleted, isEmpty);
      expect(library.calls, isNot(contains('refresh')));
      expect(find.byType(Dialog), findsOneWidget);
      // Back to something a second tap can act on.
      expect(enabled(tester, 'controller.files.dialog.delete'), isTrue);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('the search', () {
    _Library tree() => _Library(
      folders: const [LibraryFolder(id: 1, name: 'Alpha')],
      filesByFolder: {
        null: [
          _file(10, 'benchy.gcode.3mf', model: 'P1S'),
          _file(11, 'vase.gcode.3mf', model: 'P1S'),
        ],
        1: [_file(20, 'tower.gcode.3mf', model: 'P1S')],
      },
    );

    Future<void> openSearch(WidgetTester tester) async {
      await tester.tap(byLogId('controller.files.search'));
      await settle(tester);
    }

    Future<void> submit(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
    }

    testWidgets('it expands into a field in the header, not a dialog', (
      tester,
    ) async {
      await pump(tester, lib: tree());
      await openFiles(tester);
      expect(find.byType(TextField), findsNothing);

      await openSearch(tester);

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ControllerFiles),
          matching: find.byType(TextField),
        ),
        findsOneWidget,
      );
    });

    testWidgets('typing applies nothing; the search action does', (
      tester,
    ) async {
      await pump(tester, lib: tree());
      await openFiles(tester);
      await openSearch(tester);

      await tester.enterText(find.byType(TextField), 'tow');
      await settle(tester);
      expect(library.calls, isEmpty);

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);

      expect(library.calls, ['query tow']);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('tower.gcode.3mf'), findsOneWidget);
      expect(find.text('benchy.gcode.3mf'), findsNothing);
      // A search spans the library: the folder of the listing is not beside it.
      expect(byLogId('controller.files.folder'), findsNothing);
    });

    testWidgets('what is applied is a chip, and a tap on it clears it', (
      tester,
    ) async {
      await pump(tester, lib: tree());
      await openFiles(tester);
      await openSearch(tester);
      await submit(tester, 'tow');
      expect(byLogId('controller.files.search_chip'), findsOneWidget);
      expect(
        find.descendant(
          of: byLogId('controller.files.search_chip'),
          matching: find.text('tow'),
        ),
        findsOneWidget,
      );

      await tester.tap(byLogId('controller.files.search_chip'));
      await settle(tester);

      expect(library.calls, ['query tow', 'query ']);
      expect(byLogId('controller.files.search_chip'), findsNothing);
      expect(find.text('benchy.gcode.3mf'), findsOneWidget);
    });

    testWidgets('an empty search applies nothing and shows no chip', (
      tester,
    ) async {
      await pump(tester, lib: tree());
      await openFiles(tester);
      await openSearch(tester);

      await submit(tester, '   ');

      expect(byLogId('controller.files.search_chip'), findsNothing);
      expect(find.text('benchy.gcode.3mf'), findsOneWidget);
    });

    testWidgets('cancel closes the field and keeps what was applied', (
      tester,
    ) async {
      await pump(tester, lib: tree());
      await openFiles(tester);
      await openSearch(tester);
      await submit(tester, 'tow');
      await openSearch(tester);
      // Reopened on what is applied.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'tow',
      );

      await tester.enterText(find.byType(TextField), 'vas');
      await tester.tap(byLogId('controller.files.search_cancel'));
      await settle(tester);

      expect(find.byType(TextField), findsNothing);
      expect(library.calls, ['query tow']);
      expect(byLogId('controller.files.search_chip'), findsOneWidget);
    });

    testWidgets('a search with no match says so', (tester) async {
      await pump(tester, lib: tree());
      await openFiles(tester);
      await openSearch(tester);

      await submit(tester, 'zzz');

      expect(find.text(pl.fmNoMatches), findsOneWidget);
    });

    testWidgets('the keyboard does not resize the body while it is open', (
      tester,
    ) async {
      await pump(tester, lib: tree());
      await openFiles(tester);
      await openSearch(tester);
      final before = tester.getSize(find.byType(ControllerFiles));

      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      addTearDown(tester.view.resetViewInsets);
      await settle(tester);

      expect(tester.getSize(find.byType(ControllerFiles)), before);
      expect(tester.takeException(), isNull);
    });
  });

  group('the upload', () {
    final picked = PlatformFile(
      path: '/tmp/new.gcode.3mf',
      name: 'new.gcode.3mf',
      size: 10,
    );

    late _Repo repo;
    late _Picker picker;
    late Future<void> Function(WidgetTester, {_Library? lib}) start;

    setUp(() {
      repo = _Repo();
      picker = _Picker(picked);
      FilePicker.platform = picker;
      start = (tester, {lib}) async {
        await pump(
          tester,
          lib:
              lib ??
              _Library(
                filesByFolder: {
                  null: [_file(10, 'benchy.gcode.3mf', model: 'P1S')],
                },
              ),
          extra: [libraryRepositoryProvider.overrideWithValue(repo)],
        );
        await openFiles(tester);
      };
    });

    Future<void> tapUpload(WidgetTester tester) async {
      await tester.tap(byLogId('controller.files.upload'));
      await settle(tester);
    }

    testWidgets('a picked file goes into the open folder, then the list '
        'is refreshed', (tester) async {
      await start(
        tester,
        lib: _Library(
          folders: const [LibraryFolder(id: 1, name: 'Alpha')],
          startFolderId: 1,
          filesByFolder: const {1: []},
        ),
      );

      await tapUpload(tester);

      expect(repo.uploads, [
        (path: '/tmp/new.gcode.3mf', name: 'new.gcode.3mf', folderId: 1),
      ]);
      expect(library.calls, contains('refresh'));
      expect(find.text(pl.fmUploaded('new.gcode.3mf')), findsOneWidget);
    });

    testWidgets('the library stats are invalidated after it', (tester) async {
      var builds = 0;
      await pump(
        tester,
        extra: [
          libraryRepositoryProvider.overrideWithValue(repo),
          libraryStatsProvider.overrideWith((ref) async {
            builds++;
            return const LibraryStats();
          }),
        ],
      );
      await openFiles(tester);
      // The stats header is not on this tab; something has to be listening.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ControllerFiles)),
      );
      container.listen(libraryStatsProvider, (_, _) {});
      await settle(tester);
      expect(builds, 1);

      await tapUpload(tester);

      expect(builds, 2);
    });

    testWidgets('the bar shows the progress, and the header is locked', (
      tester,
    ) async {
      repo.uploadGate = Completer<void>();
      await start(tester);

      await tapUpload(tester);

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.25);
      for (final id in [
        'controller.files.up',
        'controller.files.search',
        'controller.files.sort',
        'controller.files.upload',
        'controller.files.refresh',
      ]) {
        expect(buttonAt(tester, id).onPressed, isNull, reason: id);
      }
      // Nor does a file or a folder open under the bar.
      await tester.tap(find.text('benchy.gcode.3mf'), warnIfMissed: false);
      await settle(tester);
      expect(find.byType(Dialog), findsNothing);

      repo.uploadGate!.complete();
      await settle(tester);

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(buttonAt(tester, 'controller.files.upload').onPressed, isNotNull);
    });

    testWidgets('a second tap while the picker is open starts no second '
        'upload', (tester) async {
      picker.gate = Completer<void>();
      await start(tester);

      await tester.tap(byLogId('controller.files.upload'));
      await tester.pump();
      await tester.tap(byLogId('controller.files.upload'), warnIfMissed: false);
      await tester.pump();
      picker.gate!.complete();
      await settle(tester);

      expect(picker.opened, 1);
      expect(repo.uploads, hasLength(1));
    });

    testWidgets('a cancelled picker uploads nothing and unlocks', (
      tester,
    ) async {
      picker.answer = null;
      await start(tester);

      await tapUpload(tester);

      expect(repo.uploads, isEmpty);
      expect(library.calls, isNot(contains('refresh')));
      expect(buttonAt(tester, 'controller.files.upload').onPressed, isNotNull);
    });

    testWidgets('a refused upload says so, unlocks and refreshes nothing', (
      tester,
    ) async {
      repo.uploadFails = const ApiException(
        AppErrorCode.forbidden,
        statusCode: 403,
      );
      await start(tester);

      await tapUpload(tester);

      expect(find.byType(SnackBar), findsOneWidget);
      expect(library.calls, isNot(contains('refresh')));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(buttonAt(tester, 'controller.files.upload').onPressed, isNotNull);
    });

    for (final (name, folder) in const [
      (
        'a folder the account may not write to',
        LibraryFolder(id: 1, name: 'Shared', canWrite: false),
      ),
      (
        'a read-only mount',
        LibraryFolder(id: 1, name: 'Shared', externalReadonly: true),
      ),
      (
        'an external folder',
        LibraryFolder(id: 1, name: 'Shared', isExternal: true),
      ),
    ]) {
      testWidgets('it is off in $name, and the tooltip says why', (
        tester,
      ) async {
        await start(
          tester,
          lib: _Library(
            folders: [folder],
            startFolderId: 1,
            filesByFolder: const {1: []},
          ),
        );

        expect(buttonAt(tester, 'controller.files.upload').onPressed, isNull);
        expect(find.byTooltip(pl.controllerFilesReadOnly), findsOneWidget);
        expect(picker.opened, 0);
      });
    }

    testWidgets('leaving the tab mid-upload still refreshes the list, '
        'without a toast', (tester) async {
      repo.uploadGate = Completer<void>();
      await start(tester);
      await tapUpload(tester);

      await select(tester, ControllerTab.heat);
      repo.uploadGate!.complete();
      await settle(tester);

      expect(library.calls, contains('refresh'));
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('leaving mid-upload and then a refusal throws nothing', (
      tester,
    ) async {
      repo.uploadGate = Completer<void>();
      repo.uploadFails = const ApiException(
        AppErrorCode.forbidden,
        statusCode: 403,
      );
      await start(tester);
      await tapUpload(tester);

      await select(tester, ControllerTab.heat);
      repo.uploadGate!.complete();
      await settle(tester);

      expect(library.calls, isNot(contains('refresh')));
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
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
