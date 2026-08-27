import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'wear_shape.dart';

/// Where a watch screen is allowed to put anything at all.
///
/// A round face is a circle drawn inside the square the layout gets: at the top
/// and the bottom of that square there is barely any room, so a full-width row
/// placed there has its corners outside the glass. Flutter never learns this —
/// the round display is not reported as a view inset, so `SafeArea` on Wear OS
/// resolves to zero and every screen here used to inset itself by a hand-picked
/// 8–18 px. That is what Google Play rejected: the first list row and the setup
/// screen's Save button were cut by the bezel.
///
/// What these insets describe is the **largest rectangle inscribed in the
/// circle**, and [WearScrollView] hands it to the scroll *viewport* rather than
/// to the content inside it. That distinction is the whole fix. Padding the
/// content only places the first and last item safely; everything between them
/// still travels through the top and bottom of the circle as the screen scrolls,
/// which is how a paragraph ended up sliced mid-word by the bezel and a Pause
/// button ended up with its ends cut off. A viewport that *is* the inscribed
/// rectangle cannot paint outside it, at any scroll offset.
///
/// The numbers are computed rather than guessed, from one tunable
/// ([roundEdgeFraction]) and the circle's own geometry.

/// Height kept clear above and below the viewport on a round face, as a fraction
/// of the display's height.
///
/// The one number this file is tuned by; everything else follows from the
/// circle, and the trade it makes is strict. A larger margin buys width — the
/// outermost row lands nearer the middle, where the chord is longer — and pays
/// for it in the vertical room a 225 dp face barely has: at 0.21 the setup
/// screen's own button fell below the fold, which is a worse first screen than
/// a slightly narrower one.
const roundEdgeFraction = 0.18;

/// Added to the derived side inset so a row is inside the circle rather than
/// exactly tangent to it, as a fraction of the diameter.
///
/// Corners of a rounded row cross the circle before its flat edge does, and the
/// bezel of a real watch eats a pixel or two more than the display metrics say.
const roundSideSlack = 0.015;

/// Share of the face a centred, narrow layout needs — a question with two round
/// buttons under it, rather than rows spanning the screen.
///
/// Narrow content buys height, which is the same trade as [roundEdgeFraction]
/// read from the other end: a block that does not need the full chord can reach
/// further up and down before the circle catches it. The confirmation dialog is
/// the case that needs it — its icon, question and button row are taller than
/// the rectangle a full-width screen gets, and a confirm nobody can reach
/// without scrolling is worse than one that gives up some width.
const wearNarrowWidthFraction = 0.62;

/// Insets on a square face. No geometry to satisfy — this is plain chrome, and
/// close to what the screens used before.
const _squareSideFraction = 0.06;
const _squareEdgeFraction = 0.08;

/// Half the width available at [dyFromCenter] above/below the middle of a round
/// display of [diameter] — half the chord of the circle at that height.
///
/// Zero past the edge rather than a NaN from the square root: callers ask about
/// positions that may lie outside the glass.
double roundHalfChord(double diameter, double dyFromCenter) {
  final radius = diameter / 2;
  final dy = dyFromCenter.abs();
  if (radius <= 0 || dy >= radius) return 0;
  return math.sqrt(radius * radius - dy * dy);
}

/// Side inset (a fraction of the diameter) that keeps a full-width row inside
/// the circle when the row's outermost corner sits [edgeFraction] of the
/// diameter below the top of the display.
///
/// The row's far corner is at `R - edgeFraction * D` from the centre; the chord
/// there is what the row may use, and half of what the circle does not give it
/// is the inset on each side.
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
///
/// Square faces keep their corners, so they only get chrome. On a round face the
/// pair is the inscribed rectangle: the vertical margin decides how tall the
/// rectangle is, and the horizontal one is whatever chord the circle leaves at
/// that height.
/// [widthFraction] states how much of the face the content actually needs; the
/// height then follows from the circle. Left out, the rectangle is sized for
/// content that spans it — which is every screen but the confirmation dialog.
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

/// Whether a row of [rowWidth] fits inside the circle when its outermost corner
/// is [dyFromCenter] from the middle. The check [wearFaceInsets] is built to
/// pass, exposed so tests can hold it to it.
bool rowFitsRoundFace({
  required double diameter,
  required double rowWidth,
  required double dyFromCenter,
}) =>
    rowWidth / 2 <= roundHalfChord(diameter, dyFromCenter);
