import 'package:bambuddy_mobile/core/format/datetime_format.dart';
import 'package:bambuddy_mobile/core/models/print_batch.dart';
import 'package:bambuddy_mobile/core/models/project.dart';
import 'package:bambuddy_mobile/data/batch_repository.dart';
import 'package:bambuddy_mobile/features/orders/order_edit_screen.dart';
import 'package:bambuddy_mobile/features/orders/orders_providers.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';

const _path = '/api/v1/queue/batches/2';

const _reply = <String, dynamic>{
  'id': 2,
  'name': 'Keychain set',
  'quantity': 6,
  'status': 'active',
};

PrintBatch _order({String? due, int? projectId}) => PrintBatch.fromJson({
  ..._reply,
  'notes': 'For the shop',
  'due_date': due,
  'project_id': projectId,
  'has_targets': true,
  'plates': [
    {
      'plate_id': 1,
      'plate_name': 'Tags',
      'quantity_target': 4,
      'completed_count': 2,
    },
    {'plate_id': null, 'quantity_target': 2},
  ],
});

void main() {
  // The mock matches any body containing the mocked keys.
  late RequestLog sent;

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(Scaffold).first));

  /// Opens the form from a host page, so saving has somewhere to pop back to.
  Future<DioAdapter> pumpEdit(WidgetTester tester, PrintBatch batch) async {
    final dio = testDio();
    final adapter = mockServer(dio);
    sent = captureRequests(dio);
    await pumpPhone(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const OrderEditScreen(batchId: 2),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
      overrides: [
        noServerProfileOverride,
        batchRepositoryProvider.overrideWithValue(BatchRepository(dio)),
        batchDetailProvider(2).overrideWith((ref) async => batch),
        orderProjectsProvider.overrideWith(
          (ref) async => const [
            ProjectListResponse(id: 1, name: 'Workshop'),
            ProjectListResponse(id: 2, name: 'Shop'),
          ],
        ),
      ],
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return adapter;
  }

  testWidgets('only what changed is sent', (tester) async {
    final adapter = await pumpEdit(tester, _order());
    adapter.onPatch(
      _path,
      data: {'notes': 'For the fair'},
      (s) => s.reply(200, _reply),
    );

    await tester.enterText(byLogId('order_edit.notes'), 'For the fair');
    await tester.tap(byLogId('order_edit.save'));
    await tester.pumpAndSettle();

    expect(find.text(l10n(tester).orderEditSaved), findsOneWidget);
    expect(find.byType(OrderEditScreen), findsNothing);
    expect(sent.last.data, {'notes': 'For the fair'});
  });

  testWidgets('a changed target sends every plate, the whole file as null', (
    tester,
  ) async {
    final adapter = await pumpEdit(tester, _order());
    adapter.onPatch(
      _path,
      data: {
        'plates': [
          {
            'plate_id': 1,
            'plate_name': 'Tags',
            'quantity_target': 5,
            'sort_order': 0,
          },
          {'plate_id': null, 'quantity_target': 2, 'sort_order': 1},
        ],
      },
      (s) => s.reply(200, _reply),
    );

    await tester.tap(byLogId('order_edit.target_up').first);
    await tester.pump();
    await tester.tap(byLogId('order_edit.save'));
    await tester.pumpAndSettle();

    expect(find.text(l10n(tester).orderEditSaved), findsOneWidget);
    expect((sent.last.data as Map).keys, ['plates']);
  });

  testWidgets('an emptied name is caught before anything is sent', (
    tester,
  ) async {
    await pumpEdit(tester, _order());

    await tester.enterText(byLogId('order_edit.name'), '  ');
    await tester.tap(byLogId('order_edit.save'));
    await tester.pumpAndSettle();

    expect(sent.requests, isEmpty);
    expect(find.text(l10n(tester).orderEditErrName), findsOneWidget);
    expect(find.byType(OrderEditScreen), findsOneWidget);
  });

  testWidgets('a due date or project once set says it cannot be removed', (
    tester,
  ) async {
    await pumpEdit(tester, _order(due: '2026-10-01T21:59:59', projectId: 1));
    final l = l10n(tester);

    expect(find.text(l.orderEditDueHint), findsOneWidget);
    expect(find.text(l.orderEditProjectHint), findsOneWidget);

    await tester.tap(byLogId('order_edit.project'));
    await tester.pumpAndSettle();
    expect(byLogId('order_edit.project.none'), findsNothing);
  });

  testWidgets('a write from the list in flight holds the save', (tester) async {
    await pumpEdit(tester, _order());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OrderEditScreen)),
    );
    container.read(ordersInFlightProvider.notifier).state = {2};
    await tester.pump();

    await tester.enterText(byLogId('order_edit.notes'), 'changed');
    await tester.tap(byLogId('order_edit.save'), warnIfMissed: false);
    await tester.pump();

    expect(sent.requests, isEmpty);
    expect(find.byType(OrderEditScreen), findsOneWidget);
  });

  testWidgets('a past due date opens on its own day and survives an OK', (
    tester,
  ) async {
    final adapter = await pumpEdit(tester, _order(due: '2020-01-10T12:00:00'));
    adapter.onPatch(_path, data: Matchers.any, (s) => s.reply(200, _reply));

    await tester.tap(byLogId('order_edit.due'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final shown = DateTimeFormats.of(
      tester.element(find.byType(OrderEditScreen)),
    ).date(DateTime(2020, 1, 10));
    expect(find.text(shown), findsOneWidget);
  });

  testWidgets('a due date years out still opens the calendar', (tester) async {
    await pumpEdit(tester, _order(due: '2040-06-01T21:59:59'));

    await tester.tap(byLogId('order_edit.due'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('without them there is a none choice and no warning', (
    tester,
  ) async {
    await pumpEdit(tester, _order());
    final l = l10n(tester);

    expect(find.text(l.orderEditDueHint), findsNothing);
    expect(find.text(l.orderEditDueNone), findsOneWidget);
    await tester.tap(byLogId('order_edit.project'));
    await tester.pumpAndSettle();
    expect(byLogId('order_edit.project.none'), findsWidgets);
  });

  testWidgets('every target at zero is refused in the user\'s words', (
    tester,
  ) async {
    final adapter = await pumpEdit(tester, _order());
    adapter.onPatch(
      _path,
      data: Matchers.any,
      (s) => s.reply(400, {'detail': 'Order must request at least one print'}),
    );

    // 4 and 2 down to nothing: the form lets it through, the server refuses.
    for (final (row, times) in [(0, 4), (1, 2)]) {
      for (var i = 0; i < times; i++) {
        await tester.tap(byLogId('order_edit.target_down').at(row));
        await tester.pump();
      }
    }
    await tester.tap(byLogId('order_edit.save'));
    await tester.pumpAndSettle();

    expect(sent.last.data, {
      'plates': [
        {
          'plate_id': 1,
          'plate_name': 'Tags',
          'quantity_target': 0,
          'sort_order': 0,
        },
        {'plate_id': null, 'quantity_target': 0, 'sort_order': 1},
      ],
    });
    expect(find.text(l10n(tester).orderEditErrNothingAsked), findsOneWidget);
    expect(find.byType(OrderEditScreen), findsOneWidget);
  });
}
