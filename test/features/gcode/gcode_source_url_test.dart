import 'package:bambuddy_mobile/features/gcode/gcode_viewer_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('gcodeSourceUrl', () {
    test('an archive without a plate lets the server pick', () {
      expect(
        gcodeSourceUrl(archiveId: 82, libraryFileId: null),
        '/api/v1/archives/82/gcode',
      );
    });

    // The point of the whole change: which plate the server picks for a
    // plateless request has changed between server generations, so a
    // multi-plate archive has to name its plate.
    test('an archive with a plate asks for that plate', () {
      expect(
        gcodeSourceUrl(archiveId: 82, libraryFileId: null, plate: 3),
        '/api/v1/archives/82/gcode?plate=3',
      );
    });

    test('a library file takes no plate, even when one is passed', () {
      expect(
        gcodeSourceUrl(archiveId: null, libraryFileId: 9, plate: 2),
        '/api/v1/library/files/9/gcode',
        reason: 'library.py::get_gcode reads gcode_files[0] whatever is asked',
      );
    });

    test('a plate below 1 is not a plate and is left off', () {
      // `Metadata/plate_0.gcode` does not exist: sending it would 404 a preview
      // that works without it.
      expect(
        gcodeSourceUrl(archiveId: 82, libraryFileId: null, plate: 0),
        '/api/v1/archives/82/gcode',
      );
      expect(
        gcodeSourceUrl(archiveId: 82, libraryFileId: null, plate: -1),
        '/api/v1/archives/82/gcode',
      );
    });

    test('the archive wins when both sources are given', () {
      expect(
        gcodeSourceUrl(archiveId: 82, libraryFileId: 9, plate: 1),
        '/api/v1/archives/82/gcode?plate=1',
      );
    });
  });
}
