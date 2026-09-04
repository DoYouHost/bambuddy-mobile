import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../wear_geometry.dart';
import '../wear_theme.dart';
import 'wear_scroll_view.dart';

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
        // Centred while it fits, scrolling when it doesn't: a long question with
        // a printer name under it is taller than the round-safe band on a small
        // face, and a confirmation nobody can reach the buttons of is worse than
        // an ugly one.
        child: WearScrollView(
          centerWhenShort: true,
          // An icon, a question and two round buttons: narrow, and taller than
          // the rectangle a full-width screen is allowed. Trading the width it
          // does not use for the height it does buys most of what is needed.
          contentWidthFraction: wearNarrowWidthFraction,
          // The rest is bought by pinning the answer: on a 192 dp face the
          // question alone fills the viewport, and a confirmation whose buttons
          // are a scroll away is one nobody can refuse in a hurry.
          footer: _Answer(
            confirmColor: confirmColor,
            onCancel: () => Navigator.pop(context, false),
            onConfirm: () => Navigator.pop(context, true),
          ),
          children: [
            Icon(icon, color: confirmColor, size: 28),
            const SizedBox(height: 6),
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
          ],
        ),
      ),
    );
  }
}

/// The two round buttons, held at the bottom of the face by [WearScrollView]'s
/// footer slot.
class _Answer extends StatelessWidget {
  const _Answer({
    required this.confirmColor,
    required this.onCancel,
    required this.onConfirm,
  });

  final Color confirmColor;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  /// What each button gets where the face can afford it. Below this the pair
  /// shrinks together rather than running off the glass: a face too small to
  /// hold two 48 dp targets side by side loses the tap-target guarantee before
  /// it loses the buttons, which is the better of two bad trades.
  static const _diameter = 52.0;
  static const _gap = 16.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Sized from the width the round-safe geometry left, never from a
          // number that fit one watch: those insets are fractions of the
          // display, so a 192 dp face (384 px at density 2 — what Wear
          // emulators and the smaller watches use) hands this row 113 dp where
          // a 225 dp face hands it 133. A fixed pair of 52 dp buttons
          // overflowed the small one by 11.
          final diameter =
              math.min(_diameter, (constraints.maxWidth - _gap) / 2);
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CircleButton(
                diameter: diameter,
                icon: Icons.close_rounded,
                background: wearSurfaceHigh,
                tooltip: l10n.cancel,
                onTap: onCancel,
              ),
              const SizedBox(width: _gap),
              _CircleButton(
                diameter: diameter,
                icon: Icons.check_rounded,
                background: confirmColor,
                tooltip: l10n.wearConfirm,
                onTap: onConfirm,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.diameter,
    required this.icon,
    required this.background,
    required this.tooltip,
    required this.onTap,
  });

  final double diameter;
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
        fixedSize: Size.square(diameter),
        // The laid-out box is exactly the circle: with the padded default,
        // Material's minimum target adds width this row has already spent.
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, size: diameter / 2),
    );
  }
}
