import 'dart:async';

import 'package:bambuddy_mobile/core/api/ws_client.dart';
import 'package:clock/clock.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProfileNotifier extends ServerProfileNotifier {
  @override
  ServerProfile? build() => const ServerProfile(
        baseUrl: 'http://s.local:8000',
        authMode: AuthMode.none,
      );
}

/// Połączenie, które nigdy nie kończy handshake'u i nie nadaje ramek — WS
/// zostaje „cichy", więc testujemy wyłącznie tor pollingu ([ingestPoll]).
class _HangConn implements WsConnection {
  @override
  Future<void> get ready => Completer<void>().future;
  @override
  Stream<dynamic> get stream => const Stream.empty();
  @override
  void send(String data) {}
  @override
  Future<void> close() async {}
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
}

ProviderContainer _container() {
  final c = ProviderContainer(
    overrides: [
      serverProfileProvider.overrideWith(_FakeProfileNotifier.new),
      wsClientProvider.overrideWith((ref) {
        final client = WsClient(
          url: Uri.parse('ws://s.local:8000/api/v1/ws'),
          authHeaders: () async => const {},
          connect: (_, _) => _HangConn(),
        );
        ref.onDispose(client.dispose);
        return client;
      }),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

PrinterWithStatus _pws(int id, {String? state}) => PrinterWithStatus(
      printer: Printer(id: id, name: 'P$id'),
      status: state == null ? null : PrinterStatus(id: id, state: state),
    );

void main() {
  test('ingestPoll: polling zasila tę samą mapę statusów co WS', () {
    final c = _container();
    expect(c.read(printerStatusesProvider), isEmpty);

    c.read(printerStatusesProvider.notifier).ingestPoll([
      _pws(1, state: 'RUNNING'),
      _pws(2, state: 'IDLE'),
    ]);

    final map = c.read(printerStatusesProvider);
    expect(map.keys, unorderedEquals([1, 2]));
    expect(map[1]!.isPrinting, isTrue);
    expect(map[2]!.isPrinting, isFalse);
  });

  test('ingestPoll: wpis bez statusu (null) nie kasuje istniejącego', () {
    final c = _container();
    c.read(printerStatusesProvider.notifier).ingestPoll([_pws(1, state: 'RUNNING')]);

    // Kolejny poll: drukarka 1 ma teraz null (status endpoint padł) — zostaje
    // poprzedni status, a nowa drukarka 2 dochodzi.
    c.read(printerStatusesProvider.notifier).ingestPoll([
      _pws(1),
      _pws(2, state: 'IDLE'),
    ]);

    final map = c.read(printerStatusesProvider);
    expect(map[1]!.state, 'RUNNING');
    expect(map[2]!.state, 'IDLE');
  });

  test('ingestPoll: drukarka usunięta z rostera znika z mapy', () {
    final c = _container();
    c.read(printerStatusesProvider.notifier).ingestPoll([
      _pws(1, state: 'RUNNING'),
      _pws(2, state: 'IDLE'),
    ]);
    expect(c.read(printerStatusesProvider).keys, unorderedEquals([1, 2]));

    // Kolejny poll bez drukarki 2 (skasowana na serwerze) — znika z mapy,
    // nie zostaje na zawsze.
    c.read(printerStatusesProvider.notifier).ingestPoll([_pws(1, state: 'RUNNING')]);
    expect(c.read(printerStatusesProvider).keys, [1]);
  });

  group('contact with the server', () {
    // What the card asks before it believes a `connected:false` frame: had the
    // line been up long enough for a second frame to contradict this one?
    test('nothing has arrived yet, so there is no line', () {
      final c = _container();
      expect(c.read(printerStatusesProvider.notifier).inTouchSince, isNull);
    });

    test('the line starts at the first thing that arrives and does not drift',
        () {
      final c = _container();
      final store = c.read(printerStatusesProvider.notifier);
      final opened = DateTime(2026, 9, 3, 12);

      withClock(Clock.fixed(opened), () {
        store.ingestPoll([_pws(1, state: 'RUNNING')]);
      });
      expect(store.inTouchSince, opened);

      // Later frames say the line is still up; they do not restart it. If they
      // did, every frame would look like a fresh reconnection and no
      // disconnect would ever be debounced.
      withClock(Clock.fixed(opened.add(const Duration(minutes: 5))), () {
        store.ingestPoll([_pws(1, state: 'IDLE')]);
      });
      expect(store.inTouchSince, opened);
    });

    test('a poll that carries nothing new is still the line being up', () {
      // This ingest changes no value, so it writes nothing to the map — and it
      // used to leave no trace at all. An idle printer polls like this for
      // hours, which is not the same as being out of touch.
      final c = _container();
      final store = c.read(printerStatusesProvider.notifier);
      final opened = DateTime(2026, 9, 3, 12);
      withClock(Clock.fixed(opened), () {
        store.ingestPoll([_pws(1, state: 'IDLE')]);
      });

      store.lostContact();
      final reopened = opened.add(const Duration(hours: 2));
      withClock(Clock.fixed(reopened), () {
        store.ingestPoll([_pws(1, state: 'IDLE')]); // identical to the above
      });

      expect(store.inTouchSince, reopened);
    });

    test('going to the background drops the line', () {
      final c = _container();
      final store = c.read(printerStatusesProvider.notifier);
      store.ingestPoll([_pws(1, state: 'IDLE')]);
      expect(store.inTouchSince, isNotNull);

      store.suspend();
      expect(store.inTouchSince, isNull);
    });
  });
}
