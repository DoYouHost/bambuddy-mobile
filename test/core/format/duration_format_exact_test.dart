import 'package:bambuddy_mobile/core/format/duration_format.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A span the user is setting has to read back exactly, or the control lies.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('under a minute stays in seconds', () {
    expect(formatSecondsExact(l10n, 0), '0s');
    expect(formatSecondsExact(l10n, 30), '30s');
  });

  test('a whole number of minutes reads as minutes', () {
    expect(formatSecondsExact(l10n, 60), '1min');
    expect(formatSecondsExact(l10n, 900), '15min');
    expect(formatSecondsExact(l10n, 3600), '1h');
  });

  test('a remainder is kept, which is the whole point', () {
    // formatSeconds answers "1min" to both of these, so a 30-second step moved
    // the value without moving the label.
    expect(formatSeconds(l10n, 60), formatSeconds(l10n, 90));
    expect(formatSecondsExact(l10n, 90), '1min 30s');
    expect(formatSecondsExact(l10n, 930), '15min 30s');
  });

  test('every step of a slider reads differently from its neighbours', () {
    final seen = <String>{};
    for (var s = 60; s <= 3600; s += 30) {
      expect(seen.add(formatSecondsExact(l10n, s)), isTrue, reason: '$s s');
    }
  });
}
