import 'package:bambuddy_mobile/core/api/api_client.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

ResponseBody _json(String body, int status) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ApiClient _client({
  required AuthMode mode,
  required InMemoryCredentialsStore store,
  required ScriptedAdapter adapter,
  Future<String?> Function()? refreshAuth,
}) {
  final dio = createBareDio()..httpClientAdapter = adapter;
  return ApiClient(
    profile: ServerProfile(baseUrl: 'http://s.local:8000', authMode: mode),
    credentials: store,
    refreshAuth: refreshAuth,
    dio: dio,
  );
}

void main() {
  late InMemoryCredentialsStore store;

  setUp(() => store = InMemoryCredentialsStore());

  test('AuthMode.none does not add ANY auth headers', () async {
    store
      ..jwt = 'unexpected'
      ..apiKey = 'bb_unexpected';
    final adapter = ScriptedAdapter.script([(_) => _json('[]', 200)]);
    final client = _client(mode: AuthMode.none, store: store, adapter: adapter);

    await client.dio.get<dynamic>('/api/v1/printers');

    final headers = adapter.requests.single.headers;
    expect(headers.containsKey('Authorization'), isFalse);
    expect(headers.containsKey('X-API-Key'), isFalse);
  });

  test('AuthMode.apiKey sets X-API-Key', () async {
    store.apiKey = 'bb_klucz';
    final adapter = ScriptedAdapter.script([(_) => _json('[]', 200)]);
    final client = _client(
      mode: AuthMode.apiKey,
      store: store,
      adapter: adapter,
    );

    await client.dio.get<dynamic>('/api/v1/printers');

    expect(adapter.requests.single.headers['X-API-Key'], 'bb_klucz');
    expect(
      adapter.requests.single.headers.containsKey('Authorization'),
      isFalse,
    );
  });

  test('AuthMode.jwt sets Bearer', () async {
    store.jwt = 'stary-token';
    final adapter = ScriptedAdapter.script([(_) => _json('[]', 200)]);
    final client = _client(mode: AuthMode.jwt, store: store, adapter: adapter);

    await client.dio.get<dynamic>('/api/v1/printers');

    expect(
      adapter.requests.single.headers['Authorization'],
      'Bearer stary-token',
    );
  });

  test('401 on JWT → refresh → retry with a new token', () async {
    store.jwt = 'wygasly';
    var refreshCalls = 0;
    final adapter = ScriptedAdapter.script([
      (_) => _json('{"detail":"expired"}', 401),
      (_) => _json('[]', 200),
    ]);
    final client = _client(
      mode: AuthMode.jwt,
      store: store,
      adapter: adapter,
      refreshAuth: () async {
        refreshCalls++;
        store.jwt = 'swiezy';
        return 'swiezy';
      },
    );

    final res = await client.dio.get<dynamic>('/api/v1/printers');

    expect(res.statusCode, 200);
    expect(refreshCalls, 1);
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests[1].headers['Authorization'], 'Bearer swiezy');
  });

  test('401 on JWT with no way to refresh → error flows out', () async {
    store.jwt = 'expired';
    final adapter = ScriptedAdapter.script([
      (_) => _json('{"detail":"expired"}', 401),
    ]);
    final client = _client(
      mode: AuthMode.jwt,
      store: store,
      adapter: adapter,
      refreshAuth: () async => null,
    );

    await expectLater(
      client.dio.get<dynamic>('/api/v1/printers'),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'status',
          401,
        ),
      ),
    );
    expect(adapter.requests, hasLength(1), reason: 'no retry without a token');
  });

  test(
    'a retry after refresh also gets 401 → no loop, error flows out',
    () async {
      store.jwt = 'expired';
      var refreshCalls = 0;
      final adapter = ScriptedAdapter.script([
        (_) => _json('{"detail":"revoked"}', 401),
      ]);
      final client = _client(
        mode: AuthMode.jwt,
        store: store,
        adapter: adapter,
        refreshAuth: () async {
          refreshCalls++;
          return 'fresh';
        },
      );

      await expectLater(
        client.dio.get<dynamic>('/api/v1/printers'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            401,
          ),
        ),
      );
      expect(refreshCalls, 1);
      expect(adapter.requests, hasLength(2));
    },
  );

  test('401 on an API key → no refresh, error flows out', () async {
    store.apiKey = 'bb_invalidated';
    final adapter = ScriptedAdapter.script([
      (_) => _json('{"detail":"revoked"}', 401),
    ]);
    final client = _client(
      mode: AuthMode.apiKey,
      store: store,
      adapter: adapter,
    );

    await expectLater(
      client.dio.get<dynamic>('/api/v1/printers'),
      throwsA(isA<DioException>()),
    );
    expect(adapter.requests, hasLength(1));
  });
}
