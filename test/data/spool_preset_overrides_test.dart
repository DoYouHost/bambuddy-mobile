import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/spool_preset_override.dart';
import 'package:bambuddy_mobile/data/inventory_repository.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late RequestLog sent;

  setUp(() {
    dio = testDio();
    adapter = DioAdapter(dio: dio);
    sent = captureRequests(dio);
  });

  void replyVersion(String version) => adapter.onGet(
    '/api/v1/updates/version',
    (s) => s.reply(200, {'version': version, 'repo': 'x/y'}),
  );

  InventoryRepository nativeRepo() => InventoryRepository(
    NativeInventorySource(dio),
    ServerVersionService(dio),
  );

  group('reading a spool\'s per-model presets', () {
    test('keeps both levels of the cascade, and what each names', () async {
      replyVersion('1.2.6b1');
      adapter.onGet(
        '/api/v1/inventory/spools/7/filament-presets',
        (s) => s.reply(200, [
          {
            'id': 1,
            'spool_id': 7,
            'printer_model': 'X1C',
            'nozzle_diameter': '',
            'slicer_filament': 'GFA00',
            'slicer_filament_name': 'Bambu PLA Basic @BBL X1C',
            'created_at': '2026-09-01T10:00:00Z',
          },
          {
            'id': 2,
            'spool_id': 7,
            'printer_model': 'H2D',
            'nozzle_diameter': '0.2',
            'slicer_filament': null,
            'slicer_filament_name': null,
            'created_at': '2026-09-01T10:00:00Z',
          },
        ]),
      );

      final rows = await nativeRepo().fetchPresetOverrides(7);

      expect(rows.map((r) => r.key), ['X1C|', 'H2D|0.2']);
      expect(rows.first.slicerFilamentName, 'Bambu PLA Basic @BBL X1C');
      // A row with no preset is "use none here", not a hole to fall through —
      // the app has to be able to write it back exactly as it found it.
      expect(rows.last.slicerFilament, isNull);
    });

    test('a 404 shows no rows without taking the section away', () async {
      // The route raises 404 for a spool that is gone as well as on a server
      // that never had it (`inventory.py::"Spool not found"`), so it cannot
      // settle the question — opening one stale spool used to hide the whole
      // section until the app was restarted.
      replyVersion('1.2.6b1');
      adapter.onGet(
        '/api/v1/inventory/spools/7/filament-presets',
        (s) => s.reply(404, {'detail': 'Spool not found'}),
      );
      final repo = nativeRepo();

      expect(await repo.fetchPresetOverrides(7), isEmpty);
      expect(
        await repo.supportsPresetOverrides(),
        isTrue,
        reason: 'the version row is what answers this',
      );
    });

    test('a 403 reaches the caller — a form that showed nothing would '
        'invite a save that wipes what it could not read', () async {
      replyVersion('1.2.6b1');
      adapter.onGet(
        '/api/v1/inventory/spools/7/filament-presets',
        (s) => s.reply(403, {'detail': 'Missing required permissions'}),
      );

      await expectLater(
        nativeRepo().fetchPresetOverrides(7),
        throwsA(
          isA<AuthException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.forbidden,
          ),
        ),
      );
    });
  });

  group('the version behind the latch', () {
    test('a server older than the route is not offered the section', () async {
      replyVersion('1.2.5.4');

      expect(await nativeRepo().supportsPresetOverrides(), isFalse);
    });

    test('the beta the route shipped in counts as its release', () async {
      replyVersion('1.2.6b1');

      expect(await nativeRepo().supportsPresetOverrides(), isTrue);
    });

    test('a version that cannot be read hides the section rather than '
        'offering a write that would 404', () async {
      adapter.onGet(
        '/api/v1/updates/version',
        (s) => s.reply(500, {'detail': 'boom'}),
      );

      expect(await nativeRepo().supportsPresetOverrides(), isFalse);
    });
  });

  group('writing them back', () {
    test(
      'sends the write shape, and nothing the route does not accept',
      () async {
        replyVersion('1.2.6b1');
        adapter.onPut(
          '/api/v1/inventory/spools/7/filament-presets',
          (s) => s.reply(200, []),
          data: Matchers.any,
        );

        await nativeRepo().savePresetOverrides(7, const [
          SpoolPresetOverride(
            printerModel: 'X1C',
            slicerFilament: 'GFA00',
            slicerFilamentName: 'Bambu PLA Basic @BBL X1C',
          ),
        ]);

        final body =
            sent.requests.singleWhere((r) => r.method == 'PUT').data as List;
        expect(body, [
          {
            'printer_model': 'X1C',
            'nozzle_diameter': '',
            'slicer_filament': 'GFA00',
            'slicer_filament_name': 'Bambu PLA Basic @BBL X1C',
          },
        ]);
      },
    );

    test('an empty list is how the last override is cleared', () async {
      replyVersion('1.2.6b1');
      adapter.onPut(
        '/api/v1/inventory/spools/7/filament-presets',
        (s) => s.reply(200, []),
        data: Matchers.any,
      );

      await nativeRepo().savePresetOverrides(7, const []);

      expect(sent.requests.singleWhere((r) => r.method == 'PUT').data, isEmpty);
    });

    test(
      'saving against a spool that is gone does not hide the section',
      () async {
        // Same shape as the drying cancel: the route 404s for a missing spool,
        // and reading that as "this server has no overrides" took the whole
        // section away until the app restarted.
        replyVersion('1.2.6b1');
        adapter.onPut(
          '/api/v1/inventory/spools/7/filament-presets',
          (s) => s.reply(404, {'detail': 'Spool not found'}),
          data: Matchers.any,
        );
        final repo = nativeRepo();

        await expectLater(
          repo.savePresetOverrides(7, const []),
          throwsA(isA<AppApiException>()),
          reason: 'the user pressed Save, so the failure still reaches them',
        );
        expect(await repo.supportsPresetOverrides(), isTrue);
      },
    );

    test(
      'a refusal reaches the user — the save was something they asked for',
      () async {
        replyVersion('1.2.6b1');
        adapter.onPut(
          '/api/v1/inventory/spools/7/filament-presets',
          (s) => s.reply(403, {'detail': 'Missing required permissions'}),
          data: Matchers.any,
        );

        await expectLater(
          nativeRepo().savePresetOverrides(7, const []),
          throwsA(
            isA<AuthException>().having(
              (e) => e.code,
              'code',
              AppErrorCode.forbidden,
            ),
          ),
        );
      },
    );
  });

  test('the Spoolman twin is the same call on the Spoolman path', () async {
    replyVersion('1.2.6b1');
    adapter.onGet(
      '/api/v1/spoolman/inventory/spools/7/filament-presets',
      (s) => s.reply(200, [
        {
          'id': 1,
          'spool_id': 7,
          'printer_model': 'P1S',
          'nozzle_diameter': '',
          'slicer_filament': 'GFA01',
          'slicer_filament_name': 'Bambu PLA Matte @BBL P1S',
        },
      ]),
    );

    final rows = await InventoryRepository(
      SpoolmanInventorySource(dio),
      ServerVersionService(dio),
    ).fetchPresetOverrides(7);

    expect(rows.single.printerModel, 'P1S');
  });
}
