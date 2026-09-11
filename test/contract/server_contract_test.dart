import 'package:bambuddy_mobile/core/api/endpoints.dart';
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
  });
}
