import 'package:bambuddy_mobile/core/api/action_outcome.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_removal.dart';
import 'package:bambuddy_mobile/features/queue/queue_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
