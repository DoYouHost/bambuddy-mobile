import 'package:bambuddy_mobile/core/models/user_summary.dart';
import 'package:bambuddy_mobile/features/stats/statistics_screen.dart';
import 'package:bambuddy_mobile/features/stats/stats_providers.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Regression: the "All users" row has to be selectable.
///
/// `PopupMenuButton` resolves its menu route with `null` when the user dismisses
/// it (tap outside, back gesture), and has no way to tell that apart from
/// picking an item whose value *is* null — it calls `onCanceled` for both. A
/// `value: null` row is therefore simply unclickable, which cut off the way back
/// to "all" once any user had been chosen. Hence a sentinel instead of null.
void main() {
  const users = [
    UserSummary(id: 7, username: 'ala'),
    UserSummary(id: 8, username: 'bob'),
  ];

  Widget app() => ProviderScope(
        overrides: [
          statsUsersProvider.overrideWith((ref) async => users),
        ],
        child: plApp(const StatisticsScreen()),
      );

  Element screen(WidgetTester tester) =>
      tester.element(find.byType(StatisticsScreen));

  /// Labels come from the running locale rather than being hardcoded, so the
  /// test keeps passing when a translation is reworded.
  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(screen(tester));

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(screen(tester));

  /// Opens the user-filter menu and taps the row carrying [label].
  Future<void> pick(WidgetTester tester, String label) async {
    await tester.tap(find.byIcon(Icons.people_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('picking a user, then going back to "all users"', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final container = containerOf(tester);
    expect(container.read(statsFilterProvider).createdById, isNull,
        reason: 'starts unfiltered');

    await pick(tester, 'bob');
    expect(container.read(statsFilterProvider).createdById, 8);

    // The regression itself: with a user selected, return to "all".
    await pick(tester, l10nOf(tester).statsAllUsers);
    expect(container.read(statsFilterProvider).createdById, isNull,
        reason: '"All users" must clear the filter, not be a no-op');
  });

  testWidgets('"no user" still sends -1 rather than null', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await pick(tester, l10nOf(tester).statsNoUser);

    // -1 is the server's "prints with no author" filter; the "all users"
    // sentinel must not collide with it in either direction.
    expect(containerOf(tester).read(statsFilterProvider).createdById, -1);
  });
}
