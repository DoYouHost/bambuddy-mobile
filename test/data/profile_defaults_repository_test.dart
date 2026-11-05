import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/profile_default.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/data/profile_defaults_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late RequestLog sent;
  var backend = InventoryBackend.native;
  late ProfileDefaultsRepository repo;

  setUp(() {
    dio = testDio();
    adapter = mockServer(dio);
    sent = captureRequests(dio);
    backend = InventoryBackend.native;
    repo = ProfileDefaultsRepository(
      dio,
      () async => backend,
      ServerVersionService(dio),
    );
  });

  void replyVersion(String version) => adapter.onGet(
    '/api/v1/updates/version',
    (s) => s.reply(200, {'version': version, 'repo': 'x/y'}),
  );

  const list = '/api/v1/inventory/profile-defaults';

  group('capability', () {
    test('the version decides before anything was seen', () async {
      replyVersion('1.2.5.6');
      expect(await repo.capability.supported, isFalse);
    });

    test('a 1.2.6 daily is offered the feature', () async {
      replyVersion('1.2.6b1-daily.20261030');
      expect(await repo.capability.supported, isTrue);
    });

    test('a 404 on the listing hides it on a server the version '
        'would have offered it to', () async {
      replyVersion('1.2.6b1');
      adapter.onGet(list, (s) => s.reply(404, {'detail': 'Not Found'}));

      expect(await repo.list(), isEmpty);
      expect(await repo.capability.supported, isFalse);
    });

    test('a 403 on the listing is a refusal, not an empty list', () async {
      replyVersion('1.2.6b1');
      adapter.onGet(list, (s) => s.reply(403, {'detail': 'Forbidden'}));

      expect(await repo.list(), isEmpty);
      expect(repo.capability.observedAnswer, isFalse);
    });

    test('a refused write leaves the read side offered', () async {
      adapter
        ..onGet(list, (s) => s.reply(200, <Object>[]))
        ..onDelete(
          '$list/3',
          (s) => s.reply(403, {'detail': 'Missing required permissions'}),
        );
      await repo.list();

      await expectLater(repo.delete(3), throwsA(isA<AppApiException>()));

      expect(repo.capability.observedAnswer, isTrue);
    });

    test('a 404 on a delete is a default that is gone, not a missing '
        'feature', () async {
      adapter
        ..onGet(list, (s) => s.reply(200, <Object>[]))
        ..onDelete('$list/9', (s) => s.reply(404, {'detail': 'gone'}));
      await repo.list();

      await expectLater(repo.delete(9), throwsA(isA<AppApiException>()));

      expect(repo.capability.observedAnswer, isTrue);
    });
  });

  group('list', () {
    test('reads every default and drops one that is not an object', () async {
      adapter.onGet(
        list,
        (s) => s.reply(200, [
          {'id': 1, 'material': 'PLA', 'brand': 'Bambu Lab'},
          'junk',
          {'id': 2, 'material': 'PETG', 'color_name': 'Red'},
        ]),
      );

      final rows = await repo.list();

      expect(rows.map((r) => r.id), [1, 2]);
      expect(rows.last.product.colorName, 'Red');
    });
  });

  group('resolve', () {
    const path = '/api/v1/inventory/profile-defaults/resolve';

    test(
      'sends the product trimmed, an empty field as an empty string',
      () async {
        adapter.onGet(path, (s) => s.reply(200, null));

        await repo.resolve(
          const ProfileProduct(material: ' PLA ', subtype: 'Basic '),
        );

        expect(sent.last.queryParameters, {
          'material': 'PLA',
          'brand': '',
          'subtype': 'Basic',
          'color_name': '',
        });
      },
    );

    test('a product with no default answers null', () async {
      adapter.onGet(path, (s) => s.reply(200, null));
      expect(await repo.resolve(const ProfileProduct(material: 'PLA')), isNull);
    });

    test('reads what a new spool starts with', () async {
      adapter.onGet(
        path,
        (s) => s.reply(200, {
          'slicer_filament': 'GFA00',
          'slicer_filament_name': 'Bambu PLA Basic',
          'presets': [
            {'printer_model': 'X1C', 'slicer_filament': 'GFA01'},
          ],
          'k_profiles': [],
          'default_ids': [4],
        }),
      );

      final r = await repo.resolve(const ProfileProduct(material: 'PLA'));

      expect(r!.slicerFilament, 'GFA00');
      expect(r.presets.single.printerModel, 'X1C');
    });

    test('a server without the route answers null and hides itself', () async {
      replyVersion('1.2.6b1');
      adapter.onGet(path, (s) => s.reply(404, {'detail': 'Not Found'}));

      expect(await repo.resolve(const ProfileProduct(material: 'PLA')), isNull);
      expect(await repo.capability.supported, isFalse);
    });

    test('a server error is thrown, not read as "no default"', () async {
      adapter.onGet(path, (s) => s.reply(500, {'detail': 'boom'}));

      await expectLater(
        repo.resolve(const ProfileProduct(material: 'PLA')),
        throwsA(isA<AppApiException>()),
      );
    });
  });

  group('save', () {
    test('PUTs the whole body and reads the stored default back', () async {
      final k = {'printer_id': 2, 'k_value': 0.02};
      final draft = ProfileDefaultDraft(
        product: const ProfileProduct(material: 'PLA', brand: 'Bambu Lab'),
        slicerFilament: 'GFA00',
        slicerFilamentName: 'Bambu PLA Basic',
        kProfiles: [k],
      );
      adapter.onPut(
        list,
        (s) => s.reply(200, {
          'id': 5,
          'material': 'PLA',
          'brand': 'Bambu Lab',
          'k_profiles': [k],
        }),
        data: draft.toJson(),
      );

      final saved = await repo.save(draft);

      expect(saved.id, 5);
      expect(sent.last.data, draft.toJson());
      expect(sent.last.data['k_profiles'], [k]);
    });

    test('a 422 reaches the caller', () async {
      adapter.onPut(
        list,
        (s) => s.reply(422, {'detail': 'Duplicate override'}),
        data: Matchers.any,
      );

      await expectLater(
        repo.save(
          const ProfileDefaultDraft(product: ProfileProduct(material: 'PLA')),
        ),
        throwsA(isA<AppApiException>()),
      );
    });
  });

  group('apply', () {
    test('the built-in inventory applies through its own route', () async {
      adapter.onPost('$list/4/apply', (s) => s.reply(200, {'updated': 3}));
      expect(await repo.apply(4), 3);
      expect(sent.calls, ['POST $list/4/apply']);
    });

    test('Spoolman mode applies through the Spoolman twin', () async {
      backend = InventoryBackend.spoolman;
      adapter.onPost(
        '/api/v1/spoolman/inventory/profile-defaults/4/apply',
        (s) => s.reply(200, {'updated': 2}),
      );
      expect(await repo.apply(4), 2);
      expect(sent.paths, [
        '/api/v1/spoolman/inventory/profile-defaults/4/apply',
      ]);
    });

    test('an answer without a count reads as zero spools', () async {
      adapter.onPost('$list/4/apply', (s) => s.reply(200, {}));
      expect(await repo.apply(4), 0);
    });
  });

  group('delete', () {
    test('DELETEs the default by id', () async {
      adapter.onDelete('$list/8', (s) => s.reply(200, {'status': 'deleted'}));
      await repo.delete(8);
      expect(sent.calls, ['DELETE $list/8']);
    });
  });
}
