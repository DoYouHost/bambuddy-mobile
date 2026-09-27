import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'wear_shape.dart';

/// Where a watch screen is allowed to put anything at all: the largest
/// rectangle inscribed in the circle, and the scale a curved list follows
/// instead. `SafeArea` is blind here — a round display is not reported as a
/// view inset. The derivation, and what each tunable was paid for, are in
/// `docs/wear-geometry.md`.

/// Height kept clear above and below the viewport on a round face, as a fraction
/// of the display's height.
///
/// The one number the inscribed rectangle is tuned by; at 0.21 the setup
/// screen's own button fell below the fold.
const roundEdgeFraction = 0.18;

/// Added to the derived side inset so a row is inside the circle rather than
/// exactly tangent to it, as a fraction of the diameter.
const roundSideSlack = 0.015;

/// Share of the face a centred, narrow layout needs — a question with two round
/// buttons under it, rather than rows spanning the screen. Narrow content buys
/// height, which is what the confirmation dialog needs.
const wearNarrowWidthFraction = 0.62;

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
/// Square faces keep their corners and only get chrome. [widthFraction] states
/// how much of the face the content actually needs, and the height then follows
/// from the circle; left out, the rectangle is sized for content that spans it
/// — every screen but the confirmation dialog.
EdgeInsets wearFaceInsets(WearShape shape, Size size, {double? widthFraction}) {
  if (shape == WearShape.square) {
    return EdgeInsets.symmetric(
      horizontal: size.width * _squareSideFraction,
      vertical: size.height * _squareEdgeFraction,
    );
  }
  // The circle is inscribed in the square the display reports; on a face that is
  // not exactly square the shorter side is the one that limits it.
  final diameter = size.shortestSide;
  if (widthFraction == null) {
    return EdgeInsets.symmetric(
      horizontal: diameter * roundSideInsetFraction(),
      vertical: diameter * roundEdgeFraction,
    );
  }
  final halfWidth = widthFraction.clamp(0.0, 1.0) / 2;
  // A circle does not care which axis it is asked about: the half-chord at a
  // given horizontal offset is the half-height the rectangle may have.
  final halfHeight = roundHalfChord(1, halfWidth);
  return EdgeInsets.symmetric(
    horizontal: diameter * (0.5 - halfWidth + roundSideSlack),
    vertical: diameter * (0.5 - halfHeight + roundSideSlack),
  );
}

/// Where the first and last item of a curved list come to rest, as a fraction
/// of the diameter — not a margin content may never enter.
const roundCurveEndFraction = 0.10;

/// Where an item spanning [top]..[bottom] is held while it shrinks: whichever
/// part of it is nearest the middle of the face, so it compresses towards the
/// middle rather than walking off the rim. Both are measured from that middle,
/// negative above it.
double roundCurveAnchor(double top, double bottom) =>
    top > 0 ? top : (bottom < 0 ? bottom : 0);

/// How much an item [itemWidth] wide, spanning [top]..[bottom] from the middle
/// of the face, has to shrink to sit on the glass when held at its anchor.
///
/// Solved rather than approximated — shrinking an item pulls its far corner in
/// as well as narrowing it — from `(s·(w/2 − r))² + (d + s·(reach − r))² ≤
/// (R − s·r)²`, a quadratic in `s`. See `docs/wear-geometry.md`.
///
/// [cornerRadius] defaults to nothing because the watch's items are not
/// uniform; only a screen whose rows are all one shape may claim it.
double roundScaleFor({
  required double diameter,
  required double itemWidth,
  required double top,
  required double bottom,
  double cornerRadius = 0,
}) {
  if (itemWidth <= 0) return 1;
  // Tangent is not inside: solved exactly, the arithmetic lands the corners a
  // rounding error outside the circle, so they take [roundSideSlack] too.
  final radius = diameter * (0.5 - roundSideSlack);
  final anchor = roundCurveAnchor(top, bottom);
  final distance = anchor.abs();
  final c = distance * distance - radius * radius;
  if (c >= 0) return 0;
  // How far the item reaches from its anchor. For one lying across the middle
  // that is its longer half; for one below or above, its whole height.
  final reach = math.max((top - anchor).abs(), (bottom - anchor).abs());
  // What has to fit is the corner *arc*, not the corner of the box: its centre,
  // [cornerRadius] in from both edges, plus that radius. Bounded by the item,
  // since a box cannot be rounder than half of itself.
  var round = math.min(cornerRadius, math.min(itemWidth / 2, reach));
  var side = itemWidth / 2 - round;
  var span = reach - round;
  var a = side * side + span * span - round * round;
  if (a <= 0) {
    // Corners that eat the whole item leave the quadratic without a usable
    // root; fall back to the plain box, which only ever asks for less.
    round = 0;
    side = itemWidth / 2;
    span = reach;
    a = side * side + span * span;
  }
  final b = 2 * (distance * span + radius * round);
  // `c` is negative, so the discriminant is positive and the larger root is the
  // one in range: the biggest scale that still fits.
  return math.min(1, (-b + math.sqrt(b * b - 4 * a * c)) / (2 * a));
}

/// Whether a row of [rowWidth] fits inside the circle when its outermost corner
/// is [dyFromCenter] from the middle. The check [wearFaceInsets] is built to
/// pass, exposed so tests can hold it to it.
bool rowFitsRoundFace({
  required double diameter,
  required double rowWidth,
  required double dyFromCenter,
}) => rowWidth / 2 <= roundHalfChord(diameter, dyFromCenter);
