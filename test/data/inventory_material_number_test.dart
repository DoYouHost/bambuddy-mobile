import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/inventory_bulk.dart';
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

  group('capability', () {
    test('the version decides before anything was seen', () async {
      replyVersion('1.2.5.6');
      expect(await repo.materialNumberCapability.supported, isFalse);
    });

    test('a 1.2.6 daily is offered the field', () async {
      replyVersion('1.2.6b1-daily.20260930');
      expect(await repo.materialNumberCapability.supported, isTrue);
    });

    test('a row without the key settles it as absent', () async {
      replyVersion('1.2.6b1-daily.20260920');
      repo.observeSpools([row(const {})]);
      expect(await repo.materialNumberCapability.supported, isFalse);
    });

    test('a row with a null number settles it as present', () async {
      replyVersion('1.2.5.6');
      repo.observeSpools([
        row(const {'material_number': null}),
      ]);
      expect(await repo.materialNumberCapability.supported, isTrue);
    });

    test('an empty inventory settles nothing', () async {
      replyVersion('1.2.5.6');
      repo.observeSpools(const []);
      expect(repo.materialNumberCapability.observedAnswer, isNull);
    });
  });

  group('stats', () {
    const path = '/api/v1/inventory/stats/material-numbers';

    test('rows are parsed and the range goes out as calendar days', () async {
      replyVersion('1.2.6b1');
      adapter.onGet(
        path,
        (s) => s.reply(200, [
          {
            'material_number': '15',
            'spool_count': 6,
            'remaining_g': 3900.5,
            'consumed_g': 3200,
            'cost': 285.0,
          },
        ]),
        queryParameters: {'date_from': '2026-09-01', 'date_to': '2026-09-30'},
      );

      final rows = await repo.fetchMaterialNumberStats(
        from: DateTime(2026, 9),
        to: DateTime(2026, 9, 30),
      );

      expect(rows.single.materialNumber, '15');
      expect(rows.single.spoolCount, 6);
      expect(rows.single.remainingGrams, 3900.5);
      expect(rows.single.consumedGrams, 3200);
      expect(rows.single.cost, 285);
    });

    test('a 404 is an empty list and settles the gate as absent', () async {
      replyVersion('1.2.6b1');
      adapter.onGet(path, (s) => s.reply(404, {'detail': 'Not Found'}));

      expect(await repo.fetchMaterialNumberStats(), isEmpty);
      expect(await repo.materialNumberCapability.supported, isFalse);
    });

    test('Spoolman is never asked', () async {
      replyVersion('1.2.6b1');
      final spoolman = InventoryRepository(
        SpoolmanInventorySource(dio),
        ServerVersionService(dio),
      );
      expect(await spoolman.fetchMaterialNumberStats(), isEmpty);
    });

    test('a row missing its figures reads as zeros', () {
      final row = MaterialNumberStats.fromJson(const {'material_number': 'A'});
      expect(
        [row.spoolCount, row.remainingGrams, row.consumedGrams, row.cost],
        [0, 0, 0, 0],
      );
    });
  });

  group('Spool', () {
    test('reads the number and whether the key was there', () {
      final withNumber = row(const {'material_number': '15'});
      expect(withNumber.materialNumber, '15');
      expect(withNumber.materialNumberReported, isTrue);

      final without = row(const {});
      expect(without.materialNumber, isNull);
      expect(without.materialNumberReported, isFalse);
    });

    test('a Spoolman row reads it the same way', () {
      final spool = Spool.fromSpoolman(const {
        'id': 2,
        'material': 'PLA',
        'material_number': 'A-104',
      });
      expect(spool.materialNumber, 'A-104');
      expect(spool.materialNumberReported, isTrue);
    });

    test('search finds a spool by its number', () {
      final spool = row(const {'material_number': 'A-104'});
      expect(spool.matchesSearch('a-10'), isTrue);
      expect(spool.matchesSearch('zzz'), isFalse);
    });
  });

  group('writes', () {
    test('a draft without a number keeps the key off the wire', () {
      expect(
        const SpoolDraft(
          material: 'PLA',
        ).toNativeJson().containsKey('material_number'),
        isFalse,
      );
    });

    test('an empty number is sent, so it can clear the field', () {
      final json = const SpoolDraft(
        material: 'PLA',
        materialNumber: '',
      ).toNativeJson();
      expect(json['material_number'], '');
    });

    test('editing a spool prefills the draft with its number', () {
      final draft = SpoolDraft.fromSpool(row(const {'material_number': '15'}));
      expect(draft.toNativeJson()['material_number'], '15');
    });

    test('Spoolman never receives it', () {
      const draft = SpoolDraft(material: 'PLA', materialNumber: '15');
      expect(draft.toSpoolmanJson().containsKey('material_number'), isFalse);
    });

    test('the bulk patch carries it on the native route only', () {
      const patch = SpoolBulkPatch(materialNumber: '15');
      expect(patch.toNativeJson(), {'material_number': '15'});
      expect(patch.toSpoolmanJson(), isEmpty);
      expect(patch.isEmpty, isFalse);
    });
  });
}
