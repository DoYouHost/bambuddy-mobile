import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('wsUrlFor', () {
    test('https → wss with /api/v1/ws path', () {
      expect(wsUrlFor('https://bambu.morganmlg.com').toString(),
          'wss://bambu.morganmlg.com/api/v1/ws');
    });

    test('http → ws (plain local server)', () {
      expect(wsUrlFor('http://192.168.1.10:8000').toString(),
          'ws://192.168.1.10:8000/api/v1/ws');
    });

    test('preserves a non-default port', () {
      expect(wsUrlFor('https://host:8443').toString(),
          'wss://host:8443/api/v1/ws');
    });

    test('preserves a base path prefix (reverse-proxy subpath)', () {
      expect(wsUrlFor('https://host/proxy').toString(),
          'wss://host/proxy/api/v1/ws');
    });
  });
}
