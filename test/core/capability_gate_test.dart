import 'dart:async';

import 'package:bambuddy_mobile/core/api/observed_capability.dart';
import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// A version service whose every read waits for the test to answer it, and
/// which records the forgotten failures a regained contact asks for.
class _ScriptedVersion extends ServerVersionService {
  _ScriptedVersion() : super(Dio());

  final reads = <Completer<ServerVersion?>>[];
  var forgotten = 0;

  @override
  Future<ServerVersion?> current() {
    final read = Completer<ServerVersion?>();
    reads.add(read);
    return read.future;
  }

  @override
  void forgetFailure() => forgotten++;
}

/// A 1.2.6 row, so `1.2.5.1` is the older contract and `1.2.6` the newer.
const _feature = ServerFeature.crossModelVariants;
final _older = ServerVersion.tryParse('1.2.5.1');
final _newer = ServerVersion.tryParse('1.2.6');

void main() {
  late _ScriptedVersion version;
  late ProviderContainer container;

  setUp(() {
    version = _ScriptedVersion();
    container = ProviderContainer(
      overrides: [
        fakeServerProfileOverride(),
        serverVersionServiceProvider.overrideWithValue(version),
      ],
    );
    addTearDown(container.dispose);
  });

  /// [gate] as a screen holds it, plus every value it has published since.
  List<AsyncValue<bool>> listen(Provider<AsyncValue<bool>> gate) {
    final seen = <AsyncValue<bool>>[];
    container.listen(gate, (_, next) => seen.add(next), fireImmediately: true);
    return seen;
  }

  Future<void> answerVersion(ServerVersion? answer) async {
    version.reads.last.complete(answer);
    await pumpEventQueue();
  }

  void bump() => container.read(serverContactEpochProvider.notifier).bump();

  group('versioned latch', () {
    late ObservedCapability latch;
    late Provider<AsyncValue<bool>> gate;

    setUp(() {
      latch = ObservedCapability(_feature, version);
      gate = capabilityGate((_) => latch);
    });

    test('does not settle to "off" while the version is in flight', () async {
      final seen = listen(gate);
      await pumpEventQueue();

      expect(seen, [const AsyncLoading<bool>()]);

      await answerVersion(_newer);
      expect(seen.last, const AsyncData(true));
    });

    test('once the version is known, a new reader answers at once', () async {
      listen(gate);
      await answerVersion(_newer);

      final late = capabilityGate((_) => ObservedCapability(_feature, version));
      expect(container.read(late), const AsyncData(true));
    });

    test('an observation outranks the version and reaches the gate', () async {
      final seen = listen(gate);
      await answerVersion(_older);
      expect(seen.last, const AsyncData(false));

      latch.observe(present: true);
      await pumpEventQueue();

      expect(seen.last, const AsyncData(true));
    });

    test('a refusal reads false whatever the version says', () async {
      final seen = listen(gate);
      await answerVersion(_newer);

      latch.observeRefusal();
      await pumpEventQueue();

      expect(seen.last, const AsyncData(false));
    });

    test(
      'a failed read answers whenUnknown; regained contact asks again',
      () async {
        final seen = listen(gate);
        await answerVersion(null);
        expect(seen.last, const AsyncData(false));

        bump();
        await pumpEventQueue();
        expect(version.forgotten, 1);
        expect(
          seen.last,
          const AsyncData(false),
          reason: 'the old answer stays up while the version is re-read',
        );

        await answerVersion(_newer);
        expect(seen.last, const AsyncData(true));
      },
    );

    test('re-deriving the same answer publishes nothing', () async {
      final seen = listen(gate);
      await answerVersion(_newer);
      final published = seen.length;

      bump();
      await pumpEventQueue();
      await answerVersion(_newer);

      expect(seen, hasLength(published));
    });

    test(
      'whenUnknown: true shows the control while the version is in flight',
      () async {
        // Heater history: the glyph must be in the tile's first frame, or the
        // label beside it shifts when the version lands.
        final shown = capabilityGate(
          (_) => ObservedCapability(_feature, version, whenUnknown: true),
        );
        final seen = listen(shown);
        await pumpEventQueue();
        expect(seen, [const AsyncData(true)]);

        await answerVersion(_older);
        expect(seen.last, const AsyncData(false));
      },
    );
  });

  test('unversioned, no probe: whenUnknown at once', () {
    expect(
      container.read(capabilityGate((_) => ObservedCapability.unversioned())),
      const AsyncData(true),
    );
  });

  group('probe-backed latch', () {
    late ObservedCapability latch;
    late Provider<AsyncValue<bool>> gate;
    late List<Completer<void>> probes;

    setUp(() {
      probes = [];
      latch = ObservedCapability.unversioned(
        whenUnknown: false,
        probe: () {
          final reply = Completer<void>();
          probes.add(reply);
          return latch.watching(() => reply.future);
        },
      );
      gate = capabilityGate((_) => latch);
    });

    Future<void> failProbe() async {
      probes.last.completeError(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionError,
        ),
      );
      await pumpEventQueue();
    }

    test('loading while the probe is out, then its answer', () async {
      final seen = listen(gate);
      expect(seen, [const AsyncLoading<bool>()]);
      expect(probes, hasLength(1));

      probes.single.complete();
      await pumpEventQueue();

      expect(seen.last, const AsyncData(true));
    });

    test(
      'no answer settles on whenUnknown and is asked once per regained contact',
      () async {
        final seen = listen(gate);
        await failProbe();

        expect(seen.last, const AsyncData(false));
        expect(probes, hasLength(1), reason: 'the rebuild must not re-probe');

        bump();
        await pumpEventQueue();
        expect(probes, hasLength(2));
        expect(seen.last, const AsyncData(false), reason: 'no blink meanwhile');

        probes.last.complete();
        await pumpEventQueue();
        expect(seen.last, const AsyncData(true));
      },
    );
  });

  group('and', () {
    const loading = AsyncLoading<bool>();
    const yes = AsyncData(true);
    const no = AsyncData(false);
    final broken = AsyncError<bool>(StateError('schema'), StackTrace.empty);

    test('a settled "no" is final even while the other side loads', () {
      expect(no.and(loading), no);
      expect(loading.and(no), no);
      expect(broken.and(no), no);
    });

    test('both "yes" is yes; anything unanswered is loading', () {
      expect(yes.and(yes), yes);
      expect(yes.and(loading), loading);
    });

    test('an error is handed on, and settledGate ends on it', () async {
      expect(yes.and(broken), broken);
      expect(broken.and(loading), broken);

      final gate = Provider<AsyncValue<bool>>((_) => yes.and(broken));
      await expectLater(
        settledGate(container, gate),
        throwsA(isA<StateError>()),
      );
    });
  });
}
