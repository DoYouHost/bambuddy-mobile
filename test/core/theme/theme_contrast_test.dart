import 'dart:math' as math;
import 'dart:ui';

import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// The muted inks against the surfaces they are read on.
///
/// Both `textSecondary` and `textTertiary` carry ordinary text — `label` and
/// `micro` are 11-12 px, and a field's hint is tertiary — so both owe WCAG AA's
/// 4.5:1, which is the threshold this file exists to hold. They used to share an
/// alpha of 0x66 and measured 2.4:1 in the light theme and 3.5:1 in the dark
/// one; nothing failed, because a colour cannot fail a widget test on its own.
///
/// Measured against the *lightest* surface each theme can put behind the text,
/// not its background: the tokens are translucent and stack (a card, then a
/// sub-card on top of it), and every layer moves the answer.
void main() {
  /// Relative luminance, per WCAG 2.1.
  double luminance(Color c) {
    double channel(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
    return 0.2126 * channel(c.r) +
        0.7152 * channel(c.g) +
        0.0722 * channel(c.b);
  }

  double ratio(Color a, Color b) {
    final (x, y) = (luminance(a), luminance(b));
    return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
  }

  /// [top] painted over [bottom], the way the framework composites it.
  Color over(Color top, Color bottom) => Color.from(
        alpha: 1,
        red: top.a * top.r + (1 - top.a) * bottom.r,
        green: top.a * top.g + (1 - top.a) * bottom.g,
        blue: top.a * top.b + (1 - top.a) * bottom.b,
      );

  /// The lightest thing a theme can put behind small text: its palest
  /// background corner, a card over that, and a sub-card over the card.
  Color worstSurface(DashTokens t) {
    final background = t.brightness == Brightness.light
        ? t.backgroundGradient.colors.last
        : t.backgroundGradient.colors.first;
    return over(t.subCard, over(t.cardGradient.colors.first, background));
  }

  void expectReadable(String what, Color ink, DashTokens t) {
    final surface = worstSurface(t);
    final measured = ratio(over(ink, surface), surface);
    expect(measured, greaterThanOrEqualTo(4.5),
        reason: '$what is ${measured.toStringAsFixed(2)}:1 on '
            '${t.brightness.name}, and small text owes 4.5:1');
  }

  for (final t in [const DashTokens.light(), const DashTokens.dark()]) {
    final theme = t.brightness.name;

    test('$theme: the muted caption ink is readable', () {
      expectReadable('textTertiary', t.textTertiary, t);
    });

    test('$theme: the secondary ink is readable', () {
      expectReadable('textSecondary', t.textSecondary, t);
    });

    // Three inks that all clear the floor still have to look like three, or the
    // fix has quietly flattened what the palette was for.
    test('$theme: the three inks stay a hierarchy', () {
      final surface = worstSurface(t);
      final steps = [
        ratio(over(t.textTertiary, surface), surface),
        ratio(over(t.textSecondary, surface), surface),
        ratio(over(t.textPrimary, surface), surface),
      ];
      expect(steps, orderedEquals(<Matcher>[
        lessThan(steps[1]),
        lessThan(steps[2]),
        anything,
      ]));
    });
  }
}
