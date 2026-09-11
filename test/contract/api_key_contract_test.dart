import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/api_key.dart';
import 'package:bambuddy_mobile/data/api_keys_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// What an API key may and may not do, measured rather than assumed.
///
/// This is the question the app answers most often and most invisibly: the
/// connect screen recommends a key, so every feature gated behind something a
/// key cannot do is a feature that silently is not there for most installs.
/// The verdict is taken per surface, not per route — a key that can read all of
/// something but write none of it still makes a usable read-only screen — and
/// the whole judgement rests on the two facts pinned first below.
///
/// Keys are minted through the real [ApiKeysRepository], so the request body
/// the app builds is part of what is under test.
void main() {
  group('API key contract', skip: contractSkipReason, () {
    late Dio dio;
    late ApiKeysRepository keys;
    final minted = <int>[];

    Future<CreatedApiKey> mint(String name, Set<ApiKeyScope> scopes) async {
      final created = await keys.create(
        ApiKeyCreateInput(name: name, scopes: scopes),
      );
      minted.add(created.apiKey.id);
      return created;
    }

    /// A client that authenticates the way a key-configured app does: the
    /// `X-API-Key` header and no bearer token at all.
    Dio clientFor(String key) => Dio(BaseOptions(baseUrl: contractBaseUrl))
      ..options.headers['X-API-Key'] = key
      ..options.validateStatus = (_) => true;

    setUpAll(() async {
      dio = await authenticatedDio();
      keys = ApiKeysRepository(dio);
    });

    tearDownAll(() async {
      for (final id in minted) {
        await dio.delete<dynamic>(
          Endpoints.apiKeyById(id),
          options: Options(validateStatus: (_) => true),
        );
      }
    });

    test('a key reads settings', () async {
      // The half that makes read-only surfaces worth building. If this ever
      // became a refusal, every screen that merely displays a server setting
      // would have to be gated away for key-configured installs.
      final created = await mint('contract probe: read', {
        ApiKeyScope.readStatus,
      });
      final res = await clientFor(
        created.key,
      ).get<dynamic>(Endpoints.appSettings);

      expect(
        res.statusCode,
        200,
        reason:
            'GET ${Endpoints.appSettings} with a key answered '
            '${res.statusCode}; read-only settings surfaces are no longer '
            'reachable for the connection the app recommends',
      );
    });

    test('a key cannot write settings, and is refused with 403', () async {
      // The other half, and the reason every settings write in the app demands
      // a password login. The status code is load-bearing on its own: the app
      // quotes the server's `detail` back to the user only on a 403, so a
      // refusal arriving as 401 or 405 would degrade to a generic message.
      final created = await mint('contract probe: write', {
        ApiKeyScope.readStatus,
      });
      final res = await clientFor(
        created.key,
      ).put<dynamic>(Endpoints.appSettingsUpdate, data: {'auto_archive': true});

      expect(
        res.statusCode,
        403,
        reason:
            'PUT ${Endpoints.appSettingsUpdate} with a key answered '
            '${res.statusCode}, not 403 — either keys may now write settings, '
            'or the refusal changed shape and the app will stop quoting it',
      );
      expect(res.data.toString(), contains('administrative'));
    });

    test('scopes gate the one narrow door into settings', () async {
      // ApiKeyScope.updateEnergyCost carries a doc comment calling this "the one
      // narrow door into settings". The app does not walk through it — there is
      // no Endpoints constant for the route — so this pins the claim rather than
      // a user path, and keeps that comment from going quietly stale.
      const route = '${Endpoints.apiPrefix}/settings/electricity-price';
      const body = {'energy_cost_per_kwh': 0.85};

      final withScope = await mint('contract probe: energy yes', {
        ApiKeyScope.readStatus,
        ApiKeyScope.updateEnergyCost,
      });
      final allowed = await clientFor(
        withScope.key,
      ).post<dynamic>(route, data: body);
      expect(
        allowed.statusCode,
        200,
        reason: 'a key holding updateEnergyCost was refused at $route',
      );

      final withoutScope = await mint('contract probe: energy no', {
        ApiKeyScope.readStatus,
      });
      final refused = await clientFor(
        withoutScope.key,
      ).post<dynamic>(route, data: body);
      expect(
        refused.statusCode,
        403,
        reason:
            'a key without updateEnergyCost reached $route; the scope no '
            'longer gates anything',
      );
    });

    test('the mint response decodes through CreatedApiKey', () async {
      // POST /api-keys/ is the only answer that ever carries the key itself,
      // and there is no route that returns it again — so a shape change here
      // costs the user the key, not a retry.
      final created = await mint('contract probe: shape', {
        ApiKeyScope.readStatus,
        ApiKeyScope.queue,
      });

      expect(created.key, isNotEmpty, reason: 'no plaintext key in the answer');
      expect(created.apiKey.id, greaterThan(0));
      expect(created.apiKey.keyPrefix, isNotEmpty);
      expect(created.apiKey.scopes, contains(ApiKeyScope.readStatus));
      expect(
        created.apiKey.scopes,
        isNot(contains(ApiKeyScope.controlPrinter)),
        reason:
            'a flag the app sent as false came back set; ApiKeyCreateInput '
            'sends every flag explicitly precisely because the server defaults '
            'are generous',
      );
    });
  });
}
