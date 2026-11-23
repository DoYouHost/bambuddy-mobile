import 'dart:io';

import 'package:bambuddy_mobile/core/api/client_cert.dart';
import 'package:bambuddy_mobile/core/api/custom_ca.dart';
import 'package:bambuddy_mobile/core/api/edge_access.dart';
import 'package:bambuddy_mobile/core/api/media_auth.dart';
import 'package:bambuddy_mobile/core/api/tls_overrides.dart';
import 'package:bambuddy_mobile/core/auth/credentials_store.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_url.dart';
import 'package:bambuddy_mobile/features/gcode/gcode_viewer_screen.dart';
import 'package:flutter_test/flutter_test.dart';

// Cloudflare Access (#72) for the two stacks that are not `dart:io`: the video
// player and the G-code viewer's WebView, which never meet the HTTP client that
// adds the credential to everything else.

final _token = ServiceToken(
  host: 'printers.example.com',
  clientId: 'abc.access',
  clientSecret: 's3cret',
);

final _session = BrowserSession(
  host: 'printers.example.com',
  cookie: 'eyJ.jwt',
  expiresAt: DateTime.utc(2030),
);

const _tokenHeaders = {
  'CF-Access-Client-Id': 'abc.access',
  'CF-Access-Client-Secret': 's3cret',
};

void main() {
  tearDown(() => useTls(null, null));

  group('edgeHeadersFor', () {
    Map<String, String> of(String url) => edgeHeadersFor(Uri.parse(url));

    test('is empty while nothing is presented', () {
      expect(of('https://printers.example.com/x'), isEmpty);
    });

    test('is the token for its own host, over https', () {
      useTls(null, null, _token);
      expect(of('https://printers.example.com/x'), _tokenHeaders);
      expect(of('https://PRINTERS.example.com:8443/x'), _tokenHeaders);
    });

    test('is empty for another host, and for plain http', () {
      useTls(null, null, _token);
      expect(of('https://other.example.com/x'), isEmpty);
      expect(of('http://printers.example.com/x'), isEmpty);
    });

    test('is the cookie for a browser session', () {
      useTls(null, null, _session);
      expect(of('https://printers.example.com/x'), {
        'Cookie': 'CF_Authorization=eyJ.jwt',
      });
    });
  });

  group('the timelapse player', () {
    TimelapseSource source() => (
      url: 'https://printers.example.com/api/v1/archives/1/timelapse?token=t',
      auth: const MediaAuth(headers: {'X-API-Key': 'bb_key'}),
    );

    test('keeps the session credential and adds Cloudflare\'s', () async {
      useTls(null, null, _token);
      expect((await timelapsePlayer(source())).httpHeaders, {
        'X-API-Key': 'bb_key',
        ..._tokenHeaders,
      });
    });

    test('adds nothing when nothing is presented', () async {
      expect((await timelapsePlayer(source())).httpHeaders, {
        'X-API-Key': 'bb_key',
      });
    });

    test('adds nothing for a video on another host', () async {
      useTls(null, null, _token);
      final other = (
        url: 'https://cdn.example.net/v.mp4',
        auth: const MediaAuth(),
      );
      expect((await timelapsePlayer(other)).httpHeaders, isEmpty);
    });
  });

  group('the timelapse player behind a private CA or a client certificate', () {
    final ca = CustomCa.parse(
      'ca.pem',
      File('test/fixtures/tls/ca.pem').readAsBytesSync(),
    );
    TimelapseSource source([String host = 'printers.example.com']) => (
      url: 'https://$host/api/v1/archives/1/timelapse?token=t',
      auth: const MediaAuth(headers: {'X-API-Key': 'bb_key'}),
    );

    test('is pointed at the app\'s own loopback, with no headers', () async {
      // ExoPlayer cannot trust the CA, so the app fetches for it (NativeTlsTest).
      useTls(ca, null);
      final player = await timelapsePlayer(source());
      addTearDown(player.dispose);

      final url = Uri.parse(player.dataSource);
      expect(url.host, '127.0.0.1');
      expect(url.isScheme('http'), isTrue);
      expect(player.httpHeaders, isEmpty, reason: 'the bridge has them');
    });

    test('a client certificate alone is enough', () async {
      useTls(
        null,
        ClientCert.parse(
          'phone.p12',
          File('test/fixtures/tls/client.p12').readAsBytesSync(),
          'fixture',
        ).cert,
      );
      final player = await timelapsePlayer(source());
      addTearDown(player.dispose);
      expect(Uri.parse(player.dataSource).host, '127.0.0.1');
    });

    test('gives the listener back with the player', () async {
      useTls(ca, null);
      final player = await timelapsePlayer(source());
      final url = Uri.parse(player.dataSource);

      await player.dispose();

      await expectLater(
        HttpClient().getUrl(url).then((r) => r.close()),
        throwsA(isA<SocketException>()),
      );
    });

    test('is not used for a server that needs none of it', () async {
      final player = await timelapsePlayer(source());
      expect(Uri.parse(player.dataSource).host, 'printers.example.com');
    });

    test('nor for plain http, which a native stack reaches as it is', () async {
      useTls(ca, null);
      final player = await timelapsePlayer((
        url: 'http://printers.example.com/api/v1/archives/1/timelapse',
        auth: const MediaAuth(),
      ));
      expect(Uri.parse(player.dataSource).host, 'printers.example.com');
    });
  });

  group('the G-code viewer\'s request', () {
    const profile = ServerProfile(
      baseUrl: 'https://printers.example.com',
      authMode: AuthMode.jwt,
    );

    test('carries the login and the token', () async {
      useTls(null, null, _token);
      final store = InMemoryCredentialsStore()..jwt = 'jwt-value';
      expect(await viewerRequestHeaders(profile, store), {
        'Authorization': 'Bearer jwt-value',
        ..._tokenHeaders,
      });
    });

    test('leaves out a cookie, which fetch forbids', () async {
      useTls(null, null, _session);
      final store = InMemoryCredentialsStore()..jwt = 'jwt-value';
      expect(await viewerRequestHeaders(profile, store), {
        'Authorization': 'Bearer jwt-value',
      });
    });

    test('the address it fetches is the server\'s own, never another host', () {
      // The headers are chosen by the server's host, so the URL has to resolve
      // against it: a path, with no host of its own.
      for (final url in [
        gcodeSourceUrl(archiveId: 7, libraryFileId: null),
        gcodeSourceUrl(archiveId: 7, libraryFileId: null, plate: 2),
        gcodeSourceUrl(archiveId: null, libraryFileId: 9),
      ]) {
        final uri = Uri.parse(url);
        expect(uri.hasAuthority, isFalse, reason: url);
        expect(uri.path, startsWith('/'), reason: url);
      }
    });

    test('is only the login when nothing is presented', () async {
      final store = InMemoryCredentialsStore()..jwt = 'jwt-value';
      expect(await viewerRequestHeaders(profile, store), {
        'Authorization': 'Bearer jwt-value',
      });
    });
  });
}
