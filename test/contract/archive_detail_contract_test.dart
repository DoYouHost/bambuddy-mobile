import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// What the archive detail sheet reads off a row beyond the basics: the
/// slicer's per-slot filament usage in `extra_data`, the object count, and the
/// fields a user writes — tags, note, link. The probe 3MF's `slice_info`
/// lists two PLA slots (12 g red, 13.5 g green), one object and a one-hour
/// estimate.
void main() {
  group('archive detail contract', skip: contractSkipReason, () {
    late Dio dio;
    late ArchiveRepository repo;
    late int archiveId;

    setUpAll(() async {
      dio = await authenticatedDio();
      repo = ArchiveRepository(dio);
      final file = (await LibraryRepository(
        dio,
      ).listFiles()).firstWhere((f) => f.filename == 'contract-probe.3mf');
      final bytes = (await dio.get<List<int>>(
        '${Endpoints.libraryFile(file.id)}/download',
        options: Options(responseType: ResponseType.bytes),
      )).data!;
      final uploaded = await dio.post<Map<String, dynamic>>(
        '${Endpoints.archives}upload',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: 'detail.3mf'),
        }),
      );
      archiveId = uploaded.data!['id'] as int;
    });

    tearDownAll(() => repo.delete(archiveId, purgeStats: true));

    test('the slicer\'s slots, objects and estimate are read', () async {
      final archive = await repo.byId(archiveId);

      expect(archive.filamentSlots, [
        (slot: 1, type: 'PLA', color: '#FF0000', grams: 12.0),
        (slot: 2, type: 'PLA', color: '#00FF00', grams: 13.5),
      ]);
      expect(archive.objectCount, 1);
      // Never printed, so the timer has only the estimate to show.
      expect(archive.actualTimeSeconds, isNull);
      expect(archive.shownTimeSeconds, 3600);
    });

    test('the list carries the same as the single row', () async {
      final listed = (await repo.list(
        limit: 50,
      )).firstWhere((a) => a.id == archiveId);

      expect(listed.filamentSlots, hasLength(2));
      expect(listed.objectCount, 1);
    });

    test('tags, note and link round-trip as the sheet reads them', () async {
      await dio.patch<dynamic>(
        Endpoints.archive(archiveId),
        data: {
          'tags': 'jig, workshop',
          'notes': 'No supports.',
          'external_url': 'https://www.3dbenchy.com/',
        },
      );
      final archive = await repo.byId(archiveId);

      expect(archive.tagList, ['jig', 'workshop']);
      expect(archive.notes, 'No supports.');
      expect(archive.link, 'https://www.3dbenchy.com/');
      expect(archive.createdByUsername, isNotNull);
    });

    // Energy and wear are only priced for a print that ran with a plug or a
    // rate; on an upload they are absent, and the sum must not invent them.
    test('an upload has no energy or wear cost to add up', () async {
      final archive = await repo.byId(archiveId);

      expect(archive.energyCost, isNull);
      expect(archive.wearCost, isNull);
      expect(archive.totalCost, archive.cost);
    });
  });
}
