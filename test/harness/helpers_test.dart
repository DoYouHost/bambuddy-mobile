import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// The behaviour `test/helpers.dart` promises and `docs/test-harness.md`
/// explains: a fake that quietly stopped doing it would make other tests pass
/// for the wrong reason.
void main() {
  group('FakeWearTransport', () {
    test('commands leave out the reads, calls keep every one', () async {
      final transport = FakeWearTransport();

      await transport.getFleet();
      await transport.pause(1);
      await transport.getServerVersion();

      expect(transport.calls, ['getFleet', 'pause:1', 'getServerVersion']);
      expect(transport.commands, ['pause:1']);
    });

    test(
      'an error is thrown by every call, and the call is still logged',
      () async {
        final transport = FakeWearTransport(
          error: Exception('phone out of reach'),
        );

        expect(() => transport.stop(2), throwsException);
        expect(transport.calls, ['stop:2']);
      },
    );
  });

  group('expectOnGlass', () {
    Future<Finder> pumpBox(WidgetTester tester, Alignment at) async {
      await pumpWear(
        tester,
        Align(
          alignment: at,
          child: const SizedBox(key: Key('box'), width: 20, height: 20),
        ),
        wrapInApp: false,
      );
      return find.byKey(const Key('box'));
    }

    testWidgets('passes in the middle of the face', (tester) async {
      expectOnGlass(tester, await pumpBox(tester, Alignment.center));
    });

    testWidgets('fails for a box in the corner of the square, off the circle', (
      tester,
    ) async {
      final box = await pumpBox(tester, Alignment.bottomRight);
      expect(() => expectOnGlass(tester, box), throwsA(isA<TestFailure>()));
    });
  });
}
