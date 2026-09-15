import 'dart:async';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Every write waits for the test to answer it, so two of them can overlap.
class _HeldWrites extends ArchiveRepository {
  _HeldWrites() : super(Dio());

  final deletes = <int, Completer<void>>{};
  final favorites = <int, Completer<Archive>>{};

  @override
  Future<void> delete(int archiveId, {bool purgeStats = false}) =>
      (deletes[archiveId] = Completer()).future;

  @override
  Future<Archive> toggleFavorite(int archiveId) =>
      (favorites[archiveId] = Completer()).future;
}

const _refused = ApiException(AppErrorCode.badResponse, statusCode: 500);

Archive _row(int id) =>
    Archive(id: id, filename: '$id.gcode.3mf', status: 'completed');

void main() {
  late _HeldWrites repository;
  late ProviderContainer container;

  setUp(() async {
    repository = _HeldWrites();
    container = ProviderContainer(
      overrides: [
        archiveListOverride([_row(1), _row(2), _row(3)]),
        archiveRepositoryProvider.overrideWithValue(repository),
        noServerProfileOverride,
      ],
    );
    addTearDown(container.dispose);
    container.listen(archiveProvider, (_, _) {});
    await container.read(archiveProvider.future);
  });

  ArchiveNotifier notifier() => container.read(archiveProvider.notifier);
  List<int> ids() => [
    for (final a in container.read(archiveProvider).requireValue) a.id,
  ];

  test('a failed delete does not bring back a row deleted meanwhile', () async {
    final first = notifier().delete(1, purgeStats: false);
    final second = notifier().delete(2, purgeStats: false);

    repository.deletes[2]!.complete();
    expect(await second, isTrue);
    repository.deletes[1]!.completeError(_refused);
    expect(await first, isFalse);

    // Row 1 returns to where it was; row 2 stays gone.
    expect(ids(), [1, 3]);
  });

  test('a failed favorite puts back its flag and nothing else', () async {
    final toggle = notifier().toggleFavorite(1);
    final delete = notifier().delete(2, purgeStats: false);
    repository.deletes[2]!.complete();
    await delete;

    repository.favorites[1]!.completeError(_refused);
    expect(await toggle, isFalse);

    expect(ids(), [1, 3]);
    expect(
      container.read(archiveProvider).requireValue.first.isFavorite,
      isFalse,
    );
  });

  test('a bulk delete keeps what changed while it ran', () async {
    final bulk = notifier().deleteMany({1}, purgeStats: false);
    final single = notifier().delete(2, purgeStats: false);
    repository.deletes[2]!.complete();
    await single;

    repository.deletes[1]!.complete();
    expect(await bulk, (ok: 1, failed: 0));

    expect(ids(), [3]);
  });
}
