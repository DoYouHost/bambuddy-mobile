import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/notifications/hms_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HmsError code parsing', () {
    test('composes the full ecode from attr + hex code', () {
      // Real X2D frame: attr=83887616 (0x05000600), code "0x20070".
      const e = HmsError(code: '0x20070', attr: 83887616, module: 5);
      expect(e.ecode, '0500060000020070');
      expect(e.displayCode, '0500-0600-0002-0070');
    });

    test('no attr means no ecode; displayCode normalizes separators', () {
      const e = HmsError(code: '0500_0100');
      expect(e.ecode, isNull);
      expect(e.displayCode, '0500-0100');
    });

    test('empty code renders as a question mark', () {
      expect(const HmsError().displayCode, '?');
    });
  });

  group('hmsHumanText', () {
    test('the server message wins', () {
      const e = HmsError(code: '0x1', message: 'Filament runout detected');
      expect(hmsHumanText(e), 'Filament runout detected');
    });

    test('catalog description when there is no message', () {
      const e = HmsError(code: '0x20070', attr: 83887616);
      expect(hmsHumanText(e, description: 'Nozzle clog'), 'Nozzle clog');
    });

    test('bare code when nothing is known — nothing is composed from '
        'severity/module', () {
      const e = HmsError(code: '0x20070', attr: 83887616, severity: 1, module: 5);
      expect(hmsLabel(e), isNull);
      expect(hmsHumanText(e), '0500-0600-0002-0070');
    });
  });

  group('hmsIsDisplayable', () {
    test('unrecognized code stays hidden whatever severity says', () {
      // The X2D report: bambuddy derives severity from `(attr >> 8) & 0xF`, so a
      // status message arrives as level 1 / module 5 and used to render as
      // "Fatal · mainboard" on a card while the printer was healthy.
      const fatalish = HmsError(code: '0x20070', attr: 83887616, module: 5, severity: 1);
      expect(hmsIsDisplayable(fatalish), isFalse);
      for (final severity in [1, 2, 3, 4, 6]) {
        expect(
          hmsIsDisplayable(HmsError(code: 'x', severity: severity)),
          isFalse,
          reason: 'severity $severity is not a description',
        );
      }
    });

    test('server message → shown', () {
      const e = HmsError(code: 'x', severity: 6, message: 'Filament runout');
      expect(hmsIsDisplayable(e), isTrue);
    });

    test('catalog description → shown', () {
      const e = HmsError(code: 'x', severity: 6);
      expect(hmsIsDisplayable(e, description: 'Nozzle clog'), isTrue);
    });

    test('blank message/description does not count as recognized', () {
      expect(hmsIsDisplayable(const HmsError(code: 'x', message: '  ')), isFalse);
      expect(hmsIsDisplayable(const HmsError(code: 'x'), description: ' '), isFalse);
    });
  });

  group('hmsIsNotifiable', () {
    test('known severity without a description → no alert (bambuddy parity)', () {
      expect(hmsIsNotifiable(const HmsError(code: 'x', severity: 1)), isFalse);
      expect(hmsIsNotifiable(const HmsError(code: 'x', severity: 4)), isFalse);
    });

    test('catalog description → alert', () {
      const e = HmsError(code: 'x', severity: 6);
      expect(hmsIsNotifiable(e, description: 'Nozzle clog'), isTrue);
    });

    test('severity 1 with a description → no alert (bambuddy drops sev < 2)', () {
      const e = HmsError(code: 'x', severity: 1);
      expect(hmsIsNotifiable(e, description: 'Some status message'), isFalse);
    });

    test('server message → alert', () {
      const e = HmsError(code: 'x', message: 'Filament runout');
      expect(hmsIsNotifiable(e), isTrue);
    });
  });

  group('hmsWikiUrl', () {
    test('builds an underscore-separated link for a full code', () {
      const e = HmsError(code: '0x20070', attr: 83887616);
      expect(
        hmsWikiUrl(e),
        'https://wiki.bambulab.com/en/x1/troubleshooting/hmscode/0500_0600_0002_0070',
      );
    });

    test('null when the full code cannot be composed', () {
      expect(hmsWikiUrl(const HmsError(code: '0500_0100')), isNull);
    });
  });
}
