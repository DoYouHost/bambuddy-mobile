import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/archive_capabilities.dart';
import 'package:bambuddy_mobile/core/models/archive_purge.dart';
import 'package:bambuddy_mobile/core/models/archive_slim.dart';
import 'package:bambuddy_mobile/core/models/archive_stats.dart';
import 'package:bambuddy_mobile/core/models/failure_analysis.dart';
import 'package:bambuddy_mobile/core/models/no_3mf_warning.dart';
import 'package:bambuddy_mobile/core/models/plate_list.dart';
import 'package:bambuddy_mobile/core/models/print_log_entry.dart';
import 'package:bambuddy_mobile/core/models/timelapse.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/data/print_log_repository.dart';
import 'package:bambuddy_mobile/data/stats_repository.dart';
import 'package:bambuddy_mobile/data/timelapse_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

void main() {
  group('archives contract', skip: contractSkipReason, () {
    late Dio dio;
    late ArchiveRepository archiveRepo;
    late StatsRepository statsRepo;
    late PrintLogRepository logRepo;

    setUpAll(() async {
      dio = await authenticatedDio();
      archiveRepo = ArchiveRepository(dio);
      statsRepo = StatsRepository(dio);
      logRepo = PrintLogRepository(dio);
    });

    test(
      'GET /archives/ and /archives/search decode into Archive models',
      () async {
        final archives = await archiveRepo.list(limit: 10);
        expect(archives, isA<List<Archive>>());

        final searchResults = await archiveRepo.search('test', limit: 5);
        expect(searchResults, isA<List<Archive>>());

        // The detail routes on an archive of its own: the newest one on the
        // server may be a print another file drove over MQTT, which has no 3MF
        // and answers 404 to `/capabilities` and `/plates` — which file ran
        // first decides that, and it is not always the same.
        final file = (await LibraryRepository(
          dio,
        ).listFiles()).firstWhere((f) => f.filename == 'contract-probe.3mf');
        final bytes = (await dio.get<List<int>>(
          '${Endpoints.libraryFile(file.id)}/download',
          options: Options(responseType: ResponseType.bytes),
        )).data!;
        final ownId =
            (await dio.post<Map<String, dynamic>>(
                  '${Endpoints.archives}upload',
                  data: FormData.fromMap({
                    'file': MultipartFile.fromBytes(
                      bytes,
                      filename: 'decode.3mf',
                    ),
                  }),
                )).data!['id']
                as int;
        addTearDown(() => archiveRepo.delete(ownId, purgeStats: true));
        final own = (await archiveRepo.list(
          limit: 10,
        )).where((a) => a.id == ownId);
        expect(own, hasLength(1), reason: 'the list decodes the new row');

        {
          final a = own.single;
          expect(a.id, greaterThan(0));
          expect(a.filename, isNotEmpty);
          expect(a.status, isNotEmpty);

          final single = await archiveRepo.byId(a.id);
          expect(single.id, a.id);
          expect(single.filename, a.filename);

          final caps = await dio.get<Map<String, dynamic>>(
            Endpoints.archiveCapabilities(a.id),
          );
          final parsedCaps = ArchiveCapabilities.fromJson(
            caps.data ?? const {},
          );
          expect(parsedCaps, isA<ArchiveCapabilities>());

          final plates = await archiveRepo.plates(a.id);
          expect(plates, isA<PlateList>());

          if (a.timelapsePath != null) {
            final timelapseRepo = TimelapseRepository(dio);
            final info = await timelapseRepo.info(a.id);
            expect(info, isA<TimelapseInfo>());
          }
        }
      },
    );

    test(
      'one printer\'s archive pages with printer_id, limit and offset',
      () async {
        // What the controller's Archive view reads, 50 rows at a time.
        final printerId =
            (await dio.get<List<dynamic>>(
                  Endpoints.printers,
                )).data!.cast<Map<String, dynamic>>().first['id']
                as int;
        final file = (await LibraryRepository(
          dio,
        ).listFiles()).firstWhere((f) => f.filename == 'contract-probe.3mf');
        final bytes = (await dio.get<List<int>>(
          '${Endpoints.libraryFile(file.id)}/download',
          options: Options(responseType: ResponseType.bytes),
        )).data!;
        final made = <int>[];
        for (final name in ['paged-a.3mf', 'paged-b.3mf']) {
          final res = await dio.post<Map<String, dynamic>>(
            '${Endpoints.archives}upload',
            queryParameters: {'printer_id': printerId},
            data: FormData.fromMap({
              'file': MultipartFile.fromBytes(bytes, filename: name),
            }),
          );
          made.add(res.data!['id'] as int);
        }
        addTearDown(() async {
          for (final id in made) {
            await archiveRepo.delete(id, purgeStats: true);
          }
        });

        final first = await archiveRepo.list(
          printerId: printerId,
          limit: 1,
          offset: 0,
        );
        final second = await archiveRepo.list(
          printerId: printerId,
          limit: 1,
          offset: 1,
        );

        expect(first, hasLength(1));
        expect(second, hasLength(1));
        expect(first.single.id, isNot(second.single.id));
        expect(
          [first.single.printerId, second.single.printerId],
          [printerId, printerId],
        );
        // Both uploads land in the same second, and the server breaks that tie
        // as it likes; the two pages still hold the two prints, once each.
        expect({first.single.id, second.single.id}, made.toSet());
        expect(
          await archiveRepo.list(printerId: printerId + 9999, limit: 50),
          isEmpty,
        );
      },
    );

    test('GET /archives/stats decodes into ArchiveStats', () async {
      final stats = await statsRepo.fetch();
      expect(stats, isA<ArchiveStats>());
      expect(stats.totalPrints, greaterThanOrEqualTo(0));
      expect(stats.successfulPrints, greaterThanOrEqualTo(0));
      expect(stats.failedPrints, greaterThanOrEqualTo(0));
    });

    test('GET /archives/slim decodes into ArchiveSlim list', () async {
      final slim = await statsRepo.fetchSlim();
      expect(slim, isA<List<ArchiveSlim>>());
      for (final s in slim) {
        expect(s.status, isNotEmpty);
        expect(s.createdAt, isNotNull);
      }
    });

    test(
      'GET /archives/analysis/failures decodes into FailureAnalysis',
      () async {
        final res = await dio.get<Map<String, dynamic>>(
          Endpoints.archivesFailures,
          queryParameters: {'days': 30},
        );
        final analysis = FailureAnalysis.fromJson(res.data ?? const {});
        expect(analysis, isA<FailureAnalysis>());
        expect(analysis.periodDays, greaterThanOrEqualTo(0));
        expect(analysis.totalPrints, greaterThanOrEqualTo(0));
        expect(analysis.failureRate, greaterThanOrEqualTo(0.0));
      },
    );

    test(
      'GET /archives/purge/preview decodes into ArchivePurgePreview',
      () async {
        final preview = await archiveRepo.purgePreview(olderThanDays: 90);
        expect(preview, isA<ArchivePurgePreview>());
        expect(preview.count, greaterThanOrEqualTo(0));
        expect(preview.totalBytes, greaterThanOrEqualTo(0));
      },
    );

    test('GET /archives/no-3mf-warning decodes into No3mfWarning', () async {
      final warning = await archiveRepo.no3mfWarning();
      expect(warning, isA<No3mfWarning>());
    });

    test(
      'GET /print-log/ decodes into PrintLogPage and PrintLogEntry',
      () async {
        final page = await logRepo.list(limit: 10);
        expect(page.items, isA<List<PrintLogEntry>>());
        expect(page.total, greaterThanOrEqualTo(0));
        for (final entry in page.items) {
          expect(entry.id, greaterThan(0));
          expect(entry.status, isNotEmpty);
        }
      },
    );
  });
}
