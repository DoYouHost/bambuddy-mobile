import 'package:bambuddy_mobile/core/diagnostics/diagnostic_recorder.dart';
import 'package:bambuddy_mobile/core/diagnostics/session_facts.dart';
import 'package:bambuddy_mobile/features/bug_report/recording_banner.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;

  const facts = SessionFacts(app: '0.11.2+1102', flavor: 'mobile');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  /// The real app router, with no server profile — the state a fresh install is
  /// in, where every route but setup is redirected away.
  Future<GoRouter> pumpApp(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        diagnosticRecorderProvider.overrideWith(
          (ref) => DiagnosticRecorder(
            settings: ref.watch(settingsRepositoryProvider),
            loadFacts: () async => facts,
            resolveDirectory: () async => null,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
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
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('the bug report is reachable before the server is set up', (
    tester,
  ) async {
    // Without this the redirect bounces every route back to setup, and a broken
    // setup — the report worth having most — could never be recorded.
    final router = await pumpApp(tester);

    router.go(bugReportRoute);
    await tester.pumpAndSettle();

    expect(find.text('Jak to działa'), findsOneWidget);
    expect(router.state.matchedLocation, bugReportRoute);
  });

  testWidgets('the setup screen offers a way in', (tester) async {
    final router = await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.bug_report_outlined));
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, bugReportRoute);
    // The start button sits under the consent list, which is taller than a test
    // viewport, and a lazy list does not build what it has not scrolled to.
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Rozpocznij nagrywanie'), findsOneWidget);
  });
}
