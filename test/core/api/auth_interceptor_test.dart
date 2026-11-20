import 'dart:io';

import 'package:bambuddy_mobile/core/api/api_client.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/streamed_download.dart' show postFile;
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

  // Dio lets a FormData be sent once, and the retry sends the same request
  // again. The three uploads in the app are these three shapes.
  group('401 on JWT → refresh → retry of a multipart upload', () {
    final shapes = <String, FormData Function()>{
      'fields only (timelapse process)': () =>
          FormData.fromMap({'trim_start': 0.0, 'speed': 2.0}),
      'a file from bytes (label printer)': () => FormData.fromMap({
        'files': MultipartFile.fromBytes([1, 2, 3], filename: 'label.pdf'),
      }),
    };

    for (final MapEntry(key: name, value: form) in shapes.entries) {
      test(name, () async {
        store.jwt = 'wygasly';
        final adapter = ScriptedAdapter.script([
          (_) => _json('{"detail":"expired"}', 401),
          (_) => _json('{}', 200),
        ]);
        final client = _client(
          mode: AuthMode.jwt,
          store: store,
          adapter: adapter,
          refreshAuth: () async {
            store.jwt = 'swiezy';
            return 'swiezy';
          },
        );

        final res = await client.dio.post<dynamic>(
          '/api/v1/upload',
          data: form(),
        );

        expect(res.statusCode, 200);
        expect(adapter.requests, hasLength(2));
        expect(adapter.requests[1].headers['Authorization'], 'Bearer swiezy');
      });
    }

    test('a file from disk (archive and library uploads)', () async {
      final dir = Directory.systemTemp.createTempSync('upload');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/a.3mf')..writeAsBytesSync([1, 2, 3]);
      store.jwt = 'wygasly';
      final adapter = ScriptedAdapter.script([
        (_) => _json('{"detail":"expired"}', 401),
        (_) => _json('{}', 200),
      ]);
      final client = _client(
        mode: AuthMode.jwt,
        store: store,
        adapter: adapter,
        refreshAuth: () async => 'swiezy',
      );

      final res = await postFile<dynamic>(
        client.dio,
        '/api/v1/upload',
        filePath: file.path,
        filename: 'a.3mf',
      );

      expect(res.statusCode, 200);
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests[1].headers['Authorization'], 'Bearer swiezy');
    });
  });

  // The retry carries the token the refresh returned, not whatever the store
  // holds: here the store is never updated, so reading it again would send the
  // expired one.
  test('the retry uses the token refreshAuth returned', () async {
    store.jwt = 'wygasly';
    final adapter = ScriptedAdapter.script([
      (_) => _json('{"detail":"expired"}', 401),
      (_) => _json('[]', 200),
    ]);
    final client = _client(
      mode: AuthMode.jwt,
      store: store,
      adapter: adapter,
      refreshAuth: () async => 'swiezy',
    );

    await client.dio.get<dynamic>('/api/v1/printers');

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

  group('a re-login that fails', () {
    Future<AppApiException> failure() async {
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
      try {
        await client.dio.get<dynamic>('/api/v1/printers');
      } on DioException catch (e) {
        expect(adapter.requests, hasLength(1));
        return mapDioException(e);
      }
      fail('the request succeeded');
    }

    test('without a saved login ends the session', () async {
      expect(
        await failure(),
        isA<AuthException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.unauthorized,
        ),
      );
    });

    // `silentReLogin` forgets the saved login only on a refused password or a
    // 2FA demand; anything else (429, 5xx, no network) leaves it there.
    test('with the login still saved reads as unreachable', () async {
      store
        ..username = 'anna'
        ..password = 'secret';
      expect(
        await failure(),
        isA<NetworkException>()
            .having((e) => e.code, 'code', AppErrorCode.serverUnreachable)
            .having((e) => e.path, 'path', '/api/v1/printers'),
      );
    });
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
