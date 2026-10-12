import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/data/inventory_repository.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late InventoryRepository repo;

  setUp(() {
    dio = testDio();
    adapter = mockServer(dio);
    repo = InventoryRepository(
      NativeInventorySource(dio),
      ServerVersionService(dio),
    );
  });

  void replyVersion(String version) => adapter.onGet(
    '/api/v1/updates/version',
    (s) => s.reply(200, {'version': version, 'repo': 'x/y'}),
  );

  Spool row(Map<String, dynamic> extra) =>
      Spool.fromNative({'id': 1, 'material': 'PLA', ...extra});

  group('Spool', () {
    test('reads the date, the run and whether the key was there', () {
      final spool = row(const {
        'last_dried_at': '2026-10-06T13:05:00',
        'last_dried_temp': 55,
        'last_dried_hours': 7.5,
      });
      // A server timestamp is UTC even without its Z; the model holds it local.
      expect(
        spool.lastDriedAt!.isAtSameMomentAs(DateTime.utc(2026, 10, 6, 13, 5)),
        isTrue,
      );
      expect(spool.lastDriedTemp, 55);
      expect(spool.lastDriedHours, 7.5);
      expect(spool.lastDriedReported, isTrue);
    });

    test('a date set by hand has no temperature or hours', () {
      final spool = row(const {
        'last_dried_at': '2026-10-06T13:05:00Z',
        'last_dried_temp': null,
        'last_dried_hours': null,
      });
      expect(spool.lastDriedAt, isNotNull);
      expect(spool.lastDriedTemp, isNull);
      expect(spool.lastDriedHours, isNull);
    });

    test('a spool never dried still reports the key', () {
      final spool = row(const {'last_dried_at': null});
      expect(spool.lastDriedAt, isNull);
      expect(spool.lastDriedReported, isTrue);
    });

    test('an older server sends no key', () {
      final spool = row(const {});
      expect(spool.lastDriedAt, isNull);
      expect(spool.lastDriedReported, isFalse);
    });

    test('whole hours arrive as a number, not a string', () {
      expect(row(const {'last_dried_hours': 8}).lastDriedHours, 8.0);
    });

    test('a Spoolman row reads it the same way', () {
      final spool = Spool.fromSpoolman(const {
        'id': 2,
        'material': 'PLA',
        'last_dried_at': '2026-10-06T13:05:00',
        'last_dried_temp': 50,
        'last_dried_hours': 4.0,
      });
      expect(
        spool.lastDriedAt!.isAtSameMomentAs(DateTime.utc(2026, 10, 6, 13, 5)),
        isTrue,
      );
      expect(spool.lastDriedTemp, 50);
      expect(spool.lastDriedHours, 4.0);
      expect(spool.lastDriedReported, isTrue);
    });

    test('a Spoolman row with no date reads as never dried', () {
      final spool = Spool.fromSpoolman(const {
        'id': 2,
        'material': 'PLA',
        'last_dried_at': null,
      });
      expect(spool.lastDriedAt, isNull);
      expect(spool.lastDriedReported, isTrue);
    });
  });

  group('capability', () {
    test('the version decides before anything was seen', () async {
      replyVersion('1.2.5.6');
      expect(await repo.lastDriedCapability.supported, isFalse);
    });

    test('a 1.2.6 daily is offered the field', () async {
      replyVersion('1.2.6b1-daily.20261006');
      expect(await repo.lastDriedCapability.supported, isTrue);
    });

    test('a row without the key settles it as absent', () async {
      replyVersion('1.2.6b1-daily.20260920');
      repo.observeSpools([row(const {})]);
      expect(await repo.lastDriedCapability.supported, isFalse);
    });

    test('a row with a null date settles it as present', () async {
      replyVersion('1.2.5.6');
      repo.observeSpools([
        row(const {'last_dried_at': null}),
      ]);
      expect(await repo.lastDriedCapability.supported, isTrue);
    });

    test('an empty inventory settles nothing', () async {
      replyVersion('1.2.5.6');
      repo.observeSpools(const []);
      expect(repo.lastDriedCapability.observedAnswer, isNull);
    });

    test('the material number latch is not moved by it', () async {
      replyVersion('1.2.5.6');
      repo.observeSpools([
        row(const {'last_dried_at': null}),
      ]);
      expect(repo.materialNumberCapability.observedAnswer, isFalse);
    });
  });
}
