import 'package:bambuddy_mobile/core/api/server_reachability.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';

/// One answer about the server for the whole app: what any request found, so
/// the next screen does not spend its own connect timeout finding out again.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late ServerReachability reachability;

  setUp(() {
    dio = testDio();
    adapter = DioAdapter(dio: dio);
    reachability = ServerReachability();
    dio.interceptors.add(ReachabilityProbe(reachability));
  });

  Future<void> call() =>
      dio.get<dynamic>('/api/v1/printers/').then((_) {}, onError: (_) {});

  test('nothing tried yet is neither reachable nor not', () {
    expect(reachability.reachable.value, isNull);
  });

  test('an answer of any status is the server being there', () async {
    for (final status in [200, 403, 404, 500]) {
      reachability.forget();
      adapter.onGet('/api/v1/printers/', (s) => s.reply(status, const []));

      await call();

      expect(
        reachability.reachable.value,
        isTrue,
        reason: '$status came from the server',
      );
    }
  });

  test('a transport failure is the server not being there', () async {
    adapter.onGet(
      '/api/v1/printers/',
      (s) => s.throws(
        0,
        DioException.connectionError(
          requestOptions: RequestOptions(path: '/'),
          reason: 'offline',
        ),
      ),
    );

    await call();

    expect(reachability.reachable.value, isFalse);
  });

  test('a timeout counts as not being there', () async {
    adapter.onGet(
      '/api/v1/printers/',
      (s) => s.throws(
        0,
        DioException.connectionTimeout(
          timeout: const Duration(seconds: 8),
          requestOptions: RequestOptions(path: '/'),
        ),
      ),
    );

    await call();

    expect(reachability.reachable.value, isFalse);
  });

  test('a cancelled request says nothing either way', () async {
    // The media sheet and the printer download job both hold a CancelToken; a
    // sheet the user dismissed must not read as "the server is answering".
    reachability.reachable.value = false;
    adapter.onGet(
      '/api/v1/printers/',
      (s) => s.throws(
        0,
        DioException.requestCancelled(
          requestOptions: RequestOptions(path: '/'),
          reason: 'sheet closed',
        ),
      ),
    );

    await call();

    expect(reachability.reachable.value, isFalse);
  });

  test('a failure Dio cannot name leaves the answer alone', () async {
    reachability.reachable.value = false;
    adapter.onGet(
      '/api/v1/printers/',
      (s) => s.throws(
        0,
        DioException(
          requestOptions: RequestOptions(path: '/'),
          error: StateError('parser'),
        ),
      ),
    );

    await call();

    expect(reachability.reachable.value, isFalse);
  });

  test('a reply after a failure says the server is back', () async {
    reachability.reachable.value = false;
    adapter.onGet('/api/v1/printers/', (s) => s.reply(200, const []));

    await call();

    expect(reachability.reachable.value, isTrue);
  });

  test('listeners hear a change, and only a change', () async {
    var heard = 0;
    reachability.reachable.addListener(() => heard++);
    adapter.onGet('/api/v1/printers/', (s) => s.reply(200, const []));

    await call();
    await call();

    expect(heard, 1);
  });
}
