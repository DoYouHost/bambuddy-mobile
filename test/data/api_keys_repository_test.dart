import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/api_key.dart';
import 'package:bambuddy_mobile/data/api_keys_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late ApiKeysRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = ApiKeysRepository(dio);
  });

  test('list() reads the flags as the scopes they are', () async {
    adapter.onGet(
      '/api/v1/api-keys/',
      (s) => s.reply(200, [
        {
          'id': 1,
          'name': 'Home Assistant',
          'key_prefix': 'bb_1a2b3c',
          'user_id': 4,
          'can_read_status': true,
          'can_queue': false,
          'can_control_printer': true,
          'can_manage_library': false,
          'can_manage_inventory': false,
          'can_manage_maintenance': false,
          'can_manage_archives': false,
          'can_manage_projects': false,
          'can_access_cloud': false,
          'can_update_energy_cost': true,
          'printer_ids': [2, 3],
          'enabled': true,
          'last_used': '2026-08-01T09:00:00',
          'created_at': '2026-01-01T09:00:00',
          'expires_at': null,
        },
      ]),
    );

    final key = (await repo.list()).single;
    expect(key.name, 'Home Assistant');
    expect(key.scopes, {
      ApiKeyScope.readStatus,
      ApiKeyScope.controlPrinter,
      ApiKeyScope.updateEnergyCost,
    });
    expect(key.printerIds, [2, 3]);
    expect(key.isLegacy, isFalse);
    expect(key.expiresAt, isNull);
  });

  test('a key with no owner is the legacy shape', () async {
    adapter.onGet(
      '/api/v1/api-keys/',
      (s) => s.reply(200, [
        {
          'id': 2,
          'name': 'stary skrypt',
          'key_prefix': 'bb_zzzz',
          'user_id': null,
          'can_read_status': true,
          'printer_ids': null,
          'enabled': false,
          'created_at': '2025-01-01T09:00:00',
        },
      ]),
    );

    final key = (await repo.list()).single;
    expect(key.isLegacy, isTrue);
    expect(key.enabled, isFalse);
    // Null printer_ids means every printer — an empty list would mean none.
    expect(key.printerIds, isNull);
  });

  test('an expired key is recognised without asking the server', () {
    final key = ApiKey(
      id: 3,
      name: 'wygasły',
      keyPrefix: 'bb_x',
      expiresAt: DateTime(2026, 1, 1),
    );

    expect(key.isExpired(DateTime(2026, 8, 4)), isTrue);
    expect(key.isExpired(DateTime(2025, 12, 31)), isFalse);
  });

  test('create sends every flag, not just the ticked ones', () async {
    Map<String, dynamic>? sent;
    adapter.onPost(
      '/api/v1/api-keys/',
      (s) => s.reply(200, {
        'id': 5,
        'name': 'SpoolBuddy',
        'key_prefix': 'bb_new',
        'key': 'bb_newkey_full_value',
        'user_id': 1,
        'can_read_status': true,
        'printer_ids': null,
        'enabled': true,
        'created_at': '2026-08-04T09:00:00',
      }),
      data: Matchers.any,
    );
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (options.method == 'POST') sent = options.data as Map<String, dynamic>;
      handler.next(options);
    }));

    final created = await repo.create(const ApiKeyCreateInput(
      name: 'SpoolBuddy',
      scopes: {ApiKeyScope.readStatus},
    ));

    expect(created.key, 'bb_newkey_full_value');
    expect(created.apiKey.id, 5);
    // The server's own defaults hand out queue, library, inventory,
    // maintenance, archives and projects — an omitted flag would grant more
    // than the form showed.
    expect(sent!['can_read_status'], isTrue);
    expect(sent!['can_queue'], isFalse);
    expect(sent!['can_manage_library'], isFalse);
    expect(sent!['can_manage_projects'], isFalse);
  });

  test('update sends only what changed, and can lift a printer limit',
      () async {
    Map<String, dynamic>? sent;
    adapter.onPatch(
      '/api/v1/api-keys/5',
      (s) => s.reply(200, {
        'id': 5,
        'name': 'SpoolBuddy',
        'key_prefix': 'bb_new',
        'user_id': 1,
        'can_read_status': true,
        'printer_ids': null,
        'enabled': false,
        'created_at': '2026-08-04T09:00:00',
      }),
      data: Matchers.any,
    );
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (options.method == 'PATCH') sent = options.data as Map<String, dynamic>;
      handler.next(options);
    }));

    await repo.update(
      5,
      const ApiKeyUpdateInput(enabled: false, clearPrinterIds: true),
    );

    expect(sent, {'printer_ids': null, 'enabled': false});
    expect(sent!.containsKey('can_read_status'), isFalse);
  });

  test('cloud access refused at creation keeps the server\'s reason', () async {
    adapter.onPost(
      '/api/v1/api-keys/',
      (s) => s.reply(400, {
        'detail':
            'can_access_cloud requires authentication to be enabled (per-user cloud tokens)',
      }),
      data: Matchers.any,
    );

    await expectLater(
      repo.create(const ApiKeyCreateInput(
        name: 'x',
        scopes: {ApiKeyScope.accessCloud},
      )),
      throwsA(isA<ApiException>().having(
        (e) => e.detail,
        'detail',
        contains('requires authentication to be enabled'),
      )),
    );
  });

  test('revoking hits the key\'s own path', () async {
    adapter.onDelete(
        '/api/v1/api-keys/5', (s) => s.reply(200, {'message': 'deleted'}));
    final sent = captureRequests(dio);

    await repo.delete(5);

    expect(sent.calls, ['DELETE /api/v1/api-keys/5']);
  });

  test('an identity without api_keys:read gets a mapped 403', () async {
    adapter.onGet(
      '/api/v1/api-keys/',
      (s) => s.reply(403, {'detail': 'Not enough permissions'}),
    );

    expect(repo.list(), throwsA(isA<AppApiException>()));
  });
}
