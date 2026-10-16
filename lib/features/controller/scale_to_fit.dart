import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lays [child] out at [designSize] and then scales it to fill the room it is
/// given, up to [maxScale] times and down as far as it takes to fit. The
/// controller's cards use it so a big screen gets big controls and a small one
/// small ones, instead of every screen getting the design's sizes in a corner of
/// the card.
///
/// Scaling is uniform, so proportions hold; [child] must be built to look right
/// at [designSize] with text at its normal size. A parent that gives it no bound
/// to fill gets the design size.
class ScaleToFit extends StatelessWidget {
  const ScaleToFit({
    super.key,
    required this.designSize,
    required this.child,
    this.maxScale = 2,
    this.alignment = Alignment.center,
  });

  final Size designSize;
  final double maxScale;
  final Alignment alignment;
  final Widget child;

  /// The factor [designSize] is scaled by to fit [room]. A side with no bound
  /// leaves the decision to the other; with neither bounded the design size
  /// stands.
  static double scaleFor(Size designSize, Size room, double maxScale) {
    final byWidth = room.width.isFinite
        ? room.width / designSize.width
        : double.infinity;
    final byHeight = room.height.isFinite
        ? room.height / designSize.height
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
      final design = Size(designSize.width * text, designSize.height * text);
      final scale = scaleFor(design, box.biggest, maxScale);
      return Align(
        alignment: alignment,
        child: SizedBox(
          width: design.width * scale,
          height: design.height * scale,
          child: FittedBox(
            alignment: alignment,
            child: SizedBox.fromSize(size: design, child: child),
          ),
        ),
      );
    },
  );
}
