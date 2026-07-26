import 'dart:convert';

import 'package:bambuddy_mobile/core/diagnostics/diagnostic_recorder.dart';
import 'package:bambuddy_mobile/core/diagnostics/navigation_probe.dart';
import 'package:bambuddy_mobile/core/diagnostics/session_facts.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DiagnosticRecorder recorder;

  const facts = SessionFacts(app: '0.11.2+1102', flavor: 'mobile');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    recorder = DiagnosticRecorder(
      settings: SettingsRepository(await SharedPreferences.getInstance()),
      loadFacts: () async => facts,
      resolveDirectory: () async => null,
    );
  });

  tearDown(() => recorder.discard());

  List<Map<String, dynamic>> parse(String jsonl) => [
        for (final line in const LineSplitter().convert(jsonl))
          jsonDecode(line) as Map<String, dynamic>,
      ];

  /// Context of the screen at `/`, for pushing dialogs and sheets over it the
  /// way the app does.
  late BuildContext homeContext;

  Future<GoRouter> pumpRouter(WidgetTester tester, {String at = '/'}) async {
    final probe = NavigationProbe();
    final router = GoRouter(
      initialLocation: at,
      observers: [ModalObserver()],
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) {
            homeContext = context;
            return const Scaffold(body: Text('home'));
          },
        ),
        GoRoute(path: '/queue', builder: (_, _) => const Scaffold()),
        GoRoute(path: '/gcode-viewer', builder: (_, _) => const Scaffold()),
      ],
    );
    probe.watch(router);
    addTearDown(() {
      probe.unwatch();
      router.dispose();
    });
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    return router;
  }

  Future<List<Map<String, dynamic>>> stopAndParse() async =>
      parse(await recorder.stop());

  Iterable<Map<String, dynamic>> only(
    List<Map<String, dynamic>> records,
    String evt,
  ) =>
      records.where((r) => r['evt'] == evt);

  testWidgets('records a screen change from where the user was',
      (tester) async {
    final router = await pumpRouter(tester);
    await recorder.start();

    router.go('/queue');
    await tester.pumpAndSettle();

    final route = only(await stopAndParse(), 'route').last;
    expect(route['src'], 'ui');
    expect(route['from'], '/');
    expect(route['to'], '/queue');
  });

  testWidgets('records a screen pushed on top of another', (tester) async {
    // How nearly every screen in this app is opened. The router's own location
    // stays on the screen below, so this is the case that decides whether the
    // navigation log says anything at all.
    final router = await pumpRouter(tester);
    await recorder.start();

    router.push('/queue');
    await tester.pumpAndSettle();

    final route = only(await stopAndParse(), 'route').last;
    expect(route['from'], '/');
    expect(route['to'], '/queue');
  });

  testWidgets('records going back', (tester) async {
    final router = await pumpRouter(tester);
    router.push('/queue');
    await tester.pumpAndSettle();
    await recorder.start();

    Navigator.of(homeContext).pop();
    await tester.pumpAndSettle();

    final route = only(await stopAndParse(), 'route').last;
    expect(route['from'], '/queue');
    expect(route['to'], '/');
  });

  testWidgets('opens the session with the screen it started on',
      (tester) async {
    await pumpRouter(tester, at: '/queue');
    await recorder.start();

    final route = only(await stopAndParse(), 'route').single;
    expect(route['to'], '/queue');
    // Nothing was left, so there is nothing to come from.
    expect(route.containsKey('from'), isFalse);
  });

  testWidgets('follows the screen while nothing is recording', (tester) async {
    final router = await pumpRouter(tester);

    router.go('/queue');
    await tester.pumpAndSettle();
    await recorder.start();

    expect(only(await stopAndParse(), 'route').single['to'], '/queue');
  });

  testWidgets('carries the screen across a router rebuild', (tester) async {
    // Saving a server profile builds a whole new GoRouter. Without carrying the
    // screen over, the transition that says "setup finally worked" arrives with
    // no `from` — the one record where it matters most.
    await pumpRouter(tester, at: '/queue');
    await recorder.start();

    final probe = NavigationProbe();
    final replacement = GoRouter(
      initialLocation: '/',
      observers: [ModalObserver()],
      routes: [GoRoute(path: '/', builder: (_, _) => const Scaffold())],
    );
    probe.watch(replacement);
    addTearDown(() {
      probe.unwatch();
      replacement.dispose();
    });
    await tester.pumpWidget(MaterialApp.router(routerConfig: replacement));
    await tester.pumpAndSettle();

    final route = only(await stopAndParse(), 'route').last;
    expect(route['from'], '/queue');
    expect(route['to'], '/');
  });

  testWidgets('keeps the query string out of the log', (tester) async {
    final router = await pumpRouter(tester);
    await recorder.start();

    router.push('/gcode-viewer?name=Prototyp%20v3.3mf');
    await tester.pumpAndSettle();

    final log = await recorder.stop();
    expect(only(parse(log), 'route').last['to'], '/gcode-viewer');
    expect(log, isNot(contains('Prototyp')));
  });

  testWidgets('records one line per change, not per push', (tester) async {
    final router = await pumpRouter(tester);
    await recorder.start();

    // A second copy of the same screen on the stack is still that screen; the
    // location does not change, so neither should the log.
    router.push('/queue');
    await tester.pumpAndSettle();
    router.push('/queue');
    await tester.pumpAndSettle();

    final toQueue = only(await stopAndParse(), 'route')
        .where((r) => r['to'] == '/queue');
    expect(toQueue, hasLength(1));
  });

  testWidgets('records a dialog opening and closing', (tester) async {
    await pumpRouter(tester);
    await recorder.start();

    showDialog<void>(
      context: homeContext,
      builder: (_) => const AlertDialog(content: Text('question')),
    );
    await tester.pumpAndSettle();
    Navigator.of(homeContext, rootNavigator: true).pop();
    await tester.pumpAndSettle();

    final records = await stopAndParse();
    expect(only(records, 'open').single['kind'], 'dialog');
    expect(only(records, 'close').single['kind'], 'dialog');
  });

  testWidgets('records a bottom sheet as a sheet', (tester) async {
    await pumpRouter(tester);
    await recorder.start();

    showModalBottomSheet<void>(
      context: homeContext,
      builder: (_) => const SizedBox(height: 120),
    );
    await tester.pumpAndSettle();

    expect(only(await stopAndParse(), 'open').single['kind'], 'sheet');
  });

  testWidgets("leaves the router's own screens to the location hook",
      (tester) async {
    final router = await pumpRouter(tester);
    await recorder.start();

    router.go('/queue');
    await tester.pumpAndSettle();

    // One `route` record, and no `open` for the page behind it — go_router
    // builds screens as pages, which the observer skips.
    final records = await stopAndParse();
    expect(only(records, 'route'), hasLength(2));
    expect(only(records, 'open'), isEmpty);
  });

  testWidgets('records a sheet opened inside a shell tab', (tester) async {
    // The tab has its own Navigator, and `showModalBottomSheet` uses the
    // nearest one — so the probe has to be an observer on the branch as well.
    final probe = NavigationProbe();
    late BuildContext tabContext;
    final router = GoRouter(
      observers: [ModalObserver()],
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => shell,
          branches: [
            StatefulShellBranch(
              observers: [ModalObserver()],
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, _) {
                    tabContext = context;
                    return const Scaffold(body: Text('tab'));
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
    probe.watch(router);
    addTearDown(() {
      probe.unwatch();
      router.dispose();
    });
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await recorder.start();

    showModalBottomSheet<void>(
      context: tabContext,
      builder: (_) => const SizedBox(height: 120),
    );
    await tester.pumpAndSettle();

    expect(only(await stopAndParse(), 'open').single['kind'], 'sheet');
  });

  test('the app router reports every tab navigator to the probe', () async {
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider
          .overrideWithValue(await SharedPreferences.getInstance()),
    ]);
    addTearDown(container.dispose);

    final shell = container
        .read(routerProvider)
        .configuration
        .routes
        .whereType<StatefulShellRoute>()
        .single;

    for (final branch in shell.branches) {
      expect(
        branch.observers?.whereType<ModalObserver>(),
        isNotEmpty,
        reason: 'a sheet opened in this tab would go unrecorded',
      );
    }
  });
}
