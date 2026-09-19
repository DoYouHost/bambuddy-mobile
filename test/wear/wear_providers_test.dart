import 'dart:async';

import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/wear/wear_fleet_cache.dart';
import 'package:bambuddy_mobile/wear/wear_providers.dart';
import 'package:bambuddy_mobile/wear/wear_transport.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../helpers/fake_watch_connectivity.dart';

import '../helpers.dart';

void main() {
  test('wearTransportProvider survives being only read '
      '(autoDispose killed the reply listener mid-request)', () async {
    final container = ProviderContainer(
      overrides: [
        watchConnectivityProvider.overrideWithValue(FakeWatchConnectivity()),
        noServerProfileOverride,
      ],
    );
    addTearDown(container.dispose);

    final first = container.read(wearTransportProvider);
    // With autoDispose an unlistened provider is torn down right here —
    // cancelling the relay's reply subscription while a call is in flight.
    await pumpEventQueue();
    final second = container.read(wearTransportProvider);

    expect(identical(first, second), isTrue);
  });

  group('a rebuild is not a dispose', () {
    late int polls;

    setUp(() => polls = 0);

    ProviderContainer containerWith(
      _CountingTransport transport,
      ServerProfileNotifier profile, {
      WearFleetCache cache = const _NoCache(),
    }) {
      final container = ProviderContainer(
        overrides: [
          serverProfileProvider.overrideWith(() => profile),
          wearFleetCacheProvider.overrideWithValue(cache),
          wearTransportProvider.overrideWithValue(
            HybridWearTransport.restOnly(transport),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    /// The zero-length timer `build` arms over a cached frame, plus whatever
    /// the poll behind it does.
    void settle(FakeAsync async) {
      async.flushMicrotasks();
      async.elapse(Duration.zero);
      async.flushMicrotasks();
    }

    test('the poll after a rebuild still reaches the screen', () {
      fakeAsync((async) {
        final transport = _CountingTransport(() => polls++);
        final profile = _RebuildableProfile();
        final container = containerWith(
          transport,
          profile,
          cache: const _StaleCache(),
        );
        final sub = container.listen(wearFleetProvider, (_, _) {});
        addTearDown(sub.close);
        settle(async);
        expect(polls, 1);
        expect(container.read(wearFleetProvider).requireValue.stale, isFalse);

        // What the watch does on every launch: the phone pushes the config it
        // is already running, the watch adopts it, and the profile is re-read.
        // Riverpod keeps the notifier across that and runs `onDispose` anyway,
        // so a one-way latch left every later poll answering into nothing — a
        // cached frame dimmed forever, waiting for a state that never came.
        profile.rebuild();
        settle(async);

        expect(polls, 2, reason: 'the rebuild polls');
        expect(
          container.read(wearFleetProvider).requireValue.stale,
          isFalse,
          reason: 'and its answer is what is on screen',
        );
        async.elapse(const Duration(seconds: 6));
        expect(polls, 3, reason: 'and the cadence survived the rebuild');

        container.read(wearFleetProvider.notifier).stopPolling();
        async.elapse(const Duration(minutes: 5));
      });
    });

    test('a rebuild in the background does not restart the poll', () {
      fakeAsync((async) {
        final transport = _CountingTransport(() => polls++);
        final profile = _RebuildableProfile();
        final container = containerWith(
          transport,
          profile,
          cache: const _StaleCache(),
        );
        final sub = container.listen(wearFleetProvider, (_, _) {});
        addTearDown(sub.close);
        settle(async);
        expect(polls, 1);

        // Screen off — and the phone's own launch pushes a config at it, which
        // rebuilds this provider. Waking the bridge for a dark face is the one
        // thing `stopPolling` exists to prevent.
        container.read(wearFleetProvider.notifier).stopPolling();
        profile.rebuild();
        settle(async);
        async.elapse(const Duration(minutes: 5));
        expect(polls, 1, reason: 'nothing polls behind a screen that is off');

        // Back on the wrist.
        unawaited(container.read(wearFleetProvider.notifier).refresh());
        async.flushMicrotasks();
        expect(polls, 2);

        container.read(wearFleetProvider.notifier).stopPolling();
        async.elapse(const Duration(minutes: 5));
      });
    });

    test('a refresh cannot outrun a rebuild either', () {
      fakeAsync((async) {
        final transport = _CountingTransport(() => polls++);
        final profile = _RebuildableProfile();
        // No cache, which is what a switch to a server this watch has never
        // polled leaves `build` with: it fetches, and that fetch is what the
        // frame will be.
        final container = containerWith(transport, profile);
        final sub = container.listen(wearFleetProvider, (_, _) {});
        addTearDown(sub.close);
        async.flushMicrotasks();
        expect(polls, 1);

        transport.hold = true;
        profile.rebuild();
        settle(async);
        expect(polls, 2, reason: 'the rebuild fetch, still out');

        // The two kinds of rebuild do not look alike from here: an invalidate
        // drops the value, a dependency change keeps it and only marks the
        // state reloading. Reading the missing value would wave this one
        // through, and its frame would then be overwritten by the build's.
        unawaited(container.read(wearFleetProvider.notifier).refresh());
        async.flushMicrotasks();
        expect(polls, 2, reason: 'it gives way to the build already running');

        transport.release();
        async.flushMicrotasks();
        expect(container.read(wearFleetProvider).hasValue, isTrue);

        container.read(wearFleetProvider.notifier).stopPolling();
        async.elapse(const Duration(minutes: 5));
      });
    });

    test('a refresh cannot outrun the first build', () {
      fakeAsync((async) {
        final transport = _CountingTransport(() => polls++)..hold = true;
        final container = containerWith(transport, _RebuildableProfile());
        final sub = container.listen(wearFleetProvider, (_, _) {});
        addTearDown(sub.close);
        async.flushMicrotasks();
        expect(polls, 1, reason: 'the build fetch, still out');

        // The resume hook fires while the relay is still waiting on a phone
        // booting its engine — which it is given 15 s for. Whatever this poll
        // put on screen would be wiped the moment the build's own fetch
        // answered: Riverpod assigns what `build` returns, error included.
        unawaited(container.read(wearFleetProvider.notifier).refresh());
        async.flushMicrotasks();
        expect(polls, 1, reason: 'the frame it would win is not its own');

        transport.release();
        async.flushMicrotasks();
        expect(container.read(wearFleetProvider).hasValue, isTrue);

        container.read(wearFleetProvider.notifier).stopPolling();
        async.elapse(const Duration(minutes: 5));
      });
    });
  });

  group('the poll stops while the watch app is in the background', () {
    /// Counts polls and answers at once, so the only thing pacing them is the
    /// notifier's own timer.
    late int polls;

    ProviderContainer containerWith(_CountingTransport transport) {
      final container = ProviderContainer(
        overrides: [
          fakeServerProfileOverride(),
          wearFleetCacheProvider.overrideWithValue(const _NoCache()),
          wearTransportProvider.overrideWithValue(
            HybridWearTransport.restOnly(transport),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    setUp(() => polls = 0);

    test('stopPolling stops the ticks, refresh brings them back', () {
      fakeAsync((async) {
        final transport = _CountingTransport(() => polls++);
        final container = containerWith(transport);
        final sub = container.listen(wearFleetProvider, (_, _) {});
        addTearDown(sub.close);
        async.flushMicrotasks();

        expect(polls, 1, reason: 'the build fetch');

        // Two ticks of the idle cadence.
        async.elapse(const Duration(seconds: 11));
        expect(polls, 3);

        // Screen off: every further tick would wake the phone over Bluetooth
        // for a face nobody is looking at.
        container.read(wearFleetProvider.notifier).stopPolling();
        async.elapse(const Duration(minutes: 5));
        expect(polls, 3, reason: 'not one poll while backgrounded');

        // Back on the wrist.
        unawaited(container.read(wearFleetProvider.notifier).refresh());
        async.flushMicrotasks();
        expect(polls, 4);
        async.elapse(const Duration(seconds: 6));
        expect(polls, 5, reason: 'the cadence is running again');

        container.read(wearFleetProvider.notifier).stopPolling();
        async.elapse(const Duration(minutes: 5));
      });
    });

    test('a failed poll against a frame on screen backs off to 30 s', () {
      fakeAsync((async) {
        final transport = _CountingTransport(() => polls++);
        final container = containerWith(transport);
        final sub = container.listen(wearFleetProvider, (_, _) {});
        addTearDown(sub.close);
        async.flushMicrotasks();
        expect(polls, 1);

        // From here every poll fails, with last run's fleet still drawn.
        transport.fail = true;
        async.elapse(const Duration(seconds: 6));
        expect(polls, 2, reason: 'the tick that was already armed');

        // Before the cold-start cache a failed first fetch left the provider in
        // its error state and nothing rescheduled, so an unreachable phone cost
        // nothing. Keeping the frame keeps the timer, so it has to slow down:
        // 5 s of retries only wakes the bridge for an answer not coming.
        async.elapse(const Duration(seconds: 20));
        expect(polls, 2, reason: 'no 5 s retry while the frame stands');
        async.elapse(const Duration(seconds: 11));
        expect(polls, 3, reason: 'one retry a half-minute later');

        container.read(wearFleetProvider.notifier).stopPolling();
        async.elapse(const Duration(minutes: 5));
      });
    });

    test('a manual refresh takes the armed tick with it', () {
      fakeAsync((async) {
        final transport = _CountingTransport(() => polls++);
        final container = containerWith(transport);
        final sub = container.listen(wearFleetProvider, (_, _) {});
        addTearDown(sub.close);
        async.flushMicrotasks();
        expect(polls, 1);

        // Four seconds into the five-second tick, the user pulls to refresh and
        // the relay sits on the request — a phone booting its engine is given
        // 15 s. The tick left armed would mature a second later and put an
        // identical RPC on the same bridge.
        async.elapse(const Duration(seconds: 4));
        transport.hold = true;
        unawaited(container.read(wearFleetProvider.notifier).refresh());
        async.flushMicrotasks();
        expect(polls, 2, reason: 'the manual one');

        async.elapse(const Duration(seconds: 3));
        expect(polls, 2, reason: 'the armed tick was taken down with it');

        transport.release();
        async.flushMicrotasks();
        container.read(wearFleetProvider.notifier).stopPolling();
        async.elapse(const Duration(minutes: 5));
      });
    });

    test('a fetch still in flight when the app leaves does not re-arm', () {
      fakeAsync((async) {
        final transport = _CountingTransport(() => polls++);
        final container = containerWith(transport);
        final sub = container.listen(wearFleetProvider, (_, _) {});
        addTearDown(sub.close);
        async.flushMicrotasks();
        expect(polls, 1);

        // A poll goes out, and the app is backgrounded before it lands — the
        // ordering `_scheduleNext` has to survive, or the reply re-arms the
        // timer the pause just cancelled.
        transport.hold = true;
        async.elapse(const Duration(seconds: 6));
        expect(polls, 2);
        container.read(wearFleetProvider.notifier).stopPolling();
        transport.release();
        async.flushMicrotasks();

        async.elapse(const Duration(minutes: 5));
        expect(polls, 2, reason: 'the late reply must not restart the poll');
      });
    });
  });
}

/// Answers every poll with one printer, counting the calls. [hold] parks the
/// next answer so a test can background the app mid-fetch.
class _CountingTransport implements WearTransport {
  _CountingTransport(this.onCall);

  final void Function() onCall;
  bool hold = false;
  bool fail = false;
  Completer<void>? _held;

  void release() {
    _held?.complete();
    _held = null;
    hold = false;
  }

  @override
  Future<WearFleet> getFleet() async {
    onCall();
    if (fail) throw WearRelayUnreachable();
    if (hold) {
      _held = Completer<void>();
      await _held!.future;
    }
    return wearFleetFromJson(const {
      'printers': [
        {
          'printer': {'id': 1, 'name': 'X1C'},
          'status': {'id': 1, 'connected': true},
        },
      ],
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}

/// A profile that answers with the same server every time — but as a new
/// instance, which is what a re-read costs and what rebuilds its dependents.
class _RebuildableProfile extends ServerProfileNotifier {
  @override
  ServerProfile? build() =>
      ServerProfile(baseUrl: fakeServerBaseUrl, authMode: AuthMode.none);

  /// What adopting a pushed config does.
  void rebuild() => ref.invalidateSelf();
}

/// Last run's fleet, so `build` takes the cold-start path: a dimmed frame that
/// only a landed poll can clear.
class _StaleCache implements WearFleetCache {
  const _StaleCache();

  @override
  WearFleet? load(ServerProfile? profile) => wearFleetFromJson(const {
    'printers': [
      {
        'printer': {'id': 1, 'name': 'X1C'},
        'status': {'id': 1, 'connected': true},
      },
    ],
  }, stale: true);

  @override
  Future<void> save(WearFleet fleet, ServerProfile? profile) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}

/// No cold-start cache, so `build` takes the fetching path these tests pace.
class _NoCache implements WearFleetCache {
  const _NoCache();

  @override
  WearFleet? load(ServerProfile? profile) => null;

  @override
  Future<void> save(WearFleet fleet, ServerProfile? profile) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}
