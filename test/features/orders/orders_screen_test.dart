import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/print_batch.dart';
import 'package:bambuddy_mobile/data/batch_repository.dart';
import 'package:bambuddy_mobile/features/orders/orders_providers.dart';
import 'package:bambuddy_mobile/features/orders/orders_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';

const _path = '/api/v1/queue/batches';

/// The demo's shop order: one plate done, one owing two runs, one stranded.
PrintBatch _shopOrder() => PrintBatch.fromJson(_shopOrderJson);

const _shopOrderJson = <String, dynamic>{
  'id': 2,
  'name': 'Keychain set',
  'quantity': 10,
  'status': 'active',
  'external_source': 'shopify',
  'external_ref': '#1042',
  'completed_count': 5,
  'failed_count': 1,
  'has_targets': true,
  'target_count': 10,
  'remaining_count': 4,
  'dispatchable_count': 2,
  'plates': [
    {
      'plate_id': 1,
      'plate_name': 'Tags',
      'quantity_target': 4,
      'completed_count': 4,
    },
    {
      'plate_id': 2,
      'plate_name': 'Rings',
      'quantity_target': 4,
      'completed_count': 1,
      'failed_count': 1,
      'remaining': 2,
      'can_dispatch': true,
    },
    {
      'plate_id': 3,
      'quantity_target': 2,
      'remaining': 2,
      'can_dispatch': false,
    },
  ],
};

PrintBatch _grouping() => PrintBatch.fromJson({
  'id': 3,
  'name': 'Phone stand ×3',
  'quantity': 3,
  'status': 'active',
  'pending_count': 2,
  'completed_count': 1,
});

void main() {
  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(Scaffold).first));

  late List<PrintBatchStatus?> asked;
  // The mock matches any body containing the mocked keys — `{}` matches all.
  late RequestLog sent;

  Future<DioAdapter> pumpOrders(
    WidgetTester tester,
    List<PrintBatch> batches, {
    bool orders = true,
    bool grouping = true,
    CurrentUser? user,
  }) async {
    final dio = testDio();
    final adapter = DioAdapter(dio: dio);
    sent = captureRequests(dio);
    asked = [];
    await pumpPhone(
      tester,
      const OrdersScreen(),
      overrides: [
        noServerProfileOverride,
        batchRepositoryProvider.overrideWithValue(BatchRepository(dio)),
        batchOrdersProvider.overrideWithValue(AsyncData(orders)),
        if (user != null) currentUserOverride(user),
        batchGroupingProvider.overrideWithValue(AsyncData(grouping)),
        batchesProvider.overrideWith((ref, status) async {
          asked.add(status);
          return batches;
        }),
      ],
    );
    await tester.pumpAndSettle();
    return adapter;
  }

  testWidgets('an order shows its plates, what is owed and what is stuck', (
    tester,
  ) async {
    await pumpOrders(tester, [_shopOrder()]);
    final l = l10n(tester);

    expect(asked, [PrintBatchStatus.active]);
    expect(find.text('shopify · #1042'), findsOneWidget);
    expect(find.text('Rings'), findsOneWidget);
    // A plate without a stored name is named by its number.
    expect(find.text(l.archivePlate(3)), findsOneWidget);
    expect(find.text(l.ordersStrandedNotice(2, 4)), findsOneWidget);
    expect(find.text(l.ordersStrandedPlate), findsOneWidget);
    expect(find.text(l.ordersDispatchRemaining(2)), findsOneWidget);
    // Only the plate that owes runs and can be cloned offers them.
    expect(byLogId('orders.dispatch_plate'), findsOneWidget);
  });

  testWidgets('a grouping owes nothing, so it offers nothing to queue', (
    tester,
  ) async {
    await pumpOrders(tester, [_grouping()]);
    final l = l10n(tester);

    expect(find.text(l.ordersGroupingOnly), findsOneWidget);
    expect(find.text(l.ordersProgress(1, 3)), findsOneWidget);
    expect(byLogId('orders.dispatch'), findsNothing);
  });

  testWidgets('queue the rest: one request, and no second while it runs', (
    tester,
  ) async {
    final adapter = await pumpOrders(tester, [_shopOrder()]);
    adapter.onPost(
      '$_path/2/dispatch',
      data: <String, dynamic>{},
      (s) => s.reply(200, _batchJson, delay: const Duration(seconds: 10)),
    );
    final l = l10n(tester);

    await tester.tap(find.text(l.ordersDispatchRemaining(2)));
    await tester.pump(const Duration(milliseconds: 50));

    final button = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(l.ordersDispatchRemaining(2)),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(button.onPressed, isNull, reason: 'a second tap would queue twice');

    // A filter switch rebuilds every card; the new one must still know.
    // Settling waits for frames, not for the reply's timer, which stays out.
    await tester.tap(byLogId('orders.filter.all'));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('orders.filter.active'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(l.ordersDispatchRemaining(2)),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 50));

    // Past the reply's delay: settling alone does not wait for a timer.
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(sent.calls, ['POST $_path/2/dispatch']);
    expect(sent.last.data, <String, dynamic>{});
    expect(find.text(l.ordersDispatched('Keychain set')), findsOneWidget);
  });

  testWidgets('one plate is dispatched by its id, and says which', (
    tester,
  ) async {
    final adapter = await pumpOrders(tester, [_shopOrder()]);
    adapter.onPost(
      '$_path/2/dispatch',
      data: {'plate_id': 2, 'only_plate': true},
      (s) => s.reply(200, _batchJson),
    );

    await tester.tap(byLogId('orders.dispatch_plate'));
    await tester.pumpAndSettle();
    expect(sent.last.data, {'plate_id': 2, 'only_plate': true});

    expect(
      find.text(l10n(tester).ordersPlateDispatched('Rings', 'Keychain set')),
      findsOneWidget,
    );
  });

  testWidgets('a stranded refusal is said in the user\'s words', (
    tester,
  ) async {
    final adapter = await pumpOrders(tester, [_shopOrder()]);
    adapter.onPost(
      '$_path/2/dispatch',
      data: <String, dynamic>{},
      (s) => s.reply(400, {
        'detail':
            'Plate 3 has no queued or finished run to copy settings from. '
            'Queue the plate once from the file, then dispatch the rest.',
      }),
    );
    final l = l10n(tester);

    await tester.tap(find.text(l.ordersDispatchRemaining(2)));
    await tester.pumpAndSettle();

    // The plate the server named survives the translation.
    expect(find.text(l.ordersErrStranded('Plate 3')), findsOneWidget);
  });

  testWidgets('a 404 says the order is gone, not "error 404"', (tester) async {
    final adapter = await pumpOrders(tester, [_shopOrder()]);
    adapter.onPost(
      '$_path/2/dispatch',
      data: <String, dynamic>{},
      (s) => s.reply(404, {'detail': 'Batch not found'}),
    );
    final l = l10n(tester);

    await tester.tap(find.text(l.ordersDispatchRemaining(2)));
    await tester.pumpAndSettle();

    expect(find.text(l.ordersErrGone), findsOneWidget);
  });

  testWidgets('someone else\'s order offers nothing that would 404', (
    tester,
  ) async {
    final theirs = PrintBatch.fromJson({..._shopOrderJson, 'created_by_id': 7});
    await pumpOrders(
      tester,
      [theirs],
      user: const CurrentUser(
        id: 1,
        username: 'me',
        isAdmin: false,
        permissionsKnown: true,
        permissions: {'queue:create', 'queue:update_own', 'queue:delete_all'},
      ),
    );

    expect(byLogId('orders.dispatch'), findsNothing);
    expect(byLogId('orders.dispatch_plate'), findsNothing);
    await tester.tap(byLogId('orders.actions'));
    await tester.pumpAndSettle();
    // Cancel is the one write the server does not look the owner up for.
    expect(byLogId('orders.action.cancel'), findsOneWidget);
    expect(byLogId('orders.action.ungroup'), findsNothing);
    expect(byLogId('orders.action.edit'), findsNothing);
  });

  testWidgets('a cancelled order owes nothing on its numbers line', (
    tester,
  ) async {
    final cancelled = PrintBatch.fromJson({
      ..._shopOrderJson,
      'status': 'cancelled',
    });
    await pumpOrders(tester, [cancelled]);
    final l = l10n(tester);

    expect(find.textContaining(l.ordersOwed(4)), findsNothing);
    expect(find.text(l.ordersStrandedNotice(2, 4)), findsNothing);
  });

  testWidgets('cancelling asks first, then sends the DELETE', (tester) async {
    final adapter = await pumpOrders(tester, [_shopOrder()]);
    adapter.onDelete(
      '$_path/2',
      (s) => s.reply(200, {'message': 'Batch cancelled'}),
    );
    final l = l10n(tester);

    await tester.tap(byLogId('orders.actions'));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('orders.action.cancel'));
    await tester.pumpAndSettle();
    expect(find.text(l.ordersCancelTitle), findsOneWidget);

    await tester.tap(byLogId('orders.cancel_confirm.confirm'));
    await tester.pumpAndSettle();

    expect(find.text(l.ordersCancelled), findsOneWidget);
  });

  testWidgets('ungrouping reports how many items left the batch', (
    tester,
  ) async {
    final adapter = await pumpOrders(tester, [_grouping()]);
    adapter.onPost(
      '$_path/3/ungroup',
      (s) => s.reply(200, {'ungrouped_count': 2, 'message': 'Ungrouped 2'}),
    );
    final l = l10n(tester);

    await tester.tap(byLogId('orders.actions'));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('orders.action.ungroup'));
    await tester.pumpAndSettle();
    expect(find.text(l.ordersUngroupBody), findsOneWidget);
    await tester.tap(byLogId('orders.ungroup_confirm.confirm'));
    await tester.pumpAndSettle();

    expect(find.text(l.ordersUngrouped(2)), findsOneWidget);
  });

  testWidgets('below 0.2.4.8 nothing offers to group or ungroup', (
    tester,
  ) async {
    await pumpOrders(tester, [_grouping()], orders: false, grouping: false);

    expect(byLogId('orders.group'), findsNothing);
    await tester.tap(byLogId('orders.actions'));
    await tester.pumpAndSettle();
    expect(byLogId('orders.action.ungroup'), findsNothing);
    expect(byLogId('orders.action.cancel'), findsOneWidget);
    // PATCH is 1.2.5.3+.
    expect(byLogId('orders.action.edit'), findsNothing);
  });

  testWidgets('a cancelled order can be reopened, and says so', (tester) async {
    final cancelled = PrintBatch.fromJson({
      ..._batchJson,
      'status': 'cancelled',
      'has_targets': true,
      'target_count': 4,
      'remaining_count': 3,
      'dispatchable_count': 3,
    });
    final adapter = await pumpOrders(tester, [cancelled]);
    adapter.onPatch(
      '$_path/2',
      data: {'status': 'active'},
      (s) => s.reply(200, _batchJson),
    );
    final l = l10n(tester);

    // Nothing to queue on a cancelled order, and nothing to cancel.
    expect(byLogId('orders.dispatch'), findsNothing);
    await tester.tap(byLogId('orders.actions'));
    await tester.pumpAndSettle();
    expect(byLogId('orders.action.cancel'), findsNothing);
    await tester.tap(byLogId('orders.action.reopen'));
    await tester.pumpAndSettle();

    expect(find.text(l.ordersReopened), findsOneWidget);
  });

  testWidgets('a grouping cannot be reopened: it would owe nothing', (
    tester,
  ) async {
    final cancelled = PrintBatch.fromJson({
      ..._batchJson,
      'status': 'cancelled',
    });
    await pumpOrders(tester, [cancelled]);

    await tester.tap(byLogId('orders.actions'));
    await tester.pumpAndSettle();
    expect(byLogId('orders.action.reopen'), findsNothing);
    expect(byLogId('orders.action.edit'), findsOneWidget);
  });

  testWidgets('the filter asks the server for that status, and All for none', (
    tester,
  ) async {
    await pumpOrders(tester, const []);
    final l = l10n(tester);
    expect(find.text(l.ordersEmpty), findsOneWidget);

    await tester.tap(byLogId('orders.filter.completed'));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('orders.filter.all'));
    await tester.pumpAndSettle();

    expect(asked, [PrintBatchStatus.active, PrintBatchStatus.completed, null]);
  });
}

const _batchJson = <String, dynamic>{
  'id': 2,
  'name': 'Keychain set',
  'quantity': 10,
  'status': 'active',
};
