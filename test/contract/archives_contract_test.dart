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
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/data/print_log_repository.dart';
import 'package:bambuddy_mobile/data/stats_repository.dart';
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

    test('GET /archives/ and /archives/search decode into Archive models', () async {
      final archives = await archiveRepo.list(limit: 10);
      expect(archives, isA<List<Archive>>());

      final searchResults = await archiveRepo.search('test', limit: 5);
      expect(searchResults, isA<List<Archive>>());

      if (archives.isNotEmpty) {
        final a = archives.first;
        expect(a.id, greaterThan(0));
        expect(a.filename, isNotEmpty);
        expect(a.status, isNotEmpty);

        final single = await archiveRepo.byId(a.id);
        expect(single.id, a.id);
        expect(single.filename, a.filename);

        final caps = await dio.get<Map<String, dynamic>>(
          Endpoints.archiveCapabilities(a.id),
        );
        final parsedCaps = ArchiveCapabilities.fromJson(caps.data ?? const {});
        expect(parsedCaps, isA<ArchiveCapabilities>());

        final plates = await archiveRepo.plates(a.id);
        expect(plates, isA<PlateList>());
      }
    });

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

    test('GET /archives/analysis/failures decodes into FailureAnalysis', () async {
      final res = await dio.get<Map<String, dynamic>>(
        Endpoints.archivesFailures,
        queryParameters: {'days': 30},
      );
      final analysis = FailureAnalysis.fromJson(res.data ?? const {});
      expect(analysis, isA<FailureAnalysis>());
      expect(analysis.periodDays, greaterThanOrEqualTo(0));
      expect(analysis.totalPrints, greaterThanOrEqualTo(0));
      expect(analysis.failureRate, greaterThanOrEqualTo(0.0));
    });

    test('GET /archives/purge/preview decodes into ArchivePurgePreview', () async {
      final preview = await archiveRepo.purgePreview(olderThanDays: 90);
      expect(preview, isA<ArchivePurgePreview>());
      expect(preview.count, greaterThanOrEqualTo(0));
      expect(preview.totalBytes, greaterThanOrEqualTo(0));
    });

    test('GET /archives/no-3mf-warning decodes into No3mfWarning', () async {
      final warning = await archiveRepo.no3mfWarning();
      expect(warning, isA<No3mfWarning>());
    });

    test('GET /print-log/ decodes into PrintLogPage and PrintLogEntry', () async {
      final page = await logRepo.list(limit: 10);
      expect(page.items, isA<List<PrintLogEntry>>());
      expect(page.total, greaterThanOrEqualTo(0));
      for (final entry in page.items) {
        expect(entry.id, greaterThan(0));
        expect(entry.status, isNotEmpty);
      }
    });
  });
}
