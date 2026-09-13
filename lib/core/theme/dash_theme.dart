import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:dash_ui/dash_ui.dart' hide dashAppBar;
import 'package:dash_ui/dash_ui.dart' as dash show dashAppBar;
import 'package:flutter/material.dart';

export 'package:dash_ui/dash_ui.dart' hide dashAppBar;

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
}

/// Names a hand-built [AppBar] for the diagnostic log without restyling it.
///
/// Screens that cannot use [dashAppBar] (the camera, the G-code viewer, the QR
/// scanner — all dark by design) still get a framework-built back button, and
/// that button is unreachable by a tag of its own. Wrapping the whole bar names
/// it by inheritance. The bar's own [AppBar.preferredSize] is kept, so a bar
/// with a `bottom:` is not clipped.
PreferredSizeWidget loggedAppBar(AppBar bar) => PreferredSize(
  preferredSize: bar.preferredSize,
  child: logTag('chrome.appbar', bar),
);

/// The shared app bar, named `chrome.appbar` for the diagnostic log through
/// [loggedAppBar].
PreferredSizeWidget dashAppBar(
  BuildContext context, {
  required String title,
  List<Widget>? actions,
  Widget? leading,
  PreferredSizeWidget? bottom,
  bool automaticallyImplyLeading = true,
}) => loggedAppBar(
  dash.dashAppBar(
    context,
    title: title,
    actions: actions,
    leading: leading,
    bottom: bottom,
    automaticallyImplyLeading: automaticallyImplyLeading,
  ),
);

/// The confirming action of a form's [dashAppBar] — "Save", "Create".
///
/// The green ink is the app theme's [TextButtonThemeData] default, so nothing
/// here restates it. What the call sites did share is the [busy] latch: while a
/// submit is in flight the button goes dead, which is the only thing stopping a
/// second tap from posting the form twice.
Widget dashSaveAction({
  required String id,
  required String label,
  required bool busy,
  required VoidCallback onPressed,
}) => TextButton(
  onPressed: busy ? null : onPressed,
  child: Text(label),
).tagged(id);
