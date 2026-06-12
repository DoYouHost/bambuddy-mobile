import 'package:flutter/material.dart';

/// Waga banera: błąd (serwer nieosiągalny — dane nieaktualne) vs informacja
/// (WS wznawia połączenie, ale dane z pollingu są nadal aktualne).
enum BannerTone { error, info }

/// Baner stanu połączenia — pokazywany NAD ostatnimi dobrymi danymi,
/// nigdy zamiast nich.
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
            Expanded(child: Text(message, style: TextStyle(color: fg))),
          ],
        ),
      ),
    );
  }
}
