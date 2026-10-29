import 'dart:math' as math;

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import 'controller_controls.dart';
import 'scale_to_fit.dart';

/// Height of a tile in a Prints view's grid: its thumbnail and a margin, so a
/// tile is a touch target well above the minimum whatever it says. Three rows of
/// them fill the card on a phone.
const controllerTileHeight = 82.0;
const controllerThumbSize = 64.0;
const controllerGridColumns = 2;

/// The share of the font's growth a tile in the one-column layout takes.
const _oneColumnGrowthShare = 1 / 3;

/// The grid every Prints view lays its tiles in. A tile grows with the system
/// font, as the body's box does (`ScaleToFit`): two lines of title and a row of
/// facts outgrow a fixed height at a large one.
SliverGridDelegate controllerTileGrid(
  BuildContext context,
) => SliverGridDelegateWithFixedCrossAxisCount(
  // One column at a large text size: a tile's facts and badge need the width.
  crossAxisCount: controllerLargeText(context) ? 1 : controllerGridColumns,
  // In one column the title has the width for a line and the thumbnail does not
  // grow, so a tile needs only [_oneColumnGrowthShare] of the font's growth.
  mainAxisExtent:
      controllerTileHeight *
      (controllerLargeText(context)
          ? 1 +
                (MediaQuery.textScalerOf(context).scale(1) - 1) *
                    _oneColumnGrowthShare
          : math.max(1.0, MediaQuery.textScalerOf(context).scale(1))),
  mainAxisSpacing: DashSpace.sm,
  crossAxisSpacing: DashSpace.sm,
);

/// A square icon button of a Prints view's header.
class ControllerHeaderButton extends StatelessWidget {
  const ControllerHeaderButton({
    super.key,
    required this.id,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String id;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Tooltip(
      message: tooltip,
      child: logTag(
        id,
        FilledButton(
          style: controllerButtonStyle(
            t,
            minimumSize: const Size.square(controllerButtonHeight),
            padding: EdgeInsets.zero,
          ),
          onPressed: onPressed,
          // An icon-only `FilledButton` takes its label from its child; the
          // `Tooltip` around it is not merged into the button's node.
          child: Icon(icon, semanticLabel: tooltip),
        ),
      ),
    );
  }
}

/// The card beside a header's buttons: what the view shows, anything it carries
/// beside that, a short fact on the right, and the bar of a request on its way.
class ControllerHeaderCard extends StatelessWidget {
  const ControllerHeaderCard({
    super.key,
    required this.title,
    this.extras = const [],
    this.fact,
    this.busy = false,
    this.progress,
  });

  final String title;

  /// Between the title and [fact], each after a gap.
  final List<Widget> extras;
  final String? fact;

  /// Draws a bar along the bottom edge: determinate at [progress], running
  /// while that is null.
  final bool busy;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      height: controllerButtonHeight,
      alignment: Alignment.centerLeft,
      decoration: t.cardBox,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DashSpace.lg),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: t.titleSm,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                for (final extra in extras) ...[
                  const SizedBox(width: DashSpace.md),
                  extra,
                ],
                if (fact case final text?) ...[
                  const SizedBox(width: DashSpace.md),
                  Text(text, style: t.monoLabel, maxLines: 1),
                ],
              ],
            ),
          ),
          if (busy)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(value: progress, minHeight: 4),
            ),
        ],
      ),
    );
  }
}

/// The frame of every tile: the app's sub-card, with a thumbnail slot.
class ControllerTileFrame extends StatelessWidget {
  const ControllerTileFrame({
    super.key,
    required this.id,
    required this.onTap,
    required this.leading,
    required this.children,
    this.dimmed = false,
    this.highlighted = false,
  });

  final String id;
  final VoidCallback? onTap;
  final Widget leading;
  final List<Widget> children;

  /// A tile whose item cannot be acted on here is quieter, and still opens:
  /// its dialog says why.
  final bool dimmed;

  /// The job the printer is on, edged in the accent as the queue screen edges it.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final radius = BorderRadius.circular(DashSpace.md);
    return Opacity(
      opacity: dimmed ? 0.62 : 1,
      child: Material(
        color: highlighted ? t.accentGreen.withValues(alpha: 0.06) : t.subCard,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: highlighted
                ? t.accentGreen.withValues(alpha: 0.45)
                : t.subCardBorder,
          ),
        ),
        child: logTag(
          id,
          InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(DashSpace.sm),
              child: Row(
                children: [
                  leading,
                  const SizedBox(width: DashSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: children,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A short label on a tile, in the colour that says what it means.
class ControllerChip extends StatelessWidget {
  const ControllerChip({
    super.key,
    required this.label,
    required this.ink,
    this.icon,
  });

  final String label;
  final Color ink;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DashSpace.sm),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DashSpace.sm),
        border: Border.all(color: ink.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon case final glyph?) ...[
            Icon(
              glyph,
              size: controllerIconSize(context, DashSpace.md),
              color: ink,
            ),
            const SizedBox(width: DashSpace.xs),
          ],
          Flexible(
            child: Text(
              label,
              style: t.monoLabel.copyWith(color: ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// A listing that could not be had: the server refused it, or was not there.
class ControllerListFailure extends StatelessWidget {
  const ControllerListFailure({
    super.key,
    required this.error,
    required this.retryId,
    required this.onRetry,
  });

  final Object error;
  final String retryId;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final refused =
        error is AppApiException &&
        (error as AppApiException).code == AppErrorCode.forbidden;
    return ControllerListMessage(
      icon: refused ? Icons.lock_outline_rounded : Icons.cloud_off_rounded,
      text: refused
          ? (error as AppApiException).localized(l10n)
          : l10n.connectFailed,
      // Nothing to retry for a refusal: the account has to change first.
      action: refused
          ? null
          : logTag(
              retryId,
              FilledButton(
                style: controllerButtonStyle(
                  DashTokens.of(context),
                  minimumSize: const Size(0, controllerButtonHeight),
                ),
                onPressed: onRetry,
                child: Text(l10n.retry),
              ),
            ),
    );
  }
}

class ControllerListMessage extends StatelessWidget {
  const ControllerListMessage({
    super.key,
    required this.icon,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: controllerIconSize(context, DashSpace.xxl),
            color: t.textTertiary,
          ),
          const SizedBox(height: DashSpace.md),
          Text(text, style: t.bodySoft, textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: DashSpace.lg),
            action!,
          ],
        ],
      ),
    );
  }
}
