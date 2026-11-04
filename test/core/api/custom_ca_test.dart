import 'dart:convert';
import 'dart:io';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/custom_ca.dart';
import 'package:bambuddy_mobile/core/notifications/background_api.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Fixtures in test/fixtures/tls: a throwaway root CA (its key discarded) and a
// server certificate it signed for localhost and 127.0.0.1.
List<int> _fixture(String name) =>
    File('test/fixtures/tls/$name').readAsBytesSync();

void main() {
  group('parse', () {
    test('takes a PEM file', () {
      final ca = CustomCa.parse('root.pem', _fixture('ca.pem'))!;
      expect(ca.name, 'root.pem');
      expect(ca.pem, startsWith('-----BEGIN CERTIFICATE-----'));
    });

    test('takes a DER file as the same certificate', () {
      final der = CustomCa.parse('root.cer', _fixture('ca.der'))!;
      final pem = CustomCa.parse('root.pem', _fixture('ca.pem'))!;
      String body(String p) => p.replaceAll(RegExp(r'\s'), '');
      expect(body(der.pem), body(pem.pem));
    });

    test('keeps the certificate and drops a private key next to it', () {
      final bundle = [..._fixture('server.key'), ..._fixture('server.pem')];
      final ca = CustomCa.parse('bundle.pem', bundle)!;
      expect(ca.pem, isNot(contains('PRIVATE KEY')));
      expect(ca.pem, contains('BEGIN CERTIFICATE'));
    });

    test('refuses what is not a certificate', () {
      expect(CustomCa.parse('key.pem', _fixture('server.key')), isNull);
      expect(CustomCa.parse('notes.txt', utf8.encode('hello')), isNull);
      expect(CustomCa.parse('empty.crt', const []), isNull);
      expect(
        CustomCa.parse(
          'broken.pem',
          utf8.encode(
            '-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----\n',
          ),
        ),
        isNull,
      );
    });

    test('refuses a file over the cap before reading it', () {
      final pem = _fixture('ca.pem');
      final atCap = [
        ...pem,
        ...List.filled(CustomCa.maxBytes - pem.length, 10),
      ];
      expect(CustomCa.parse('root.pem', atCap), isNotNull);
      expect(CustomCa.parse('root.pem', [...atCap, 10]), isNull);
    });

    test('survives a round trip through storage', () {
      final ca = CustomCa.parse('root.pem', _fixture('ca.pem'))!;
      final back = CustomCa.fromJson(
        jsonDecode(jsonEncode(ca.toJson())) as Map<String, dynamic>,
      );
      expect((back.name, back.pem), (ca.name, ca.pem));
    });
  });

  group('trust', () {
    late HttpServer server;
    late Uri url;

    setUp(() async {
      // The test binding answers every HttpClient with a canned 400; these
      // tests need the real handshake.
      final mocked = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = mocked);
      final context = SecurityContext()
        ..useCertificateChainBytes(_fixture('server.pem'))
        ..usePrivateKeyBytes(_fixture('server.key'));
      server = await HttpServer.bindSecure('127.0.0.1', 0, context);
      server.listen(
        (r) => r.response
          ..write('ok')
          ..close(),
      );
      url = Uri.parse('https://127.0.0.1:${server.port}/');
    });

    tearDown(() async {
      trustCustomCa(null);
      await server.close(force: true);
    });

    Future<String> get() async {
      final client = HttpClient();
      try {
        final response = await (await client.getUrl(url)).close();
        return await response.transform(utf8.decoder).join();
      } finally {
        client.close(force: true);
      }
    }

    test('a server signed by a private CA is refused without it', () {
      expect(get(), throwsA(isA<HandshakeException>()));
    });

    test(
      'is reached once its CA is trusted, and refused again after',
      () async {
        trustCustomCa(CustomCa.parse('root.pem', _fixture('ca.pem')));
        expect(await get(), 'ok');
        trustCustomCa(null);
        await expectLater(get(), throwsA(isA<HandshakeException>()));
      },
    );

    test('a client made before the CA keeps distrusting', () async {
      final before = HttpClient();
      addTearDown(() => before.close(force: true));
      trustCustomCa(CustomCa.parse('root.pem', _fixture('ca.pem')));
      await expectLater(
        before.getUrl(url).then((r) => r.close()),
        throwsA(isA<HandshakeException>()),
      );
    });

    test('a background isolate trusts the CA stored in prefs', () async {
      final ca = CustomCa.parse('root.pem', _fixture('ca.pem'));
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await SettingsRepository(prefs).saveCustomCa(ca);
      await buildBackgroundApiClient(prefs);
      expect(await get(), 'ok');
    });

    test('Dio maps the refusal to the certificate error', () async {
      final dio = Dio();
      addTearDown(dio.close);
      try {
        await dio.getUri<String>(url);
        fail('the handshake should have failed');
      } on DioException catch (e) {
        expect(mapDioException(e).code, AppErrorCode.badCertificate);
      }
    });
  });

  test('plain http on an https port stays a connection error', () async {
    final mocked = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = mocked);
    final plain = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(() => plain.close(force: true));
    plain.listen((r) => r.response.close());
    final dio = Dio();
    addTearDown(dio.close);
    try {
      await dio.getUri<String>(Uri.parse('https://127.0.0.1:${plain.port}/'));
      fail('the handshake should have failed');
    } on DioException catch (e) {
      expect(e.error, isA<HandshakeException>());
      expect(mapDioException(e).code, AppErrorCode.connectionError);
    }
  });

  test('taking the CA back leaves an override that is not ours', () {
    final foreign = _Foreign();
    final mocked = HttpOverrides.current;
    HttpOverrides.global = foreign;
    addTearDown(() => HttpOverrides.global = mocked);
    trustCustomCa(null);
    expect(HttpOverrides.current, same(foreign));
  });

  test('changing the CA gives sign-in a fresh Dio', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() => trustCustomCa(null));
    final before = container.read(bareDioProvider);
    await container
        .read(customCaProvider.notifier)
        .set(CustomCa.parse('root.pem', _fixture('ca.pem')));
    expect(container.read(bareDioProvider), isNot(same(before)));
    expect(container.read(customCaProvider)?.name, 'root.pem');
  });
}

class _Foreign extends HttpOverrides {}
