import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bambuddy_mobile/providers.dart';

import '../../helpers.dart';
import 'queue_fakes.dart';

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

  Widget screen(FakeQueue queue, {required String printerState}) =>
      ProviderScope(
        retry: neverRetry,
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
    final queue = FakeQueue([printingItem()]);
    await tester.pumpWidget(screen(queue, printerState: 'FAILED'));
    await tester.pumpAndSettle();

    await openRemoval(tester);
    expect(find.widgetWithText(ListTile, pl.queueRemove), findsOneWidget);
    expect(
      find.widgetWithText(ListTile, pl.queueStop),
      findsNothing,
      reason: 'nothing is printing, so there is nothing to stop',
    );

    await tester.tap(find.widgetWithText(ListTile, pl.queueRemove));
    await tester.pumpAndSettle();

    // Confirmed first — it is not undoable — and worded for a print that has
    // already ended rather than one being aborted.
    expect(find.text(pl.queueRemoveStoppedTitle), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, pl.queueDeleteConfirm));
    await tester.pumpAndSettle();

    expect(queue.stopped, [
      78,
    ], reason: '/stop is the only route that clears a printing row');
    expect(queue.cancelled, isEmpty, reason: '/cancel is what answered 400');
  });

  testWidgets('a print actually running warns that it will be aborted', (
    tester,
  ) async {
    final queue = FakeQueue([printingItem()]);
    await tester.pumpWidget(screen(queue, printerState: 'RUNNING'));
    await tester.pumpAndSettle();

    await openRemoval(tester);
    expect(find.widgetWithText(ListTile, pl.queueStop), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, pl.queueStop));
    await tester.pumpAndSettle();

    expect(find.text(pl.queueStopTitle), findsOneWidget);
    expect(
      find.textContaining(pl.queueStopBody),
      findsOneWidget,
      reason: 'aborting a running print is the destructive case',
    );
  });

  testWidgets('backing out of the confirmation sends nothing', (tester) async {
    final queue = FakeQueue([printingItem()]);
    await tester.pumpWidget(screen(queue, printerState: 'RUNNING'));
    await tester.pumpAndSettle();

    await openRemoval(tester);
    await tester.tap(find.widgetWithText(ListTile, pl.queueStop));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, pl.cancel));
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
    final queue = FakeQueue([pending]);
    await tester.pumpWidget(screen(queue, printerState: 'IDLE'));
    await tester.pumpAndSettle();

    await openRemoval(tester);
    await tester.tap(find.widgetWithText(ListTile, pl.cancel));
    await tester.pumpAndSettle();

    expect(queue.cancelled, [78]);
    expect(queue.stopped, isEmpty);
  });

  testWidgets('a refusal explains itself instead of naming the status code', (
    tester,
  ) async {
    // What the reporter saw was "server returned error 400", twice.
    final queue = FakeQueue([printingItem()])
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
    await tester.tap(find.widgetWithText(ListTile, pl.queueRemove));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, pl.queueDeleteConfirm));
    await tester.pumpAndSettle();

    expect(find.textContaining(pl.queueRemovalStatusChanged), findsOneWidget);
    expect(find.textContaining('400'), findsNothing);
  });
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
