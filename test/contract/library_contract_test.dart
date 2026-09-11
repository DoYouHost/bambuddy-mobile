import 'package:bambuddy_mobile/core/models/library_file.dart';
import 'package:bambuddy_mobile/core/models/library_folder.dart';
import 'package:bambuddy_mobile/core/models/library_stats.dart';
import 'package:bambuddy_mobile/core/models/plate_list.dart';
import 'package:bambuddy_mobile/core/models/trash_file.dart';
import 'package:bambuddy_mobile/core/models/variant_group.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

void main() {
  group('library contract', skip: contractSkipReason, () {
    late Dio dio;
    late LibraryRepository library;
    final createdFolderIds = <int>[];
    final createdTagIds = <int>[];

    setUpAll(() async {
      dio = await authenticatedDio();
      library = LibraryRepository(dio);
    });

    tearDownAll(() async {
      for (final folderId in createdFolderIds) {
        try {
          await library.deleteFolder(folderId);
        } catch (_) {}
      }
      for (final tagId in createdTagIds) {
        try {
          await library.deleteTag(tagId);
        } catch (_) {}
      }
    });

    test('GET /library/files decodes file listing into LibraryFile', () async {
      final files = await library.listFiles();

      expect(files, isA<List<LibraryFile>>());
      if (files.isNotEmpty) {
        final f = files.first;
        expect(f.id, greaterThan(0));
        expect(f.filename, isNotEmpty);
        expect(f.fileType, isNotEmpty);
        expect(f.fileSize, greaterThanOrEqualTo(0));
      }
    });

    test('GET /library/folders decodes folder tree into LibraryFolder', () async {
      final folders = await library.listFolders();

      expect(folders, isA<List<LibraryFolder>>());
      for (final folder in folders) {
        expect(folder.id, greaterThan(0));
        expect(folder.name, isNotEmpty);
      }
    });

    test('GET /library/stats decodes library telemetry into LibraryStats', () async {
      final stats = await library.stats();

      expect(stats, isA<LibraryStats>());
      expect(stats.totalFiles, anyOf(isNull, greaterThanOrEqualTo(0)));
      expect(stats.totalSizeBytes, anyOf(isNull, greaterThanOrEqualTo(0)));
      expect(stats.totalFolders, anyOf(isNull, greaterThanOrEqualTo(0)));
    });

    test('folder lifecycle: create, rename, list and delete round-trip', () async {
      final folderName = 'contract-folder-${DateTime.now().millisecondsSinceEpoch}';
      await library.createFolder(folderName);

      final folders = await library.listFolders();
      final created = folders.firstWhere(
        (f) => f.name == folderName,
        orElse: () => throw StateError('Created folder $folderName not found in listFolders'),
      );
      createdFolderIds.add(created.id);
      expect(created.id, greaterThan(0));

      final renamedName = '$folderName-renamed';
      await library.renameFolder(created.id, renamedName);

      final updatedFolders = await library.listFolders();
      expect(updatedFolders.any((f) => f.id == created.id && f.name == renamedName), isTrue);

      await library.deleteFolder(created.id);
      createdFolderIds.remove(created.id);

      final finalFolders = await library.listFolders();
      expect(finalFolders.any((f) => f.id == created.id), isFalse);
    });

    test('tag lifecycle: create, list and delete if tags supported', () async {
      final tags = await library.listTags();
      if (tags == null) {
        // Tag endpoints return 404 on servers predating 1.2.5 — feature gated.
        return;
      }

      final tagName = 'tag-${DateTime.now().millisecondsSinceEpoch}';
      final created = await library.createTag(tagName);
      createdTagIds.add(created.id);

      expect(created.id, greaterThan(0));
      expect(created.name, tagName);

      final updatedTags = await library.listTags();
      expect(updatedTags?.any((t) => t.id == created.id), isTrue);

      await library.deleteTag(created.id);
      createdTagIds.remove(created.id);

      final finalTags = await library.listTags();
      expect(finalTags?.any((t) => t.id == created.id), isFalse);
    });

    test('GET /library/files/{id}/plates decodes plates from seeded file', () async {
      final files = await library.listFiles();
      if (files.isEmpty) return;

      final probeFile = files.cast<LibraryFile?>().firstWhere(
        (f) => f?.filename == 'contract-probe.3mf',
        orElse: () => null,
      );
      if (probeFile == null) return;

      final plateList = await library.plates(probeFile.id);
      expect(plateList, isA<PlateList>());
      if (plateList.plates.isNotEmpty) {
        final plate = plateList.plates.first;
        expect(plate.index, greaterThanOrEqualTo(1));
      }

      // Variant group for probe file (null or VariantGroup)
      final group = await library.variantGroupForFile(probeFile.id);
      expect(group, anyOf(isNull, isA<VariantGroup>()));
    });

    test('GET /library/trash decodes into TrashFile list', () async {
      final trash = await library.listTrash();
      expect(trash, isA<List<TrashFile>>());
    });
  });
}
