import 'dart:async';

import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/features/queue/queue_edit_screen.dart';
import 'package:bambuddy_mobile/features/queue/queue_history.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../contract/sent_writes.dart';
import '../../helpers.dart';

/// The queue's History tab, against the web's `HistorySection` and
/// `CompactHistoryRow` (`QueuePage.tsx`).

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
  List<ColorSubstitution> substitutions = const [],
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
  colorSubstitutions: substitutions,
);

/// A history on an older server, which sends all of it unsorted; [paged] is
/// one with `GET /queue/history`, which sorts and pages it (#2960).
class _History extends QueueRepository {
  _History(this.items, {this.kept = const {}, this.paged = false})
    : super(Dio());

  List<QueueItem> items;
  final Set<int> kept;
  final bool paged;
  final deleted = <int>[];

  int historyReads = 0;

  /// What a [paged] server was asked for: sort_by, reverse, limit.
  final pages = <(String, bool, int)>[];
  int clears = 0;

  /// When set, holds back the answer to each page read in its own completer.
  List<Completer<void>>? gates;

  /// When set, every older-server read waits for it.
  Future<void>? hold;

  @override
  Future<List<QueueItem>> fetchHistory() async {
    historyReads++;
    await hold;
    return items;
  }

  @override
  Future<QueueHistoryPage> fetchHistoryPage({
    required String sortBy,
    required bool reverse,
    required int limit,
  }) async {
    if (!paged) {
      final all = await fetchHistory();
      return (items: all, total: all.length, serverOrdered: false);
    }
    historyReads++;
    pages.add((sortBy, reverse, limit));
    if (gates case final gates?) {
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
    }
    final sorted = sortBy == 'name'
        ? ([...items]..sort((a, b) => a.archiveName!.compareTo(b.archiveName!)))
        : items;
    return (
      items: sorted.take(limit).toList(),
      total: items.length,
      serverOrdered: true,
    );
  }

  @override
  Future<QueueHistoryCleared> clearHistory(List<QueueItem> shown) async {
    if (!paged) return super.clearHistory(shown);
    clears++;
    final cleared = items.length;
    items = const [];
    return (cleared: cleared, kept: 0);
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
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: neverRetry,
      overrides: [
        queueRepositoryProvider.overrideWithValue(repo),
        queueProvider.overrideWith(_NoQueue.new),
        sharedPreferencesProvider.overrideWithValue(prefs ?? await _prefs()),
        currentUserOverride(user),
        noServerProfileOverride,
      ],
      child: plApp(
        const QueueScreen(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(pl.queueHistory));
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

  group('colour substitutions', () {
    const green = ColorSubstitution(
      slotId: 2,
      type: 'PLA',
      wanted: '#FF0000',
      got: '#00FF00',
      tray: 5,
    );
    const yellow = ColorSubstitution(
      slotId: 3,
      wanted: '#0000FF',
      got: '#FFFF00',
    );
    const white = ColorSubstitution(
      slotId: 4,
      wanted: '#000000',
      got: '#FFFFFF',
    );
    final chip = byLogId('queue.color_substitution');

    testWidgets('only the row that reports one carries the chip', (
      tester,
    ) async {
      await _openHistory(
        tester,
        _History([
          _item(1, substitutions: const [green]),
          _item(2),
        ]),
      );

      expect(chip, findsOneWidget);
      expect(find.text(pl.queueColorSubstitutionTitle), findsNothing);
    });

    testWidgets('the sheet names both colours of a slot with their hex', (
      tester,
    ) async {
      await _openHistory(
        tester,
        _History([
          _item(1, substitutions: const [green]),
        ]),
      );
      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(find.text(pl.queueColorSubstitutionTitle), findsOneWidget);
      expect(find.text(pl.queueColorSubstitutionSlot(2)), findsOneWidget);
      expect(find.text(pl.queueColorSubstitutionPrinted), findsOneWidget);
      expect(find.text(pl.queueColorSubstitutionWanted), findsOneWidget);
      expect(find.text(pl.colorFamilyGreen), findsOneWidget);
      expect(find.text('#00FF00'), findsOneWidget);
      expect(find.text(pl.colorFamilyRed), findsOneWidget);
      expect(find.text('#FF0000'), findsOneWidget);
    });

    testWidgets('several slots are one chip with a count, a block each', (
      tester,
    ) async {
      await _openHistory(
        tester,
        _History([
          _item(1, substitutions: const [green, yellow, white]),
        ]),
      );

      expect(find.text(pl.queueColorSubstitutionSlots(3)), findsOneWidget);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      for (final slot in [2, 3, 4]) {
        expect(find.text(pl.queueColorSubstitutionSlot(slot)), findsOneWidget);
      }
    });

    testWidgets('a screen reader can open the sheet by its tap action', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _openHistory(
        tester,
        _History([
          _item(1, substitutions: const [green]),
        ]),
      );

      expect(
        tester.getSemantics(chip),
        matchesSemantics(
          isButton: true,
          hasTapAction: true,
          hasEnabledState: false,
          label: pl.queueColorSubstitution(
            2,
            pl.colorFamilyGreen,
            pl.colorFamilyRed,
          ),
        ),
      );
      tester.semantics.tap(find.semantics.byLabel(RegExp('Slot 2')));
      await tester.pumpAndSettle();
      expect(find.text(pl.queueColorSubstitutionTitle), findsOneWidget);
      handle.dispose();
    });

    for (final (scale, stacked) in [(1.0, false), (2.0, true)]) {
      testWidgets(
        'the two sides of a slot are ${stacked ? 'stacked' : 'side '
                  'by side'} at text $scale',
        (tester) async {
          tester.view.physicalSize = const Size(411, 1600);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await _openHistory(
            tester,
            _History([
              _item(1, substitutions: const [green]),
            ]),
            textScale: scale,
          );
          await tester.tap(chip);
          await tester.pumpAndSettle();

          final printed = tester.getTopLeft(
            find.text(pl.queueColorSubstitutionPrinted),
          );
          final wanted = tester.getTopLeft(
            find.text(pl.queueColorSubstitutionWanted),
          );
          expect(wanted.dy > printed.dy, stacked);
        },
      );
    }

    testWidgets('a third slot does not make the row taller', (tester) async {
      Future<double> rowHeight(List<ColorSubstitution> subs) async {
        await _openHistory(tester, _History([_item(1, substitutions: subs)]));
        return tester.getSize(byLogId('queue_history.row')).height;
      }

      expect(
        await rowHeight(const [green, yellow, white]),
        await rowHeight(const [green]),
        reason: 'the slots are in the sheet, not on the row',
      );
    });

    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('the chip stays inside the row and 48 dp tall at text '
          '$scale', (tester) async {
        tester.view.physicalSize = const Size(411, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _openHistory(
          tester,
          _History([
            _item(1, substitutions: const [green, yellow, white]),
          ]),
          textScale: scale,
        );

        expect(tester.takeException(), isNull);
        final rect = tester.getRect(chip);
        expect(rect.right, lessThanOrEqualTo(411));
        expect(rect.height, greaterThanOrEqualTo(48));
        expect(rect.width, greaterThanOrEqualTo(48));

        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(pl.queueColorSubstitutionSlot(4)), findsOneWidget);
      });
    }
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
    expect(find.text(pl.queueHistoryRemoved), findsOneWidget);
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
        '${pl.queueHistoryCleared(2)} ${pl.queueHistoryKeptForOrders(1)}',
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

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('a batch header keeps its name and counts in the card at text '
        '$scale', (tester) async {
      tester.view.physicalSize = const Size(411, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final at = DateTime.now().subtract(const Duration(days: 30));
      await _openHistory(
        tester,
        _History([
          _item(1, batchId: 9, batchName: 'A long order name', completedAt: at),
          _item(2, batchId: 9, status: 'failed', completedAt: at),
          _item(3, batchId: 9, status: 'cancelled', completedAt: at),
        ]),
        textScale: scale,
      );

      expect(tester.takeException(), isNull);
      final card = tester.getRect(byLogId('queue_history.batch'));
      expect(card.right, lessThanOrEqualTo(411));
      expect(
        tester.getSize(find.text('A long order name')).width,
        greaterThan(60),
        reason: 'the name keeps room to be read',
      );
    });
  }

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('a history row keeps its buttons in the row at text $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(411, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _openHistory(
        tester,
        _History([
          _item(
            1,
            name: 'A long model name for a history row.3mf',
            // Older than a week, so the time reads as a full date.
            completedAt: DateTime.now().subtract(const Duration(days: 30)),
          ),
        ]),
        textScale: scale,
      );

      expect(tester.takeException(), isNull);
      final remove = tester.getRect(byLogId('queue_history.remove'));
      expect(remove.right, lessThanOrEqualTo(411));
      expect(
        tester
            .getSize(find.text('A long model name for a history row.3mf'))
            .width,
        greaterThan(60),
        reason: 'the name keeps room to be read, not a letter and an ellipsis',
      );
    });
  }

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
    expect(find.text(pl.queueHistoryShowing(50, 51)), findsOneWidget);
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

  group('a server that pages the history', () {
    testWidgets('sends the order and one page, and a longer one on request', (
      tester,
    ) async {
      final repo = _History([
        for (var i = 1; i <= 120; i++) _item(i),
      ], paged: true);
      await _openHistory(tester, repo);

      // Read twice on the way in: by the tab's build and by its switch.
      expect(repo.pages.toSet(), {('date', false, 50)});
      expect(find.textContaining(pl.queueItemCount(120)), findsOneWidget);
      await tester.scrollUntilVisible(
        byLogId('queue_history.show_more'),
        400,
        scrollable: find
            .descendant(
              of: find.byType(QueueHistoryView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text(pl.queueHistoryShowing(50, 120)), findsOneWidget);
      await tester.tap(byLogId('queue_history.show_more'));
      await tester.pumpAndSettle();

      expect(repo.pages.last, ('date', false, 100));
    });

    testWidgets('a new order is asked of the server, from one page', (
      tester,
    ) async {
      final repo = _History([
        for (var i = 1; i <= 60; i++) _item(i),
      ], paged: true);
      await _openHistory(tester, repo);

      await tester.tap(byLogId('queue_history.sort'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.ancestor(
          of: byLogId('queue_history.sort.printer'),
          matching: find.byType(CheckedPopupMenuItem<String>),
        ),
      );
      await tester.pumpAndSettle();

      expect(repo.pages.last, ('printer', false, 50));
    });

    testWidgets('what clearing sends, recorded for the contract test', (
      tester,
    ) async {
      final dio = testDio();
      mockServer(dio)
        ..onGet(
          '/api/v1/queue/history',
          (server) => server.reply(200, {
            'items': [
              {'id': 1, 'position': 1, 'status': 'completed'},
            ],
            'total': 1,
            'locations': <String>[],
          }),
          queryParameters: {'sort_by': 'date', 'reverse': false, 'limit': 50},
        )
        ..onPost(
          '/api/v1/queue/history/clear',
          (server) => server.reply(200, {'cleared': 1, 'kept': 0}),
        );
      final log = captureRequests(dio);
      await tester.pumpWidget(
        ProviderScope(
          retry: neverRetry,
          overrides: [
            queueRepositoryProvider.overrideWithValue(QueueRepository(dio)),
            queueProvider.overrideWith(_NoQueue.new),
            sharedPreferencesProvider.overrideWithValue(await _prefs()),
            currentUserOverride(null),
            noServerProfileOverride,
          ],
          child: plApp(const Scaffold(body: QueueHistoryView())),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(byLogId('queue_history.clear'));
      await tester.pumpAndSettle();
      await tester.tap(byLogId('queue_history.clear_confirm.confirm'));
      await tester.pumpAndSettle();

      expectSentAsRecorded('queue_history_clear', writesOf(log.requests));
      expect(find.text(pl.queueHistoryCleared(1)), findsOneWidget);
    });

    testWidgets('an order picked while the first page loads wins', (
      tester,
    ) async {
      final repo = _History([
        _item(1, name: 'b'),
        _item(2, name: 'a'),
      ], paged: true)..gates = [];
      await tester.pumpWidget(
        ProviderScope(
          retry: neverRetry,
          overrides: [
            queueRepositoryProvider.overrideWithValue(repo),
            queueProvider.overrideWith(_NoQueue.new),
            sharedPreferencesProvider.overrideWithValue(await _prefs()),
            currentUserOverride(null),
            noServerProfileOverride,
          ],
          child: plApp(const Scaffold(body: QueueHistoryView())),
        ),
      );
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(QueueHistoryView)),
      );
      container.read(queueHistoryOrderProvider.notifier).set((
        by: QueueHistorySort.name,
        ascending: false,
      ));
      await tester.pump();

      // The name order answers first, the date order it replaced after it.
      expect(repo.pages.map((p) => p.$1), ['date', 'name']);
      repo.gates![1].complete();
      await tester.pump();
      repo.gates![0].complete();
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('a')).dy,
        lessThan(tester.getTopLeft(find.text('b')).dy),
      );
    });

    testWidgets('a slower poll does not undo a longer page', (tester) async {
      final repo = _History([
        for (var i = 1; i <= 120; i++) _item(i),
      ], paged: true);
      await tester.pumpWidget(
        ProviderScope(
          retry: neverRetry,
          overrides: [
            queueRepositoryProvider.overrideWithValue(repo),
            queueProvider.overrideWith(_NoQueue.new),
            sharedPreferencesProvider.overrideWithValue(await _prefs()),
            currentUserOverride(null),
            noServerProfileOverride,
          ],
          child: plApp(const Scaffold(body: QueueHistoryView())),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(QueueHistoryView)),
      );
      final notifier = container.read(queueHistoryProvider.notifier);
      repo.gates = [];

      final poll = notifier.refresh();
      final more = notifier.showMore();
      await tester.pump();
      repo.gates![1].complete();
      await more;
      repo.gates![0].complete();
      await poll;

      final shown = container.read(queueHistoryProvider).value!;
      expect((shown.limit, shown.items.length), (100, 100));
    });

    testWidgets('clearing is one request, not one per row', (tester) async {
      final repo = _History([_item(1), _item(2)], paged: true);
      await _openHistory(tester, repo);

      await tester.tap(byLogId('queue_history.clear'));
      await tester.pumpAndSettle();
      await tester.tap(byLogId('queue_history.clear_confirm.confirm'));
      await tester.pumpAndSettle();

      expect(repo.clears, 1);
      expect(repo.deleted, isEmpty);
      expect(find.text(pl.queueHistoryCleared(2)), findsOneWidget);
    });
  });

  testWidgets('on an older server, a poll still out does not undo more rows', (
    tester,
  ) async {
    final repo = _History([for (var i = 1; i <= 120; i++) _item(i)]);
    await _openHistory(tester, repo);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(QueueHistoryView)),
    );
    final notifier = container.read(queueHistoryProvider.notifier);
    final gate = Completer<void>();
    repo.hold = gate.future;

    final poll = notifier.refresh();
    await notifier.showMore();
    gate.complete();
    await poll;

    expect(container.read(queueHistoryProvider).value?.limit, 100);
  });

  testWidgets('an older server is not asked again for a new order', (
    tester,
  ) async {
    final repo = _History([_item(1, name: 'b'), _item(2, name: 'a')]);
    await _openHistory(tester, repo);
    final reads = repo.historyReads;

    await tester.tap(byLogId('queue_history.sort'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: byLogId('queue_history.sort.name'),
        matching: find.byType(CheckedPopupMenuItem<String>),
      ),
    );
    await tester.pumpAndSettle();

    expect(repo.historyReads, reads);
    expect(
      tester.getTopLeft(find.text('a')).dy,
      lessThan(tester.getTopLeft(find.text('b')).dy),
      reason: 'sorted here instead',
    );
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
    // The tag sits on the label, which the checked item puts under an
    // IgnorePointer; the item itself takes the tap.
    await tester.tap(
      find.ancestor(
        of: byLogId('queue_history.sort.name'),
        matching: find.byType(CheckedPopupMenuItem<String>),
      ),
    );
    await tester.pumpAndSettle();

    expect(prefs.getString('queue.history_sort_by'), 'name');
  });

  testWidgets('an empty history says what will appear there', (tester) async {
    await _openHistory(tester, _History(const []));

    expect(find.text(pl.queueHistoryEmpty), findsOneWidget);
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

    expect(find.text(pl.queueHistoryKeptForOrder), findsOneWidget);
    expect(find.text('part-1.3mf'), findsOneWidget);
  });

  testWidgets('switching back to the queue reads it at once', (tester) async {
    await _openHistory(tester, _History([_item(1)]));
    final before = _NoQueue.refreshes;

    await tester.tap(find.text(pl.navQueue).last);
    await tester.pumpAndSettle();

    expect(_NoQueue.refreshes, before + 1);
  });
}
