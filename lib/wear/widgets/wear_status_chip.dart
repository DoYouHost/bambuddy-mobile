import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../wear_status.dart';
import '../wear_theme.dart';

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
      decoration: wearTintedBox(color),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          // Flexible, not bare: the round-safe content width on a 225 dp face is
          // 166 dp, and "Zatrzymywanie"/"Oczekiwanie na płytę" in Polish
          // overflow it — the chip drew its own striped overflow bar right where
          // Play looks for text cut off by the edge.
          Flexible(
            child: Text(
              state.label(AppLocalizations.of(context)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WearText.strong.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
