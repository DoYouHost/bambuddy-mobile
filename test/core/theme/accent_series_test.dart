import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const themes = {
    'dark': DashTokens.dark(bambuddyBrand),
    'light': DashTokens.light(bambuddyBrand),
  };

  double hueGap(double a, double b) {
    final d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }

  for (final MapEntry(:key, :value) in themes.entries) {
    group('accentSeries ($key)', () {
      test('is empty for nothing and the accent for one', () {
        expect(value.accentSeries(0), isEmpty);
        expect(value.accentSeries(-3), isEmpty);
        expect(value.accentSeries(1), [value.accent]);
      });

      test('starts at the accent and has the length asked for', () {
        final series = value.accentSeries(8);
        expect(series, hasLength(8));
        expect(series.first, value.accent);
      });

      test('keeps the accent saturation and lightness', () {
        final base = HSLColor.fromColor(value.accent);
        for (final c in value.accentSeries(8)) {
          final hsl = HSLColor.fromColor(c);
          expect(hsl.saturation, closeTo(base.saturation, 0.02));
          expect(hsl.lightness, closeTo(base.lightness, 0.02));
        }
      });

      test('tells every colour apart and keeps clear of the danger hue', () {
        final hues = [
          for (final c in value.accentSeries(8)) HSLColor.fromColor(c).hue,
        ];
        final red = HSLColor.fromColor(value.danger).hue;
        for (var i = 0; i < hues.length; i++) {
          expect(hueGap(hues[i], red), greaterThan(20), reason: 'colour $i');
          for (var j = i + 1; j < hues.length; j++) {
            expect(hueGap(hues[i], hues[j]), greaterThan(15));
          }
        }
      });

      test('uses the theme blue, orange and amber hues', () {
        double hue(Color c) => HSLColor.fromColor(c).hue;
        final hues = [for (final c in value.accentSeries(8)) hue(c)];
        expect(hues[2], closeTo(hue(value.accentBlue), 1));
        expect(hues[6], closeTo(hue(value.accentOrange), 1));
        expect(hues[7], closeTo(hue(value.warning), 1));
      });

      test('is the same sequence in both themes', () {
        double hue(Color c) => HSLColor.fromColor(c).hue;
        final dark = themes['dark']!.accentSeries(8).map(hue).toList();
        final light = themes['light']!.accentSeries(8).map(hue).toList();
        for (var i = 0; i < 8; i++) {
          expect(hueGap(dark[i], light[i]), lessThan(8), reason: 'colour $i');
        }
      });

      test('spreads fewer than eight over the eight and repeats past them', () {
        final three = value.accentSeries(3);
        final eight = value.accentSeries(8);
        expect(three, [eight[0], eight[2], eight[5]]);
        expect(value.accentSeries(10)[8], eight[0]);
      });
    });
  }
}
