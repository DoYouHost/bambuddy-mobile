import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/data/batch_repository.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/features/orders/orders_group_sheet.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';

Map<String, dynamic> _item(
  int id,
  String name, {
  int? batchId,
  int? createdBy,
}) => {
  'id': id,
  'created_by_id': createdBy,
  'position': id,
  'status': 'pending',
  'archive_name': name,
  'batch_id': batchId,
};

void main() {
  // The mock matches any body containing the mocked keys.
  late RequestLog sent;

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(Scaffold).first));

  Future<DioAdapter> pumpSheet(
    WidgetTester tester,
    List<Map<String, dynamic>> pending, {
    CurrentUser? user,
  }) async {
    final dio = testDio();
    final adapter = DioAdapter(dio: dio)
      ..onGet(
        '/api/v1/queue/',
        queryParameters: {'status': 'pending'},
        (s) => s.reply(200, pending),
      );
    sent = captureRequests(dio);
    await pumpPhone(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showGroupSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
      overrides: [
        noServerProfileOverride,
        queueRepositoryProvider.overrideWithValue(QueueRepository(dio)),
        batchRepositoryProvider.overrideWithValue(BatchRepository(dio)),
        if (user != null) currentUserOverride(user),
      ],
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return adapter;
  }

  FilledButton confirm(WidgetTester tester) => tester.widget<FilledButton>(
    find.descendant(
      of: byLogId('orders_group.confirm'),
      matching: find.byType(FilledButton),
    ),
  );

  testWidgets('groups the picked waiting jobs under the typed name', (
    tester,
  ) async {
    final adapter = await pumpSheet(tester, [
      _item(1, 'Clip'),
      _item(2, 'Hook'),
      _item(3, 'Stand'),
      _item(4, 'Already grouped', batchId: 9),
    ]);
    adapter.onPost(
      '/api/v1/queue/batches',
      data: {
        'name': 'Hardware',
        'item_ids': [1, 3],
      },
      (s) => s.reply(200, {
        'id': 10,
        'name': 'Hardware',
        'quantity': 2,
        'status': 'active',
        'pending_count': 2,
      }),
    );

    // A job in a batch already is not offered: the server would skip it.
    expect(find.text('Already grouped'), findsNothing);

    await tester.tap(find.text('Clip'));
    await tester.pump();
    await tester.enterText(byLogId('orders_group.name'), 'Hardware');
    await tester.pump();
    expect(confirm(tester).onPressed, isNull, reason: 'one job is no group');

    await tester.tap(find.text('Stand'));
    await tester.pump();
    await tester.tap(byLogId('orders_group.confirm'));
    await tester.pumpAndSettle();
    expect(sent.last.data, {
      'name': 'Hardware',
      'item_ids': [1, 3],
    });

    expect(
      find.text(l10n(tester).ordersGrouped(2, 'Hardware')),
      findsOneWidget,
    );
  });

  testWidgets('every pick skipped: says nothing was grouped, not "1 job"', (
    tester,
  ) async {
    final adapter = await pumpSheet(tester, [
      _item(1, 'Clip'),
      _item(2, 'Hook'),
    ]);
    // The server floors `quantity` at 1 for a batch it assigned nothing to.
    adapter.onPost(
      '/api/v1/queue/batches',
      data: Matchers.any,
      (s) => s.reply(200, {
        'id': 10,
        'name': 'Hardware',
        'quantity': 1,
        'status': 'active',
      }),
    );

    await tester.tap(find.text('Clip'));
    await tester.tap(find.text('Hook'));
    await tester.enterText(byLogId('orders_group.name'), 'Hardware');
    await tester.pump();
    await tester.tap(byLogId('orders_group.confirm'));
    await tester.pumpAndSettle();

    expect(find.text(l10n(tester).ordersGroupedNone), findsOneWidget);
  });

  testWidgets('someone else\'s jobs are not offered without update-all', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      [
        _item(1, 'Mine', createdBy: 1),
        _item(2, 'Also mine', createdBy: 1),
        _item(3, 'Theirs', createdBy: 7),
      ],
      user: const CurrentUser(
        id: 1,
        username: 'me',
        isAdmin: false,
        permissions: {'queue:create', 'queue:update_own'},
      ),
    );

    expect(find.text('Mine'), findsOneWidget);
    expect(find.text('Theirs'), findsNothing);
  });

  testWidgets('fewer than two ungrouped jobs: says so', (tester) async {
    await pumpSheet(tester, [_item(1, 'Clip'), _item(2, 'Hook', batchId: 9)]);

    expect(find.text(l10n(tester).ordersGroupEmpty), findsOneWidget);
  });
}
