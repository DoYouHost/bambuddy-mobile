import 'dart:async';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Four pending rows, and every delete waits for the test to answer it.
class _HeldDeletes extends QueueRepository {
  _HeldDeletes() : super(Dio());

  final deletes = <int, Completer<void>>{};

  @override
  Future<List<QueueItem>> fetchActive() async => [
    for (final id in [1, 2, 3, 4])
      QueueItem(id: id, position: id, status: 'pending'),
  ];

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
}
