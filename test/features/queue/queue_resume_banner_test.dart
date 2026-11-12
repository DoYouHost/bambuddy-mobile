import 'package:bambuddy_mobile/core/api/action_outcome.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_removal.dart';
import 'package:bambuddy_mobile/features/queue/queue_resume_banner.dart';
import 'package:bambuddy_mobile/features/queue/queue_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../contract/sent_writes.dart';
import '../../helpers.dart';

/// The "Resume after failure" banner (server #1818): a failed print behind a
/// `require_previous_success` gate leaves the jobs after it skipped, and the
/// route that brings them back is one tap away from the queue.
void main() {
  QueueItem skipped(
    int id, {
    int printerId = 1,
    String printerName = 'X1C Warsztat',
    String? error = kPreviousFailureGate,
  }) => QueueItem.fromJson({
    'id': id,
    'position': id,
    'status': 'skipped',
    'printer_id': printerId,
    'printer_name': printerName,
    'error_message': error,
  });

  Widget screen({required List<QueueItem> held, _ResumeQueue? queue}) =>
      ProviderScope(
        retry: neverRetry,
        overrides: [
          queueProvider.overrideWith(() => queue ?? _ResumeQueue()),
          queueSkippedProvider.overrideWith(() => _FixedSkipped(held)),
          noServerProfileOverride,
        ],
        child: plApp(const QueueScreen()),
      );

  testWidgets('one banner per held printer, with what it skipped', (
    tester,
  ) async {
    await tester.pumpWidget(
      screen(
        held: [
          skipped(1),
          skipped(2),
          skipped(3, printerId: 2, printerName: 'P1S'),
          skipped(
            4,
            printerId: 3,
            printerName: 'A1',
            error: 'Filament deficit',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(byLogId('queue.resume_banner'), findsNWidgets(2));
    expect(find.text(pl.queueResumeBanner('X1C Warsztat', 2)), findsOneWidget);
    expect(find.text(pl.queueResumeBanner('P1S', 1)), findsOneWidget);
    expect(
      find.textContaining('A1'),
      findsNothing,
      reason: 'a skip for another reason is not what resume restores',
    );
  });

  testWidgets('no banner while nothing is held', (tester) async {
    await tester.pumpWidget(screen(held: const []));
    await tester.pumpAndSettle();

    expect(byLogId('queue.resume_banner'), findsNothing);
  });

  testWidgets('the banner shows over an empty queue', (tester) async {
    await tester.pumpWidget(screen(held: [skipped(1)]));
    await tester.pumpAndSettle();

    expect(find.text(pl.queueEmpty), findsOneWidget);
    expect(byLogId('queue.resume_banner'), findsOneWidget);
  });

  testWidgets('confirming resumes that printer and says how many came back', (
    tester,
  ) async {
    final queue = _ResumeQueue(restored: 2);
    await tester.pumpWidget(
      screen(
        held: [skipped(1, printerId: 7), skipped(2, printerId: 7)],
        queue: queue,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(byLogId('queue.resume'));
    await tester.pumpAndSettle();

    expect(find.text(pl.queueResumeConfirmTitle), findsOneWidget);
    expect(
      find.text(pl.queueResumeConfirmBody(2, 'X1C Warsztat')),
      findsOneWidget,
    );
    expect(queue.resumed, isEmpty, reason: 'asks before it restores anything');

    await tester.tap(
      find.widgetWithText(FilledButton, pl.queueResumeButton).last,
    );
    await tester.pumpAndSettle();

    expect(queue.resumed, [7]);
    expect(find.text(pl.queueResumed(2)), findsOneWidget);
  });

  testWidgets('backing out of the confirmation sends nothing', (tester) async {
    final queue = _ResumeQueue();
    await tester.pumpWidget(screen(held: [skipped(1)], queue: queue));
    await tester.pumpAndSettle();

    await tester.tap(byLogId('queue.resume'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, pl.cancel));
    await tester.pumpAndSettle();

    expect(queue.resumed, isEmpty);
  });

  testWidgets('a refusal is said, not reported as a resume', (tester) async {
    final queue = _ResumeQueue(
      refusal: const AuthException(AppErrorCode.forbidden),
    );
    await tester.pumpWidget(screen(held: [skipped(1)], queue: queue));
    await tester.pumpAndSettle();

    await tester.tap(byLogId('queue.resume'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, pl.queueResumeButton).last,
    );
    await tester.pumpAndSettle();

    expect(find.text(pl.queueResumed(0)), findsNothing);
    expect(
      find.text(
        queueWriteMessage(
          pl,
          const ActionFailed(AuthException(AppErrorCode.forbidden)),
        )!,
      ),
      findsOneWidget,
    );
  });

  group('any-model jobs held by a failed print', () {
    Map<String, Object?> waiting(int id, {String? reason, int? printerId}) => {
      'id': id,
      'position': id,
      'status': 'pending',
      'printer_id': printerId,
      'target_model': 'X1C',
      'waiting_reason': reason,
    };

    /// The banner alone over the real notifier and repository; returns what
    /// was sent.
    Future<RequestLog> pump(
      WidgetTester tester,
      List<Map<String, Object?>> pending, {
      CurrentUser? me,
    }) async {
      final dio = testDio();
      final adapter = mockServer(dio);
      for (final (status, rows) in [
        ('pending', pending),
        ('printing', const <Object>[]),
        ('skipped', const <Object>[]),
      ]) {
        adapter.onGet(
          '/api/v1/queue/',
          (server) => server.reply(200, rows),
          queryParameters: {'status': status},
        );
      }
      adapter.onPost(
        '/api/v1/queue/model/X1C/resume',
        (server) => server.reply(200, {'acknowledged': 1, 'printers': 2}),
      );
      final log = captureRequests(dio);
      await tester.pumpWidget(
        ProviderScope(
          retry: neverRetry,
          overrides: [
            fakeServerProfileOverride(),
            if (me != null) currentUserOverride(me),
            queueRepositoryProvider.overrideWithValue(QueueRepository(dio)),
          ],
          child: plApp(const Scaffold(body: QueueResumeBanners())),
        ),
      );
      await tester.pumpAndSettle();
      return log;
    }

    testWidgets('one banner per model, counting the jobs that wait', (
      tester,
    ) async {
      await pump(tester, [
        waiting(1, reason: kModelGateWaitReason),
        waiting(2, reason: kModelGateWaitReason),
        waiting(3, reason: 'All matching printers are busy'),
      ]);

      expect(byLogId('queue.resume_banner'), findsOneWidget);
      expect(find.text(pl.queueResumeModelBanner('X1C', 2)), findsOneWidget);
    });

    testWidgets('a job that already has its printer is not one', (
      tester,
    ) async {
      await pump(tester, [
        waiting(1, reason: kModelGateWaitReason, printerId: 4),
      ]);

      expect(byLogId('queue.resume_banner'), findsNothing);
    });

    testWidgets('not for a user the route would refuse', (tester) async {
      await pump(
        tester,
        [waiting(1, reason: kModelGateWaitReason)],
        me: CurrentUser(
          id: 7,
          username: 'u',
          isAdmin: false,
          permissions: const {Permissions.queueUpdateOwn},
        ),
      );

      expect(byLogId('queue.resume_banner'), findsNothing);
    });

    testWidgets('confirming clears the gate on the model, and only then', (
      tester,
    ) async {
      final log = await pump(tester, [
        waiting(1, reason: kModelGateWaitReason),
      ]);

      await tester.tap(byLogId('queue.resume'));
      await tester.pumpAndSettle();
      expect(find.text(pl.queueResumeModelConfirmBody('X1C')), findsOneWidget);
      expect(writesOf(log.requests), isEmpty);

      await tester.tap(
        find.widgetWithText(FilledButton, pl.queueResumeButton).last,
      );
      await tester.pumpAndSettle();

      expectSentAsRecorded('queue_resume_model', writesOf(log.requests));
      expect(find.text(pl.queueResumed(0)), findsOneWidget);
    });
  });

  group('queueSkippedProvider', () {
    Future<(List<QueueItem>, List<String>)> load(CurrentUser me) async {
      final dio = testDio();
      mockServer(dio).onGet(
        '/api/v1/queue/',
        (server) => server.reply(200, [
          {
            'id': 1,
            'position': 1,
            'status': 'skipped',
            'printer_id': 1,
            'error_message': kPreviousFailureGate,
          },
        ]),
        queryParameters: {'status': 'skipped'},
      );
      final sent = captureRequests(dio);
      final container = ProviderContainer(
        retry: neverRetry,
        overrides: [
          fakeServerProfileOverride(),
          currentUserOverride(me),
          queueRepositoryProvider.overrideWithValue(QueueRepository(dio)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(currentUserProvider.future);
      final items = await container.read(queueSkippedProvider.future);
      return (items, sent.calls);
    }

    CurrentUser user(Set<String> permissions) => CurrentUser(
      id: 7,
      username: 'u',
      isAdmin: false,
      permissions: permissions,
    );

    test('asks for the skipped jobs when the user may resume', () async {
      final (items, calls) = await load(user({Permissions.queueUpdateAll}));

      expect(items, hasLength(1));
      expect(calls, ['GET /api/v1/queue/']);
    });

    test('a queue refresh asks nothing while no banner is shown', () async {
      // Reading the notifier of an unwatched provider builds it: one request,
      // plus the refresh's own, both for nobody.
      final dio = testDio();
      final adapter = mockServer(dio);
      for (final status in ['pending', 'printing', 'skipped']) {
        adapter.onGet(
          '/api/v1/queue/',
          (server) => server.reply(200, <Object>[]),
          queryParameters: {'status': status},
        );
      }
      final sent = captureRequests(dio);
      final container = ProviderContainer(
        retry: neverRetry,
        overrides: [
          fakeServerProfileOverride(),
          currentUserOverride(user({Permissions.queueUpdateAll})),
          queueRepositoryProvider.overrideWithValue(QueueRepository(dio)),
        ],
      );
      addTearDown(container.dispose);
      container.listen(queueProvider, (_, _) {});
      await container.read(queueProvider.future);
      sent.requests.clear();

      await container.read(queueProvider.notifier).refresh();

      expect([
        for (final r in sent.requests) r.queryParameters['status'],
      ], unorderedEquals(['pending', 'printing']));
    });

    test(
      'asks nothing of a user who may not: the route would refuse',
      () async {
        final (items, calls) = await load(user({Permissions.queueUpdateOwn}));

        expect(items, isEmpty);
        expect(calls, isEmpty);
      },
    );
  });
}

/// A queue that records the printers resumed instead of calling the server.
class _ResumeQueue extends QueueNotifier {
  _ResumeQueue({this.restored = 0, this.refusal});

  final int restored;
  final AppApiException? refusal;
  final resumed = <int>[];

  @override
  Future<List<QueueItem>> build() async => const [];

  @override
  Future<({ActionOutcome outcome, int restored})> resumeAfterFailure(
    int printerId,
  ) async {
    resumed.add(printerId);
    final error = refusal;
    return (
      outcome: error == null ? ActionOutcome.ok : ActionFailed(error),
      restored: restored,
    );
  }
}

class _FixedSkipped extends QueueSkippedNotifier {
  _FixedSkipped(this._items);

  final List<QueueItem> _items;

  @override
  Future<List<QueueItem>> build() async => _items;
}
