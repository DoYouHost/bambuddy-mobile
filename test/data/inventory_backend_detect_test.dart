import 'package:bambuddy_mobile/core/api/api_client.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

/// The app talks to whichever inventory the server runs, as `/spoolman/status`
/// says — before this, nothing ever switched it off the built-in one, and a
/// Spoolman user saw an empty shelf (issue #5).
void main() {
  const status = '/api/v1/spoolman/status';
  late Dio dio;
  late DioAdapter adapter;
  late RequestLog sent;

  setUp(() {
    dio = testDio();
    adapter = mockServer(dio);
    sent = captureRequests(dio);
  });

  group('detectInventoryBackend', () {
    Future<InventoryBackend> answer(Map<String, dynamic> body) {
      adapter.onGet(status, (s) => s.reply(200, body));
      return detectInventoryBackend(dio);
    }

    test('enabled with a URL is Spoolman, whether or not it is up', () async {
      expect(
        await answer({
          'enabled': true,
          'connected': true,
          'url': 'http://spoolman:8000',
        }),
        InventoryBackend.spoolman,
      );
      expect(
        await answer({
          'enabled': true,
          'connected': false,
          'url': 'http://spoolman:8000',
        }),
        InventoryBackend.spoolman,
      );
    });

    test('disabled is native, even with a URL left behind', () async {
      expect(
        await answer({
          'enabled': false,
          'connected': false,
          'url': 'http://spoolman:8000',
        }),
        InventoryBackend.native,
      );
    });

    test('enabled without a URL is native', () async {
      expect(
        await answer({'enabled': true, 'connected': false, 'url': null}),
        InventoryBackend.native,
      );
      expect(
        await answer({'enabled': true, 'connected': false, 'url': '  '}),
        InventoryBackend.native,
      );
    });

    test('an odd body is native rather than a crash', () async {
      expect(await answer({}), InventoryBackend.native);
      expect(
        await answer({'enabled': 'true', 'url': 'http://spoolman:8000'}),
        InventoryBackend.native,
      );
    });

    for (final code in [403, 404]) {
      test('$code settles on native', () async {
        adapter.onGet(status, (s) => s.reply(code, {'detail': 'x'}));
        expect(await detectInventoryBackend(dio), InventoryBackend.native);
        expect(sent.statuses, [code]);
      });
    }

    test('a server error is thrown, not taken for native', () async {
      adapter.onGet(status, (s) => s.reply(500, {'detail': 'boom'}));
      await expectLater(
        detectInventoryBackend(dio),
        throwsA(isA<AppApiException>()),
      );
    });

    test('no network is thrown, not taken for native', () async {
      adapter.onGet(
        status,
        (s) => s.throws(
          0,
          DioException.connectionError(
            requestOptions: RequestOptions(path: status),
            reason: 'refused',
          ),
        ),
      );
      await expectLater(
        detectInventoryBackend(dio),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  group('inventory providers', () {
    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(
              profile: const ServerProfile(
                baseUrl: fakeServerBaseUrl,
                authMode: AuthMode.none,
              ),
              credentials: InMemoryCredentialsStore(),
              dio: dio,
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('a Spoolman server is read through the Spoolman routes only', () async {
      adapter
        ..onGet(
          status,
          (s) => s.reply(200, {
            'enabled': true,
            'connected': true,
            'url': 'http://spoolman:8000',
          }),
        )
        ..onGet(
          '/api/v1/spoolman/inventory/spools',
          (s) => s.reply(200, [
            {'id': 3, 'material': 'PLA'},
          ]),
          queryParameters: {'include_archived': false},
        );

      // Asked before the status has answered: the call has to wait for it, not
      // go to the built-in inventory in the meantime.
      final spools = await container()
          .read(inventoryRepositoryProvider)
          .fetchSpools();

      expect(spools.map((s) => s.id), [3]);
      expect(sent.calls, [
        'GET $status',
        'GET /api/v1/spoolman/inventory/spools',
      ]);
    });

    test('a failed ask fails the call and is asked again on regained '
        'contact', () async {
      adapter.onGet(
        status,
        (s) => s.throws(
          0,
          DioException.connectionError(
            requestOptions: RequestOptions(path: status),
            reason: 'refused',
          ),
        ),
      );
      final c = container();

      await expectLater(
        c.read(inventoryRepositoryProvider).fetchSpools(),
        throwsA(isA<NetworkException>()),
      );
      expect(sent.calls, ['GET $status']);

      adapter
        ..onGet(
          status,
          (s) =>
              s.reply(200, {'enabled': false, 'connected': false, 'url': null}),
        )
        ..onGet(
          '/api/v1/inventory/spools',
          (s) => s.reply(200, []),
          queryParameters: {'include_archived': false},
        );
      c.read(serverContactEpochProvider.notifier).bump();

      expect(
        await c.read(inventoryBackendProvider.future),
        InventoryBackend.native,
      );
      await c.read(inventoryRepositoryProvider).fetchSpools();
      expect(sent.calls, [
        'GET $status',
        'GET $status',
        'GET /api/v1/inventory/spools',
      ]);
    });

    test('a settled answer is not asked again on regained contact', () async {
      adapter.onGet(
        status,
        (s) =>
            s.reply(200, {'enabled': false, 'connected': false, 'url': null}),
      );
      final c = container();
      await c.read(inventoryBackendProvider.future);

      c.read(serverContactEpochProvider.notifier).bump();
      await c.read(inventoryBackendProvider.future);

      expect(sent.calls, ['GET $status']);
    });
  });
}
