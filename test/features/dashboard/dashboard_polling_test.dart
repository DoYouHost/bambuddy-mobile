import 'dart:async';

import 'package:bambuddy_mobile/core/api/ws_client.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Statuses go nowhere: this is about who asks the server and when.
class _InertStatusesNotifier extends PrinterStatusesNotifier {
  @override
  Map<int, PrinterStatus> build() => const {};
}

class _CountingRepo extends PrintersRepository {
  _CountingRepo() : super(Dio());

  int polls = 0;

  @override
  Future<List<PrinterWithStatus>> fetchAll() async {
    polls++;
    return const [];
  }
}

void main() {
  late _CountingRepo repo;
  late StreamController<WsConnectionState> socket;

  setUp(() {
    repo = _CountingRepo();
    socket = StreamController<WsConnectionState>.broadcast();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        fakeServerProfileOverride(),
        printerStatusesProvider.overrideWith(_InertStatusesNotifier.new),
        printersRepositoryProvider.overrideWithValue(repo),
        wsConnectionStateProvider.overrideWith((ref) => socket.stream),
      ],
    );
    // Auto-dispose: something has to hold it the way the dashboard does.
    container.listen(dashboardProvider, (_, _) {});
    return container;
  }

  test('a dropped socket switches the polling to the fallback rate', () {
    // The behaviour the pause must not break: without a socket, REST is the
    // only source of truth, so it speeds up and pulls at once.
    fakeAsync((async) {
      final container = makeContainer();
      addTearDown(container.dispose);
      async.flushMicrotasks();
      // The retune reacts to a *change*, so the socket has to be up first.
      socket.add(WsConnectionState.connected);
      async.flushMicrotasks();
      final before = repo.polls;

      socket.add(WsConnectionState.disconnected);
      async.flushMicrotasks();

      expect(repo.polls, before + 1);
      async.elapse(pollInterval * 2);
      expect(repo.polls, before + 3);
    });
  });

  test('the socket closing on the way to the background does not restart the '
      'polling', () {
    // Backgrounding closes the socket, which to the retune looks exactly like
    // losing the network. Before the pause was a flag, that re-armed the timer
    // a millisecond after it had been cancelled — and the foreground service,
    // which had just taken over, ended up polling in parallel with the UI.
    fakeAsync((async) {
      final container = makeContainer();
      addTearDown(container.dispose);
      async.flushMicrotasks();
      socket.add(WsConnectionState.connected);
      async.flushMicrotasks();
      final notifier = container.read(dashboardProvider.notifier)
        ..pausePolling();
      final before = repo.polls;

      // What `suspend()` does to the socket on the way to the background.
      socket.add(WsConnectionState.disconnected);
      async.flushMicrotasks();
      async.elapse(pollInterval * 4);

      expect(repo.polls, before);

      // And coming back to the foreground brings it straight back.
      notifier.resumePolling();
      async.flushMicrotasks();
      expect(repo.polls, before + 1);
      async.elapse(pollInterval);
      expect(repo.polls, before + 2);
    });
  });
}
