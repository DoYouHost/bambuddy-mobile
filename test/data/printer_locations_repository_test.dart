import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/printer_location.dart';
import 'package:bambuddy_mobile/data/printer_locations_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late PrinterLocationsRepository repo;

  setUp(() {
    dio = testDio();
    adapter = mockServer(dio);
    repo = PrinterLocationsRepository(dio, ServerVersionService(dio));
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

    test('a 1.2.6 daily is offered the screen', () async {
      replyVersion('1.2.6b1-daily.20261004');
      expect(await repo.capability.supported, isTrue);
    });

    test('a 404 on the listing hides it on a server the version '
        'would have offered it to', () async {
      replyVersion('1.2.6b1');
      adapter.onGet(
        '/api/v1/printer-locations/',
        (s) => s.reply(404, {'detail': 'Not Found'}),
      );

      expect(await repo.list(), isEmpty);
      expect(await repo.capability.supported, isFalse);
    });

    test('a refused write leaves the read side offered', () async {
      adapter
        ..onGet('/api/v1/printer-locations/', (s) => s.reply(200, <Object>[]))
        ..onPost(
          '/api/v1/printer-locations/',
          (s) => s.reply(403, {'detail': 'Missing required permissions'}),
          data: const PrinterLocationDraft(name: 'Rack').toCreateJson(),
        );
      await repo.list();

      await expectLater(
        repo.create(const PrinterLocationDraft(name: 'Rack')),
        throwsA(isA<AppApiException>()),
      );

      expect(repo.capability.observedAnswer, isTrue);
    });
  });

  test(
    'list reads a styled location, an unstyled one and an empty one',
    () async {
      adapter.onGet(
        '/api/v1/printer-locations/',
        (s) => s.reply(200, [
          {
            'id': 4,
            'name': 'Rack 1',
            'icon': 'server',
            'color': '#3b82f6',
            'printer_count': 2,
          },
          // A location only printers carry has no row, so no id.
          {
            'id': null,
            'name': 'Office',
            'icon': null,
            'color': null,
            'printer_count': 1,
          },
          {'id': 9, 'name': 'Attic', 'printer_count': 0},
        ]),
      );

      final rows = await repo.list();

      expect(rows.map((r) => r.name), ['Rack 1', 'Office', 'Attic']);
      expect(rows.first.id, 4);
      expect(rows.first.icon, 'server');
      expect(rows.first.color, '#3b82f6');
      expect(rows[1].id, isNull);
      expect(rows[1].printerCount, 1);
      expect(rows.last.icon, isNull);
      expect(rows.last.printerCount, 0);
    },
  );

  group('drafts', () {
    test('an update sends the emptied icon and colour so the server clears '
        'them', () {
      expect(const PrinterLocationDraft(name: 'Rack').toUpdateJson(), {
        'name': 'Rack',
        'icon': null,
        'color': null,
      });
    });

    test('an update names the new name only when it changed', () {
      expect(
        const PrinterLocationDraft(
          name: 'Rack',
          newName: 'Rack',
          icon: 'home',
        ).toUpdateJson(),
        {'name': 'Rack', 'icon': 'home', 'color': null},
      );
      expect(
        const PrinterLocationDraft(
          name: 'Rack',
          newName: 'Shelf',
        ).toUpdateJson(),
        containsPair('new_name', 'Shelf'),
      );
    });
  });

  test('update addresses the location by its current name', () async {
    adapter.onPatch(
      '/api/v1/printer-locations/',
      (s) => s.reply(200, {
        'id': 4,
        'name': 'Shelf',
        'icon': null,
        'color': '#22c55e',
        'printer_count': 2,
      }),
      data: {
        'name': 'Rack',
        'new_name': 'Shelf',
        'icon': null,
        'color': '#22c55e',
      },
    );

    final saved = await repo.update(
      const PrinterLocationDraft(
        name: 'Rack',
        newName: 'Shelf',
        color: '#22c55e',
      ),
    );

    expect(saved.name, 'Shelf');
    expect(saved.color, '#22c55e');
  });

  test('delete sends the names and reads the counts', () async {
    adapter.onPost(
      '/api/v1/printer-locations/delete',
      (s) => s.reply(200, {'deleted': 2, 'printers_ungrouped': 3}),
      data: {
        'names': ['A', 'B'],
      },
    );

    final result = await repo.delete(['A', 'B']);

    expect(result.deleted, 2);
    expect(result.printersUngrouped, 3);
  });

  test('assign sends null to take printers out of every location', () async {
    adapter.onPost(
      '/api/v1/printer-locations/assign',
      (s) => s.reply(200, {'moved': 2}),
      data: {
        'printer_ids': [1, 2],
        'location': null,
      },
    );

    expect(await repo.assign([1, 2], null), 2);
  });

  test('a name taken is the server\'s 409, not a swallowed error', () async {
    adapter.onPost(
      '/api/v1/printer-locations/',
      (s) =>
          s.reply(409, {'detail': 'A location with this name already exists'}),
      data: const PrinterLocationDraft(name: 'Rack').toCreateJson(),
    );

    await expectLater(
      repo.create(const PrinterLocationDraft(name: 'Rack')),
      throwsA(
        isA<AppApiException>().having((e) => e.statusCode, 'status', 409),
      ),
    );
  });
}
