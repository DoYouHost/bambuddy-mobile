import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// These assert SHAPE, not content. The server they run against is a container
/// created seconds earlier with no printers and no history, so "the list came
/// back empty" is the expected answer — what is being checked is that the
/// response decoded through the app's own models without throwing, which is the
/// failure a mocked transport is structurally unable to produce.
void main() {
  group('live server contract', skip: contractSkipReason, () {
    late Dio dio;

    setUpAll(() async {
      dio = await authenticatedDio();
    });

    test('login embeds a user the app can decode', () async {
      // AuthService reads `user` straight out of the login answer to avoid a
      // second round trip, so a change in its shape breaks sign-in before any
      // screen is reached.
      final body = await rawLogin();

      expect(
        body['user'],
        isA<Map<String, dynamic>>(),
        reason:
            'login no longer embeds `user`; AuthService would sign in '
            'with no account details and every screen keyed on them would '
            'render empty',
      );

      final user = CurrentUser.fromJson(body['user'] as Map<String, dynamic>);
      expect(user.username, isNotEmpty);
    });

    test(
      'a completed login says so twice, and the app checks the right one',
      () async {
        // AuthService tests `requires_2fa` BEFORE `access_token`, because a
        // server asking for a second factor also answers 200 — with a token-shaped
        // field that is not a session. Both halves have to keep arriving or that
        // ordering protects nothing.
        final body = await rawLogin();

        expect(
          body['requires_2fa'],
          isFalse,
          reason: 'this account was seeded without a second factor',
        );
        expect(body['access_token'], isA<String>());
      },
    );

    test('/auth/me decodes into CurrentUser', () async {
      // The same account, fetched the way the app refreshes it mid-session.
      final res = await dio.get<Map<String, dynamic>>(Endpoints.authMe);

      final body = res.data;
      expect(body, isNotNull, reason: '${Endpoints.authMe} returned no body');

      final user = CurrentUser.fromJson(body!);
      expect(user.username, isNotEmpty);
    });

    test('printer list decodes through PrintersRepository', () async {
      // The real repository, not a hand-rolled request: parseJsonList and
      // Printer.fromJson are exactly what the dashboard runs.
      final printers = await PrintersRepository(dio).fetchPrinters();

      expect(printers, isA<List<Printer>>());
    });

    test('trailing slash on /printers/ is still required', () async {
      // Endpoints.printers carries a trailing slash with a comment saying the
      // unslashed route 404s. That is a server-side routing detail we cannot
      // see from here, so it is pinned: if FastAPI starts redirecting instead,
      // this test says so before someone "tidies" the constant.
      expect(Endpoints.printers, endsWith('/'));

      final unslashed = Endpoints.printers.substring(
        0,
        Endpoints.printers.length - 1,
      );
      final res = await dio.get<dynamic>(
        unslashed,
        options: Options(validateStatus: (_) => true),
      );

      expect(
        res.statusCode,
        anyOf(404, 307),
        reason:
            'unslashed $unslashed answered ${res.statusCode}; the trailing '
            'slash in Endpoints.printers may no longer be load-bearing',
      );
    });

    test('/auth/status answers public auth flags', () async {
      // Connect flow probes auth/status to determine whether the server
      // requires authentication or initial admin setup.
      final unauthedDio = Dio(BaseOptions(baseUrl: contractBaseUrl));
      final res = await unauthedDio.get<Map<String, dynamic>>(
        Endpoints.authStatus,
      );

      expect(res.statusCode, 200);
      expect(res.data?['auth_enabled'], isA<bool>());
      expect(res.data?['requires_setup'], isA<bool>());
    });

    test('/updates/version answers unauthenticated and decodes', () async {
      // Version must be readable before authentication — ServerVersionService
      // probes this on connect to determine whether the server supports tri-state
      // calibrations and other feature flags.
      final unauthedDio = Dio(BaseOptions(baseUrl: contractBaseUrl));
      final service = ServerVersionService(unauthedDio);
      final version = await service.current();

      expect(version, isNotNull, reason: 'server version could not be parsed');
      expect(version!.raw, isNotEmpty);
      expect(await service.reportedVersion(), isNotEmpty);
    });

    test(
      'POST /auth/ws-token mints a valid websocket handshake token',
      () async {
        // The WebSocket upgrade cannot carry HTTP headers from browsers, so
        // WebSocketClient mints a short-lived token to supply in ?token=.
        final res = await dio.post<Map<String, dynamic>>(Endpoints.wsToken);

        expect(res.statusCode, 200);
        expect(res.data?['token'], isA<String>());
        expect((res.data?['token'] as String).isNotEmpty, isTrue);
      },
    );

    test('POST /auth/media-token mints a valid media token', () async {
      // Elements loading images/videos (?token=) outside of Dio use this
      // short-lived media token on newer servers.
      final res = await dio.post<Map<String, dynamic>>(Endpoints.mediaToken);

      expect(res.statusCode, 200);
      expect(res.data?['token'], isA<String>());
      expect((res.data?['token'] as String).isNotEmpty, isTrue);
    });

    test(
      'POST /printers/camera/stream-token mints a valid camera token',
      () async {
        // MJPEG camera feeds and snapshots require this stream token.
        final res = await dio.post<Map<String, dynamic>>(
          Endpoints.cameraStreamToken,
        );

        expect(res.statusCode, 200);
        expect(res.data?['token'], isA<String>());
        expect((res.data?['token'] as String).isNotEmpty, isTrue);
      },
    );
  });
}
