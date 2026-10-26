import 'package:bambuddy_mobile/core/models/print_batch.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/features/orders/order_edit_screen.dart';
import 'package:bambuddy_mobile/features/orders/orders_providers.dart';
import 'package:bambuddy_mobile/features/orders/orders_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets for the orders: the list under every
/// filter, an order's card menu and its confirmations, the group-as-batch sheet
/// with and without jobs to pick, and the order edit form with its date and
/// project pickers. The harness and the rules are in a11y_harness.dart. Orders
/// 1 to 3 are the demo's: a grouping with targets, a shop order with a stranded
/// plate, and a finished grouping. A cancelled order is not seeded, so that
/// card is built from a fixture.

/// A cancelled order, which the demo does not seed (it hides the owed counts
/// and the cancel action).
final _cancelled = PrintBatch.fromJson({
  'id': 7,
  'name': 'Cancelled drawer set',
  'status': 'cancelled',
  'created_by_username': 'demo',
  'notes': 'Replaced by a bigger order.',
  'has_targets': true,
  'target_count': 4,
  'completed_count': 1,
  'plates': [
    {'quantity_target': 4, 'completed_count': 1, 'remaining': 3},
  ],
});

/// A server whose pending queue has nothing to group.
class _NothingPending extends QueueRepository {
  _NothingPending() : super(Dio());

  @override
  Future<List<QueueItem>> fetch({int? printerId, String? status}) async =>
      const [];
}

Future<void> _openFirstMenu(WidgetTester tester) async {
  await tester.tap(byLogId('orders.actions').first);
  await tester.pumpAndSettle();
}

void main() {
  a11ySurface(
    'orders',
    home: () => const OrdersScreen(),
    shows: find.text('Gridfinity bins ×8'),
  );

  for (final (filter, shown) in [
    ('completed', find.text('IKEA SAMLA box clips ×3')),
    ('cancelled', find.text(pl.ordersEmpty)),
    ('all', find.text('IKEA SAMLA box clips ×3')),
  ]) {
    a11ySurface(
      'orders, filter $filter',
      home: () => const OrdersScreen(),
      arrange: (tester) async {
        await tester.tap(byLogId('orders.filter.$filter'));
        await tester.pumpAndSettle();
      },
      shows: shown,
    );
  }

  a11ySurface(
    'orders, cancelled order',
    overrides: [
      batchesProvider.overrideWith((ref, status) async => [_cancelled]),
    ],
    home: () => const OrdersScreen(),
    shows: find.text('Cancelled drawer set'),
  );

  a11ySurface(
    'orders, load failed',
    overrides: [
      batchesProvider.overrideWith(
        (ref, status) async => throw StateError('unreachable'),
      ),
    ],
    home: () => const OrdersScreen(),
    shows: find.text(pl.retry),
  );

  a11ySurface(
    'orders, card menu',
    home: () => const OrdersScreen(),
    arrange: _openFirstMenu,
    shows: byLogId('orders.action.cancel'),
  );

  a11ySurface(
    'orders, cancel confirmation',
    home: () => const OrdersScreen(),
    arrange: (tester) async {
      await _openFirstMenu(tester);
      await tester.tap(byLogId('orders.action.cancel'));
      await tester.pumpAndSettle();
    },
    shows: find.text(pl.ordersCancelTitle),
  );

  a11ySurface(
    'orders, ungroup confirmation of an order',
    home: () => const OrdersScreen(),
    arrange: (tester) async {
      await _openFirstMenu(tester);
      await tester.tap(byLogId('orders.action.ungroup'));
      await tester.pumpAndSettle();
    },
    shows: find.text(pl.ordersUngroupTitle),
  );

  // The finished grouping has no targets, so its confirmation reads the plain
  // grouping body and is not destructive.
  a11ySurface(
    'orders, ungroup confirmation of a grouping',
    home: () => const OrdersScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('orders.filter.completed'));
      await tester.pumpAndSettle();
      await _openFirstMenu(tester);
      await tester.tap(byLogId('orders.action.ungroup'));
      await tester.pumpAndSettle();
    },
    shows: find.text(pl.ordersUngroupBody),
  );

  // --- Group as batch ---

  Future<void> openGroup(WidgetTester tester) async {
    await tester.tap(byLogId('orders.group'));
    await tester.pumpAndSettle();
  }

  a11ySurface(
    'group sheet',
    home: () => const OrdersScreen(),
    arrange: openGroup,
    shows: byLogId('orders_group.confirm'),
  );

  a11ySurface(
    'group sheet, name typed and jobs picked',
    home: () => const OrdersScreen(),
    arrange: (tester) async {
      await openGroup(tester);
      await tester.enterText(byLogId('orders_group.name'), 'Rack parts');
      await tester.tap(byLogId('orders_group.item').at(0));
      await tester.tap(byLogId('orders_group.item').at(1));
      await tester.pumpAndSettle();
    },
    shows: byLogId('orders_group.confirm'),
  );

  a11ySurface(
    'group sheet, nothing to group',
    overrides: [queueRepositoryProvider.overrideWithValue(_NothingPending())],
    home: () => const OrdersScreen(),
    arrange: openGroup,
    shows: find.text(pl.ordersGroupEmpty),
  );

  // --- The order edit form ---

  a11ySurface(
    'order edit, an order with plates',
    home: () => const OrderEditScreen(batchId: 2),
    shows: find.text(pl.orderEditTargets),
  );

  a11ySurface(
    'order edit, a grouping',
    home: () => const OrderEditScreen(batchId: 3),
    shows: find.text(pl.orderEditTitle),
  );

  a11ySurface(
    'order edit, project select open',
    home: () => const OrderEditScreen(batchId: 2),
    arrange: (tester) async {
      await tester.tap(byLogId('order_edit.project'));
      await tester.pumpAndSettle();
    },
    shows: byLogId('order_edit.project.option'),
  );

  a11ySurface(
    'order edit, date picker',
    home: () => const OrderEditScreen(batchId: 2),
    arrange: (tester) async {
      await tester.tap(byLogId('order_edit.due'));
      await tester.pumpAndSettle();
    },
    shows: find.byType(DatePickerDialog),
  );

  a11ySurface(
    'order edit, name missing',
    home: () => const OrderEditScreen(batchId: 2),
    arrange: (tester) async {
      await tester.enterText(byLogId('order_edit.name'), '');
      await tester.tap(byLogId('order_edit.save'));
      await tester.pumpAndSettle();
    },
    shows: find.text(pl.orderEditErrName),
  );

  a11ySurface(
    'order edit, order not found',
    home: () => const OrderEditScreen(batchId: 99),
    shows: find.text(pl.retry),
  );
}
