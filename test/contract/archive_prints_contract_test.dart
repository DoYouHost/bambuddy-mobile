import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:app_util/app_util.dart';
import 'package:bambuddy_mobile/core/format/system_clock_sync.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// The archive calendar's read: every print that ended in a month. A server
/// before the archive redesign answers 422 (`/archives/{archive_id}` takes the
/// path), which the app reads as "place each archive as its one print".
void main() {
  group('archive prints contract', skip: contractSkipReason, () {
    late Dio dio;
    late ArchiveRepository repo;
    late bool served;

    setUpAll(() async {
      dio = await authenticatedDio();
      // Android answers the zone in the app; here a zone the server must
      // accept stands in, so `tz` reaches the server as it does from a phone.
      repo = ArchiveRepository(dio, null, const _Warsaw());
      served = (await contractServerVersion()).supports(
        ServerFeature.archiveCalendar,
      );
    });

    test(
      'a month reads as a list, or as no route on an older server',
      () async {
        final now = DateTime.now();
        final rows = await repo.printsBetween(
          DateTime(now.year, now.month),
          DateTime(now.year, now.month + 1, 0),
        );

        if (served) {
          expect(rows, isNotNull);
          expect(rows!.every((r) => r.archiveId != null), isTrue);
          expect(await repo.printsCapability.supported, isTrue);
        } else {
          expect(rows, isNull);
          expect(await repo.printsCapability.supported, isFalse);
        }
      },
    );

    test('a printer filter is accepted', () async {
      if (!served) return markTestSkipped('the server predates the calendar');
      final now = DateTime.now();

      final rows = await repo.printsBetween(
        DateTime(now.year, now.month),
        DateTime(now.year, now.month + 1, 0),
        printerId: 999999,
      );

      expect(rows, isEmpty, reason: 'a printer outside the scope has none');
    });
  });
}

class _Warsaw implements SystemClockQuery {
  const _Warsaw();

  @override
  Future<String?> timeZone() async => 'Europe/Warsaw';

  @override
  Future<bool?> read() async => true;

  @override
  PlatformQuery get platform => throw UnimplementedError();
}
