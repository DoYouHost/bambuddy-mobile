import 'package:bambuddy_mobile/features/setup/api_key_qr.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors the server's own payload builder
/// (`reference/bambuddy/frontend/src/utils/apiKeyQr.ts`) so these tests fail if
/// the two ever drift apart:
///
///   `bambuddy://config?v=1&url=<encodeURIComponent(baseUrl)>&key=<encodeURIComponent(apiKey)>`
String referencePayload(String baseUrl, String apiKey, {int version = 1}) =>
    'bambuddy://config?v=$version'
    '&url=${Uri.encodeComponent(baseUrl)}'
    '&key=${Uri.encodeComponent(apiKey)}';

void main() {
  group('the server\'s payload, built the way the server builds it', () {
    test('round-trips the shapes a real deployment produces', () {
      // The web UI encodes `window.location.origin`, so whatever the admin's
      // browser was pointed at is what arrives: a LAN address with a port, or a
      // domain behind a reverse proxy.
      const cases = <String>[
        'http://192.168.1.10:8000',
        'https://bambu.example.com',
        'https://bambu.example.com:8443',
        'http://bambuddy.local',
      ];
      for (final origin in cases) {
        final cfg = parseScannedApiKey(referencePayload(origin, 'bb_abc123'));
        expect(cfg?.baseUrl, origin, reason: origin);
        expect(cfg?.apiKey, 'bb_abc123', reason: origin);
      }
    });

    test('keys with base64 padding and slashes survive the encoding', () {
      final cfg = parseScannedApiKey(
          referencePayload('https://h:8443', 'bb_ZZ/99+aa=='));
      expect(cfg?.baseUrl, 'https://h:8443');
      expect(cfg?.apiKey, 'bb_ZZ/99+aa==');
    });

    test('a future version bump still parses', () {
      final cfg = parseScannedApiKey(
          referencePayload('https://x', 'bb_future', version: 9));
      expect(cfg?.baseUrl, 'https://x');
      expect(cfg?.apiKey, 'bb_future');
    });

    test('a subpath deployment only ever gets the origin back', () {
      // Known limitation of the server side, recorded here so the app is not
      // blamed for it: the QR carries `window.location.origin`, which drops the
      // `/bambuddy` prefix a subpath reverse proxy needs. Whatever the payload
      // does carry is taken verbatim, so a hand-made code with the prefix works.
      expect(
        parseScannedApiKey(referencePayload('https://example.com', 'bb_k'))
            ?.baseUrl,
        'https://example.com',
      );
      expect(
        parseScannedApiKey(
                referencePayload('https://example.com/bambuddy', 'bb_k'))
            ?.baseUrl,
        'https://example.com/bambuddy',
      );
    });

    test('unknown extra params are ignored', () {
      final cfg = parseScannedApiKey(
          '${referencePayload('https://x', 'bb_k')}&issued=2026-07-29&name=phone');
      expect(cfg?.baseUrl, 'https://x');
      expect(cfg?.apiKey, 'bb_k');
    });

    test('a scheme in a different case is still recognized', () {
      // URI schemes are case-insensitive and some scanners hand back upper case.
      final cfg = parseScannedApiKey(
          'BAMBUDDY://config?v=1&url=https%3A%2F%2Fx&key=bb_k');
      expect(cfg?.apiKey, 'bb_k');
      expect(cfg?.baseUrl, 'https://x');
    });

    test('a payload with no key at all is refused, url or not', () {
      expect(parseScannedApiKey('bambuddy://config?v=1&url=https%3A%2F%2Fx'),
          isNull);
      expect(
        parseScannedApiKey('bambuddy://config?v=1&url=https%3A%2F%2Fx&key='),
        isNull,
      );
    });

    test('an unrelated code is refused instead of becoming the key', () {
      // Anything scannable ends up in front of this parser. A link with no key
      // in it must come back empty, or the key field silently fills with a
      // Wi-Fi string and the server answers "key rejected".
      for (final payload in [
        'https://example.com/products/12345',
        'WIFI:S:MyNetwork;T=WPA;P=hunter2;;',
        'http://192.168.1.10:8000',
        'mailto:someone@example.com?subject=hi',
        'bambuddy://config?v=1',
      ]) {
        expect(parseScannedApiKey(payload), isNull, reason: payload);
      }
    });
  });

  group('parseScannedApiKey', () {
    test('decodes the combined bambuddy://config payload (url + key)', () {
      final cfg = parseScannedApiKey(
        'bambuddy://config?v=1&url=https%3A%2F%2Fprinter.local&key=bb_abc123',
      );
      expect(cfg?.baseUrl, 'https://printer.local');
      expect(cfg?.apiKey, 'bb_abc123');
    });

    test('round-trips a key with url-encoded special characters', () {
      final cfg = parseScannedApiKey(
        'bambuddy://config?v=1&url=https%3A%2F%2Fh%3A8443&key=bb_ZZ%2F99%2Baa%3D%3D',
      );
      expect(cfg?.baseUrl, 'https://h:8443');
      expect(cfg?.apiKey, 'bb_ZZ/99+aa==');
    });

    test('ignores the version so a bumped payload still parses', () {
      final cfg = parseScannedApiKey(
        'bambuddy://config?v=9&url=https%3A%2F%2Fx&key=bb_future',
      );
      expect(cfg?.baseUrl, 'https://x');
      expect(cfg?.apiKey, 'bb_future');
    });

    test('accepts a key-only query param (no url)', () {
      final cfg = parseScannedApiKey('https://host/setup?api_key=bb_xyz');
      expect(cfg?.baseUrl, isNull);
      expect(cfg?.apiKey, 'bb_xyz');
    });

    test('accepts a bare bb_ key', () {
      final cfg = parseScannedApiKey('  bb_abc123DEF ');
      expect(cfg?.baseUrl, isNull);
      expect(cfg?.apiKey, 'bb_abc123DEF');
    });

    test('pulls a bb_ token out of surrounding text', () {
      final cfg = parseScannedApiKey('API key: bb_token-value_1 (keep secret)');
      expect(cfg?.apiKey, 'bb_token-value_1');
    });

    test('accepts a non-bb single token (custom key formats)', () {
      expect(parseScannedApiKey('CUSTOMKEY123')?.apiKey, 'CUSTOMKEY123');
    });

    test('returns null for empty or prose without a key token', () {
      expect(parseScannedApiKey(''), isNull);
      expect(parseScannedApiKey('   '), isNull);
      expect(parseScannedApiKey('please enter your key'), isNull);
    });
  });
}
