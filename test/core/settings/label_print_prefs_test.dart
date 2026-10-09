import 'package:bambuddy_mobile/core/models/spool_label.dart';
import 'package:bambuddy_mobile/core/settings/label_print_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
