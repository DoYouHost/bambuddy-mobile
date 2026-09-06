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

    test(
      'answers 0 rather than NaN past the glass, or with no glass at all',
      () {
        expect(roundHalfChord(450, 500), 0);
        expect(roundHalfChord(0, 0), 0);
        expect(roundHalfChord(-450, 10), 0);
      },
    );
  });

  group('roundSideInsetFraction', () {
    test(
      'leaves a full-width row inside the circle at the top of the content',
      () {
        const diameter = 450.0;
        final padding = wearFaceInsets(
          WearShape.round,
          const Size(diameter, diameter),
        );
        final rowWidth = diameter - padding.horizontal;
        // The row's outermost corner: as far from the middle as the content area
        // reaches.
        final dy = diameter / 2 - padding.top;

        expect(
          rowFitsRoundFace(
            diameter: diameter,
            rowWidth: rowWidth,
            dyFromCenter: dy,
          ),
          isTrue,
        );
      },
    );

    test('keeps real slack, not a tangent', () {
      const diameter = 450.0;
      final padding = wearFaceInsets(
        WearShape.round,
        const Size(diameter, diameter),
      );
      final dy = diameter / 2 - padding.top;
      final spare =
          roundHalfChord(diameter, dy) - (diameter - padding.horizontal) / 2;

      // Worth about 6 px a side on a 450 px face: the bezel eats a little more
      // than the display metrics admit, and rounded corners cross first.
      expect(spare, greaterThan(diameter * roundSideSlack * 0.9));
    });

    test('a taller margin buys a wider row', () {
      expect(
        roundSideInsetFraction(edgeFraction: 0.25),
        lessThan(roundSideInsetFraction(edgeFraction: 0.10)),
      );
    });

    test('is the geometry, not a constant', () {
      // Half the diameter minus the chord at the content's edge, plus slack.
      const edge = 0.18;
      final expected =
          0.5 - math.sqrt(0.25 - math.pow(0.5 - edge, 2)) + roundSideSlack;
      expect(
        roundSideInsetFraction(edgeFraction: edge),
        closeTo(expected, 1e-9),
      );
    });
  });

  group('wearFaceInsets', () {
    test(
      'round: sides derived from the circle, top and bottom from the tunable',
      () {
        final padding = wearFaceInsets(WearShape.round, const Size(450, 450));

        expect(padding.top, closeTo(450 * roundEdgeFraction, 0.001));
        expect(padding.top, padding.bottom);
        expect(padding.left, closeTo(450 * roundSideInsetFraction(), 0.001));
        expect(padding.left, padding.right);
      },
    );

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

    test('and both axes are read off that same shorter side', () {
      // The other way round: 400 wide, 450 tall still holds a 400 circle, so
      // top and bottom follow 400 too. Measuring the margin off the height
      // insets from a circle that is not there and loses rows the glass shows.
      final padding = wearFaceInsets(WearShape.round, const Size(400, 450));

      expect(padding.top, closeTo(400 * roundEdgeFraction, 0.001));
      expect(padding.left, closeTo(400 * roundSideInsetFraction(), 0.001));
    });

    test('degenerate sizes stay finite', () {
      final padding = wearFaceInsets(WearShape.round, Size.zero);

      expect(padding, EdgeInsets.zero);
    });
  });

  /// The branch only the confirmation dialog takes: it says how much width it
  /// needs and is given the height the circle owes it at that width.
  group('wearFaceInsets for narrow content', () {
    const face = Size(450, 450);

    test('trades the width it does not use for height', () {
      final full = wearFaceInsets(WearShape.round, face);
      final narrow = wearFaceInsets(
        WearShape.round,
        face,
        widthFraction: wearNarrowWidthFraction,
      );

      expect(narrow.left, greaterThan(full.left));
      expect(
        narrow.top,
        lessThan(full.top),
        reason: 'the whole point: a taller band for the confirm buttons',
      );
    });

    test(
      'leaves the content exactly as wide as it asked for, less the slack',
      () {
        const fraction = wearNarrowWidthFraction;
        final padding = wearFaceInsets(
          WearShape.round,
          face,
          widthFraction: fraction,
        );

        expect(
          face.width - padding.horizontal,
          closeTo(face.width * (fraction - 2 * roundSideSlack), 0.001),
        );
      },
    );

    test('and keeps that rectangle inside the glass on the smallest face', () {
      // 192 dp: the face the fixed-width button row overflowed by 11 px.
      const diameter = 384.0;
      final padding = wearFaceInsets(
        WearShape.round,
        const Size(diameter, diameter),
        widthFraction: wearNarrowWidthFraction,
      );

      expect(
        rowFitsRoundFace(
          diameter: diameter,
          rowWidth: diameter - padding.horizontal,
          dyFromCenter: diameter / 2 - padding.top,
        ),
        isTrue,
      );
    });

    test('and the height it gets back is the chord at that width', () {
      const fraction = 0.6;
      final padding = wearFaceInsets(
        WearShape.round,
        face,
        widthFraction: fraction,
      );

      // The circle does not care which axis it is asked about: the half-chord
      // at a horizontal offset of 0.3 is the half-height the rectangle may
      // have. Anything else here is a number somebody picked.
      expect(
        face.height - padding.vertical,
        closeTo(
          face.height *
              (2 * roundHalfChord(1, fraction / 2) - 2 * roundSideSlack),
          0.001,
        ),
      );
    });

    test('a fraction outside 0..1 is clamped, not extrapolated into a NaN', () {
      expect(
        wearFaceInsets(WearShape.round, face, widthFraction: 1.5),
        wearFaceInsets(WearShape.round, face, widthFraction: 1),
      );
      expect(
        wearFaceInsets(WearShape.round, face, widthFraction: -1),
        wearFaceInsets(WearShape.round, face, widthFraction: 0),
      );
    });

    test('a square face ignores it — there is no circle to trade against', () {
      expect(
        wearFaceInsets(
          WearShape.square,
          face,
          widthFraction: wearNarrowWidthFraction,
        ),
        wearFaceInsets(WearShape.square, face),
      );
    });
  });

  group('the curve a scrolling list follows', () {
    const diameter = 225.0;
    const width = 166.0;
    const height = 59.0;
    final radius = diameter * (0.5 - roundSideSlack);

    double scaleAt(double top) => roundScaleFor(
      diameter: diameter,
      itemWidth: width,
      top: top,
      bottom: top + height,
    );

    /// The corner furthest from the middle once [top] has been scaled.
    double farCorner(double top) {
      final bottom = top + height;
      final anchor = roundCurveAnchor(top, bottom);
      final scale = scaleAt(top);
      return math.max(
        (anchor + (top - anchor) * scale).abs(),
        (anchor + (bottom - anchor) * scale).abs(),
      );
    }

    test('leaves an item lying across the middle alone', () {
      expect(scaleAt(-height / 2), 1);
    });

    test('the scale it returns actually fits, wherever the item is', () {
      // The property the whole layout rests on, checked against the circle
      // rather than against the formula that produced it: shrinking an item
      // pulls its far corner in as well as narrowing it, which is the part the
      // obvious answer — measure the unscaled corner — gets wrong in both
      // directions at once.
      for (var top = -diameter; top < diameter; top += 1) {
        final scale = scaleAt(top);
        if (scale == 0) continue;
        final halfWidth = width * scale / 2;
        final corner = farCorner(top);
        expect(
          halfWidth,
          lessThanOrEqualTo(
            math.sqrt(math.max(0, radius * radius - corner * corner)) + 0.001,
          ),
          reason:
              'an item scaled to $scale at $top still has a corner off the '
              'glass',
        );
      }
    });

    test('never scales away an item that still has glass under it', () {
      // The bug this anchoring exists for: held by its own centre, the demo
      // fleet's third printer went to nothing with 15 dp of its row still on
      // the display, so a list of four showed two and a black gap. Anything
      // whose near edge is on the face has to be worth something.
      for (var top = 0.0; top < radius - 1; top += 1) {
        expect(
          scaleAt(top),
          greaterThan(0),
          reason: 'an item starting at $top is still partly on the glass',
        );
      }
    });

    test('shrinks the further out it is asked about', () {
      final scales = [for (var top = 0.0; top < 100; top += 20) scaleAt(top)];

      expect(
        scales,
        orderedEquals(scales.toList()..sort((a, b) => b.compareTo(a))),
        reason: 'a list that grew items on its way out would read as a fault',
      );
      // And it has to be a real curve, not a formula that answers 1 everywhere
      // and satisfies the fit check by never shrinking anything.
      expect(scales.first, 1);
      expect(scales.last, lessThan(0.6));
    });

    test('is nothing once the near edge has left the face', () {
      expect(scaleAt(radius + 1), 0);
    });

    test('does not divide by an item with no width', () {
      expect(
        roundScaleFor(diameter: diameter, itemWidth: 0, top: 50, bottom: 100),
        1,
      );
    });

    test('reads the same above and below the middle', () {
      expect(scaleAt(40), closeTo(scaleAt(-40 - height), 0.000001));
    });

    test(
      'does not shrink a rounded item to protect a corner it never paints',
      () {
        double at(double corner) => roundScaleFor(
          diameter: diameter,
          itemWidth: width,
          top: 20,
          bottom: 20 + height,
          cornerRadius: corner,
        );

        // The measured cost of ignoring this: a 20 dp round row was scaled to
        // 0.85 to keep a square corner on the glass. Scaled text is re-rasterised
        // — the same advances land on different pixels — so a row that shrinks
        // for nothing reads as a row with different letter spacing.
        expect(at(20), greaterThan(at(0)));
      },
    );

    test('and the rounded shape it allows still fits the glass', () {
      const corner = 20.0;
      for (var top = 0.0; top < radius - 1; top += 1) {
        final bottom = top + height;
        final scale = roundScaleFor(
          diameter: diameter,
          itemWidth: width,
          top: top,
          bottom: bottom,
          cornerRadius: corner,
        );
        if (scale == 0) continue;

        final anchor = roundCurveAnchor(top, bottom);
        final reach = math.max((top - anchor).abs(), (bottom - anchor).abs());
        final round = math.min(corner, math.min(width / 2, reach)) * scale;
        final far = (anchor + (bottom - anchor) * scale).abs();
        // What has to be inside the circle is the corner arc: its centre, one
        // radius in from each edge, plus that radius.
        final centre = Offset(width * scale / 2 - round, far - round);
        expect(
          centre.distance + round,
          lessThanOrEqualTo(radius + 0.001),
          reason:
              'a $corner dp round item scaled to $scale at $top puts its '
              'corner arc off the glass',
        );
      }
    });

    test('survives a corner radius larger than the item it is given', () {
      // Nonsense in, something safe out: the quadratic loses its usable root
      // when the corners eat the whole box, and the plain box is the answer
      // that only ever asks for less.
      final scale = roundScaleFor(
        diameter: diameter,
        itemWidth: 20,
        top: 60,
        bottom: 70,
        cornerRadius: 200,
      );

      expect(scale, greaterThan(0));
      expect(scale, lessThanOrEqualTo(1));
    });

    test('anchors an item by whichever part of it is nearest the middle', () {
      expect(roundCurveAnchor(20, 80), 20, reason: 'below: its top edge');
      expect(roundCurveAnchor(-80, -20), -20, reason: 'above: its bottom edge');
      expect(roundCurveAnchor(-30, 30), 0, reason: 'across: the middle itself');
    });
  });
}
