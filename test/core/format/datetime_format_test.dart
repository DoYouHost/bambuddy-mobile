import 'package:bambuddy_mobile/core/format/datetime_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixed instant used everywhere below: a PM time on a two-digit day, so a
/// 12-hour clock and a day/month swap are both visible in the output.
///
/// CLDR separates the am/pm marker with U+202F (narrow no-break space), not a
/// plain one — spelling it out here keeps a failure legible instead of showing
/// two identical-looking strings.
final _at = DateTime(2026, 8, 22, 21, 20);

DateTimeFormats _fmt({String locale = 'en_US', bool use24Hour = false}) =>
    DateTimeFormats.forTest(locale: locale, use24Hour: use24Hour);

void main() {
  group('clock', () {
    test('the system 24-hour switch wins over the locale', () {
      expect(_fmt(locale: 'en_US', use24Hour: true).time(_at), '21:20');
      expect(_fmt(locale: 'en_US').time(_at), '9:20 PM');
    });

    test('a locale that never uses am/pm reads the same either way', () {
      expect(_fmt(locale: 'pl', use24Hour: true).time(_at), '21:20');
      expect(_fmt(locale: 'pl').time(_at), '21:20');
    });

    test('midnight and noon do not collapse onto 0 or 24', () {
      final f = _fmt();
      expect(f.time(DateTime(2026, 8, 22, 0, 5)), '12:05 AM');
      expect(f.time(DateTime(2026, 8, 22, 12, 5)), '12:05 PM');
    });
  });

  group('date', () {
    test('field order follows the locale', () {
      expect(_fmt(locale: 'en_US').date(_at), '8/22/2026');
      expect(_fmt(locale: 'en_GB').date(_at), '22/08/2026');
      expect(_fmt(locale: 'pl').date(_at), '22.08.2026');
    });

    test('a named month is spelled in the locale, not just reordered', () {
      expect(_fmt(locale: 'en_US').dateNamedMonth(_at), 'Aug 22, 2026');
      expect(_fmt(locale: 'pl').dateNamedMonth(_at), '22 sie 2026');
    });

    test('the year-less forms keep their locale too', () {
      expect(_fmt(locale: 'en_US').dayNamedMonth(_at), 'Aug 22');
      expect(_fmt(locale: 'pl').dayNamedMonth(_at), '22 sie');
      expect(_fmt(locale: 'en_US').dayMonthNumeric(_at), '8/22');
      expect(_fmt(locale: 'en_GB').dayMonthNumeric(_at), '22/08');
      expect(_fmt(locale: 'en_US').monthAbbr(_at), 'Aug');
      expect(_fmt(locale: 'pl').monthAbbr(_at), 'sie');
    });

    test('a date and time together carry both settings', () {
      expect(_fmt(locale: 'en_US').dateTime(_at), '8/22/2026 9:20 PM');
      expect(
        _fmt(locale: 'en_GB', use24Hour: true).dateTime(_at),
        '22/08/2026 21:20',
      );
    });
  });

  group('clockOnDay', () {
    test('drops the date while the finish is still today', () {
      final f = _fmt(locale: 'en_US', use24Hour: true);
      expect(f.clockOnDay(_at, now: DateTime(2026, 8, 22, 20, 0)), '21:20');
    });

    test('carries the date once the finish crosses midnight', () {
      final f = _fmt(locale: 'en_US', use24Hour: true);
      expect(
        f.clockOnDay(DateTime(2026, 8, 23, 1, 20), now: _at),
        '8/23 01:20',
      );
    });

    test('a same-numbered day in another month is not "today"', () {
      final f = _fmt(locale: 'en_US', use24Hour: true);
      expect(
        f.clockOnDay(DateTime(2026, 9, 22, 21, 20), now: _at),
        '9/22 21:20',
      );
    });
  });

  test('an hour bucket is labelled the way the device reads clocks', () {
    final h24 = _fmt(locale: 'en_US', use24Hour: true);
    expect([for (final h in [0, 6, 12, 18]) h24.hourOfDay(h)],
        ['00:00', '06:00', '12:00', '18:00']);
    final h12 = _fmt(locale: 'en_US');
    expect([for (final h in [0, 6, 12, 18]) h12.hourOfDay(h)],
        ['12 AM', '6 AM', '12 PM', '6 PM']);
  });

  test('short weekdays start on Monday, as every grid here draws them', () {
    expect(_fmt(locale: 'en_US').shortWeekdaysMondayFirst,
        ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']);
    expect(_fmt(locale: 'pl').shortWeekdaysMondayFirst.first, 'pon.');
  });

  group('resolution against the platform', () {
    testWidgets('an untranslated system language falls back to the app locale',
        (tester) async {
      // German is not a language the app ships, so German month names must not
      // leak into an English UI — but the app locale still has to format.
      tester.platformDispatcher.localeTestValue = const Locale('de', 'DE');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);

      late DateTimeFormats fmt;
      await tester.pumpWidget(
        Localizations(
          locale: const Locale('en'),
          delegates: const [
            DefaultWidgetsLocalizations.delegate,
            DefaultMaterialLocalizations.delegate,
          ],
          child: Builder(builder: (context) {
            fmt = DateTimeFormats.of(context);
            return const SizedBox();
          }),
        ),
      );

      expect(fmt.dateNamedMonth(_at), 'Aug 22, 2026');
    });

    testWidgets('a translated language keeps its region', (tester) async {
      // en_GB is not in supportedLocales — the UI renders as plain `en` — yet
      // the date order is the whole point of the issue this fixes.
      tester.platformDispatcher.localeTestValue = const Locale('en', 'GB');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);

      late DateTimeFormats fmt;
      await tester.pumpWidget(
        Localizations(
          locale: const Locale('en'),
          delegates: const [
            DefaultWidgetsLocalizations.delegate,
            DefaultMaterialLocalizations.delegate,
          ],
          child: Builder(builder: (context) {
            fmt = DateTimeFormats.of(context);
            return const SizedBox();
          }),
        ),
      );

      expect(fmt.date(_at), '22/08/2026');
    });
  });
}
