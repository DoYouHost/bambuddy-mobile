import 'package:bambuddy_mobile/core/format/datetime_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixed instant used everywhere below: a PM time on a two-digit day, so a
/// 12-hour clock and a day/month swap are both visible in the output.
///
/// The am/pm marker is preceded by a plain space here because the 12-hour clock
/// is built from an explicit `h:mm a` pattern. Skeletons like `jm` use U+202F
/// (narrow no-break space) instead, so an expectation copied from one of those
/// fails against two strings that look identical on screen.
final _at = DateTime(2026, 8, 22, 21, 20);

DateTimeFormats _fmt({String locale = 'en_US', bool use24Hour = false}) =>
    DateTimeFormats.forTest(locale: locale, use24Hour: use24Hour);

void main() {
  group('clock', () {
    test('the system 24-hour switch wins over the locale', () {
      expect(_fmt(locale: 'en_US', use24Hour: true).time(_at), '21:20');
      expect(_fmt(locale: 'en_US').time(_at), '9:20 PM');
    });

    test('a 24-hour locale still honours a hand-picked 12-hour clock', () {
      // Deferring to the locale here would silently ignore the setting.
      expect(_fmt(locale: 'pl', use24Hour: true).time(_at), '21:20');
      expect(_fmt(locale: 'pl').time(_at), '9:20 PM');
    });

    test('thin am/pm markers are replaced, not shown', () {
      // intl gives pl the single letters a/p; `9:20 p` reads as a typo, and
      // Android itself shows AM/PM there.
      expect(_fmt(locale: 'pl').time(_at), contains('PM'));
      // A locale with usable markers of its own keeps them.
      expect(_fmt(locale: 'en_GB').time(_at), '9:20 pm');
      expect(_fmt(locale: 'en_CA').time(_at), '9:20 p.m.');
    });

    test('an unreadable switch follows the locale, not a 12-hour default', () {
      // The foreground service's engine is never told what the switch says, and
      // its Dart-side default is "12-hour" — which is how a phone set to 24 got
      // `ETA 8:29 PM` in its print notification.
      expect(DateTimeFormats.forTest(locale: 'pl').time(_at), '21:20');
      expect(DateTimeFormats.forTest(locale: 'en_GB').time(_at), '21:20');
      expect(DateTimeFormats.forTest(locale: 'de_DE').time(_at), '21:20');
      // A 12-hour locale still gets a 12-hour clock, marker and all.
      expect(DateTimeFormats.forTest(locale: 'en_US').time(_at), '9:20 PM');
      expect(DateTimeFormats.forTest(locale: 'en_CA').time(_at), '9:20 p.m.');
    });

    test('the hour cycle comes off the region, the markers off the language', () {
      // A Polish app on a US phone: the device's convention decides the clock,
      // and the marker is borrowed from English because intl gives pl `a`/`p`.
      final f = DateTimeFormats.forTest(locale: 'en_US', wordLocale: 'pl');
      expect(f.time(_at), '9:20 PM');
    });

    test('midnight and noon do not collapse onto 0 or 24', () {
      final f = _fmt();
      expect(f.time(DateTime(2026, 8, 22, 0, 5)), '12:05 AM');
      expect(f.time(DateTime(2026, 8, 22, 12, 5)), '12:05 PM');
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
      expect(_fmt(locale: 'en_US').dateTime(_at), '8/22/2026 9:20 PM');
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
    expect(
      [
        for (final h in [0, 6, 12, 18]) h24.hourOfDay(h),
      ],
      ['00:00', '06:00', '12:00', '18:00'],
    );
    final h12 = _fmt(locale: 'en_US');
    expect(
      [
        for (final h in [0, 6, 12, 18]) h12.hourOfDay(h),
      ],
      ['12:00 AM', '6:00 AM', '12:00 PM', '6:00 PM'],
    );
    // A 24-hour locale forced to 12h reads the axis the same way.
    expect(_fmt(locale: 'pl').hourOfDay(6), '6:00 AM');
  });

  test('short weekdays start on Monday, as every grid here draws them', () {
    expect(_fmt(locale: 'en_US').shortWeekdaysMondayFirst, [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ]);
    expect(_fmt(locale: 'pl').shortWeekdaysMondayFirst.first, 'pon.');
  });

  group('the clock a bare isolate resolves', () {
    /// What `DateTimeFormats.system()` would spell with that answer, on a locale
    /// whose own convention is the opposite of a hardcoded 12-hour clock.
    /// `system()` itself cannot be steered from a test — it reads
    /// `PlatformDispatcher.instance`, the process-wide singleton, which ignores
    /// the values a widget test sets on its own dispatcher.
    String spelled(bool? clock, {String locale = 'de_DE'}) =>
        DateTimeFormats.forTest(locale: locale, use24Hour: clock).time(_at);

    test('a dispatcher false is a non-answer, not a 12-hour clock', () {
      // The foreground service runs a bare FlutterEngine, which is never sent
      // the user settings and leaves the flag at its Dart-side default. Reading
      // that as "12-hour" is how a phone set to 24 got `ETA 8:29 PM` in its
      // print notification — the bug this whole rule exists for.
      final clock = DateTimeFormats.isolateClock(
        remembered: null,
        dispatcherSays: false,
      );

      expect(clock, isNull, reason: 'nobody has said — ask the locale');
      expect(spelled(clock), '21:20');
      expect(
        spelled(clock, locale: 'en_US'),
        '9:20 PM',
        reason: 'a 12-hour locale still reads 12-hour',
      );
    });

    test('a dispatcher true is real and is taken', () {
      // Nothing but the setting itself produces one, so it needs no corroboration.
      expect(
        DateTimeFormats.isolateClock(remembered: null, dispatcherSays: true),
        isTrue,
      );
    });

    test('a published 12-hour clock beats the locale that disagrees', () {
      // The case a 24-hour locale makes easy to lose: someone on a de_DE phone
      // who went and picked 12-hour by hand. Once the tree has published it,
      // falling back to the locale would overrule them.
      final clock = DateTimeFormats.isolateClock(
        remembered: false,
        dispatcherSays: false,
      );

      expect(clock, isFalse);
      expect(spelled(clock), '9:20 PM');
    });

    test('what was published outranks whatever the dispatcher says', () {
      // Either way round: the tree has seen the real setting, the dispatcher of
      // a bare engine has not.
      expect(
        DateTimeFormats.isolateClock(remembered: false, dispatcherSays: true),
        isFalse,
      );
      expect(
        DateTimeFormats.isolateClock(remembered: true, dispatcherSays: false),
        isTrue,
      );
    });
  });

  group('resolution against the platform', () {
    testWidgets('an untranslated system language falls back to the app locale', (
      tester,
    ) async {
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
          child: Builder(
            builder: (context) {
              fmt = DateTimeFormats.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(fmt.dateNamedMonth(_at), 'Aug 22, 2026');
      // The digits still follow the device: `5/8/2026` would read as a
      // different day to the person holding a German phone.
      expect(fmt.date(_at), '22.8.2026');
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
          child: Builder(
            builder: (context) {
              fmt = DateTimeFormats.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(fmt.date(_at), '22/08/2026');
    });
  });
}
