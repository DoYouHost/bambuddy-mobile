import 'package:bambuddy_mobile/core/models/panda_breath.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The shape `PandaBreathState` serialises to (schemas/printer.py).
  const full = {
    'device_id': 'pb-1',
    'online': true,
    'chamber_temp': 41.5,
    'target_temp': 45,
    'work_on': true,
    'mode': 'filament drying',
    'filament_drying_mode': 'PLA',
    'drying_running': true,
    'drying_remaining_min': 95.0,
  };

  group('pandaBreathFromJson', () {
    test('reads every field the printer card shows', () {
      final p = pandaBreathFromJson(full)!;
      expect(p.deviceId, 'pb-1');
      expect(p.online, isTrue);
      expect(p.chamberTemp, 41.5);
      expect(p.targetTemp, 45);
      expect(p.workOn, isTrue);
      expect(p.knownMode, PandaBreathMode.drying);
      expect(p.dryingRunning, isTrue);
      expect(p.dryingRemainingMin, 95);
    });

    test('a heater that has reported nothing but its id', () {
      final p = pandaBreathFromJson({'device_id': 'pb-1'})!;
      expect(p.online, isNull);
      expect(p.chamberTemp, isNull);
      expect(p.workOn, isNull);
      expect(p.knownMode, isNull);
      // Unknown is not offline: the web lets the user try.
      expect(p.usable, isTrue);
    });

    test('offline only when the server says so', () {
      expect(pandaBreathFromJson({...full, 'online': false})!.usable, isFalse);
    });

    test('an unknown mode is kept raw and maps to no known mode', () {
      final p = pandaBreathFromJson({...full, 'mode': 'turbo'})!;
      expect(p.mode, 'turbo');
      expect(p.knownMode, isNull);
    });

    test('each wire mode maps to its member', () {
      for (final m in PandaBreathMode.values) {
        expect(pandaBreathFromJson({...full, 'mode': m.wire})!.knownMode, m);
      }
    });

    test('no heater: null, the key missing, or no device id', () {
      expect(pandaBreathFromJson(null), isNull);
      expect(pandaBreathFromJson('nonsense'), isNull);
      expect(pandaBreathFromJson(const <String, dynamic>{}), isNull);
      expect(pandaBreathFromJson({...full, 'device_id': '  '}), isNull);
      expect(pandaBreathFromJson({...full, 'device_id': 7}), isNull);
    });

    test('a non-bool flag reads as unreported, not as off', () {
      final p = pandaBreathFromJson({...full, 'online': 'yes', 'work_on': 1})!;
      expect(p.online, isNull);
      expect(p.workOn, isNull);
    });
  });

  group('on a status', () {
    Map<String, dynamic> frame({Object? panda = _absent, bool on = true}) => {
      'id': 1,
      'connected': on,
      'state': on ? 'IDLE' : null,
      if (panda != _absent) 'panda_breath': panda,
    };

    test('is read from panda_breath', () {
      expect(
        PrinterStatus.fromJson(frame(panda: full)).pandaBreath?.deviceId,
        'pb-1',
      );
    });

    test('an older server sends no key: no heater', () {
      expect(PrinterStatus.fromJson(frame()).pandaBreath, isNull);
    });

    test('a frame with null takes an unbound heater away', () {
      final before = PrinterStatus.fromJson(frame(panda: full));
      final after = PrinterStatus.fromJson(frame(panda: null));
      expect(after.mergedWith(before).pandaBreath, isNull);
    });

    test('stays on a printer that goes offline: it runs without one', () {
      final gone = PrinterStatus.fromJson(frame(panda: full, on: false));
      final previous = PrinterStatus.fromJson(frame(panda: full));
      expect(gone.mergedWith(previous).pandaBreath?.deviceId, 'pb-1');
      expect(gone.mergedWith(null).pandaBreath?.deviceId, 'pb-1');
    });

    test('statuses that differ only in the heater are not equal', () {
      final a = PrinterStatus.fromJson(frame(panda: full));
      final b = PrinterStatus.fromJson(
        frame(panda: {...full, 'chamber_temp': 42.0}),
      );
      expect(a, PrinterStatus.fromJson(frame(panda: full)));
      expect(a, isNot(b));
    });
  });
}

const _absent = Object();
