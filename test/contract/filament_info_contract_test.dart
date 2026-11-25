import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/api_key.dart';
import 'package:bambuddy_mobile/data/ams_slot_config_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// `POST /cloud/filament-info`, which names the detailed slot rows. A seeded
/// server has no cloud login and no imported profiles, so the answer is the
/// built-in table: the test cross-checks it against `GET /cloud/builtin-filaments`
/// rather than pinning names the server may rename.
void main() {
  group('filament-info contract', skip: contractSkipReason, () {
    late Dio dio;
    late AmsSlotConfigRepository repo;
    late Map<String, String> builtin;

    setUpAll(() async {
      dio = await authenticatedDio();
      repo = AmsSlotConfigRepository(dio);
      builtin = {for (final f in await repo.builtinFilaments()) f.id: f.name};
    });

    test('answers every id asked and names the ones the table knows', () async {
      final known = builtin.keys.take(2).toList();
      expect(known, hasLength(2), reason: 'the built-in table is not empty');
      final asked = [...known, 'ZZ-no-such-filament'];

      final res = await dio.post<Map<String, dynamic>>(
        Endpoints.cloudFilamentInfo,
        data: asked,
        // A list body is only JSON when it says so; without it the answer is 422.
        options: Options(contentType: Headers.jsonContentType),
      );

      expect(res.statusCode, 200);
      expect(res.data!.keys, containsAll(asked));
      for (final id in known) {
        final entry = res.data![id] as Map<String, dynamic>;
        expect(entry['name'], builtin[id], reason: id);
      }
      expect(
        (res.data!['ZZ-no-such-filament'] as Map<String, dynamic>)['name'],
        '',
      );
    });

    test('the repository keeps the names and leaves the unknown out', () async {
      final known = builtin.keys.take(2).toList();

      final names = await repo.filamentNames([
        ...known,
        'ZZ-no-such-filament',
        '',
      ]);

      expect(names, {for (final id in known) id: builtin[id]});
    });

    test('an API key with the cloud scope is named like the session', () async {
      final keyed = AmsSlotConfigRepository(
        // The cloud gate passes, then the route's own scope is wanted: both.
        await contractApiKeyDio(dio, {
          ApiKeyScope.readStatus,
          ApiKeyScope.accessCloud,
        }, name: 'contract: filament-info'),
      );
      final known = builtin.keys.take(2).toList();

      expect(await keyed.filamentNames(known), {
        for (final id in known) id: builtin[id],
      });
    });

    test(
      'an API key without it is refused, and the rows go on unnamed',
      () async {
        final bare = await contractApiKeyDio(dio, {
          ApiKeyScope.readStatus,
        }, name: 'contract: filament-info bare');
        final known = builtin.keys.take(1).toList();

        final raw = await bare.post<dynamic>(
          Endpoints.cloudFilamentInfo,
          data: known,
          options: Options(validateStatus: (_) => true),
        );
        expect(raw.statusCode, 403);
        expect(
          await AmsSlotConfigRepository(bare).filamentNames(known),
          isEmpty,
        );
      },
    );
  });
}
