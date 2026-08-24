import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../wear_theme.dart';

/// Ask [title] and come back with a plain yes/no.
///
/// The `?? false` is the reason this wrapper exists: back-swipe is *the* way off
/// a Wear OS screen and it dismisses the dialog with `null`, so any call site
/// reading the raw result as a bool turns an accidental swipe into a yes. One
/// place to get that right instead of three.
Future<bool> wearConfirm(
  BuildContext context, {
  required IconData icon,
  required String title,
  String? subtitle,
  Color confirmColor = wearDestructive,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => WearConfirmDialog(
        icon: icon,
        title: title,
        subtitle: subtitle,
        confirmColor: confirmColor,
      ),
    ) ??
    false;

/// Full-screen confirmation in the Wear OS idiom: an icon, the question and
/// two round ✕/✓ buttons. A phone-style [AlertDialog] gets clipped by round
/// watch faces and its text buttons are poor tap targets there.
///
/// Pops `true` on confirm, `false` on cancel (back-swipe pops `null`). Prefer
/// [wearConfirm] over showing this by hand.
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
                style: WearText.hero,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: WearText.body.copyWith(color: wearMuted),
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
