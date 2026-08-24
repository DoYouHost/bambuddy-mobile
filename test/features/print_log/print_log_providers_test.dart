import 'dart:async';

import 'package:bambuddy_mobile/core/models/print_log_entry.dart';
import 'package:bambuddy_mobile/data/print_log_repository.dart';
import 'package:bambuddy_mobile/features/print_log/print_log_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// What the notifier has to get right about requests that outlive the state
/// they started from — a page still in flight when the filters changed, a
/// delete fired while the list is in its error state.
class _FakeRepository extends PrintLogRepository {
  _FakeRepository() : super(Dio());

  /// Pages the caller must complete by hand, so a request can be held open
  /// across a filter change.
  final pending = <Completer<PrintLogPage>>[];

  /// Query recorded per call, newest last.
  final calls = <String?>[];

  var deleted = <int>[];

  @override
  Future<bool> supportsCostEnergy() async => true;

  @override
  Future<PrintLogPage> list({
    String? search,
    int? printerId,
    String? status,
    String? createdByUsername,
    DateTime? dateFrom,
    DateTime? dateTo,
    int limit = 50,
    int offset = 0,
    PrintLogSort? sort,
    bool descending = true,
  }) {
    calls.add(status);
    final completer = Completer<PrintLogPage>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<void> deleteEntry(int entryId) async => deleted.add(entryId);
}

PrintLogEntry _entry(int id) => PrintLogEntry(
      id: id,
      status: 'completed',
      createdAt: DateTime(2026, 8, 1),
      printName: 'Run $id',
    );

PrintLogPage _page(List<int> ids, {int? total}) => PrintLogPage(
      items: [for (final id in ids) _entry(id)],
      total: total ?? ids.length,
    );

void main() {
  late _FakeRepository repo;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repo = _FakeRepository();
    container = ProviderContainer(overrides: [
      printLogRepositoryProvider.overrideWithValue(repo),
      sharedPreferencesProvider.overrideWithValue(prefs),
      noServerProfileOverride,
    ]);
    // Keep the notifier alive for the whole test: it is autoDispose, and a
    // listener is what a screen would be.
    container.listen(printLogProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  test('a page in flight when the filters change is dropped', () async {
    // The rebuild disposes nothing — same notifier instance, new build — so a
    // flag cleared in `build` lets this answer through and the list shows the
    // previous filter's rows under the new filter.
    repo.pending.first.complete(_page([1, 2], total: 4));
    await container.read(printLogProvider.future);

    unawaited(container.read(printLogProvider.notifier).loadMore());
    await Future<void>.delayed(Duration.zero);

    container
        .read(printLogFiltersProvider.notifier)
        .set(const PrintLogFilters(status: 'failed'));
    await Future<void>.delayed(Duration.zero);

    // Two requests are now open: the stale second page, and the first page of
    // the new filter. Answer the stale one last, which is the losing order.
    final filtered = repo.pending.last;
    final stale = repo.pending[1];
    filtered.complete(_page([9], total: 1));
    await Future<void>.delayed(Duration.zero);
    stale.complete(_page([3, 4], total: 4));
    await Future<void>.delayed(Duration.zero);

    final state = container.read(printLogProvider).valueOrNull!;
    expect(state.items.map((e) => e.id), [9]);
    expect(state.total, 1);
    expect(repo.calls.last, 'failed');
  });

  test('a delete is sent even when the list is holding an error', () async {
    // Reachable by a refresh failing behind the open sheet. Reading the list
    // first and giving up on an empty one told the user the run was deleted
    // while nothing left the phone.
    repo.pending.first.completeError(
      DioException(requestOptions: RequestOptions(path: '/print-log/')),
    );
    await expectLater(
      container.read(printLogProvider.future),
      throwsA(anything),
    );
    expect(container.read(printLogProvider).valueOrNull, isNull);

    final error = await container.read(printLogProvider.notifier).deleteEntry(7);

    expect(error, isNull);
    expect(repo.deleted, [7], reason: 'the request has to go regardless');
  });
}
