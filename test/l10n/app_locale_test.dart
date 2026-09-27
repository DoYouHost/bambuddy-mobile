import 'package:bambuddy_mobile/l10n/app_locale.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every translated language resolves to itself', () {
    for (final supported in AppLocalizations.supportedLocales) {
      expect(resolveAppLocale([supported]), supported);
    }
  });

  test('a regional system locale resolves to the bare supported locale', () {
    expect(resolveAppLocale([const Locale('de', 'AT')]), const Locale('de'));
    expect(resolveAppLocale([const Locale('fr', 'CA')]), const Locale('fr'));
    expect(resolveAppLocale([const Locale('es', 'MX')]), const Locale('es'));
  });

  test('an untranslated first choice falls through to the next one', () {
    expect(
      resolveAppLocale([const Locale('it', 'IT'), const Locale('pl', 'PL')]),
      const Locale('pl'),
    );
  });

  test('an untranslated language falls back to English, not German', () {
    expect(resolveAppLocale([const Locale('it', 'IT')]), const Locale('en'));
    expect(resolveAppLocale([const Locale('cs')]), const Locale('en'));
  });

  test('no reported locale falls back to English', () {
    expect(resolveAppLocale(const []), const Locale('en'));
  });

  test('the resolved locale always has a translation to look up', () {
    expect(
      () => lookupAppLocalizations(resolveAppLocale([const Locale('ja')])),
      returnsNormally,
    );
  });
}
