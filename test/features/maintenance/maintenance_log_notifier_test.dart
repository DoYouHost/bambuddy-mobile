import 'dart:async';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/maintenance.dart';
import 'package:bambuddy_mobile/data/maintenance_repository.dart';
import 'package:bambuddy_mobile/features/maintenance/maintenance_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

MaintenanceLogEntry entry(int id) => MaintenanceLogEntry(id: id);

/// A log the test controls: [rows] is what the server holds, newest first.
class _Server extends MaintenanceRepository {
  _Server(this.rows) : super(Dio());

  List<MaintenanceLogEntry> rows;
  final fetches = <({int printer, int offset})>[];
  final deleted = <int>[];
  final cleanups = <({int days, int? printer})>[];
  Completer<void>? hold;

  /// What the next calls do, one entry each, before the fields below apply.
  final scripts = <({Completer<void>? hold, Object? fail})>[];

  /// The offset whose answer waits for [hold]; null holds every one.
  int? holdOffset;
  Object? failure;

  /// What the server says it holds, when it is not [rows]'s length.
  int? claimedTotal;

  /// Rows the server sends that do not parse, so they never reach the screen.
  Set<int> unparseable = {};

  @override
  Future<MaintenanceLogPage> fetchLog(
    int printerId, {
    int limit = MaintenanceRepository.logPageSize,
    int offset = 0,
  }) async {
    fetches.add((printer: printerId, offset: offset));
    final script = scripts.isEmpty ? null : scripts.removeAt(0);
    await script?.hold?.future;
    if (script?.fail case final Object failure) throw failure;
    if (holdOffset == null || holdOffset == offset) await hold?.future;
    final failure = this.failure;
    if (failure != null) throw failure;
    final sent = rows.skip(offset).take(limit).toList();
    return (
      items: [
        for (final e in sent)
          if (!unparseable.contains(e.id)) e,
      ],
      total: claimedTotal ?? rows.length,
      received: sent.length,
    );
  }

  @override
  Future<void> deleteLogEntry(int entryId) async {
    deleted.add(entryId);
    rows = [
      for (final e in rows)
        if (e.id != entryId) e,
    ];
  }

  @override
  Future<int> cleanUpLog({required int olderThanDays, int? printerId}) async {
    cleanups.add((days: olderThanDays, printer: printerId));
    return 2;
  }
}

Future<(_Server, ProviderContainer)> open(
  int rows, {
  Set<int> unparseable = const {},
  bool withProfile = true,
}) async {
  final server = _Server([for (var i = rows; i >= 1; i--) entry(i)])
    ..unparseable = {...unparseable};
  final container = ProviderContainer(
    retry: neverRetry,
    overrides: [
      maintenanceRepositoryProvider.overrideWithValue(server),
      withProfile ? fakeServerProfileOverride() : noServerProfileOverride,
    ],
  );
  addTearDown(container.dispose);
  container.listen(maintenanceLogProvider(4), (_, _) {});
  await container.read(maintenanceLogProvider(4).future);
  return (server, container);
}

List<int> ids(ProviderContainer c) => [
  for (final e in c.read(maintenanceLogProvider(4)).requireValue.entries) e.id,
];

void main() {
  const logId = 'maintenance_log.more';

  test('the first page is what the screen starts with', () async {
    final (server, container) = await open(120);

    final view = container.read(maintenanceLogProvider(4)).requireValue;
    expect(view.entries, hasLength(50));
    expect(view.total, 120);
    expect(server.fetches, [(printer: 4, offset: 0)]);
    expect(container.read(maintenanceLogProvider(4).notifier).hasMore, isTrue);
  });

  test('more pages append, until nothing is left', () async {
    final (server, container) = await open(120);
    final notifier = container.read(maintenanceLogProvider(4).notifier);

    await notifier.loadMore(logId: logId);
    await notifier.loadMore(logId: logId);

    expect(ids(container), [for (var i = 120; i >= 1; i--) i]);
    expect(notifier.hasMore, isFalse);
    expect(server.fetches.map((f) => f.offset), [0, 50, 100]);

    await notifier.loadMore(logId: logId);
    expect(server.fetches, hasLength(3), reason: 'nothing left, nothing asked');
  });

  test('exactly one page has no more', () async {
    final (_, container) = await open(50);

    expect(container.read(maintenanceLogProvider(4).notifier).hasMore, isFalse);
  });

  test('an empty log has no more either', () async {
    final (_, container) = await open(0);

    expect(ids(container), isEmpty);
    expect(container.read(maintenanceLogProvider(4).notifier).hasMore, isFalse);
  });

  test('a second tap while a page is in the air asks nothing more', () async {
    final (server, container) = await open(120);
    final notifier = container.read(maintenanceLogProvider(4).notifier);
    server.hold = Completer();

    final first = notifier.loadMore(logId: logId);
    final second = notifier.loadMore(logId: logId);
    server.hold!.complete();
    await Future.wait([first, second]);

    expect(server.fetches.where((f) => f.offset == 50), hasLength(1));
    expect(ids(container), hasLength(100));
  });

  test('a reset made between two pages does not show a row twice', () async {
    final (server, container) = await open(60);
    final notifier = container.read(maintenanceLogProvider(4).notifier);
    // A new reset moves every row down by one: row 11 is now at offset 50.
    server.rows = [entry(61), ...server.rows];

    await notifier.loadMore(logId: logId);

    final shown = ids(container);
    expect(shown.toSet(), hasLength(shown.length));
    expect(shown.first, 60);
    expect(shown.last, 1);
    expect(container.read(maintenanceLogProvider(4)).requireValue.total, 61);
  });

  test('a failed page keeps the rows and says so', () async {
    final (server, container) = await open(120);
    final notifier = container.read(maintenanceLogProvider(4).notifier);
    server.failure = const ApiException(
      AppErrorCode.badResponse,
      statusCode: 500,
    );

    final outcome = await notifier.loadMore(logId: logId);

    expect(outcome.isOk, isFalse);
    expect(ids(container), hasLength(50));
    // A tap after the failure may try again.
    server.failure = null;
    expect((await notifier.loadMore(logId: logId)).isOk, isTrue);
    expect(ids(container), hasLength(100));
  });

  test(
    'a row that does not parse does not make the next page start early',
    () async {
      final (server, container) = await open(120, unparseable: {100});
      final notifier = container.read(maintenanceLogProvider(4).notifier);

      expect(ids(container), hasLength(49));
      await notifier.loadMore(logId: logId);
      await notifier.loadMore(logId: logId);

      expect(server.fetches.map((f) => f.offset), [0, 50, 100]);
      expect(notifier.hasMore, isFalse, reason: 'the end, one row short');
      expect(ids(container), hasLength(119));
    },
  );

  test(
    'rows that went meanwhile end the paging instead of repeating it',
    () async {
      final (server, container) = await open(120);
      final notifier = container.read(maintenanceLogProvider(4).notifier);
      // The server lost every row after the first page; the view still thinks
      // there are 120.
      server
        ..rows = server.rows.take(50).toList()
        // A count that still includes rows the server no longer sends.
        ..claimedTotal = 120;
      server.fetches.clear();

      await notifier.loadMore(logId: logId);

      expect(server.fetches, hasLength(1));
      expect(notifier.hasMore, isFalse);
      await notifier.loadMore(logId: logId);
      expect(server.fetches, hasLength(1), reason: 'nothing more is asked');
    },
  );

  test('a page that answers after a reload does not overwrite it', () async {
    final (server, container) = await open(120);
    final notifier = container.read(maintenanceLogProvider(4).notifier);
    server
      ..hold = Completer()
      ..holdOffset = 50;

    final more = notifier.loadMore(logId: logId);
    // A cleanup reloads the first page while the second is still in the air.
    server.rows = server.rows.take(20).toList();
    await notifier.cleanUp(1, logId: 'maintenance_log.cleanup');
    server.hold!.complete();
    await more;

    final view = container.read(maintenanceLogProvider(4)).requireValue;
    expect(view.entries, hasLength(20));
    expect(view.total, 20);
  });

  test(
    'a write that landed over a list that cannot be reloaded is not a success',
    () async {
      final (server, container) = await open(3);
      final notifier = container.read(maintenanceLogProvider(4).notifier);
      server.failure = const ApiException(
        AppErrorCode.badResponse,
        statusCode: 500,
      );

      final outcome = await notifier.deleteEntry(
        2,
        logId: 'maintenance_log.delete',
      );

      expect(server.deleted, [2]);
      expect(outcome.isOk, isFalse);
      final cleanUp = await notifier.cleanUp(
        30,
        logId: 'maintenance_log.cleanup',
      );
      expect(cleanUp.outcome.isOk, isFalse);
    },
  );

  test(
    'more is not asked for while the list is reloading or failed to',
    () async {
      final (server, container) = await open(120);
      final notifier = container.read(maintenanceLogProvider(4).notifier);
      server.failure = const ApiException(
        AppErrorCode.badResponse,
        statusCode: 500,
      );
      await notifier.refresh();
      expect(container.read(maintenanceLogProvider(4)).hasError, isTrue);
      server.fetches.clear();

      await notifier.loadMore(logId: logId);

      expect(server.fetches, isEmpty);
    },
  );

  test('without a server profile nothing is asked', () async {
    final (server, container) = await open(3, withProfile: false);

    expect(ids(container), isEmpty);
    expect(server.fetches, isEmpty);
  });

  test('a page asked for during a reload does not overwrite it', () async {
    final (server, container) = await open(120);
    final notifier = container.read(maintenanceLogProvider(4).notifier);
    final reload = Completer<void>();
    final page = Completer<void>();
    server.scripts.addAll([
      (hold: reload, fail: null),
      (hold: page, fail: null),
    ]);

    final deleted = notifier.deleteEntry(120, logId: 'maintenance_log.delete');
    await Future<void>.delayed(Duration.zero);
    // The reload is in the air and has not said so: a tap is not refused.
    final more = notifier.loadMore(logId: logId);
    await Future<void>.delayed(Duration.zero);
    reload.complete();
    await deleted;
    page.complete();
    await more;

    final view = container.read(maintenanceLogProvider(4)).requireValue;
    expect(view.entries, hasLength(50), reason: 'the reloaded first page');
    expect(view.total, 119);
  });

  test(
    'a refresh that a failing reload overtook does not stay loading',
    () async {
      final (server, container) = await open(3);
      final notifier = container.read(maintenanceLogProvider(4).notifier);
      final refreshed = Completer<void>();
      server.scripts.addAll([
        (hold: refreshed, fail: null),
        (
          hold: null,
          fail: const ApiException(AppErrorCode.badResponse, statusCode: 500),
        ),
      ]);

      final refresh = notifier.refresh();
      await Future<void>.delayed(Duration.zero);
      final outcome = await notifier.deleteEntry(
        2,
        logId: 'maintenance_log.delete',
      );
      refreshed.complete();
      await refresh;

      expect(outcome.isOk, isFalse);
      final state = container.read(maintenanceLogProvider(4));
      expect(state.isLoading, isFalse);
      expect(state.hasError, isTrue);
      expect(
        state.value?.entries,
        hasLength(3),
        reason: 'the old rows stay under it',
      );
    },
  );

  test('a superseded page does not refuse the next one', () async {
    final (server, container) = await open(120);
    final notifier = container.read(maintenanceLogProvider(4).notifier);
    final slow = Completer<void>();
    server.scripts.add((hold: slow, fail: null));

    final first = notifier.loadMore(logId: logId);
    await Future<void>.delayed(Duration.zero);
    await notifier.refresh();
    server.fetches.clear();
    await notifier.loadMore(logId: logId);

    expect(server.fetches.map((f) => f.offset), [50]);
    slow.complete();
    await first;
    expect(
      container.read(maintenanceLogProvider(4)).requireValue.entries,
      hasLength(100),
    );
  });

  test('deleting an entry reloads the first page', () async {
    final (server, container) = await open(3);
    final notifier = container.read(maintenanceLogProvider(4).notifier);

    final outcome = await notifier.deleteEntry(
      2,
      logId: 'maintenance_log.delete',
    );

    expect(outcome.isOk, isTrue);
    expect(server.deleted, [2]);
    expect(ids(container), [3, 1]);
  });

  test(
    'a cleanup of this printer names it, a fleet cleanup does not',
    () async {
      final (server, container) = await open(3);
      final notifier = container.read(maintenanceLogProvider(4).notifier);

      final mine = await notifier.cleanUp(90, logId: 'maintenance_log.cleanup');
      final all = await notifier.cleanUp(
        30,
        logId: 'maintenance_log.cleanup',
        allPrinters: true,
      );

      expect(mine.deleted, 2);
      expect(all.outcome.isOk, isTrue);
      expect(server.cleanups, [
        (days: 90, printer: 4),
        (days: 30, printer: null),
      ]);
    },
  );
}
