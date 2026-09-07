import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/notifications/hms_catalog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The bundled catalog against real server payloads: whether a code can be
/// named is decided by an asset, so a stubbed resolver proves nothing about
/// what a user actually sees.
///
/// The app names the faults bambuddy names and no others: the `print_error`
/// channel — what pauses or kills a print and offers the user a button. The
/// `hms[]` channel (component diagnostics) is deliberately unnamed, which is
/// what `fixtures/printer_status_hms.json` below is evidence of: three real
/// errors from a live printer, none of which bambuddy would show either.
///
/// That fixture lives outside `captured/` because it is **irreproducible**. HMS
/// errors belong to a print job, and this printer stopped reporting these the
/// moment it reconnected; `captured/` is untracked (see
/// `test/fixtures/README.md`), so anything left there exists only on the
/// machine that captured it.
void main() {
  late HmsCatalog en;

  /// A fault as the server builds it from the 32-bit `print_error` field
  /// (`bambu_mqtt.py::_update_state`): `attr` holds the whole value, `code` its
  /// low half, `full_code` the 8-hex key.
  HmsError printError(int value, {int severity = 3, String? description}) =>
      HmsError(
        code: '0x${(value & 0xFFFF).toRadixString(16)}',
        attr: value,
        module: (value >> 24) & 0xFF,
        severity: severity,
        fullCode: value.toRadixString(16).padLeft(8, '0').toUpperCase(),
        description: description,
      );

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    en = HmsCatalog();
    await en.load(const Locale('en'));
    // The loader swallows a missing/corrupt asset and leaves an empty table, so
    // without this guard every expectation below would pass by saying "unknown".
    expect(
      en.describe(printError(0x03008004)),
      isNotNull,
      reason:
          'assets/hms/print_errors_en.json did not load — the rest is vacuous',
    );
  });

  /// The three errors that printer really reported, in fixture order.
  List<HmsError> capturedErrors() {
    final status = PrinterStatus.fromJson(
      readFixture('printer_status_hms.json') as Map<String, dynamic>,
    );
    final errors = status.hmsErrors;
    expect(errors, hasLength(3));
    return errors!;
  }

  group('the print errors a user is meant to act on', () {
    test('the codes that pause a print resolve to Bambu\'s own text', () {
      expect(en.describe(printError(0x03008004)), contains('Filament ran out'));
      expect(en.describe(printError(0x0300800F)), contains('door'));
      expect(en.describe(printError(0x03008011)), contains('build plate'));
      expect(en.describe(printError(0x07008011)), contains('AMS'));
    });

    test('a described error is shown, and shown by its description', () {
      final runout = printError(0x03008004);
      final description = en.describe(runout);
      expect(hmsIsDisplayable(runout, description: description), isTrue);
      expect(hmsLabel(runout, description: description), description);
      expect(hmsHumanText(runout, description: description), description);
    });

    test('the code renders in the two-group form the printer screen uses', () {
      expect(printError(0x03008004).displayCode, '0300-8004');
    });

    test('a print error outside bambuddy\'s table stays unnamed', () {
      final unknown = printError(0x0300FFFF);
      expect(en.describe(unknown), isNull);
      expect(
        hmsIsDisplayable(unknown, description: en.describe(unknown)),
        isFalse,
      );
    });

    test('a blank full code is no identifier at all', () {
      // `HMSError.full_code` is a plain `str` defaulting to `""` server-side, so
      // "no identifier" reaches the app as an empty string as readily as as a
      // missing key. Both must land on null: the route's regex wants 8 or 16 hex
      // digits and answers 422 to a blank, and the notification payload built
      // around one parses back to nothing.
      final blank = HmsError.fromJson(const {
        'code': '0x8004',
        'attr': 0x03008004,
        'full_code': '',
        'job_id': '',
        'actions': ['RESUME_PRINTING'],
      });
      expect(blank.fullCode, isNull);
      expect(blank.jobId, isNull);
      // Still nameable — the short form does not depend on the full code.
      expect(en.describe(blank), contains('Filament ran out'));
    });

    test('a server too old to send full_code still names the fault', () {
      // Pre-0.2.4.8 payload: no `full_code`, so the lookup falls back to the
      // short form the server itself composes. Actions are what such a server
      // cannot offer — the description is not.
      const legacy = HmsError(code: '0x8004', attr: 0x03008004, module: 3);
      expect(legacy.fullCode, isNull);
      expect(legacy.shortCode, '0300_8004');
      expect(en.describe(legacy), contains('Filament ran out'));
    });

    test('the fault that explains a silent printer is carried by full code', () {
      // 0500_0500_0001_0007 — "MQTT command verification failed". An hms[]-channel
      // code, kept because it is the one that explains why nothing the app sends
      // arrives. Its meaning lives in the bits the short form discards, so it
      // resolves by the 16-hex key and its short form must NOT.
      const verifyFailed = HmsError(
        code: '0x10007',
        attr: 0x05000500,
        fullCode: '0500050000010007',
      );
      expect(en.describe(verifyFailed), contains('rejected a command'));
      expect(verifyFailed.shortCode, '0500_0007');
      expect(
        en.describe(const HmsError(code: '0x7', attr: 0x05000500)),
        isNull,
      );
    });
  });

  group('real capture through the real catalog', () {
    test('component diagnostics stay silent — bambuddy does not show them', () {
      for (final e in capturedErrors()) {
        final description = en.describe(e);
        expect(description, isNull, reason: '${e.fullCode} is an hms[] fault');
        expect(hmsIsDisplayable(e, description: description), isFalse);
        expect(hmsIsNotifiable(e, description: description), isFalse);
        expect(hmsLabel(e, description: description), isNull);
      }
    });

    test('neither module nor severity can make a code speak', () {
      final [unknown, heatbed, _] = capturedErrors();
      expect(unknown.module, 5);
      expect(heatbed.module, 3);
      expect([unknown.severity, heatbed.severity], [6, 1]);
      expect(hmsIsDisplayable(unknown), isFalse);
      expect(hmsIsDisplayable(heatbed), isFalse);
    });
  });

  group('lookup granularity', () {
    test('an error with neither full code nor attr cannot be looked up', () {
      const noAttr = HmsError(code: '0x1000a');
      expect(noAttr.shortCode, isNull);
      expect(en.describe(noAttr), isNull);
      expect(
        hmsIsDisplayable(noAttr, description: en.describe(noAttr)),
        isFalse,
      );
    });

    test('an unknown action-bearing fault is still not shown', () {
      // bambuddy keeps an uncataloged error when the firmware offers actions;
      // the app does not (see hmsIsDisplayable). A card headed by bare hex is
      // not something to hand a user a button on.
      final unknown = HmsError(
        code: '0xffff',
        attr: 0x0300FFFF,
        fullCode: '0300FFFF',
        actions: const ['RESUME_PRINTING'],
      );
      expect(en.describe(unknown), isNull);
      expect(
        hmsIsDisplayable(unknown, description: en.describe(unknown)),
        isFalse,
      );
    });
  });

  group('the sentence the server attaches to a fault', () {
    // `HMSError.description` (hms_errors.py::describe_fault) is English only, so
    // it ranks UNDER the bundled table rather than over it.
    //
    // At this server version it names nothing the assets cannot name: the assets
    // are generated FROM that table (tool/fetch_print_error_catalog.py), then
    // given Bambu's untruncated text and a Polish half. The field earns its
    // place when the two drift apart — a server that learned a code before the
    // app shipped an asset for it, which is the ordinary state of an install
    // whose server updates more often than its phone.

    test('names a fault the bundled table has no word for', () {
      const text = 'The left hotend is not installed.';
      final e = printError(0x0300FFFF, description: text);
      expect(
        en.describe(printError(0x0300FFFF)),
        isNull,
        reason: 'premise: this code is outside the bundled table',
      );
      expect(en.describe(e), text);
      expect(hmsIsDisplayable(e, description: en.describe(e)), isTrue);
      expect(hmsLabel(e, description: en.describe(e)), text);
    });

    test('the bundled table outranks it, so Polish stays Polish', () async {
      final pl = HmsCatalog();
      await pl.load(const Locale('pl'));
      const english = 'Filament ran out. Please load new filament.';
      final runout = printError(0x03008004, description: english);
      expect(pl.describe(runout), contains('filament'));
      expect(pl.describe(runout), isNot(english));
    });

    test(
      'a server too old to send it leaves the code as unknown as before',
      () {
        // The whole compatibility claim in one line: absent field = today.
        final legacy = HmsError.fromJson(const {
          'code': '0xffff',
          'attr': 0x0300FFFF,
          'full_code': '0300FFFF',
        });
        expect(legacy.description, isNull);
        expect(en.describe(legacy), isNull);
        expect(
          hmsIsDisplayable(legacy, description: en.describe(legacy)),
          isFalse,
        );
      },
    );

    test('an empty description is no text, not a fault without text', () {
      // Server-side default is `None`, but a regenerated catalogue could hold a
      // blank entry, and blank must not become a card headed by a bare code.
      final blank = HmsError.fromJson(const {
        'code': '0xffff',
        'attr': 0x0300FFFF,
        'full_code': '0300FFFF',
        'description': '   ',
      });
      expect(blank.description, isNull);
      expect(hmsIsDisplayable(blank, description: en.describe(blank)), isFalse);
    });

    test('it does not lift the severity floor on notifications', () {
      // Displayable and notifiable are different gates: severity 1 is bambuddy's
      // "informational", and a server sentence does not make it worth waking
      // anybody for.
      final quiet = printError(0x0300FFFF, severity: 1, description: 'Idle.');
      expect(hmsIsDisplayable(quiet, description: en.describe(quiet)), isTrue);
      expect(hmsIsNotifiable(quiet, description: en.describe(quiet)), isFalse);
    });
  });

  group('the tester report', () {
    test('an X2D status message never renders as a fatal mainboard fault', () {
      // Reported 2026-07-29: healthy X2D, printer/Bambu Studio/bambuddy all
      // fine, the app card red. Module 5 + the severity the server derives from
      // part_id used to compose "Fatal · mainboard" for a code we cannot name.
      const reported = HmsError(
        code: '0x20070',
        attr: 83887616,
        module: 5,
        severity: 1,
      );
      final description = en.describe(reported);
      expect(description, isNull);
      expect(hmsIsDisplayable(reported, description: description), isFalse);
      expect(hmsIsNotifiable(reported, description: description), isFalse);
      expect(hmsLabel(reported, description: description), isNull);
      expect(
        hmsHumanText(reported, description: description),
        '0500-0600-0002-0070',
      );
    });
  });

  group("the sentence the server attaches to a fault", () {
    test('a code the bundled table cannot name is named by the server', () {
      // 1.2.5.4+ (#2926) sends its own catalogue's sentence with the fault. It
      // reaches the app as the fallback behind the bundled table, which is the
      // difference between a named card and one hmsIsDisplayable hides.
      final described = HmsError.fromJson(const {
        'code': '0x10007',
        'attr': 0x05000500,
        'severity': 2,
        'full_code': '05000500FFFF0007',
        'description': 'The AMS lid is open',
      });

      expect(en.describe(described), 'The AMS lid is open');
      expect(
        hmsIsDisplayable(described, description: en.describe(described)),
        isTrue,
      );
      expect(
        hmsIsNotifiable(described, description: en.describe(described)),
        isTrue,
      );
    });

    test('the bundled table wins, because it is the localized one', () async {
      // The server ships one language; the app ships two. A code both know
      // must read in the user's language, so the wire sentence is a fallback
      // and never an override.
      final pl = HmsCatalog();
      await pl.load(const Locale('pl'));
      final runout = HmsError.fromJson(const {
        'code': '0x8004',
        'attr': 0x03008004,
        'full_code': '03008004',
        'description': 'Filament ran out',
      });

      expect(pl.describe(runout), contains('filament'));
      expect(pl.describe(runout), isNot('Filament ran out'));
    });

    test('an empty description is no text, and hides the fault as before', () {
      // `description` is `str | None` server-side; a blank has to fold into
      // null the same way `full_code` does, or an unnameable fault turns into
      // a card headed by a bare hex code.
      final blank = HmsError.fromJson(const {
        'code': '0xffff',
        'attr': 0x0300FFFF,
        'full_code': '0300FFFF',
        'description': '   ',
      });

      expect(blank.description, isNull);
      expect(en.describe(blank), isNull);
      expect(hmsIsDisplayable(blank, description: en.describe(blank)), isFalse);
    });
  });

  group('locales', () {
    test(
      'pl describes the same codes in Polish and keeps unknowns unknown',
      () async {
        final pl = HmsCatalog();
        await pl.load(const Locale('pl'));
        expect(pl.describe(printError(0x03008004)), contains('filament'));
        expect(pl.describe(printError(0x0300FFFF)), isNull);
      },
    );

    test('an unsupported locale falls back to the English table', () async {
      final de = HmsCatalog();
      await de.load(const Locale('de'));
      expect(
        de.describe(printError(0x03008004)),
        en.describe(printError(0x03008004)),
      );
    });
  });
}
