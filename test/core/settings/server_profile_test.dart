import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeBaseUrl', () {
    test('bare host gets http:// (default for LAN/self-hosted)', () {
      expect(
        ServerProfile.normalizeBaseUrl('bambu.morganmlg.com'),
        'http://bambu.morganmlg.com',
      );
    });

    test('host:port without scheme gets http://', () {
      expect(
        ServerProfile.normalizeBaseUrl('192.168.1.10:8000'),
        'http://192.168.1.10:8000',
      );
    });

    test('explicit https is preserved', () {
      expect(
        ServerProfile.normalizeBaseUrl('https://bambu.morganmlg.com'),
        'https://bambu.morganmlg.com',
      );
    });

    test('explicit http is preserved', () {
      expect(ServerProfile.normalizeBaseUrl('http://host'), 'http://host');
    });

    test('trailing slashes are stripped', () {
      expect(ServerProfile.normalizeBaseUrl('https://host/'), 'https://host');
      expect(ServerProfile.normalizeBaseUrl('https://host///'), 'https://host');
    });

    test('surrounding whitespace is trimmed', () {
      expect(
        ServerProfile.normalizeBaseUrl('  bambu.morganmlg.com  '),
        'http://bambu.morganmlg.com',
      );
    });

    test('empty stays empty (no scheme injected)', () {
      expect(ServerProfile.normalizeBaseUrl(''), '');
      expect(ServerProfile.normalizeBaseUrl('   '), '');
    });
  });

  group('baseUrlFromReached', () {
    // Regression guard for the WS bug: user types a bare host → normalized to
    // http:// → the https server redirects the probe → we must adopt the https
    // base so WS uses wss:// instead of a dead ws://.
    test('adopts the redirected https base (http→https)', () {
      final base = ServerProfile.baseUrlFromReached(
        Uri.parse('https://bambu.morganmlg.com${Endpoints.authStatus}'),
        requested: 'http://bambu.morganmlg.com',
        endpointSuffix: Endpoints.authStatus,
      );
      expect(base, 'https://bambu.morganmlg.com');
    });

    test('preserves a non-default port', () {
      final base = ServerProfile.baseUrlFromReached(
        Uri.parse('https://host:8443${Endpoints.authStatus}'),
        requested: 'http://host:8443',
        endpointSuffix: Endpoints.authStatus,
      );
      expect(base, 'https://host:8443');
    });

    test('preserves a base path prefix (reverse-proxy subpath)', () {
      final base = ServerProfile.baseUrlFromReached(
        Uri.parse('https://host/proxy${Endpoints.authStatus}'),
        requested: 'http://host/proxy',
        endpointSuffix: Endpoints.authStatus,
      );
      expect(base, 'https://host/proxy');
    });

    test('ignores query on the reached URI', () {
      final base = ServerProfile.baseUrlFromReached(
        Uri.parse('https://host${Endpoints.authStatus}?x=1'),
        requested: 'http://host',
        endpointSuffix: Endpoints.authStatus,
      );
      expect(base, 'https://host');
    });

    test('works for the /printers fallback suffix', () {
      final base = ServerProfile.baseUrlFromReached(
        Uri.parse('https://host${Endpoints.printers}'),
        requested: 'http://host',
        endpointSuffix: Endpoints.printers,
      );
      expect(base, 'https://host');
    });

    test('null reached URI → keep requested', () {
      expect(
        ServerProfile.baseUrlFromReached(
          null,
          requested: 'http://host',
          endpointSuffix: Endpoints.authStatus,
        ),
        'http://host',
      );
    });

    test('unexpected shape (suffix mismatch) → keep requested', () {
      final base = ServerProfile.baseUrlFromReached(
        Uri.parse('https://host/unexpected/path'),
        requested: 'http://host',
        endpointSuffix: Endpoints.authStatus,
      );
      expect(base, 'http://host');
    });

    test('no redirect (http answered) → keep http', () {
      final base = ServerProfile.baseUrlFromReached(
        Uri.parse('http://host${Endpoints.authStatus}'),
        requested: 'http://host',
        endpointSuffix: Endpoints.authStatus,
      );
      expect(base, 'http://host');
    });
  });

  group('displayName', () {
    test('the label wins — it is what the user called it', () {
      expect(
        const ServerProfile(
          baseUrl: 'http://192.168.1.10:8000',
          authMode: AuthMode.none,
          label: 'Workshop',
        ).displayName,
        'Workshop',
      );
    });

    test('a blank label is no label', () {
      expect(
        const ServerProfile(
          baseUrl: 'http://192.168.1.10:8000',
          authMode: AuthMode.none,
          label: '   ',
        ).displayName,
        '192.168.1.10',
      );
    });

    test('no label → the host, which is what tells two LAN servers apart', () {
      expect(
        const ServerProfile(
          baseUrl: 'http://printer.local:8000',
          authMode: AuthMode.none,
        ).displayName,
        'printer.local',
      );
    });

    test('a url with no host falls back to the url rather than to nothing', () {
      expect(
        const ServerProfile(
          baseUrl: 'garbage',
          authMode: AuthMode.none,
        ).displayName,
        'garbage',
      );
    });
  });
}
