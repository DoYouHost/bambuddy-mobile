import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../wear_status.dart';

/// Printer state as a pill, using the same per-state palette as the phone app
/// ([WearState.color]). Tinted fill + matching border/text so the state reads
/// at a glance on the OLED black, echoing the dashboard's status chip.
class WearStatusChip extends StatelessWidget {
  const WearStatusChip({super.key, required this.state});

  final WearState state;

  @override
  Widget build(BuildContext context) {
    final color = state.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            state.label(AppLocalizations.of(context)),
            style: TextStyle(
                color: color, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
