import 'package:bambuddy_mobile/core/models/plate_list.dart';
import 'package:bambuddy_mobile/data/batch_repository.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/features/orders/orders_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_create_service.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';
import 'queue_form_harness.dart';

const _batches = '/api/v1/queue/batches';

void main() {
  setUp(setUpQueueForm);

  late RequestLog batchCalls;

  /// A container whose batch routes answer [orderStatus]; orders are supported.
  ProviderContainer container({int orderStatus = 200}) {
    final dio = testDio();
    batchCalls = captureRequests(dio);
    mockServer(dio).onPost(
      _batches,
      data: Matchers.any,
      (s) => s.reply(
        orderStatus,
        orderStatus == 200
            ? {'id': 12, 'name': 'cube ×3', 'quantity': 3, 'status': 'active'}
            : {'detail': 'refused'},
      ),
    );
    final c = ProviderContainer(
      overrides: [
        batchRepositoryProvider.overrideWithValue(BatchRepository(dio)),
        batchOrdersProvider.overrideWithValue(const AsyncData(true)),
        queueOutcomeProvider.overrideWithValue(const AsyncData(false)),
        plateListProvider.overrideWith((ref, source) async => PlateList.none),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<QueueCreateOutcome> create(
    ProviderContainer c,
    QueueRepository repo, {
    required QueueCreateOptions Function() buildOptions,
    int copies = 3,
  }) => createQueueJobs(
    repo: repo,
    providers: c,
    archiveId: 77,
    libraryFileId: null,
    sourceName: 'cube.gcode.3mf',
    printerId: 1,
    copies: copies,
    insertAtTop: true,
    plateId: 2,
    confirmOutcomeChoice: null,
    confirmOutcomeSticky: false,
    buildOptions: buildOptions,
  );

  test('the options are built after the order exists, not before', () async {
    final c = container();
    final repo = queueFormRepo(triState: true);
    var batchCallsWhenBuilt = -1;
    var queueBodyWhenBuilt = 'unset';

    await create(
      c,
      repo,
      buildOptions: () {
        batchCallsWhenBuilt = batchCalls.calls.length;
        queueBodyWhenBuilt = '${capturedBody?['batch_id']}';
        return const QueueCreateOptions();
      },
    );

    expect(batchCallsWhenBuilt, 1);
    expect(queueBodyWhenBuilt, 'null');
    expect(capturedBody?['batch_id'], 12);
  });

  test(
    'a refused order is reported, and the copies go in as a grouping',
    () async {
      final c = container(orderStatus: 400);
      final repo = queueFormRepo(triState: true);

      final outcome = await create(
        c,
        repo,
        buildOptions: () => const QueueCreateOptions(),
      );

      expect(outcome.orderRefused, isTrue);
      expect(capturedBody?['quantity'], 3);
      expect(capturedBody?.containsKey('batch_id'), isFalse);
      expect(capturedBody?['plate_id'], 2);
    },
  );

  test('an order made is not reported as refused', () async {
    final c = container();
    final repo = queueFormRepo(triState: true);

    final outcome = await create(
      c,
      repo,
      buildOptions: () => const QueueCreateOptions(),
    );

    expect(outcome.orderRefused, isFalse);
  });

  test('one copy makes no order and keeps the plate that was picked', () async {
    final c = container();
    final repo = queueFormRepo(triState: true);

    await create(
      c,
      repo,
      copies: 1,
      buildOptions: () => const QueueCreateOptions(),
    );

    expect(batchCalls.calls, isEmpty);
    expect(capturedBody?['plate_id'], 2);
    expect(capturedBody?.containsKey('batch_id'), isFalse);
  });

  test('options that set the plate are refused: it has one owner', () async {
    final c = container();
    final repo = queueFormRepo(triState: true);

    expect(
      create(c, repo, buildOptions: () => const QueueCreateOptions(plateId: 9)),
      throwsA(isA<AssertionError>()),
    );
  });
}
