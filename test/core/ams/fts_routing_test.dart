import 'package:bambuddy_mobile/core/ams/fts_routing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extruderForInlet', () {
    test('names the side each inlet rests on', () {
      expect(extruderForInlet('A'), 1, reason: 'In-A → Out-A → left hotend');
      expect(extruderForInlet('B'), 0);
    });

    test('takes the letter as the server may spell it', () {
      expect(extruderForInlet('a'), 1);
      expect(extruderForInlet(' b '), 0);
    });

    test('refuses anything else', () {
      expect(extruderForInlet(null), isNull);
      expect(extruderForInlet(''), isNull);
      expect(extruderForInlet('C'), isNull);
      expect(extruderForInlet('AB'), isNull);
    });
  });

  group('slotExtruder', () {
    test('a mapped AMS wins, switch or no switch', () {
      // BambuStudio treats a real extruder id as authoritative too: a unit
      // wired straight to one nozzle keeps that binding on a machine whose
      // other units go through the switch.
      expect(
        slotExtruder(
          amsId: 0,
          trayId: 2,
          amsExtruderMap: const {0: 1},
          amsSwitchInlet: const {0: 'B'},
        ),
        1,
      );
    });

    test('falls back to the inlet binding', () {
      expect(
        slotExtruder(amsId: 1, trayId: 0, amsSwitchInlet: const {1: 'A'}),
        1,
      );
      expect(
        slotExtruder(
          amsId: 1,
          trayId: 0,
          amsExtruderMap: const {},
          amsSwitchInlet: const {1: 'B'},
        ),
        0,
      );
    });

    test('the external holder is answered by the tray side alone', () {
      // Ext-L is tray 0 and the left hotend is extruder 1 — the inversion the
      // dashboard already relies on for `vt_tray` 254/255.
      expect(slotExtruder(amsId: 255, trayId: 0), 1);
      expect(slotExtruder(amsId: 255, trayId: 1), 0);
    });

    test('an external tray id that names no side is unknown', () {
      // The global tray numbers (254/255) reach here as 0/1; anything else is
      // a caller that forgot to normalise, and guessing would hide it.
      expect(slotExtruder(amsId: 255, trayId: 254), isNull);
      expect(slotExtruder(amsId: 255, trayId: -1), isNull);
    });

    test('says it does not know rather than answering 0', () {
      // The whole point of the port: on a dual-nozzle machine "unknown" and
      // "the right-hand nozzle" are different answers, and the old default of
      // 0 filed left-nozzle calibrations under the right one.
      expect(slotExtruder(amsId: 0, trayId: 0), isNull);
      expect(
        slotExtruder(
          amsId: 0,
          trayId: 0,
          amsExtruderMap: const {1: 0},
          amsSwitchInlet: const {2: 'A'},
        ),
        isNull,
      );
    });

    test('an unknown inlet letter is unknown, not right-hand', () {
      expect(
        slotExtruder(amsId: 0, trayId: 0, amsSwitchInlet: const {0: 'C'}),
        isNull,
      );
    });

    test('an AMS-HT keeps its mapping', () {
      // HT units are numbered from 128 and go through the same map.
      expect(
        slotExtruder(amsId: 128, trayId: 0, amsExtruderMap: const {128: 0}),
        0,
      );
    });
  });
}
