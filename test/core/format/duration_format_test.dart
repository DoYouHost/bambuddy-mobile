import 'package:bambuddy_mobile/core/format/duration_format.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The wording lives in the .arb files, so the assertions read it from there
  // rather than restating it — a translator changing "min" must not fail these.
  final en = lookupAppLocalizations(const Locale('en'));
  final pl = lookupAppLocalizations(const Locale('pl'));

  group('from minutes', () {
    test('under an hour is minutes alone', () {
      expect(formatMinutes(en, 45), '45min');
      expect(formatMinutes(en, 0), '0min');
    });

    test('over an hour splits, with the units against their numbers', () {
      expect(formatMinutes(en, 83), '1h 23min');
      expect(formatMinutes(en, 137), '2h 17min');
    });

    test('a whole hour drops the zero minutes', () {
      expect(formatMinutes(en, 60), '1h');
      expect(formatMinutes(en, 120), '2h');
    });

    test('both languages spell a span the same way', () {
      // `h` and `min` are the abbreviations in either, so the two must not
      // drift apart the way the old hand-rolled formatters had.
      expect(formatMinutes(pl, 83), formatMinutes(en, 83));
    });
  });

  group('from seconds', () {
    test('under a minute stays in seconds', () {
      // A print that died on the first layer must not read as having taken
      // no time at all.
      expect(formatSeconds(en, 30), '30s');
      expect(formatSeconds(en, 0), '0s');
    });

    test('a minute or more reads like the minute form', () {
      expect(formatSeconds(en, 60), '1min');
      expect(formatSeconds(en, 4980), '1h 23min');
      expect(formatSeconds(en, 34260), '9h 31min');
    });

    test('a stray second does not round the span up', () {
      expect(formatSeconds(en, 119), '1min');
    });
  });
}
