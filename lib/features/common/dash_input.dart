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
}) {
  final radius = BorderRadius.circular(14);
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: color, width: width));
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: t.subCard,
    labelText: labelText,
    hintText: hintText,
    suffixText: suffixText,
    errorText: errorText,
    helperText: helperText,
    suffixIcon: suffixIcon,
    prefixIcon: prefixIcon,
    labelStyle: TextStyle(
      fontFamily: DashTokens.fontUi,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: t.textSecondary,
    ),
    floatingLabelStyle: TextStyle(
      fontFamily: DashTokens.fontUi,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: t.accentGreenInk,
    ),
    hintStyle: TextStyle(fontFamily: DashTokens.fontUi, color: t.textTertiary),
    helperStyle: TextStyle(
      fontFamily: DashTokens.fontUi,
      fontSize: 11,
      color: t.textTertiary,
    ),
    suffixStyle: TextStyle(
      fontFamily: DashTokens.fontMono,
      fontSize: 11.5,
      color: t.textTertiary,
    ),
    border: border(t.subCardBorder),
    enabledBorder: border(t.subCardBorder),
    focusedBorder: border(t.accentGreen, 1.5),
    errorBorder: border(t.danger),
    focusedErrorBorder: border(t.danger, 1.5),
  );
}

/// The same chrome as an [InputDecorationTheme], for [DropdownMenu] — it builds
/// its own text field internally and takes no [InputDecoration].
InputDecorationTheme dashInputTheme(DashTokens t) {
  final radius = BorderRadius.circular(14);
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: color, width: width));
  return InputDecorationTheme(
    isDense: true,
    filled: true,
    fillColor: t.subCard,
    labelStyle: TextStyle(
      fontFamily: DashTokens.fontUi,
      fontSize: 13,
      color: t.textSecondary,
    ),
    border: border(t.subCardBorder),
    enabledBorder: border(t.subCardBorder),
    focusedBorder: border(t.accentGreen, 1.5),
    errorBorder: border(t.danger),
  );
}
