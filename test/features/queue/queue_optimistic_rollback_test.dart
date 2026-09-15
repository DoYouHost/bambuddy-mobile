import 'dart:async';

import 'package:bambuddy_mobile/core/api/action_outcome.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Four pending rows, and every write waits for the test to answer it.
class _HeldDeletes extends QueueRepository {
  _HeldDeletes() : super(Dio());

  final deletes = <int, Completer<void>>{};
  Completer<void>? reorders;

  @override
  Future<void> reorder(List<({int id, int position})> positions) {
    reorderCalls++;
    return (reorders = Completer()).future;
  }

  /// What the server holds; a test changes it before a refresh.
  var active = [
    for (final id in [1, 2, 3, 4])
      QueueItem(id: id, position: id, status: 'pending'),
  ];

  @override
  Future<List<QueueItem>> fetchActive() async => active;

  int reorderCalls = 0;

  @override
  Future<void> delete(int itemId) => (deletes[itemId] = Completer()).future;
}

List<int> ids(ProviderContainer container) => [
  for (final i in container.read(queueProvider).requireValue) i.id,
];

Future<(_HeldDeletes, ProviderContainer)> open() async {
  final repository = _HeldDeletes();
  final container = ProviderContainer(
    overrides: [
      queueRepositoryProvider.overrideWithValue(repository),
      fakeServerProfileOverride(),
    ],
  );
  addTearDown(container.dispose);
  container.listen(queueProvider, (_, _) {});
  await container.read(queueProvider.future);
  return (repository, container);
}

const _refused = ApiException(AppErrorCode.badResponse, statusCode: 500);

void main() {
  test('a failed delete does not bring back a row deleted meanwhile', () async {
    final (repository, container) = await open();
    final notifier = container.read(queueProvider.notifier);

    final first = notifier.delete(1);
    final second = notifier.delete(2);
    repository.deletes[2]!.complete();
    await second;
    repository.deletes[1]!.completeError(
      const ApiException(AppErrorCode.badResponse, statusCode: 500),
    );
    await first;

    expect(ids(container), [1, 3, 4]);
  });

  test('a row put back takes its place in the queue order, not its old '
      'index', () async {
    final (repository, container) = await open();
    final notifier = container.read(queueProvider.notifier);

    // 2 sat at index 1; with 1 gone, index 1 is between 3 and 4.
    final second = notifier.delete(2);
    final first = notifier.delete(1);
    repository.deletes[1]!.complete();
    await first;
    repository.deletes[2]!.completeError(
      const ApiException(AppErrorCode.badResponse, statusCode: 500),
    );
    await second;

    expect(ids(container), [2, 3, 4]);
  });

  test('an unexpected failure still puts the row back', () async {
    final (repository, container) = await open();
    final delete = container.read(queueProvider.notifier).delete(2);
    repository.deletes[2]!.completeError(StateError('bug'));

    await expectLater(delete, throwsStateError);
    expect(ids(container), [1, 2, 3, 4]);
  });
  test(
    'a failed reorder restores the order, not a row deleted meanwhile',
    () async {
      final (repository, container) = await open();
      final notifier = container.read(queueProvider.notifier);

      final reorder = notifier.reorder(0, 2);
      expect(ids(container), [2, 3, 1, 4]);
      final delete = notifier.delete(3);
      repository.deletes[3]!.complete();
      await delete;
      repository.reorders!.completeError(_refused);
      await reorder;

      expect(ids(container), [1, 2, 4]);
    },
  );

  test('a failed delete keeps a reorder that already landed', () async {
    final (repository, container) = await open();
    final notifier = container.read(queueProvider.notifier);

    final reorder = notifier.reorder(0, 2);
    repository.reorders!.complete();
    await reorder;
    final delete = notifier.delete(3);
    repository.deletes[3]!.completeError(_refused);
    await delete;

    expect(ids(container), [2, 3, 1, 4]);
  });

  test('an unexpected reorder failure still restores the order', () async {
    final (repository, container) = await open();
    final reorder = container.read(queueProvider.notifier).reorder(0, 2);
    repository.reorders!.completeError(StateError('bug'));

    await expectLater(reorder, throwsStateError);
    expect(ids(container), [1, 2, 3, 4]);
  });
  test(
    'a failed delete keeps a reorder that landed while it was out',
    () async {
      final (repository, container) = await open();
      final notifier = container.read(queueProvider.notifier);

      final delete = notifier.delete(4);
      final reorder = notifier.reorder(1, 0);
      repository.reorders!.complete();
      await reorder;
      expect(ids(container), [2, 1, 3]);
      repository.deletes[4]!.completeError(_refused);
      await delete;

      expect(ids(container), [2, 1, 3, 4]);
    },
  );

  test('a row a refresh added keeps its place through a rollback', () async {
    final (repository, container) = await open();
    final notifier = container.read(queueProvider.notifier);

    final reorder = notifier.reorder(0, 2);
    // Added on the web UI at the front, and the server has no drag yet.
    repository.active = [
      const QueueItem(id: 9, position: 0, status: 'pending'),
      ...repository.active,
    ];
    await notifier.refresh();
    repository.reorders!.completeError(_refused);
    await reorder;

    expect(ids(container), [9, 1, 2, 3, 4]);
  });

  test('a drag while another is out is dropped, not sent', () async {
    final (repository, container) = await open();
    final notifier = container.read(queueProvider.notifier);

    final first = notifier.reorder(0, 2);
    expect(await notifier.reorder(3, 0), same(ActionOutcome.ok));
    expect(repository.reorderCalls, 1);
    expect(ids(container), [2, 3, 1, 4]);

    repository.reorders!.completeError(_refused);
    await first;
    expect(ids(container), [1, 2, 3, 4]);
  });

  test('indices from a list that has since shrunk change nothing', () async {
    final (repository, container) = await open();
    final notifier = container.read(queueProvider.notifier);

    expect(await notifier.reorder(4, 0), same(ActionOutcome.ok));
    expect(await notifier.reorder(0, 4), same(ActionOutcome.ok));
    expect(repository.reorderCalls, 0);
    expect(ids(container), [1, 2, 3, 4]);
  });
}
