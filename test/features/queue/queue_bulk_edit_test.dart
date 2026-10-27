import 'package:bambuddy_mobile/core/api/action_outcome.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/features/queue/queue_bulk_edit_screen.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_removal.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The bulk edit (`PATCH /queue/bulk`): the web's "Edit N items" modal. Its
/// whole contract is that a setting nobody touched is not sent — the route
/// applies only the keys it receives, to every row at once.
void main() {
  Widget screen({
    _BulkQueue? queue,
    bool triState = true,
    Set<String> snippets = const {},
    bool outcome = true,
    List<Printer> printers = const [
      Printer(id: 1, name: 'X1C', model: 'X1C', nozzleCount: 1),
      Printer(id: 2, name: 'P1S', model: 'P1S', nozzleCount: 1),
    ],
    CurrentUser? user,
  }) => ProviderScope(
    retry: neverRetry,
    overrides: [
      noServerProfileOverride,
      queueProvider.overrideWith(() => queue ?? _BulkQueue()),
      allPrintersProvider.overrideWith((ref) async => printers),
      triStateCalibrationProvider.overrideWithValue(AsyncData(triState)),
      gcodeSnippetModelsProvider.overrideWithValue(AsyncData(snippets)),
      queueOutcomeProvider.overrideWithValue(AsyncData(outcome)),
      currentUserOverride(user),
    ],
    child: plApp(const QueueBulkEditScreen(itemIds: [4, 9])),
  );

  /// One segment of one setting: every segment of a row shares the row's id, so
  /// the label picks the one meant.
  Finder choice(String id, String label) =>
      find.descendant(of: byLogId(id), matching: find.text(label));

  Finder apply() => find.widgetWithText(FilledButton, pl.queueBulkApply);

  Future<void> open(WidgetTester tester, Widget app) async {
    usePhoneWindow(tester, dp: 3200);
    // Dropped first: a scope keeps the overrides it was built with, so a test
    // that opens the screen twice would read the first one's answers.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  bool applyEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(apply()).onPressed != null;

  testWidgets('says how many items it edits and sends nothing until a change', (
    tester,
  ) async {
    await open(tester, screen());

    expect(find.text(pl.queueBulkTitle(2)), findsOneWidget);
    expect(
      applyEnabled(tester),
      isFalse,
      reason: 'an empty body is a 400 ("No fields to update")',
    );
  });

  testWidgets('only what was touched goes out, for every picked id', (
    tester,
  ) async {
    final queue = _BulkQueue();
    await open(tester, screen(queue: queue));

    await tester.tap(choice('queue_bulk.timelapse', pl.commonOn));
    await tester.tap(choice('queue_bulk.vibration_cali', pl.commonOff));
    await tester.pump();
    expect(applyEnabled(tester), isTrue);
    await tester.tap(apply());
    await tester.pumpAndSettle();

    expect(queue.calls.single.$1, [4, 9]);
    expect(queue.calls.single.$2, {'timelapse': true, 'vibration_cali': false});
  });

  testWidgets('tapping the picked value again leaves the setting alone', (
    tester,
  ) async {
    final queue = _BulkQueue();
    await open(tester, screen(queue: queue));

    await tester.tap(choice('queue_bulk.use_ams', pl.commonOn));
    await tester.pump();
    expect(applyEnabled(tester), isTrue);
    await tester.tap(choice('queue_bulk.use_ams', pl.commonOn));
    await tester.pump();

    expect(applyEnabled(tester), isFalse);
    expect(queue.calls, isEmpty);
  });

  testWidgets(
    'the printer: "no printer" unassigns, and the key is null, not absent',
    (tester) async {
      final queue = _BulkQueue();
      await open(tester, screen(queue: queue));

      await tester.tap(byLogId('queue_bulk.printer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(pl.queueBulkUnassigned).last);
      await tester.pumpAndSettle();
      await tester.tap(apply());
      await tester.pumpAndSettle();

      expect(queue.calls.single.$2, {'printer_id': null});
    },
  );

  testWidgets('a printer picked by name goes out as its id', (tester) async {
    final queue = _BulkQueue();
    await open(tester, screen(queue: queue));

    await tester.tap(byLogId('queue_bulk.printer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('P1S').last);
    await tester.pumpAndSettle();
    await tester.tap(apply());
    await tester.pumpAndSettle();

    expect(queue.calls.single.$2, {'printer_id': 2});
  });

  group('calibration rows', () {
    testWidgets('a 1.2.5 server can be told auto', (tester) async {
      final queue = _BulkQueue();
      await open(tester, screen(queue: queue));

      await tester.tap(choice('queue_bulk.bed_levelling', pl.commonAuto));
      await tester.pump();
      await tester.tap(apply());
      await tester.pumpAndSettle();

      expect(queue.calls.single.$2, {'bed_levelling': 'auto'});
    });

    testWidgets('an older server has no auto to offer', (tester) async {
      await open(tester, screen(triState: false));

      expect(choice('queue_bulk.bed_levelling', pl.commonAuto), findsNothing);
      expect(choice('queue_bulk.bed_levelling', pl.commonOn), findsOneWidget);
    });
  });

  group('rows that are offered only where they do something', () {
    testWidgets('G-code injection waits for a snippet on the server', (
      tester,
    ) async {
      await open(tester, screen());
      expect(byLogId('queue_bulk.gcode_injection'), findsNothing);

      await open(tester, screen(snippets: const {'A1 mini'}));
      expect(byLogId('queue_bulk.gcode_injection'), findsWidgets);
    });

    testWidgets('"ask for the outcome" waits for a server that reads it', (
      tester,
    ) async {
      await open(tester, screen(outcome: false));
      expect(byLogId('queue_bulk.confirm_outcome'), findsNothing);

      await open(tester, screen());
      expect(byLogId('queue_bulk.confirm_outcome'), findsWidgets);
    });

    testWidgets('the nozzle offset needs a two-nozzle printer on the farm', (
      tester,
    ) async {
      await open(tester, screen());
      expect(byLogId('queue_bulk.nozzle_offset_cali'), findsNothing);

      await open(
        tester,
        screen(
          printers: const [
            Printer(id: 1, name: 'H2D', model: 'H2D', nozzleCount: 2),
          ],
        ),
      );
      expect(byLogId('queue_bulk.nozzle_offset_cali'), findsWidgets);
    });
  });

  group('power off when done', () {
    CurrentUser user(Set<String> permissions) => CurrentUser(
      id: 7,
      username: 'u',
      isAdmin: false,
      permissions: permissions,
    );

    testWidgets('is shut without printers:control, as on the web', (
      tester,
    ) async {
      final queue = _BulkQueue();
      await open(
        tester,
        screen(queue: queue, user: user({Permissions.queueUpdateOwn})),
      );

      await tester.tap(
        choice('queue_bulk.auto_off', pl.commonOn),
        warnIfMissed: false,
      );
      await tester.pump();

      expect(applyEnabled(tester), isFalse);
    });

    testWidgets('works with it', (tester) async {
      final queue = _BulkQueue();
      await open(
        tester,
        screen(
          queue: queue,
          user: user({Permissions.queueUpdateOwn, Permissions.printersControl}),
        ),
      );

      await tester.tap(choice('queue_bulk.auto_off', pl.commonOn));
      await tester.pump();
      await tester.tap(apply());
      await tester.pumpAndSettle();

      expect(queue.calls.single.$2, {'auto_off_after': true});
    });
  });

  testWidgets('a refusal is said and the form stays for another try', (
    tester,
  ) async {
    final queue = _BulkQueue(
      refusal: const AuthException(AppErrorCode.forbidden),
    );
    await open(tester, screen(queue: queue));

    await tester.tap(choice('queue_bulk.timelapse', pl.commonOn));
    await tester.pump();
    await tester.tap(apply());
    await tester.pumpAndSettle();

    expect(
      find.text(
        queueWriteMessage(
          pl,
          const ActionFailed(AuthException(AppErrorCode.forbidden)),
        )!,
      ),
      findsOneWidget,
    );
    expect(
      find.text(pl.queueBulkTitle(2)),
      findsOneWidget,
      reason: 'still on the form, with the choices as they were',
    );
    expect(applyEnabled(tester), isTrue);
  });

  group('queueBulkSummary', () {
    test('says how many changed, and how many were left alone', () {
      expect(
        queueBulkSummary(pl, (updated: 3, skipped: 0)),
        pl.queueBulkUpdated(3),
      );
      expect(
        queueBulkSummary(pl, (updated: 2, skipped: 1)),
        '${pl.queueBulkUpdated(2)}. ${pl.queueBulkSkipped(1)}',
      );
    });

    test('a 200 that changed nothing does not say "updated"', () {
      expect(
        queueBulkSummary(pl, (updated: 0, skipped: 4)),
        '${pl.queueBulkNothingUpdated}. ${pl.queueBulkSkipped(4)}',
      );
      expect(
        queueBulkSummary(pl, (updated: 0, skipped: 0)),
        pl.queueBulkNothingUpdated,
      );
    });
  });
}

/// A queue that records the bulk edits it was asked for instead of sending
/// them: the ids and the body the changes would put on the wire.
class _BulkQueue extends QueueNotifier {
  _BulkQueue({this.refusal});

  final AppApiException? refusal;
  final calls = <(List<int>, Map<String, dynamic>)>[];

  @override
  Future<List<QueueItem>> build() async => const [];

  @override
  Future<({ActionOutcome outcome, QueueBulkResult? result})> bulkUpdate(
    List<int> itemIds,
    QueueBulkChanges changes,
  ) async {
    final error = refusal;
    if (error != null) return (outcome: ActionFailed(error), result: null);
    calls.add((itemIds, changes.toJson(triState: true)));
    return (outcome: ActionOutcome.ok, result: (updated: 2, skipped: 0));
  }
}
