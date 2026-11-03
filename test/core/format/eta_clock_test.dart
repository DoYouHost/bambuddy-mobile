import 'package:bambuddy_mobile/core/format/datetime_format.dart';
import 'package:bambuddy_mobile/core/format/duration_format.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final noon = DateTime(2026, 11, 1, 12);
  final h24 = DateTimeFormats.forTest(locale: 'en_US', use24Hour: true);
  final h12 = DateTimeFormats.forTest(locale: 'en_US', use24Hour: false);

  test('zero minutes reads the current time', () {
    withClock(Clock.fixed(noon), () {
      expect(etaClock(h24, 0), '12:00');
    });
  });

  test('90 minutes reads one and a half hours on', () {
    withClock(Clock.fixed(noon), () {
      expect(etaClock(h24, 90), '13:30');
    });
  });

  test('a span across midnight rolls the day over', () {
    withClock(Clock.fixed(DateTime(2026, 11, 1, 23, 30)), () {
      expect(etaClock(h24, 45), '00:15');
    });
  });

  test('the 12-hour setting formats the same instant with am/pm', () {
    withClock(Clock.fixed(noon), () {
      expect(etaClock(h12, 90), h12.time(DateTime(2026, 11, 1, 13, 30)));
      expect(etaClock(h12, 90), contains('PM'));
    });
  });
}
