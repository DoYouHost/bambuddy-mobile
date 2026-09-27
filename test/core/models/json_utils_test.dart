import 'package:bambuddy_mobile/core/models/json_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dateTimeFromJson', () {
    // Values taken from real 0.2.5b2 server responses.
    test('with a Z suffix: a UTC instant, handed back in local time', () {
      final d = dateTimeFromJson('2026-07-30T16:00:00Z')!;

      expect(d.isUtc, isFalse, reason: 'consumers format the fields directly');
      expect(d.toUtc().hour, 16);
      expect(
        d.millisecondsSinceEpoch,
        DateTime.utc(2026, 7, 30, 16).millisecondsSinceEpoch,
      );
    });

    test('no zone means UTC, not local time', () {
      // The second bug: the server keeps UTC in naive columns and only some
      // schemas append the Z. Dart read that as local, so every archive date and
      // every statistics bucket was off by the device's offset.
      final naive = dateTimeFromJson('2026-07-29T06:15:10.233878')!;
      final explicit = dateTimeFromJson('2026-07-29T06:15:10.233878Z')!;

      expect(
        naive,
        explicit,
        reason:
            'both spellings are the same instant — the server is '
            'inconsistent in format, not in meaning',
      );
      expect(naive.toUtc().hour, 6);
    });

    test('an offset and a Z at once — the malformed PATCH answer', () {
      // serialize_utc_datetime appends Z to a value that already carries +00:00.
      // DateTime.tryParse answers null for it, silently losing the time.
      expect(
        DateTime.tryParse('2026-07-30T16:00:00+00:00Z'),
        isNull,
        reason: 'if Dart swallowed this, the tolerance would be unnecessary',
      );

      final d = dateTimeFromJson('2026-07-30T16:00:00+00:00Z')!;
      expect(d, dateTimeFromJson('2026-07-30T16:00:00Z'));
    });

    test('a real offset is respected', () {
      expect(
        dateTimeFromJson('2026-07-30T18:00:00+02:00'),
        dateTimeFromJson('2026-07-30T16:00:00Z'),
      );
    });

    test('absent, junk and non-strings → null, never a throw', () {
      for (final junk in [null, '', '   ', 'wczoraj', 42, <String>[], {}]) {
        expect(dateTimeFromJson(junk), isNull, reason: 'input: $junk');
      }
    });

    test('a bare date with no time of day gets no zone', () {
      // There is no time of day here, so appending a Z would be a guess; the value
      // stays a calendar date.
      final d = dateTimeFromJson('2026-07-30')!;
      expect([d.year, d.month, d.day], [2026, 7, 30]);
    });
  });
}
