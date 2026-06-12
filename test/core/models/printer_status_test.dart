import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  group('PrinterStatus.fromJson', () {
    test('parsuje status drukującej drukarki, ignorując nieznane pola', () {
      final status = PrinterStatus.fromJson(
          readFixture('printer_status_printing.json') as Map<String, dynamic>);

      expect(status.id, 1);
      expect(status.name, 'X1C Warsztat');
      expect(status.connected, isTrue);
      expect(status.state, 'RUNNING');
      expect(status.currentPrint, 'benchy.3mf');
      expect(status.gcodeFile, 'benchy_plate_1.gcode');
      expect(status.progress, 42.5);
      expect(status.remainingTime, 137);
      expect(status.layerNum, 87);
      expect(status.totalLayers, 203);
      expect(status.temperatures, {
        'nozzle': 219.7,
        'bed': 60.0,
        'chamber': 31.2,
      });
      expect(status.isPrinting, isTrue);
    });

    test('parsuje status bezczynnej drukarki', () {
      final status = PrinterStatus.fromJson(
          readFixture('printer_status_idle.json') as Map<String, dynamic>);

      expect(status.state, 'IDLE');
      expect(status.currentPrint, isNull);
      expect(status.isPrinting, isFalse);
    });

    test('toleruje liczby jako stringi i nieparsowalne wartości temperatur',
        () {
      final status = PrinterStatus.fromJson(
          readFixture('printer_status_error.json') as Map<String, dynamic>);

      expect(status.state, 'FAILED');
      expect(status.progress, 61.0, reason: 'progress przyszedł jako string');
      expect(status.remainingTime, 88);
      expect(status.layerNum, isNull);
      expect(status.temperatures, {'nozzle': 25.0},
          reason: '"off" nie jest liczbą — wpis pominięty, nie crash');
    });

    test('minimalny payload (samo id) nie wywala parsera', () {
      final status = PrinterStatus.fromJson(const {'id': 7});

      expect(status.id, 7);
      expect(status.state, isNull);
      expect(status.temperatures, isNull);
      expect(status.isPrinting, isFalse);
    });

    test('faza przygotowania (RUNNING, progress 0) liczy się jako wydruk', () {
      const status = PrinterStatus(
        id: 1,
        state: 'RUNNING',
        progress: 0,
        remainingTime: 0,
        stgCurName: 'Auto bed leveling',
      );

      expect(status.isPrinting, isTrue,
          reason: 'nagrzewanie/leveling to etap wydruku');
      expect(status.isPreparing, isTrue);
    });

    test('FAILED nie jest wydrukiem mimo dodatniego progresu', () {
      const status =
          PrinterStatus(id: 1, state: 'FAILED', progress: 61, remainingTime: 88);

      expect(status.isPrinting, isFalse);
    });
  });

  group('Printer.fromJson', () {
    test('parsuje listę drukarek, ignorując nieznane pola', () {
      final raw = readFixture('printers_list.json') as List<dynamic>;
      final printers = raw
          .map((e) => Printer.fromJson(e as Map<String, dynamic>))
          .toList();

      expect(printers, hasLength(2));
      expect(printers[0].name, 'X1C Warsztat');
      expect(printers[0].ipAddress, '192.168.1.50');
      expect(printers[1].location, isNull);
      expect(printers[1].isActive, isFalse);
    });
  });
}
