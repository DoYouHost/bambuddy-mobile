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
