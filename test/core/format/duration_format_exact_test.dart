import 'package:bambuddy_mobile/core/format/duration_format.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers.dart';

/// A span the user is setting has to read back exactly, or the control lies.
void main() {
  test('under a minute stays in seconds', () {
    expect(formatSecondsExact(en, 0), '0s');
    expect(formatSecondsExact(en, 30), '30s');
  });

  test('a whole number of minutes reads as minutes', () {
    expect(formatSecondsExact(en, 60), '1min');
    expect(formatSecondsExact(en, 900), '15min');
    expect(formatSecondsExact(en, 3600), '1h');
  });

  test('a remainder is kept, which is the whole point', () {
    // formatSeconds answers "1min" to both of these, so a 30-second step moved
    // the value without moving the label.
    expect(formatSeconds(en, 60), formatSeconds(en, 90));
    expect(formatSecondsExact(en, 90), '1min 30s');
    expect(formatSecondsExact(en, 930), '15min 30s');
  });

  test('every step of a slider reads differently from its neighbours', () {
    final seen = <String>{};
    for (var s = 60; s <= 3600; s += 30) {
      expect(seen.add(formatSecondsExact(en, s)), isTrue, reason: '$s s');
    }
  });
}
