/// Shared setup for the tests that talk to a REAL bambuddy server.
///
/// Everything else under `test/` answers "does the app do the right thing with
/// the bytes we said the server sends". These answer the other half — "does the
/// server still send those bytes" — which a mocked adapter cannot, because the
/// fixtures it replays are ours. Both of the bugs that motivated this file
/// passed a fully green suite: the queue's filament colours, where the server
/// filters empty entries in one list but not its pair, and the http/https
/// redirect, which no mock ever performs.
///
/// The server is supplied by `.github/workflows/contract-tests.yml`, which
/// starts a throwaway container and seeds an admin. Without the environment
/// these tests SKIP rather than fail, so `just test` on a laptop is unaffected.
library;

import 'dart:io';

import 'package:bambuddy_mobile/core/api/api_client.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:dio/dio.dart';

/// Reason to skip, or `null` when a server was supplied. Pass straight to the
/// `skip:` argument of `group`.
String? get contractSkipReason {
  if (_baseUrl == null || _baseUrl!.isEmpty) {
    return 'BAMBUDDY_CONTRACT_URL is unset — no live server to check against';
  }
  if (_username == null || _password == null) {
    return 'BAMBUDDY_CONTRACT_USER / _PASS are unset';
  }
  return null;
}

String? get _baseUrl => Platform.environment['BAMBUDDY_CONTRACT_URL'];
String? get _username => Platform.environment['BAMBUDDY_CONTRACT_USER'];
String? get _password => Platform.environment['BAMBUDDY_CONTRACT_PASS'];

/// The server under test, without a trailing slash.
String get contractBaseUrl => _baseUrl!.replaceAll(RegExp(r'/+$'), '');

/// A Dio carrying a freshly minted JWT.
///
/// Deliberately built on [createBareDio] — the same timeouts and the same
/// `HttpProbe` the app ships with — so a contract failure is a failure of the
/// client the user actually runs, not of a test-only substitute.
Future<Dio> authenticatedDio() async {
  final dio = createBareDio()..options.baseUrl = contractBaseUrl;

  final res = await dio.post<Map<String, dynamic>>(
    Endpoints.authLogin,
    data: {'username': _username, 'password': _password},
  );

  final body = res.data;
  if (body == null) {
    throw StateError('POST ${Endpoints.authLogin} answered with no body');
  }
  // Mirrors AuthService: a 200 is not proof of a completed login — a server
  // asking for a second factor answers 200 too, without a token.
  final token = body['access_token'];
  if (token is! String || token.isEmpty) {
    throw StateError(
      'login answered 200 without access_token; keys: ${body.keys.toList()}',
    );
  }

  dio.options.headers['Authorization'] = 'Bearer $token';
  return dio;
}
