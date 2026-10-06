import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/features/queue/queue_edit_screen.dart';
import 'package:bambuddy_mobile/features/queue/queue_history.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// The queue's History tab, against the web's `HistorySection` and
/// `CompactHistoryRow` (`QueuePage.tsx`).

final _l10n = lookupAppLocalizations(const Locale('pl'));

QueueItem _item(
  int id, {
  String status = 'completed',
  String? name,
  String? printer,
  DateTime? completedAt,
  DateTime? createdAt,
  int? batchId,
  String? batchName,
  String? error,
  int? createdById,
}) => QueueItem(
  id: id,
  position: 1,
  status: status,
  archiveId: 100 + id,
  archiveName: name ?? 'part-$id.3mf',
  printerName: printer,
  completedAt: completedAt,
  createdAt: createdAt,
  batchId: batchId,
  batchName: batchName,
  errorMessage: error,
  createdById: createdById,
);

class _History extends QueueRepository {
  _History(this.items, {this.kept = const {}}) : super(Dio());

  List<QueueItem> items;
  final Set<int> kept;
  final deleted = <int>[];

  int historyReads = 0;

  @override
  Future<List<QueueItem>> fetchHistory() async {
    historyReads++;
    return items;
  }

  @override
  Future<List<QueueItem>> fetchActive() async => const [];

  @override
  Future<bool> delete(int itemId) async {
    deleted.add(itemId);
    if (kept.contains(itemId)) return false;
    items = [...items]..removeWhere((i) => i.id == itemId);
    return true;
  }
}

class _NoQueue extends QueueNotifier {
  static int refreshes = 0;

  @override
  Future<List<QueueItem>> build() async => const [];

  @override
  Future<void> refresh() async => refreshes++;
}

Future<SharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Future<void> _openHistory(
  WidgetTester tester,
  _History repo, {
  CurrentUser? user,
  SharedPreferences? prefs,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        queueRepositoryProvider.overrideWithValue(repo),
        queueProvider.overrideWith(_NoQueue.new),
        sharedPreferencesProvider.overrideWithValue(prefs ?? await _prefs()),
        currentUserOverride(user),
        noServerProfileOverride,
      ],
      child: plApp(const QueueScreen()),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(_l10n.queueHistory));
  await tester.pumpAndSettle();
}

CurrentUser _user(int id, Set<String> permissions) => CurrentUser(
  id: id,
  username: 'u$id',
  isAdmin: false,
  permissions: permissions,
);

void main() {
  group('order', () {
    final at = DateTime(2026, 10, 1);
    final items = [
      _item(1, name: 'b', printer: 'Z', completedAt: at),
      _item(
        2,
        name: 'A',
        printer: 'y',
        createdAt: at.add(const Duration(days: 2)),
      ),
      _item(
        3,
        name: 'c',
        printer: 'x',
        completedAt: at.add(const Duration(days: 1)),
      ),
      _item(4, name: 'a', printer: 'y'),
    ];
    List<int> ids(QueueHistorySort by, {bool ascending = false}) => [
      for (final i in sortQueueHistory(items, (by: by, ascending: ascending)))
        i.id,
    ];

    test('newest first by when each finished, else when it was queued', () {
      // No time at all sorts as the oldest, as the web's `?? 0` does.
      expect(ids(QueueHistorySort.date), [2, 3, 1, 4]);
      expect(ids(QueueHistorySort.date, ascending: true), [4, 1, 3, 2]);
    });

    test('by name or printer, ignoring case, ties in server order', () {
      expect(ids(QueueHistorySort.name), [2, 4, 1, 3]);
      expect(ids(QueueHistorySort.printer), [3, 2, 4, 1]);
    });
  });

  test('a batch is one row at its first item, carrying every sibling', () {
    final sorted = [
      _item(1),
      _item(2, batchId: 9, batchName: 'Order'),
      _item(3),
      _item(4, batchId: 9),
    ];

    final rows = queueHistoryRows(sorted, 2);

    expect([for (final r in rows) r.item?.id ?? -r.batchId!], [1, -9]);
    expect([for (final i in rows.last.batch) i.id], [2, 4]);
    expect(rows.last.batchName, 'Order');
  });

  test('removing needs the all permission, or the own one on your own', () {
    bool can(CurrentUser? me, int? owner) => canModifyOwned(
      me,
      all: Permissions.queueDeleteAll,
      own: Permissions.queueDeleteOwn,
      createdById: owner,
    );
    final own = _user(7, {Permissions.queueDeleteOwn});

    expect(can(null, 1), isTrue, reason: 'unknown identity: the server says');
    expect(can(_user(7, {Permissions.queueDeleteAll}), 1), isTrue);
    expect(can(own, 7), isTrue);
    expect(can(own, 8), isFalse);
    expect(can(own, null), isFalse, reason: 'ownerless needs _all');
    expect(can(_user(7, const {}), 7), isFalse);
  });

  testWidgets('a failed item says why; a completed one carries no error', (
    tester,
  ) async {
    const reason =
        'Nozzle rack pick no longer fits the printer: rack position 2 is '
        'picked for more than one filament group.';
    await _openHistory(
      tester,
      _History([
        _item(1, status: 'failed', error: reason),
        _item(2, error: 'stale'),
      ]),
    );

    expect(find.text(reason), findsOneWidget);
    expect(find.text('stale'), findsNothing);
  });

  testWidgets('removing asks first, then deletes and drops the row', (
    tester,
  ) async {
    final repo = _History([_item(1), _item(2)]);
    await _openHistory(tester, repo);

    await tester.tap(byLogId('queue_history.remove').first);
    await tester.pumpAndSettle();
    await tester.tap(byLogId('queue_history.remove_confirm.confirm'));
    await tester.pumpAndSettle();

    expect(repo.deleted, [1]);
    expect(find.text(_l10n.queueHistoryRemoved), findsOneWidget);
    expect(find.text('part-1.3mf'), findsNothing);
    expect(find.text('part-2.3mf'), findsOneWidget);
  });

  testWidgets('clearing counts the rows a batch order kept', (tester) async {
    final repo = _History([_item(1), _item(2), _item(3)], kept: {3});
    await _openHistory(tester, repo);

    await tester.tap(byLogId('queue_history.clear'));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('queue_history.clear_confirm.confirm'));
    await tester.pumpAndSettle();

    expect(repo.deleted, [1, 2, 3]);
    expect(
      find.text(
        '${_l10n.queueHistoryCleared(2)} ${_l10n.queueHistoryKeptForOrders(1)}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('without the permissions the buttons are there and refuse', (
    tester,
  ) async {
    await _openHistory(
      tester,
      _History([_item(1, createdById: 7), _item(2, createdById: 8)]),
      user: _user(7, {Permissions.queueDeleteOwn}),
    );

    bool enabled(String id, [int index = 0]) => tester
        .widget<ButtonStyleButton>(
          find.descendant(
            of: byLogId(id).at(index),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        )
        .enabled;
    bool iconEnabled(String id, int index) =>
        tester
            .widget<IconButton>(
              find.descendant(
                of: byLogId(id).at(index),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed !=
        null;

    expect(enabled('queue_history.clear'), isFalse);
    // Newest first with no times: server order, so 1 then 2.
    expect(iconEnabled('queue_history.remove', 0), isTrue);
    expect(iconEnabled('queue_history.remove', 1), isFalse);
    expect(iconEnabled('queue_history.requeue', 0), isFalse);
  });

  testWidgets('re-queue opens the print form on the same file', (tester) async {
    await _openHistory(tester, _History([_item(1)]));

    await tester.tap(byLogId('queue_history.requeue'));
    await tester.pumpAndSettle();

    final form = tester.widget<QueueEditScreen>(find.byType(QueueEditScreen));
    expect(form.mode, QueueEditMode.create);
    expect(form.item.archiveId, 101);
    expect(form.item.id, 0, reason: 'a new job, not the old one edited');
  });

  testWidgets('fifty rows at first, and fifty more on request', (tester) async {
    await _openHistory(
      tester,
      _History([for (var i = 1; i <= 51; i++) _item(i)]),
    );
    final list = find
        .descendant(
          of: find.byType(QueueHistoryView),
          matching: find.byType(Scrollable),
        )
        .first;

    await tester.scrollUntilVisible(
      byLogId('queue_history.show_more'),
      400,
      scrollable: list,
    );
    expect(find.text(_l10n.queueHistoryShowing(50, 51)), findsOneWidget);
    await tester.tap(byLogId('queue_history.show_more'));
    await tester.pumpAndSettle();

    expect(byLogId('queue_history.show_more'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('part-51.3mf'),
      400,
      scrollable: list,
    );
    expect(find.text('part-51.3mf'), findsOneWidget);
  });

  testWidgets('a batch folds into one row until opened', (tester) async {
    await _openHistory(
      tester,
      _History([
        _item(1, batchId: 9, batchName: 'Order'),
        _item(2, status: 'failed', batchId: 9),
      ]),
    );

    expect(find.text('Order'), findsOneWidget);
    expect(find.text('part-1.3mf'), findsNothing);

    await tester.tap(byLogId('queue_history.batch'));
    await tester.pumpAndSettle();

    expect(find.text('part-1.3mf'), findsOneWidget);
    expect(find.text('part-2.3mf'), findsOneWidget);
  });

  testWidgets('the chosen order is kept for next time', (tester) async {
    final prefs = await _prefs();
    await _openHistory(tester, _History([_item(1)]), prefs: prefs);

    await tester.tap(byLogId('queue_history.sort'));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('queue_history.sort.name'));
    await tester.pumpAndSettle();

    expect(prefs.getString('queue.history_sort_by'), 'name');
  });

  testWidgets('an empty history says what will appear there', (tester) async {
    await _openHistory(tester, _History(const []));

    expect(find.text(_l10n.queueHistoryEmpty), findsOneWidget);
  });

  testWidgets('only the tab on screen is polled', (tester) async {
    final repo = _History([_item(1)]);
    await _openHistory(tester, repo);
    final (reads, refreshes) = (repo.historyReads, _NoQueue.refreshes);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(repo.historyReads, reads + 1);
    expect(_NoQueue.refreshes, refreshes);
  });

  testWidgets('a row a batch order keeps says it was cancelled instead', (
    tester,
  ) async {
    final repo = _History([_item(1)], kept: {1});
    await _openHistory(tester, repo);

    await tester.tap(byLogId('queue_history.remove'));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('queue_history.remove_confirm.confirm'));
    await tester.pumpAndSettle();

    expect(find.text(_l10n.queueHistoryKeptForOrder), findsOneWidget);
    expect(find.text('part-1.3mf'), findsOneWidget);
  });

  testWidgets('switching back to the queue reads it at once', (tester) async {
    await _openHistory(tester, _History([_item(1)]));
    final before = _NoQueue.refreshes;

    await tester.tap(find.text(_l10n.navQueue).last);
    await tester.pumpAndSettle();

    expect(_NoQueue.refreshes, before + 1);
  });
}
