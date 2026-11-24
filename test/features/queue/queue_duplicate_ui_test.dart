import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../contract/sent_writes.dart';
import '../../helpers.dart';

/// Duplicate on the queue screen: a row's menu entry and the selection bar's
/// icon, against the web's two buttons (`QueuePage.tsx`, `canDuplicate`).
/// The real notifier and repository run over a mock server, so what is asserted
/// is what the server would be sent.
void main() {
  Map<String, dynamic> job(
    int id,
    String status, {
    Map<String, dynamic>? more,
  }) => {
    ...readFixture('queue_item.json') as Map<String, dynamic>,
    'id': id,
    'position': id,
    'status': status,
    ...?more,
  };

  /// Whether the queue screen is the one showing: a test turns it off to leave.
  final onQueue = ValueNotifier(true);

  /// A queue of two waiting jobs and one printing, on a server that has the
  /// route unless [served] is false.
  Future<RequestLog> open(
    WidgetTester tester, {
    bool served = true,
    CurrentUser? user,
    double scale = 1,
    List<Map<String, dynamic>>? pending,
    Map<String, dynamic> answer = const {
      'created_ids': [90, 91],
      'skipped_count': 0,
    },
  }) async {
    onQueue.value = true;
    final dio = testDio();
    mockServer(dio)
      ..onGet(
        '/api/v1/queue/',
        (server) => server.reply(
          200,
          pending ?? [job(79, 'pending'), job(80, 'pending')],
        ),
        queryParameters: {'status': 'pending'},
      )
      ..onGet(
        '/api/v1/queue/',
        (server) => server.reply(200, [job(78, 'printing')]),
        queryParameters: {'status': 'printing'},
      )
      ..onPost(
        '/api/v1/queue/duplicate',
        data: Matchers.any,
        (server) => server.reply(200, answer),
      );
    final log = captureRequests(dio);
    await tester.pumpWidget(
      ProviderScope(
        retry: neverRetry,
        overrides: [
          queueRepositoryProvider.overrideWithValue(QueueRepository(dio)),
          fakeServerProfileOverride(),
          currentUserOverride(user),
          queueDuplicateProvider.overrideWithValue(AsyncData(served)),
          printerStatusesProvider.overrideWith(_Statuses.new),
        ],
        child: plApp(
          ValueListenableBuilder(
            valueListenable: onQueue,
            builder: (_, on, _) => on ? const QueueScreen() : const Scaffold(),
          ),
          builder: textScaled(scale),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return log;
  }

  /// Lets the request and the list reload finish without waiting out the
  /// snackbar, which `pumpAndSettle` would: it is dismissed after four seconds.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  const scales = [1.0, 1.5, 2.0];

  group('the row menu', () {
    for (final scale in scales) {
      testWidgets('copies the job it belongs to, at $scale text', (
        tester,
      ) async {
        final run = await open(tester, scale: scale);

        await tester.tap(byLogId('queue.actions').first);
        await tester.pumpAndSettle();
        await tester.tap(byLogId('queue.action.duplicate'));
        await settle(tester);

        final sent = writesOf(run.requests).single;
        expect((sent.method, sent.path), ('POST', '/api/v1/queue/duplicate'));
        expect(sent.body, {
          'item_ids': [78],
        }, reason: 'the printing job sits on top of the list');
        expect(find.text(pl.queueDuplicateAdded(2)), findsOneWidget);
      });
    }

    testWidgets('is offered on a printing job and a waiting one', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(byLogId('queue.actions').first);
      await tester.pumpAndSettle();
      expect(byLogId('queue.action.duplicate'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      // Index 1 is a waiting job: the printing one is pinned on top.
      await tester.tap(byLogId('queue.actions').at(1));
      await tester.pumpAndSettle();
      expect(byLogId('queue.action.duplicate'), findsOneWidget);
      expect(byLogId('queue.action.edit'), findsOneWidget);
    });

    testWidgets('is absent for a job a printer-card upload made', (
      tester,
    ) async {
      // Its file goes when the original starts, so there is nothing to copy
      // (the web's `canDuplicate`, the server's skip).
      await open(
        tester,
        pending: [
          job(
            79,
            'pending',
            more: {'cleanup_library_after_dispatch': true, 'archive_id': null},
          ),
        ],
      );

      await tester.tap(byLogId('queue.actions').last);
      await tester.pumpAndSettle();
      expect(byLogId('queue.action.edit'), findsOneWidget);
      expect(byLogId('queue.action.duplicate'), findsNothing);
    });

    testWidgets('is absent on a server before the route', (tester) async {
      await open(tester, served: false);

      await tester.tap(byLogId('queue.actions').first);
      await tester.pumpAndSettle();
      expect(byLogId('queue.action.cancel'), findsOneWidget);
      expect(byLogId('queue.action.duplicate'), findsNothing);
    });

    testWidgets('is absent without queue:create', (tester) async {
      await open(
        tester,
        user: const CurrentUser(
          id: 7,
          username: 'op',
          isAdmin: false,
          permissions: {Permissions.queueUpdateOwn},
        ),
      );

      await tester.tap(byLogId('queue.actions').first);
      await tester.pumpAndSettle();
      expect(byLogId('queue.action.cancel'), findsOneWidget);
      expect(byLogId('queue.action.duplicate'), findsNothing);
    });
  });

  group('the selection bar', () {
    Future<void> pick(WidgetTester tester) async {
      // Below the fold at large text, where a tap would silently miss.
      await tester.ensureVisible(byLogId('queue.card').at(1));
      await tester.longPress(byLogId('queue.card').at(1));
      await tester.pumpAndSettle();
      await tester.ensureVisible(byLogId('queue.card').at(2));
      await tester.pumpAndSettle();
      await tester.tap(byLogId('queue.card').at(2));
      await tester.pumpAndSettle();
    }

    for (final scale in scales) {
      testWidgets(
        'copies what is picked and clears the picks, at $scale text',
        (tester) async {
          final run = await open(tester, scale: scale);
          await pick(tester);
          expect(find.text(pl.queueSelectedCount(2)), findsOneWidget);

          await tester.tap(byLogId('queue.bulk_duplicate'));
          await settle(tester);

          expectSentAsRecorded('queue_duplicate', writesOf(run.requests));
          expect(find.text(pl.queueDuplicateAdded(2)), findsOneWidget);
          expect(
            byLogId('queue.bulk_duplicate'),
            findsNothing,
            reason: 'the selection is over',
          );
        },
      );
    }

    testWidgets('a second tap while the first is in flight sends nothing', (
      tester,
    ) async {
      final run = await open(tester);
      await pick(tester);

      await tester.tap(byLogId('queue.bulk_duplicate'));
      await tester.tap(byLogId('queue.bulk_duplicate'));
      await settle(tester);

      expect(writesOf(run.requests), hasLength(1));
    });

    testWidgets('leaving the screen mid-request is harmless', (tester) async {
      await open(tester);
      await pick(tester);

      await tester.tap(byLogId('queue.bulk_duplicate'));
      onQueue.value = false;
      await tester.pump();
      await settle(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps the picks when the server refuses', (tester) async {
      final dio = testDio();
      mockServer(dio)
        ..onGet(
          '/api/v1/queue/',
          (server) =>
              server.reply(200, [job(79, 'pending'), job(80, 'pending')]),
          queryParameters: {'status': 'pending'},
        )
        ..onGet(
          '/api/v1/queue/',
          (server) => server.reply(200, <dynamic>[]),
          queryParameters: {'status': 'printing'},
        )
        ..onPost(
          '/api/v1/queue/duplicate',
          data: Matchers.any,
          (server) => server.reply(500, {'detail': 'boom'}),
        );
      await tester.pumpWidget(
        ProviderScope(
          retry: neverRetry,
          overrides: [
            queueRepositoryProvider.overrideWithValue(QueueRepository(dio)),
            fakeServerProfileOverride(),
            currentUserOverride(),
            queueDuplicateProvider.overrideWithValue(const AsyncData(true)),
            printerStatusesProvider.overrideWith(_Statuses.new),
          ],
          child: plApp(const QueueScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(byLogId('queue.card').first);
      await tester.pumpAndSettle();

      await tester.tap(byLogId('queue.bulk_duplicate'));
      await settle(tester);

      expect(find.text(pl.queueSelectedCount(1)), findsOneWidget);
      expect(find.text(pl.queueDuplicateAdded(1)), findsNothing);
    });

    testWidgets('says when the server left one out', (tester) async {
      await open(
        tester,
        answer: const {
          'created_ids': [90],
          'skipped_count': 1,
        },
      );
      await pick(tester);

      await tester.tap(byLogId('queue.bulk_duplicate'));
      await settle(tester);

      expect(find.text(pl.queueDuplicateSkipped(1, 1)), findsOneWidget);
    });

    testWidgets('a user who may only queue still picks, and cannot edit', (
      tester,
    ) async {
      await open(
        tester,
        user: const CurrentUser(
          id: 7,
          username: 'op',
          isAdmin: false,
          permissions: {Permissions.queueCreate},
        ),
      );

      await tester.longPress(byLogId('queue.card').at(1));
      await tester.pumpAndSettle();

      expect(byLogId('queue.bulk_duplicate'), findsOneWidget);
      expect(byLogId('queue.bulk_edit'), findsNothing);
    });

    testWidgets('is absent when nothing picked can be copied', (tester) async {
      await open(
        tester,
        pending: [
          job(
            79,
            'pending',
            more: {'cleanup_library_after_dispatch': true, 'archive_id': null},
          ),
        ],
      );

      await tester.longPress(byLogId('queue.card').at(1));
      await tester.pumpAndSettle();

      expect(find.text(pl.queueSelectedCount(1)), findsOneWidget);
      expect(byLogId('queue.bulk_edit'), findsOneWidget);
      expect(byLogId('queue.bulk_duplicate'), findsNothing);
    });

    testWidgets('keeps the picks when the server copied none', (tester) async {
      await open(
        tester,
        answer: const {'created_ids': <int>[], 'skipped_count': 2},
      );
      await pick(tester);

      await tester.tap(byLogId('queue.bulk_duplicate'));
      await settle(tester);

      expect(find.text(pl.queueDuplicateNone), findsOneWidget);
      expect(find.text(pl.queueSelectedCount(2)), findsOneWidget);
    });

    testWidgets('is absent on a server before the route', (tester) async {
      await open(tester, served: false);
      await pick(tester);

      expect(byLogId('queue.bulk_edit'), findsOneWidget);
      expect(byLogId('queue.bulk_duplicate'), findsNothing);
    });
  });
}

class _Statuses extends PrinterStatusesNotifier {
  @override
  Map<int, PrinterStatus> build() => {
    1: PrinterStatus(id: 1, connected: true, state: 'IDLE'),
  };
}
