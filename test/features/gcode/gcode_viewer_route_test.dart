import 'package:bambuddy_mobile/features/gcode/gcode_viewer_route.dart';
import 'package:flutter_test/flutter_test.dart';

/// What `router.dart` pulls back out of the link, so a round trip can be
/// checked the way the app really does it.
({int? archive, int? libraryFile, int? plate, String? name}) parsed(
  String route,
) {
  final q = Uri.parse(route).queryParameters;
  return (
    archive: int.tryParse(q['archive'] ?? ''),
    libraryFile: int.tryParse(q['library_file'] ?? ''),
    plate: int.tryParse(q['plate'] ?? ''),
    name: q['name'],
  );
}

void main() {
  group('gcodeViewerRoute', () {
    test('an archive with a plate and a title', () {
      final route = gcodeViewerRoute(archiveId: 82, plate: 3, title: 'Benchy');

      expect(Uri.parse(route).path, gcodeViewerPath);
      expect(parsed(route), (
        archive: 82,
        libraryFile: null,
        plate: 3,
        name: 'Benchy',
      ));
    });

    test('a library file names its own parameter', () {
      final route = gcodeViewerRoute(libraryFileId: 9, title: 'lid.3mf');

      expect(parsed(route).libraryFile, 9);
      expect(parsed(route).archive, isNull);
    });

    // The library route serves the first `.gcode` in the file whatever is
    // asked, so a plate on that link would promise something it cannot keep.
    test('a plate is dropped for a library file', () {
      expect(
        parsed(gcodeViewerRoute(libraryFileId: 9, plate: 2)).plate,
        isNull,
      );
    });

    test(
      'no plate and a plate below 1 both leave the choice to the server',
      () {
        expect(parsed(gcodeViewerRoute(archiveId: 82)).plate, isNull);
        expect(parsed(gcodeViewerRoute(archiveId: 82, plate: 0)).plate, isNull);
        expect(
          parsed(gcodeViewerRoute(archiveId: 82, plate: -3)).plate,
          isNull,
        );
      },
    );

    test('an absent or blank title leaves the parameter out', () {
      expect(parsed(gcodeViewerRoute(archiveId: 82)).name, isNull);
      expect(
        parsed(gcodeViewerRoute(archiveId: 82, title: '   ')).name,
        isNull,
      );
    });

    // A print name is user data and carries whatever the designer typed. The
    // three hand-built versions did remember to encode it; the point of one
    // builder is that this no longer depends on remembering.
    test('a title full of query syntax survives the round trip', () {
      const nasty = 'Bracket & Lid #2 (50%) ?v=1 + spare/parts';

      final route = gcodeViewerRoute(archiveId: 82, plate: 2, title: nasty);

      expect(parsed(route), (
        archive: 82,
        libraryFile: null,
        plate: 2,
        name: nasty,
      ));
    });

    test('a non-ASCII title survives too', () {
      const name = 'Uchwyt na słuchawki — wersja żółta';

      expect(parsed(gcodeViewerRoute(archiveId: 1, title: name)).name, name);
    });

    test('the archive wins when both sources are given', () {
      final route = gcodeViewerRoute(archiveId: 82, libraryFileId: 9);

      expect(parsed(route).archive, 82);
      expect(parsed(route).libraryFile, isNull);
    });
  });
}
