import 'package:bambuddy_mobile/core/watch/wear_rpc.dart';
import 'package:bambuddy_mobile/wear/wear_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_watch_connectivity.dart';

/// Scriptable transport for hybrid-policy tests.
class FakeTransport implements WearTransport {
  FakeTransport({this.error});

  /// Thrown by every call when set; otherwise calls succeed.
  final Exception? error;
  final calls = <String>[];

  Future<T> _run<T>(String name, T value) {
    calls.add(name);
    final e = error;
    if (e != null) throw e;
    return Future.value(value);
  }

  @override
  Future<WearFleet> getFleet() =>
      _run('getFleet', const WearFleet(printers: []));

  @override
  Future<void> pause(int printerId) => _run('pause', null);

  @override
  Future<void> resume(int printerId) => _run('resume', null);

  @override
  Future<void> stop(int printerId) => _run('stop', null);

  @override
  Future<void> clearPlate(int printerId) => _run('clearPlate', null);

  @override
  Future<void> startNext(int printerId) => _run('startNext', null);

  @override
  Future<void> clearHmsErrors(int printerId) => _run('clearHmsErrors', null);

  @override
  Future<void> executeHmsAction(
    int printerId, {
    required String printError,
    required String action,
    String? jobId,
  }) =>
      _run('executeHmsAction:$printError:$action', null);
}

void main() {
  group('RelayTransport', () {
    late FakeWatchConnectivity watch;
    late RelayTransport relay;

    setUp(() {
      watch = FakeWatchConnectivity();
      relay = RelayTransport(watch, timeout: const Duration(milliseconds: 100));
    });

    tearDown(() => relay.dispose());

    test('getFleet round-trip: request encoded, reply parsed into models',
        () async {
      watch.autoRespond = (req) => WearRpcResponse.ok(req['id'] as String, {
            'printers': [
              {
                'printer': {'id': 1, 'name': 'X1C'},
                'status': {'id': 1, 'connected': true, 'progress': 42},
              },
              {
                'printer': {'id': 2, 'name': 'P1S'},
                // no status → offline card
              },
            ],
            'queuePending': 3,
          }).encode();
      final fleet = await relay.getFleet();
      expect(fleet.printers, hasLength(2));
      expect(fleet.printers.first.printer.name, 'X1C');
      expect(fleet.printers.first.status, isNotNull);
      expect(fleet.printers.last.status, isNull);
      expect(fleet.queuePending, 3);
      // The wire request was a getFleet with the RPC envelope.
      expect(watch.sent.single['action'], 'getFleet');
      expect(watch.sent.single['kind'], 'req');
    });

    test('missing queuePending (older phone) → null, not zero', () async {
      watch.autoRespond = (req) => WearRpcResponse.ok(
          req['id'] as String, {'printers': <dynamic>[]}).encode();
      final fleet = await relay.getFleet();
      expect(fleet.queuePending, isNull);
    });

    test('command sends printerId and resolves on ok', () async {
      watch.autoRespond =
          (req) => WearRpcResponse.ok(req['id'] as String).encode();
      await relay.pause(7);
      expect(watch.sent.single['action'], 'pause');
      expect(watch.sent.single['printerId'], 7);
    });

    test('unreachable phone → WearRelayUnreachable without sending', () async {
      watch.reachable = false;
      await expectLater(relay.getFleet(), throwsA(isA<WearRelayUnreachable>()));
      expect(watch.sent, isEmpty);
    });

    test('no reply within timeout → WearRelayTimeout', () async {
      await expectLater(relay.getFleet(), throwsA(isA<WearRelayTimeout>()));
    });

    test('reply with a different id is ignored (still times out)', () async {
      watch.autoRespond =
          (req) => const WearRpcResponse.ok('some-other-id').encode();
      await expectLater(relay.pause(1), throwsA(isA<WearRelayTimeout>()));
    });

    test('phone-unconfigured maps to WearRelayUnreachable (safe to fall back)',
        () async {
      watch.autoRespond = (req) =>
          WearRpcResponse.failure(req['id'] as String, 'phone-unconfigured')
              .encode();
      await expectLater(relay.getFleet(), throwsA(isA<WearRelayUnreachable>()));
    });

    test('empty-queue maps to StateError, same as the REST path', () async {
      watch.autoRespond = (req) =>
          WearRpcResponse.failure(req['id'] as String, 'empty-queue').encode();
      await expectLater(
        relay.startNext(1),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', 'empty-queue')),
      );
    });

    test('other remote errors surface as WearRelayRemoteError with the code',
        () async {
      watch.autoRespond = (req) =>
          WearRpcResponse.failure(req['id'] as String, 'forbidden').encode();
      await expectLater(
        relay.stop(1),
        throwsA(
            isA<WearRelayRemoteError>().having((e) => e.code, 'code', 'forbidden')),
      );
    });
  });

  group('HybridWearTransport', () {
    test('relay success → no REST call, lastMode=relay', () async {
      final relay = FakeTransport();
      final rest = FakeTransport();
      final hybrid = HybridWearTransport(relay: relay, rest: rest);
      await hybrid.getFleet();
      expect(relay.calls, ['getFleet']);
      expect(rest.calls, isEmpty);
      expect(hybrid.lastMode, WearTransportMode.relay);
    });

    test('no relay (demo) goes straight to REST, and never asks the phone',
        () async {
      // Demo lives in this process. A phone answering the relay would answer
      // from its own server, so a demo watch would list the real fleet.
      final rest = FakeTransport();
      final hybrid = HybridWearTransport(rest: rest);

      await hybrid.getFleet();
      await hybrid.pause(1);

      expect(rest.calls, ['getFleet', 'pause']);
      expect(hybrid.lastMode, WearTransportMode.rest);
    });

    test('read falls back to REST on unreachable AND on timeout', () async {
      for (final error in [WearRelayUnreachable(), WearRelayTimeout()]) {
        final rest = FakeTransport();
        final hybrid = HybridWearTransport(
            relay: FakeTransport(error: error), rest: rest);
        await hybrid.getFleet();
        expect(rest.calls, ['getFleet'], reason: '$error');
        expect(hybrid.lastMode, WearTransportMode.rest);
      }
    });

    test('command falls back on unreachable (definitely not executed)',
        () async {
      final rest = FakeTransport();
      final hybrid = HybridWearTransport(
          relay: FakeTransport(error: WearRelayUnreachable()), rest: rest);
      await hybrid.pause(1);
      expect(rest.calls, ['pause']);
    });

    test('command does NOT fall back on timeout (may have executed)',
        () async {
      final rest = FakeTransport();
      final hybrid = HybridWearTransport(
          relay: FakeTransport(error: WearRelayTimeout()), rest: rest);
      await expectLater(hybrid.startNext(1), throwsA(isA<WearRelayTimeout>()));
      expect(rest.calls, isEmpty);
    });

    test('remote errors propagate without REST retry', () async {
      final rest = FakeTransport();
      final hybrid = HybridWearTransport(
          relay: FakeTransport(error: WearRelayRemoteError('forbidden')),
          rest: rest);
      await expectLater(
          hybrid.clearPlate(1), throwsA(isA<WearRelayRemoteError>()));
      expect(rest.calls, isEmpty);
    });

    test('no REST configured → relay error propagates', () async {
      final hybrid = HybridWearTransport(
          relay: FakeTransport(error: WearRelayUnreachable()), rest: null);
      await expectLater(
          hybrid.getFleet(), throwsA(isA<WearRelayUnreachable>()));
    });
  });
}
