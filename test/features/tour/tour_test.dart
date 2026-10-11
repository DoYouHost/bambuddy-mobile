import 'package:bambuddy_mobile/core/demo/demo_backend.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/features/stats/statistics_screen.dart';
import 'package:bambuddy_mobile/features/tour/tour_beacon.dart';
import 'package:bambuddy_mobile/features/tour/tour_sandbox.dart';
import 'package:bambuddy_mobile/features/tour/tour_screen.dart';
import 'package:bambuddy_mobile/features/wall/wall_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

const _server = ServerProfile(
  baseUrl: 'http://printers.lan',
  authMode: AuthMode.none,
);

Future<SettingsRepository> _settings(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SettingsRepository(await SharedPreferences.getInstance());
}

/// The harness runs in Polish (`plApp`).

Finder _target(String id) =>
    find.byWidgetPredicate((w) => w is TourTarget && w.id == id);

void main() {
  group('when the tour runs by itself', () {
    test('the first sign-in on a fresh install owes the tour', () async {
      final settings = await _settings({});
      await settings.settleTourForExistingInstall();
      expect(settings.tourDue, isFalse);

      await settings.saveProfile(_server);
      await settings.markTourDue();
      expect(settings.tourDue, isTrue);

      await settings.saveTourSeen();
      expect(settings.tourDue, isFalse);
    });

    test(
      'an install signed in before the tour existed never gets it',
      () async {
        final settings = await _settings({});
        await settings.saveProfile(_server);

        await settings.settleTourForExistingInstall();
        // "Change server" signs in again; that must not bring the tour back.
        await settings.markTourDue();

        expect(settings.tourDue, isFalse);
      },
    );

    test('a tour cut short by the app being killed runs again', () async {
      final settings = await _settings({});
      await settings.saveProfile(_server);
      await settings.markTourDue();

      // The next cold start.
      await settings.settleTourForExistingInstall();

      expect(settings.tourDue, isTrue);
    });
  });

  group('the sandbox', () {
    test('runs on the demo and keeps every write to itself', () async {
      SharedPreferences.setMockInitialValues({});
      final real = await SharedPreferences.getInstance();
      final sandbox = TourSandbox(onEvent: (_) {});
      addTearDown(sandbox.dispose);

      expect(sandbox.container.read(serverProfileProvider)?.isDemo, isTrue);
      await sandbox.container
          .read(serverProfileProvider.notifier)
          .save(_server);
      await sandbox.container.read(serverProfileProvider.notifier).clear();
      await sandbox.container
          .read(sharedPreferencesProvider)
          .setBool('x', true);

      expect(real.getKeys(), isEmpty);
    });

    test('lends the demo a fresh backend and gives the old one back', () {
      final before = DemoBackend.instance;
      final count = DemoBackend.printingPrinters;
      DemoBackend.printingPrinters = 3;
      addTearDown(() => DemoBackend.printingPrinters = count);

      final sandbox = TourSandbox(onEvent: (_) {});
      expect(DemoBackend.instance, isNot(same(before)));
      expect(DemoBackend.printingPrinters, 1);

      sandbox.dispose();
      expect(DemoBackend.instance, same(before));
      expect(DemoBackend.printingPrinters, 3);
    });
  });

  testWidgets('the whole tour runs on the demo, gesture by gesture', (
    tester,
  ) async {
    // Tall enough that the wall step's card, preview and all, leaves the top
    // of the screen uncovered, as it does on a phone held upright.
    tester.view
      ..physicalSize = const Size(800, 1280)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final before = DemoBackend.instance;
    await pumpPhone(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => TourHost.open(context),
          child: const Text('open'),
        ),
      ),
      builder: (context, child) => TourHost(child: child!),
    );
    await tester.tap(find.text('open'));
    await settle(tester);

    Future<void> next() async {
      await tester.tap(byLogId('tour.next'));
      await settle(tester);
    }

    // The card keeps clear of what it points at.
    expect(
      tester.getRect(byLogId('tour.skip')).bottom,
      lessThan(tester.getRect(_target('shell.nav')).top),
    );

    // 1. Every tab; "Next" only once all four were opened.
    for (final tab in [pl.navQueue, pl.navArchive, pl.navMaintenance]) {
      await tester.tap(find.text(tab));
      await settle(tester);
      expect(byLogId('tour.next'), findsNothing);
    }
    await tester.tap(find.text(pl.navFilaments));
    await settle(tester);
    await next();

    // 2. Outside the spotlight nothing reacts: the menu next to it stays shut.
    await tester.tap(byLogId('dashboard.menu'), warnIfMissed: false);
    await settle(tester);
    expect(find.text(pl.wallModeTitle), findsNothing);
    await tester.tap(byLogId('chrome.drawer'));
    await settle(tester);
    await next();

    // 3.
    await tester.longPress(_target('printer.edit.1'));
    await settle(tester);
    await next();

    // 4. A drag that starts on the handle.
    final gesture = await tester.startGesture(
      tester.getCenter(_target('queue.reorder.102')),
    );
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settle(tester);
    await next();

    // 5. The confirmation opens; "Next" closes it unanswered.
    await tester.drag(_target('queue.swipe_delete.103'), const Offset(-400, 0));
    await settle(tester);
    await next();

    // 6.
    await tester.longPress(_target('archive.item.41'));
    await settle(tester);
    await next();

    // 7. The tour opens the menu itself and rings Wall mode, which only
    // looks: tapping it would lock the phone in landscape mid-tour.
    expect(find.byType(WallScreen), findsOneWidget);
    final wallItem = tester.renderObject(byLogId('dashboard.wall_mode'));
    final hit = tester.hitTestOnBinding(
      tester.getCenter(byLogId('dashboard.wall_mode')),
    );
    expect(hit.path.map((e) => e.target), isNot(contains(wallItem)));
    await next();

    // 8. The tour opens the drawer; the user taps its Statistics row. Closed
    // again (Back does that), the button that opens it is the way back in.
    expect(find.text(pl.menuStatistics), findsOneWidget);
    tester
        .firstState<ScaffoldState>(
          find.ancestor(
            of: byLogId('chrome.drawer'),
            matching: find.byType(Scaffold),
          ),
        )
        .closeDrawer();
    await settle(tester);
    await tester.tap(byLogId('chrome.drawer'));
    await settle(tester);
    await tester.tap(find.text(pl.menuStatistics));
    await settle(tester);
    expect(find.byType(StatisticsScreen), findsOneWidget);
    await next();

    // 9.
    await tester.tap(byLogId('tour.finish'));
    await settle(tester);
    expect(find.byType(TourScreen), findsNothing);
    expect(DemoBackend.instance, same(before));
  });

  testWidgets('Back ends the tour and leaves the app screens under it alone', (
    tester,
  ) async {
    late BuildContext tips;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Text('home'),
          routes: [
            GoRoute(
              path: 'tips',
              builder: (context, _) {
                tips = context;
                return const Text('tips');
              },
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('pl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (context, child) => TourHost(
          backButtonDispatcher: router.backButtonDispatcher,
          child: child!,
        ),
      ),
    );
    unawaited(router.push('/tips'));
    await settle(tester);
    unawaited(TourHost.open(tips));
    await settle(tester);
    expect(find.byType(TourScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(TourScreen), findsNothing);
    expect(find.text('tips'), findsOneWidget);

    // The tour's claim on Back went with it.
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('the card scrolls on a phone on its side with large text', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(800, 360)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpPhone(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => TourHost.open(context),
          child: const Text('open'),
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(2)),
        child: TourHost(child: child!),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);

    // An overflow would have failed the pump; the way out stays reachable.
    await tester.scrollUntilVisible(
      byLogId('tour.skip'),
      50,
      scrollable: find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    await tester.tap(byLogId('tour.skip'));
    await settle(tester);
    expect(find.byType(TourScreen), findsNothing);
  });

  testWidgets(
    'a second copy of a target leaving does not take the first along',
    (tester) async {
      // A reorder drag mounts a proxy of the row, handle and all, and drops it
      // when the finger lifts.
      final beacon = TourBeacon((_) {});
      Widget tree({required bool proxy}) => ProviderScope(
        overrides: [tourBeaconProvider.overrideWithValue(beacon)],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              const TourTarget(id: 'row', child: SizedBox(height: 10)),
              if (proxy)
                const TourTarget(id: 'row', child: SizedBox(height: 10)),
            ],
          ),
        ),
      );
      await tester.pumpWidget(tree(proxy: true));
      await tester.pumpWidget(tree(proxy: false));

      expect(beacon.rectOf(['row']), isNotNull);
    },
  );

  test('the card keeps its side until the target is well into its half', () {
    expect(tourCardAtTop(null, 0.8), isTrue);
    expect(tourCardAtTop(null, 0.3), isFalse);
    // A drag a little past the middle leaves it where it is…
    expect(tourCardAtTop(true, 0.4), isTrue);
    expect(tourCardAtTop(false, 0.6), isFalse);
    // …one deep into its half moves it.
    expect(tourCardAtTop(true, 0.2), isFalse);
    expect(tourCardAtTop(false, 0.8), isTrue);
  });
}
