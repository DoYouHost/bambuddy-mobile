import 'package:bambuddy_mobile/core/models/user_summary.dart';
import 'package:bambuddy_mobile/features/stats/statistics_screen.dart';
import 'package:bambuddy_mobile/features/stats/stats_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Regresja: pozycja „Wszyscy użytkownicy" musi dać się wybrać.
///
/// `PopupMenuButton` rozwiązuje trasę menu wartością `null`, gdy użytkownik je
/// porzuci (tap obok, cofnięcie), i nie ma jak odróżnić tego od wybrania
/// pozycji, której wartość *jest* nullem — w obu wypadkach woła `onCanceled`.
/// Pozycja z `value: null` jest więc po prostu nieklikalna, co odcinało powrót
/// do „wszystkich" po wybraniu kogokolwiek. Stąd wartownik zamiast nulla.
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

  /// Otwiera menu filtra użytkownika i klika pozycję o podanej etykiecie.
  Future<void> pick(WidgetTester tester, String label) async {
    await tester.tap(find.byIcon(Icons.people_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('wybór użytkownika, a potem powrót do „wszyscy"', (tester) async {
    late ProviderContainer container;

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    container = ProviderScope.containerOf(
      tester.element(find.byType(StatisticsScreen)),
    );

    expect(container.read(statsFilterProvider).createdById, isNull,
        reason: 'start: brak filtra');

    await pick(tester, 'bob');
    expect(container.read(statsFilterProvider).createdById, 8);

    // Sedno regresji: z wybranym użytkownikiem wracamy na „wszyscy".
    await pick(tester, 'Wszyscy użytkownicy');
    expect(container.read(statsFilterProvider).createdById, isNull,
        reason: '„Wszyscy użytkownicy" musi czyścić filtr, nie być no-opem');
  });

  testWidgets('„bez użytkownika" nadal wysyła -1, nie null', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(StatisticsScreen)),
    );

    await pick(tester, 'Brak użytkownika (system)');

    // -1 to filtr serwera „wydruki bez autora"; wartownik „wszyscy" nie może go
    // przykryć ani odwrotnie.
    expect(container.read(statsFilterProvider).createdById, -1);
  });
}
