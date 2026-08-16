import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/notifications/hms_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

/// Everything a server can put in the fields that are NOT human text. None of
/// them may ever make an error displayable on its own — that regression shipped
/// once as a red "Fatal · mainboard" card on a healthy X2D.
const _severities = <int?>[null, 0, 1, 2, 3, 4, 5, 6, 15];
const _modules = <int?>[null, 0x03, 0x05, 0x07, 0x08, 0x0C, 0x18, 0xFF];

/// Text that carries no information: absent, empty, whitespace only.
const _blanks = <String?>[null, '', '   '];

/// Code shapes the wire actually uses, with what each one must render as.
const _codes = <({String? code, int? attr, String displayed})>[
  (code: '0x20070', attr: 83887616, displayed: '0500-0600-0002-0070'),
  (code: '0500_0100', attr: null, displayed: '0500-0100'),
  (code: null, attr: null, displayed: '?'),
];

/// A code and nothing else: hex digits, separators, or the empty-code marker.
/// Any word composed from `severity`/`module` breaks this.
final _codeOnly = RegExp(r'^[0-9A-F?-]+$');

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

  group('displayable means nameable — swept over every non-text field', () {
    test('no severity/module combination makes an unnamed error displayable',
        () {
      for (final c in _codes) {
        for (final sev in _severities) {
          for (final mod in _modules) {
            for (final message in _blanks) {
              for (final description in _blanks) {
                final e = HmsError(
                  code: c.code,
                  attr: c.attr,
                  severity: sev,
                  module: mod,
                  message: message,
                );
                final where = 'code=${c.code} sev=$sev mod=$mod '
                    'message=${message?.length} desc=${description?.length}';
                expect(
                  hmsIsDisplayable(e, description: description),
                  isFalse,
                  reason: 'displayed with nothing to say it: $where',
                );
                expect(
                  hmsLabel(e, description: description),
                  isNull,
                  reason: 'label invented from severity/module: $where',
                );
                // The one text an unnamed error may produce is its own code —
                // reached only by callers that bypass the gate.
                final text = hmsHumanText(e, description: description);
                expect(text, c.displayed, reason: where);
                expect(
                  text,
                  matches(_codeOnly),
                  reason: 'words composed for an unnamed error: $where',
                );
              }
            }
          }
        }
      }
    });

    test('text from either source makes it displayable, whatever else says', () {
      for (final c in _codes) {
        for (final sev in _severities) {
          for (final mod in _modules) {
            final base = HmsError(code: c.code, attr: c.attr, severity: sev, module: mod);
            final fromMessage = HmsError(
              code: c.code,
              attr: c.attr,
              severity: sev,
              module: mod,
              message: 'Filament runout',
            );
            final where = 'code=${c.code} sev=$sev mod=$mod';
            expect(hmsIsDisplayable(fromMessage), isTrue, reason: where);
            expect(hmsLabel(fromMessage), 'Filament runout', reason: where);
            expect(
              hmsIsDisplayable(base, description: 'Nozzle clog'),
              isTrue,
              reason: where,
            );
            expect(hmsLabel(base, description: 'Nozzle clog'), 'Nozzle clog',
                reason: where);
          }
        }
      }
    });

    test('anything worth notifying is worth displaying', () {
      for (final c in _codes) {
        for (final sev in _severities) {
          for (final text in [...(_blanks), 'Nozzle clog']) {
            for (final viaMessage in [true, false]) {
              final e = HmsError(
                code: c.code,
                attr: c.attr,
                severity: sev,
                message: viaMessage ? text : null,
              );
              final description = viaMessage ? null : text;
              if (!hmsIsNotifiable(e, description: description)) continue;
              expect(
                hmsIsDisplayable(e, description: description),
                isTrue,
                reason: 'notified but hidden from the card: sev=$sev '
                    'text=${text?.length} viaMessage=$viaMessage',
              );
            }
          }
        }
      }
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

    test('a print error links to the index, not to a made-up code page', () {
      // Bambu publishes no per-code page for the print_error channel, and the
      // 16-hex code this class could compose out of its 32-bit attr would name
      // a different fault — so the link goes where bambuddy's own does.
      const e = HmsError(code: '0x8004', attr: 0x03008004, fullCode: '03008004');
      expect(hmsWikiUrl(e), 'https://wiki.bambulab.com/en/hms/home');
    });

    test('the index also covers a code too incomplete to link precisely', () {
      expect(hmsWikiUrl(const HmsError(code: '0500_0100')),
          'https://wiki.bambulab.com/en/hms/home');
    });
  });
}
