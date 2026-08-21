import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/print_log_entry.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/features/print_log/print_log_providers.dart';
import 'package:bambuddy_mobile/features/print_log/print_log_screen.dart';
import 'package:bambuddy_mobile/features/stats/stats_common.dart' show fmtNum;
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The print log's screen, held to the two things it can get wrong quietly.
///
/// One is the edit: `PATCH /print-log/{id}` applies only the fields it is
/// given, and a status this server cannot write back (`aborted`) survives
/// exactly as long as the field stays unsent. The other is the version gate —
/// below 1.2.6 cost and energy are absent from every row, which is not the same
/// as a run that drew no power.
class _FakePrintLog extends PrintLogNotifier {
  _FakePrintLog(this.entries, {this.failure});

  final List<PrintLogEntry> entries;

  /// Returned instead of applying, to stand for a server that refuses.
  final AppApiException? failure;

  ({String? reason, bool cleared, String? status})? lastEdit;
  int? deleted;
  var cleared = 0;

  @override
  Future<PrintLogState> build() async =>
      PrintLogState(items: entries, total: entries.length);

  @override
  Future<AppApiException?> reclassify(
    int entryId, {
    String? failureReason,
    bool clearFailureReason = false,
    String? status,
  }) async {
    lastEdit = (
      reason: failureReason,
      cleared: clearFailureReason,
      status: status,
    );
    return failure;
  }

  @override
  Future<AppApiException?> deleteEntry(int entryId) async {
    deleted = entryId;
    return failure;
  }

  @override
  Future<(int?, AppApiException?)> clearAll() async {
    cleared++;
    return (entries.length, failure);
  }
}

/// Null profile: nothing here talks to a server, and building the API client
/// without one throws by design. It also keeps the thumbnail tile on its
/// placeholder instead of reaching for a camera token.
class _NullProfile extends ServerProfileNotifier {
  @override
  ServerProfile? build() => null;
}

PrintLogEntry _entry({
  int id = 7,
  String name = 'Benchy',
  String status = 'failed',
  String? failureReason,
  int? archiveId = 82,
  double? cost = 1.23,
  double? energyKwh = 0.42,
}) =>
    PrintLogEntry(
      id: id,
      status: status,
      createdAt: DateTime(2026, 8, 1, 9, 59),
      startedAt: DateTime(2026, 8, 1, 10),
      archiveId: archiveId,
      printName: name,
      printerName: 'P1S',
      createdByUsername: 'zosia',
      durationSeconds: 5400,
      filamentUsedGrams: 42.5,
      failureReason: failureReason,
      cost: cost,
      energyKwh: energyKwh,
    );

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pl'));
  });

  /// `pumpAndSettle` never returns here — the search field's cursor blinks
  /// forever, so no frame is ever free of animation. A fixed span is long
  /// enough for a sheet or a dialog to finish opening.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  Future<_FakePrintLog> pumpScreen(
    WidgetTester tester, {
    List<PrintLogEntry>? entries,
    bool costEnergy = true,
    AppApiException? failure,
  }) async {
    final fake = _FakePrintLog(entries ?? [_entry()], failure: failure);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        printLogProvider.overrideWith(() => fake),
        printLogCostEnergyProvider.overrideWith((ref) async => costEnergy),
        serverProfileProvider.overrideWith(_NullProfile.new),
      ],
      child: plApp(const PrintLogScreen()),
    ));
    await settle(tester);
    return fake;
  }

  /// Opens one entry's classification sheet.
  Future<void> openSheet(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await settle(tester);
  }

  /// Picks [option] out of one of the sheet's two combos — 0 is the cause, 1
  /// the status. Found by type rather than by label: a `DropdownMenu` shows the
  /// *selected* value in its field, and its label floats out of the way, so a
  /// text finder hits whatever happens to be chosen.
  Future<void> pick(WidgetTester tester, int combo, String option) async {
    await tester.tap(find.byType(DropdownMenu<String>).at(combo));
    await settle(tester);
    // The open menu is a scrollable overlay taller than the room under a sheet,
    // so an entry can be built and still be off-screen — where a tap silently
    // misses instead of failing.
    final entry = find.text(option).last;
    await tester.ensureVisible(entry);
    await tester.pump();
    await tester.tap(entry);
    await settle(tester);
  }

  const reasonCombo = 0;
  const statusCombo = 1;

  testWidgets('a cause set on its own leaves the status unsent', (tester) async {
    // The load-bearing case: this row carries `aborted`, which the PATCH
    // vocabulary has no value for. Sending the status field at all would cost
    // the row a value it can never be given back.
    final fake = await pumpScreen(
      tester,
      entries: [_entry(status: 'aborted', name: 'Spiral vase')],
    );
    await openSheet(tester, 'Spiral vase');

    await pick(tester, reasonCombo, l10n.failureReasonLayerShift);
    await tester.tap(find.widgetWithText(FilledButton, l10n.printLogSave));
    await settle(tester);

    expect(fake.lastEdit?.reason, 'layerShift');
    expect(fake.lastEdit?.cleared, isFalse);
    expect(fake.lastEdit?.status, isNull, reason: 'aborted must survive');
  });

  testWidgets('clearing the cause sends the clear, not a null', (tester) async {
    final fake = await pumpScreen(
      tester,
      entries: [_entry(failureReason: 'warping')],
    );
    await openSheet(tester, 'Benchy');

    await pick(tester, reasonCombo, l10n.printLogNoClassification);
    await tester.tap(find.widgetWithText(FilledButton, l10n.printLogSave));
    await settle(tester);

    expect(fake.lastEdit?.cleared, isTrue);
    expect(fake.lastEdit?.reason, isNull);
  });

  testWidgets('save stays dead until something actually changes',
      (tester) async {
    await pumpScreen(tester);
    await openSheet(tester, 'Benchy');

    final save = find.widgetWithText(FilledButton, l10n.printLogSave);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await pick(tester, reasonCombo, l10n.failureReasonWarping);

    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
  });

  testWidgets('the sheet says whether the chosen status counts as a failure',
      (tester) async {
    // A cause on a run the server does not count as a failure is stored and
    // then shown nowhere — the sheet has to say so while the choice is made.
    await pumpScreen(tester, entries: [_entry(status: 'failed')]);
    await openSheet(tester, 'Benchy');

    expect(find.text(l10n.printLogCountsAsFailure), findsOneWidget);

    await pick(tester, statusCombo, l10n.printLogStatusCompleted);

    expect(find.text(l10n.printLogNotCountedAsFailure), findsOneWidget);
  });

  testWidgets('an unwritable status is offered, and flagged as one-way',
      (tester) async {
    await pumpScreen(tester, entries: [_entry(status: 'aborted')]);
    await openSheet(tester, 'Benchy');

    expect(
      find.text(l10n.printLogStatusOneWay(l10n.printLogStatusAborted)),
      findsOneWidget,
    );
  });

  testWidgets('energy is shown where the server sends it', (tester) async {
    await pumpScreen(tester, costEnergy: true);

    expect(
      find.textContaining(l10n.printLogEnergy(fmtNum(0.42))),
      findsOneWidget,
    );
  });

  testWidgets('energy stays off a server that withholds it', (tester) async {
    // Below 1.2.6 the field is absent from every row, so a figure here would be
    // the app inventing one — and a zero would read as a measurement.
    await pumpScreen(tester, costEnergy: false);

    expect(
      find.textContaining(l10n.printLogEnergy(fmtNum(0.42))),
      findsNothing,
    );
  });

  testWidgets('an orphan run is marked as one', (tester) async {
    await pumpScreen(tester, entries: [_entry(archiveId: null)]);

    expect(find.text(l10n.printLogOrphan), findsOneWidget);
  });

  testWidgets('clearing the log asks first, and names the count',
      (tester) async {
    final fake = await pumpScreen(
      tester,
      entries: [_entry(id: 1), _entry(id: 2, name: 'Cube')],
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await settle(tester);
    await tester.tap(find.text(l10n.printLogClear).last);
    await settle(tester);

    expect(find.text(l10n.printLogClearBody(2)), findsOneWidget);
    expect(fake.cleared, 0, reason: 'nothing goes before the answer');

    await tester.tap(find.widgetWithText(FilledButton, l10n.printLogClear));
    await settle(tester);

    expect(fake.cleared, 1);
  });

  testWidgets('deleting one run asks first', (tester) async {
    final fake = await pumpScreen(tester);
    await openSheet(tester, 'Benchy');

    await tester.tap(find.widgetWithText(TextButton, l10n.printLogDelete));
    await settle(tester);
    expect(fake.deleted, isNull);

    await tester.tap(find.widgetWithText(FilledButton, l10n.printLogDelete));
    await settle(tester);

    expect(fake.deleted, 7);
  });

  testWidgets('a refused edit is told, and the sheet stays open',
      (tester) async {
    // A key with read-only scope gets a 403 on every write; the row must not
    // look edited when nothing was.
    await pumpScreen(
      tester,
      failure: const AuthException(AppErrorCode.forbidden),
    );
    await openSheet(tester, 'Benchy');

    await pick(tester, reasonCombo, l10n.failureReasonOther);
    await tester.tap(find.widgetWithText(FilledButton, l10n.printLogSave));
    await settle(tester);

    expect(find.text(l10n.printLogSaveFailed), findsOneWidget);
    expect(find.text(l10n.printLogFailureCause), findsWidgets);
  });
}
