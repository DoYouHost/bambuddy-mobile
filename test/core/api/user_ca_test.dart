import 'dart:io';

import 'package:bambuddy_mobile/core/api/user_ca.dart';
import 'package:flutter_test/flutter_test.dart';

/// `test/fixtures/user_ca/`: `ca.pem` is a home CA, `server.pem` a localhost
/// certificate it signed (both valid for 100 years).
const _fixtures = 'test/fixtures/user_ca';

void main() {
  late HttpServer server;
  late Directory dir;

  setUp(() async {
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      SecurityContext()
        ..useCertificateChain('$_fixtures/server.pem')
        ..usePrivateKey('$_fixtures/server.key'),
    );
    server.listen((r) => r.response.close());
    dir = await Directory.systemTemp.createTemp('user_ca');
  });

  tearDown(() async {
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  // A raw socket: the test binding's HttpOverrides would answer an HttpClient
  // without any handshake.
  Future<void> get(SecurityContext context) async {
    final socket = await SecureSocket.connect(
      'localhost',
      server.port,
      context: context,
    );
    socket.destroy();
  }

  test('an exported CA makes its server trusted', () async {
    File('$_fixtures/ca.pem').copySync('${dir.path}/$userCaFileName');
    final context = SecurityContext(withTrustedRoots: true);
    await trustCasFrom(dir, context);
    await get(context);
  });

  test('without an export the server stays untrusted', () async {
    final context = SecurityContext(withTrustedRoots: true);
    await trustCasFrom(dir, context);
    await expectLater(get(context), throwsA(isA<HandshakeException>()));
  });

  test('a corrupt export is skipped, not thrown', () async {
    File('${dir.path}/$userCaFileName').writeAsStringSync('not a cert');
    final context = SecurityContext(withTrustedRoots: true);
    await trustCasFrom(dir, context);
    await expectLater(get(context), throwsA(isA<HandshakeException>()));
  });
}
