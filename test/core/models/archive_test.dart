import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  group('Archive.fromJson', () {
    test('parsuje wpis archiwum, ignorując nieznane pola', () {
      final archive = Archive.fromJson(
          readFixture('archive.json') as Map<String, dynamic>);

      expect(archive.id, 82);
      expect(archive.displayName, 'The Smoothy - Y Splitter Connector');
      expect(archive.status, 'completed');
      expect(archive.filamentType, 'PETG');
      expect(archive.cost, 0.51);
      expect(archive.isFavorite, isFalse);
      expect(archive.designer, 'JDJDJD');
      expect(archive.createdAt, isA<DateTime>());
    });

    test('displayName: printName ma pierwszeństwo nad filename', () {
      const withName = Archive(
        id: 1,
        filename: 'plik.gcode.3mf',
        status: 'completed',
        printName: 'Ładna nazwa',
      );
      const withoutName = Archive(
        id: 2,
        filename: 'plik.gcode.3mf',
        status: 'completed',
      );

      expect(withName.displayName, 'Ładna nazwa');
      expect(withoutName.displayName, 'plik.gcode.3mf');
    });

    test('plate_id names the plate a multi-plate file printed', () {
      // Real value only since server 1.2.5.4 (#2796 reported null for every
      // archive); a run with no plate chosen still has to come back null, which
      // is what keeps the card from claiming "Plate 1" for every print.
      final chosen = Archive.fromJson(const {
        'id': 1,
        'filename': 'multi.3mf',
        'status': 'completed',
        'plate_id': 3,
      });
      final none = Archive.fromJson(const {
        'id': 2,
        'filename': 'single.3mf',
        'status': 'completed',
        'plate_id': null,
      });

      expect(chosen.plateId, 3);
      expect(none.plateId, isNull);
      // Carried through the one local mutation the app makes.
      expect(chosen.withFavorite(true).plateId, 3);
    });

    test('nieznane klucze nie wywołują wyjątku', () {
      expect(
        () => Archive.fromJson(const {
          'id': 1,
          'filename': 'test.3mf',
          'status': 'completed',
          'totally_unknown_future_field': {'nested': true},
        }),
        returnsNormally,
      );
    });

    test('minimalny payload (id/filename/status) parsuje się bez błędu', () {
      final archive = Archive.fromJson(const {
        'id': 5,
        'filename': 'minimalny.gcode',
        'status': 'archived',
      });

      expect(archive.id, 5);
      expect(archive.filename, 'minimalny.gcode');
      expect(archive.isFavorite, isFalse,
          reason: 'domyślna wartość false gdy pole nieobecne');
      expect(archive.displayName, 'minimalny.gcode',
          reason: 'brak printName → fallback na filename');
    });

    test('duplicate fields domyślnie 0 gdy nieobecne', () {
      final archive = Archive.fromJson(const {
        'id': 5,
        'filename': 'a.gcode',
        'status': 'completed',
      });
      expect(archive.duplicateCount, 0);
      expect(archive.duplicateSequence, 0);
      expect(archive.fileSize, isNull);
    });

    test('parsuje file_size / duplicate_count / duplicate_sequence', () {
      final archive = Archive.fromJson(const {
        'id': 5,
        'filename': 'a.gcode',
        'status': 'completed',
        'file_size': 12345,
        'duplicate_count': 2,
        'duplicate_sequence': 1,
      });
      expect(archive.fileSize, 12345);
      expect(archive.duplicateCount, 2);
      expect(archive.duplicateSequence, 1);
    });
  });

  group('Archive.photos / hasPhotos / hasTimelapse', () {
    Archive parse(Map<String, dynamic> extra) => Archive.fromJson({
      'id': 1,
      'filename': 'a.gcode',
      'status': 'completed',
      ...extra,
    });

    test('brak pola photos → pusta lista, hasPhotos false', () {
      final archive = parse(const {});
      expect(archive.photos, isEmpty);
      expect(archive.hasPhotos, isFalse);
    });

    test('photos: null → pusta lista', () {
      expect(parse(const {'photos': null}).photos, isEmpty);
    });

    test('parsuje nazwy plików, pomijając elementy niebędące stringiem', () {
      final archive = parse(const {
        'photos': ['finish_20260815_120000_ab12cd34.jpg', 42, 'ab12cd34.png'],
      });
      expect(archive.photos, [
        'finish_20260815_120000_ab12cd34.jpg',
        'ab12cd34.png',
      ]);
      expect(archive.hasPhotos, isTrue);
    });

    test('hasTimelapse: puste/brak timelapse_path → false', () {
      expect(parse(const {}).hasTimelapse, isFalse);
      expect(parse(const {'timelapse_path': ''}).hasTimelapse, isFalse);
      expect(
        parse(const {'timelapse_path': 'archive/1/video.mp4'}).hasTimelapse,
        isTrue,
      );
    });
  });

  group('Archive.isSliced', () {
    Archive withFile(String filename, {int? totalLayers, int? printTime}) =>
        Archive(
          id: 1,
          filename: filename,
          status: 'completed',
          totalLayers: totalLayers,
          printTimeSeconds: printTime,
        );

    test('.gcode i .gcode.3mf → sliced', () {
      expect(withFile('a.gcode').isSliced, isTrue);
      expect(withFile('a.gcode.3mf').isSliced, isTrue);
    });

    test('.3mf bez metadanych → source', () {
      expect(withFile('a.3mf').isSliced, isFalse);
    });

    test('.3mf z metadanymi cięcia → sliced', () {
      expect(withFile('a.3mf', totalLayers: 100).isSliced, isTrue);
      expect(withFile('a.3mf', printTime: 3600).isSliced, isTrue);
    });
  });

  group('Archive.filamentColors', () {
    Archive withColor(String? color) =>
        Archive(id: 1, filename: 'a.gcode', status: 'x', filamentColor: color);

    test('null → pusta lista', () {
      expect(withColor(null).filamentColors, isEmpty);
    });

    test('rozdziela po przecinku i przycina spacje', () {
      expect(
        withColor('#FF0000, #00FF00').filamentColors,
        ['#FF0000', '#00FF00'],
      );
    });

    test('pomija puste tokeny', () {
      expect(withColor('#FF0000,,').filamentColors, ['#FF0000']);
    });
  });

  group('Archive.withFavorite', () {
    test('zmienia tylko isFavorite, resztę pól zachowuje', () {
      const a = Archive(
        id: 7,
        filename: 'a.gcode',
        status: 'completed',
        printName: 'Nazwa',
        filamentType: 'PLA',
        fileSize: 999,
        duplicateCount: 2,
        timelapsePath: 'archive/7/video.mp4',
        photos: ['finish_1.jpg'],
      );
      final fav = a.withFavorite(true);
      expect(fav.isFavorite, isTrue);
      expect(fav.id, 7);
      expect(fav.printName, 'Nazwa');
      expect(fav.filamentType, 'PLA');
      expect(fav.fileSize, 999);
      expect(fav.duplicateCount, 2);
      expect(fav.hasTimelapse, isTrue);
      expect(fav.photos, ['finish_1.jpg']);
      // Oryginał nietknięty (niemutowalny).
      expect(a.isFavorite, isFalse);
    });
  });
}
