import 'package:bambuddy_mobile/core/models/smart_plug.dart';
import 'package:bambuddy_mobile/data/smart_plugs_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/smart_plugs_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Counts polls. No plugs come back, so a poll is exactly one list request.
class _CountingRepo extends SmartPlugsRepository {
  _CountingRepo() : super(Dio());

  int polls = 0;

  @override
  Future<List<SmartPlug>> fetchPlugs() async {
    polls++;
    return const [];
  }
}

void main() {
  late _CountingRepo repo;

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        smartPlugsRepositoryProvider.overrideWithValue(repo),
        fakeServerProfileOverride(),
      ],
    );
    // Auto-dispose: something has to hold the provider the way the dashboard
    // does.
    container.listen(smartPlugsProvider, (_, _) {});
    return container;
  }

  setUp(() => repo = _CountingRepo());

  test('polls while the dashboard is the tab on screen', () {
    fakeAsync((async) {
      final container = makeContainer();
      addTearDown(container.dispose);

      async.flushMicrotasks();
      expect(repo.polls, 1);

      async.elapse(smartPlugPollInterval * 2);
      expect(repo.polls, 3);
    });
  });

  test('another tab is not the dashboard, so the polling stops', () {
    // The plug controls and the farm total are on the dashboard and nowhere
    // else; from any other tab this is a request every five seconds for a
    // number nobody can see.
    fakeAsync((async) {
      final container = makeContainer();
      addTearDown(container.dispose);
      async.flushMicrotasks();
      final before = repo.polls;

      container.read(smartPlugsProvider.notifier).setOnScreen(false);
      async.elapse(smartPlugPollInterval * 4);

      expect(repo.polls, before);
    });
  });

  test('coming back to the dashboard catches up at once', () {
    fakeAsync((async) {
      final container = makeContainer();
      addTearDown(container.dispose);
      async.flushMicrotasks();
      final notifier = container.read(smartPlugsProvider.notifier)
        ..setOnScreen(false);
      async.elapse(smartPlugPollInterval * 4);
      final before = repo.polls;

      notifier.setOnScreen(true);
      async.flushMicrotasks();

      // Now, not five seconds from now: the user is looking at a stale number.
      expect(repo.polls, before + 1);
    });
  });

  test('returning from the background does not poll from another tab', () {
    // Why the two gates are separate: the lifecycle knows nothing about which
    // tab is showing, and it resumes on every return to the foreground.
    fakeAsync((async) {
      final container = makeContainer();
      addTearDown(container.dispose);
      async.flushMicrotasks();
      final notifier = container.read(smartPlugsProvider.notifier)
        ..setOnScreen(false)
        ..pausePolling();
      final before = repo.polls;

      notifier.resumePolling();
      async.flushMicrotasks();
      async.elapse(smartPlugPollInterval * 3);

      expect(repo.polls, before);

      // And once the user is back on the dashboard, it runs again.
      notifier.setOnScreen(true);
      async.flushMicrotasks();
      expect(repo.polls, before + 1);
    });
  });
}
