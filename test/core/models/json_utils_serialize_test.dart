import 'package:bambuddy_mobile/core/models/json_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calendarDateToJson', () {
    test('pads to the shape the server parses', () {
      expect(calendarDateToJson(DateTime(2026, 8, 5)), '2026-08-05');
      expect(calendarDateToJson(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('keeps the day the user picked, whatever the zone', () {
      // The reason `toIso8601String`/`toUtc` cannot stand in: a local midnight
      // is the previous day in UTC for every device west of it, which is what
      // used to move a project's due date back one.
      expect(calendarDateToJson(DateTime(2026, 8, 5, 0, 0)), '2026-08-05');
      expect(calendarDateToJson(DateTime(2026, 8, 5, 23, 59)), '2026-08-05');
    });

    test('round-trips through the parser it is the inverse of', () {
      final date = DateTime(2026, 3, 7);
      expect(calendarDateFromJson(calendarDateToJson(date)), date);
    });
  });

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
