import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/notifications/hms_catalog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The bundled catalog against real server payloads: whether a code can be
/// named is decided by an asset, so a stubbed resolver proves nothing about
/// what a user actually sees.
///
/// Codes below come from `fixtures/captured/printer_status.json` — a real
/// `GET /printers/{id}/status` capture, hence the odd trio: one code missing
/// from the catalog and two that share a short code with different meanings.
void main() {
  late HmsCatalog en;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    en = HmsCatalog();
    await en.load(const Locale('en'));
    // The loader swallows a missing/corrupt asset and leaves an empty table, so
    // without this guard every expectation below would pass by saying "unknown".
    expect(
      en.describe(const HmsError(code: '0x1000a', attr: 50331904)),
      isNotNull,
      reason: 'assets/hms/hms_en.json did not load — the rest is vacuous',
    );
  });

  /// The three errors that printer really reported, in fixture order.
  List<HmsError> capturedErrors() {
    final status = PrinterStatus.fromJson(
        readFixture('captured/printer_status.json') as Map<String, dynamic>);
    final errors = status.hmsErrors;
    expect(errors, hasLength(3));
    return errors!;
  }

  group('real capture through the real catalog', () {
    test('the uncataloged code is hidden, the two known ones are shown', () {
      final [unknown, heatbed, chamber] = capturedErrors();

      // 0500_0600_0002_0070 — absent from BambuStudio's device_hms table, so
      // the app has nothing to say about it and therefore says nothing.
      expect(unknown.ecode, '0500060000020070');
      expect(en.describe(unknown), isNull);
      expect(hmsIsDisplayable(unknown, description: en.describe(unknown)),
          isFalse);
      expect(hmsLabel(unknown, description: en.describe(unknown)), isNull);

      for (final e in [heatbed, chamber]) {
        final description = en.describe(e);
        expect(description, isNotNull, reason: '${e.ecode} should resolve');
        expect(hmsIsDisplayable(e, description: description), isTrue);
        expect(hmsHumanText(e, description: description), description);
      }
    });

    test('the module byte alone never speaks for a code', () {
      // Both known codes report `module: 3`, and so does the hidden one's
      // family — module is not what makes an error nameable.
      final [unknown, heatbed, _] = capturedErrors();
      expect(unknown.module, 5);
      expect(heatbed.module, 3);
      expect(hmsIsDisplayable(unknown), isFalse);
      expect(hmsIsDisplayable(heatbed), isFalse,
          reason: 'without the catalog even a real fault stays unnamed');
    });

    test('severity 1 from the server is not evidence of anything', () {
      // Both codes the capture marks `severity: 1` — bambuddy computes that
      // from `(attr >> 8) & 0xF`, i.e. BambuStudio's part_id. One of them is a
      // real heatbed fault, and the field is what used to print "Fatal".
      final [_, heatbed, chamber] = capturedErrors();
      expect([heatbed.severity, chamber.severity], [1, 1]);
      for (final e in [heatbed, chamber]) {
        expect(hmsIsDisplayable(e), isFalse);
        expect(hmsIsDisplayable(e, description: en.describe(e)), isTrue);
      }
    });
  });

  group('lookup granularity', () {
    test('codes sharing a short code do not share a meaning', () {
      // 0300_000A twice, differing only in part_id (0x01 vs 0x91): the heated
      // bed and chamber heater 1. This is why the lookup is the full 16-hex
      // code and must never fall back to the short form — 660 of the 801 short
      // codes in the table cover several parts with different text.
      final [_, heatbed, chamber] = capturedErrors();
      expect(heatbed.ecode!.substring(12), chamber.ecode!.substring(12));
      expect(en.describe(heatbed), isNot(en.describe(chamber)));
      expect(en.describe(heatbed), contains('heatbed'));
      expect(en.describe(chamber), contains('chamber heater 1'));
    });

    test('a code whose part_id is not in the table stays unknown', () {
      // 0704_2200_0002_0025 is catalogued ("AMS E slot 3 feed resistance");
      // the same code from part 0x99 is not, and must not borrow that text.
      const catalogued = HmsError(code: '0x20025', attr: 0x07042200);
      const otherPart = HmsError(code: '0x20025', attr: 0x07049900);
      expect(en.describe(catalogued), contains('AMS'));
      expect(en.describe(otherPart), isNull);
      expect(hmsIsDisplayable(otherPart, description: en.describe(otherPart)),
          isFalse);
    });

    test('an error with no attr cannot be looked up at all', () {
      const noAttr = HmsError(code: '0x1000a');
      expect(noAttr.ecode, isNull);
      expect(en.describe(noAttr), isNull);
      expect(hmsIsDisplayable(noAttr, description: en.describe(noAttr)), isFalse);
    });
  });

  group('the tester report', () {
    test('an X2D status message never renders as a fatal mainboard fault', () {
      // Reported 2026-07-29: healthy X2D, printer/Bambu Studio/bambuddy all
      // fine, the app card red. Module 5 + the severity the server derives from
      // part_id used to compose "Fatal · mainboard" for a code we cannot name.
      const reported =
          HmsError(code: '0x20070', attr: 83887616, module: 5, severity: 1);
      final description = en.describe(reported);
      expect(description, isNull);
      expect(hmsIsDisplayable(reported, description: description), isFalse);
      expect(hmsIsNotifiable(reported, description: description), isFalse);
      expect(hmsLabel(reported, description: description), isNull);
      expect(hmsHumanText(reported, description: description),
          '0500-0600-0002-0070');
    });
  });

  group('locales', () {
    test('pl describes the same codes in Polish and keeps unknowns unknown',
        () async {
      final pl = HmsCatalog();
      await pl.load(const Locale('pl'));
      final [unknown, heatbed, _] = capturedErrors();
      expect(pl.describe(heatbed), contains('stołu'));
      expect(pl.describe(unknown), isNull);
      expect(hmsIsDisplayable(unknown, description: pl.describe(unknown)),
          isFalse);
    });

    test('an unsupported locale falls back to the English table', () async {
      final de = HmsCatalog();
      await de.load(const Locale('de'));
      final [_, heatbed, _] = capturedErrors();
      expect(de.describe(heatbed), en.describe(heatbed));
    });
  });
}
