import 'package:flutter/material.dart';

import '../wear_geometry.dart';
import '../wear_shape.dart';

/// The rectangle inscribed in the watch face, for content that does not scroll.
///
/// [WearScrollView] is how a scrolling screen gets the same thing, and it is
/// still the answer for anything that scrolls — the insets have to go on the
/// viewport there, which is a different problem than this one. What was left
/// over is the handful of screens that paint a fixed block on the glass, and
/// each of them had to know all three moving parts: ask the platform for the
/// shape, ask the media query for the size, and only then compute the insets.
/// Three calls remembered in three places is how one of them ends up forgotten,
/// which is what the printer-unavailable state was until it got its own line
/// here.
class WearFace extends StatelessWidget {
  const WearFace({super.key, required this.child, this.widthFraction});

  final Widget child;

  /// How much of the face the content actually needs, if less than all of it —
  /// see [wearNarrowWidthFraction]. Narrower content is allowed a taller box,
  /// because the circle takes its width back nearer the edges.
  final double? widthFraction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: wearFaceInsets(
      wearShapeOf(context),
      MediaQuery.sizeOf(context),
      widthFraction: widthFraction,
    ),
    child: child,
  );
}
