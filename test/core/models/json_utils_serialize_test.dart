import 'package:bambuddy_mobile/core/models/json_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('instantToJson', () {
    test('is UTC, and carries no zone marker', () {
      // A trailing Z makes the bind param tz-aware, which compares against the
      // server's naive-UTC columns differently per database.
      final at = DateTime.utc(2026, 8, 5, 21, 20, 9);
      expect(instantToJson(at), '2026-08-05T21:20:09');
    });

    test('converts a local instant rather than truncating it', () {
      final local = DateTime.utc(2026, 8, 5, 21, 20, 9).toLocal();
      expect(instantToJson(local), '2026-08-05T21:20:09');
    });

    test('drops the milliseconds toIso8601String would append', () {
      final at = DateTime.utc(2026, 8, 5, 21, 20, 9, 456);
      expect(instantToJson(at), '2026-08-05T21:20:09');
    });
  });
}
