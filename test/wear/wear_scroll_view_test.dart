import 'package:bambuddy_mobile/wear/wear_shape.dart';
import 'package:bambuddy_mobile/wear/widgets/wear_scaling_list.dart';
import 'package:bambuddy_mobile/wear/widgets/wear_scroll_indicator.dart';
import 'package:bambuddy_mobile/wear/widgets/wear_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Both layout rejections Google Play sent back live in this widget: content cut
/// off by the round bezel, and a scrollable screen with no scroll indicator.

/// Every corner of [rect] inside the glass of a round face [logical] dp across.
Matcher insideFace(double logical) => predicate<Rect>((rect) {
  final radius = logical / 2;
  final centre = Offset(radius, radius);
  return [
    rect.topLeft,
    rect.topRight,
    rect.bottomLeft,
    rect.bottomRight,
  ].every((corner) => (corner - centre).distance <= radius);
}, 'inside a ${logical.round()} dp round face');

/// Pumps [child] on a watch face, without the localizations and provider scope
/// [pumpWear] carries — this widget needs neither, and the tests below pump the
/// same tree twice with two different shapes.
Future<void> _pumpFace(
  WidgetTester tester,
  Widget child, {
  WearShape shape = WearShape.round,
  Size face = wearFaceLarge,
}) async {
  useWatchFace(tester, shape, face);
  await tester.pumpWidget(
    MaterialApp(
      // Keyed by shape: pumping a second face into the same tree would otherwise
      // update the existing scope instead of rebuilding it, and the shape is read
      // once, in initState.
      builder: (context, inner) =>
          WearShapeScope(key: ValueKey(shape), child: inner!),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

/// A full-width row, the shape that was landing under the bezel.
Widget _row(int index) => SizedBox(
  key: ValueKey('row-$index'),
  height: 44,
  child: ColoredBox(color: Colors.green.shade900, child: Text('row $index')),
);

Finder get _indicator => find.descendant(
  of: find.byType(WearScrollIndicator),
  matching: find.byType(CustomPaint),
);

void main() {
  for (final (face, logical) in [
    (wearFaceSmall, 192.0),
    (wearFaceLarge, 225.0),
  ]) {
    group('round-safe insets on a ${logical.round()} dp face', () {
      final inside = insideFace(logical);

      testWidgets('the viewport itself never reaches the bezel', (
        tester,
      ) async {
        await _pumpFace(
          tester,
          WearScrollView(children: [for (var i = 0; i < 12; i++) _row(i)]),
          face: face,
        );

        // The invariant the layout rests on, and the one a per-row rect cannot
        // express: a row on its way out legitimately hangs past the viewport and
        // is clipped by it. What must hold is that the viewport — everything that
        // can be painted, at any scroll offset — is inside the glass.
        expect(tester.getRect(find.byType(Scrollable)), inside);

        await tester.drag(find.byType(WearScrollView), const Offset(0, -70));
        await tester.pumpAndSettle();

        expect(tester.getRect(find.byType(Scrollable)), inside);
      });

      testWidgets(
        'the first row is inside the glass at the top of the scroll',
        (tester) async {
          await _pumpFace(
            tester,
            WearScrollView(children: [for (var i = 0; i < 12; i++) _row(i)]),
            face: face,
          );

          expect(tester.getRect(find.byKey(const ValueKey('row-0'))), inside);
        },
      );

      testWidgets('and the last one is, at the bottom of it', (tester) async {
        await _pumpFace(
          tester,
          WearScrollView(children: [for (var i = 0; i < 12; i++) _row(i)]),
          face: face,
        );

        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('row-11')),
          60,
        );
        await tester.pumpAndSettle();

        expect(tester.getRect(find.byKey(const ValueKey('row-11'))), inside);
      });

      testWidgets('short content sits in the middle when asked to', (
        tester,
      ) async {
        await _pumpFace(
          tester,
          WearScrollView(centerWhenShort: true, children: [_row(0)]),
          face: face,
        );

        final row = tester.getRect(find.byKey(const ValueKey('row-0')));
        expect(row.center.dy, closeTo(logical / 2, 1));
        expect(row, inside);
      });
    });
  }

  group('scroll indicator', () {
    testWidgets('stays away while everything fits on the face', (tester) async {
      await _pumpFace(tester, WearScrollView(children: [_row(0)]));

      expect(_indicator, findsNothing);
    });

    testWidgets('shows itself on a screen that scrolls', (tester) async {
      await _pumpFace(
        tester,
        WearScrollView(children: [for (var i = 0; i < 12; i++) _row(i)]),
      );

      // No gesture yet: landing on a scrollable screen is when someone needs to
      // be told that it scrolls.
      expect(_indicator, findsOneWidget);
    });

    testWidgets('comes back on a scroll and leaves again when it stops', (
      tester,
    ) async {
      await _pumpFace(
        tester,
        WearScrollView(children: [for (var i = 0; i < 12; i++) _row(i)]),
      );

      // Past the first showing, so what follows is the gesture's doing.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(_indicator, findsNothing);

      await tester.drag(find.byType(WearScrollView), const Offset(0, -60));
      // Two frames: the first is where the fade's ticker starts counting, the
      // second is the one that actually carries it off zero.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_indicator, findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(
        _indicator,
        findsNothing,
        reason: 'permanent chrome on a 1.4" face is a waste of it',
      );
    });
  });

  group('the edge fade', () {
    testWidgets('stays out of it while everything fits', (tester) async {
      // Nothing can reach the viewport's edge, so the gradient would be
      // invisible — and a ShaderMask is an offscreen compositing pass a frame.
      await _pumpFace(tester, WearScrollView(children: [_row(0)]));

      expect(find.byType(ShaderMask), findsNothing);
    });

    testWidgets('softens it once the content can cross it', (tester) async {
      await _pumpFace(
        tester,
        WearScrollView(children: [for (var i = 0; i < 12; i++) _row(i)]),
      );

      expect(find.byType(ShaderMask), findsOneWidget);
    });

    testWidgets('and arrives when a list grows into one that scrolls', (
      tester,
    ) async {
      // The fleet landing turns a one-row screen into a list, without anyone
      // touching the glass: the fade has to follow the content, not the pump.
      Widget listOf(int rows) =>
          WearScrollView(children: [for (var i = 0; i < rows; i++) _row(i)]);
      await _pumpFace(tester, listOf(1));
      expect(find.byType(ShaderMask), findsNothing);

      await _pumpFace(tester, listOf(12));

      expect(find.byType(ShaderMask), findsOneWidget);
    });
  });

  group("a scaling list (Wear OS's ScalingLazyColumn)", () {
    List<Widget> rows(int n) => [for (var i = 0; i < n; i++) _row(i)];

    test('scale and alpha are its defaults at its own reference points', () {
      // An item 20% of the viewport tall puts the scaling line at 35% from the
      // edge (`minElementHeight`, `minTransitionArea`); the easing is symmetric,
      // so halfway to the edge is exactly halfway between full and edge size.
      const viewport = 200.0;
      const height = 40.0;
      ({double scale, double alpha}) bottomAt(double bottom) =>
          wearScaleAndAlpha(
            viewportHeight: viewport,
            itemTop: bottom - height,
            itemBottom: bottom,
          );
      expect(bottomAt(0.35 * viewport), (scale: 1.0, alpha: 1.0));
      final half = bottomAt(0.175 * viewport);
      expect(half.scale, moreOrLessEquals(0.85, epsilon: 1e-9));
      expect(half.alpha, moreOrLessEquals(0.75, epsilon: 1e-9));
      final edge = bottomAt(0);
      // `ScalingLazyColumnDefaults.scalingParams()`: edgeScale, edgeAlpha.
      expect(edge.scale, moreOrLessEquals(0.7, epsilon: 1e-9));
      expect(edge.alpha, moreOrLessEquals(0.5, epsilon: 1e-9));
    });

    for (final (face, logical) in [
      (wearFaceSmall, 192.0),
      (wearFaceLarge, 225.0),
    ]) {
      testWidgets('on a ${logical.round()} dp face no row is drawn below 70% '
          'and the rows stay packed', (tester) async {
        await _pumpFace(
          tester,
          WearScrollView(curved: true, children: rows(12)),
          face: face,
        );
        final full = tester
            .renderObject<RenderBox>(find.byKey(const ValueKey('row-0')))
            .size;

        var checked = 0;
        for (var step = 0; step < 16; step++) {
          Rect? previous;
          for (var i = 0; i < 12; i++) {
            final row = find.byKey(ValueKey('row-$i'));
            if (row.evaluate().isEmpty) {
              previous = null;
              continue;
            }
            final rect = tester.getRect(row);
            expect(
              rect.height,
              greaterThanOrEqualTo(full.height * 0.7 - 1e-6),
              reason: 'row $i after $step drags',
            );
            // Shrinking pulls each row against its neighbour nearer the
            // middle, so the list never opens gaps as it scrolls.
            if (previous != null) {
              expect(
                rect.top,
                moreOrLessEquals(previous.bottom, epsilon: 0.5),
                reason: 'rows ${i - 1} and $i after $step drags',
              );
            }
            previous = rect;
            checked++;
          }
          await tester.drag(find.byType(WearScrollView), const Offset(0, -30));
          await tester.pumpAndSettle();
        }
        expect(checked, greaterThan(40));
      });
    }

    testWidgets('starts with the second item in the middle, and the last one '
        'can reach it too (AutoCenteringParams)', (tester) async {
      await _pumpFace(tester, WearScrollView(curved: true, children: rows(12)));
      const middle = 225.0 / 2;
      expect(
        tester.getCenter(find.byKey(const ValueKey('row-1'))).dy,
        moreOrLessEquals(middle, epsilon: 1),
      );

      // Twice: the space after the last item is measured once that item is
      // laid out — in Compose too it is 0 until the last item is visible — and
      // one 2000 px jump arrives at the old end before it is.
      for (var i = 0; i < 2; i++) {
        await tester.drag(find.byType(WearScrollView), const Offset(0, -2000));
        await tester.pumpAndSettle();
      }
      expect(
        tester.getCenter(find.byKey(const ValueKey('row-11'))).dy,
        moreOrLessEquals(middle, epsilon: 1),
      );
    });

    testWidgets('a gap is spacing, not an item: it is not what gets centred', (
      tester,
    ) async {
      await _pumpFace(
        tester,
        WearScrollView(
          curved: true,
          children: [
            _row(0),
            const SizedBox(height: 8),
            _row(1),
            ...[for (var i = 2; i < 12; i++) _row(i)],
          ],
        ),
      );
      expect(
        tester.getCenter(find.byKey(const ValueKey('row-1'))).dy,
        moreOrLessEquals(225.0 / 2, epsilon: 1),
      );
    });

    testWidgets('paints, hit-tests and describes the size it shrinks to', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final tapped = <int>[];
      await _pumpFace(
        tester,
        WearScrollView(
          curved: true,
          children: [
            for (var i = 0; i < 12; i++)
              Semantics(
                container: true,
                label: 'row $i',
                child: GestureDetector(
                  onTap: () => tapped.add(i),
                  // Composited, so the list's transform is a layer this
                  // test can read rather than a canvas call it cannot.
                  child: RepaintBoundary(child: _row(i)),
                ),
              ),
          ],
        ),
      );
      await tester.drag(find.byType(WearScrollView), const Offset(0, -60));
      await tester.pumpAndSettle();

      var shrunk = 0;
      for (var i = 0; i < 12; i++) {
        final row = find.byKey(ValueKey('row-$i'));
        if (row.evaluate().isEmpty) continue;
        final drawn = tester.getRect(row);
        final full = tester.renderObject<RenderBox>(row).size.width;

        Layer? layer = tester
            .renderObject(
              find
                  .ancestor(of: row, matching: find.byType(RepaintBoundary))
                  .first,
            )
            .debugLayer;
        while (layer != null && layer is! TransformLayer) {
          layer = layer.parent;
        }
        final painted = (layer! as TransformLayer).transform!.storage[0];
        expect(
          painted * full,
          moreOrLessEquals(drawn.width, epsilon: 0.5),
          reason: 'row $i painted',
        );

        final node = tester.getSemantics(row);
        var described = node.rect;
        for (SemanticsNode? n = node; n != null; n = n.parent) {
          if (n.transform case final transform?) {
            described = MatrixUtils.transformRect(transform, described);
          }
        }
        expect(
          described.width / tester.view.devicePixelRatio,
          moreOrLessEquals(drawn.width, epsilon: 0.5),
          reason: 'row $i described',
        );

        if (drawn.width < full - 1 && drawn.top > 0 && drawn.bottom < 225) {
          shrunk++;
          tapped.clear();
          await tester.tapAt(drawn.center);
          expect(tapped, [i], reason: 'a tap on row $i where it is drawn');
        }
      }
      expect(shrunk, greaterThan(0), reason: 'a sweep with no scaling in it');
      handle.dispose();
    });
  });

  testWidgets('a square face gets its corners back', (tester) async {
    await _pumpFace(
      tester,
      WearScrollView(children: [for (var i = 0; i < 12; i++) _row(i)]),
      shape: WearShape.square,
    );
    final square = tester.getRect(find.byKey(const ValueKey('row-0')));

    await _pumpFace(
      tester,
      WearScrollView(children: [for (var i = 0; i < 12; i++) _row(i)]),
    );
    final round = tester.getRect(find.byKey(const ValueKey('row-0')));

    // Nothing to dodge on a square display, so the row is wider and starts
    // higher than the circle allows.
    expect(square.width, greaterThan(round.width));
    expect(square.top, lessThan(round.top));
  });
}
