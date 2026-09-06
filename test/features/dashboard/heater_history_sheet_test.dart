import 'package:bambuddy_mobile/core/models/heater_history.dart';
import 'package:bambuddy_mobile/data/heater_history_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/heater_history_sheet.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Repozytorium bez sieci: oddaje przygotowaną historię albo rzuca.
class _StubRepo extends HeaterHistoryRepository {
  _StubRepo({this.history, this.error}) : super(Dio());

  final HeaterHistory? history;
  final Object? error;

  /// Zapamiętane parametry ostatniego zapytania — sprawdzamy, że arkusz pyta
  /// o wybrany zakres i tylko o czujnik, który jest na ekranie.
  int? lastHours;
  List<String>? lastKinds;

  @override
  Future<HeaterHistory> fetch(
    int printerId, {
    int hours = 24,
    List<String> kinds = const [],
  }) async {
    lastHours = hours;
    lastKinds = kinds;
    if (error != null) throw error!;
    return history!;
  }
}

HeaterHistory _history({List<HeaterHistoryPoint>? nozzle}) => HeaterHistory(
  printerId: 3,
  series: [
    HeaterSeries(
      sensorKind: 'nozzle',
      points:
          nozzle ??
          [
            HeaterHistoryPoint(
              recordedAt: DateTime.now().subtract(const Duration(hours: 1)),
              value: 24.5,
              target: 0,
            ),
            HeaterHistoryPoint(
              recordedAt: DateTime.now(),
              value: 219.8,
              target: 220,
            ),
          ],
      minValue: 24.5,
      maxValue: 220.4,
      avgValue: 120.3,
    ),
    const HeaterSeries(sensorKind: 'bed', points: []),
  ],
);

void main() {
  Future<void> pumpSheet(WidgetTester tester, _StubRepo repo) async {
    await pumpPhone(
      tester,
      const HeaterHistorySheet(
        printerId: 3,
        kinds: [(kind: 'nozzle', label: 'Dysza'), (kind: 'bed', label: 'Stół')],
        initialKind: 'nozzle',
      ),
      overrides: [heaterHistoryRepositoryProvider.overrideWithValue(repo)],
    );
    await tester.pumpAndSettle();
  }

  testWidgets('rysuje odczyt i zadaną, statystyki z serwera, pyta tylko '
      'o wybrany czujnik', (tester) async {
    final repo = _StubRepo(history: _history());

    await pumpSheet(tester, repo);

    expect(repo.lastHours, 24);
    expect(repo.lastKinds, ['nozzle']);

    // Dwie linie: odczyt i (bo w danych są cele) zadana.
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData, hasLength(2));
    expect(find.text('Odczyt'), findsOneWidget);
    expect(find.text('Zadana'), findsOneWidget);

    // Aktualna z ostatniego punktu, reszta prosto z serwera.
    expect(find.text('219.8°C'), findsOneWidget);
    expect(find.text('120.3°C'), findsOneWidget);
    expect(find.text('24.5°C'), findsOneWidget);
    expect(find.text('220.4°C'), findsOneWidget);
  });

  testWidgets('zmiana czujnika i zakresu odpytuje na nowo', (tester) async {
    final repo = _StubRepo(history: _history());

    await pumpSheet(tester, repo);

    await tester.tap(find.text('6 h'));
    await tester.pumpAndSettle();
    expect(repo.lastHours, 6);

    // Stół nie ma punktów — pusty stan zamiast wykresu.
    await tester.tap(find.text('Stół'));
    await tester.pumpAndSettle();
    expect(repo.lastKinds, ['bed']); // nowy czujnik = nowe zapytanie
    expect(find.text('Brak danych w tym zakresie'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
  });

  testWidgets('długi zakres nie ładuje na wykres wszystkich próbek', (
    tester,
  ) async {
    // Tydzień zapisu co minutę: serwer oddaje ~10 tys. punktów, a wykres ma
    // kilkaset pikseli szerokości.
    final start = DateTime.now().subtract(const Duration(days: 7));
    final repo = _StubRepo(
      history: _history(
        nozzle: [
          for (var i = 0; i < 10080; i++)
            HeaterHistoryPoint(
              recordedAt: start.add(Duration(minutes: i)),
              value: 200 + (i % 7),
            ),
        ],
      ),
    );

    await pumpSheet(tester, repo);

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final spots = chart.data.lineBarsData.single.spots;
    expect(spots.length, lessThanOrEqualTo(481));
    // Ostatni punkt zostaje — z niego bierze się „Aktualna".
    expect(spots.last.y, 200 + (10079 % 7));
    expect(
      find.text('${(200 + 10079 % 7).toStringAsFixed(1)}°C'),
      findsOneWidget,
    );
  });

  testWidgets('bez zadanych temperatur nie ma linii przerywanej ani legendy', (
    tester,
  ) async {
    final repo = _StubRepo(
      history: _history(
        nozzle: [HeaterHistoryPoint(recordedAt: DateTime.now(), value: 24.5)],
      ),
    );

    await pumpSheet(tester, repo);

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData, hasLength(1));
    expect(find.text('Zadana'), findsNothing);
  });

  testWidgets('błąd pobrania pokazuje komunikat zamiast pustego wykresu', (
    tester,
  ) async {
    final repo = _StubRepo(error: Exception('boom'));

    await pumpSheet(tester, repo);

    expect(find.text('Nie udało się wczytać historii'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
  });
}
