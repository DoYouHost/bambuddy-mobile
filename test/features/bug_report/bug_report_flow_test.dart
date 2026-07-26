import 'package:bambuddy_mobile/core/diagnostics/diagnostic_recorder.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_event.dart';
import 'package:bambuddy_mobile/core/diagnostics/session_facts.dart';
import 'package:bambuddy_mobile/features/bug_report/bug_report_controller.dart';
import 'package:bambuddy_mobile/features/bug_report/bug_report_screen.dart';
import 'package:bambuddy_mobile/features/bug_report/recording_banner.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
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

  /// Memory-only recorder: no package-info channel, no files on disk.
  List<Override> overrides() => [
        sharedPreferencesProvider.overrideWithValue(prefs),
        diagnosticRecorderProvider.overrideWith(
          (ref) => DiagnosticRecorder(
            settings: ref.watch(settingsRepositoryProvider),
            loadFacts: () async => facts,
            resolveDirectory: () async => null,
          ),
        ),
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

  testWidgets('opens on the explanation, not on a running recording',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Jak to działa'), findsOneWidget);
    expect(find.text('Rozpocznij nagrywanie'), findsOneWidget);
    expect(DiagnosticRecorder.isRecording, isFalse);
  });

  testWidgets('says out loud which sources are not wired up yet',
      (tester) async {
    await pumpScreen(tester);

    expect(find.textContaining('Jeszcze niepodpięte'), findsOneWidget);
  });

  /// Mounted on a router, because starting a recording navigates away.
  Future<ProviderContainer> pumpRouted(WidgetTester tester) async {
    final container = ProviderContainer(overrides: overrides());
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: bugReportRoute,
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('dashboard')),
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

    await tester.tap(find.text('Rozpocznij nagrywanie'));
    await tester.pumpAndSettle();

    // The bug is reproduced on the dashboard, so that is where the user is put.
    expect(find.text('dashboard'), findsOneWidget);
    expect(find.text('Rozpocznij nagrywanie'), findsNothing);
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

    /// The bar's own box — the innermost Material around the clock, in both the
    /// expanded and the collapsed form.
    Finder barBox() => find
        .ancestor(of: find.text('0:00'), matching: find.byType(Material))
        .first;

    testWidgets('stays out of the way until something is recording',
        (tester) async {
      await pumpBanner(tester);

      expect(find.text('Zakończ'), findsNothing);
      expect(find.byIcon(Icons.drag_indicator), findsNothing);
    });

    testWidgets('shows over whatever screen the user is on', (tester) async {
      await whileRecording(tester, (_) async {
        expect(find.text('Zakończ'), findsOneWidget);
        expect(find.text('ekran'), findsOneWidget);
        expect(find.text('0:00'), findsOneWidget);
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
        expect(find.text('0:00'), findsOneWidget);
        expect(find.text('Zakończ'), findsNothing);
        expect(find.byIcon(Icons.bookmark_add_outlined), findsNothing);

        await tester.tap(find.text('0:00'));
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
}
