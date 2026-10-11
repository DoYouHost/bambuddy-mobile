import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/queue_settings.dart';
import 'package:bambuddy_mobile/core/settings/server_settings.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// The server half of post-print outcome confirmation (#1898).
///
/// Every gate on the feature is an observation: `confirm_requested` on an
/// archive row, `confirm_outcome` on a queue row, three keys in `/settings`.
/// The mocked suites prove the app reads them; these prove a server sends them
/// together — and, on a server without the feature, that its writes really are
/// dropped in silence, which is the premise every "applied" check rests on.
///
/// Written for both generations, so the same file keeps passing across the
/// release that ships the feature: [served] is what the settings say, and each
/// test asserts the matching half.
void main() {
  group('print outcome contract', skip: contractSkipReason, () {
    late Dio dio;
    late bool served;

    setUpAll(() async {
      dio = await authenticatedDio();
      final settings = await dio.get<Map<String, dynamic>>(
        Endpoints.appSettings,
      );
      served = settings.data!.containsKey('default_confirm_outcome');
    });

    test('the three settings arrive together, as booleans', () async {
      final settings = (await dio.get<Map<String, dynamic>>(
        Endpoints.appSettings,
      )).data!;
      const keys = [
        QueueSetting.confirmOutcomeDefault,
        QueueSetting.confirmOutcomeExternal,
        QueueSetting.confirmGoodOnPlateClear,
      ];

      for (final setting in keys) {
        expect(
          settings.containsKey(setting.key),
          served,
          reason: '${setting.key} alone decides nothing; the three are a set',
        );
        if (served) expect(settings[setting.key], isA<bool>());
      }
    });

    test('a default written reads back on a server that has it', () async {
      Future<Map<String, dynamic>> write(bool value) async =>
          (await dio.put<Map<String, dynamic>>(
            Endpoints.appSettingsUpdate,
            data: QueueSettings.patch(
              QueueSetting.confirmOutcomeDefault,
              value,
            ),
          )).data!;

      final after = await write(true);
      try {
        if (served) {
          expect(after.settingBool('default_confirm_outcome'), isTrue);
        } else {
          expect(
            after.containsKey('default_confirm_outcome'),
            isFalse,
            reason: 'an older server drops the key rather than refusing it',
          );
        }
      } finally {
        if (served) await write(false);
      }
    });

    test(
      'queue rows carry the flag exactly when the server keeps it',
      () async {
        final repo = QueueRepository(dio);
        final raw = (await dio.get<List<dynamic>>(Endpoints.queue)).data!;
        final items = await repo.fetch();

        expect(items, isNotEmpty, reason: 'the seed queues one item');
        expect((raw.first as Map).containsKey('confirm_outcome'), served);
        expect(repo.outcomeCapability.observedAnswer, served);
      },
    );

    // The silent drop the form's gate exists for: an older server answers the
    // PATCH like any other and keeps nothing.
    test('a flag sent in an update is kept, or dropped in silence', () async {
      final repo = QueueRepository(dio);
      final item = (await repo.fetch()).first;

      await repo.updateItem(item.id, confirmOutcome: true);
      try {
        final after = (await repo.fetch()).firstWhere((i) => i.id == item.id);
        expect(after.confirmOutcome, served);
      } finally {
        if (served) await repo.updateItem(item.id, confirmOutcome: false);
      }
    });

    test('a flag sent with a create is kept, or dropped in silence', () async {
      final repo = QueueRepository(dio);
      final file = (await LibraryRepository(
        dio,
      ).listFiles()).firstWhere((f) => f.filename == 'contract-probe.3mf');
      final before = {for (final i in await repo.fetch()) i.id};

      await repo.addFromLibraryFile(
        file.id,
        options: const QueueCreateOptions(
          manualStart: true,
          confirmOutcome: true,
        ),
      );
      final created = (await repo.fetch()).where((i) => !before.contains(i.id));
      try {
        expect(created, hasLength(1));
        expect(created.single.confirmOutcome, served);
      } finally {
        for (final item in created) {
          await repo.delete(item.id);
        }
      }
    });

    group('an archive', () {
      late ArchiveRepository repo;
      late int archiveId;

      // The seed makes no archive, so this one is uploaded from the seeded
      // library file and made a completed print — the only kind that takes a
      // verdict.
      setUpAll(() async {
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
            'file': MultipartFile.fromBytes(bytes, filename: 'outcome.3mf'),
          }),
        );
        archiveId = uploaded.data!['id'] as int;
        await dio.patch<dynamic>(
          Endpoints.archive(archiveId),
          data: {'status': 'completed'},
        );
      });

      tearDownAll(() => repo.delete(archiveId, purgeStats: true));

      test(
        'its row carries the fields exactly when the server keeps them',
        () async {
          final raw = (await dio.get<Map<String, dynamic>>(
            Endpoints.archive(archiveId),
          )).data!;
          final archive = await repo.byId(archiveId);

          for (final key in [
            'confirm_requested',
            'user_verdict',
            'user_verdict_source',
            'user_verdict_at',
          ]) {
            expect(raw.containsKey(key), served, reason: key);
          }
          expect(repo.outcomeCapability.observedAnswer, served);
          expect(archive.status, 'completed');
          expect(archive.userVerdict, isNull);
          expect(archive.confirmRequested, isFalse, reason: 'nobody asked');
        },
      );

      test(
        'a verdict is stored with its cause, or dropped in silence',
        () async {
          final rejected = await repo.setVerdict(
            archiveId,
            PrintVerdict.reject,
            reason: 'warping',
          );
          expect(rejected.applied, served);
          if (!served) return;

          expect(rejected.archive.userVerdict, PrintVerdict.reject);
          expect(
            rejected.archive.userVerdictSource,
            'dialog',
            reason: 'the source the app claims is the one stored',
          );
          expect(rejected.archive.userVerdictAt, isNotNull);
          expect(rejected.archive.failureReason, 'warping');

          final good = await repo.setVerdict(
            archiveId,
            PrintVerdict.good,
            clearReason: true,
          );
          expect(good.applied, isTrue);
          expect(good.archive.userVerdict, PrintVerdict.good);
          expect(
            good.archive.failureReason,
            isNull,
            reason: 'a present null is what clears the column',
          );

          final cleared = await repo.setVerdict(archiveId, null);
          expect(cleared.applied, isTrue);
          expect(cleared.archive.userVerdict, isNull);
          expect(
            cleared.archive.userVerdictSource,
            isNull,
            reason: 'the server drops the provenance with the verdict',
          );
          expect(cleared.archive.userVerdictAt, isNull);
        },
      );

      // Only `dialog`, `printer_card` and `api` may be claimed; the others are
      // the server's own to stamp. The app sends `dialog`, which must stay on
      // the accepted side.
      test('a source only the server may stamp is refused', () async {
        if (!served) return markTestSkipped('the server predates #1898');
        final res = await dio.patch<dynamic>(
          Endpoints.archive(archiveId),
          data: {'user_verdict': 'good', 'user_verdict_source': 'link'},
          options: Options(validateStatus: (_) => true),
        );
        expect(res.statusCode, 422);
      });
    });
  });
}
