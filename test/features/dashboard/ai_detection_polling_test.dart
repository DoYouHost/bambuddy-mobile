import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/ai_detection.dart';
import 'package:bambuddy_mobile/data/ai_detection_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/ai_detection_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

const _safe = AiDetection(cls: AiDetectionClass.safe, frameCount: 1);

class _CountingRepo extends AiDetectionRepository {
  _CountingRepo() : super(Dio());

  int polls = 0;
  AiDetectionStatus? answer = const AiDetectionStatus(
    enabled: true,
    perPrinter: {1: _safe},
  );
  Object? error;

  @override
  Future<AiDetectionStatus?> fetch() async {
    polls++;
    if (error != null) throw error!;
    return answer;
  }
}

void main() {
  late _CountingRepo repo;

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      retry: neverRetry,
      overrides: [
        aiDetectionRepositoryProvider.overrideWithValue(repo),
        fakeServerProfileOverride(),
      ],
    );
    // Auto-dispose: something has to hold the provider the way a print panel
    // does.
    container.listen(aiDetectionProvider, (_, _) {});
    return container;
  }

  setUp(() => repo = _CountingRepo());

  void run(void Function(FakeAsync async, ProviderContainer container) body) {
    fakeAsync((async) {
      final container = makeContainer();
      addTearDown(container.dispose);
      async.flushMicrotasks();
      body(async, container);
    });
  }

  test('detection that is on is polled', () {
    run((async, container) {
      expect(repo.polls, 1);
      expect(container.read(aiDetectionForProvider(1)), _safe);

      async.elapse(aiDetectionPollInterval * 2);
      expect(repo.polls, 3);
    });
  });

  test('detection that is off is asked about once', () {
    repo.answer = const AiDetectionStatus(enabled: false);
    run((async, container) {
      async.elapse(aiDetectionPollInterval * 4);
      expect(repo.polls, 1);
    });
  });

  test('a server without the routes is asked once', () {
    repo.answer = null;
    run((async, container) {
      async.elapse(aiDetectionPollInterval * 4);
      expect(repo.polls, 1);
      expect(container.read(aiDetectionForProvider(1)), isNull);
    });
  });

  test('regained contact asks again, and starts the polling once it is on', () {
    repo.answer = const AiDetectionStatus(enabled: false);
    run((async, container) {
      repo.answer = const AiDetectionStatus(enabled: true);
      container.read(serverContactEpochProvider.notifier).bump();
      async.flushMicrotasks();
      expect(repo.polls, 2);

      async.elapse(aiDetectionPollInterval);
      expect(repo.polls, 3);
    });
  });

  test('switched off on the server, the polling stops', () {
    run((async, container) {
      repo.answer = const AiDetectionStatus(enabled: false);
      async.elapse(aiDetectionPollInterval);
      final after = repo.polls;

      async.elapse(aiDetectionPollInterval * 4);
      expect(repo.polls, after);
      expect(container.read(aiDetectionForProvider(1)), isNull);
    });
  });

  test('pull-to-refresh asks now', () {
    repo.answer = const AiDetectionStatus(enabled: false);
    run((async, container) {
      container.read(aiDetectionProvider.notifier).refresh();
      async.flushMicrotasks();
      expect(repo.polls, 2);
    });
  });

  for (final (name, hide, show) in [
    (
      'another tab',
      (DashboardWatched w) => w.setOnScreen(false),
      (DashboardWatched w) => w.setOnScreen(true),
    ),
    (
      'the background',
      (DashboardWatched w) => w.setForeground(false),
      (DashboardWatched w) => w.setForeground(true),
    ),
  ]) {
    test('$name stops the polling, coming back catches up at once', () {
      run((async, container) {
        final watched = container.read(dashboardWatchedProvider.notifier);
        hide(watched);
        final before = repo.polls;
        async.elapse(aiDetectionPollInterval * 4);
        expect(repo.polls, before);

        show(watched);
        async.flushMicrotasks();
        expect(repo.polls, before + 1);
        async.elapse(aiDetectionPollInterval);
        expect(repo.polls, before + 2);
      });
    });
  }

  test('in the background, coming back to another tab stays silent', () {
    run((async, container) {
      final watched = container.read(dashboardWatchedProvider.notifier);
      watched.setOnScreen(false);
      watched.setForeground(false);
      final before = repo.polls;

      watched.setForeground(true);
      async.elapse(aiDetectionPollInterval * 2);
      expect(repo.polls, before);
    });
  });

  test('born while nobody watches the dashboard, it asks nothing', () {
    fakeAsync((async) {
      final container = ProviderContainer(
        retry: neverRetry,
        overrides: [
          aiDetectionRepositoryProvider.overrideWithValue(repo),
          fakeServerProfileOverride(),
        ],
      );
      addTearDown(container.dispose);
      container.read(dashboardWatchedProvider.notifier).setOnScreen(false);
      container.listen(aiDetectionProvider, (_, _) {});
      async.elapse(aiDetectionPollInterval * 2);
      expect(repo.polls, 0);

      container.read(dashboardWatchedProvider.notifier).setOnScreen(true);
      async.flushMicrotasks();
      expect(repo.polls, 1);
    });
  });

  test('a failed poll keeps the last answer and the polling', () {
    run((async, container) {
      repo.error = const NetworkException(AppErrorCode.serverUnreachable);
      async.elapse(aiDetectionPollInterval);
      expect(container.read(aiDetectionForProvider(1)), _safe);

      repo.error = null;
      final before = repo.polls;
      async.elapse(aiDetectionPollInterval);
      expect(repo.polls, before + 1);
    });
  });
}
