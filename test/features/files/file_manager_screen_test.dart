import 'package:bambuddy_mobile/core/models/library_file.dart';
import 'package:bambuddy_mobile/core/models/library_stats.dart';
import 'package:bambuddy_mobile/core/models/library_tag.dart';
import 'package:bambuddy_mobile/features/files/file_manager_providers.dart';
import 'package:bambuddy_mobile/features/files/file_manager_screen.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}) =>
    LibraryFile(
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
    List<LibraryTag>? tags = const [],
    Size size = const Size(411, 866),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        noServerProfileOverride,
        fileManagerProvider
            .overrideWith(() => _FakeNotifier(FileManagerState(files: [file]))),
        libraryStatsProvider.overrideWith((ref) async => const LibraryStats()),
        libraryTagsProvider.overrideWith((ref) async => tags),
        slicerEnabledProvider.overrideWith((ref) async => slicerEnabled),
      ],
      child: plApp(const FileManagerScreen()),
    ));
    await tester.pumpAndSettle();
  }

  /// Opens the per-file action sheet.
  Future<void> openFileSheet(WidgetTester tester, LibraryFile file) async {
    await tester.tap(find.text(file.displayName));
    await tester.pumpAndSettle();
  }

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

      expect(tester.takeException(), isNull,
          reason: 'the sheet must scroll rather than overflow');
    });

    testWidgets('the last action is reachable by scrolling', (tester) async {
      // Not just "no exception": the point of the fix is that the actions past
      // the fold can actually be got at.
      final file = _file(variantCount: 2);
      await pump(tester, file: file);
      await openFileSheet(tester, file);

      final sheet = find.byType(BottomSheet);
      await tester.dragUntilVisible(
          find.text('Usuń'), sheet, const Offset(0, -60));
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
    testWidgets('a sliceable model offers slicing, not printing',
        (tester) async {
      // A 3MF that is not gcode cannot be printed as-is, and the slice gate is
      // on: `canSlice = slicerEnabled && !file.isPrintable`.
      final file = _file();
      await pump(tester, file: file);
      await openFileSheet(tester, file);

      expect(find.text('Potnij'), findsOneWidget);
      expect(find.text('Drukuj'), findsNothing);
    });

    testWidgets('slicing is not offered when the server has it switched off',
        (tester) async {
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

    testWidgets('a server with no tag routes hides the tag action',
        (tester) async {
      // A loaded null is the 404 gate — see libraryTagsSupported.
      final file = _file();
      await pump(tester, file: file, tags: null);
      await openFileSheet(tester, file);
      expect(find.textContaining('tag'), findsNothing);
      expect(find.textContaining('Tagi'), findsNothing);
    });
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
