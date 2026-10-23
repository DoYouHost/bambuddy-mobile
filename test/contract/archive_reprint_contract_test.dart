import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/data/account_repository.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'contract_harness.dart';

/// `archiveReprintBlockProvider` predicts what `POST /queue/` answers for an
/// archive: `queue:create`, then `_assert_can_queue_archive` (`print_queue.py`),
/// which reads the archive's `created_by_id`. Each case asks the provider and
/// the server the same question as the same user.
void main() {
  group('archive reprint contract', skip: contractSkipReason, () {
    late Dio admin;
    late ArchiveRepository archives;
    late int adminId;
    late int archiveId;

    setUpAll(() async {
      admin = await authenticatedDio();
      archives = ArchiveRepository(admin);
      adminId = (await AccountRepository(admin).me()).id;
      final file = (await LibraryRepository(
        admin,
      ).listFiles()).firstWhere((f) => f.filename == 'contract-probe.3mf');
      final bytes = (await admin.get<List<int>>(
        '${Endpoints.libraryFile(file.id)}/download',
        options: Options(responseType: ResponseType.bytes),
      )).data!;
      final uploaded = await admin.post<Map<String, dynamic>>(
        '${Endpoints.archives}upload',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: 'reprint.3mf'),
        }),
      );
      archiveId = uploaded.data!['id'] as int;
    });

    tearDownAll(() => archives.delete(archiveId, purgeStats: true));

    test('an archive names who printed it, in the list and alone', () async {
      final listed = (await archives.list(
        limit: 50,
      )).firstWhere((a) => a.id == archiveId);
      expect(listed.createdById, adminId);
      expect((await archives.byId(archiveId)).createdById, adminId);
    });

    /// The provider's answer for [me], and the server's status for queueing
    /// the admin's archive as [me]; a job that got in is removed again.
    Future<(ArchiveReprintBlock?, int?)> ask(
      ({Dio dio, CurrentUser me}) user,
    ) async {
      final container = ProviderContainer(
        overrides: [currentUserOverride(user.me)],
      );
      addTearDown(container.dispose);
      await container.read(currentUserProvider.future);
      final block = container.read(archiveReprintBlockProvider(adminId));
      final res = await user.dio.post<Map<String, dynamic>>(
        Endpoints.queue,
        data: {'archive_id': archiveId, 'manual_start': true},
        options: Options(validateStatus: (_) => true),
      );
      if (res.statusCode == 200) {
        await admin.delete<dynamic>(
          Endpoints.queueItem(res.data!['id'] as int),
        );
      }
      return (block, res.statusCode);
    }

    test('queue:create without a reprint right is refused', () async {
      final (block, status) = await ask(
        await contractUser(admin, [
          Permissions.queueCreate,
          'archives:read_all',
        ]),
      );
      expect(status, 403);
      expect(block, ArchiveReprintBlock.noReprint);
    });

    test('reprint-own does not cover someone else\'s print', () async {
      final (block, status) = await ask(
        await contractUser(admin, [
          Permissions.queueCreate,
          Permissions.archivesReprintOwn,
          'archives:read_all',
        ]),
      );
      expect(status, 403);
      expect(block, ArchiveReprintBlock.noReprint);
    });

    test('a reprint right without queue:create is refused', () async {
      final (block, status) = await ask(
        await contractUser(admin, [
          Permissions.archivesReprintAll,
          'archives:read_all',
        ]),
      );
      expect(status, 403);
      expect(block, ArchiveReprintBlock.noQueue);
    });

    test('queue:create with reprint-all is let through', () async {
      final (block, status) = await ask(
        await contractUser(admin, [
          Permissions.queueCreate,
          Permissions.archivesReprintAll,
          'archives:read_all',
        ]),
      );
      expect(status, 200);
      expect(block, isNull);
    });
  });
}
