import 'package:bambuddy_mobile/core/api/media_auth.dart';
import 'package:bambuddy_mobile/core/api/media_fetch.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _url = 'http://s.local:8000/api/v1/archives/7/thumbnail';

/// Answers each request with the next status in [statuses] and records the
/// credential it arrived with.
class _Server extends Interceptor {
  _Server(this.statuses);

  final List<int> statuses;
  final tokens = <String?>[];
  final keys = <String?>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    tokens.add(options.queryParameters['token'] as String?);
    keys.add(options.headers['X-API-Key'] as String?);
    final status = statuses[tokens.length - 1];
    if (status != 200) {
      return handler.reject(
        DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: status),
        ),
      );
    }
    handler.resolve(
      Response(requestOptions: options, statusCode: 200, data: <int>[1, 2, 3]),
    );
  }
}

void main() {
  late Dio dio;

  Future<List<int>?> fetch(_Server server, {int mintsBefore = 0}) {
    dio = Dio()..interceptors.add(server);
    var minted = mintsBefore;
    return mediaBytes(_url, dio, ({bool forceRefresh = false}) async {
      if (forceRefresh) minted++;
      return MediaAuth(queryToken: 'tok$minted');
    });
  }

  test('a served image comes back on the first request', () async {
    final server = _Server([200]);

    expect(await fetch(server), [1, 2, 3]);
    expect(server.tokens, ['tok0']);
  });

  test('a 401 is retried once with a freshly resolved credential', () async {
    // The background isolate never sees the widgets' recovery path, so this is
    // the only thing standing between a lapsed token and a widget stuck on the
    // last cover it managed to fetch.
    final server = _Server([401, 200]);

    expect(await fetch(server), [1, 2, 3]);
    expect(server.tokens, ['tok0', 'tok1']);
  });

  test(
    'a 403 is not retried — a fresh mint cannot grant a permission',
    () async {
      // 401 says the credential lapsed, 403 says the user may not have this row.
      // Retrying the second would double every refused request for as long as
      // the service runs, and still get a 403.
      final server = _Server([403, 200]);

      await expectLater(fetch(server), throwsA(isA<DioException>()));
      expect(server.tokens, ['tok0'], reason: 'asked once, not twice');
    },
  );

  test('a second 401 gives up rather than minting forever', () async {
    final server = _Server([401, 401]);

    await expectLater(fetch(server), throwsA(isA<DioException>()));
    expect(server.tokens, hasLength(2));
  });

  test('a header credential reaches the request as a header', () async {
    final server = _Server([200]);
    dio = Dio()..interceptors.add(server);

    await mediaBytes(
      _url,
      dio,
      ({bool forceRefresh = false}) async =>
          const MediaAuth(headers: {'X-API-Key': 'bb_key'}),
    );

    expect(server.keys, ['bb_key']);
    expect(server.tokens, [null], reason: 'nothing to put in the query');
  });
}
