import 'package:bambuddy_mobile/features/inventory/spool_scanner_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseScannedSpoolId', () {
    test('extracts spool id from bambuddy QR url (?spool=)', () {
      expect(
        parseScannedSpoolId('https://bambu.morganmlg.com/inventory?spool=24'),
        24,
      );
    });

    test('accepts a plain integer', () {
      expect(parseScannedSpoolId('42'), 42);
      expect(parseScannedSpoolId('  7 '), 7);
    });

    test('tolerates alternative query keys', () {
      expect(parseScannedSpoolId('https://x/inventory?spool_id=5'), 5);
      expect(parseScannedSpoolId('https://x/inventory?id=9'), 9);
    });

    test('falls back to a numeric path segment', () {
      expect(parseScannedSpoolId('https://x/inventory/spools/123'), 123);
    });

    test('prefers the spool query param over path/other params', () {
      expect(
        parseScannedSpoolId('https://x/inventory/spools/7?spool=24&page=2'),
        24,
      );
    });

    test('returns null for empty, non-numeric, or id-less input', () {
      expect(parseScannedSpoolId(''), isNull);
      expect(parseScannedSpoolId('   '), isNull);
      expect(parseScannedSpoolId('https://x/inventory'), isNull);
      expect(parseScannedSpoolId('hello world'), isNull);
      expect(parseScannedSpoolId('https://x/inventory?spool=0'), isNull);
      expect(parseScannedSpoolId('https://x/inventory?spool=-3'), isNull);
    });
  });
}
