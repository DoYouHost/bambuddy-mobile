import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// The behaviour `test/helpers.dart` promises and `docs/test-harness.md`
/// explains: a fake that quietly stopped doing it would make other tests pass
/// for the wrong reason.
void main() {
  group('RequestLog', () {
    test(
      'logs a request no mocked route matches, and it still fails',
      () async {
        final dio = testDio();
        mockServer(dio);
        final log = captureRequests(dio);

        await expectLater(
          dio.get<dynamic>('/nobody-mocked-this'),
          throwsA(isA<DioException>()),
        );

        expect(log.calls, ['GET /nobody-mocked-this']);
        expect(log.statuses, [
          null,
        ], reason: 'no route means no response at all');
      },
    );

    test('records the status of an answer next to the request', () async {
      final dio = testDio();
      mockServer(dio).onGet('/ok', (s) => s.reply(200, {'a': 1}));
      final log = captureRequests(dio);

      await dio.get<dynamic>('/ok');

      expect(log.calls, ['GET /ok']);
      expect(log.statuses, [200]);
    });

    test('untilCount returns on its deadline instead of throwing', () async {
      final log = RequestLog();
      await log.untilCount(3, turns: 5);
      expect(log.statuses, isEmpty);
    });

    test('untilCount counts answers, not requests on their way out', () async {
      final dio = testDio();
      mockServer(dio).onGet('/ok', (s) => s.reply(200, null));
      final log = captureRequests(dio);

      final pending = dio.get<dynamic>('/ok');
      await log.untilCount(1);
      // Straight after: a request is logged on its way out, its status only once
      // the answer is back, so waiting on the former would return too early.
      expect(log.statuses, hasLength(1));
      await pending;
    });
  });

  group('ScriptedAdapter', () {
    ResponseBody ok(String body) => ResponseBody.fromString(body, 200);

    test(
      'the last step answers every request past the end of the script',
      () async {
        final adapter = ScriptedAdapter.script([
          (_) => ok('first'),
          (_) => ok('last'),
        ]);
        final dio = testDio()..httpClientAdapter = adapter;

        final answers = [
          for (var i = 0; i < 4; i++)
            (await dio.get<String>(
              '/x',
              options: Options(responseType: ResponseType.plain),
            )).data,
        ];

        expect(answers, ['first', 'last', 'last', 'last']);
        expect(adapter.requests, hasLength(4));
      },
    );

    test('a DioException step is thrown, as a transport failure is', () async {
      final adapter = ScriptedAdapter(
        (options) => DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        ),
      );
      final dio = testDio()..httpClientAdapter = adapter;

      await expectLater(
        dio.get<dynamic>('/x'),
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.connectionTimeout,
          ),
        ),
      );
    });
  });

  group('FakeTimer', () {
    test('fires its callback once, unless cancelled first', () {
      var fired = 0;
      final live = FakeTimer(const Duration(seconds: 3), () => fired++)..fire();
      final dead = FakeTimer(const Duration(seconds: 3), () => fired++)
        ..cancel()
        ..fire();

      expect(fired, 1);
      expect(live.duration, const Duration(seconds: 3));
      expect(dead.isActive, isFalse);
    });
  });

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

  testWithClock(
    'testWithClock moves the ambient clock by hand',
    DateTime.utc(2026, 1, 1),
    (time) {
      expect(clock.now(), DateTime.utc(2026, 1, 1));
      time.tick(const Duration(minutes: 5));
      expect(clock.now(), DateTime.utc(2026, 1, 1, 0, 5));
    },
  );

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
