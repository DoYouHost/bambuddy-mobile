import 'dart:async';

import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/features/queue/queue_edit_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'queue_form_harness.dart';

/// "Ask for outcome" on the print form (#1898). An older server takes the
/// flag and drops it, so the switch is only there where the server keeps it,
/// and a new job starts where the server's own print dialog starts.
void main() {
  setUp(setUpQueueForm);

  final label = formL10n.queueOptConfirmOutcome;

  List<Override> outcome({
    required bool supported,
    bool serverDefault = false,
  }) => [
    queueOutcomeProvider.overrideWithValue(AsyncData(supported)),
    defaultConfirmOutcomeProvider.overrideWithValue(AsyncData(serverDefault)),
  ];

  Future<void> tapSwitch(WidgetTester tester) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    // The title is not a tap target; the switch beside it is.
    await tester.tap(
      find.descendant(
        of: find
            .ancestor(of: find.text(label), matching: find.byType(Row))
            .first,
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a server that would drop the flag gets no switch and no key', (
    tester,
  ) async {
    await tester.pumpWidget(
      queueFormScreen(archiveDraft(), extra: outcome(supported: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text(label), findsNothing);
    await submitQueueForm(tester);
    expect(capturedBody?.containsKey('confirm_outcome'), isFalse);
  });

  testWidgets('a new job starts from the server default', (tester) async {
    await tester.pumpWidget(
      queueFormScreen(
        archiveDraft(),
        extra: outcome(supported: true, serverDefault: true),
      ),
    );
    await tester.pumpAndSettle();

    await submitQueueForm(tester);
    expect(capturedBody?['confirm_outcome'], true);
  });

  testWidgets('the switch rides with the POST', (tester) async {
    await tester.pumpWidget(
      queueFormScreen(archiveDraft(), extra: outcome(supported: true)),
    );
    await tester.pumpAndSettle();

    await tapSwitch(tester);
    await submitQueueForm(tester);
    expect(capturedBody?['confirm_outcome'], true);
  });

  // The key is left out rather than resent: another client may have changed
  // it while the form was open.
  testWidgets('an edit that does not touch the switch does not send it', (
    tester,
  ) async {
    await tester.pumpWidget(
      queueFormScreen(
        QueueItem.fromJson({
          'id': 5,
          'position': 1,
          'status': 'pending',
          'archive_id': 77,
          'printer_id': 1,
          'confirm_outcome': true,
        }),
        schedule: QueueScheduleType.queue,
        mode: QueueEditMode.edit,
        extra: outcome(supported: true),
      ),
    );
    await tester.pumpAndSettle();

    await submitQueueForm(tester, edit: true);
    expect(capturedBody?.containsKey('confirm_outcome'), isFalse);
  });

  testWidgets('a job submitted before the default arrives waits for it', (
    tester,
  ) async {
    final settings = Completer<bool>();
    await tester.pumpWidget(
      queueFormScreen(
        archiveDraft(),
        extra: [
          queueOutcomeProvider.overrideWithValue(const AsyncData(true)),
          defaultConfirmOutcomeProvider.overrideWith(
            (ref) => ref.watch(_heldDefault(settings)),
          ),
        ],
      ),
    );
    await tester.pump();

    await tester.tap(
      find.widgetWithText(FilledButton, formL10n.queueCreateSubmit),
    );
    await tester.pump();
    settings.complete(true);
    await tester.pumpAndSettle();

    expect(capturedBody?['confirm_outcome'], true);
  });

  // The server copies only a `true` onto the archive and never clears it, so a
  // switch that could be turned off here would promise a silence that never
  // comes.
  testWidgets('a reprint of an archive that asks says it will ask again', (
    tester,
  ) async {
    await tester.pumpWidget(
      queueFormScreen(
        QueueItem.draft(
          archiveId: 77,
          name: 'cube.3mf',
          printerId: 1,
          slicedForModel: 'X2D',
          confirmOutcome: true,
        ),
        extra: outcome(supported: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(formL10n.queueOptConfirmOutcomeSticky), findsOneWidget);
    await submitQueueForm(tester);
    expect(capturedBody?['confirm_outcome'], true);
  });

  testWidgets('a choice survives the gate reloading before submit', (
    tester,
  ) async {
    await tester.pumpWidget(
      queueFormScreen(
        archiveDraft(),
        extra: [
          queueOutcomeProvider.overrideWith((ref) => ref.watch(_gate)),
          defaultConfirmOutcomeProvider.overrideWithValue(
            const AsyncData(false),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tapSwitch(tester);
    ProviderScope.containerOf(
      tester.element(find.byType(QueueEditScreen)),
    ).read(_gate.notifier).state = const AsyncLoading();
    await tester.pump();
    await submitQueueForm(tester);

    expect(capturedBody?['confirm_outcome'], true);
  });

  // The item's own flag, not the server default: editing is about THIS job.
  testWidgets('editing starts from the flag the item has', (tester) async {
    await tester.pumpWidget(
      queueFormScreen(
        QueueItem.fromJson({
          'id': 5,
          'position': 1,
          'status': 'pending',
          'archive_id': 77,
          'printer_id': 1,
          'confirm_outcome': true,
        }),
        schedule: QueueScheduleType.queue,
        mode: QueueEditMode.edit,
        extra: outcome(supported: true),
      ),
    );
    await tester.pumpAndSettle();

    await tapSwitch(tester);
    await submitQueueForm(tester, edit: true);
    expect(capturedBody?['confirm_outcome'], false);
  });
}

/// A default that answers when [answer] completes — `/settings` still out when
/// the form opens.
final _heldDefault = FutureProvider.family<bool, Completer<bool>>(
  (ref, answer) => answer.future,
);

final _gate = StateProvider<AsyncValue<bool>>((ref) => const AsyncData(true));
