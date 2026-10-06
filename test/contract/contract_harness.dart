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

import 'dart:convert';
import 'dart:io';

import 'package:bambuddy_mobile/core/api/api_client.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/group_write.dart';
import 'package:bambuddy_mobile/core/models/user_write.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/account_repository.dart';
import 'package:bambuddy_mobile/data/groups_repository.dart';
import 'package:bambuddy_mobile/data/users_repository.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

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

/// The stand-in printer's broker — its container, for `docker exec`, and its
/// address on the bridge, for a printer a test adds itself. Supplied by the same
/// workflow; a test that needs them skips on [brokerSkipReason].
String? get contractBrokerContainer =>
    Platform.environment['BAMBUDDY_CONTRACT_BROKER'];
String? get contractBrokerIp =>
    Platform.environment['BAMBUDDY_CONTRACT_BROKER_IP'];

String? get brokerSkipReason =>
    contractSkipReason ??
    ((contractBrokerContainer ?? '').isEmpty || (contractBrokerIp ?? '').isEmpty
        ? 'BAMBUDDY_CONTRACT_BROKER / _BROKER_IP are unset'
        : null);

/// A Spoolman the server under test can reach, as the server would address it:
/// `http://<ip>:8000` on Docker's default bridge, which resolves no names. The Spoolman tests point the server at it for
/// their own run and put the setting back after.
String? get contractSpoolmanUrl =>
    Platform.environment['BAMBUDDY_CONTRACT_SPOOLMAN_URL'];

String? get spoolmanSkipReason =>
    contractSkipReason ??
    ((contractSpoolmanUrl ?? '').isEmpty
        ? 'BAMBUDDY_CONTRACT_SPOOLMAN_URL is unset'
        : null);

/// The server under test, without a trailing slash.
String get contractBaseUrl => _baseUrl!.replaceAll(RegExp(r'/+$'), '');

/// The raw body of `POST /auth/login`, for the tests that are about that
/// answer's shape rather than about being signed in.
Future<Map<String, dynamic>> rawLogin() async {
  final dio = createBareDio()..options.baseUrl = contractBaseUrl;
  final res = await dio.post<Map<String, dynamic>>(
    Endpoints.authLogin,
    data: {'username': _username, 'password': _password},
  );
  return res.data ?? const {};
}

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

/// A signed-in non-admin, alone in a group holding exactly [permissions], for
/// a test about what such a user is offered. [admin] creates both and removes
/// them when the test — or, from `setUpAll`, the group — is over.
Future<({Dio dio, CurrentUser me})> contractUser(
  Dio admin,
  List<String> permissions,
) async {
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final group = await GroupsRepository(
    admin,
  ).create(GroupCreateInput(name: 'contract-$stamp', permissions: permissions));
  addTearDown(() => _quietly(admin.delete(Endpoints.groupById(group.id))));
  const password = 'Contract-user-1';
  final user = await UsersRepository(admin).create(
    UserCreateInput(
      username: 'contract$stamp',
      password: password,
      groupIds: [group.id],
    ),
  );
  // Registered last, so it runs first: the group goes once nobody is in it.
  addTearDown(
    () => _quietly(
      admin.delete(
        Endpoints.userById(user.id),
        queryParameters: {'delete_items': true},
      ),
    ),
  );
  final dio = createBareDio()..options.baseUrl = contractBaseUrl;
  final login = await dio.post<Map<String, dynamic>>(
    Endpoints.authLogin,
    data: {'username': user.username, 'password': password},
  );
  dio.options.headers['Authorization'] =
      'Bearer ${login.data!['access_token']}';
  return (dio: dio, me: await AccountRepository(dio).me());
}

Future<void> _quietly(Future<Object?> cleanup) async {
  try {
    await cleanup;
  } on DioException catch (_) {}
}

/// The app's providers on top of [dio], for a test that has to follow a
/// reading through the same chain a screen does rather than through one
/// repository. Disposed with the test.
ProviderContainer contractContainer(Dio dio) {
  final container = ProviderContainer(
    overrides: [
      fakeServerProfileOverride(),
      apiClientProvider.overrideWithValue(
        ApiClient(
          profile: ServerProfile(
            baseUrl: contractBaseUrl,
            authMode: AuthMode.none,
          ),
          credentials: InMemoryCredentialsStore(),
          dio: dio,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// One report from the stand-in printer, as a Bambu printer publishes it.
Future<void> publishReport(String serial, Map<String, Object?> print) async {
  final result = await Process.run('docker', [
    'exec',
    contractBrokerContainer!,
    'mosquitto_pub',
    '-h',
    'localhost',
    '-p',
    '8883',
    '--insecure',
    '--cafile',
    '/mosquitto/certs/server.crt',
    '-t',
    'device/$serial/report',
    '-m',
    jsonEncode({'print': print}),
  ]);
  if (result.exitCode != 0) {
    throw StateError('mosquitto_pub failed: ${result.stderr}');
  }
}

/// Asks [probe] every [every] until it answers non-null, for server state that
/// lands some time after the request that caused it. Throws a [StateError]
/// naming [what] once [within] has passed without an answer.
Future<T> pollUntil<T extends Object>(
  String what,
  Future<T?> Function() probe, {
  required Duration within,
  Duration every = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(within);
  while (true) {
    final answer = await probe();
    if (answer != null) return answer;
    if (!DateTime.now().isBefore(deadline)) {
      throw StateError('gave up waiting for $what after $within');
    }
    await Future<void>.delayed(every);
  }
}
