import 'package:bambuddy_mobile/core/models/embedded_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// The gate for "slice as designed". Both halves of it are the point: whether
/// the *server* honours `use_embedded_settings`, and whether *this* printer is
/// the one the design targets.
void main() {
  Map<String, dynamic> plates({
    Object? printer = 'Bambu Lab X1 Carbon 0.4 nozzle',
    Object? process = '0.20mm Standard @BBL X1C',
    bool withDesignOverrides = true,
  }) =>
      {
        'file_id': 45,
        'plates': const [],
        'embedded_printer': printer,
        'embedded_process': process,
        if (withDesignOverrides) 'design_overrides': const [],
      };

  group('server support', () {
    test('is read from the design_overrides key, empty list and all', () {
      // Server #2622 added the key and #2611 (use_embedded_settings) came
      // before it, so the key being there proves the field is honoured. Its
      // contents cannot: a file whose designer changed nothing answers [].
      final settings = EmbeddedSettings.fromJson(plates());

      expect(settings.serverSupportsAsDesigned, isTrue);
      expect(settings.isAvailable, isTrue);
    });

    test('is absent when the response predates the key', () {
      // The embedded_printer/process pair has been in this response since
      // server #1325 (v0.2.4.3), so a server can name the design's printer and
      // still drop use_embedded_settings without a word — which is exactly the
      // switch that appears to work and changes nothing.
      final settings =
          EmbeddedSettings.fromJson(plates(withDesignOverrides: false));

      expect(settings.printer, isNotNull);
      expect(settings.serverSupportsAsDesigned, isFalse);
      expect(settings.isAvailable, isFalse,
          reason: 'naming the printer is not the same as honouring the field');
    });
  });

  group('the file', () {
    test('offers nothing when it carries no embedded profile', () {
      // An STL or a plain-model 3MF: the server ignores the field for these.
      final settings = EmbeddedSettings.fromJson(
          plates(printer: null, process: null));

      expect(settings.isAvailable, isFalse);
      expect(settings.matchesPrinter('Bambu Lab X1 Carbon 0.4 nozzle'), isFalse);
    });

    test('treats a blank name as no name', () {
      final settings =
          EmbeddedSettings.fromJson(plates(printer: '   ', process: ''));

      expect(settings.printer, isNull);
      expect(settings.isAvailable, isFalse);
    });

    test('survives a printer field that is not a string', () {
      expect(EmbeddedSettings.fromJson(plates(printer: 42)).printer, isNull);
    });
  });

  group('printer match', () {
    final settings = EmbeddedSettings.fromJson(plates());

    test('accepts the same preset regardless of case, padding or the # prefix',
        () {
      // All three come off the same preset namespace; a modified preset carries
      // the "# " marker the web strips the same way.
      expect(settings.matchesPrinter('Bambu Lab X1 Carbon 0.4 nozzle'), isTrue);
      expect(settings.matchesPrinter('bambu lab x1 carbon 0.4 NOZZLE'), isTrue);
      expect(settings.matchesPrinter('# Bambu Lab X1 Carbon 0.4 nozzle'), isTrue);
      expect(settings.matchesPrinter('  Bambu Lab X1 Carbon 0.4 nozzle  '),
          isTrue);
    });

    test('refuses another model, and another nozzle on the same model', () {
      // The gate is load-bearing: the embedded settings lay the model out for
      // the bed they were made for, and this path has no re-targeting step.
      expect(settings.matchesPrinter('Bambu Lab P1S 0.4 nozzle'), isFalse);
      expect(settings.matchesPrinter('Bambu Lab X1 Carbon 0.6 nozzle'), isFalse);
    });

    test('refuses when nothing is picked yet', () {
      expect(settings.matchesPrinter(null), isFalse);
    });

    test('never matches while the server cannot honour it', () {
      final unsupported =
          EmbeddedSettings.fromJson(plates(withDesignOverrides: false));

      expect(unsupported.matchesPrinter('Bambu Lab X1 Carbon 0.4 nozzle'),
          isFalse);
    });
  });

  test('none is the answer that hides the switch', () {
    expect(EmbeddedSettings.none.isAvailable, isFalse);
    expect(EmbeddedSettings.none.matchesPrinter('anything'), isFalse);
  });
}
