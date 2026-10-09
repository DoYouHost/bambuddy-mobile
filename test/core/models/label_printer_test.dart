import 'package:bambuddy_mobile/core/models/label_printer.dart';
import 'package:bambuddy_mobile/core/models/spool_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeLabelPrinterUrl', () {
    test('a bare IP gets http and the default port', () {
      expect(
        normalizeLabelPrinterUrl('192.168.1.40'),
        'http://192.168.1.40:8000',
      );
    });

    test('keeps an explicit port, including a default one', () {
      expect(normalizeLabelPrinterUrl('pi:9000'), 'http://pi:9000');
      expect(normalizeLabelPrinterUrl('http://pi:80'), 'http://pi:80');
    });

    test('drops a path and trailing slashes', () {
      expect(
        normalizeLabelPrinterUrl(' http://pi:8000/info/ '),
        'http://pi:8000',
      );
    });

    test('keeps https', () {
      expect(normalizeLabelPrinterUrl('https://pi'), 'https://pi:8000');
      expect(normalizeLabelPrinterUrl('http://pi:80'), 'http://pi:80');
    });

    test('empty or hostless input gives an empty string', () {
      expect(normalizeLabelPrinterUrl(''), '');
      expect(normalizeLabelPrinterUrl('   '), '');
      expect(normalizeLabelPrinterUrl('http://'), '');
    });
  });

  group('LabelPrinterInfo', () {
    test('parses /info', () {
      final info = LabelPrinterInfo.fromJson({
        'service': 'label-printer',
        'version': 1,
        'printer': {'model': 'QL-600', 'connected': true},
        'label': {'id': '62x29', 'width_mm': 62, 'height_mm': 29, 'dpi': 300},
        'limits': {'max_copies': 50},
      });
      expect(info.model, 'QL-600');
      expect(info.connected, isTrue);
      expect(info.takes(SpoolLabelTemplate.box62x29), isTrue);
      expect(info.takes(SpoolLabelTemplate.box40x30), isFalse);
      expect(info.takes(SpoolLabelTemplate.averyL7160), isFalse);
      expect(info.takesAnySpoolLabel, isTrue);
      expect(info.maxCopies, 50);
    });

    test('connected stays null when the server cannot probe', () {
      final info = LabelPrinterInfo.fromJson({
        'printer': {'model': 'QL-800', 'connected': null},
        'label': {'id': '54x29'},
      });
      expect(info.connected, isNull);
      expect(info.takes(SpoolLabelTemplate.box62x29), isFalse);
      expect(info.takesAnySpoolLabel, isFalse);
    });

    test('tolerates missing blocks', () {
      expect(LabelPrinterInfo.fromJson(const {}).labelId, isNull);
    });

    test('recognises only the label printer service', () {
      expect(
        LabelPrinterInfo.isLabelPrinter({'service': 'label-printer'}),
        isTrue,
      );
      expect(LabelPrinterInfo.isLabelPrinter({'service': 'other'}), isFalse);
      expect(LabelPrinterInfo.isLabelPrinter('<html>'), isFalse);
      expect(LabelPrinterInfo.isLabelPrinter(null), isFalse);
    });
  });
}
