import 'package:bambuddy_mobile/core/ams/slot_addressing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the external holder', () {
    test('converts between its side and its global id', () {
      expect(externalSideOf(254), 0, reason: 'Ext-L');
      expect(externalSideOf(255), 1, reason: 'Ext-R');
      expect(externalTrayIdOf(0), 254);
      expect(externalTrayIdOf(1), 255);
    });

    test('is not a global id just because it is a big number', () {
      expect(externalSideOf(253), isNull);
      expect(externalSideOf(256), isNull);
      expect(externalSideOf(null), isNull);
    });

    test(
      'feeds the nozzle on its own side, which is numbered the other way',
      () {
        // Verified on a live X2D: the 254 spool sits physically left, and the
        // printer calls the left nozzle extruder 1.
        expect(extruderForExternalSide(0), 1);
        expect(extruderForExternalSide(1), 0);
      },
    );

    test('says it does not know rather than answering 0', () {
      expect(extruderForExternalSide(null), isNull);
      expect(extruderForExternalSide(2), isNull);
    });

    test('is recognised under either unit id the backends use', () {
      // The status and the slot routes say 255; the inventory backend has been
      // seen filing the same holder under 254.
      expect(isExternalHolder(255), isTrue);
      expect(isExternalHolder(254), isTrue);
      expect(isExternalHolder(3), isFalse);
      expect(isExternalHolder(128), isFalse, reason: 'AMS-HT is a real unit');
    });
  });

  group('globalTrayId', () {
    test('numbers a regular AMS slot as unit * 4 + slot', () {
      expect(globalTrayId(amsId: 0, trayId: 0), 0);
      expect(globalTrayId(amsId: 1, trayId: 2), 6);
      expect(globalTrayId(amsId: 3, trayId: 3), 15);
      // The A2L AMS-Lite arrives normalised to unit 6.
      expect(globalTrayId(amsId: 6, trayId: 3), 27);
    });

    test('gives an AMS-HT its own unit id', () {
      // `print_scheduler.py::_build_loaded_filaments` — an HT holds one tray,
      // so the unit id *is* the tray number. The arithmetic above would put it
      // at 512, which the printer does not know.
      expect(globalTrayId(amsId: 128, trayId: 0), 128);
      expect(globalTrayId(amsId: 135, trayId: 0), 135);
    });

    test('passes the holder side through as 254/255', () {
      expect(globalTrayId(amsId: 255, trayId: 0), 254);
      expect(globalTrayId(amsId: 255, trayId: 1), 255);
      expect(globalTrayId(amsId: 254, trayId: 1), 255);
    });
  });

  group('localSlotOf', () {
    test('undoes globalTrayId for every encoding', () {
      for (final slot in const [
        (amsId: 0, trayId: 0),
        (amsId: 2, trayId: 3),
        (amsId: 6, trayId: 1),
        (amsId: 128, trayId: 0),
        (amsId: 255, trayId: 0),
        (amsId: 255, trayId: 1),
      ]) {
        expect(
          localSlotOf(globalTrayId(amsId: slot.amsId, trayId: slot.trayId)),
          slot,
          reason: 'AMS ${slot.amsId} slot ${slot.trayId}',
        );
      }
    });
  });
}
