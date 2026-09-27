import 'package:bambuddy_mobile/features/common/refresh_when_shown.dart';
import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a tab does with the data it read the first time it was opened.
///
/// The tabs live in an `IndexedStack`, so leaving one does not dispose it: a
/// print queued from the web, or a spool edited elsewhere, stayed invisible
/// until the user pulled the list down by hand.
void main() {
  late int refreshes;
  late DateTime now;

  setUp(() {
    refreshes = 0;
    now = DateTime(2026, 9, 19, 11);
  });

  /// The screen inside the `TickerMode` its branch container gives it.
  Future<void> pumpTab(
    WidgetTester tester, {
    required bool shown,
    int announced = 0,
  }) => withClock(
    Clock(() => now),
    () => tester.pumpWidget(
      TickerMode(
        enabled: shown,
        child: RefreshWhenShown(
          announced: announced,
          onRefresh: () => refreshes++,
          child: const SizedBox(),
        ),
      ),
    ),
  );

  Future<void> settle(WidgetTester tester) =>
      withClock(Clock(() => now), () => tester.pump());

  testWidgets('the tab in front on the first frame fetches nothing', (
    tester,
  ) async {
    await pumpTab(tester, shown: true);
    await settle(tester);

    expect(refreshes, 0, reason: 'the screen has just read its data');
  });

  testWidgets('coming back after a while re-reads the list', (tester) async {
    await pumpTab(tester, shown: true);
    await pumpTab(tester, shown: false);

    now = now.add(const Duration(minutes: 2));
    await pumpTab(tester, shown: true);
    await settle(tester);

    expect(refreshes, 1);
  });

  testWidgets('flipping between tabs is not a request each', (tester) async {
    await pumpTab(tester, shown: true);
    await pumpTab(tester, shown: false);

    now = now.add(const Duration(seconds: 5));
    await pumpTab(tester, shown: true);
    await settle(tester);

    expect(refreshes, 0, reason: 'this is still what the user just saw');
  });

  testWidgets('a change the server announced skips the wait', (tester) async {
    await pumpTab(tester, shown: true);
    await pumpTab(tester, shown: false);

    // The spool was edited on the web a second ago.
    await pumpTab(tester, shown: false, announced: 1);
    now = now.add(const Duration(seconds: 5));
    await pumpTab(tester, shown: true, announced: 1);
    await settle(tester);

    expect(refreshes, 1);
  });

  testWidgets('a change announced while the tab is in front lands at once', (
    tester,
  ) async {
    await pumpTab(tester, shown: true);

    await pumpTab(tester, shown: true, announced: 1);
    await settle(tester);

    expect(refreshes, 1);
  });

  testWidgets('a phone picked up after an hour re-reads the list', (
    tester,
  ) async {
    await pumpTab(tester, shown: true);

    withClock(Clock(() => now), () {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    });
    now = now.add(const Duration(hours: 1));
    await settle(tester);
    withClock(Clock(() => now), () {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await settle(tester);

    expect(refreshes, 1);
  });

  testWidgets('a glance at another app is not a reason to fetch', (
    tester,
  ) async {
    await pumpTab(tester, shown: true);

    withClock(Clock(() => now), () {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    });
    now = now.add(const Duration(seconds: 3));
    withClock(Clock(() => now), () {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await settle(tester);

    expect(refreshes, 0);
  });

  testWidgets('a tab out of sight stays out of the way', (tester) async {
    await pumpTab(tester, shown: false);
    now = now.add(const Duration(minutes: 5));
    await settle(tester);

    expect(refreshes, 0, reason: 'nothing is fetched for a tab nobody sees');
  });
}
