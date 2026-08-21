import 'package:flutter/material.dart';

import '../../core/diagnostics/log_tag.dart';
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

/// The app's select field: an M3 [DropdownMenu] wearing [dashInputTheme], with
/// the menu height a phone can actually scroll and the diagnostic name on the
/// field itself.
///
/// `DropdownButtonFormField` is deliberately not used anywhere in the app — its
/// full-screen overlay is the old Material look. Rows carry their own ids: the
/// menu opens in a route of its own, so [id] never reaches them (the trap is
/// written up in docs/logging-guide.md).
///
/// [filterable] turns the field into a combo the user may type into, which is
/// also what makes it take focus — a plain select must not, or the keyboard
/// covers the list it just opened.
Widget dashCombo<T>(
  BuildContext context, {
  required String id,
  required List<DropdownMenuEntry<T>> entries,
  Key? fieldKey,
  Widget? label,
  String? helperText,
  String? errorText,
  T? initialSelection,
  TextEditingController? controller,
  bool enabled = true,
  bool filterable = false,
  double menuHeight = 320,
  TextStyle? textStyle,
  InputDecorationTheme? decorationTheme,
  ValueChanged<T?>? onSelected,
}) =>
    DropdownMenu<T>(
      key: fieldKey,
      controller: controller,
      initialSelection: initialSelection,
      enabled: enabled,
      label: label,
      helperText: helperText,
      errorText: errorText,
      expandedInsets: EdgeInsets.zero,
      menuHeight: menuHeight,
      enableFilter: filterable,
      requestFocusOnTap: filterable,
      textStyle: textStyle,
      inputDecorationTheme:
          decorationTheme ?? dashInputTheme(DashTokens.of(context)),
      onSelected: onSelected,
      dropdownMenuEntries: entries,
    ).tagged(id);
