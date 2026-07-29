import 'package:bambuddy_mobile/core/auth/auth_service.dart';
import 'package:bambuddy_mobile/features/setup/providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';

const _baseUrl = 'http://server.local:8000';

void main() {
  late DioAdapter adapter;
  late ProviderContainer container;

  setUp(() {
    final dio = Dio();
    adapter = DioAdapter(dio: dio);
    container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(
          AuthService(bareDio: dio, credentials: InMemoryCredentialsStore()),
        ),
      ],
    );
    // AutoDispose provider: keep the controller alive across the awaits.
    container.listen(setupControllerProvider, (_, _) {});
    addTearDown(container.dispose);
  });

  void mockAuthStatus(String fixture) => adapter.onGet(
        '$_baseUrl/api/v1/auth/status',
        (server) => server.reply(200, readFixture(fixture)),
      );

  group('SetupController.probe', () {
    test('auth włączony + requires_setup → formularz logowania, bez błędu',
        () async {
      // Regression: servers with auth on but no `setup_completed` row report
      // requires_setup forever, and the app used to refuse them outright.
      mockAuthStatus('auth_status_setup_pending.json');

      await container.read(setupControllerProvider.notifier).probe(_baseUrl);

      final state = container.read(setupControllerProvider);
      expect(state.error, isNull);
      expect(state.needsAuth, isTrue);
      expect(state.baseUrl, _baseUrl);
    });

    test('świeży serwer (auth off + requires_setup) → błąd konfiguracji',
        () async {
      mockAuthStatus('auth_status_fresh_server.json');

      await container.read(setupControllerProvider.notifier).probe(_baseUrl);

      final state = container.read(setupControllerProvider);
      expect(state.error, SetupErrorCode.requiresServerSetup);
      expect(state.baseUrl, isNull);
    });
  });
}
