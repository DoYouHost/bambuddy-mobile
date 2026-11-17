import 'package:dash_kit/dash_kit.dart';
import 'package:material_ui/material_ui.dart';
export 'package:dash_kit/dash_kit.dart';

/// Bambuddy's accent in the shared design system. `brand_contrast_test.dart`
/// holds it to `dashContrastAudit`; the light ink is the HCT tone of the old
/// `#18733D` that also clears the accent's own wash (dash_ui v0.14.2).
const bambuddyBrand = DashBrand(
  dark: DashAccent(fill: Color(0xFF5FE08A), ink: Color(0xFF5FE08A)),
  light: DashAccent(fill: Color(0xFF34C46E), ink: Color(0xFF15713B)),
  onAccent: Color(0xFF0A0C08),
);

/// The accent under the name the screens were written with.
extension BambuddyAccent on DashTokens {
  Color get accentGreen => accent;
  Color get accentGreenInk => accentInk;

  /// A box washed in [accent] with a soft outline of it: the banners and
  /// notices that stand out from a card (merge, resume, no 3MF, locked group),
  /// and the card's accent rows. Decoration only, like [cardBox]; the layout
  /// stays with the caller.
  ///
  /// [radius] is `lg` for a banner. A row that is itself the tap target takes
  /// its own, and so must the `Material` that clips its ripple.
  BoxDecoration tintBox(Color accent, {double radius = DashRadius.lg}) =>
      BoxDecoration(
        color: accent.withValues(alpha: DashAlpha.faint),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: accent.withValues(alpha: DashAlpha.soft)),
      );

  /// [bodyBold] in the primary ink: a section heading inside a sheet, or a
  /// row's main line.
  TextStyle get bodyBoldPrimary => bodyBold.copyWith(color: textPrimary);
}
