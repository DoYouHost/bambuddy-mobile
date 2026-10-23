import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';

import '../../core/models/calibration_option.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import 'controller_controls.dart';

/// A − / + row with the value between: plate, copies and the chamber target.
class PrintStepper extends StatelessWidget {
  const PrintStepper({
    super.key,
    required this.id,
    required this.label,
    required this.value,
    required this.onLess,
    required this.onMore,
    this.lessTooltip,
    this.moreTooltip,
  });

  final String id;
  final String label;
  final String value;
  final VoidCallback? onLess;
  final VoidCallback? onMore;
  final String? lessTooltip;
  final String? moreTooltip;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    Widget button(
      String suffix,
      IconData icon,
      VoidCallback? onTap,
      String? tip,
    ) {
      final b = logTag(
        '$id.$suffix',
        FilledButton(
          style: controllerButtonStyle(
            t,
            minimumSize: const Size.square(controllerButtonHeight),
            padding: EdgeInsets.zero,
          ),
          onPressed: onTap,
          child: Icon(icon),
        ),
      );
      return tip == null ? b : Tooltip(message: tip, child: b);
    }

    return Row(
      children: [
        button('less', Icons.remove_rounded, onLess, lessTooltip),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: t.labelSoft, maxLines: 1),
              Text(
                value,
                style: t.titleSm,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        button('more', Icons.add_rounded, onMore, moreTooltip),
      ],
    );
  }
}

/// A print option that changes by being tapped: its name, and its value at the
/// far end.
class PrintOptionRow extends StatelessWidget {
  const PrintOptionRow({
    super.key,
    required this.id,
    required this.label,
    required this.value,
    required this.onTap,
    this.on = false,
  });

  final String id;
  final String label;
  final String value;
  final bool on;

  /// Null disables the row.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final radius = BorderRadius.circular(DashSpace.md);
    return logTag(
      id,
      Material(
        color: on ? t.accent.withValues(alpha: 0.16) : t.subCard,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: on ? t.accent.withValues(alpha: 0.4) : t.subCardBorder,
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: SizedBox(
            height: printOptionHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: DashSpace.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: t.bodyPlain,
                      // Two lines where a language names the option at length.
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: DashSpace.sm),
                  Text(
                    value,
                    style: t.bodyBold.copyWith(color: on ? t.accentInk : null),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three of these and a fourth for the time fill the card on a phone.
const printOptionHeight = 48.0;

/// Auto, On, Off round again where the server can keep `auto`; On and Off where
/// it cannot, which is what the form's switch does too.
CalibrationOption nextCalibration(CalibrationOption now, bool triState) {
  if (!triState) {
    return now.asSwitch ? CalibrationOption.off : CalibrationOption.on;
  }
  return switch (now) {
    CalibrationOption.auto => CalibrationOption.on,
    CalibrationOption.on => CalibrationOption.off,
    CalibrationOption.off => CalibrationOption.auto,
  };
}

String calibrationLabel(
  AppLocalizations l10n,
  CalibrationOption value,
  bool triState,
) {
  if (!triState) return value.asSwitch ? l10n.commonOn : l10n.commonOff;
  return switch (value) {
    CalibrationOption.auto => l10n.commonAuto,
    CalibrationOption.on => l10n.commonOn,
    CalibrationOption.off => l10n.commonOff,
  };
}
