import 'package:flutter/material.dart';

import 'package:app_diagnostics/app_diagnostics.dart';
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
}) => dashFieldDecoration(
  t,
  labelText: labelText,
  hintText: hintText,
  helperText: helperText,
  errorText: errorText,
  suffixText: suffixText,
  suffixIcon: suffixIcon,
  prefixIcon: prefixIcon,
).copyWith(helperMaxLines: _helperLines);

/// How many lines a field's `helperText` may take. Flutter's default is one,
/// ellipsized, which cut a two-sentence hint off mid-word.
const _helperLines = 3;

/// The same chrome as an [InputDecorationTheme], for [DropdownMenu], which builds its
/// own text field. Read off [dashFieldDecoration] rather than restated.
/// `suffixIconConstraints` is deliberately absent: it boxes a select's arrow
/// ([dashCombo] applies it) (docs/ui-primitives.md, "Fields and selects").
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
    helperMaxLines: _helperLines,
    border: d.border,
    enabledBorder: d.enabledBorder,
    focusedBorder: d.focusedBorder,
    errorBorder: d.errorBorder,
    focusedErrorBorder: d.focusedErrorBorder,
  );
}

/// The app's select field: an M3 [DropdownMenu] wearing [dashInputTheme], with the
/// menu height a phone can scroll and the diagnostic name on the field itself. Every
/// select belongs here, never in a `DropdownButtonFormField`. Rows carry their own
/// ids, since the menu opens in a route of its own (docs/logging-guide.md).
/// [filterable] makes it a combo the user may type into, which is also what makes it
/// take focus (docs/ui-primitives.md, "Fields and selects").
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
}) {
  final theme = decorationTheme ?? dashInputTheme(DashTokens.of(context));
  return DropdownMenu<T>(
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
    inputDecorationTheme: theme.suffixIconConstraints == null
        ? theme.copyWith(suffixIconConstraints: _arrowBox)
        : theme,
    onSelected: onSelected,
    dropdownMenuEntries: entries,
  ).tagged(id);
}

/// How much room the menu's arrow may claim. Flutter builds it as an `IconButton`
/// with a 48x48 target, which pushes the field to 56 while every text field is 48. 40
/// is a ceiling: the button's own `Padding(all: 4)` leaves 40 + 8 in a 48-tall field.
/// The whole field is the real target (docs/ui-primitives.md, "Fields and selects").
const _arrowBox = BoxConstraints.tightFor(width: 40, height: 40);

/// A [dashCombo] whose first row means "no filter". **Null is the any-row**, so [T] is
/// bound to a non-null type and a filter's two states need no sentinel. [options]
/// pairs each value with its label; labels stay out of the diagnostic id, so the
/// any-row records as `<id>.any` and every value row as `<id>.option`
/// (docs/ui-primitives.md, "Fields and selects").
Widget dashAnyOrOne<T extends Object>(
  BuildContext context, {
  required String id,
  required String anyLabel,
  required T? selected,
  required List<(T, String)> options,
  required ValueChanged<T?> onPick,
  Widget? label,
  String? helperText,
  bool enabled = true,
  TextStyle? textStyle,
}) => dashCombo<T?>(
  context,
  id: id,
  label: label,
  helperText: helperText,
  enabled: enabled,
  textStyle: textStyle,
  initialSelection: selected,
  onSelected: onPick,
  entries: [
    DropdownMenuEntry(
      value: null,
      label: anyLabel,
      labelWidget: logTag('$id.any', Text(anyLabel)),
    ),
    for (final (value, optionLabel) in options)
      DropdownMenuEntry(
        value: value,
        label: optionLabel,
        labelWidget: logTag('$id.option', Text(optionLabel)),
      ),
  ],
);

/// A field that opens a picker instead of taking typed input: the app's field chrome,
/// the current value (or a placeholder) inside it, and the affordance on the right.
/// [value] null or empty means nothing is picked and [placeholder] shows in tertiary
/// ink; a value that *is* the word "none" is still a value. [clear] adds the clear
/// button while something is picked, as one record so a call site cannot give the
/// callback and forget the id (docs/ui-primitives.md, "Fields and selects").
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
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
    vertical: DashSpace.sm,
  ),
}) => _DashPickerField(
  id: id,
  label: label,
  placeholder: placeholder,
  onTap: onTap,
  value: value,
  helperText: helperText,
  leading: leading,
  prefixIcon: prefixIcon,
  trailingIcon: trailingIcon,
  clear: clear,
  valueStyle: valueStyle,
  padding: padding,
);

/// Stateful only to carry the focus flag: an [InputDecorator] paints the
/// theme's focused border when it is told it has focus, and it cannot tell on
/// its own — it holds no field. Without this a keyboard or switch user tabbing
/// through the form gets no border at all on the one control that is not a
/// text field.
class _DashPickerField extends StatefulWidget {
  const _DashPickerField({
    required this.id,
    required this.label,
    required this.placeholder,
    required this.onTap,
    required this.value,
    required this.helperText,
    required this.leading,
    required this.prefixIcon,
    required this.trailingIcon,
    required this.clear,
    required this.valueStyle,
    required this.padding,
  });

  final String id;
  final String label;
  final String placeholder;
  final VoidCallback onTap;
  final String? value;
  final String? helperText;
  final Widget? leading;
  final IconData? prefixIcon;
  final IconData trailingIcon;
  final ({String id, VoidCallback onPressed})? clear;
  final TextStyle? valueStyle;
  final EdgeInsetsGeometry padding;

  @override
  State<_DashPickerField> createState() => _DashPickerFieldState();
}

class _DashPickerFieldState extends State<_DashPickerField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final value = widget.value;
    final unset = value == null || value.isEmpty;
    final clear = widget.clear;
    final leading = widget.leading;
    final prefixIcon = widget.prefixIcon;
    return Padding(
      padding: widget.padding,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onTap,
        onFocusChange: (has) => setState(() => _focused = has),
        child: InputDecorator(
          isFocused: _focused,
          decoration: dashDecoration(
            t,
            labelText: widget.label,
            helperText: widget.helperText,
            prefixIcon: prefixIcon == null
                ? null
                : Icon(prefixIcon, color: t.textTertiary),
            // The clear button is a control inside a control on purpose: it is
            // the child, so it takes the taps in its own box and the field
            // takes the rest, and the two are separate nodes to a screen
            // reader — a field to open, and a button to empty it.
            suffixIcon: clear == null || unset
                ? Icon(widget.trailingIcon, color: t.textTertiary)
                : IconButton(
                    icon: Icon(Icons.clear, color: t.textTertiary),
                    tooltip: l10n.clear,
                    onPressed: clear.onPressed,
                  ).tagged(clear.id),
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading,
                const SizedBox(width: DashSpace.sm),
              ],
              Expanded(
                child: Text(
                  unset ? widget.placeholder : value,
                  style: (widget.valueStyle ?? t.body).copyWith(
                    color: unset ? t.textTertiary : t.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ).tagged(widget.id),
    );
  }
}
