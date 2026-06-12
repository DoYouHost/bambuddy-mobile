import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/printer_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  testWidgets('karta renderuje nazwę, postęp i temperatury z fixture\'a',
      (tester) async {
    final item = PrinterWithStatus(
      printer: const Printer(id: 1, name: 'X1C Warsztat'),
      status: PrinterStatus.fromJson(
          readFixture('printer_status_printing.json') as Map<String, dynamic>),
    );

    await tester.pumpWidget(plApp(Scaffold(body: PrinterCard(item: item))));

    expect(find.text('X1C Warsztat'), findsOneWidget);
    expect(find.text('RUNNING'), findsOneWidget);
    expect(find.text('benchy.3mf'), findsOneWidget);
    expect(find.textContaining('43%'), findsOneWidget);
    expect(find.textContaining('87/203'), findsOneWidget);
    expect(find.textContaining('pozostało 2 h 17 min'), findsOneWidget);
    // Kafelek temperatury: etykieta i wartość to osobne teksty.
    expect(find.text('Dysza'), findsOneWidget);
    expect(find.text('220°'), findsOneWidget);
    expect(find.text('Stół'), findsOneWidget);
    expect(find.text('60°'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('kafelki temperatur: parowanie aktualna/cel, cel 0 ukryty, '
      'numerowana dysza, nieznany klucz', (tester) async {
    final item = PrinterWithStatus(
      printer: const Printer(id: 3, name: 'X2D'),
      status: const PrinterStatus(
        id: 3,
        connected: true,
        state: 'RUNNING',
        temperatures: {
          'bed': 70,
          'bed_target': 70,
          'nozzle': 244,
          'nozzle_target': 245,
          'nozzle_2': 47,
          'nozzle_2_target': 0,
          'chamber': 30,
          'cośdziwnego': 12,
        },
      ),
    );

    await tester.pumpWidget(plApp(Scaffold(body: PrinterCard(item: item))));

    // Parowanie aktualna/cel.
    expect(find.text('Stół'), findsOneWidget);
    expect(find.text('70° / 70°'), findsOneWidget);
    expect(find.text('Dysza'), findsOneWidget);
    expect(find.text('244° / 245°'), findsOneWidget);
    // Cel = 0 → pokazujemy tylko wartość aktualną.
    expect(find.text('Dysza 2'), findsOneWidget);
    expect(find.text('47°'), findsOneWidget);
    // Bez celu.
    expect(find.text('Komora'), findsOneWidget);
    expect(find.text('30°'), findsOneWidget);
    // Nieznany klucz zostaje surowy.
    expect(find.text('cośdziwnego'), findsOneWidget);
    expect(find.text('12°'), findsOneWidget);
  });

  testWidgets('karta bez statusu pokazuje „status niedostępny"',
      (tester) async {
    const item = PrinterWithStatus(
      printer: Printer(id: 2, name: 'A1 mini'),
    );

    await tester.pumpWidget(plApp(const Scaffold(body: PrinterCard(item: item))));

    expect(find.text('A1 mini'), findsOneWidget);
    expect(find.text('status niedostępny'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
