import 'package:flutter/material.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/theme/dash_theme.dart';

/// Unified search field for list screens (inventory, archive, …): a rounded
/// [DashTokens.subCard] pill with a leading search icon and a self-managed
/// clear button that appears once there is text.
///
/// All inner [InputDecoration] border states are nulled on purpose. The global
/// [InputDecorationTheme] defines a green, radius-14 focus border; left to the
/// default it paints a second outline *inside* the radius-20 pill (offset
/// after the icon), which reads as a UI glitch. Killing every border state
/// leaves only the pill's own border.
class DashSearchField extends StatefulWidget {
  const DashSearchField({
    super.key,
    required this.hintText,
    required this.onChanged,
    this.controller,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.id = 'search',
  });

  final String hintText;
  final ValueChanged<String> onChanged;

  /// Optional external controller; when omitted the field manages its own.
  final TextEditingController? controller;

  final bool autofocus;
  final TextCapitalization textCapitalization;

  /// Name for the diagnostic log. Typed text is never recorded — the id is all
  /// that says which screen's search this was.
  final String id;

  @override
  State<DashSearchField> createState() => _DashSearchFieldState();
}

class _DashSearchFieldState extends State<DashSearchField> {
  TextEditingController? _internal;
  TextEditingController get _controller =>
      widget.controller ?? (_internal ??= TextEditingController());

  @override
  void dispose() {
    _internal?.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return logTag(
      widget.id,
      DecoratedBox(
        decoration: BoxDecoration(
          color: t.subCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.subCardBorder),
        ),
        child: TextField(
          controller: _controller,
          autofocus: widget.autofocus,
          textCapitalization: widget.textCapitalization,
          style: TextStyle(
            fontFamily: DashTokens.fontUi,
            fontSize: 14,
            color: t.textPrimary,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: false,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            prefixIcon: Icon(Icons.search, color: t.textTertiary),
            hintText: widget.hintText,
            hintStyle:
                TextStyle(fontFamily: DashTokens.fontUi, color: t.textTertiary),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (_, value, child) =>
                  value.text.isEmpty ? const SizedBox.shrink() : child!,
              child: IconButton(
                icon: Icon(Icons.clear, color: t.textTertiary),
                onPressed: _clear,
              ),
            ),
          ),
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}
