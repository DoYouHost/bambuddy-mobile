import 'package:bambuddy_mobile/core/models/library_file.dart';
import 'package:flutter_test/flutter_test.dart';

LibraryFile file({String? printName}) => LibraryFile(
  id: 1,
  filename: 'Mug Holder.3mf',
  fileType: '3mf',
  fileSize: 1024,
  printCount: 0,
  printName: printName,
);

void main() {
  group('LibraryFile.displayName', () {
    test('the slicer name wins over the name on disk', () {
      expect(file(printName: 'Mug Holder v3').displayName, 'Mug Holder v3');
    });

    test('a file the slicer named nothing falls back to the filename', () {
      expect(file().displayName, 'Mug Holder.3mf');
    });
  });

  test('isSlicedFilename: sliced outputs in any case, nothing else', () {
    expect(isSlicedFilename('part.gcode'), isTrue);
    expect(isSlicedFilename('Plate 1.GCODE.3MF'), isTrue);
    expect(isSlicedFilename('model.3mf'), isFalse);
    expect(isSlicedFilename('model.stl'), isFalse);
    expect(isSlicedFilename('gcode'), isFalse);
    expect(isSlicedFilename(''), isFalse);
  });
}
