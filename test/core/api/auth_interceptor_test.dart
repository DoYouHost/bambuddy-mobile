import 'dart:typed_data';

import 'package:bambuddy_mobile/core/api/api_client.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Adapter HTTP rejestrujący żądania i odpowiadający wg skryptu —
/// pełna kontrola nad sekwencją 401→200 potrzebną do testu retry.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.script);

  /// Kolejne odpowiedzi; ostatnia obowiązuje dla nadmiarowych żądań.
  final List<ResponseBody Function(RequestOptions)> script;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final step = script[requests.length <= script.length
        ? requests.length - 1
        : script.length - 1];
    return step(options);
  }

  @override
  void close({bool force = false}) {}
}

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
  required _ScriptedAdapter adapter,
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

  test('AuthMode.none nie dodaje ŻADNYCH nagłówków auth', () async {
    store
      ..jwt = 'niespodziewany'
      ..apiKey = 'bb_niespodziewany';
    final adapter = _ScriptedAdapter([(_) => _json('[]', 200)]);
    final client =
        _client(mode: AuthMode.none, store: store, adapter: adapter);

    await client.dio.get<dynamic>('/api/v1/printers');

    final headers = adapter.requests.single.headers;
    expect(headers.containsKey('Authorization'), isFalse);
    expect(headers.containsKey('X-API-Key'), isFalse);
  });

  test('AuthMode.apiKey ustawia X-API-Key', () async {
    store.apiKey = 'bb_klucz';
    final adapter = _ScriptedAdapter([(_) => _json('[]', 200)]);
    final client =
        _client(mode: AuthMode.apiKey, store: store, adapter: adapter);

    await client.dio.get<dynamic>('/api/v1/printers');

    expect(adapter.requests.single.headers['X-API-Key'], 'bb_klucz');
    expect(
        adapter.requests.single.headers.containsKey('Authorization'), isFalse);
  });

  test('AuthMode.jwt ustawia Bearer', () async {
    store.jwt = 'stary-token';
    final adapter = _ScriptedAdapter([(_) => _json('[]', 200)]);
    final client =
        _client(mode: AuthMode.jwt, store: store, adapter: adapter);

    await client.dio.get<dynamic>('/api/v1/printers');

    expect(adapter.requests.single.headers['Authorization'],
        'Bearer stary-token');
  });

  test('401 przy JWT → refresh → retry z nowym tokenem', () async {
    store.jwt = 'wygasly';
    var refreshCalls = 0;
    final adapter = _ScriptedAdapter([
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

  test('401 przy JWT bez możliwości refreshu → błąd wypływa', () async {
    store.jwt = 'wygasly';
    final adapter =
        _ScriptedAdapter([(_) => _json('{"detail":"expired"}', 401)]);
    final client = _client(
      mode: AuthMode.jwt,
      store: store,
      adapter: adapter,
      refreshAuth: () async => null,
    );

    await expectLater(
      client.dio.get<dynamic>('/api/v1/printers'),
      throwsA(isA<DioException>()
          .having((e) => e.response?.statusCode, 'status', 401)),
    );
    expect(adapter.requests, hasLength(1), reason: 'bez retry bez tokenu');
  });

  test('retry po refreshu też dostaje 401 → bez pętli, błąd wypływa',
      () async {
    store.jwt = 'wygasly';
    var refreshCalls = 0;
    final adapter =
        _ScriptedAdapter([(_) => _json('{"detail":"revoked"}', 401)]);
    final client = _client(
      mode: AuthMode.jwt,
      store: store,
      adapter: adapter,
      refreshAuth: () async {
        refreshCalls++;
        return 'swiezy';
      },
    );

    await expectLater(
      client.dio.get<dynamic>('/api/v1/printers'),
      throwsA(isA<DioException>()
          .having((e) => e.response?.statusCode, 'status', 401)),
    );
    expect(refreshCalls, 1);
    expect(adapter.requests, hasLength(2));
  });

  test('401 przy kluczu API → bez refreshu, błąd wypływa', () async {
    store.apiKey = 'bb_uniewazniony';
    final adapter =
        _ScriptedAdapter([(_) => _json('{"detail":"revoked"}', 401)]);
    final client =
        _client(mode: AuthMode.apiKey, store: store, adapter: adapter);

    await expectLater(
      client.dio.get<dynamic>('/api/v1/printers'),
      throwsA(isA<DioException>()),
    );
    expect(adapter.requests, hasLength(1));
  });
}
