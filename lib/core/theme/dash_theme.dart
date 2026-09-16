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
