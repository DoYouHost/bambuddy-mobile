import 'package:bambuddy_mobile/core/models/plate_list.dart';
import 'package:bambuddy_mobile/data/batch_repository.dart';
import 'package:dio/dio.dart';
import 'package:bambuddy_mobile/features/orders/orders_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';
import 'queue_form_harness.dart';

const _batches = '/api/v1/queue/batches';

void main() {
  setUp(setUpQueueForm);

  /// What the batch routes were sent, next to the queue's [capturedBody].
  late RequestLog batchCalls;

  /// [createStatus] as in [queueFormRepo]: 0 is a dropped connection.
  List<Override> batchServer({
    required bool listing,
    required bool orders,
    int createStatus = 200,
  }) {
    final dio = testDio();
    batchCalls = captureRequests(dio);
    DioAdapter(dio: dio)
      ..onPost(_batches, data: Matchers.any, (s) {
        if (createStatus == 0) {
          s.throws(
            0,
            DioException.connectionError(
              requestOptions: RequestOptions(path: _batches),
              reason: 'dropped',
            ),
          );
          return;
        }
        s.reply(
          createStatus,
          createStatus == 200
              ? {'id': 12, 'name': 'cube ×3', 'quantity': 3, 'status': 'active'}
              : {'detail': 'boom'},
        );
      })
      ..onPost(
        '$_batches/12/ungroup',
        (s) => s.reply(200, {'ungrouped_count': 0, 'message': 'Ungrouped 0'}),
      );
    return [
      batchRepositoryProvider.overrideWithValue(BatchRepository(dio)),
      batchListingProvider.overrideWithValue(AsyncData(listing)),
      batchOrdersProvider.overrideWithValue(AsyncData(orders)),
    ];
  }

  Future<void> addCopies(WidgetTester tester, int more) async {
    for (var i = 0; i < more; i++) {
      await tester.tap(byLogId('queue_edit.copies_up'));
      await tester.pump();
    }
  }

  testWidgets('below v0.2.3 there is no copies field: it would queue one', (
    tester,
  ) async {
    await tester.pumpWidget(
      queueFormScreen(
        archiveDraft(),
        extra: batchServer(listing: false, orders: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(byLogId('queue_edit.copies_up'), findsNothing);
    await submitQueueForm(tester);
    expect(capturedBody?['quantity'], 1);
  });

  testWidgets('a multi-plate file with no plate picked orders plate 1, named', (
    tester,
  ) async {
    await tester.pumpWidget(
      queueFormScreen(
        archiveDraft(),
        plates: PlateList.fromJson({
          'plates': [
            {'index': 1, 'name': 'Base', 'object_count': 1},
            {'index': 2, 'name': 'Lid', 'object_count': 1},
          ],
          'is_multi_plate': true,
          'has_gcode': true,
        }),
        extra: batchServer(listing: true, orders: true),
      ),
    );
    await tester.pumpAndSettle();

    await addCopies(tester, 2);
    await submitQueueForm(tester);

    // The form says plate 1 and the server prints plate 1; a null target
    // would call it "whole file".
    expect((batchCalls.last.data as Map)['plates'], [
      {
        'plate_id': 1,
        'plate_name': 'Base',
        'quantity_target': 3,
        'sort_order': 0,
      },
    ]);
    expect(capturedBody?['plate_id'], 1);
  });

  testWidgets('a dropped order create stops: the order may exist', (
    tester,
  ) async {
    await tester.pumpWidget(
      queueFormScreen(
        archiveDraft(),
        extra: batchServer(listing: true, orders: true, createStatus: 0),
      ),
    );
    await tester.pumpAndSettle();

    await addCopies(tester, 2);
    await submitQueueForm(tester);

    // A grouping queued beside a committed order would leave it owing all.
    expect(capturedBody, isNull);
  });

  testWidgets('a dropped queue create keeps the order: the copies may be in', (
    tester,
  ) async {
    await tester.pumpWidget(
      queueFormScreen(
        archiveDraft(),
        createStatus: 0,
        extra: batchServer(listing: true, orders: true),
      ),
    );
    await tester.pumpAndSettle();

    await addCopies(tester, 2);
    await submitQueueForm(tester);

    expect(batchCalls.calls, ['POST $_batches']);
  });

  testWidgets('with orders: the order first, then the copies into it', (
    tester,
  ) async {
    await tester.pumpWidget(
      queueFormScreen(
        archiveDraft(plateId: 2),
        extra: batchServer(listing: true, orders: true),
      ),
    );
    await tester.pumpAndSettle();

    await addCopies(tester, 2);
    await submitQueueForm(tester);

    expect(batchCalls.calls, ['POST $_batches']);
    expect(batchCalls.last.data, {
      'name': 'cube ×3',
      'archive_id': 77,
      // Progress is counted by plate, so the target names the item's plate.
      'plates': [
        {'plate_id': 2, 'quantity_target': 3, 'sort_order': 0},
      ],
    });
    expect(capturedBody?['quantity'], 3);
    expect(capturedBody?['batch_id'], 12);
    expect(capturedBody?['plate_id'], 2);
  });

  testWidgets('without orders: the copies alone, grouped by the server', (
    tester,
  ) async {
    await tester.pumpWidget(
      queueFormScreen(
        archiveDraft(),
        extra: batchServer(listing: true, orders: false),
      ),
    );
    await tester.pumpAndSettle();

    await addCopies(tester, 2);
    await submitQueueForm(tester);

    expect(batchCalls.requests, isEmpty);
    expect(capturedBody?['quantity'], 3);
    expect(capturedBody?.containsKey('batch_id'), isFalse);
  });

  testWidgets('one copy makes no order', (tester) async {
    await tester.pumpWidget(
      queueFormScreen(
        archiveDraft(),
        extra: batchServer(listing: true, orders: true),
      ),
    );
    await tester.pumpAndSettle();

    await submitQueueForm(tester);

    expect(batchCalls.requests, isEmpty);
    expect(capturedBody?['quantity'], 1);
  });

  testWidgets('a refused order still queues the copies, as a grouping', (
    tester,
  ) async {
    await tester.pumpWidget(
      queueFormScreen(
        archiveDraft(),
        extra: batchServer(listing: true, orders: true, createStatus: 500),
      ),
    );
    await tester.pumpAndSettle();

    await addCopies(tester, 1);
    await tester.tap(
      find.widgetWithText(FilledButton, formL10n.queueCreateSubmit),
    );
    // Read before the form's own route finishes popping: pumped as the root,
    // it leaves no Scaffold to show a snack on afterwards.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // Said, since the form promised an order.
    expect(find.text(formL10n.queueEditOrderRefused), findsOneWidget);
    await tester.pumpAndSettle();
    expect(capturedBody?['quantity'], 2);
    expect(capturedBody?.containsKey('batch_id'), isFalse);
  });

  testWidgets('copies refused after the order: the empty order is removed', (
    tester,
  ) async {
    await tester.pumpWidget(
      queueFormScreen(
        archiveDraft(),
        createStatus: 400,
        extra: batchServer(listing: true, orders: true),
      ),
    );
    await tester.pumpAndSettle();

    await addCopies(tester, 2);
    await submitQueueForm(tester);

    // Left behind, it would owe three copies with nothing to clone them from.
    expect(batchCalls.calls, ['POST $_batches', 'POST $_batches/12/ungroup']);
  });
}
