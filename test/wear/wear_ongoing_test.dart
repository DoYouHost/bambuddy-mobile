import 'dart:async';
import 'dart:ui';

import 'package:bambuddy_mobile/core/format/datetime_format.dart';
import 'package:bambuddy_mobile/wear/screens/wear_home.dart';
import 'package:bambuddy_mobile/wear/wear_app.dart';
import 'package:bambuddy_mobile/wear/wear_fleet_cache.dart';
import 'package:bambuddy_mobile/wear/wear_ongoing.dart';
import 'package:bambuddy_mobile/wear/wear_providers.dart';
import 'package:bambuddy_mobile/wear/wear_transport.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Play's WO-V4: a print followed from the watch stays on the watch face as an
/// Ongoing Activity once the app leaves the screen.

Map<String, Object?> _printer(
  int id,
  String state, {
  num? progress,
  int? eta,
}) => {
  'printer': {'id': id, 'name': 'P$id'},
  'status': {
    'id': id,
    'name': 'P$id',
    'connected': true,
    'state': state,
    'current_print': 'job$id',
    'progress': ?progress,
    'remaining_time': ?eta,
  },
};

WearFleet _fleet(List<Map<String, Object?>> printers) =>
    wearFleetFromJson({'printers': printers});

final _formats = DateTimeFormats.outsideTree(const [Locale('pl')], true);
final _now = DateTime(2026, 10, 14, 12);

void main() {
  group('wearOngoingArgs', () {
    test('nothing running is nothing to show', () {
      expect(
        wearOngoingArgs(_fleet([_printer(1, 'IDLE')]), pl, _formats, _now),
        isNull,
      );
    });

    test('one print: its job, its percent, a countdown to its end', () {
      final args = wearOngoingArgs(
        _fleet([_printer(1, 'RUNNING', progress: 40, eta: 90)]),
        pl,
        _formats,
        _now,
      )!;
      expect(args['title'], 'job1');
      expect(args['body'], pl.notifOngoingBody(40, '13:30'));
      expect(args['chip'], '40%');
      expect(args['etaInMs'], 90 * 60000);
      expect(args['paused'], isFalse);
      expect(args['channelName'], pl.wearOngoingChannel);
    });

    test('several: the one that finishes first leads', () {
      final args = wearOngoingArgs(
        _fleet([
          _printer(1, 'RUNNING', progress: 10, eta: 300),
          _printer(2, 'PAUSE', progress: 80, eta: 20),
        ]),
        pl,
        _formats,
        _now,
      )!;
      expect(args['title'], pl.printingCount(2));
      expect(args['chip'], '80%');
      expect(args['paused'], isTrue, reason: 'the countdown freezes');
    });

    test('a preparing machine has no percent and no countdown', () {
      final args = wearOngoingArgs(
        _fleet([_printer(1, 'PREPARE', progress: 0, eta: 0)]),
        pl,
        _formats,
        _now,
      )!;
      expect(args['progress'], isNull);
      expect(args['chip'], isNull);
      expect(args['etaInMs'], isNull);
    });
  });

  group('the background poll', () {
    late int polls;
    late _Transport transport;

    ProviderContainer start({WearFleetCache cache = const _NoCache()}) {
      final container = ProviderContainer(
        overrides: [
          fakeServerProfileOverride(),
          wearFleetCacheProvider.overrideWithValue(cache),
          wearTransportProvider.overrideWithValue(
            HybridWearTransport.restOnly(transport),
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(wearFleetProvider, (_, _) {});
      addTearDown(sub.close);
      return container;
    }

    setUp(() {
      polls = 0;
      transport = _Transport(() => polls++);
    });

    test('runs every five minutes', () {
      fakeAsync((async) {
        transport.eta = 120;
        final container = start();
        async.flushMicrotasks();
        container.read(wearFleetProvider.notifier).pollInBackground();
        expect(polls, 1);

        async.elapse(const Duration(minutes: 4, seconds: 59));
        expect(polls, 1, reason: 'not the 5 s foreground cadence');
        async.elapse(const Duration(seconds: 2));
        expect(polls, 2);

        container.read(wearFleetProvider.notifier).stopPolling();
        async.elapse(const Duration(minutes: 30));
        expect(polls, 2);
      });
    });

    test('comes early when the print is due sooner', () {
      fakeAsync((async) {
        transport.eta = 2;
        final container = start();
        async.flushMicrotasks();
        container.read(wearFleetProvider.notifier).pollInBackground();

        async.elapse(const Duration(minutes: 2, seconds: 31));
        expect(polls, 2, reason: 'a finished print is not left on the face');

        container.read(wearFleetProvider.notifier).stopPolling();
      });
    });

    test('a failed poll does not end it', () {
      fakeAsync((async) {
        transport.eta = 120;
        final container = start();
        async.flushMicrotasks();
        container.read(wearFleetProvider.notifier).pollInBackground();
        transport.fail = true;

        async.elapse(const Duration(minutes: 11));
        expect(polls, 3, reason: 'nobody taps a retry behind a dark screen');

        container.read(wearFleetProvider.notifier).stopPolling();
      });
    });

    test('the last minute gets the next poll in half a minute', () {
      fakeAsync((async) {
        // Zero minutes on a machine past preparing: the print is ending.
        transport.eta = 0;
        final container = start();
        async.flushMicrotasks();
        container.read(wearFleetProvider.notifier).pollInBackground();

        async.elapse(const Duration(seconds: 31));
        expect(polls, 2);

        container.read(wearFleetProvider.notifier).stopPolling();
      });
    });

    test('a failed rebuild does not end it', () {
      fakeAsync((async) {
        transport.eta = 120;
        final container = start();
        async.flushMicrotasks();
        container.read(wearFleetProvider.notifier).pollInBackground();

        // A server switch with no cache: `build` fetches, and the fetch fails.
        transport.fail = true;
        container.invalidate(wearFleetProvider);
        container.read(wearFleetProvider);
        async.flushMicrotasks();
        expect(container.read(wearFleetProvider).hasError, isTrue);
        final afterError = polls;

        async.elapse(const Duration(minutes: 5, seconds: 1));
        expect(polls, afterError + 1);

        container.read(wearFleetProvider.notifier).stopPolling();
      });
    });

    test('an error over an unconfirmed frame does not end it either', () {
      fakeAsync((async) {
        transport.fail = true;
        final container = start(cache: const _StaleCache());
        container.read(wearFleetProvider.notifier).pollInBackground();
        async.elapse(const Duration(minutes: 5, seconds: 1));
        expect(container.read(wearFleetProvider).hasError, isTrue);
        final afterError = polls;

        async.elapse(const Duration(minutes: 5, seconds: 1));
        expect(polls, afterError + 1);

        container.read(wearFleetProvider.notifier).stopPolling();
      });
    });
  });

  group('WearApp', () {
    setUp(WearHome.forgetNotificationAsk);

    Future<_FakeOngoing> pumpApp(WidgetTester tester, _Transport t) async {
      final ongoing = _FakeOngoing();
      await pumpWear(
        tester,
        const WearApp(),
        wrapInApp: false,
        overrides: [
          fakeServerProfileOverride(),
          wearFleetCacheProvider.overrideWithValue(const _NoCache()),
          wearTransportProvider.overrideWithValue(
            HybridWearTransport.restOnly(t),
          ),
          wearOngoingProvider.overrideWithValue(ongoing),
        ],
      );
      await tester.pump();
      return ongoing;
    }

    Future<void> goTo(
      WidgetTester tester,
      List<AppLifecycleState> states,
    ) async {
      for (final s in states) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pump();
    }

    const away = [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ];
    const back = [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ];

    testWidgets('leaving during a print puts it on the face, coming back '
        'takes it off', (tester) async {
      final ongoing = await pumpApp(tester, _Transport(() {})..eta = 60);
      expect(ongoing.permissionAsks, 1, reason: 'asked while on screen');

      await goTo(tester, away);
      expect(ongoing.shown.single['title'], 'job1');

      await goTo(tester, back);
      expect(ongoing.stops, greaterThan(0));
      await goTo(tester, away);
      await goTo(tester, back);
    });

    testWidgets('the end of the print ends it', (tester) async {
      final transport = _Transport(() {})..eta = 60;
      final ongoing = await pumpApp(tester, transport);
      await goTo(tester, away);
      final stopsBefore = ongoing.stops;

      transport.eta = null;
      await tester.pump(WearFleetNotifier.backgroundInterval);
      await tester.pump();
      expect(ongoing.stops, stopsBefore + 1);
      await goTo(tester, back);
    });

    testWidgets('a refusal from an earlier pause does not end a later one', (
      tester,
    ) async {
      final transport = _Transport(() {})..eta = 60;
      final ongoing = await pumpApp(tester, transport);
      final firstAnswer = Completer<bool>();
      ongoing.answers.add(firstAnswer);

      await goTo(tester, away);
      await goTo(tester, back);
      await goTo(tester, away);
      final stopsBefore = ongoing.stops;

      firstAnswer.complete(false);
      await tester.pump();
      expect(ongoing.stops, stopsBefore, reason: 'the second session stands');

      // Still fed: the next background poll reaches the notification.
      final shownBefore = ongoing.shown.length;
      await tester.pump(WearFleetNotifier.backgroundInterval);
      await tester.pump();
      expect(ongoing.shown.length, shownBefore + 1);
      await goTo(tester, back);
    });

    testWidgets('leaving with nothing running shows nothing', (tester) async {
      final ongoing = await pumpApp(tester, _Transport(() {}));
      await goTo(tester, away);
      expect(ongoing.shown, isEmpty);
      expect(ongoing.permissionAsks, 0);
      await goTo(tester, back);
    });
  });
}

class _Transport implements WearTransport {
  _Transport(this.onCall);

  final void Function() onCall;
  bool fail = false;

  /// Minutes left on printer 1; null is an idle printer.
  int? eta;

  @override
  Future<WearFleet> getFleet() async {
    onCall();
    if (fail) throw WearRelayUnreachable();
    final minutes = eta;
    return _fleet([
      minutes == null
          ? _printer(1, 'IDLE')
          : _printer(1, 'RUNNING', progress: 50, eta: minutes),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}

class _FakeOngoing implements WearOngoing {
  final shown = <Map<String, Object?>>[];
  int stops = 0;
  int permissionAsks = 0;

  /// Answers for the next `show` calls, in order; empty answers true at once.
  final answers = <Completer<bool>>[];

  @override
  Future<bool> show(Map<String, Object?> args) async {
    shown.add(args);
    if (answers.isEmpty) return true;
    return answers.removeAt(0).future;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> requestPermission() async => permissionAsks++;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}

class _NoCache implements WearFleetCache {
  const _NoCache();

  @override
  WearFleet? load(_) => null;

  @override
  Future<void> save(WearFleet fleet, _) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}

class _StaleCache implements WearFleetCache {
  const _StaleCache();

  @override
  WearFleet? load(_) => wearFleetFromJson({
    'printers': [_printer(1, 'RUNNING', progress: 50, eta: 60)],
  }, stale: true);

  @override
  Future<void> save(WearFleet fleet, _) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}
