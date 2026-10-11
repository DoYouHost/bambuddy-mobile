import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/supplier.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/data/suppliers_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late SuppliersRepository repo;

  setUp(() {
    dio = testDio();
    adapter = mockServer(dio);
    repo = SuppliersRepository(dio, ServerVersionService(dio));
  });

  void replyVersion(String version) => adapter.onGet(
    '/api/v1/updates/version',
    (s) => s.reply(200, {'version': version, 'repo': 'x/y'}),
  );

  group('capability', () {
    test('the version decides before anything was seen', () async {
      replyVersion('1.2.5.6');
      expect(await repo.capability.supported, isFalse);
    });

    test('a 1.2.6 daily is offered suppliers', () async {
      replyVersion('1.2.6b1-daily.20260929');
      expect(await repo.capability.supported, isTrue);
    });

    test('a spool row without the key settles it as absent', () async {
      replyVersion('1.2.6b1-daily.20260920');
      repo.observeSpools([
        Spool.fromNative(const {'id': 1, 'material': 'PLA'}),
      ]);
      expect(await repo.capability.supported, isFalse);
    });

    test('a spool row with an empty list settles it as present', () async {
      replyVersion('1.2.5.6');
      repo.observeSpools([
        Spool.fromNative(const {'id': 1, 'material': 'PLA', 'suppliers': []}),
      ]);
      expect(await repo.capability.supported, isTrue);
    });

    test('an empty inventory settles nothing', () async {
      replyVersion('1.2.5.6');
      repo.observeSpools(const []);
      expect(repo.capability.observedAnswer, isNull);
    });

    test('a 404 on the listing hides it on a server the version '
        'would have offered it to', () async {
      replyVersion('1.2.6b1');
      adapter.onGet(
        '/api/v1/inventory/suppliers',
        (s) => s.reply(404, {'detail': 'Not Found'}),
      );

      expect(await repo.listSuppliers(), isEmpty);
      expect(await repo.capability.supported, isFalse);
    });

    test('a 403 on the listing is a refusal, not an empty list', () async {
      adapter.onGet(
        '/api/v1/inventory/suppliers',
        (s) => s.reply(403, {'detail': 'Missing required permissions'}),
      );

      expect(await repo.listSuppliers(), isEmpty);
      expect(repo.capability.observedAnswer, isFalse);
    });
  });

  test('a refused write leaves the read side offered', () async {
    adapter
      ..onGet('/api/v1/inventory/suppliers', (s) => s.reply(200, <Object>[]))
      ..onPost(
        '/api/v1/inventory/suppliers',
        (s) => s.reply(403, {'detail': 'Missing required permissions'}),
        data: const SupplierDraft(name: 'X').toJson(),
      );
    await repo.listSuppliers();

    await expectLater(
      repo.createSupplier(const SupplierDraft(name: 'X')),
      throwsA(isA<AppApiException>()),
    );

    expect(repo.capability.observedAnswer, isTrue);
  });

  test('listSuppliers reads every field the sheet shows', () async {
    adapter.onGet(
      '/api/v1/inventory/suppliers',
      (s) => s.reply(200, [
        {
          'id': 3,
          'name': 'Extrudr',
          'website': 'https://extrudr.com',
          'customer_number': 'K-1',
          'note': 'fast',
          'spool_count': 4,
          'created_at': '2026-09-28T10:00:00',
          'updated_at': '2026-09-28T10:00:00',
        },
        {
          'id': 5,
          'name': 'Filamentworld',
          'website': null,
          'customer_number': null,
          'note': null,
          'spool_count': 0,
          'created_at': '2026-09-28T10:00:00',
          'updated_at': '2026-09-28T10:00:00',
        },
      ]),
    );

    final rows = await repo.listSuppliers();

    expect(rows.map((r) => r.name), ['Extrudr', 'Filamentworld']);
    expect(rows.first.website, 'https://extrudr.com');
    expect(rows.first.customerNumber, 'K-1');
    expect(rows.first.note, 'fast');
    expect(rows.map((r) => r.spoolCount), [4, 0]);
    expect(rows.last.website, isNull);
    expect(await repo.capability.supported, isTrue);
  });

  test('a PATCH sends every field, so an emptied one is cleared', () async {
    final log = captureRequests(dio);
    adapter.onPatch(
      '/api/v1/inventory/suppliers/3',
      (s) => s.reply(200, {'id': 3, 'name': 'Extrudr', 'spool_count': 1}),
      data: {
        'name': 'Extrudr',
        'website': null,
        'customer_number': 'K-2',
        'note': null,
      },
    );

    final saved = await repo.updateSupplier(
      3,
      const SupplierDraft(name: 'Extrudr', customerNumber: 'K-2'),
    );

    expect(saved.spoolCount, 1);
    expect(log.calls, ['PATCH /api/v1/inventory/suppliers/3']);
  });

  test('a duplicate name reaches the caller as its 409', () async {
    adapter.onPost(
      '/api/v1/inventory/suppliers',
      (s) =>
          s.reply(409, {'detail': 'A supplier with this name already exists'}),
      data: const SupplierDraft(name: 'extrudr').toJson(),
    );

    await expectLater(
      repo.createSupplier(const SupplierDraft(name: 'extrudr')),
      throwsA(
        isA<AppApiException>().having((e) => e.statusCode, 'status', 409),
      ),
    );
  });

  test('a supplier still assigned reaches the caller as its 409', () async {
    adapter.onDelete(
      '/api/v1/inventory/suppliers/3',
      (s) => s.reply(409, {
        'detail': 'Supplier has spools assigned and cannot be deleted',
      }),
    );

    await expectLater(
      repo.deleteSupplier(3),
      throwsA(
        isA<AppApiException>().having((e) => e.statusCode, 'status', 409),
      ),
    );
  });

  group('saveSpoolLinks', () {
    const links = [
      SpoolSupplierLink(
        supplierId: 3,
        supplierName: 'Extrudr',
        articleNumber: 'NX2-1',
        quotedPricePerKg: 24.5,
        isPurchaseSource: true,
      ),
      SpoolSupplierLink(supplierId: 5, supplierName: 'Filamentworld'),
    ];
    const body = [
      {
        'supplier_id': 3,
        'supplier_article_number': 'NX2-1',
        'quoted_price_per_kg': 24.5,
        'is_purchase_source': true,
      },
      {
        'supplier_id': 5,
        'supplier_article_number': null,
        'quoted_price_per_kg': null,
        'is_purchase_source': false,
      },
    ];

    for (final (backend, path) in [
      (InventoryBackend.native, '/api/v1/inventory/spools/7/suppliers'),
      (
        InventoryBackend.spoolman,
        '/api/v1/spoolman/inventory/spools/7/suppliers',
      ),
    ]) {
      test('${backend.name} writes the whole list to its own route', () async {
        final log = captureRequests(dio);
        adapter.onPut(path, (s) => s.reply(200, <Object>[]), data: body);

        await repo.saveSpoolLinks(7, links, backend: backend);

        expect(log.calls, ['PUT $path']);
        expect(log.last.data, body);
      });
    }
  });

  test('fetchStats sends the range as calendar days', () async {
    final log = captureRequests(dio);
    adapter.onGet(
      '/api/v1/inventory/stats/suppliers',
      (s) => s.reply(200, [
        {
          'supplier_id': 3,
          'supplier_name': 'Extrudr',
          'spool_count': 2,
          'remaining_g': 1500.0,
          'consumed_g': 820.5,
          'cost': 19.4,
        },
      ]),
      queryParameters: {'date_from': '2026-09-01', 'date_to': '2026-09-30'},
    );

    final rows = await repo.fetchStats(
      from: DateTime(2026, 9),
      to: DateTime(2026, 9, 30),
    );

    expect(log.last.queryParameters, {
      'date_from': '2026-09-01',
      'date_to': '2026-09-30',
    });
    final row = rows.single;
    expect(row.supplierName, 'Extrudr');
    expect(row.spoolCount, 2);
    expect(row.remainingGrams, 1500);
    expect(row.consumedGrams, 820.5);
    expect(row.cost, 19.4);
  });

  group('Spool.suppliers', () {
    test('absent key parses as null, not as an empty list', () {
      expect(
        Spool.fromNative(const {'id': 1, 'material': 'PLA'}).suppliers,
        isNull,
      );
      expect(
        Spool.fromSpoolman(const {'id': 1, 'material': 'PLA'}).suppliers,
        isNull,
      );
    });

    test('both backends read the same link shape', () {
      const json = {
        'id': 1,
        'material': 'PLA',
        'suppliers': [
          {
            'id': 9,
            'supplier_id': 3,
            'supplier_name': 'Extrudr',
            'supplier_article_number': 'NX2-1',
            'quoted_price_per_kg': 24.5,
            'is_purchase_source': true,
          },
        ],
      };
      for (final spool in [Spool.fromNative(json), Spool.fromSpoolman(json)]) {
        final link = spool.suppliers!.single;
        expect(link.supplierId, 3);
        expect(link.supplierName, 'Extrudr');
        expect(link.articleNumber, 'NX2-1');
        expect(link.quotedPricePerKg, 24.5);
        expect(link.isPurchaseSource, isTrue);
      }
    });

    test('search finds a spool by any supplier it can be bought from', () {
      final spool = Spool.fromNative(const {
        'id': 1,
        'material': 'PLA',
        'suppliers': [
          {'supplier_id': 3, 'supplier_name': 'Extrudr'},
        ],
      });
      expect(spool.matchesSearch('extru'), isTrue);
      expect(spool.matchesSearch('amazon'), isFalse);
    });
  });

  test('purchaseSourceFirst moves the purchase source to the front', () {
    final ordered = purchaseSourceFirst(const [
      SpoolSupplierLink(supplierId: 1),
      SpoolSupplierLink(supplierId: 2, isPurchaseSource: true),
      SpoolSupplierLink(supplierId: 3),
    ]);
    expect(ordered.map((l) => l.supplierId), [2, 1, 3]);
  });
}
