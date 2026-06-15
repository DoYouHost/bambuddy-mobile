import 'dart:async';

import 'package:bambuddy_mobile/core/api/ws_client.dart';
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
}
