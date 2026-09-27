import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/features/archive/outcome_sheet.dart';
import 'package:bambuddy_mobile/features/queue/queue_edit_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations_pl.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

final _l10n = AppLocalizationsPl();

/// The sheet that asks how a print came out. What it sends is the point: the
/// server counts a completed reject out of the project's good parts and yield,
/// so a verdict or a cause written wrong is a wrong number on another screen.
void main() {
  late _FakeArchives repo;

  Future<void> open(WidgetTester tester, Archive archive) async {
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
        ],
        child: plApp(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showOutcomeSheet(context, archive.id),
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

    await tapText(tester, _l10n.outcomeGood);

    expect(repo.sent.single, (
      verdict: PrintVerdict.good,
      reason: null,
      clearReason: false,
    ));
    expect(find.text(_l10n.outcomeSavedGood), findsOneWidget);
    expect(find.byType(OutcomeSheet), findsNothing);
  });

  testWidgets('a reject carries the cause picked for it', (tester) async {
    await open(tester, testArchive(confirmRequested: true));

    await tapText(tester, _l10n.outcomeReject);
    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    await tapText(tester, _l10n.failureReasonWarping);
    await tapText(tester, _l10n.outcomeSaveReject);

    expect(repo.sent.single, (
      verdict: PrintVerdict.reject,
      reason: 'warping',
      clearReason: false,
    ));
    expect(find.text(_l10n.outcomeSavedReject), findsOneWidget);
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

    await tapText(tester, _l10n.outcomeReject);
    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    await tapText(tester, _l10n.outcomeNoReason);
    await tapText(tester, _l10n.outcomeSaveReject);

    expect(repo.sent.single, (
      verdict: PrintVerdict.reject,
      reason: null,
      clearReason: true,
    ));
  });

  testWidgets('taking a reject back clears its cause', (tester) async {
    await open(
      tester,
      _withReason(testArchive(userVerdict: PrintVerdict.reject), 'warping'),
    );

    await tapText(tester, _l10n.outcomeGood);

    expect(repo.sent.single, (
      verdict: PrintVerdict.good,
      reason: null,
      clearReason: true,
    ));
  });

  testWidgets('a verdict already given can be cleared', (tester) async {
    await open(tester, testArchive(userVerdict: PrintVerdict.good));

    expect(find.text(_l10n.outcomeLater), findsNothing);
    await tapText(tester, _l10n.outcomeClear);

    expect(repo.sent.single.verdict, isNull);
    expect(find.text(_l10n.outcomeCleared), findsOneWidget);
  });

  testWidgets('a verdict the server dropped is not reported as saved', (
    tester,
  ) async {
    await open(tester, testArchive(confirmRequested: true));
    repo.applied = false;

    await tapText(tester, _l10n.outcomeGood);

    expect(find.text(_l10n.outcomeUnsupported), findsOneWidget);
    expect(find.text(_l10n.outcomeSavedGood), findsNothing);
  });

  testWidgets('a refusal keeps the sheet open and says why', (tester) async {
    await open(tester, testArchive(confirmRequested: true));
    repo.error = const AuthException(AppErrorCode.forbidden);

    await tapText(tester, _l10n.outcomeGood);

    expect(find.byType(OutcomeSheet), findsOneWidget);
    expect(find.text(_l10n.outcomeSavedGood), findsNothing);
  });

  testWidgets('print again opens the form on the same file', (tester) async {
    await open(tester, testArchive(confirmRequested: true));

    await tapText(tester, _l10n.outcomeReject);
    await tapText(tester, _l10n.outcomeRejectAndReprint);

    expect(repo.sent.single.verdict, PrintVerdict.reject);
    final form = tester.widget<QueueEditScreen>(find.byType(QueueEditScreen));
    expect(form.item.archiveId, 1);
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
    return (archive: archive, applied: applied);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}
