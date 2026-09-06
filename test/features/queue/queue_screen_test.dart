import 'dart:async';

import 'package:bambuddy_mobile/core/api/action_outcome.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/printer_commands_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_mapping_sheet.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_screen.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Fake notifier — returns the given list without touching the repository/network.
class _FakeQueueNotifier extends QueueNotifier {
  _FakeQueueNotifier(this._items);

  final List<QueueItem> _items;

  @override
  Future<List<QueueItem>> build() async => _items;
}

Widget _screen(List<QueueItem> items) => ProviderScope(
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
        find.text('Drukuje'),
        findsOneWidget,
        reason: 'status printing → pl',
      );
      expect(find.textContaining('X2D-3DP'), findsOneWidget);
    },
  );

  testWidgets('an empty queue shows a message', (tester) async {
    await tester.pumpWidget(_screen(const []));
    await tester.pumpAndSettle();

    expect(find.text('Kolejka jest pusta'), findsOneWidget);
  });

  testWidgets('no FAB when the queue only has printing items', (tester) async {
    final json = readFixture('queue_item.json') as Map<String, dynamic>;
    final printing = QueueItem.fromJson({...json, 'status': 'printing'});

    await tester.pumpWidget(_screen([printing]));
    await tester.pumpAndSettle();

    expect(find.text('Uruchom następny'), findsNothing);
  });

  testWidgets('the "Start next" FAB is visible when there are pending prints', (
    tester,
  ) async {
    final json = readFixture('queue_item.json') as Map<String, dynamic>;
    final pending = QueueItem.fromJson({...json, 'status': 'pending'});

    await tester.pumpWidget(_screen([pending]));
    await tester.pumpAndSettle();

    expect(find.text('Uruchom następny'), findsOneWidget);
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

    expect(find.text('Usunąć z kolejki?'), findsOneWidget);
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

    late _MutableQueueNotifier queue;
    late _HeldCommands commands;

    Widget screen() {
      queue = _MutableQueueNotifier([pending]);
      commands = _HeldCommands();
      return ProviderScope(
        overrides: [
          queueProvider.overrideWith(() => queue),
          noServerProfileOverride,
          printerCommandsRepositoryProvider.overrideWithValue(commands),
          // The scheduler gates on the plate, and this printer's is dirty —
          // the branch that sends a request before the start does.
          requirePlateClearProvider.overrideWith((ref) async => true),
          printerStatusesProvider.overrideWith(_DirtyPlateStatuses.new),
          // The mapping sheet with nothing to map: one confirm button.
          filamentRequirementsProvider.overrideWith(
            (ref, key) async => const [],
          ),
          printerTraysProvider.overrideWith((ref, printerId) async => const []),
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
      await tester.tap(find.widgetWithText(ListTile, 'Uruchom teraz'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Uruchom teraz'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Płyta jest pusta'));
      await tester.pumpAndSettle();
      expect(commands.acks, 1, reason: 'the acknowledgement is on the wire');
    }

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
      expect(find.textContaining('Zaktualizuj bambuddy'), findsOneWidget);
      expect(queue.started, isEmpty, reason: 'a held gate starts nothing');
    });
  });
}

/// Queue whose list a test can change under the screen, and which records the
/// starts it was asked for instead of talking to a server.
class _MutableQueueNotifier extends QueueNotifier {
  _MutableQueueNotifier(this._items);

  List<QueueItem> _items;
  final List<({int item, int printer})> started = [];

  @override
  Future<List<QueueItem>> build() async => _items;

  void replace(List<QueueItem> items) {
    _items = items;
    state = AsyncData(items);
  }

  @override
  Future<ActionOutcome> startOnPrinter(
    int itemId,
    int printerId, {
    List<int>? amsMapping,
  }) async {
    started.add((item: itemId, printer: printerId));
    return ActionOutcome.ok;
  }
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
