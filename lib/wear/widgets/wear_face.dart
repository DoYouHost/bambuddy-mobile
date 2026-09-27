import 'package:flutter/material.dart';

import '../wear_geometry.dart';
import '../wear_shape.dart';

/// The rectangle inscribed in the watch face, for content that does not scroll.
///
/// Anything that scrolls goes through [WearScrollView] instead, where the insets
/// belong on the viewport. This is for the screens that paint a fixed block, and
/// it exists because each of them otherwise had to remember all three moving
/// parts — the platform's shape, the media query's size, then the insets.
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
