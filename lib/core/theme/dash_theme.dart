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

  // The small tracked texts of a role that is not a heading. A section's heading
  // is the `SectionLabel` widget, which owns that style; the case of these two
  // stays with the caller, because case mapping depends on the locale.

  /// The caption of a tile or of a section in a sheet: `micro` in the secondary
  /// ink. Written in capitals.
  TextStyle get caption =>
      micro.copyWith(color: textSecondary, letterSpacing: DashTracking.label);

  /// The text inside a pill, in the pill's [tone].
  TextStyle pillText(Color tone) =>
      micro.copyWith(color: tone, letterSpacing: DashTracking.label);
}
