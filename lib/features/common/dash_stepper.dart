import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';

import '../../core/theme/dash_theme.dart';

/// − n + for a small whole number: copies, spools, runs per plate.
///
/// Each button carries a tooltip because an [IconButton] without one has no
/// accessible name — a minus and a plus beside a number say nothing on their
/// own. The log ids stay the caller's: they are wire values, and a shared
/// widget that tagged itself would report every use under one name.
///
/// [onChanged] null disables both buttons, e.g. while a request runs; each end
/// of the range disables its own.
class DashStepper extends StatelessWidget {
  const DashStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.lessTooltip,
    required this.moreTooltip,
    required this.lessId,
    required this.moreId,
    this.compact = false,
    this.valueStyle,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int>? onChanged;
  final String lessTooltip;
  final String moreTooltip;
  final String lessId;
  final String moreId;

  /// Small buttons for a stepper set inside a header, as the spool form's is.
  final bool compact;

  /// Defaults to the mono value style.
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final change = onChanged;
    Widget button(String id, String tooltip, IconData icon, int? to) =>
        IconButton(
          tooltip: tooltip,
          onPressed: change == null || to == null ? null : () => change(to),
          icon: Icon(icon, color: compact ? t.textSecondary : null),
          iconSize: compact ? 20 : null,
          visualDensity: compact ? VisualDensity.compact : null,
          constraints: compact
              ? const BoxConstraints.tightFor(width: 36, height: 36)
              : null,
          padding: compact ? EdgeInsets.zero : null,
        ).tagged(id);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(
          lessId,
          lessTooltip,
          Icons.remove,
          value > min ? value - 1 : null,
        ),
        ConstrainedBox(
          constraints: BoxConstraints(minWidth: compact ? 24 : 40),
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: valueStyle ?? (compact ? t.monoTitle : t.monoValue),
          ),
        ),
        button(moreId, moreTooltip, Icons.add, value < max ? value + 1 : null),
      ],
    );
  }
}
