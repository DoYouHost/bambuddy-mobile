import 'dart:async';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/observed_capability.dart';
import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;

  setUp(() {
    dio = testDio();
    adapter = DioAdapter(dio: dio);
  });

  ObservedCapability capability(String? version, {bool whenUnknown = false}) {
    if (version != null) {
      adapter.onGet(
        '/api/v1/updates/version',
        (s) => s.reply(200, {'version': version, 'repo': 'x/y'}),
      );
    }
    return ObservedCapability(
      // A 1.2.6 row, so `1.2.5.1` is the older contract and `1.2.6b1` the newer.
      ServerFeature.crossModelVariants,
      version == null ? null : ServerVersionService(dio),
      whenUnknown: whenUnknown,
    );
  }

  /// A request that fails the way Dio fails, so the wrapper sees what a
  /// repository sees.
  Future<T> refusing<T>(int status) => Future<T>.error(
    DioException(
      requestOptions: RequestOptions(path: '/x'),
      // badResponse, or `mapDioException` reads it as a transport failure
      // and no status reaches the mapping at all.
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: status,
      ),
    ),
  );

  test('with nothing seen it answers from the version table', () async {
    expect(await capability('1.2.5.1').supported, isFalse);
    // A beta of the cycle that introduced the feature counts as having it.
    expect(await capability('1.2.6b1').supported, isTrue);
  });

  test('no version service at all falls back to whenUnknown', () async {
    expect(await capability(null).supported, isFalse);
    expect(await capability(null, whenUnknown: true).supported, isTrue);
  });

  test('what was observed outranks the version, in both directions', () async {
    final older = capability('1.2.5.1')..observe(present: true);
    expect(await older.supported, isTrue);

    final newer = capability('1.2.6b1')..observe(present: false);
    expect(await newer.supported, isFalse);
  });

  test('a refusal outranks both, and a later reply clears it', () async {
    final cap = capability('1.2.6b1')..observeRefusal();
    expect(
      await cap.supported,
      isFalse,
      reason: 'the route is there, this session may not use it',
    );

    cap.observe(present: true);
    expect(
      await cap.supported,
      isTrue,
      reason: 'a reply that arrived says the refusal is over',
    );
  });

  test(
    'a route\'s own answer: 404 absent, 403 refused, the rest silent',
    () async {
      expect(
        await (capability('1.2.6b1')..observeFailure(404)).supported,
        isFalse,
      );
      expect(
        await (capability('1.2.6b1')..observeFailure(403)).supported,
        isFalse,
      );
      // 401, 5xx and no response at all say nothing about the route — pinning
      // either latch on them would disable a feature over a flaky network.
      for (final status in [null, 401, 500, 502]) {
        expect(
          await (capability('1.2.6b1')..observeFailure(status)).supported,
          isTrue,
          reason: 'status $status must leave the version reading standing',
        );
      }
    },
  );

  test('unversioned: offered until the route says otherwise', () async {
    expect(await ObservedCapability.unversioned().supported, isTrue);
    expect(
      await (ObservedCapability.unversioned()..observeFailure(404)).supported,
      isFalse,
    );
  });

  group('watching', () {
    test('an answer is the answer, and records the route as there', () async {
      final cap = capability('1.2.5.1');

      expect(await cap.watching(() async => 'ok'), 'ok');
      // The version said no; the reply outranks it.
      expect(await cap.supported, isTrue);
    });

    test('both statuses come back as the caller\'s answer', () async {
      for (final status in [404, 403]) {
        final cap = capability('1.2.6b1');

        expect(
          await cap.watching(
            () => refusing<List<int>>(status),
            absent: () => const [],
          ),
          isEmpty,
          reason: 'status $status still answers with `absent`',
        );
      }
    });

    test('by default a 404 answers without hiding the capability', () async {
      // The whole point of the default: most of these routes are addressed by
      // a row id, so a 404 is a stale id, and reading it as absence took the
      // feature away for the rest of the session.
      final cap = capability('1.2.6b1');

      expect(
        await cap.watching(
          () => refusing<List<int>>(404),
          absent: () => const [],
        ),
        isEmpty,
      );
      expect(
        await cap.supported,
        isTrue,
        reason: 'the version still answers; nothing was observed',
      );
    });

    test('a refusal is recorded whatever else is', () async {
      final cap = capability('1.2.6b1');

      expect(
        await cap.watching(
          () => refusing<List<int>>(403),
          absent: () => const [],
        ),
        isEmpty,
      );
      expect(await cap.supported, isFalse);
    });

    test('treat404AsAbsent is what lets a 404 settle it', () async {
      final cap = capability('1.2.6b1');

      expect(
        await cap.watching(
          () => refusing<List<int>>(404),
          absent: () => const [],
          observing: treat404AsAbsent,
        ),
        isEmpty,
      );
      expect(
        await cap.supported,
        isFalse,
        reason: 'this route looks no row up, so its 404 is the route',
      );
    });

    test('absentOn narrows it, so a refusal still reaches the user', () async {
      final cap = capability('1.2.6b1');

      expect(
        await cap.watching(
          () => refusing<String?>(404),
          absent: () => null,
          absentOn: const {404},
        ),
        isNull,
      );
      await expectLater(
        cap.watching(
          () => refusing<String?>(403),
          absent: () => null,
          absentOn: const {404},
        ),
        throwsA(isA<AuthException>()),
      );
      // And the refusal is still on the latch, whether or not it was thrown.
      expect(await cap.supported, isFalse);
    });

    test('with no answer to give, every failure throws mapped', () async {
      final cap = capability('1.2.6b1');

      await expectLater(
        cap.watching(() => refusing<String>(404)),
        throwsA(isA<AppApiException>()),
      );
      expect(
        await cap.supported,
        isTrue,
        reason: 'throwing it is not the same as concluding from it',
      );
    });

    test(
      'a failure that says nothing about the route throws and pins nothing',
      () async {
        final cap = capability('1.2.6b1');

        await expectLater(
          cap.watching(() => refusing<List<int>>(500), absent: () => const []),
          throwsA(isA<AppApiException>()),
          reason: 'a 500 is a fault to report, not an empty shelf',
        );
        expect(await cap.supported, isTrue);
      },
    );

    test(
      'anything that is not a Dio failure passes straight through',
      () async {
        final cap = capability('1.2.6b1');

        await expectLater(
          cap.watching<int>(() => throw StateError('parser')),
          throwsA(isA<StateError>()),
        );
      },
    );
  });

  group('change notification', () {
    (ObservedCapability, List<bool?>) listened() {
      final cap = ObservedCapability.unversioned();
      final heard = <bool?>[];
      cap.addListener(() => heard.add(cap.observedAnswer));
      return (cap, heard);
    }

    test('fires on a change of answer, and only then', () {
      // Queue payloads observe the calibration spelling on every fetch; an
      // unchanged answer must not rebuild every gate reading it.
      final (cap, heard) = listened();

      cap.observe(present: true);
      cap.observe(present: true);
      cap.observe(present: false);

      expect(heard, [true, false]);
    });

    test('a refusal is a change; a second one is not', () {
      final (cap, heard) = listened();

      cap.observe(present: true);
      cap.observeRefusal();
      cap.observeRefusal();

      expect(heard, [true, false]);
      expect(cap.observedAnswer, isFalse);
    });

    test('a removed listener hears nothing more', () {
      final (cap, heard) = listened();
      void other() => heard.add(null);
      cap.addListener(other);
      cap.removeListener(other);

      cap.observe(present: true);

      expect(heard, [true]);
    });

    test('an unversioned or version-less latch has no row to consult', () {
      expect(ObservedCapability.unversioned().feature, isNull);
      expect(capability(null).feature, isNull);
      expect(capability('1.2.6b1').feature, ServerFeature.crossModelVariants);
    });
  });

  group('probe', () {
    late ObservedCapability cap;
    late List<Completer<void>> sent;
    late int notified;

    /// A latch whose every probe waits for the test to answer it through
    /// [cap]'s own `watching`, as a repository's list call would.
    setUp(() {
      sent = [];
      notified = 0;
      cap = ObservedCapability.unversioned(
        whenUnknown: false,
        probe: () {
          final reply = Completer<void>();
          sent.add(reply);
          return cap.watching(() => reply.future, observing: treat404AsAbsent);
        },
      );
      cap.addListener(() => notified++);
    });

    Future<void> fail(Completer<void> probe, [int? status]) async {
      if (status == null) {
        probe.completeError(
          DioException(
            requestOptions: RequestOptions(path: '/x'),
            type: DioExceptionType.connectionError,
          ),
        );
      } else {
        probe.complete(refusing<void>(status));
      }
      await pumpEventQueue();
    }

    test('sends one probe while one is in flight', () {
      cap.probeIfUnknown(epoch: 0);
      cap.probeIfUnknown(epoch: 0);

      expect(sent, hasLength(1));
      expect(notified, 0, reason: 'nothing may notify from inside a build');
    });

    test('an answered probe settles the latch and notifies once', () async {
      cap.probeIfUnknown(epoch: 0);
      sent.single.complete();
      await pumpEventQueue();

      expect(cap.observedAnswer, isTrue);
      expect(cap.probeFailed, isFalse);
      expect(notified, 1);

      cap.probeIfUnknown(epoch: 1);
      expect(sent, hasLength(1), reason: 'an answer is never asked again');
    });

    test('a 404 is an answer too', () async {
      cap.probeIfUnknown(epoch: 0);
      await fail(sent.single, 404);

      expect(cap.observedAnswer, isFalse);
      expect(cap.probeFailed, isFalse);
    });

    test('an unanswered probe is not sent again at the same epoch', () async {
      // The loop this guards: a failed probe notifies, the gate rebuilds and
      // calls this again at the epoch it already failed at.
      cap.probeIfUnknown(epoch: 0);
      await fail(sent.single);

      expect(cap.probeFailed, isTrue);
      expect(cap.observedAnswer, isNull);
      expect(notified, 1);

      cap.probeIfUnknown(epoch: 0);
      expect(sent, hasLength(1));
    });

    test('a new epoch sends exactly one more', () async {
      cap.probeIfUnknown(epoch: 0);
      await fail(sent.single);

      cap.probeIfUnknown(epoch: 1);
      cap.probeIfUnknown(epoch: 1);
      expect(sent, hasLength(2));
      expect(
        cap.probeFailed,
        isTrue,
        reason: 'kept while the re-probe is out, so the gate does not blink',
      );

      await fail(sent.last);
      expect(notified, 1, reason: 'failing again changes nothing');

      cap.probeIfUnknown(epoch: 2);
      sent.last.complete();
      await pumpEventQueue();
      expect(cap.observedAnswer, isTrue);
      expect(cap.probeFailed, isFalse);
      expect(notified, 2);
    });

    test('a latch without a probe never sends one', () {
      final plain = ObservedCapability.unversioned();
      expect(plain.canProbe, isFalse);
      plain.probeIfUnknown(epoch: 0);
      expect(plain.probeFailed, isFalse);
    });
  });
}
