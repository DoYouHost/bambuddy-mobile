import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/notifications/hms_catalog.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  group('HmsError code parsing', () {
    test('składa pełny ecode z attr + hex code', () {
      // Realna ramka X2D: attr=83887616 (0x05000600), code "0x20070".
      const e = HmsError(code: '0x20070', attr: 83887616, module: 5);
      expect(e.ecode, '0500060000020070');
      expect(e.displayCode, '0500-0600-0002-0070');
    });

    test('bez attr nie składa ecode, displayCode normalizuje separatory', () {
      const e = HmsError(code: '0500_0100');
      expect(e.ecode, isNull);
      expect(e.displayCode, '0500-0100');
    });

    test('pusty kod → znak zapytania', () {
      expect(const HmsError().displayCode, '?');
    });
  });

  group('hmsHumanText', () {
    test('wiadomość z serwera ma pierwszeństwo', () {
      const e = HmsError(code: '0x1', message: 'Filament runout detected');
      expect(hmsHumanText(e, l10n: l10n), 'Filament runout detected');
    });

    test('opis z katalogu, gdy brak wiadomości', () {
      const e = HmsError(code: '0x20070', attr: 83887616);
      expect(
        hmsHumanText(e, description: 'Nozzle clog', l10n: l10n),
        'Nozzle clog',
      );
    });

    test('fallback: poziom · moduł (kod) gdy nic nie znane', () {
      // severity 2 = serious, module 7 = AMS.
      const e = HmsError(code: '0x20070', attr: 83887616, severity: 2, module: 7);
      expect(
        hmsHumanText(e, l10n: l10n),
        'Serious · AMS (0500-0600-0002-0070)',
      );
    });

    test('fallback pomija nieznany poziom/moduł', () {
      // severity 6 (nieznany), module 5 = mainboard.
      const e = HmsError(code: '0x20070', attr: 83887616, severity: 6, module: 5);
      expect(hmsHumanText(e, l10n: l10n), 'mainboard (0500-0600-0002-0070)');
    });

    test('sam kod, gdy brak poziomu i modułu', () {
      const e = HmsError(code: '0x20070', attr: 83887616);
      expect(hmsHumanText(e, l10n: l10n), '0500-0600-0002-0070');
    });
  });

  group('hmsIsDisplayable', () {
    test('wewnętrzny wpis (sev 6, brak opisu/wiadomości) → ukryty', () {
      const e = HmsError(code: '0x20070', attr: 83887616, module: 5, severity: 6);
      expect(hmsIsDisplayable(e), isFalse);
    });

    test('znany poziom (1–4) → pokazany', () {
      expect(hmsIsDisplayable(const HmsError(code: 'x', severity: 1)), isTrue);
      expect(hmsIsDisplayable(const HmsError(code: 'x', severity: 4)), isTrue);
    });

    test('wiadomość z serwera → pokazany mimo dziwnego severity', () {
      const e = HmsError(code: 'x', severity: 6, message: 'Filament runout');
      expect(hmsIsDisplayable(e), isTrue);
    });

    test('opis z katalogu → pokazany mimo dziwnego severity', () {
      const e = HmsError(code: 'x', severity: 6);
      expect(hmsIsDisplayable(e, description: 'Nozzle clog'), isTrue);
    });
  });

  group('hmsWikiUrl', () {
    test('buduje link z podkreśleniami dla pełnego kodu', () {
      const e = HmsError(code: '0x20070', attr: 83887616);
      expect(
        hmsWikiUrl(e),
        'https://wiki.bambulab.com/en/x1/troubleshooting/hmscode/0500_0600_0002_0070',
      );
    });

    test('null gdy nie da się złożyć pełnego kodu', () {
      expect(hmsWikiUrl(const HmsError(code: '0500_0100')), isNull);
    });
  });
}
