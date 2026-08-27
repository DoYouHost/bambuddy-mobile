import 'package:bambuddy_mobile/wear/wear_shape.dart';
import 'package:bambuddy_mobile/wear/widgets/wear_scroll_indicator.dart';
import 'package:bambuddy_mobile/wear/widgets/wear_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Both layout rejections Google Play sent back live in this widget: content cut
/// off by the round bezel, and a scrollable screen with no scroll indicator.

/// Every corner of [rect] inside the glass of a round face [logical] dp across.
Matcher insideFace(double logical) => predicate<Rect>((rect) {
      final radius = logical / 2;
      final centre = Offset(radius, radius);
      return [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]
          .every((corner) => (corner - centre).distance <= radius);
    }, 'inside a ${logical.round()} dp round face');

/// Pumps [child] on a watch face, without the localizations and provider scope
/// [pumpWear] carries — this widget needs neither, and the tests below pump the
/// same tree twice with two different shapes.
Future<void> _pumpFace(WidgetTester tester, Widget child,
    {WearShape shape = WearShape.round, Size face = wearFaceLarge}) async {
  useWatchFace(tester, shape, face);
  await tester.pumpWidget(MaterialApp(
    // Keyed by shape: pumping a second face into the same tree would otherwise
    // update the existing scope instead of rebuilding it, and the shape is read
    // once, in initState.
    builder: (context, inner) =>
        WearShapeScope(key: ValueKey(shape), child: inner!),
    home: Scaffold(body: child),
  ));
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

      testWidgets('the viewport itself never reaches the bezel', (tester) async {
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

    testWidgets('the first row is inside the glass at the top of the scroll',
        (tester) async {
      await _pumpFace(
        tester,
        WearScrollView(children: [for (var i = 0; i < 12; i++) _row(i)]),
        face: face,
      );

      expect(tester.getRect(find.byKey(const ValueKey('row-0'))), inside);
    });

    testWidgets('and the last one is, at the bottom of it', (tester) async {
      await _pumpFace(
        tester,
        WearScrollView(children: [for (var i = 0; i < 12; i++) _row(i)]),
        face: face,
      );

      await tester.scrollUntilVisible(find.byKey(const ValueKey('row-11')), 60);
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byKey(const ValueKey('row-11'))), inside);
    });

    testWidgets('short content sits in the middle when asked to', (tester) async {
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

    testWidgets('comes back on a scroll and leaves again when it stops',
        (tester) async {
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
      expect(_indicator, findsNothing,
          reason: 'permanent chrome on a 1.4" face is a waste of it');
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

    testWidgets('and arrives when a list grows into one that scrolls',
        (tester) async {
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
