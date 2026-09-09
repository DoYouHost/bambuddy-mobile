import 'package:flutter/material.dart';

import 'package:app_diagnostics/app_diagnostics.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';

/// A row on a hub screen: an icon in a green tile, a title, a line saying what
/// is behind it, and a chevron.
///
/// The app has two hubs — administration and server settings — and one of them
/// is an entry on the other, so the row had to stop being private to a screen.
class SettingsEntryTile extends StatelessWidget {
  const SettingsEntryTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.id,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Name for the diagnostic log — the visible label is localized and is not
  /// recorded.
  final String id;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: logTag(
          id,
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: t.cardGradient,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: t.cardBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.accentGreen.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, size: 21, color: t.accentGreenInk),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: t.titleMd),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: t.labelSoft.copyWith(color: t.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: t.textTertiary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
