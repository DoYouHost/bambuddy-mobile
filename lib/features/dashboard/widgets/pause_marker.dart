import 'package:material_ui/material_ui.dart';

import '../../../core/format/duration_format.dart';
import '../../../core/models/printer_status.dart';
import '../../../core/theme/dash_theme.dart';
import '../../../l10n/app_localizations.dart';
import 'print_meta_row.dart';

/// Where the next pause falls on the print's progress bar, 0 to 1, or null when
/// it cannot be placed (server #2984).
///
/// With minutes it is placed on the bar's own scale: the bar's fill is the
/// share of the print done, so the pause sits that far plus the share its
/// minutes are of the whole print. Without them (the start of a print, a speed
/// mode other than standard) it falls back to its layer's share of the layers,
/// which is only roughly where the fill will be then.
double? pauseTickFraction(PrinterStatus status) {
  final pause = status.nextPause;
  if (pause == null) return null;
  final progress = status.progress;
  final remaining = status.remainingTime;
  final minutes = pause.minutes;
  if (progress != null &&
      progress < 100 &&
      remaining != null &&
      remaining > 0 &&
      minutes != null) {
    final done = progress / 100;
    final whole = remaining / (1 - done);
    return (done + minutes / whole).clamp(done, 1.0);
  }
  final layers = status.totalLayers;
  if (layers != null && layers > 0 && pause.layer <= layers) {
    return pause.layer / layers;
  }
  return null;
}

/// The "next pause" item of the print panel's meta row: the minutes to it, or
/// its layer while the server cannot say. Null when no pause is ahead. The
/// words are for a screen reader; the row itself keeps to an icon and a figure.
PrintMetaItem? pauseMetaItem(
  BuildContext context,
  AppLocalizations l10n,
  PrinterStatus status,
) {
  final pause = status.nextPause;
  if (pause == null) return null;
  final minutes = pause.minutes;
  final when = minutes == null ? null : formatMinutes(l10n, minutes);
  return PrintMetaItem(
    icon: Icons.pause_circle_outline,
    text: when ?? l10n.printPauseAtLayer(pause.layer),
    color: DashTokens.of(context).accentBlueInk,
    semanticLabel: when == null
        ? l10n.printPauseA11yLayer(pause.layer)
        : l10n.printPauseA11yIn(when, pause.layer),
  );
}

/// A tick across a progress bar at [fraction] of its width. Drawn over the bar
/// without taking room, and left out of the semantics tree: the meta row's
/// item says the same in words.
class PauseTick extends StatelessWidget {
  const PauseTick({
    super.key,
    required this.fraction,
    required this.barHeight,
    required this.child,
  });

  final double? fraction;
  final double barHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final at = fraction;
    if (at == null || at <= 0 || at >= 1) return child;
    final t = DashTokens.of(context);
    const tickHeight = DashSize.d12;
    const tickWidth = DashSize.d4;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned.fill(
          child: ExcludeSemantics(
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: box.maxWidth * at - tickWidth / 2,
                    top: (barHeight - tickHeight) / 2,
                    child: Container(
                      width: tickWidth,
                      height: tickHeight,
                      decoration: BoxDecoration(
                        color: t.accentBlue,
                        borderRadius: BorderRadius.circular(DashRadius.sm),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
