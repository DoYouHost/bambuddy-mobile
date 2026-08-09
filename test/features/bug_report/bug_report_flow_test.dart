import 'dart:async';
import 'dart:io';

import 'package:bambuddy_mobile/core/diagnostics/diagnostic_recorder.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_event.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_store.dart';
import 'package:app_report_client/app_report_client.dart';
import 'package:bambuddy_mobile/core/diagnostics/report_config.dart';
import 'package:bambuddy_mobile/core/diagnostics/session_facts.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/features/bug_report/bug_report_controller.dart';
import 'package:bambuddy_mobile/features/bug_report/bug_report_screen.dart';
import 'package:bambuddy_mobile/features/bug_report/log_export.dart';
import 'package:bambuddy_mobile/features/bug_report/recording_banner.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

void main() {
  late SharedPreferences prefs;

  const facts = SessionFacts(
    app: '0.11.2+1102',
    flavor: 'mobile',
    os: 'Android 15',
    locale: 'pl-PL',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  /// Memory-only recorder: no package-info channel, no files on disk. The facts
  /// are overridden at their own provider as well, because a change or feature
  /// request reads them straight from there — there is no recording to carry
  /// them.
  List<Override> overrides([List<Override> extra = const []]) => [
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionFactsProvider.overrideWithValue(() async => facts),
        diagnosticRecorderProvider.overrideWith(
          (ref) => DiagnosticRecorder(
            settings: ref.watch(settingsRepositoryProvider),
            loadFacts: () async => facts,
            resolveDirectory: () async => null,
          ),
        ),
        ...extra,
      ];

  Future<ProviderContainer> pumpScreen(WidgetTester tester) async {
    final container = ProviderContainer(overrides: overrides());
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: plApp(const BugReportScreen()),
      ),
    );
    return container;
  }

  /// Scrolls the idle screen down to its action button.
  ///
  /// Both kinds put one under a consent list taller than a test viewport, and a
  /// lazy list does not build what it has not scrolled to. Deliberately below
  /// the fold rather than above it: the list is what the user is agreeing to by
  /// pressing the button.
  Future<void> scrollToActions(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
  }

  testWidgets('opens on the explanation, not on a running recording',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Jak to działa'), findsOneWidget);
    await scrollToActions(tester);
    expect(find.text('Rozpocznij nagrywanie'), findsOneWidget);
    expect(DiagnosticRecorder.isRecording, isFalse);
  });

  testWidgets('says what the log will contain, background service included',
      (tester) async {
    // The screen used to list what was *not* wired up yet. Now that the service
    // and its notification decisions are in the log, saying so is the point —
    // this is what the user agrees to before anything is recorded, and it is a
    // list rather than a paragraph because a consent notice nobody reads is
    // worse consent than four lines somebody skims.
    await pumpScreen(tester);

    expect(find.textContaining('usługa w tle'), findsOneWidget);
    // Both halves of the promise: what is kept, and what never goes in.
    expect(find.text('Klucz API ani hasło'), findsOneWidget);
    expect(find.text('Tekst, który wpisujesz'), findsOneWidget);
    expect(find.textContaining('zanim opuści telefon'), findsOneWidget);
  });

  testWidgets('the three steps replace the paragraph that described them',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Włącz nagrywanie'), findsOneWidget);
    expect(find.text('Odtwórz problem'), findsOneWidget);
    expect(find.text('Wróć tutaj i zakończ'), findsOneWidget);
  });

  /// Gives real file I/O already in flight the real event loop it needs, then
  /// rebuilds on the result.
  ///
  /// This screen writes to disk before anything goes out — the outbox, and the
  /// salvaged session file — and real file I/O does not complete under the fake
  /// clock a widget test runs on, only inside [WidgetTester.runAsync].
  ///
  /// [until] is polled rather than waiting a fixed slice of real time: any
  /// constant short enough to keep the suite quick is also short enough to lose
  /// the race on a loaded machine, where the failure then reads as a send that
  /// never happened or a file that was never deleted. The deadline only bounds a
  /// condition that never comes true — the assertions after the call are what
  /// report that.
  Future<void> settleAsyncUntil(
    WidgetTester tester,
    Future<bool> Function() until,
  ) async {
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!await until() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
  }

  /// Taps and lets the disk work the tap starts actually run.
  ///
  /// Only for taps whose work is pure I/O. A tap answering an awaited dialog
  /// needs [WidgetTester.pumpAndSettle] first — popping that route is driven by
  /// frames, which never come inside [WidgetTester.runAsync] — so the work there
  /// has not even begun while this would be polling for it.
  Future<void> tapAndSettleAsync(
    WidgetTester tester,
    Finder target, {
    required Future<bool> Function() until,
  }) async {
    await tester.runAsync(() => tester.tap(target));
    await settleAsyncUntil(tester, until);
  }

  /// Mounted on a router, because starting a recording navigates away.
  /// [withProfile] decides where "back to the user" is: a configured app has a
  /// dashboard, a fresh one only has setup.
  Future<ProviderContainer> pumpRouted(
    WidgetTester tester, {
    bool withProfile = true,
    List<Override> extra = const [],
  }) async {
    if (withProfile) {
      await SettingsRepository(prefs).saveProfile(
        const ServerProfile(baseUrl: 'https://printer.example', authMode: AuthMode.apiKey),
      );
    }
    final container = ProviderContainer(overrides: overrides(extra));
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: bugReportRoute,
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('dashboard')),
        ),
        GoRoute(
          path: '/setup',
          builder: (_, _) => const Scaffold(body: Text('setup')),
        ),
        GoRoute(path: bugReportRoute, builder: (_, _) => const BugReportScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          locale: const Locale('pl'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    return container;
  }

  testWidgets('starting hands the app straight back to the user',
      (tester) async {
    final container = await pumpRouted(tester);

    await scrollToActions(tester);
    await tester.tap(find.text('Rozpocznij nagrywanie'));
    await tester.pumpAndSettle();

    // The bug is reproduced on the dashboard, so that is where the user is put.
    expect(find.text('dashboard'), findsOneWidget);
    expect(find.text('Rozpocznij nagrywanie'), findsNothing);
    expect(DiagnosticRecorder.isRecording, isTrue);

    await container.read(bugReportProvider.notifier).discard();
  });

  testWidgets('a recording can start before the server is set up',
      (tester) async {
    // The setup screen is exactly where the app can be broken enough to report,
    // and there is no dashboard to go back to yet.
    final container = await pumpRouted(tester, withProfile: false);

    await scrollToActions(tester);
    await tester.tap(find.text('Rozpocznij nagrywanie'));
    await tester.pumpAndSettle();

    expect(find.text('setup'), findsOneWidget);
    expect(DiagnosticRecorder.isRecording, isTrue);

    await container.read(bugReportProvider.notifier).discard();
  });

  testWidgets('coming back mid-recording shows the recording view',
      (tester) async {
    final container = await pumpScreen(tester);

    await container.read(bugReportProvider.notifier).start();
    await tester.pumpAndSettle();

    expect(find.text('Nagrywanie trwa'), findsOneWidget);
    expect(container.read(bugReportProvider).isRecording, isTrue);

    await container.read(bugReportProvider.notifier).discard();
  });

  testWidgets('marking a moment records a marker', (tester) async {
    final container = await pumpScreen(tester);
    await container.read(bugReportProvider.notifier).start();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Oznacz moment'));
    await tester.pumpAndSettle();

    expect(find.text('Moment oznaczony'), findsOneWidget);

    await container.read(bugReportProvider.notifier).stop();
    expect(container.read(bugReportProvider).log, contains('user_marker'));
  });

  testWidgets('review lists the records and the summary', (tester) async {
    final container = await pumpScreen(tester);
    await container.read(bugReportProvider.notifier).start();
    await tester.pumpAndSettle();

    DiagnosticRecorder.active?.add(
      LogSource.http,
      'response',
      lvl: LogLevel.warn,
      fields: const {'status': 502},
    );
    await container.read(bugReportProvider.notifier).stop();
    await tester.pumpAndSettle();

    expect(find.text('Przejrzyj przed wysłaniem'), findsOneWidget);
    expect(find.textContaining('rekordów'), findsOneWidget);
    expect(find.textContaining('http · response'), findsOneWidget);
    expect(find.textContaining('status=502'), findsOneWidget);
  });

  group('a record too long to skim', () {
    /// The detail of the one record whose text is [needle].
    Text detailOf(WidgetTester tester, String needle) => tester.widget<Text>(
          find.textContaining(needle),
        );

    Future<ProviderContainer> pumpWithLongRecord(WidgetTester tester) async {
      final container = await pumpScreen(tester);
      await container.read(bugReportProvider.notifier).start();
      await tester.pumpAndSettle();
      // What a sampled response body looks like in this list: one record, forty
      // lines, and the tap that caused it pushed off the screen.
      DiagnosticRecorder.active?.add(
        LogSource.http,
        'response',
        fields: {
          'path': '/api/v1/queue/',
          'first': {for (var i = 0; i < 30; i++) 'field_$i': 'value_$i'},
        },
      );
      DiagnosticRecorder.active?.add(
        LogSource.ui,
        'tap',
        fields: const {'id': 'nav.queue'},
      );
      await container.read(bugReportProvider.notifier).stop();
      await tester.pumpAndSettle();
      // The list opens on the review header and the destination choice, so the
      // records sit below the fold — and a lazy list has not laid them out yet,
      // while the clamp is measured during layout. Scrolled to, as a reader does.
      await tester.scrollUntilVisible(find.textContaining('field_0'), 200);
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('is clamped, and says it has more with a chevron',
        (tester) async {
      await pumpWithLongRecord(tester);

      expect(detailOf(tester, 'field_0').maxLines, 2);
      // Exactly one chevron: the short record next to it fits inside the clamp,
      // so it is already whole and has nothing to open.
      expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
      expect(find.textContaining('nav.queue'), findsOneWidget);
    });

    testWidgets('opens on a tap and closes again', (tester) async {
      await pumpWithLongRecord(tester);

      await tester.tap(find.textContaining('field_0'));
      await tester.pumpAndSettle();

      expect(detailOf(tester, 'field_0').maxLines, isNull);
      expect(find.byIcon(Icons.expand_less_rounded), findsOneWidget);

      await tester.tap(find.textContaining('field_0'));
      await tester.pumpAndSettle();

      expect(detailOf(tester, 'field_0').maxLines, 2);
      expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
    });
  });

  testWidgets('the raw log is one tap away and holds the header',
      (tester) async {
    final container = await pumpScreen(tester);
    await container.read(bugReportProvider.notifier).start();
    await tester.pumpAndSettle();
    await container.read(bugReportProvider.notifier).stop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pokaż surowy log'));
    await tester.pumpAndSettle();

    expect(find.textContaining('"app":"0.11.2+1102"'), findsOneWidget);
  });

  testWidgets('discarding asks first, then returns to the start',
      (tester) async {
    final container = await pumpScreen(tester);
    await container.read(bugReportProvider.notifier).start();
    await tester.pumpAndSettle();
    await container.read(bugReportProvider.notifier).stop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Odrzuć'));
    await tester.pumpAndSettle();
    expect(find.text('Odrzucić to nagranie?'), findsOneWidget);

    // Confirm — the dialog's button carries the same label as the one that
    // opened it, so target the one inside the dialog.
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Odrzuć'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Jak to działa'), findsOneWidget);
    expect(container.read(bugReportProvider).log, isNull);
  });

  group('handing the log over', () {
    /// A finished recording sitting in review, mounted on the router — every
    /// way out of this screen ends on the dashboard. [padding] adds records of
    /// the maximum length a single field survives at (the redactor clips at
    /// 2000 chars), which is how a real session grows to hundreds of kilobytes.
    Future<ProviderContainer> pumpReview(
      WidgetTester tester, {
      List<Override> extra = const [],
      int padding = 0,
    }) async {
      final container = await pumpRouted(tester, extra: extra);
      await container.read(bugReportProvider.notifier).start();
      for (var i = 0; i < padding; i++) {
        DiagnosticRecorder.active?.add(
          LogSource.app,
          'noise',
          fields: {'pad': 'x' * 2000},
        );
      }
      await container.read(bugReportProvider.notifier).stop();
      await tester.pumpAndSettle();
      return container;
    }

    /// Answers for the system save dialog and records what it was handed.
    Override fakeSaver(
      LogSaveResult result, {
      void Function(String fileName, String log)? onCall,
    }) =>
        logFileSaverProvider.overrideWithValue((
          {required String fileName,
          required String log,
          String? dialogTitle}) async {
          onCall?.call(fileName, log);
          return result;
        });

    testWidgets('the clipboard is not one of the ways out', (tester) async {
      // Copying was there and was taken out: a log of this size janks the whole
      // phone through the clipboard, and lands in the keyboard's clip history
      // on the way. Selecting a fragment in the raw log is what is left.
      await pumpReview(tester);

      expect(find.textContaining('Kopiuj'), findsNothing);
      // The choice above the log, and the button that acts on it.
      expect(find.text('Zapisz do pliku'), findsOneWidget);
      expect(find.text('Zapisz'), findsOneWidget);
    });

    testWidgets('saving it names a text file and then cleans up',
        (tester) async {
      String? name;
      String? written;
      final container = await pumpReview(tester, extra: [
        fakeSaver(
          LogSaveResult.saved,
          onCall: (fileName, log) {
            name = fileName;
            written = log;
          },
        ),
      ]);

      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();

      expect(name, startsWith('bambuddy-log-'));
      expect(name, endsWith('.txt'));
      // The whole session, exactly as reviewed — header included.
      expect(written, contains('"app":"0.11.2+1102"'));
      expect(written, contains('recording_stopped'));
      expect(find.text('Log zapisany do pliku'), findsOneWidget);
      expect(find.text('dashboard'), findsOneWidget);
      expect(container.read(bugReportProvider).log, isNull);
    });

    /// The relay, faked. Counts challenges because *when* one is asked for is
    /// the design decision this screen encodes.
    Override fakeRelay(_FakeRelay relay) =>
        relayClientProvider.overrideWithValue(relay);

    Override outboxIn(Directory root) =>
        reportOutboxProvider.overrideWithValue(ReportOutbox(root: root));

    testWidgets('opens on keeping the log, not on publishing it',
        (tester) async {
      final relay = _FakeRelay();
      await pumpReview(tester, extra: [fakeRelay(relay)]);

      // The default cannot be the one that posts to a public repository: the
      // action offered is the save, and there is nothing to describe.
      expect(find.text('Zapisz'), findsOneWidget);
      expect(find.text('Co poszło nie tak?'), findsNothing);
      // And nothing has been asked of the relay: the user has not decided yet,
      // and a challenge is charged for when it is handed out.
      expect(relay.challenges, 0);
    });

    testWidgets('choosing GitHub asks for the challenge there and then',
        (tester) async {
      final relay = _FakeRelay(issued: _ticket());
      await pumpReview(tester, extra: [fakeRelay(relay)]);

      await tester.tap(find.text('Zgłoś na GitHubie'));
      await tester.pumpAndSettle();

      // The wait starts now, while the description is still being written —
      // which is the only reason the wait is tolerable.
      expect(relay.challenges, 1);
      expect(find.text('Co poszło nie tak?'), findsOneWidget);
      expect(find.text('Zgłoś'), findsOneWidget);
    });

    testWidgets('flipping the destination does not buy a second challenge',
        (tester) async {
      final relay = _FakeRelay(issued: _ticket());
      await pumpReview(tester, extra: [fakeRelay(relay)]);

      // Somebody reading the warning, backing out, and deciding to report after
      // all. Each extra challenge would double their wait — 25 s, 50 s, 100 s —
      // for a decision they were entitled to change.
      await tester.tap(find.text('Zgłoś na GitHubie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zapisz do pliku'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zgłoś na GitHubie'));
      await tester.pumpAndSettle();

      expect(relay.challenges, 1);
    });

    testWidgets('discarding calls off a report that is still queued',
        (tester) async {
      final root = Directory.systemTemp.createTempSync('outbox');
      addTearDown(() => root.deleteSync(recursive: true));
      final outbox = ReportOutbox(root: root);
      final relay = _FakeRelay(issued: _ticket(wait: const Duration(minutes: 5)));
      final container =
          await pumpReview(tester, extra: [fakeRelay(relay), outboxIn(root)]);

      await tester.tap(find.text('Zgłoś na GitHubie'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'jednak nie chcę tego');
      // Waited on by the phase, not by the outbox: the report is on disk before
      // the wait is announced, so a file-shaped condition lets the dialog below
      // be built while the send still looks idle — and it then offers the wrong
      // warning.
      await tapAndSettleAsync(
        tester,
        find.text('Zgłoś'),
        until: () async =>
            container.read(bugReportProvider).send.phase == SendPhase.waiting,
      );

      await tester.tap(find.text('Odrzuć'));
      await tester.pumpAndSettle();
      // The dialog has to admit that this cancels the send, not just delete a file.
      expect(find.textContaining('wysyłka anulowana'), findsOneWidget);
      // Confirming is answered by an awaited dialog, so the discard only starts
      // once the pop has been pumped — and only then is there disk work to wait
      // for.
      await tester.tap(find.text('Odrzuć').last);
      await tester.pumpAndSettle();
      await settleAsyncUntil(tester, () async => await outbox.peek() == null);

      // Nothing left to send: the outbox keeps its own copy of the log, so
      // deleting the recording alone would have published it minutes later.
      final queued = await tester.runAsync(outbox.peek);
      expect(queued, isNull);
      expect(relay.sends, 0);
      expect(container.read(bugReportProvider).log, isNull);
    });

    testWidgets('refuses to send an issue with no description', (tester) async {
      final root = Directory.systemTemp.createTempSync('outbox');
      addTearDown(() => root.deleteSync(recursive: true));
      final relay = _FakeRelay(issued: _ticket());
      await pumpReview(tester, extra: [fakeRelay(relay), outboxIn(root)]);

      await tester.tap(find.text('Zgłoś na GitHubie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zgłoś'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Napisz, co poszło nie tak'), findsOneWidget);
      // A log nobody explained is nearly unusable, so nothing left the phone.
      expect(relay.sends, 0);
    });

    testWidgets('sends the issue and offers the link back', (tester) async {
      final root = Directory.systemTemp.createTempSync('outbox');
      addTearDown(() => root.deleteSync(recursive: true));
      final relay = _FakeRelay(issued: _ticket());
      final container =
          await pumpReview(tester, extra: [fakeRelay(relay), outboxIn(root)]);

      await tester.tap(find.text('Zgłoś na GitHubie'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'kolejka pusta po wznowieniu',
      );
      // The relay's own counter goes up inside the call, one step ahead of the
      // state the screen shows the link from.
      await tapAndSettleAsync(
        tester,
        find.text('Zgłoś'),
        until: () async =>
            container.read(bugReportProvider).send.phase == SendPhase.sent,
      );

      expect(relay.sends, 1);
      expect(relay.lastDescription, 'kolejka pusta po wznowieniu');
      // The envelope comes off the log, so the header travels with it.
      expect(relay.lastHeader?['app'], '0.11.2+1102');
      expect(relay.lastSchema, 1);
      // The URL is the one thing that cannot be recovered once this closes.
      expect(find.text('Otwórz zgłoszenie'), findsOneWidget);
    });

    testWidgets('a ticket that is not due yet queues instead of failing',
        (tester) async {
      final root = Directory.systemTemp.createTempSync('outbox');
      addTearDown(() => root.deleteSync(recursive: true));
      final outbox = ReportOutbox(root: root);
      final relay = _FakeRelay(issued: _ticket(wait: const Duration(minutes: 5)));
      final container =
          await pumpReview(tester, extra: [fakeRelay(relay), outboxIn(root)]);

      await tester.tap(find.text('Zgłoś na GitHubie'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'coś się zepsuło');
      // The countdown and the dead text field are both built off the phase, not
      // off the file.
      await tapAndSettleAsync(
        tester,
        find.text('Zgłoś'),
        until: () async =>
            container.read(bugReportProvider).send.phase == SendPhase.waiting,
      );

      expect(relay.sends, 0);
      // m:ss, not a bare second count — 5 minutes reads as 4:5x by the time the
      // first tick lands.
      expect(find.textContaining(RegExp(r'Wysyłka za \d+:\d\d')), findsOneWidget);
      // The queued copy is what gets sent, so the field must stop pretending
      // that carrying on typing changes anything.
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      // Queued to disk, so closing the screen does not lose it.
      final queued = await tester.runAsync(outbox.peek);
      expect(queued, isNotNull);
    });

    testWidgets('backing out of the picker keeps the report', (tester) async {
      final container = await pumpReview(
        tester,
        extra: [fakeSaver(LogSaveResult.cancelled)],
      );

      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();

      expect(find.text('Przejrzyj przed wysłaniem'), findsOneWidget);
      expect(find.text('Log zapisany do pliku'), findsNothing);
      expect(container.read(bugReportProvider).log, isNotNull);
    });

    testWidgets('a save that fails says so and keeps the report',
        (tester) async {
      final container = await pumpReview(
        tester,
        extra: [fakeSaver(LogSaveResult.failed)],
      );

      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();

      expect(find.text('Nie udało się zapisać loga.'), findsOneWidget);
      expect(find.text('Przejrzyj przed wysłaniem'), findsOneWidget);
      expect(container.read(bugReportProvider).log, isNotNull);
    });

    testWidgets('a long session goes out whole, size being the file\'s problem',
        (tester) async {
      // ~300k characters — the size that made the clipboard unusable. The file
      // takes it in one piece, which is the whole reason it is the only way out.
      String? written;
      final container = await pumpReview(tester, padding: 150, extra: [
        fakeSaver(LogSaveResult.saved, onCall: (_, log) => written = log),
      ]);
      final recorded = container.read(bugReportProvider).log!;
      expect(recorded.length, greaterThan(256 * 1024));

      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();

      expect(written, recorded);
      expect(find.text('dashboard'), findsOneWidget);
      expect(container.read(bugReportProvider).log, isNull);
    });

    testWidgets('the raw view shows a window onto a long session, and says so',
        (tester) async {
      // Laying out 300k characters of `SelectableText` on the frame the user
      // taps "show raw log" is what this window exists to avoid.
      final container = await pumpReview(tester, padding: 150);
      final recorded = container.read(bugReportProvider).log!;

      await tester.tap(find.text('Pokaż surowy log'));
      await tester.pumpAndSettle();

      expect(find.textContaining('nie są tu pokazane'), findsOneWidget);
      final shown = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .single
          .data!;
      expect(shown.length, lessThan(recorded.length));
      expect(shown, startsWith('{"v":1,'),
          reason: 'the header stays, whatever gets clipped');
      // The end of the session is what the window keeps.
      expect(shown, endsWith(recorded.substring(recorded.length - 200)));
    });
  });

  testWidgets('a session id left over from a crash does not fake a recording',
      (tester) async {
    SharedPreferences.setMockInitialValues({'diagnostics_session': 'abc123'});
    prefs = await SharedPreferences.getInstance();

    final container = await pumpScreen(tester);

    expect(container.read(bugReportProvider).isRecording, isFalse);
    expect(find.text('Jak to działa'), findsOneWidget);
    // Cleared, or the background isolate would keep writing to a session
    // nobody is ever going to send.
    expect(
      container.read(settingsRepositoryProvider).loadDiagnosticsSession(),
      isNull,
    );
  });

  group('after a crash', () {
    late Directory dir;

    const session = 'deadbeefdeadbeefdeadbeefdeadbeef';
    const header = '{"v":1,"ts":"2026-07-26T12:00:00.000Z","session":"$session",'
        '"stream":"ui","app":"0.11.2+1102","flavor":"mobile"}';

    setUp(() {
      dir = Directory.systemTemp.createTempSync('bambuddy_recover');
      addTearDown(() => dir.deleteSync(recursive: true));
    });

    File sessionFile() => File('${dir.path}/session-$session.jsonl');

    /// What a process killed mid-recording leaves behind: the flag still in
    /// prefs and whatever the mirror had already flushed to disk.
    ///
    /// [recovers] says whether this is a log the screen will offer back, which
    /// decides what the pump can wait for.
    Future<ProviderContainer> pumpAfterCrash(
      WidgetTester tester, {
      required String log,
      bool recovers = true,
    }) async {
      await SettingsRepository(prefs).saveDiagnosticsSession(session);
      sessionFile().writeAsStringSync(log);

      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        diagnosticRecorderProvider.overrideWith(
          (ref) => DiagnosticRecorder(
            settings: ref.watch(settingsRepositoryProvider),
            loadFacts: () async => facts,
            resolveDirectory: () async => dir,
          ),
        ),
      ]);
      addTearDown(container.dispose);
      // Pumped inside `runAsync`: the salvaged log is read off disk, and real
      // file IO only completes on the real event loop, which the fake one a
      // widget test runs on never gets to.
      await tester.runAsync(() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: plApp(const BugReportScreen()),
          ),
        );
      });
      if (recovers) {
        // The salvaged log arriving is what the card is built from, so waiting
        // for anything less than that is what made this flake: the tap that
        // follows found no card to press.
        await settleAsyncUntil(
          tester,
          () async => container.read(bugReportProvider).recovered != null,
        );
      } else {
        // A log the screen stays quiet about — there is no arrival to wait for.
        // A slice of real time is enough here: too short a wait can only ever
        // pass, and a card that stopped appearing is what the two tests above
        // would catch.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pumpAndSettle();
      }
      return container;
    }

    testWidgets('offers the log that survived', (tester) async {
      await pumpAfterCrash(
        tester,
        log: '$header\n{"t":5,"src":"app","evt":"user_marker"}\n',
      );

      expect(find.text('Nagranie przetrwało awarię'), findsOneWidget);

      await tester.tap(find.text('Pokaż'));
      await tester.pumpAndSettle();

      // Reviewed like any other recording, raw log included.
      expect(find.text('Przejrzyj przed wysłaniem'), findsOneWidget);
      await tester.tap(find.text('Pokaż surowy log'));
      await tester.pumpAndSettle();
      expect(find.textContaining('user_marker'), findsOneWidget);
    });

    testWidgets('throwing it away takes the file with it', (tester) async {
      final container = await pumpAfterCrash(
        tester,
        log: '$header\n{"t":5,"src":"app","evt":"user_marker"}\n',
      );

      // Deleting the file is real IO again, so the tap that starts it has to
      // run where real IO completes — and be waited on until it has. Waited on
      // by the state and not by the file: the drop clears the offer only once
      // the delete is through, so the file going is the earlier of the two, and
      // stopping there cuts the rebuild off.
      await tapAndSettleAsync(
        tester,
        find.text('Odrzuć'),
        until: () async => container.read(bugReportProvider).recovered == null,
      );

      expect(find.text('Nagranie przetrwało awarię'), findsNothing);
      expect(sessionFile().existsSync(), isFalse);
    });

    testWidgets('finishing something else does not take the offer away',
        (tester) async {
      final container = await pumpAfterCrash(
        tester,
        log: '$header\n{"t":5,"src":"app","evt":"user_marker"}\n',
      );

      // What sending a change or feature request from this screen ends on. The
      // salvaged log is looked for once per process, in `build`, so a reset that
      // dropped it would strand the files with nothing left to open or delete
      // them for the rest of the session.
      container.read(bugReportProvider.notifier).reset();
      await tester.pumpAndSettle();

      expect(container.read(bugReportProvider).recovered, isNotNull);
      expect(find.text('Nagranie przetrwało awarię'), findsOneWidget);
    });

    testWidgets('says nothing about a file with no records', (tester) async {
      // The crash beat the first record. Asking the user to decide about an
      // empty file is worse than staying quiet.
      await pumpAfterCrash(tester, log: '$header\n', recovers: false);

      expect(find.text('Nagranie przetrwało awarię'), findsNothing);
      expect(find.text('Jak to działa'), findsOneWidget);
    });
  });

  group('recording bar', () {
    /// Mounted exactly as the app does it — through `MaterialApp.builder`,
    /// which sits ABOVE the Navigator. Wrapping it in `home:` instead would
    /// hand the bar an Overlay it does not have in production, and hide a
    /// whole class of crash (anything needing one, e.g. a tooltip).
    Future<ProviderContainer> pumpBanner(
      WidgetTester tester, {
      Widget home = const Scaffold(body: Text('ekran')),
    }) async {
      final container = ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('pl'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => RecordingBannerScaffold(
              child: child ?? const SizedBox.shrink(),
            ),
            home: home,
          ),
        ),
      );
      return container;
    }

    /// Runs [body] with a recording in progress and discards it afterwards.
    /// The discard cannot go into `addTearDown`: the recording attaches an
    /// interaction probe, whose `SemanticsHandle` the framework checks for at
    /// the end of the test body — before any teardown runs.
    Future<void> whileRecording(
      WidgetTester tester,
      Future<void> Function(ProviderContainer container) body, {
      Widget home = const Scaffold(body: Text('ekran')),
    }) async {
      final container = await pumpBanner(tester, home: home);
      await container.read(bugReportProvider.notifier).start();
      await tester.pumpAndSettle();
      try {
        await body(container);
      } finally {
        await container.read(bugReportProvider.notifier).discard();
        await tester.pumpAndSettle();
      }
    }

    /// What the bar's clock reads at the start: elapsed against the ceiling the
    /// recording will stop itself at.
    final clockText = '0:00 / ${formatElapsed(recordingLimit)}';

    /// The bar's own box — the innermost Material around the clock, in both the
    /// expanded and the collapsed form.
    Finder barBox() => find
        .ancestor(of: find.text(clockText), matching: find.byType(Material))
        .first;

    testWidgets('stays out of the way until something is recording',
        (tester) async {
      await pumpBanner(tester);

      expect(find.text('Zakończ'), findsNothing);
      expect(find.byIcon(Icons.drag_indicator), findsNothing);
    });

    testWidgets('ends itself at the limit and says so', (tester) async {
      // Nobody presses finish here — the recording runs out while the user is
      // on another screen, so the bar going away has to be explained.
      final container = await pumpBanner(tester);
      await container.read(bugReportProvider.notifier).start();
      await tester.pumpAndSettle();

      await tester.pump(recordingLimit);
      await tester.pumpAndSettle();

      expect(container.read(bugReportProvider).isRecording, isFalse);
      expect(container.read(bugReportProvider).autoStopped, isTrue);
      expect(find.text('Zakończ'), findsNothing);
      // Derived, not spelled out: the limit is one constant and a test that
      // hardcodes its value turns a deliberate change into a false alarm.
      expect(
        find.textContaining('minął limit ${recordingLimit.inMinutes} min'),
        findsOneWidget,
      );

      await container.read(bugReportProvider.notifier).discard();
      await tester.pumpAndSettle();
    });

    testWidgets('shows over whatever screen the user is on', (tester) async {
      await whileRecording(tester, (_) async {
        expect(find.text('Zakończ'), findsOneWidget);
        expect(find.text('ekran'), findsOneWidget);
        expect(find.text(clockText), findsOneWidget);
      });
    });

    testWidgets('lets taps through to the screen underneath', (tester) async {
      var taps = 0;
      await whileRecording(
        tester,
        home: Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('kliknij'),
            ),
          ),
        ),
        (_) async {
          // The layer covers the whole screen; only the bar itself may absorb
          // pointers, or recording would block using the app.
          await tester.tap(find.text('kliknij'));
          await tester.pumpAndSettle();

          expect(taps, 1);
        },
      );
    });

    testWidgets('drags out of the way by the handle', (tester) async {
      await whileRecording(tester, (_) async {
        final before = tester.getTopLeft(barBox());
        await tester.drag(
          find.byIcon(Icons.drag_indicator),
          const Offset(0, 240),
        );
        await tester.pumpAndSettle();

        expect(tester.getTopLeft(barBox()).dy - before.dy, closeTo(240, 1));
      });
    });

    testWidgets('cannot be dragged off the screen', (tester) async {
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;

      await whileRecording(tester, (_) async {
        await tester.drag(
          find.byIcon(Icons.drag_indicator),
          const Offset(4000, 4000),
        );
        await tester.pumpAndSettle();

        final bar = tester.getRect(barBox());
        expect(bar.right, lessThanOrEqualTo(screen.width));
        expect(bar.bottom, lessThanOrEqualTo(screen.height));
      });
    });

    testWidgets('collapses to a pill and comes back', (tester) async {
      await whileRecording(tester, (_) async {
        await tester.tap(find.byIcon(Icons.close_fullscreen_rounded));
        await tester.pumpAndSettle();

        // Clock stays — it is the proof something is still being recorded.
        expect(find.text(clockText), findsOneWidget);
        expect(find.text('Zakończ'), findsNothing);
        expect(find.byIcon(Icons.bookmark_add_outlined), findsNothing);

        await tester.tap(find.text(clockText));
        await tester.pumpAndSettle();

        expect(find.text('Zakończ'), findsOneWidget);
      });
    });

    testWidgets('keeps the dragged position when it collapses', (tester) async {
      await whileRecording(tester, (_) async {
        await tester.drag(
          find.byIcon(Icons.drag_indicator),
          const Offset(0, 200),
        );
        await tester.pumpAndSettle();
        final dragged = tester.getTopLeft(barBox());

        await tester.tap(find.byIcon(Icons.close_fullscreen_rounded));
        await tester.pumpAndSettle();

        expect(tester.getTopLeft(barBox()), dragged);
      });
    });

    // The clock reads wall time, which `tester.pump` does not advance — the
    // formatting is covered directly instead.
    test('formats the elapsed clock', () {
      expect(formatElapsed(Duration.zero), '0:00');
      expect(formatElapsed(const Duration(seconds: 7)), '0:07');
      expect(formatElapsed(const Duration(seconds: 63)), '1:03');
      expect(formatElapsed(const Duration(minutes: 12, seconds: 5)), '12:05');
    });

    testWidgets('the bar\'s buttons work without an Overlay above them',
        (tester) async {
      final container = await pumpBanner(tester);
      await container.read(bugReportProvider.notifier).start();
      await tester.pumpAndSettle();

      // Regression: an IconButton with `tooltip:` here threw "No Overlay
      // widget found" on a real device, because MaterialApp.builder is above
      // the Navigator.
      await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Moment oznaczony'), findsOneWidget);

      await container.read(bugReportProvider.notifier).discard();
      await tester.pumpAndSettle();
    });

    testWidgets('keeps its own taps and drags out of the log', (tester) async {
      await whileRecording(tester, (container) async {
        await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
        await tester.pumpAndSettle();
        await tester.drag(
          find.byIcon(Icons.drag_indicator),
          const Offset(0, 120),
        );
        await tester.pumpAndSettle();

        await container.read(bugReportProvider.notifier).stop();
        final log = container.read(bugReportProvider).log!;

        // The mark is recorded once, by the recorder itself.
        expect(log, contains('user_marker'));
        expect(log, isNot(contains('"evt":"tap"')));
        expect(log, isNot(contains('"evt":"drag"')));
      });
    });

    testWidgets('disappears once the recording is finished', (tester) async {
      final container = await pumpBanner(tester);
      await container.read(bugReportProvider.notifier).start();
      await tester.pumpAndSettle();

      await container.read(bugReportProvider.notifier).stop();
      await tester.pumpAndSettle();

      expect(find.text('Nagrywanie'), findsNothing);
    });
  });

  group('changes and features', () {
    Future<ProviderContainer> pumpIdle(
      WidgetTester tester, {
      List<Override> extra = const [],
    }) =>
        pumpRouted(tester, extra: extra);

    /// Picks a kind on the screen everything starts from.
    Future<void> choose(WidgetTester tester, String label) async {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    testWidgets('opens on the bug, which is the kind that records',
        (tester) async {
      final relay = _FakeRelay(issued: _ticket());
      await pumpIdle(tester, extra: [relayClientProvider.overrideWithValue(relay)]);

      await scrollToActions(tester);
      expect(find.text('Rozpocznij nagrywanie'), findsOneWidget);
      // No ticket bought for a screen the user has not asked anything of yet.
      expect(relay.challenges, 0);
    });

    testWidgets('a request replaces the recording flow with a form',
        (tester) async {
      final relay = _FakeRelay(issued: _ticket());
      await pumpIdle(tester, extra: [relayClientProvider.overrideWithValue(relay)]);

      await choose(tester, 'Funkcję');

      // Nothing to record, so nothing offers to.
      expect(find.text('Rozpocznij nagrywanie'), findsNothing);
      expect(find.text('Czego brakuje?'), findsOneWidget);
      // The segment is the cheapest thing here to tap out of curiosity, and a
      // challenge is charged for when it is handed out — so looking is free.
      expect(relay.challenges, 0);
    });

    testWidgets('the wait starts on the first word, not on the segment',
        (tester) async {
      final relay = _FakeRelay(issued: _ticket());
      await pumpIdle(tester, extra: [relayClientProvider.overrideWithValue(relay)]);

      await choose(tester, 'Zmianę');
      await tester.enterText(find.byType(TextField), 'p');
      await tester.pumpAndSettle();

      // Somebody typing has decided, and from here the relay's delay runs while
      // they finish the sentence — which is the only reason it is tolerable.
      expect(relay.challenges, 1);
    });

    testWidgets('typing on does not buy a challenge per keystroke',
        (tester) async {
      // The round trip is held open for all four keystrokes: a fast typist on a
      // slow connection. The ticket only lands once the trip is over, so the
      // "already have one" check cannot see it — without the sender joining a
      // trip in flight, every one of these would pay for its own challenge, and
      // each one doubles the user's next wait.
      final gate = Completer<void>();
      final relay = _FakeRelay(issued: _ticket(), gate: gate.future);
      await pumpIdle(tester, extra: [relayClientProvider.overrideWithValue(relay)]);

      await choose(tester, 'Zmianę');
      for (final text in ['p', 'po', 'pow', 'powi']) {
        await tester.enterText(find.byType(TextField), text);
      }
      await tester.pumpAndSettle();

      expect(relay.challenges, 1);

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('the change wording is not the feature wording',
        (tester) async {
      await pumpIdle(tester, extra: [
        relayClientProvider.overrideWithValue(_FakeRelay(issued: _ticket())),
      ]);

      await choose(tester, 'Zmianę');

      expect(find.text('Co powinno się zmienić?'), findsOneWidget);
      expect(find.text('Czego brakuje?'), findsNothing);
    });

    testWidgets('flipping between requests does not buy a second challenge',
        (tester) async {
      final relay = _FakeRelay(issued: _ticket());
      await pumpIdle(tester, extra: [relayClientProvider.overrideWithValue(relay)]);

      await choose(tester, 'Funkcję');
      await tester.enterText(find.byType(TextField), 'niech to robi tamto');
      await tester.pumpAndSettle();
      await choose(tester, 'Zmianę');
      await choose(tester, 'Błąd');
      await choose(tester, 'Funkcję');

      // Same reason as the destination picker: each extra challenge doubles the
      // user's next wait, for a decision they were entitled to change. The text
      // survives the flip, so the second description is the first one.
      expect(relay.challenges, 1);
    });

    testWidgets('refuses to send an empty request', (tester) async {
      final root = Directory.systemTemp.createTempSync('outbox');
      addTearDown(() => root.deleteSync(recursive: true));
      final relay = _FakeRelay(issued: _ticket());
      await pumpIdle(tester, extra: [
        relayClientProvider.overrideWithValue(relay),
        reportOutboxProvider.overrideWithValue(ReportOutbox(root: root)),
      ]);

      await choose(tester, 'Funkcję');
      await scrollToActions(tester);
      await tester.tap(find.text('Zgłoś'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Napisz, o co prosisz'), findsOneWidget);
      expect(relay.sends, 0);
    });

    testWidgets('sends the request with no log and offers the link back',
        (tester) async {
      final root = Directory.systemTemp.createTempSync('outbox');
      addTearDown(() => root.deleteSync(recursive: true));
      final relay = _FakeRelay(issued: _ticket());
      final container = await pumpIdle(tester, extra: [
        relayClientProvider.overrideWithValue(relay),
        reportOutboxProvider.overrideWithValue(ReportOutbox(root: root)),
      ]);

      await choose(tester, 'Funkcję');
      await tester.enterText(
        find.byType(TextField),
        'chciałbym harmonogram wydruków',
      );
      await scrollToActions(tester);
      await tapAndSettleAsync(
        tester,
        find.text('Zgłoś'),
        until: () async =>
            container.read(bugReportProvider).send.phase == SendPhase.sent,
      );

      expect(relay.sends, 1);
      expect(relay.lastKind, ReportKind.feature);
      expect(relay.lastDescription, 'chciałbym harmonogram wydruków');
      // No recording behind it, and the schema says so rather than claiming a
      // log that was never written.
      expect(relay.lastLog, isNull);
      expect(relay.lastSchema, isNull);
      // The versions travel, because "already released" is the one answer a
      // request can get from the phone.
      expect(relay.lastHeader?['app'], '0.11.2+1102');
      expect(relay.lastHeader?.keys, isNot(contains('auth')));
      expect(find.text('Otwórz zgłoszenie'), findsOneWidget);
    });

    testWidgets('a queued request can be called off before it goes',
        (tester) async {
      final root = Directory.systemTemp.createTempSync('outbox');
      addTearDown(() => root.deleteSync(recursive: true));
      final outbox = ReportOutbox(root: root);
      final relay = _FakeRelay(issued: _ticket(wait: const Duration(minutes: 5)));
      final container = await pumpIdle(tester, extra: [
        relayClientProvider.overrideWithValue(relay),
        reportOutboxProvider.overrideWithValue(outbox),
      ]);

      await choose(tester, 'Zmianę');
      await tester.enterText(find.byType(TextField), 'inaczej to ułóż');
      await scrollToActions(tester);
      await tapAndSettleAsync(
        tester,
        find.text('Zgłoś'),
        until: () async =>
            container.read(bugReportProvider).send.phase == SendPhase.waiting,
      );

      // There is no "discard the recording" here to double as a cancel, so the
      // wait needs its own way out.
      expect(find.textContaining(RegExp(r'Wysyłka za \d+:\d\d')), findsOneWidget);
      // Below the fold on a test-sized screen, and a lazy list does not build
      // what it has not scrolled to.
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tapAndSettleAsync(
        tester,
        find.text('Anuluj wysyłanie'),
        until: () async => await outbox.peek() == null,
      );

      expect(relay.sends, 0);
      final queued = await tester.runAsync(outbox.peek);
      expect(queued, isNull);
    });

    testWidgets('switching back to the bug keeps the queued request in sight',
        (tester) async {
      final root = Directory.systemTemp.createTempSync('outbox');
      addTearDown(() => root.deleteSync(recursive: true));
      final outbox = ReportOutbox(root: root);
      final relay = _FakeRelay(issued: _ticket(wait: const Duration(minutes: 5)));
      final container = await pumpIdle(tester, extra: [
        relayClientProvider.overrideWithValue(relay),
        reportOutboxProvider.overrideWithValue(outbox),
      ]);

      await choose(tester, 'Zmianę');
      await tester.enterText(find.byType(TextField), 'inaczej to ułóż');
      await scrollToActions(tester);
      await tapAndSettleAsync(
        tester,
        find.text('Zgłoś'),
        until: () async =>
            container.read(bugReportProvider).send.phase == SendPhase.waiting,
      );

      // Back up to the picker and over to the tab the request is not on. The
      // relay gets it either way, so hiding the countdown here would leave it
      // running invisibly with the only way out a tab away.
      await tester.drag(find.byType(ListView), const Offset(0, 600));
      await tester.pumpAndSettle();
      await choose(tester, 'Błąd');

      expect(find.textContaining(RegExp(r'Wysyłka za \d+:\d\d')), findsOneWidget);
      await tapAndSettleAsync(
        tester,
        find.text('Anuluj wysyłanie'),
        until: () async => await outbox.peek() == null,
      );

      expect(relay.sends, 0);
      expect(await tester.runAsync(outbox.peek), isNull);
    });

    testWidgets('facts it cannot read say so instead of hanging the button',
        (tester) async {
      final root = Directory.systemTemp.createTempSync('outbox');
      addTearDown(() => root.deleteSync(recursive: true));
      final relay = _FakeRelay(issued: _ticket());
      // Reading the facts is a platform channel and a request to the server for
      // its version. Nothing downstream ever sees an attempt that dies here, so
      // without this the tap would leave a live button and a silent screen.
      final container = await pumpIdle(tester, extra: [
        relayClientProvider.overrideWithValue(relay),
        reportOutboxProvider.overrideWithValue(ReportOutbox(root: root)),
        sessionFactsProvider.overrideWithValue(
          () => Future.error(StateError('no package info')),
        ),
      ]);

      await choose(tester, 'Funkcję');
      await tester.enterText(find.byType(TextField), 'coś nowego');
      await scrollToActions(tester);
      await tester.tap(find.text('Zgłoś'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nic nie wysłano'), findsOneWidget);
      expect(relay.sends, 0);
      // Idle, not failed: nothing was handed over, so there is no report for a
      // failure to be about — and the button has to come back for the retry.
      expect(container.read(bugReportProvider).send.phase, SendPhase.idle);
      expect(find.text('Zgłoś'), findsOneWidget);
    });

    testWidgets('a failed request is not told to save a log it never had',
        (tester) async {
      final root = Directory.systemTemp.createTempSync('outbox');
      addTearDown(() => root.deleteSync(recursive: true));
      // No ticket: the relay cannot be reached at all.
      final container = await pumpIdle(tester, extra: [
        relayClientProvider.overrideWithValue(_FakeRelay()),
        reportOutboxProvider.overrideWithValue(ReportOutbox(root: root)),
      ]);

      await choose(tester, 'Funkcję');
      await tester.enterText(find.byType(TextField), 'coś nowego');
      await scrollToActions(tester);
      await tapAndSettleAsync(
        tester,
        find.text('Zgłoś'),
        until: () async =>
            container.read(bugReportProvider).send.phase == SendPhase.failed,
      );

      expect(find.textContaining('Sprawdź połączenie i spróbuj ponownie'),
          findsOneWidget);
      expect(find.textContaining('zapisz log do pliku'), findsNothing);
    });
  });
}

RelayTicket _ticket({Duration wait = Duration.zero}) {
  final now = DateTime.now();
  return RelayTicket(
    ticket: 'signed',
    notBefore: now.add(wait),
    expiresAt: now.add(wait + const Duration(minutes: 30)),
    // Zero bits: the real difficulty is about a second of hashing, which every
    // test using this would otherwise pay.
    challenge: const PowChallenge(seed: 'seed', bits: 0),
  );
}

/// Stands in for the relay. What matters here is not the protocol — the worker's
/// own suite covers that — but *when* this screen talks to it.
class _FakeRelay extends RelayClient {
  _FakeRelay({this.issued, this.gate})
      : super(Dio(), baseUrl: relayBaseUrl);

  final RelayTicket? issued;

  /// Holds the challenge open, for the one test that needs a second call made
  /// while the first is still in flight. Counted before it is awaited, so what
  /// [challenges] reports is attempts rather than answers.
  final Future<void>? gate;

  int challenges = 0;
  int sends = 0;
  String? lastDescription;
  Map<String, Object>? lastHeader;
  int? lastSchema;
  ReportKind? lastKind;
  String? lastLog;

  @override
  Future<RelayTicket> challenge(String installId) async {
    challenges++;
    await gate;
    final next = issued;
    if (next == null) throw const RelayException(RelayFailure.unreachable);
    return next;
  }

  @override
  Future<String> send({
    required String installId,
    required RelayTicket ticket,
    required ReportKind kind,
    required String description,
    required Map<String, Object> header,
    int? logSchema,
    String? log,
  }) async {
    sends++;
    lastDescription = description;
    lastHeader = header;
    lastSchema = logSchema;
    lastKind = kind;
    lastLog = log;
    return 'https://github.example/issues/7';
  }
}
