import 'package:bambuddy_mobile/wear/wear_shape.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// The one platform fact the watch layout stands on. Everything that can go
/// wrong with it has to end up round: that is the stricter geometry, so a wrong
/// answer costs some width, while the opposite mistake is what Google Play
/// rejected the build for.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  void answer(Object? Function() reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(wearShapeChannel, (call) async {
      calls.add(call);
      return reply();
    });
  }

  setUp(() => calls = []);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(wearShapeChannel, null);
  });

  group('WearShapeQuery', () {
    test('a round display is a round face', () async {
      answer(() => true);

      expect(await const WearShapeQuery().read(), WearShape.round);
      expect(calls.single.method, 'isScreenRound');
    });

    test('a display that is not round is a square face', () async {
      answer(() => false);

      expect(await const WearShapeQuery().read(), WearShape.square);
    });

    test('no answer at all is treated as round', () async {
      answer(() => null);

      expect(await const WearShapeQuery().read(), WearShape.round);
    });

    test('a platform without the channel is round', () async {
      // No handler registered: what a plain `flutter test` process looks like,
      // and what any host that never implemented the channel would do.
      expect(await const WearShapeQuery().read(), WearShape.round);
    });

    test('a channel that fails is round', () async {
      answer(() => throw PlatformException(code: 'no-activity'));

      expect(await const WearShapeQuery().read(), WearShape.round);
    });
  });

  group('WearShapeScope', () {
    testWidgets('hands the platform answer to everything below it',
        (tester) async {
      answer(() => false);
      late WearShape seen;

      await tester.pumpWidget(WearShapeScope(
        child: Builder(builder: (context) {
          seen = wearShapeOf(context);
          return const SizedBox();
        }),
      ));
      await tester.pumpAndSettle();

      expect(seen, WearShape.square);
    });

    testWidgets('a widget with no scope above it reads round', (tester) async {
      late WearShape seen;

      await tester.pumpWidget(Builder(builder: (context) {
        seen = wearShapeOf(context);
        return const SizedBox();
      }));

      expect(seen, WearShape.round);
    });
  });
}
