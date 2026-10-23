import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_screen.dart';
import 'package:bambuddy_mobile/features/queue/queue_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import 'queue_fakes.dart';

/// Picking queue items for a bulk edit: long press starts it (the archive's
/// gesture), a tap extends it, and only a `pending` row can be picked — the
/// route changes nothing else.
void main() {
  QueueItem item(int id, {String status = 'pending'}) => QueueItem.fromJson({
    'id': id,
    'position': id,
    'status': status,
    'archive_name': 'Part $id',
  });

  Widget screen(FakeQueue queue, {List<Override> extra = const []}) =>
      ProviderScope(
        overrides: [
          queueProvider.overrideWith(() => queue),
          noServerProfileOverride,
          allPrintersProvider.overrideWith((ref) async => const <Printer>[]),
          ...extra,
        ],
        child: plApp(const QueueScreen()),
      );

  Future<void> pick(WidgetTester tester, int id) async {
    await tester.longPress(find.text('Part $id'));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, Widget app) async {
    usePhoneWindow(tester);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  testWidgets('a long press picks the item and the bar counts it', (
    tester,
  ) async {
    await open(tester, screen(FakeQueue([item(1), item(2)])));

    await pick(tester, 1);

    expect(find.text(pl.queueSelectedCount(1)), findsOneWidget);
    expect(byLogId('queue.bulk_edit'), findsOneWidget);
    expect(
      find.text(pl.queueStartNext),
      findsNothing,
      reason: 'starting is not what a selection is for',
    );
  });

  testWidgets('a tap extends the selection, and taps it away again', (
    tester,
  ) async {
    await open(tester, screen(FakeQueue([item(1), item(2)])));
    await pick(tester, 1);

    await tester.tap(find.text('Part 2'));
    await tester.pumpAndSettle();
    expect(find.text(pl.queueSelectedCount(2)), findsOneWidget);

    await tester.tap(find.text('Part 2'));
    await tester.pumpAndSettle();
    expect(find.text(pl.queueSelectedCount(1)), findsOneWidget);

    await tester.tap(find.text('Part 1'));
    await tester.pumpAndSettle();
    expect(
      byLogId('queue.bulk_edit'),
      findsNothing,
      reason: 'the last pick gone ends the mode',
    );
  });

  testWidgets('without a selection a tap does nothing', (tester) async {
    await open(tester, screen(FakeQueue([item(1)])));

    await tester.tap(find.text('Part 1'));
    await tester.pumpAndSettle();

    expect(byLogId('queue.bulk_edit'), findsNothing);
  });

  testWidgets('the close button drops the selection', (tester) async {
    await open(tester, screen(FakeQueue([item(1)])));
    await pick(tester, 1);

    await tester.tap(byLogId('queue.selection_clear'));
    await tester.pumpAndSettle();

    expect(find.text(pl.queueSelectedCount(1)), findsNothing);
    expect(find.text(pl.navQueue), findsWidgets);
  });

  testWidgets('select all takes the waiting items and leaves the printing', (
    tester,
  ) async {
    await open(
      tester,
      screen(FakeQueue([item(1), item(2), item(3, status: 'printing')])),
    );
    await pick(tester, 1);

    await tester.tap(byLogId('queue.select_all'));
    await tester.pumpAndSettle();

    expect(find.text(pl.queueSelectedCount(2)), findsOneWidget);
  });

  testWidgets('a printing item cannot be picked', (tester) async {
    await open(tester, screen(FakeQueue([item(3, status: 'printing')])));

    await tester.longPress(find.text('Part 3'));
    await tester.pumpAndSettle();

    expect(byLogId('queue.bulk_edit'), findsNothing);
  });

  testWidgets('while picking, the per-item menu is out of the way', (
    tester,
  ) async {
    await open(tester, screen(FakeQueue([item(1), item(2)])));
    expect(find.byIcon(Icons.more_vert), findsNWidgets(2));

    await pick(tester, 1);

    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('while picking, a swipe deletes nothing', (tester) async {
    await open(tester, screen(FakeQueue([item(1), item(2)])));
    Dismissible swipe() =>
        tester.widget<Dismissible>(find.byKey(const ValueKey('dismiss_2')));
    expect(swipe().direction, DismissDirection.endToStart);

    await pick(tester, 1);

    expect(
      swipe().direction,
      DismissDirection.none,
      reason: 'a swipe would delete one item out of a selection of several',
    );
  });

  testWidgets('a user who may not edit items cannot start picking', (
    tester,
  ) async {
    const reader = CurrentUser(
      id: 7,
      username: 'u',
      isAdmin: false,
      permissions: {Permissions.queueCreate},
    );
    await open(
      tester,
      screen(FakeQueue([item(1)]), extra: [currentUserOverride(reader)]),
    );

    await tester.longPress(find.text('Part 1'));
    await tester.pumpAndSettle();

    expect(byLogId('queue.bulk_edit'), findsNothing);
  });

  testWidgets('the edit button opens the bulk edit for the picked items', (
    tester,
  ) async {
    await open(tester, screen(FakeQueue([item(1), item(2), item(3)])));
    await pick(tester, 1);
    await tester.tap(find.text('Part 3'));
    await tester.pumpAndSettle();

    await tester.tap(byLogId('queue.bulk_edit'));
    await tester.pumpAndSettle();

    expect(find.text(pl.queueBulkTitle(2)), findsOneWidget);
  });

  group('queueSelectionProvider', () {
    test('drops an item that left the waiting list', () async {
      final queue = FakeQueue([item(1), item(2)]);
      final container = ProviderContainer(
        overrides: [queueProvider.overrideWith(() => queue)],
      );
      addTearDown(container.dispose);
      container.listen(queueSelectionProvider, (_, _) {});
      await container.read(queueProvider.future);
      container.read(queueSelectionProvider.notifier).selectAll([1, 2]);

      // Item 1 starts printing elsewhere, item 2 is still waiting.
      queue.replace([item(1, status: 'printing'), item(2)]);

      expect(container.read(queueSelectionProvider), {2});
    });

    test('is not touched by a poll that changes nothing for it', () async {
      final queue = FakeQueue([item(1)]);
      final container = ProviderContainer(
        overrides: [queueProvider.overrideWith(() => queue)],
      );
      addTearDown(container.dispose);
      container.listen(queueSelectionProvider, (_, _) {});
      await container.read(queueProvider.future);
      container.read(queueSelectionProvider.notifier).toggle(1);

      queue.replace([item(1), item(2)]);

      expect(container.read(queueSelectionProvider), {1});
    });
  });
}
