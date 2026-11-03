import 'package:bambuddy_mobile/features/common/speed_name.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  test('names each of the four known levels', () {
    expect(speedName(l10n, 1), l10n.speedSilent);
    expect(speedName(l10n, 2), l10n.speedStandard);
    expect(speedName(l10n, 3), l10n.speedSport);
    expect(speedName(l10n, 4), l10n.speedLudicrous);
  });

  test('returns null for a level the printer does not have', () {
    expect(speedName(l10n, 0), isNull);
    expect(speedName(l10n, 5), isNull);
    expect(speedName(l10n, -1), isNull);
  });

  test('returns null for no level', () {
    expect(speedName(l10n, null), isNull);
  });
}
