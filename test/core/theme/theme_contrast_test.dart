import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show HSLColor;

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
/// Measured against every surface each theme can put behind text — background
/// corners, the dialog surface, and each with a card and a sub-card stacked on
/// it — keeping the worst. The tokens are translucent and stack, so every layer
/// moves the answer, and which layer is worst flips between the two themes.
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

  /// Every surface a theme can put behind small text: each corner of the
  /// background gradient, the dialog and menu surface, and each of those with a
  /// card over it and a sub-card over the card.
  ///
  /// All of them, rather than a guess at the worst one, because the guess goes
  /// the wrong way. The intuition is that a translucent ink suffers most on the
  /// palest surface — true for the light-on-dark theme, and backwards for the
  /// dark-on-light one, where the palest card is the *kindest* thing behind
  /// grey text and the bare background corner the harshest. Measuring both ways
  /// costs nothing and does not depend on getting that right.
  List<Color> surfacesOf(DashTokens t) {
    final grounds = [...t.backgroundGradient.colors, t.overlaySurface];
    return [
      for (final ground in grounds) ...[
        ground,
        over(t.subCard, ground),
        over(t.cardGradient.colors.first, ground),
        over(t.subCard, over(t.cardGradient.colors.first, ground)),
      ],
    ];
  }

  /// The worst ratio [ink] reaches on any of them, and where.
  (double, Color) worstOf(Color ink, DashTokens t) {
    var worst = double.infinity;
    var where = const Color(0xFFFFFFFF);
    for (final surface in surfacesOf(t)) {
      final measured = ratio(over(ink, surface), surface);
      if (measured < worst) {
        worst = measured;
        where = surface;
      }
    }
    return (worst, where);
  }

  void expectReadable(String what, Color ink, DashTokens t) {
    final (measured, surface) = worstOf(ink, t);
    expect(measured, greaterThanOrEqualTo(4.5),
        reason: '$what is ${measured.toStringAsFixed(2)}:1 on '
            '${t.brightness.name}, over '
            '#${surface.toARGB32().toRadixString(16).substring(2)} — '
            'small text owes 4.5:1');
  }

  for (final t in [const DashTokens.light(), const DashTokens.dark()]) {
    final theme = t.brightness.name;

    test('$theme: the muted caption ink is readable', () {
      expectReadable('textTertiary', t.textTertiary, t);
    });

    test('$theme: the secondary ink is readable', () {
      expectReadable('textSecondary', t.textSecondary, t);
    });

    // A button's label is text, and "Cancel" in a dialog is the one every
    // screen has. The accent is ink here, never a fill — the solid green
    // swatch is `accentGreen` and is not measured against this.
    test('$theme: the accent is readable where it is a label', () {
      expectReadable('accentGreenInk', t.accentGreenInk, t);
    });

    // The warm accent is ink in the same places the green one is: a caveat's
    // mark, a "paused"/"due" pill, the star on a favourite. `accentOrange`
    // itself is the fill — a gauge, a chart slice, a chip's tint — and is not
    // measured here for the same reason `accentGreen` is not.
    test('$theme: the warm accent is readable where it is a label', () {
      expectReadable('accentOrangeInk', t.accentOrangeInk, t);
    });

    // An ink is its accent darkened, not a different colour. Contrast cannot
    // say so — it measures lightness alone, and two inks tuned to the same
    // ratio come out identical by it — so the hue is what this checks: darken
    // the warm accent far enough and it stops reading as amber and starts
    // reading as brown, which is the failure worth catching.
    test('$theme: each ink keeps the hue of the accent it darkens', () {
      void sameHue(String what, Color accent, Color ink) {
        final (a, i) = (HSLColor.fromColor(accent), HSLColor.fromColor(ink));
        expect((a.hue - i.hue).abs(), lessThan(8),
            reason: '$what drifted from ${a.hue.round()}° '
                'to ${i.hue.round()}°');
      }

      sameHue('accentGreenInk', t.accentGreen, t.accentGreenInk);
      sameHue('accentOrangeInk', t.accentOrange, t.accentOrangeInk);
    });

    // Three inks that all clear the floor still have to look like three, or the
    // fix has quietly flattened what the palette was for.
    test('$theme: the three inks stay a hierarchy', () {
      final surface = surfacesOf(t).first;
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
