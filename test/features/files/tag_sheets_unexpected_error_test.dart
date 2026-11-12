import 'package:bambuddy_mobile/core/models/library_file.dart';
import 'package:bambuddy_mobile/core/models/library_stats.dart';
import 'package:bambuddy_mobile/core/models/library_tag.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/features/files/file_manager_providers.dart';
import 'package:bambuddy_mobile/features/files/file_manager_screen.dart';
import 'package:bambuddy_mobile/features/pipelines/pipelines_providers.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Tagging fails with something that is not an `AppApiException`: a server
/// answer the app cannot read. The app reports it rather than wording it, and
/// the sheet is not left locked behind it.
class _UnreadableLibrary extends LibraryRepository {
  _UnreadableLibrary() : super(testDio());

  @override
  Future<TagAssignResult> assignTags({
    required List<int> fileIds,
    required List<int> tagIds,
    required TagAssignAction action,
  }) async => throw StateError('unreadable answer');
}

class _FakeNotifier extends FileManagerNotifier {
  _FakeNotifier(this._state);
  final FileManagerState _state;

  @override
  Future<FileManagerState> build() async => _state;
}

const _file = LibraryFile(
  id: 1,
  filename: 'thing.3mf',
  fileType: '3mf',
  fileSize: 1024,
  printCount: 0,
);

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required bool selecting,
  }) async {
    await pumpPhone(
      tester,
      const FileManagerScreen(),
      overrides: [
        noServerProfileOverride,
        libraryRepositoryProvider.overrideWithValue(_UnreadableLibrary()),
        fileManagerProvider.overrideWith(
          () => _FakeNotifier(
            FileManagerState(
              files: [_file],
              selectionMode: selecting,
              selected: selecting ? {_file.id} : const {},
            ),
          ),
        ),
        libraryStatsProvider.overrideWith((ref) async => const LibraryStats()),
        libraryTagsProvider.overrideWith(
          (ref) async => const [LibraryTag(id: 4, name: 'gift')],
        ),
        libraryTagsSupportedProvider.overrideWithValue(const AsyncData(true)),
        slicerEnabledProvider.overrideWithValue(const AsyncData(true)),
        canRunPipelinesProvider.overrideWithValue(const AsyncData(false)),
      ],
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the bulk tags sheet is unlocked after an unexpected error, '
      'which is still reported', (tester) async {
    await pumpScreen(tester, selecting: true);
    await tester.tap(byLogId('files.tag_selected'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('gift'));
    await tester.pumpAndSettle();

    final errors = await tapCapturingErrors(tester, byLogId('bulk_tags.add'));

    expect(errors.single, isA<StateError>());
    expect(buttonAt(tester, 'bulk_tags.add').onPressed, isNotNull);
  });

  testWidgets('the file tags sheet is unlocked after an unexpected error, '
      'which is still reported', (tester) async {
    await pumpScreen(tester, selecting: false);
    await tester.tap(find.text('thing.3mf'));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('file_actions.tags'));
    await tester.pumpAndSettle();

    final errors = await tapCapturingErrors(tester, byLogId('file_tags.save'));

    expect(errors.single, isA<StateError>());
    expect(buttonAt(tester, 'file_tags.save').onPressed, isNotNull);
  });
}
