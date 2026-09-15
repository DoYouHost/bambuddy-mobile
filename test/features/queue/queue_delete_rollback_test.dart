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

/// Three pending rows, and every delete waits for the test to answer it.
class _HeldDeletes extends QueueRepository {
  _HeldDeletes() : super(Dio());

  final deletes = <int, Completer<void>>{};

  @override
  Future<List<QueueItem>> fetchActive() async => [
    for (final id in [1, 2, 3])
      QueueItem(id: id, position: id, status: 'pending'),
  ];

  @override
  Future<void> delete(int itemId) => (deletes[itemId] = Completer()).future;
}

void main() {
  test('a failed delete does not bring back a row deleted meanwhile', () async {
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
    final notifier = container.read(queueProvider.notifier);

    final first = notifier.delete(1);
    final second = notifier.delete(2);
    repository.deletes[2]!.complete();
    await second;
    repository.deletes[1]!.completeError(
      const ApiException(AppErrorCode.badResponse, statusCode: 500),
    );
    await first;

    expect(
      [for (final i in container.read(queueProvider).requireValue) i.id],
      [1, 3],
    );
  });
}
