import 'package:material_ui/material_ui.dart';

import '../../../core/theme/dash_theme.dart';

/// Banner weight: error (server unreachable — data stale) vs info
/// (WS resuming connection, but polling data still fresh).
enum BannerTone { error, info }

/// Connection status banner — shown ABOVE last good data,
/// never instead of it.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({
    super.key,
    required this.message,
    this.tone = BannerTone.error,
    this.action,
    this.icon,
  });

  final String message;
  final BannerTone tone;

  /// The one thing to do about it, at the end of the line.
  final Widget? action;

  /// Replaces the tone's own icon, for a banner that is not about the
  /// connection.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg, toneIcon) = switch (tone) {
      BannerTone.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.cloud_off,
      ),
      BannerTone.info => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        Icons.sync,
      ),
    };
    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DashSpace.gutter,
          vertical: DashSpace.md,
        ),
        child: Row(
          children: [
            Icon(icon ?? toneIcon, size: DashIcon.md, color: fg),
            const SizedBox(width: DashSpace.sm),
            Expanded(
              child: Text(message, style: TextStyle(color: fg)),
            ),
            if (action != null) ...[
              const SizedBox(width: DashSpace.sm),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
