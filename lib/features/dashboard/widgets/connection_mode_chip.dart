import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/ws_client.dart';
import '../../../l10n/app_localizations.dart';
import '../ws_providers.dart';

/// Always-visible AppBar chip telling the user which lane currently feeds the
/// dashboard: live WebSocket (`connected`) or REST polling (any other state —
/// the fast 5 s fallback). Clearer than the transient reconnecting banner.
class ConnectionModeChip extends ConsumerWidget {
  const ConnectionModeChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final live =
        ref.watch(wsConnectionStateProvider).valueOrNull ==
            WsConnectionState.connected;

    final (label, tooltip, icon, bg, fg) = live
        ? (
            l10n.connLive,
            l10n.connLiveTooltip,
            Icons.bolt,
            scheme.tertiaryContainer,
            scheme.onTertiaryContainer,
          )
        : (
            l10n.connPolling,
            l10n.connPollingTooltip,
            Icons.sync,
            scheme.secondaryContainer,
            scheme.onSecondaryContainer,
          );

    return Tooltip(
      message: tooltip,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
