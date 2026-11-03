import 'dart:math' as math;

import 'package:dash_kit/dash_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
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

/// Full-screen confirmation laid out as Wear Material 3's `AlertDialog` with
/// confirm and dismiss buttons (compose-material3 1.7.1): one scrolling
/// `ScalingLazyColumn` of icon, title, message and the two buttons, centred when
/// it fits. Every number below is from that source.
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

  /// `confirmDismissWithIconContentPadding()`: 1.2% of the screen height on
  /// top, `verticalContentPadding()` (10%) below.
  static const _topFraction = 0.012;
  static const _bottomFraction = 0.10;

  /// `TitlePaddingFraction`, `TextPaddingFraction`: side insets of the title
  /// and the message, as fractions of the screen width.
  static const _titleSideFraction = 0.12;
  static const _textSideFraction = 0.0416;

  /// `AlertTitleMaxLines`.
  static const _titleMaxLines = 3;

  /// Between the items (`AlertDialogDefaults.VerticalArrangement`) plus the
  /// spacing each slot carries: `AlertIconBottomSpacing`,
  /// `AlertTextMessageTopSpacing`, `ConfirmDismissButtonsTopSpacing`.
  static const _gap = 4.0;
  static const _iconToTitle = _gap + 4;
  static const _titleToText = _gap + 4;
  static const _textToButtons = _gap + 12;

  /// `ConfirmDismissButtonsBottomSpacingFraction`.
  static const _belowButtonsFraction = 0.045;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: WearScrollView(
        curved: true,
        contentPadding: (
          top: size.height * _topFraction,
          bottom: size.height * _bottomFraction,
        ),
        children: [
          Icon(icon, color: confirmColor, size: _AnswerButton.iconSize),
          const SizedBox(height: _iconToTitle),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: size.width * _titleSideFraction,
            ),
            child: Text(
              title,
              maxLines: _titleMaxLines,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: WearText.hero,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: _titleToText),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: size.width * _textSideFraction,
              ),
              child: Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: WearText.message.copyWith(color: wearMuted),
              ),
            ),
          ],
          const SizedBox(height: _textToButtons),
          _Answer(
            confirmColor: confirmColor,
            onCancel: () => Navigator.pop(context, false),
            onConfirm: () => Navigator.pop(context, true),
          ),
          SizedBox(height: size.height * _belowButtonsFraction),
        ],
      ),
    );
  }
}

/// `ConfirmDismissButtons`: 6 dp, the dismiss button, 3% of the screen width,
/// the confirm button, 2 dp.
class _Answer extends StatelessWidget {
  const _Answer({
    required this.confirmColor,
    required this.onCancel,
    required this.onConfirm,
  });

  final Color confirmColor;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  static const _leading = 6.0;
  static const _trailing = 2.0;
  static const _betweenFraction = 0.03;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(width: _leading),
        _AnswerButton.dismiss(tooltip: l10n.cancel, onTap: onCancel),
        SizedBox(width: MediaQuery.sizeOf(context).width * _betweenFraction),
        _AnswerButton.confirm(
          color: confirmColor,
          tooltip: l10n.wearConfirm,
          onTap: onConfirm,
        ),
        const SizedBox(width: _trailing),
      ],
    );
  }
}

/// `AlertDialogDefaults.DismissButton` — a 60 dp tonal square with the
/// `medium` (18 dp) corners — and `ConfirmButton` — a 63 x 54 dp filled
/// capsule turned 45° counter-clockwise, its icon turned back upright.
class _AnswerButton extends StatelessWidget {
  const _AnswerButton.dismiss({required this.tooltip, required this.onTap})
    : color = wearSurfaceHigh,
      icon = Icons.close_rounded,
      size = const Size.square(60),
      shape = const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(DashRadius.xl)),
      ),
      turn = 0;

  const _AnswerButton.confirm({
    required this.color,
    required this.tooltip,
    required this.onTap,
  }) : icon = Icons.check_rounded,
       size = const Size(63, 54),
       shape = const StadiumBorder(),
       turn = -math.pi / 4;

  /// `ConfirmIcon` / `DismissIcon`.
  static const iconSize = 28.0;

  final Color color;
  final IconData icon;
  final Size size;
  final ShapeBorder shape;
  final double turn;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: turn,
    child: Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.fromSize(
            size: size,
            child: Center(
              child: Transform.rotate(
                angle: -turn,
                child: Icon(icon, size: iconSize, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
