import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a nozzle reports about itself (server #1908): wear, print time, status,
/// temperature rating and serial. Every one is optional: H2C firmware sends
/// `p_t`, an older firmware or server leaves it out, and the card shows only
/// what was reported.
void main() {
  group('NozzleRackSlot.fromJson', () {
    test('reads what a 1.3.2 server sends for an H2C nozzle', () {
      final slot = NozzleRackSlot.fromJson(const {
        'id': 17,
        'nozzle_type': 'HS01',
        'nozzle_diameter': '0.6',
        'wear': 12,
        'print_time_s': 90061,
        'stat': 1,
        'max_temp': 300,
        'serial_number': '0A1B2C',
      });

      expect(slot.wear, 12);
      expect(slot.printTimeS, 90061);
      expect(slot.stat, 1);
      expect(slot.maxTemp, 300);
      expect(slot.serialNumber, '0A1B2C');
    });

    test('a server before 1.3.2 sends no print time, and it stays null', () {
      final slot = NozzleRackSlot.fromJson(const {
        'id': 17,
        'wear': 12,
        'max_temp': 300,
      });

      expect(slot.printTimeS, isNull);
      expect(slot.wear, 12);
    });

    test('a null print time is a nozzle that reports none, not zero hours', () {
      final slot = NozzleRackSlot.fromJson(const {
        'id': 0,
        'print_time_s': null,
        'wear': null,
      });

      expect(slot.printTimeS, isNull);
      expect(slot.wear, isNull);
    });

    test(
      'numbers that arrive as text are still numbers, odd ones are null',
      () {
        final slot = NozzleRackSlot.fromJson(const {
          'id': 16,
          'print_time_s': '7200',
          'wear': 'worn',
          'stat': true,
          'max_temp': '300',
        });

        expect(slot.printTimeS, 7200);
        expect(slot.wear, isNull);
        expect(slot.stat, isNull);
        expect(slot.maxTemp, 300);
      },
    );

    test('an empty record has none of them', () {
      final slot = NozzleRackSlot.fromJson(const {});

      expect(slot.wear, isNull);
      expect(slot.printTimeS, isNull);
      expect(slot.stat, isNull);
      expect(slot.maxTemp, isNull);
      expect(slot.serialNumber, isNull);
    });
  });

  test('the rack in a status keeps each nozzle\'s print time', () {
    final status = PrinterStatus.fromJson(const {
      'id': 1,
      'nozzle_rack': [
        {'id': 0, 'print_time_s': 3600},
        {'id': 16, 'print_time_s': null},
      ],
    });

    expect([for (final n in status.nozzleRack!) n.printTimeS], [3600, null]);
  });
}
