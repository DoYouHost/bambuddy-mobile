import 'package:flutter/material.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';

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

/// A field that opens a picker instead of taking typed input: the app's field
/// chrome, the current value (or a placeholder) inside it, and the affordance
/// on the right.
///
/// Written out seven times before it lived here — the spool form's empty-spool,
/// colour, preset and per-model preset fields, the mass-edit sheet's preset and
/// colour, and the AMS slot sheet's colour — and by then they had drifted: one
/// let a long value overflow instead of ellipsizing, one styled its placeholder
/// like a real value, and the clear button was spelled three different ways.
///
/// [value] null or empty means nothing is picked: [placeholder] shows in
/// tertiary ink, which is the whole of how the two are told apart. A value that
/// *is* the word "none" is still a value — pass it as [value], not as the
/// placeholder, or a deliberate "use nothing here" reads as an empty field.
///
/// [clear] adds the clear button, and only while something is picked. It is one
/// record rather than two parameters so a call site cannot give the callback
/// and forget the id: [id] and the clear button's own id both come from the
/// call site, because a shared control that tags itself reports every use under
/// the first one's name (docs/logging-guide.md).
Widget dashPickerField(
  BuildContext context, {
  required String id,
  required String label,
  required String placeholder,
  required VoidCallback onTap,
  String? value,
  String? helperText,
  Widget? leading,
  IconData? prefixIcon,
  IconData trailingIcon = Icons.arrow_drop_down,
  ({String id, VoidCallback onPressed})? clear,
  TextStyle? valueStyle,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(vertical: 6),
}) {
  final t = DashTokens.of(context);
  final l10n = AppLocalizations.of(context);
  final unset = value == null || value.isEmpty;
  return Padding(
    padding: padding,
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: InputDecorator(
        decoration: dashDecoration(
          t,
          labelText: label,
          helperText: helperText,
          prefixIcon: prefixIcon == null
              ? null
              : Icon(prefixIcon, color: t.textTertiary),
          suffixIcon: clear == null || unset
              ? Icon(trailingIcon, color: t.textTertiary)
              : IconButton(
                  icon: Icon(Icons.clear, color: t.textTertiary),
                  tooltip: l10n.clear,
                  onPressed: clear.onPressed,
                ).tagged(clear.id),
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 8)],
            Expanded(
              child: Text(
                unset ? placeholder : value,
                style: (valueStyle ?? t.body).copyWith(
                  color: unset ? t.textTertiary : t.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    ).tagged(id),
  );
}
