import 'package:bambuddy_mobile/core/models/spool_label.dart';
import 'package:bambuddy_mobile/core/settings/label_print_prefs.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('everything survives a round trip', () {
    final prefs = LabelPrintPrefs(
      monochrome: true,
      destination: LabelDestination.labelPrinter,
      format: SpoolLabelFormat.png,
      dpi: 203,
      fields: {
        SpoolLabelTemplate.box62x29: {
          SpoolLabelField.qr,
          SpoolLabelField.materialNumber,
        },
        SpoolLabelTemplate.box40x30: const {},
      },
      copies: 3,
      cutAtEnd: false,
      cutEvery: 10,
    );

    final back = LabelPrintPrefs.fromJson(prefs.toJson());

    expect(back.monochrome, isTrue);
    expect(back.destination, LabelDestination.labelPrinter);
    expect(back.format, SpoolLabelFormat.png);
    expect(back.dpi, 203);
    expect(back.fieldsFor(SpoolLabelTemplate.box62x29), {
      SpoolLabelField.qr,
      SpoolLabelField.materialNumber,
    });
    // Empty is a choice (no lines at all), not a missing entry.
    expect(back.fieldsFor(SpoolLabelTemplate.box40x30), isEmpty);
    expect(back.copies, 3);
    expect(back.cutAtEnd, isFalse);
    expect(back.cutEvery, 10);
  });

  test('a template never touched prints the default lines', () {
    expect(
      const LabelPrintPrefs().fieldsFor(SpoolLabelTemplate.avery5160),
      SpoolLabelField.defaults,
    );
  });

  test('nothing stored means no destination chosen yet', () {
    expect(LabelPrintPrefs.fromJson(const {}).destination, isNull);
  });

  test('a damaged blob costs one setting, not the sheet', () {
    final back = LabelPrintPrefs.fromJson({
      'monochrome': 'yes',
      'destination': 'carrier-pigeon',
      'format': 'gif',
      'dpi': 72,
      'fields': {
        'box_62x29': ['qr', 'not_a_field', 7],
        'unknown_template': ['qr'],
      },
      'copies': 0,
      'cut_every': -1,
    });

    expect(back.monochrome, isFalse);
    expect(back.destination, isNull);
    expect(back.format, SpoolLabelFormat.pdf);
    expect(back.dpi, 300);
    expect(back.fieldsFor(SpoolLabelTemplate.box62x29), {SpoolLabelField.qr});
    expect(back.copies, 1);
    expect(back.cutEvery, 0);
    expect(back.cutAtEnd, isTrue);
  });

  test('copies above what the server takes fall back to one', () {
    expect(
      LabelPrintPrefs.fromJson({'copies': labelPrinterMaxCopies + 1}).copies,
      1,
    );
    expect(
      LabelPrintPrefs.fromJson({'copies': labelPrinterMaxCopies}).copies,
      labelPrinterMaxCopies,
    );
  });

  group('resolveDestination', () {
    LabelDestination resolve(
      LabelDestination? chosen, {
      bool printerSet = true,
      bool printerFits = true,
      bool png = false,
    }) => LabelPrintPrefs(destination: chosen).resolveDestination(
      printerSet: printerSet,
      printerFits: printerFits,
      png: png,
    );

    test(
      'an unchosen destination is the printer only when it is set up and fits',
      () {
        expect(resolve(null), LabelDestination.labelPrinter);
        expect(resolve(null, printerSet: false), LabelDestination.system);
        expect(resolve(null, printerFits: false), LabelDestination.system);
      },
    );

    test('a choice is kept, also a printer that does not fit', () {
      for (final d in [
        LabelDestination.system,
        LabelDestination.share,
        LabelDestination.save,
      ]) {
        expect(resolve(d), d);
      }
      expect(
        resolve(LabelDestination.labelPrinter, printerFits: false),
        LabelDestination.labelPrinter,
      );
    });

    test('a removed label printer falls back to the print dialog', () {
      expect(
        resolve(LabelDestination.labelPrinter, printerSet: false),
        LabelDestination.system,
      );
    });

    test('a PNG is shared unless saving was chosen', () {
      expect(resolve(null, png: true), LabelDestination.share);
      expect(
        resolve(LabelDestination.system, png: true),
        LabelDestination.share,
      );
      expect(
        resolve(LabelDestination.labelPrinter, png: true),
        LabelDestination.share,
      );
      expect(resolve(LabelDestination.save, png: true), LabelDestination.save);
    });
  });

  group('SettingsRepository', () {
    Future<SettingsRepository> open([
      Map<String, Object> stored = const {},
    ]) async {
      SharedPreferences.setMockInitialValues(stored);
      return SettingsRepository(await SharedPreferences.getInstance());
    }

    test('nothing stored reads as the defaults', () async {
      final prefs = (await open()).loadLabelPrintPrefs();
      expect(prefs.destination, isNull);
      expect(prefs.cutAtEnd, isTrue);
    });

    test('what was saved is read back', () async {
      final repo = await open();
      await repo.saveLabelPrintPrefs(
        const LabelPrintPrefs(monochrome: true, copies: 4, cutEvery: 3),
      );
      final back = repo.loadLabelPrintPrefs();
      expect(back.monochrome, isTrue);
      expect(back.copies, 4);
      expect(back.cutEvery, 3);
    });

    test('a corrupt blob reads as the defaults', () async {
      final repo = await open({'label_print_prefs': '{not json'});
      expect(repo.loadLabelPrintPrefs().copies, 1);
    });
  });
}
