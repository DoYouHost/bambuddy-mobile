import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:bambuddy_mobile/core/models/archive_merge.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';
import 'sent_writes.dart';

/// "Merge duplicates" against a real server: two uploads of one file by one
/// user are a group, the merge keeps the oldest archive of it, and the id of
/// one merged away still opens the one it went into. On a server before the
/// archive redesign the count is a 404, which the app reads as nothing to do.
void main() {
  group('archive merge contract', skip: contractSkipReason, () {
    late Dio dio;
    late ArchiveRepository repo;
    late bool served;
    final uploaded = <int>[];

    setUpAll(() async {
      dio = await authenticatedDio();
      repo = ArchiveRepository(dio);
      served = (await contractServerVersion()).supports(
        ServerFeature.archiveMerge,
      );
      final file = (await LibraryRepository(
        dio,
      ).listFiles()).firstWhere((f) => f.filename == 'contract-probe.3mf');
      final bytes = (await dio.get<List<int>>(
        '${Endpoints.libraryFile(file.id)}/download',
        options: Options(responseType: ResponseType.bytes),
      )).data!;
      for (final name in ['merge-a.3mf', 'merge-b.3mf']) {
        final res = await dio.post<Map<String, dynamic>>(
          '${Endpoints.archives}upload',
          data: FormData.fromMap({
            'file': MultipartFile.fromBytes(bytes, filename: name),
          }),
        );
        uploaded.add(res.data!['id'] as int);
      }
    });

    tearDownAll(() async {
      for (final id in uploaded) {
        await dio.delete<dynamic>(
          Endpoints.archive(id),
          options: Options(validateStatus: (_) => true),
        );
      }
    });

    test('an older server answers no merge, without an error', () async {
      if (served) return markTestSkipped('the server merges duplicates');

      expect(await repo.mergeCount(), 0);
      expect(await repo.mergeCapability.supported, isFalse);
    });

    test('two uploads of one file are a group, and merge into one', () async {
      if (!served) return markTestSkipped('the server predates the merge');
      expect(await repo.mergeCount(), greaterThanOrEqualTo(1));
      final group = (await repo.mergePreview()).firstWhere(
        (g) =>
            {g.survivor.id, ...g.merged.map((m) => m.id)}.containsAll(uploaded),
      );
      expect(
        group.survivor.id,
        lessThan(uploaded.last),
        reason: 'the oldest archive of the group stays',
      );

      // What the merge sheet sends, recorded by its widget test.
      final answer = (await replayWrites(
        dio,
        recordedWrites('archive_merge'),
        ids: {
          'survivor_ids': [group.survivor.id],
        },
      )).single;
      expect(answer.statusCode, 200);
      final result = ArchiveMergeResult.fromJson(
        answer.data as Map<String, dynamic>,
      );

      // An upload counts as just printed for half an hour (`_JUST_PRINTED`),
      // so on a fresh stack the group is held back: then the merge says so
      // with the preview's reason. The merge itself is the demo's to show.
      if (!group.mergeable) {
        expect(result.merged, isEmpty);
        expect(result.skipped.single.reason, group.skipped);
        return;
      }
      expect(result.merged, [group.survivor.id]);
      expect(result.skipped, isEmpty);
      // The merged archive's id still opens the archive it went into.
      expect((await repo.byId(uploaded.last)).id, group.survivor.id);
      final listed = (await repo.list(limit: 500)).map((a) => a.id);
      expect(listed, isNot(contains(uploaded.last)));
    });

    test('a survivor that is no group is left out, and says why', () async {
      if (!served) return markTestSkipped('the server predates the merge');

      final result = await repo.merge([999999]);

      expect(result.merged, isEmpty);
      expect(result.skipped.single.reason, 'not_a_group');
    });
  });
}
