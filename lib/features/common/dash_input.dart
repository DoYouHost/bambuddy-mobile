import 'package:flutter/material.dart';

import '../../core/theme/dash_theme.dart';

/// The app's field chrome: a rounded [DashTokens.subCard] fill with a hairline
/// border, turning [DashTokens.accentGreen] on focus.
///
/// Shared rather than per-screen because a field built with Material's own
/// defaults reads as a different app the moment it sits next to one of these —
/// which is exactly what happens in a bottom sheet.
InputDecoration dashDecoration(
  DashTokens t, {
  String? labelText,
  String? hintText,
  String? suffixText,
  String? errorText,
  String? helperText,
  Widget? suffixIcon,
  Widget? prefixIcon,
}) =>
    dashFieldDecoration(
      t,
      labelText: labelText,
      hintText: hintText,
      helperText: helperText,
      errorText: errorText,
      suffixText: suffixText,
      suffixIcon: suffixIcon,
      prefixIcon: prefixIcon,
    );

/// The same chrome as an [InputDecorationTheme], for [DropdownMenu] — it builds
/// its own text field internally and takes no [InputDecoration]. Read off
/// [dashFieldDecoration] rather than restated, which is how the two drifted
/// apart the last time.
InputDecorationTheme dashInputTheme(DashTokens t) {
  final d = dashFieldDecoration(t);
  return InputDecorationTheme(
    isDense: d.isDense ?? true,
    filled: d.filled ?? true,
    fillColor: d.fillColor,
    labelStyle: d.labelStyle,
    floatingLabelStyle: d.floatingLabelStyle,
    hintStyle: d.hintStyle,
    helperStyle: d.helperStyle,
    border: d.border,
    enabledBorder: d.enabledBorder,
    focusedBorder: d.focusedBorder,
    errorBorder: d.errorBorder,
    focusedErrorBorder: d.focusedErrorBorder,
  );
}
