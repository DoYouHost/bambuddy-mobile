import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/widget/widget_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('activePrintLabel', () {
    test('a set currentPrint is trimmed and wins over gcodeFile', () {
      const s = PrinterStatus(
        id: 1,
        currentPrint: '  benchy.3mf ',
        gcodeFile: 'other.gcode',
        stgCurName: 'Heating',
      );
      expect(activePrintLabel(s), 'benchy.3mf');
    });

    test('a null currentPrint falls back to gcodeFile', () {
      const s = PrinterStatus(id: 1, gcodeFile: 'other.gcode');
      expect(activePrintLabel(s), 'other.gcode');
    });

    test('a blank currentPrint does not fall back to gcodeFile', () {
      const s = PrinterStatus(
        id: 1,
        currentPrint: '   ',
        gcodeFile: 'other.gcode',
        stgCurName: 'Heating',
      );
      expect(activePrintLabel(s), 'Heating');
    });

    test('both names blank shows the trimmed stage', () {
      const s = PrinterStatus(
        id: 1,
        currentPrint: '',
        gcodeFile: ' ',
        stgCurName: ' Homing ',
      );
      expect(activePrintLabel(s), 'Homing');
    });

    test('a blank stage with no file name is empty', () {
      const s = PrinterStatus(id: 1, stgCurName: '  ');
      expect(activePrintLabel(s), '');
    });

    test('all null is empty', () {
      const s = PrinterStatus(id: 1);
      expect(activePrintLabel(s), '');
    });
  });
}
