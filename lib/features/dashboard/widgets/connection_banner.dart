import 'package:flutter/material.dart';

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
  });

  final String message;
  final BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg, icon) = switch (tone) {
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, style: TextStyle(color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}
