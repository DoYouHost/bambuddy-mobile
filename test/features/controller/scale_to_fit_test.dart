import 'package:bambuddy_mobile/features/controller/scale_to_fit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Size room, {double maxScale = 2, Size? design}) => MaterialApp(
  home: Center(
    child: SizedBox.fromSize(
      size: room,
      child: ScaleToFit(
        designSize: design ?? const Size(100, 50),
        maxScale: maxScale,
        child: const ColoredBox(key: Key('content'), color: Colors.red),
      ),
    ),
  ),
);

void main() {
  group('scaleFor', () {
    test('fits down into a room that is too small', () {
      expect(
        ScaleToFit.scaleFor(const Size(100, 50), const Size(50, 100), 2),
        0.5,
      );
    });

    test('grows into a room that is bigger, to the cap and no further', () {
      expect(
        ScaleToFit.scaleFor(const Size(100, 50), const Size(150, 100), 2),
        1.5,
      );
      expect(
        ScaleToFit.scaleFor(const Size(100, 50), const Size(900, 900), 2),
        2,
      );
    });

    test('the tighter side decides', () {
      expect(
        ScaleToFit.scaleFor(const Size(100, 50), const Size(400, 75), 3),
        1.5,
      );
    });

    test('a side without a bound leaves the other to decide', () {
      expect(
        ScaleToFit.scaleFor(
          const Size(100, 50),
          const Size(200, double.infinity),
          3,
        ),
        2,
      );
      expect(
        ScaleToFit.scaleFor(
          const Size(100, 50),
          const Size(double.infinity, double.infinity),
          3,
        ),
        1,
      );
    });
  });

  group('the widget', () {
    testWidgets('fills a bigger room, keeping the proportions', (tester) async {
      await tester.pumpWidget(_host(const Size(150, 150)));

      expect(
        tester.getRect(find.byKey(const Key('content'))).size,
        const Size(150, 75),
      );
    });

    testWidgets('stops at the cap', (tester) async {
      await tester.pumpWidget(_host(const Size(900, 900), maxScale: 1.5));

      expect(
        tester.getRect(find.byKey(const Key('content'))).size,
        const Size(150, 75),
      );
    });

    testWidgets('shrinks into a smaller room', (tester) async {
      await tester.pumpWidget(_host(const Size(50, 100)));

      expect(
        tester.getRect(find.byKey(const Key('content'))).size,
        const Size(50, 25),
      );
    });

    testWidgets('lays out a larger system font in a box that grows with it', (
      tester,
    ) async {
      // At 1.5x text the design box is 1.5x: the child gets the room its bigger
      // words need, and the whole is fitted back into the room it was given.
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(_host(const Size(100, 50)));

      final content = find.byKey(const Key('content'));
      expect(tester.getSize(content), const Size(150, 75), reason: 'laid out');
      expect(tester.getRect(content).size.width, closeTo(100, 0.01));
    });
  });
}
