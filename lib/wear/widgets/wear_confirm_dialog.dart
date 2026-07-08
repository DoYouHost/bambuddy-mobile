import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Full-screen confirmation in the Wear OS idiom: an icon, the question and
/// two round ✕/✓ buttons. A phone-style [AlertDialog] gets clipped by round
/// watch faces and its text buttons are poor tap targets there.
///
/// Pops `true` on confirm, `false` on cancel (back-swipe pops `null`).
class WearConfirmDialog extends StatelessWidget {
  const WearConfirmDialog({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.confirmColor,
  });

  final IconData icon;
  final String title;

  /// Optional context line (e.g. the printer name) under the question.
  final String? subtitle;

  /// Accent for the icon and the confirm button — red for destructive actions.
  final Color confirmColor;

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: confirmColor, size: 30),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CircleButton(
                    icon: Icons.close_rounded,
                    background: const Color(0xFF2A2A2C),
                    tooltip: AppLocalizations.of(context).cancel,
                    onTap: () => Navigator.pop(context, false),
                  ),
                  const SizedBox(width: 20),
                  _CircleButton(
                    icon: Icons.check_rounded,
                    background: confirmColor,
                    tooltip: AppLocalizations.of(context).wearConfirm,
                    onTap: () => Navigator.pop(context, true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.background,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color background;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: background,
        foregroundColor: Colors.white,
        fixedSize: const Size(52, 52),
      ),
      icon: Icon(icon, size: 26),
    );
  }
}
