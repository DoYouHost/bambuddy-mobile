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

  // Ported from the web's `__tests__/utils/trayIds.test.ts`, which pins the
  // server's `utils/tray_ids.py` values.
  group('rack printer (H3C)', () {
    final h3c = TrayLayout.of(const [(id: 32, amsType: AmsType.zmultiA)]);

    test('a unit type is told from the id when the server sends none', () {
      expect(unitAmsType(0), AmsType.ams);
      expect(unitAmsType(128), AmsType.n3s);
      expect(unitAmsType(32), AmsType.zmultiA);
      expect(unitAmsType(32, AmsType.zmultiB), AmsType.zmultiB);
      expect(unitAmsType(128, AmsType.ams), AmsType.n3s);
      expect(unitAmsType(5, 0), AmsType.ams, reason: 'EXT_SPOOL is no unit');
      expect(unitAmsType(5, 99), AmsType.ams, reason: 'nonsense type');
    });

    test('the AMS 3H numbers its nine slots 28-36, an AMS-B from 37', () {
      expect(
        [for (var s = 0; s < 9; s++) globalTrayId(amsId: 32, trayId: s)],
        [for (var s = 0; s < 9; s++) 28 + s],
      );
      expect(globalTrayId(amsId: 40, trayId: 2, amsType: AmsType.zmultiB), 39);
      // The A2L's AMS Lite by its type, the same 24-27 as unit 6.
      expect(
        globalTrayId(amsId: 6, trayId: 1, amsType: AmsType.amsLiteMixed),
        25,
      );
    });

    test('numbers the H3C both ways', () {
      expect(h3c.rack, isTrue);
      for (var slot = 0; slot < rackSlotCount; slot++) {
        final tray = h3c.globalTrayIdOf(32, slot);
        expect(tray, 28 + slot);
        expect(h3c.locate(tray), (amsId: 32, trayId: slot));
        expect(localSlotOf(tray, h3c), (amsId: 32, trayId: slot));
      }
    });

    test('a regular printer is numbered as before', () {
      final layout = TrayLayout.of(
        const [
          (id: 0, amsType: null),
          (id: 1, amsType: AmsType.n3f),
          (id: 128, amsType: null),
        ],
        const [254, 255],
      );
      expect(layout.rack, isFalse);
      expect(layout.globalTrayIdOf(1, 3), 7);
      expect(layout.locate(7), (amsId: 1, trayId: 3));
      expect(layout.locate(128), (amsId: 128, trayId: 0));
      expect(layout.locate(250), isNull);
    });

    test('28-36 are the AMS 3H without live data, but not past a unit 7', () {
      final empty = TrayLayout.of(const []);
      expect(empty.locate(30), (amsId: 32, trayId: 2));
      final unit7 = TrayLayout.of(const [(id: 7, amsType: null)]);
      expect(unit7.locate(28), (amsId: 7, trayId: 0));
      expect(unit7.locate(31), (amsId: 7, trayId: 3));
    });

    test('an explicit type from the API wins', () {
      final layout = TrayLayout.of(const [
        (id: 32, amsType: AmsType.zmultiA),
        (id: 32, amsType: AmsType.zmultiA),
      ]);
      expect(layout.units, {32: AmsType.zmultiA});
      expect(layout.locate(32), (amsId: 32, trayId: 4));
    });

    test('external inputs 247-253 exist only on a rack printer', () {
      for (final tray in [254, 255]) {
        expect(isExternalTray(tray), isTrue);
        expect(isExternalTray(tray, rack: true), isTrue);
      }
      for (var tray = 247; tray <= 253; tray++) {
        expect(isExternalTray(tray), isFalse);
        expect(isExternalTray(tray, rack: true), isTrue);
      }
      for (final tray in [0, 15, 28, 36, 128, 246, 256]) {
        expect(isExternalTray(tray, rack: true), isFalse, reason: '$tray');
      }
      expect(isExternalTray(null, rack: true), isFalse);
    });

    test('an input feeds hotend 255 - id and is stored as tray 0-8', () {
      expect(
        [255, 254, 253, 252, 251, 250, 249, 248, 247].map(externalHotend),
        [0, 1, 2, 3, 4, 5, 6, 7, 8],
      );
      expect(externalSlotIndex(254), 0);
      expect(externalSlotIndex(255), 1);
      expect(
        [for (var t = 247; t <= 253; t++) externalSlotIndex(t)],
        [
          2, 3, 4, 5, 6, 7, 8, //
        ],
      );
      for (var tray = 247; tray <= 255; tray++) {
        expect(externalTrayId(externalSlotIndex(tray)), tray);
        expect(globalTrayId(amsId: 255, trayId: externalSlotIndex(tray)), tray);
        expect(localSlotOf(tray), (
          amsId: externalHolderUnit,
          trayId: externalSlotIndex(tray),
        ));
      }
      expect(rackExternalLabel(255), 'Ext-1');
      expect(rackExternalLabel(247), 'Ext-9');
      // Out of range as on the web: not folded onto a holder side.
      expect(externalSlotIndex(256), 11);
    });

    test('a rack printer is told by its model where no status says it', () {
      for (final model in ['H3C', 'h3c', ' N10 ']) {
        expect(isRackPrinterModel(model), isTrue, reason: model);
      }
      for (final model in ['H2C', 'X1C', '', null]) {
        expect(isRackPrinterModel(model), isFalse, reason: '$model');
      }
    });

    test('an H3C listing no AMS unit is a rack printer by its model', () {
      final bare = TrayLayout.of(const [], const [254, 255], 'H3C');
      expect(bare.rack, isTrue);
      expect(bare.units, {ams3hUnit: AmsType.zmultiA});
      // Never over a listed unit, and not for another model.
      expect(
        TrayLayout.of(
          const [(id: 0, amsType: AmsType.ams)],
          const [254],
          'H3C',
        ).rack,
        isFalse,
      );
      expect(TrayLayout.of(const [], const [254, 255], 'X2D').rack, isFalse);
      expect(externalTrayId(-1), 244, reason: 'as on the web, not 253');
    });

    test('reporting one of 247-253 makes a rack printer', () {
      expect(TrayLayout.of(const [], const [250]).rack, isTrue);
      expect(TrayLayout.of(const [], const [254, 255]).rack, isFalse);
      expect(TrayLayout.of(const [], const [null]).rack, isFalse);
    });

    test('names the AMS 3H and its slots as the web does', () {
      expect(amsUnitName(32), 'AMS 3H');
      expect(amsUnitName(40, amsType: AmsType.zmultiA), 'AMS 3H');
      expect(amsSlotName(32, 6), 'AMS 3H · 7');
      expect(formatSlotLabel(32, 6, isHt: false), '3H-7');
      expect(formatSlotLabel(1, 2, isHt: false), 'B3');
    });
  });

  group('AMS names', () {
    test('a unit is lettered from its id, as the web letters it', () {
      expect(amsUnitName(0), 'AMS-A');
      expect(amsUnitName(3), 'AMS-D');
      expect(amsUnitName(128), 'HT-A');
      expect(amsUnitName(129), 'HT-B');
      expect(amsUnitName(amsLiteUnit), 'AMS Lite');
    });

    test('a slot adds its 1-based tray, except on a one-tray AMS-HT', () {
      expect(amsSlotName(0, 0), 'AMS-A · 1');
      expect(amsSlotName(1, 3), 'AMS-B · 4');
      expect(amsSlotName(128, 0), 'HT-A');
    });

    test("the user's own unit name replaces the letter only", () {
      expect(amsSlotName(0, 2, unit: 'Dryer box'), 'Dryer box · 3');
      expect(amsSlotName(128, 0, unit: 'Dryer box'), 'Dryer box');
    });

    test('the external holder is not a unit', () {
      expect(() => amsUnitName(externalHolderUnit), throwsAssertionError);
    });
  });

  group('fallbackSpoolTag', () {
    test('matches the server byte for byte', () {
      // Expected values computed by running
      // spoolman_tracking.py::get_fallback_spool_tag_for_slot.
      expect(fallbackSpoolTag('01P00A123456789', 0, 2), '45FACEC400000002');
      expect(fallbackSpoolTag('0948ad5c1800123', 255, 1), 'E6D056A600FF0001');
      expect(fallbackSpoolTag(' x1c-test ', 129, 0), 'B0139FDA00810000');
    });

    test('there is none without a serial', () {
      expect(fallbackSpoolTag(null, 0, 0), isNull);
      expect(fallbackSpoolTag('  ', 0, 0), isNull);
    });
  });

  group('slotOfTray (amsHelpers.ts::trayForSlot)', () {
    test('a unit that reports only some trays names each by its id', () {
      expect(slotOfTray([2], 0), 2);
      expect(slotOfTray([0, 3], 1), 3);
    });

    test('trays reported out of order keep their own slots', () {
      expect(slotOfTray([1, 0, 3, 2], 0), 1);
      expect(slotOfTray([1, 0, 3, 2], 3), 2);
    });

    test('ids that do not tell the trays apart leave it to the position', () {
      expect(slotOfTray([0, 0], 1), 1);
      expect(slotOfTray([null, null, null, null], 2), 2);
      expect(slotOfTray([0, null], 1), 1, reason: 'one missing id is enough');
    });

    test('a single tray is its own slot', () {
      expect(slotOfTray([0], 0), 0);
      expect(slotOfTray([null], 0), 0);
    });
  });
}
