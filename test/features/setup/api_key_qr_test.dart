import 'package:bambuddy_mobile/features/setup/api_key_qr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
