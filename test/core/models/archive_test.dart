import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  group('Archive.fromJson', () {
    test('parses an archive entry, ignoring unknown fields', () {
      final archive = Archive.fromJson(
        readFixture('archive.json') as Map<String, dynamic>,
      );

      expect(archive.id, 82);
      expect(archive.displayName, 'The Smoothy - Y Splitter Connector');
      expect(archive.status, 'completed');
      expect(archive.filamentType, 'PETG');
      expect(archive.cost, 0.51);
      expect(archive.isFavorite, isFalse);
      expect(archive.designer, 'JDJDJD');
      expect(archive.createdAt, isA<DateTime>());
    });

    test('displayName: printName takes priority over filename', () {
      const withName = Archive(
        id: 1,
        filename: 'file.gcode.3mf',
        status: 'completed',
        printName: 'Nice name',
      );
      const withoutName = Archive(
        id: 2,
        filename: 'file.gcode.3mf',
        status: 'completed',
      );

      expect(withName.displayName, 'Nice name');
      expect(withoutName.displayName, 'file.gcode.3mf');
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

    test('unknown keys do not throw an exception', () {
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

    test('a minimal payload (id/filename/status) parses without error', () {
      final archive = Archive.fromJson(const {
        'id': 5,
        'filename': 'minimal.gcode',
        'status': 'archived',
      });

      expect(archive.id, 5);
      expect(archive.filename, 'minimal.gcode');
      expect(
        archive.isFavorite,
        isFalse,
        reason: 'default value false when the field is absent',
      );
      expect(
        archive.displayName,
        'minimal.gcode',
        reason: 'no printName → falls back to filename',
      );
    });

    test('duplicate fields default to 0 when absent', () {
      final archive = Archive.fromJson(const {
        'id': 5,
        'filename': 'a.gcode',
        'status': 'completed',
      });
      expect(archive.duplicateCount, 0);
      expect(archive.duplicateSequence, 0);
      expect(archive.fileSize, isNull);
    });

    test('parses file_size / duplicate_count / duplicate_sequence', () {
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

    test('no photos field → empty list, hasPhotos false', () {
      final archive = parse(const {});
      expect(archive.photos, isEmpty);
      expect(archive.hasPhotos, isFalse);
    });

    test('photos: null → empty list', () {
      expect(parse(const {'photos': null}).photos, isEmpty);
    });

    test('parses filenames, skipping non-string elements', () {
      final archive = parse(const {
        'photos': ['finish_20260815_120000_ab12cd34.jpg', 42, 'ab12cd34.png'],
      });
      expect(archive.photos, [
        'finish_20260815_120000_ab12cd34.jpg',
        'ab12cd34.png',
      ]);
      expect(archive.hasPhotos, isTrue);
    });

    test('hasTimelapse: empty/missing timelapse_path → false', () {
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

    test('.gcode and .gcode.3mf → sliced', () {
      expect(withFile('a.gcode').isSliced, isTrue);
      expect(withFile('a.gcode.3mf').isSliced, isTrue);
    });

    test('.3mf without metadata → source', () {
      expect(withFile('a.3mf').isSliced, isFalse);
    });

    test('.3mf with slice metadata → sliced', () {
      expect(withFile('a.3mf', totalLayers: 100).isSliced, isTrue);
      expect(withFile('a.3mf', printTime: 3600).isSliced, isTrue);
    });
  });

  group('Archive.filamentColors', () {
    Archive withColor(String? color) =>
        Archive(id: 1, filename: 'a.gcode', status: 'x', filamentColor: color);

    test('null → empty list', () {
      expect(withColor(null).filamentColors, isEmpty);
    });

    test('splits on comma and trims spaces', () {
      expect(withColor('#FF0000, #00FF00').filamentColors, [
        '#FF0000',
        '#00FF00',
      ]);
    });

    test('skips empty tokens', () {
      expect(withColor('#FF0000,,').filamentColors, ['#FF0000']);
    });
  });

  group('Archive.withFavorite', () {
    test('changes only isFavorite, keeps the rest of the fields', () {
      const a = Archive(
        id: 7,
        filename: 'a.gcode',
        status: 'completed',
        printName: 'Name',
        filamentType: 'PLA',
        fileSize: 999,
        duplicateCount: 2,
        timelapsePath: 'archive/7/video.mp4',
        photos: ['finish_1.jpg'],
      );
      final fav = a.withFavorite(true);
      expect(fav.isFavorite, isTrue);
      expect(fav.id, 7);
      expect(fav.printName, 'Name');
      expect(fav.filamentType, 'PLA');
      expect(fav.fileSize, 999);
      expect(fav.duplicateCount, 2);
      expect(fav.hasTimelapse, isTrue);
      expect(fav.photos, ['finish_1.jpg']);
      // Original untouched (immutable).
      expect(a.isFavorite, isFalse);
    });
  });

  group('slicer AMS mapping', () {
    Archive withExtra(Object? extra) => Archive.fromJson({
      'id': 1,
      'filename': 'a.3mf',
      'status': 'completed',
      'extra_data': extra,
    });

    test('reads the mapping and the printer it was resolved against', () {
      final a = withExtra({
        'slicer_ams_mapping': {
          'printer_id': 3,
          'mapping': [2, -1, 0],
        },
      });
      expect(a.slicerAmsMapping?.printerId, 3);
      expect(a.slicerAmsMapping?.mapping, [2, -1, 0]);
    });

    test('anything less is no mapping', () {
      expect(withExtra(null).slicerAmsMapping, isNull);
      expect(withExtra(const {}).slicerAmsMapping, isNull);
      expect(
        withExtra({
          'slicer_ams_mapping': {'printer_id': 3, 'mapping': []},
        }).slicerAmsMapping,
        isNull,
      );
      expect(
        withExtra({
          'slicer_ams_mapping': {
            'mapping': [1],
          },
        }).slicerAmsMapping,
        isNull,
      );
    });
  });

  group('fields the web card shows', () {
    Archive parse(Map<String, dynamic> extra) => Archive.fromJson({
      'id': 1,
      'filename': 'a.gcode.3mf',
      'status': 'completed',
      ...extra,
    });

    test('reads time, cost, counts and the user\'s own fields', () {
      final a = parse({
        'print_time_seconds': 1400,
        'actual_time_seconds': 1260,
        'time_accuracy': 111.1,
        'object_count': 3,
        'project_name': 'Workshop',
        'tags': 'jig, workshop,,',
        'notes': 'no supports',
        'external_url': 'https://printables.com/model/1',
        'makerworld_url': 'https://makerworld.com/models/2',
        'energy_kwh': 0.123,
        'energy_cost': 0.07,
        'wear_cost': 0.18,
        'cost': 0.17,
        'created_by_username': 'morgan',
      });
      expect(a.shownTimeSeconds, 1260);
      expect(a.timeAccuracy, 111.1);
      expect(a.objectCount, 3);
      expect(a.projectName, 'Workshop');
      expect(a.tagList, ['jig', 'workshop']);
      expect(a.link, 'https://printables.com/model/1');
      expect(a.totalCost, closeTo(0.42, 1e-9));
      expect(a.createdByUsername, 'morgan');
    });

    test('the estimate stands in until the print has really run', () {
      expect(parse({'print_time_seconds': 1400}).shownTimeSeconds, 1400);
    });

    test('an older server sends none of it, and nothing is made up', () {
      final a = parse(const {});
      expect(a.shownTimeSeconds, isNull);
      expect(a.totalCost, isNull);
      expect(a.link, isNull);
      expect(a.tagList, isEmpty);
      expect(a.filamentSlots, isEmpty);
    });

    test('an empty user link falls back to MakerWorld', () {
      expect(
        parse({
          'external_url': '',
          'makerworld_url': 'https://makerworld.com/models/2',
        }).link,
        'https://makerworld.com/models/2',
      );
    });

    test('a cost the server does not track is left out of the sum', () {
      expect(
        parse({'cost': 0.17, 'energy_cost': 0.07}).totalCost,
        closeTo(0.24, 1e-9),
      );
    });
  });

  group('filament slots', () {
    Archive withSlots(Object? slots) => Archive.fromJson({
      'id': 1,
      'filename': 'a.gcode.3mf',
      'status': 'completed',
      'extra_data': {'filament_slots': slots},
    });

    test('one entry per slot, in slot order', () {
      final a = withSlots([
        {'slot_id': 3, 'used_g': 4.1, 'type': 'PETG', 'color': '#2C6BE0'},
        {'slot_id': 1, 'used_g': 18.2, 'type': 'PLA', 'color': '#E23B3B'},
      ]);
      expect(a.filamentSlots, [
        (slot: 1, type: 'PLA', color: '#E23B3B', grams: 18.2),
        (slot: 3, type: 'PETG', color: '#2C6BE0', grams: 4.1),
      ]);
    });

    // A multi-plate export lists every slot once per plate.
    test('a slot listed for two plates is summed', () {
      final a = withSlots([
        {'slot_id': 1, 'used_g': 10, 'type': 'PLA', 'color': '#FFFFFF'},
        {'slot_id': 1, 'used_g': 5.5, 'type': 'PLA', 'color': '#FFFFFF'},
      ]);
      expect(a.filamentSlots.single.grams, 15.5);
    });

    test('odd entries are skipped, not guessed at', () {
      final a = withSlots([
        'nope',
        {'used_g': 3, 'type': 'PLA'},
        {'slot_id': 2, 'used_g': 0, 'type': 'PLA'},
        {'slot_id': 'x', 'used_g': 3},
        {'slot_id': 4, 'used_g': 2.2},
      ]);
      expect(a.filamentSlots, [(slot: 4, type: '', color: '', grams: 2.2)]);
    });

    test('no list is no slots', () {
      expect(withSlots(null).filamentSlots, isEmpty);
      expect(withSlots('PLA').filamentSlots, isEmpty);
    });
  });
}
