import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/ws_client.dart';
import '../../../core/theme/dash_text.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/theme/dash_theme.dart';
import '../ws_providers.dart';

/// Always-visible AppBar pill telling the user which lane currently feeds the
/// dashboard: live WebSocket (`connected`) or REST polling (any other state —
/// the fast 5 s fallback). Styled as the design's "Live" pill (green dot);
/// polling falls back to an amber sync pill.
class ConnectionModeChip extends ConsumerWidget {
  const ConnectionModeChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final live =
        ref.watch(wsConnectionStateProvider).valueOrNull ==
        WsConnectionState.connected;

    final accent = live ? t.accentGreen : t.accentOrange;
    final ink = live ? t.accentGreenInk : t.accentOrangeInk;
    final tooltip = live ? l10n.connLiveTooltip : l10n.connPollingTooltip;
    final label = live ? l10n.connLive : l10n.connPolling;

    return Tooltip(
      message: tooltip,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (live)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              )
            else
              Icon(Icons.sync, size: 13, color: ink),
            const SizedBox(width: 6),
            Text(label, style: t.label.copyWith(color: ink)),
          ],
        ),
      ),
    );
  }
}
