import 'package:bambuddy_mobile/features/common/file_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mimeTypeForFileName', () {
    test('names the kinds a printer stores', () {
      expect(mimeTypeForFileName('Benchy.3mf'), 'model/3mf');
      expect(mimeTypeForFileName('plate_1.gcode'), 'text/x.gcode');
      expect(mimeTypeForFileName('Ultron-files.zip'), 'application/zip');
    });

    test('reads the last extension, not the first', () {
      expect(mimeTypeForFileName('Benchy.gcode.3mf'), 'model/3mf');
    });

    test('is case-insensitive, because the printer is not consistent', () {
      expect(mimeTypeForFileName('COVER.PNG'), 'image/png');
    });

    test('leaves the guess to the platform for anything else', () {
      // Null rather than octet-stream: some share targets refuse that outright,
      // and the platform's own guess from the extension is a better answer.
      expect(mimeTypeForFileName('cache.bin'), isNull);
      expect(mimeTypeForFileName('noextension'), isNull);
      expect(mimeTypeForFileName(''), isNull);
    });
  });
}
