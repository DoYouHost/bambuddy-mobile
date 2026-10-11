import 'package:dash_kit/dash_kit.dart';
import 'package:flutter/material.dart';

import 'dash_space.dart';

export 'package:dash_kit/dash_kit.dart';
export 'dash_space.dart';

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
