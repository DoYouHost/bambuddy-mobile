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

  group('the poll stops while the watch app is in the background', () {
    /// Counts polls and answers at once, so the only thing pacing them is the
    /// notifier's own timer.
    late int polls;

    ProviderContainer containerWith(_CountingTransport transport) {
      final container = ProviderContainer(
        overrides: [
          fakeServerProfileOverride(),
          wearFleetCacheProvider.overrideWithValue(_NoCache()),
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
  Completer<void>? _held;

  void release() {
    _held?.complete();
    _held = null;
    hold = false;
  }

  @override
  Future<WearFleet> getFleet() async {
    onCall();
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

/// No cold-start cache, so `build` takes the fetching path these tests pace.
class _NoCache implements WearFleetCache {
  @override
  WearFleet? load(ServerProfile? profile) => null;

  @override
  Future<void> save(WearFleet fleet, ServerProfile? profile) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}
