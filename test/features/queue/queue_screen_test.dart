import 'dart:async';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/printer_commands_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/features/orders/orders_providers.dart';
import 'package:bambuddy_mobile/features/queue/color_substitution_chip.dart';
import 'package:bambuddy_mobile/features/queue/queue_filament_chips.dart';
import 'package:bambuddy_mobile/features/queue/queue_mapping_sheet.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_screen.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/rendering.dart' show RenderPointerListener;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import 'queue_fakes.dart';

/// Fake notifier — returns the given list without touching the repository/network.
class _FakeQueueNotifier extends QueueNotifier {
  _FakeQueueNotifier(this._items);

  final List<QueueItem> _items;

  @override
  Future<List<QueueItem>> build() async => _items;
}

Widget _screen(List<QueueItem> items) => ProviderScope(
  retry: neverRetry,
  overrides: [
    queueProvider.overrideWith(() => _FakeQueueNotifier(items)),
    noServerProfileOverride,
  ],
  child: plApp(const QueueScreen()),
);

void main() {
  testWidgets(
    'renders the queue card: name, status and printer from the fixture',
    (tester) async {
      final item = QueueItem.fromJson(
        readFixture('queue_item.json') as Map<String, dynamic>,
      );

      await tester.pumpWidget(_screen([item]));
      await tester.pumpAndSettle();

      expect(
        find.text('Multi-material drawer fronts - Plate 4'),
        findsOneWidget,
      );
      expect(
        find.text(pl.queueStatusPrinting),
        findsOneWidget,
        reason: 'status printing → pl',
      );
      expect(find.textContaining('X2D-3DP'), findsOneWidget);
    },
  );

  testWidgets('a run in a batch names it, and the bar opens the orders', (
    tester,
  ) async {
    final json = readFixture('queue_item.json') as Map<String, dynamic>;
    final item = QueueItem.fromJson({
      ...json,
      'batch_id': 4,
      'batch_name': 'Keychains ×6',
    });

    await tester.pumpWidget(
      ProviderScope(
        retry: neverRetry,
        overrides: [
          queueProvider.overrideWith(() => _FakeQueueNotifier([item])),
          noServerProfileOverride,
          batchListingProvider.overrideWithValue(const AsyncData(true)),
        ],
        child: plApp(const QueueScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(pl.queueInBatch('Keychains ×6')),
      findsOneWidget,
    );
    expect(byLogId('queue.orders'), findsOneWidget);
  });

  testWidgets('no orders entry once the server has no batch list', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: neverRetry,
        overrides: [
          queueProvider.overrideWith(() => _FakeQueueNotifier(const [])),
          noServerProfileOverride,
          batchListingProvider.overrideWithValue(const AsyncData(false)),
        ],
        child: plApp(const QueueScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(byLogId('queue.orders'), findsNothing);
  });

  testWidgets(
    'a queued card carries a chip for a slot printed in another colour',
    (tester) async {
      final item = QueueItem.fromJson({
        ...(readFixture('queue_item.json') as Map<String, dynamic>),
        'color_substitutions': [
          {
            'slot_id': 1,
            'type': 'PLA',
            'wanted': '#FF0000',
            'got': '#0000FF',
            'tray': 0,
          },
        ],
      });

      await tester.pumpWidget(_screen([item]));
      await tester.pumpAndSettle();

      final chip = byLogId('queue.color_substitution');
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.text(pl.colorFamilyBlue), findsOneWidget);
      expect(find.text(pl.colorFamilyRed), findsOneWidget);
    },
  );

  QueueItem substituted({int slots = 1, String status = 'printing'}) =>
      QueueItem.fromJson({
        ...(readFixture('queue_item.json') as Map<String, dynamic>),
        'status': status,
        'color_substitutions': [
          for (var i = 1; i <= slots; i++)
            {
              'slot_id': i,
              'type': 'PLA',
              'wanted': '#FF0000',
              'got': '#0000FF',
              'tray': 0,
            },
        ],
      });

  /// The queue at [scale]x text on a 360 dp phone, the width the layout is
  /// tuned for; the default test surface is wide enough to hide a cramped card.
  Future<void> pumpPhone(
    WidgetTester tester,
    QueueItem item, {
    required double scale,
  }) async {
    useLogicalWindow(tester, const Size(360, 800));
    await tester.pumpWidget(
      ProviderScope(
        retry: neverRetry,
        overrides: [
          queueProvider.overrideWith(() => _FakeQueueNotifier([item])),
          noServerProfileOverride,
        ],
        child: plApp(const QueueScreen(), builder: textScaled(scale)),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('the substitution pill is level with the filament chip at '
        '${scale}x text', (tester) async {
      await pumpPhone(tester, substituted(), scale: scale);

      // One slot: the pill has no text, so the only text in the chip row is
      // the filament's label.
      final filament = tester.getCenter(
        find.descendant(
          of: find.byType(QueueFilamentChips),
          matching: find.byType(Text),
        ),
      );
      final pill = tester.getCenter(
        find.descendant(
          of: byLogId('queue.color_substitution'),
          matching: find.byIcon(Icons.error_outline),
        ),
      );
      // A wrapped chip would be a different row and fail the `dy` check.
      expect(pill.dx, lessThan(filament.dx));
      expect(pill.dy, closeTo(filament.dy, 1));
    });

    testWidgets('a waiting job with three swapped colours fits at ${scale}x '
        'text and the name keeps its width', (tester) async {
      final item = substituted(slots: 3, status: 'pending');
      await pumpPhone(tester, item, scale: scale);

      // An overflow is an exception in a widget test; it must not be there.
      expect(tester.takeException(), isNull);
      // The name shares no column with the chips, so the text size does not
      // narrow it: the picture, the gaps and a 48 dp menu are all it gives up.
      expect(
        tester.getSize(find.text(item.displayName)).width,
        greaterThanOrEqualTo(170),
      );
      // Handle and menu keep their 24 dp: the theme scales icons with the
      // text, and a 48 dp menu glyph is what narrowed the name to 102 dp.
      for (final icon in [Icons.drag_indicator, Icons.more_vert]) {
        final glyph = tester.widget<RichText>(
          find.descendant(
            of: find.byIcon(icon),
            matching: find.byType(RichText),
          ),
        );
        expect(glyph.text.style?.fontSize, 24, reason: '$icon');
      }
    });
  }

  testWidgets('the whole 48 dp box of the drag handle takes the finger, not '
      'only the glyph in it', (tester) async {
    await pumpPhone(tester, substituted(slots: 0, status: 'pending'), scale: 1);

    final box = tester.getRect(
      find
          .ancestor(
            of: find.byIcon(Icons.drag_indicator),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(box.size, const Size.square(48));
    Set<RenderPointerListener> listenersAt(Offset at) => tester
        .hitTestOnBinding(at)
        .path
        .map((entry) => entry.target)
        .whereType<RenderPointerListener>()
        .toSet();
    final centre = listenersAt(box.center);
    expect(centre, isNotEmpty);
    // A drag that starts in the 12 dp ring around the glyph must reach the same
    // listeners, or it scrolls the list or swipes the card instead.
    expect(listenersAt(box.topLeft + const Offset(3, 3)), containsAll(centre));
  });

  testWidgets('a card of a server without the field has no such chip', (
    tester,
  ) async {
    final item = QueueItem.fromJson(
      readFixture('queue_item.json') as Map<String, dynamic>,
    );

    await tester.pumpWidget(_screen([item]));
    await tester.pumpAndSettle();

    expect(byLogId('queue.color_substitution'), findsNothing);
    // Not in the tree at all, not merely drawn empty: a zero-size child that
    // lands on a new run still adds a run spacing.
    expect(find.byType(ColorSubstitutionChip), findsNothing);
  });

  testWidgets('an empty queue shows a message', (tester) async {
    await tester.pumpWidget(_screen(const []));
    await tester.pumpAndSettle();

    expect(find.text(pl.queueEmpty), findsOneWidget);
  });

  testWidgets('no FAB when the queue only has printing items', (tester) async {
    final json = readFixture('queue_item.json') as Map<String, dynamic>;
    final printing = QueueItem.fromJson({...json, 'status': 'printing'});

    await tester.pumpWidget(_screen([printing]));
    await tester.pumpAndSettle();

    expect(find.text(pl.queueStartNext), findsNothing);
  });

  testWidgets('the "Start next" FAB is visible when there are pending prints', (
    tester,
  ) async {
    final json = readFixture('queue_item.json') as Map<String, dynamic>;
    final pending = QueueItem.fromJson({...json, 'status': 'pending'});

    await tester.pumpWidget(_screen([pending]));
    await tester.pumpAndSettle();

    expect(find.text(pl.queueStartNext), findsOneWidget);
  });

  group('a user held for review (#1620)', () {
    final json = readFixture('queue_item.json') as Map<String, dynamic>;
    final waiting = QueueItem.fromJson({
      ...json,
      'status': 'pending',
      'manual_start': true,
    });

    Widget screen({required bool held}) => ProviderScope(
      retry: neverRetry,
      overrides: [
        queueProvider.overrideWith(() => _FakeQueueNotifier([waiting])),
        noServerProfileOverride,
        awaitingReviewProvider.overrideWithValue(held),
      ],
      child: plApp(const QueueScreen()),
    );

    testWidgets('is told who starts the job and offered no start', (
      tester,
    ) async {
      await tester.pumpWidget(screen(held: true));
      await tester.pumpAndSettle();

      expect(find.text(pl.queueBadgeAwaitingReview), findsOneWidget);
      expect(find.text(pl.queueStartNext), findsNothing);
      await tester.tap(byLogId('queue.actions'));
      await tester.pumpAndSettle();
      expect(byLogId('queue.action.start'), findsNothing);
      expect(byLogId('queue.action.edit'), findsOneWidget);
    });

    testWidgets('anyone else sees the job staged and may start it', (
      tester,
    ) async {
      await tester.pumpWidget(screen(held: false));
      await tester.pumpAndSettle();

      expect(find.text(pl.queueBadgeStaged), findsOneWidget);
      expect(find.text(pl.queueStartNext), findsOneWidget);
      await tester.tap(byLogId('queue.actions'));
      await tester.pumpAndSettle();
      expect(byLogId('queue.action.start'), findsOneWidget);
    });
  });

  testWidgets('a job with no owner is claimed by a bare start (#1670)', (
    tester,
  ) async {
    // Every PATCH on it is refused to an update-own user until /start has made
    // it theirs, so the flow must neither assign a printer nor save a mapping.
    final ownerless = QueueItem.fromJson({
      ...readFixture('queue_item.json') as Map<String, dynamic>,
      'status': 'pending',
      'printer_id': 1,
      'created_by_id': null,
    });
    final queue = FakeQueue([ownerless]);
    await tester.pumpWidget(
      ProviderScope(
        retry: neverRetry,
        overrides: [
          queueProvider.overrideWith(() => queue),
          noServerProfileOverride,
          currentUserOverride(
            const CurrentUser(
              id: 7,
              username: 'op',
              isAdmin: false,
              permissions: {
                Permissions.queueUpdateOwn,
                Permissions.queueStartUnreviewed,
              },
            ),
          ),
          requirePlateClearProvider.overrideWithValue(const AsyncData(false)),
        ],
        child: plApp(const QueueScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(byLogId('queue.actions'));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('queue.action.start'));
    await tester.pumpAndSettle();

    expect(queue.startedAsIs, [ownerless.id]);
    expect(queue.started, isEmpty);
  });

  testWidgets('a job with alternatives is released by a bare start (#671)', (
    tester,
  ) async {
    // The server answers 400 to a printer put on a job with alternatives, so
    // the flow must neither pick a printer nor assign one.
    final crossModel = QueueItem.fromJson({
      ...readFixture('queue_item.json') as Map<String, dynamic>,
      'status': 'pending',
      'printer_id': null,
      'target_model': 'X1C',
      'variants': [
        {
          'library_file_id': 1,
          'filename': 'a.3mf',
          'target_model': 'X1C',
          'position': 0,
        },
        {
          'library_file_id': 2,
          'filename': 'b.3mf',
          'target_model': 'P1S',
          'position': 1,
        },
      ],
    });
    final queue = FakeQueue([crossModel]);
    await tester.pumpWidget(
      ProviderScope(
        retry: neverRetry,
        overrides: [
          queueProvider.overrideWith(() => queue),
          noServerProfileOverride,
        ],
        child: plApp(const QueueScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(byLogId('queue.actions'));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('queue.action.start'));
    await tester.pumpAndSettle();

    expect(queue.startedAsIs, [crossModel.id]);
    expect(queue.started, isEmpty);
  });

  testWidgets('swiping a pending item reveals the delete confirmation', (
    tester,
  ) async {
    // A printing item is pinned (no Dismissible) — swiping needs a
    // reorderable item, so we overwrite the status to "pending".
    final json = readFixture('queue_item.json') as Map<String, dynamic>;
    final item = QueueItem.fromJson({...json, 'status': 'pending'});

    await tester.pumpWidget(_screen([item]));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text(pl.queueDeleteTitle), findsOneWidget);
  });

  group('start flow outliving the row that began it', () {
    // The row is keyed by item id, so an item leaving the list disposes exactly
    // this card — and the list is rebuilt on every WS-driven refresh. Anything
    // the flow still needs from `ref` after an await would throw there ("Cannot
    // use ref after the widget was disposed"), which is why it reads through the
    // provider container instead.
    final pending = QueueItem.fromJson({
      ...readFixture('queue_item.json') as Map<String, dynamic>,
      'status': 'pending',
      'started_at': null,
    });

    late FakeQueue queue;
    late _HeldCommands commands;

    Widget screen({AsyncValue<bool> gate = const AsyncValue.data(true)}) {
      queue = FakeQueue([pending]);
      commands = _HeldCommands();
      return ProviderScope(
        retry: neverRetry,
        overrides: [
          queueProvider.overrideWith(() => queue),
          noServerProfileOverride,
          printerCommandsRepositoryProvider.overrideWithValue(commands),
          // The scheduler gates on the plate, and this printer's is dirty —
          // the branch that sends a request before the start does.
          requirePlateClearProvider.overrideWithValue(gate),
          printerStatusesProvider.overrideWith(_DirtyPlateStatuses.new),
          // The mapping sheet with nothing to map: one confirm button.
          printRequirementsProvider.overrideWith((ref, key) async => const []),
          mappingStatusProvider.overrideWith((ref, printerId) async => null),
        ],
        child: plApp(const QueueScreen()),
      );
    }

    /// Menu → Start → mapping sheet → the plate confirmation, stopping with the
    /// acknowledgement in flight.
    Future<void> startUntilRequestInFlight(WidgetTester tester) async {
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, pl.queueStart));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, pl.queueStart));
      await tester.pumpAndSettle();

      await tester.tap(find.text(pl.plateClearConfirm));
      await tester.pumpAndSettle();
      expect(commands.acks, 1, reason: 'the acknowledgement is on the wire');
    }

    testWidgets('a failure nobody predicted still reaches the user', (
      tester,
    ) async {
      // A settings read that broke outright: no step in the flow words this
      // one, so without the net the user picks a printer, maps the AMS, and
      // then nothing happens at all — no print and no explanation.
      await tester.pumpWidget(
        screen(
          gate: AsyncValue.error(StateError('unreadable'), StackTrace.empty),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, pl.queueStart));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, pl.queueStart));
      await tester.pumpAndSettle();

      expect(find.text(pl.connectFailed), findsOneWidget);
      expect(queue.started, isEmpty, reason: 'nothing reached the server');
      expect(
        tester.takeException(),
        isStateError,
        reason: 'still reported, so a bug report keeps what actually broke',
      );
    });

    testWidgets('the print still starts when the row goes mid-request', (
      tester,
    ) async {
      await startUntilRequestInFlight(tester);

      // The queue refreshes and this item is gone — the card is disposed while
      // the acknowledgement is still in flight.
      queue.replace(const []);
      await tester.pump();
      expect(find.byIcon(Icons.more_vert), findsNothing);

      commands.release();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(queue.started, [
        (item: 78, printer: 1),
      ], reason: 'the start the user asked for is not dropped');
    });

    testWidgets('a refusal after the row is gone is still explained', (
      tester,
    ) async {
      await startUntilRequestInFlight(tester);

      queue.replace(const []);
      await tester.pump();
      commands.release(
        const ApiException(
          AppErrorCode.badResponse,
          statusCode: 400,
          detail: 'Printer not connected',
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining(pl.plateClearNeedsOnline), findsOneWidget);
      expect(queue.started, isEmpty, reason: 'a held gate starts nothing');
    });
  });
}

/// A plate the scheduler is waiting on, on a printer that is not reachable.
class _DirtyPlateStatuses extends PrinterStatusesNotifier {
  @override
  Map<int, PrinterStatus> build() => const {
    1: PrinterStatus(id: 1, connected: false, awaitingPlateClear: true),
  };
}

/// Holds the plate-clear acknowledgement open until a test answers it.
class _HeldCommands implements PrinterCommandsRepository {
  final _held = Completer<void>();
  int acks = 0;
  Object? _error;

  /// Answers the request in flight: successfully, or with [error].
  void release([Object? error]) {
    _error = error;
    _held.complete();
  }

  @override
  Future<void> clearPlate(int printerId) async {
    acks++;
    await _held.future;
    if (_error != null) throw _error!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}
