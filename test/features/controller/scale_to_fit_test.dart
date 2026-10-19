import 'package:bambuddy_mobile/features/controller/scale_to_fit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Size room, {double maxScale = 2}) => MaterialApp(
  home: Center(
    child: SizedBox.fromSize(
      size: room,
      child: ScaleToFit(
        minSize: const Size(100, 50),
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
    final content = find.byKey(const Key('content'));

    testWidgets('fills a bigger room, laid out at the room over the factor', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const Size(300, 100)));

      // The factor is 2 (the height decides), so the content is laid out at
      // 150x50 and painted over the whole room.
      expect(tester.getSize(content), const Size(150, 50));
      expect(tester.getRect(content).size, const Size(300, 100));
    });

    testWidgets('stops at the cap, and still fills the room', (tester) async {
      await tester.pumpWidget(_host(const Size(600, 300), maxScale: 1.5));

      expect(tester.getSize(content), const Size(400, 200));
      expect(tester.getRect(content).size, const Size(600, 300));
    });

    testWidgets('is never laid out under its minimum, it shrinks instead', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const Size(50, 100)));

      expect(tester.getSize(content), const Size(100, 200));
      expect(tester.getRect(content).size, const Size(50, 100));
    });

    testWidgets('tells what is under it the factor it is drawn at', (
      tester,
    ) async {
      double? seen;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox.fromSize(
              size: const Size(300, 100),
              child: ScaleToFit(
                minSize: const Size(100, 50),
                child: Builder(
                  builder: (context) {
                    seen = ControllerScale.of(context);
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        ),
      );

      expect(seen, 2);
    });

    testWidgets('is 1 where nothing scales', (tester) async {
      double? seen;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            seen = ControllerScale.of(context);
            return const SizedBox();
          },
        ),
      );

      expect(seen, 1);
    });

    testWidgets('lays out a larger system font in a box that grows with it', (
      tester,
    ) async {
      // At 1.5x text the minimum is 1.5x: the child gets the room its bigger
      // words need, and the whole is fitted back into the room it was given.
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(_host(const Size(100, 50)));

      expect(tester.getSize(content), const Size(150, 75), reason: 'laid out');
      expect(tester.getRect(content).size.width, closeTo(100, 0.01));
    });
  });
}
