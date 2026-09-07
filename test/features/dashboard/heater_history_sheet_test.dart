import 'package:bambuddy_mobile/core/models/heater_history.dart';
import 'package:bambuddy_mobile/data/heater_history_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/heater_history_sheet.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// A network-free repository: hands back a prepared history or throws.
class _StubRepo extends HeaterHistoryRepository {
  _StubRepo({this.history, this.error}) : super(Dio());

  final HeaterHistory? history;
  final Object? error;

  /// Remembered parameters of the last query — checks that the sheet asks
  /// for the chosen range and only for the sensor that's on screen.
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

  testWidgets('draws reading and target, stats from the server, asks only '
      'for the chosen sensor', (tester) async {
    final repo = _StubRepo(history: _history());

    await pumpSheet(tester, repo);

    expect(repo.lastHours, 24);
    expect(repo.lastKinds, ['nozzle']);

    // Two lines: reading and (since the data has targets) target.
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData, hasLength(2));
    expect(find.text('Odczyt'), findsOneWidget);
    expect(find.text('Zadana'), findsOneWidget);

    // Current from the last point, the rest straight from the server.
    expect(find.text('219.8°C'), findsOneWidget);
    expect(find.text('120.3°C'), findsOneWidget);
    expect(find.text('24.5°C'), findsOneWidget);
    expect(find.text('220.4°C'), findsOneWidget);
  });

  testWidgets('changing sensor and range re-queries', (tester) async {
    final repo = _StubRepo(history: _history());

    await pumpSheet(tester, repo);

    await tester.tap(find.text('6 h'));
    await tester.pumpAndSettle();
    expect(repo.lastHours, 6);

    // Bed has no points — empty state instead of a chart.
    await tester.tap(find.text('Stół'));
    await tester.pumpAndSettle();
    expect(repo.lastKinds, ['bed']); // new sensor = new query
    expect(find.text('Brak danych w tym zakresie'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
  });

  testWidgets('a long range does not load all samples onto the chart', (
    tester,
  ) async {
    // A week of per-minute logging: the server hands back ~10k points, and the
    // chart is a few hundred pixels wide.
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
    // The last point stays — that's where "Current" comes from.
    expect(spots.last.y, 200 + (10079 % 7));
    expect(
      find.text('${(200 + 10079 % 7).toStringAsFixed(1)}°C'),
      findsOneWidget,
    );
  });

  testWidgets('without target temperatures there is no dashed line or legend', (
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

  testWidgets('a fetch error shows a message instead of an empty chart', (
    tester,
  ) async {
    final repo = _StubRepo(error: Exception('boom'));

    await pumpSheet(tester, repo);

    expect(find.text('Nie udało się wczytać historii'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
  });
}
