import 'dart:async';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/features/archive/outcome_sheet.dart';
import 'package:bambuddy_mobile/features/queue/queue_edit_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// The sheet that asks how a print came out. What it sends is the point: the
/// server counts a completed reject out of the project's good parts and yield,
/// so a verdict or a cause written wrong is a wrong number on another screen.
void main() {
  late _FakeArchives repo;

  Future<void> open(
    WidgetTester tester,
    Archive archive, {
    bool rejecting = false,
    CurrentUser? user,
  }) async {
    repo = _FakeArchives(archive);
    SharedPreferences.setMockInitialValues({});
    // The reprint form reads the print options this phone remembers.
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          archiveRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
          noServerProfileOverride,
          if (user != null) currentUserOverride(user),
        ],
        child: plApp(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showOutcomeSheet(context, archive.id, rejecting: rejecting),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    // A menu entry may sit scrolled past the menu's 320 px.
    await tester.ensureVisible(find.text(text).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  testWidgets('Good records a good part as given in the app', (tester) async {
    await open(tester, testArchive(confirmRequested: true));

    await tapText(tester, pl.outcomeGood);

    expect(repo.sent.single, (
      verdict: PrintVerdict.good,
      reason: null,
      clearReason: false,
    ));
    expect(find.text(pl.outcomeSavedGood), findsOneWidget);
    expect(find.byType(OutcomeSheet), findsNothing);
  });

  testWidgets('a reject carries the cause picked for it', (tester) async {
    await open(tester, testArchive(confirmRequested: true));

    await tapText(tester, pl.outcomeReject);
    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    await tapText(tester, pl.failureReasonWarping);
    await tapText(tester, pl.outcomeSaveReject);

    expect(repo.sent.single, (
      verdict: PrintVerdict.reject,
      reason: 'warping',
      clearReason: false,
    ));
    expect(find.text(pl.outcomeSavedReject), findsOneWidget);
  });

  // "No reason" is a choice, not an absence: kept silent, the cause a print
  // already carries would survive a user taking it off.
  testWidgets('choosing no reason clears the one a reject carried', (
    tester,
  ) async {
    await open(
      tester,
      _withReason(testArchive(userVerdict: PrintVerdict.reject), 'warping'),
    );

    await tapText(tester, pl.outcomeReject);
    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    await tapText(tester, pl.outcomeNoReason);
    await tapText(tester, pl.outcomeSaveReject);

    expect(repo.sent.single, (
      verdict: PrintVerdict.reject,
      reason: null,
      clearReason: true,
    ));
  });

  // The archive detail's thumb down has already stored the reject; what is
  // left to ask is why.
  testWidgets('opened for a reject it starts on the reason', (tester) async {
    await open(
      tester,
      testArchive(userVerdict: PrintVerdict.reject),
      rejecting: true,
    );

    expect(find.byType(DropdownMenu<String>), findsOneWidget);
    expect(find.text(pl.outcomeSaveReject), findsOneWidget);
    expect(find.text(pl.outcomeGood), findsNothing);
  });

  // Saved untouched, the reason step must not take off the cause it opened
  // with.
  testWidgets('opened for a reject it keeps the cause until changed', (
    tester,
  ) async {
    await open(
      tester,
      _withReason(testArchive(userVerdict: PrintVerdict.reject), 'warping'),
      rejecting: true,
    );

    await tapText(tester, pl.outcomeSaveReject);

    expect(repo.sent.single, (
      verdict: PrintVerdict.reject,
      reason: 'warping',
      clearReason: false,
    ));
  });

  testWidgets('taking a reject back clears its cause', (tester) async {
    await open(
      tester,
      _withReason(testArchive(userVerdict: PrintVerdict.reject), 'warping'),
    );

    await tapText(tester, pl.outcomeGood);

    expect(repo.sent.single, (
      verdict: PrintVerdict.good,
      reason: null,
      clearReason: true,
    ));
  });

  testWidgets('a verdict already given can be cleared', (tester) async {
    await open(tester, testArchive(userVerdict: PrintVerdict.good));

    expect(find.text(pl.outcomeLater), findsNothing);
    await tapText(tester, pl.outcomeClear);

    expect(repo.sent.single.verdict, isNull);
    expect(find.text(pl.outcomeCleared), findsOneWidget);
  });

  testWidgets('a verdict the server dropped is not reported as saved', (
    tester,
  ) async {
    await open(tester, testArchive(confirmRequested: true));
    repo.applied = false;

    await tapText(tester, pl.outcomeGood);

    expect(find.text(pl.outcomeUnsupported), findsOneWidget);
    expect(find.text(pl.outcomeSavedGood), findsNothing);
  });

  testWidgets('a refusal keeps the sheet open and says why', (tester) async {
    await open(tester, testArchive(confirmRequested: true));
    repo.error = const AuthException(AppErrorCode.forbidden);

    await tapText(tester, pl.outcomeGood);

    expect(find.byType(OutcomeSheet), findsOneWidget);
    expect(find.text(pl.outcomeSavedGood), findsNothing);
  });

  // The sheet's navigator outlives the sheet: popping it after a dismissal
  // closed whatever screen the user had gone back to.
  testWidgets('a sheet dismissed during the save leaves the screen alone', (
    tester,
  ) async {
    await open(tester, testArchive(confirmRequested: true));
    repo.held = Completer<void>();

    await tester.tap(find.text(pl.outcomeGood).last);
    await tester.pump();
    Navigator.of(tester.element(find.byType(OutcomeSheet))).pop();
    await tester.pumpAndSettle();
    repo.held!.complete();
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('two taps in one frame send one verdict', (tester) async {
    await open(tester, testArchive(confirmRequested: true));
    repo.held = Completer<void>();

    await tester.tap(find.text(pl.outcomeGood).last);
    await tester.tap(find.text(pl.outcomeGood).last, warnIfMissed: false);
    repo.held!.complete();
    await tester.pumpAndSettle();

    expect(repo.sent, hasLength(1));
  });

  testWidgets('a cause outside the list is shown, not blanked', (tester) async {
    await open(
      tester,
      _withReason(testArchive(userVerdict: PrintVerdict.reject), 'Stringy'),
    );

    await tapText(tester, pl.outcomeReject);

    expect(find.text('Stringy'), findsWidgets);
  });

  testWidgets('print again opens the form on the same file', (tester) async {
    await open(tester, testArchive(confirmRequested: true));

    await tapText(tester, pl.outcomeReject);
    await tapText(tester, pl.outcomeRejectAndReprint);

    expect(repo.sent.single.verdict, PrintVerdict.reject);
    final form = tester.widget<QueueEditScreen>(find.byType(QueueEditScreen));
    expect(form.item.archiveId, 1);
  });

  // The server refuses the queue job without the reprint right (403), so the
  // reject can still be saved but not followed by a print.
  testWidgets('print again is off, with the reason, without the right', (
    tester,
  ) async {
    await open(
      tester,
      testArchive(confirmRequested: true),
      user: const CurrentUser(
        id: 7,
        username: 'op',
        isAdmin: false,
        permissions: {Permissions.queueCreate},
      ),
    );

    await tapText(tester, pl.outcomeReject);

    final again = buttonAt(tester, 'outcome.reject_reprint');
    expect(again.onPressed, isNull);
    expect(find.text(pl.archiveReprintNotAllowed), findsOneWidget);
    expect(find.text(pl.outcomeSaveReject), findsOneWidget);
  });
}

Archive _withReason(Archive a, String reason) => Archive(
  id: a.id,
  filename: a.filename,
  status: a.status,
  printName: a.printName,
  confirmRequested: a.confirmRequested,
  userVerdict: a.userVerdict,
  failureReason: reason,
);

class _FakeArchives implements ArchiveRepository {
  _FakeArchives(this.archive);

  Archive archive;
  bool applied = true;
  AppApiException? error;
  Completer<void>? held;
  final sent = <({PrintVerdict? verdict, String? reason, bool clearReason})>[];

  @override
  Future<Archive> byId(int archiveId) async => archive;

  @override
  Future<({Archive archive, bool applied})> setVerdict(
    int archiveId,
    PrintVerdict? verdict, {
    String? reason,
    bool clearReason = false,
  }) async {
    if (error != null) throw error!;
    sent.add((verdict: verdict, reason: reason, clearReason: clearReason));
    if (held != null) await held!.future;
    return (archive: archive, applied: applied);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}
