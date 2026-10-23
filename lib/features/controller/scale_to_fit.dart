import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The smallest box the controller's body is laid out in: the body area of the
/// touch panel whose look the controller borrows. A floor, not the target — the
/// screens are designed for a phone in landscape
/// ([docs/single-printer-controller.md]). Below it the whole body shrinks, above
/// it the whole body grows — one factor for every tab, so a button, a font or a
/// gap is the same size wherever it appears.
const controllerBodySize = Size(800, 360);

/// Scales [child] uniformly to fill the room it is given: the factor is the
/// largest that keeps [minSize] inside the room (capped at [maxScale]), and
/// [child] is laid out in the room divided by that factor, so it fills the
/// room exactly and is never laid out smaller than [minSize].
///
/// One of these wraps the whole controller body; nothing inside scales on its
/// own, which is what keeps similar controls the same size across cards.
class ScaleToFit extends StatelessWidget {
  const ScaleToFit({
    super.key,
    required this.child,
    this.minSize = controllerBodySize,
    this.maxScale = 2,
  });

  final Size minSize;
  final double maxScale;
  final Widget child;

  /// The factor [minSize] is scaled by to fit [room]. A side with no bound
  /// leaves the decision to the other; with neither bounded nothing scales.
  static double scaleFor(Size minSize, Size room, double maxScale) {
    final byWidth = room.width.isFinite
        ? room.width / minSize.width
        : double.infinity;
    final byHeight = room.height.isFinite
        ? room.height / minSize.height
        : double.infinity;
    final fit = math.min(byWidth, byHeight);
    return fit.isFinite ? math.min(fit, maxScale) : 1;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // The design is for text at its normal size. A larger system font makes
      // the same words need more room, so the box they are laid out in grows
      // with it; the whole is then scaled to fit, and nothing overflows.
      final text = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
      final min = minSize * text;
      final scale = scaleFor(min, box.biggest, maxScale);
      final room = box.biggest;
      final layout = Size(
        room.width.isFinite ? room.width / scale : min.width,
        room.height.isFinite ? room.height / scale : min.height,
      );
      // A FittedBox under loose constraints keeps the child's own size rather
      // than growing it, so its box is given the scaled size outright.
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox.fromSize(
          size: layout * scale,
          child: FittedBox(
            child: SizedBox.fromSize(
              size: layout,
              child: ControllerScale(scale: scale, child: child),
            ),
          ),
        ),
      );
    },
  );
}

/// The factor the controller body is drawn at, for what it opens in a route of
/// its own — a keypad is laid over the screen, not inside it, and would
/// otherwise stay at the design size on a larger screen. 1 where nothing scales.
class ControllerScale extends InheritedWidget {
  const ControllerScale({super.key, required this.scale, required super.child});

  final double scale;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ControllerScale>()?.scale ?? 1;

  @override
  bool updateShouldNotify(ControllerScale old) => scale != old.scale;
}
