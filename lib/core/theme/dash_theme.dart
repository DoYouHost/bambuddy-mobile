import 'dart:math' as math;

import 'package:dash_kit/dash_kit.dart';
import 'package:flutter/material.dart';
export 'package:dash_kit/dash_kit.dart';

/// Bambuddy's accent in the shared design system. `brand_contrast_test.dart`
/// holds it to `dashContrastAudit`.
const bambuddyBrand = DashBrand(
  dark: DashAccent(fill: Color(0xFF5FE08A), ink: Color(0xFF5FE08A)),
  light: DashAccent(fill: Color(0xFF34C46E), ink: Color(0xFF18733D)),
  onAccent: Color(0xFF0A0C08),
);

/// Categorical colours for a chart's series, in the order they are handed out.
/// Past the end a chart pools the rest in `textTertiary` rather than reusing a
/// colour, so two legend rows never share a dot.
const seriesPalette = [
  Color(0xFF22C55E),
  Color(0xFF3B82F6),
  Color(0xFFF59E0B),
  Color(0xFFEF4444),
  Color(0xFFA855F7),
  Color(0xFF14B8A6),
  Color(0xFFEC4899),
  Color(0xFF84CC16),
];

/// The accent under the name the screens were written with.
extension BambuddyAccent on DashTokens {
  Color get accentGreen => accent;
  Color get accentGreenInk => accentInk;

  /// [count] colours that belong to this theme, to tell [count] things apart.
  /// The first is [accent] itself. The rest take hues the web app uses for its
  /// accents — green, teal, blue, indigo, purple, orange and amber, with red left
  /// to [danger], and pink as the eighth, which it uses rarely — at the accent's
  /// own saturation and lightness, so
  /// every one reads as the same family at the same weight in either brightness.
  /// Blue, orange and amber are the theme's own ([accentBlue], [accentOrange],
  /// [warning]) so they match the rest of the app. Fewer than eight are spread
  /// over the eight; past eight the hues repeat.
  List<Color> accentSeries(int count) {
    if (count <= 0) return const [];
    final base = HSLColor.fromColor(accent);
    double hueOf(Color c) => HSLColor.fromColor(c).hue;
    final hues = [
      base.hue,
      173.0,
      hueOf(accentBlue),
      240.0,
      271.0,
      330.0,
      hueOf(accentOrange),
      hueOf(warning),
    ];
    return [
      accent,
      for (var i = 1; i < count; i++)
        base
            .withHue(
              hues[(i * hues.length ~/ math.min(count, hues.length)) %
                  hues.length],
            )
            .toColor(),
    ];
  }

  /// The card every screen in this app is built out of: gradient fill, 22 px
  /// corners, hairline border. Seventeen screens spelled it out before it had
  /// a name, which is why the two `SectionCard` classes looked like the same
  /// widget written twice — they are two headers over one box, and this is the
  /// box. A card that needs a different border (the queue's selected row)
  /// writes its own.
  BoxDecoration get cardBox => BoxDecoration(
    gradient: cardGradient,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: cardBorder),
  );
}

/// The padding of every screen's scrolling body: the gutter at the sides, [sm]
/// above, [bottom] below, plus the system navigation bar. Seven variants of it
/// were typed out by hand before; a list under a FAB passes
/// `DashSpace.fabClearance`.
EdgeInsets screenListPadding(
  BuildContext context, {
  double bottom = DashSpace.xl,
}) => withSystemNavInset(
  context,
  const EdgeInsets.fromLTRB(
    DashSpace.gutter,
    DashSpace.sm,
    DashSpace.gutter,
    0,
  ).copyWith(bottom: bottom),
);

/// The spacing scale: every padding, margin and gap in `lib/` is one of these.
///
/// A 4 dp grid. Before it existed the app had 25 distinct hand-typed values
/// and two side margins (12 and 16) that made a search bar and the card above
/// it end at different x. `spacing_scale_test.dart` refuses a numeric literal
/// where one of these belongs.
abstract final class DashSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Left and right inset of everything that meets the screen edge: cards,
  /// list tiles, search bars, banners, section headers.
  static const double gutter = lg;

  /// Bottom inset of a list under a FAB: the 56 dp button, its 16 dp margin
  /// and one [lg] of air, so the last row can scroll clear of it.
  static const double fabClearance = 88;
}
