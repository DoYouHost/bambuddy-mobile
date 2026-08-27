import 'dart:math' as math;

import 'package:bambuddy_mobile/wear/wear_geometry.dart';
import 'package:bambuddy_mobile/wear/wear_shape.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The maths Google Play rejected the watch build over: a round face is a circle
/// inside the square the layout is handed, and Flutter reports no inset for it,
/// so the padding has to be derived rather than picked.
void main() {
  group('roundHalfChord', () {
    test('is the radius through the middle and nothing at the edge', () {
      expect(roundHalfChord(450, 0), 225);
      expect(roundHalfChord(450, 225), 0);
    });

    test('follows the circle in between', () {
      // 3-4-5: at 135 from the centre of a 450 face the chord is 2x180.
      expect(roundHalfChord(450, 135), closeTo(180, 0.001));
    });

    test('is symmetric above and below the middle', () {
      expect(roundHalfChord(450, -90), roundHalfChord(450, 90));
    });

    test('answers 0 rather than NaN past the glass, or with no glass at all',
        () {
      expect(roundHalfChord(450, 500), 0);
      expect(roundHalfChord(0, 0), 0);
      expect(roundHalfChord(-450, 10), 0);
    });
  });

  group('roundSideInsetFraction', () {
    test('leaves a full-width row inside the circle at the top of the content',
        () {
      const diameter = 450.0;
      final padding = wearFaceInsets(WearShape.round, const Size(diameter, diameter));
      final rowWidth = diameter - padding.horizontal;
      // The row's outermost corner: as far from the middle as the content area
      // reaches.
      final dy = diameter / 2 - padding.top;

      expect(
        rowFitsRoundFace(diameter: diameter, rowWidth: rowWidth, dyFromCenter: dy),
        isTrue,
      );
    });

    test('keeps real slack, not a tangent', () {
      const diameter = 450.0;
      final padding = wearFaceInsets(WearShape.round, const Size(diameter, diameter));
      final dy = diameter / 2 - padding.top;
      final spare = roundHalfChord(diameter, dy) - (diameter - padding.horizontal) / 2;

      // Worth about 6 px a side on a 450 px face: the bezel eats a little more
      // than the display metrics admit, and rounded corners cross first.
      expect(spare, greaterThan(diameter * roundSideSlack * 0.9));
    });

    test('a taller margin buys a wider row', () {
      expect(roundSideInsetFraction(edgeFraction: 0.25),
          lessThan(roundSideInsetFraction(edgeFraction: 0.10)));
    });

    test('is the geometry, not a constant', () {
      // Half the diameter minus the chord at the content's edge, plus slack.
      const edge = 0.18;
      final expected =
          0.5 - math.sqrt(0.25 - math.pow(0.5 - edge, 2)) + roundSideSlack;
      expect(roundSideInsetFraction(edgeFraction: edge), closeTo(expected, 1e-9));
    });
  });

  group('wearFaceInsets', () {
    test('round: sides derived from the circle, top and bottom from the tunable',
        () {
      final padding =
          wearFaceInsets(WearShape.round, const Size(450, 450));

      expect(padding.top, closeTo(450 * roundEdgeFraction, 0.001));
      expect(padding.top, padding.bottom);
      expect(padding.left, closeTo(450 * roundSideInsetFraction(), 0.001));
      expect(padding.left, padding.right);
    });

    test('square: plain chrome, and less of it than a round face needs', () {
      final square = wearFaceInsets(WearShape.square, const Size(450, 450));
      final round = wearFaceInsets(WearShape.round, const Size(450, 450));

      expect(square.left, lessThan(round.left));
      expect(square.top, lessThan(round.top));
    });

    test('a face that is not exactly square is limited by its shorter side', () {
      // The circle is inscribed in the display, so the chord maths runs on the
      // smaller dimension — taking the width here would inset too little.
      final padding = wearFaceInsets(WearShape.round, const Size(450, 400));

      expect(padding.left, closeTo(400 * roundSideInsetFraction(), 0.001));
    });

    test('degenerate sizes stay finite', () {
      final padding = wearFaceInsets(WearShape.round, Size.zero);

      expect(padding, EdgeInsets.zero);
    });
  });
}
