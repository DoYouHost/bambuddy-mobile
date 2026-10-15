import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'wear_shape.dart';

/// Where a watch screen is allowed to put anything at all: the largest
/// rectangle inscribed in the circle (a list scales instead —
/// `widgets/wear_scaling_list.dart`). `SafeArea` is blind here — a round
/// display is not reported as a view inset. The derivation, and what each
/// tunable was paid for, are in `docs/wear-geometry.md`.

/// Height kept clear above and below the viewport on a round face, as a fraction
/// of the display's height.
///
/// The one number the inscribed rectangle is tuned by; at 0.21 the setup
/// screen's own button fell below the fold.
const roundEdgeFraction = 0.18;

/// Added to the derived side inset so a row is inside the circle rather than
/// exactly tangent to it, as a fraction of the diameter.
const roundSideSlack = 0.015;

/// Insets on a square face. No geometry to satisfy — this is plain chrome, and
/// close to what the screens used before.
const _squareSideFraction = 0.06;
const _squareEdgeFraction = 0.08;

/// Half the chord of a [diameter] circle at [dyFromCenter] from its middle, and
/// zero past the edge rather than a NaN: callers ask about positions that may
/// lie outside the glass.
double roundHalfChord(double diameter, double dyFromCenter) {
  final radius = diameter / 2;
  final dy = dyFromCenter.abs();
  if (radius <= 0 || dy >= radius) return 0;
  return math.sqrt(radius * radius - dy * dy);
}

/// Side inset (a fraction of the diameter) keeping a full-width row inside the
/// circle when its outermost corner sits [edgeFraction] below the top: the far
/// corner is at `R - edgeFraction * D` from the centre, and half of what the
/// chord there does not give the row is the inset on each side.
double roundSideInsetFraction({
  double edgeFraction = roundEdgeFraction,
  double slack = roundSideSlack,
}) {
  const unitDiameter = 1.0;
  final dy = unitDiameter / 2 - edgeFraction * unitDiameter;
  final inset = unitDiameter / 2 - roundHalfChord(unitDiameter, dy);
  return inset + slack;
}

/// Insets that turn the display into a rectangle a watch screen may paint in.
/// Square faces keep their corners and only get chrome.
EdgeInsets wearFaceInsets(WearShape shape, Size size) {
  if (shape == WearShape.square) {
    return EdgeInsets.symmetric(
      horizontal: size.width * _squareSideFraction,
      vertical: size.height * _squareEdgeFraction,
    );
  }
  // The circle is inscribed in the square the display reports; on a face that is
  // not exactly square the shorter side is the one that limits it.
  final diameter = size.shortestSide;
  return EdgeInsets.symmetric(
    horizontal: diameter * roundSideInsetFraction(),
    vertical: diameter * roundEdgeFraction,
  );
}

/// Whether a row of [rowWidth] fits inside the circle when its outermost corner
/// is [dyFromCenter] from the middle. The check [wearFaceInsets] is built to
/// pass, exposed so tests can hold it to it.
bool rowFitsRoundFace({
  required double diameter,
  required double rowWidth,
  required double dyFromCenter,
}) => rowWidth / 2 <= roundHalfChord(diameter, dyFromCenter);
