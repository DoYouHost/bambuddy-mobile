import 'package:bambuddy_mobile/core/api/action_outcome.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The queue's one removal button, and which of the server's three routes it
/// sends the user down.
///
/// Issue #35: the menu offered "Cancel" for every status and always posted to
/// `/cancel`, which the server accepts for a `pending` item alone. A row it
/// held as `printing` — a print that had failed on the machine, never
/// reconciled — took a 400, and the pinned printing card carries no swipe
/// either, so there was no way at all to clear it.
void main() {
  /// The reporter's item: the server still calls it `printing`.
  QueueItem printingItem() => QueueItem.fromJson({
    ...readFixture('queue_item.json') as Map<String, dynamic>,
    'status': 'printing',
  });

  Widget screen(_RecordingQueue queue, {required String printerState}) =>
      ProviderScope(
        overrides: [
          queueProvider.overrideWith(() => queue),
          noServerProfileOverride,
          printerStatusesProvider.overrideWith(() => _Statuses(printerState)),
        ],
        child: plApp(const QueueScreen()),
      );

  Future<void> openRemoval(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
  }

  testWidgets('a print the machine has failed offers removal, not a stop', (
    tester,
  ) async {
    // Exactly the reporter's state: item `printing`, printer FAILED.
    final queue = _RecordingQueue([printingItem()]);
    await tester.pumpWidget(screen(queue, printerState: 'FAILED'));
    await tester.pumpAndSettle();

    await openRemoval(tester);
    expect(find.widgetWithText(ListTile, 'Usuń z kolejki'), findsOneWidget);
    expect(
      find.widgetWithText(ListTile, 'Zatrzymaj wydruk'),
      findsNothing,
      reason: 'nothing is printing, so there is nothing to stop',
    );

    await tester.tap(find.widgetWithText(ListTile, 'Usuń z kolejki'));
    await tester.pumpAndSettle();

    // Confirmed first — it is not undoable — and worded for a print that has
    // already ended rather than one being aborted.
    expect(find.text('Usunąć z kolejki?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Usuń'));
    await tester.pumpAndSettle();

    expect(queue.stopped, [
      78,
    ], reason: '/stop is the only route that clears a printing row');
    expect(queue.cancelled, isEmpty, reason: '/cancel is what answered 400');
  });

  testWidgets('a print actually running warns that it will be aborted', (
    tester,
  ) async {
    final queue = _RecordingQueue([printingItem()]);
    await tester.pumpWidget(screen(queue, printerState: 'RUNNING'));
    await tester.pumpAndSettle();

    await openRemoval(tester);
    expect(find.widgetWithText(ListTile, 'Zatrzymaj wydruk'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'Zatrzymaj wydruk'));
    await tester.pumpAndSettle();

    expect(find.text('Zatrzymać ten wydruk?'), findsOneWidget);
    expect(
      find.textContaining('nie da się wznowić'),
      findsOneWidget,
      reason: 'aborting a running print is the destructive case',
    );
  });

  testWidgets('backing out of the confirmation sends nothing', (tester) async {
    final queue = _RecordingQueue([printingItem()]);
    await tester.pumpWidget(screen(queue, printerState: 'RUNNING'));
    await tester.pumpAndSettle();

    await openRemoval(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Zatrzymaj wydruk'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Anuluj'));
    await tester.pumpAndSettle();

    expect(queue.stopped, isEmpty);
  });

  testWidgets('a waiting item still cancels, without a confirmation', (
    tester,
  ) async {
    // The behaviour that already worked, kept: /cancel takes a pending item,
    // and undoing it is re-queueing rather than a loss.
    final pending = QueueItem.fromJson({
      ...readFixture('queue_item.json') as Map<String, dynamic>,
      'status': 'pending',
    });
    final queue = _RecordingQueue([pending]);
    await tester.pumpWidget(screen(queue, printerState: 'IDLE'));
    await tester.pumpAndSettle();

    await openRemoval(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Anuluj'));
    await tester.pumpAndSettle();

    expect(queue.cancelled, [78]);
    expect(queue.stopped, isEmpty);
  });

  testWidgets('a refusal explains itself instead of naming the status code', (
    tester,
  ) async {
    // What the reporter saw was "server returned error 400", twice.
    final queue = _RecordingQueue([printingItem()])
      ..stopFailure = const ApiException(
        AppErrorCode.badResponse,
        statusCode: 400,
        detail:
            "Can only stop items that are printing, current status: "
            "'completed'",
      );
    await tester.pumpWidget(screen(queue, printerState: 'FAILED'));
    await tester.pumpAndSettle();

    await openRemoval(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Usuń z kolejki'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Usuń'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Odśwież kolejkę'), findsOneWidget);
    expect(find.textContaining('400'), findsNothing);
  });
}

/// Queue that records which route the screen chose instead of sending one.
class _RecordingQueue extends QueueNotifier {
  _RecordingQueue(this._items);

  final List<QueueItem> _items;
  final List<int> stopped = [];
  final List<int> cancelled = [];
  final List<int> deleted = [];

  /// What `/stop` comes back with, when a test wants it refused.
  AppApiException? stopFailure;

  @override
  Future<List<QueueItem>> build() async => _items;

  @override
  Future<ActionOutcome> stop(int itemId) async {
    stopped.add(itemId);
    final failure = stopFailure;
    return failure == null ? ActionOutcome.ok : ActionOutcome.failed(failure);
  }

  @override
  Future<ActionOutcome> cancel(int itemId) async {
    cancelled.add(itemId);
    return ActionOutcome.ok;
  }

  @override
  Future<ActionOutcome> delete(int itemId, {String logId = ''}) async {
    deleted.add(itemId);
    return ActionOutcome.ok;
  }
}

/// One printer whose live state the test dictates — the half of the decision
/// that separates "stop the print" from "remove what is left of it".
class _Statuses extends PrinterStatusesNotifier {
  _Statuses(this.reported);

  /// What the printer says it is doing — RUNNING, FAILED, IDLE.
  final String reported;

  @override
  Map<int, PrinterStatus> build() => {
    1: PrinterStatus(id: 1, connected: true, state: reported),
  };
}
