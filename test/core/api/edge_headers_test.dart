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

    test('keeps the session credential and adds Cloudflare\'s', () {
      useTls(null, null, _token);
      expect(timelapsePlayer(source()).httpHeaders, {
        'X-API-Key': 'bb_key',
        ..._tokenHeaders,
      });
    });

    test('adds nothing when nothing is presented', () {
      expect(timelapsePlayer(source()).httpHeaders, {'X-API-Key': 'bb_key'});
    });

    test('adds nothing for a video on another host', () {
      useTls(null, null, _token);
      final other = (
        url: 'https://cdn.example.net/v.mp4',
        auth: const MediaAuth(),
      );
      expect(timelapsePlayer(other).httpHeaders, isEmpty);
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
