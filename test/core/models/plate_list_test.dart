import 'package:bambuddy_mobile/core/models/plate_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> plate(int index, {Object? thumb = true}) => {
        'index': index,
        'name': 'Plate $index',
        'objects': ['bracket', 'lid'],
        'object_count': 2,
        'has_thumbnail': thumb,
        'thumbnail_url': '/api/v1/archives/82/plate-thumbnail/$index',
        'print_time_seconds': 1200,
        'filament_used_grams': 12.5,
        'bed_type': 'Textured PEI Plate',
      };

  group('PlateList.fromJson', () {
    test('reads the plate rows of a multi-plate response', () {
      final list = PlateList.fromJson({
        'archive_id': 82,
        'plates': [plate(1), plate(2)],
        'is_multi_plate': true,
        'has_gcode': true,
      });

      expect(list.plates, hasLength(2));
      expect(list.isMultiPlate, isTrue);
      expect(list.hasGcode, isTrue);
      final first = list.plates.first;
      expect(first.index, 1);
      expect(first.name, 'Plate 1');
      expect(first.objects, ['bracket', 'lid']);
      expect(first.objectCount, 2);
      expect(first.printTimeSeconds, 1200);
      expect(first.filamentUsedGrams, 12.5);
      expect(first.bedType, 'Textured PEI Plate');
      expect(first.thumbnailPath, '/api/v1/archives/82/plate-thumbnail/1');
    });

    test('a single-plate file is not offered as a choice', () {
      final list = PlateList.fromJson({'plates': [plate(1)], 'has_gcode': true});

      expect(list.plates, hasLength(1));
      expect(list.isMultiPlate, isFalse);
    });

    test('a file with no plates parses to the same state as a failure', () {
      final list = PlateList.fromJson({'plates': [], 'is_multi_plate': false});

      expect(list.plates, isEmpty);
      expect(list.isMultiPlate, isFalse);
      expect(list.hasGcode, PlateList.none.hasGcode);
    });

    // The library route omits both keys; reading either as true would offer a
    // G-code preview for a source-only 3MF that has none.
    test('missing has_gcode and bed_type read as absent, not as true', () {
      final list = PlateList.fromJson({
        'plates': [
          {'index': 3, 'has_thumbnail': false},
        ],
      });

      expect(list.hasGcode, isFalse);
      expect(list.plates.single.bedType, isNull);
      expect(list.plates.single.thumbnailPath, isNull);
    });

    test('rows without a usable index are dropped, not the whole list', () {
      final list = PlateList.fromJson({
        'plates': [
          plate(2),
          {'index': null, 'name': 'no number'},
          {'index': 0, 'name': 'zero is not a plate'},
          {'name': 'no index at all'},
          'not even a map',
          plate(1),
        ],
      });

      expect(list.plates.map((p) => p.index), [1, 2]);
    });

    test('a thumbnail is only asked for when the server said there is one', () {
      final list = PlateList.fromJson({
        'plates': [
          plate(1, thumb: false),
          {'index': 2, 'has_thumbnail': true, 'thumbnail_url': null},
        ],
      });

      expect(list.plates[0].thumbnailPath, isNull);
      expect(list.plates[1].thumbnailPath, isNull);
    });

    // The render is fetched with the camera token in the query, so a path that
    // names another host would hand that token to whoever it named.
    test('a thumbnail_url pointing off this server is refused', () {
      final list = PlateList.fromJson({
        'plates': [
          {'index': 1, 'has_thumbnail': true,
            'thumbnail_url': 'https://evil.example/steal'},
          {'index': 2, 'has_thumbnail': true, 'thumbnail_url': '//evil.example/steal'},
          {'index': 3, 'has_thumbnail': true, 'thumbnail_url': 'plate.png'},
          {'index': 4, 'has_thumbnail': true,
            'thumbnail_url': '/api/v1/archives/82/plate-thumbnail/4'},
        ],
      });

      expect(list.byIndex(1)?.thumbnailPath, isNull);
      expect(list.byIndex(2)?.thumbnailPath, isNull);
      expect(list.byIndex(3)?.thumbnailPath, isNull);
      expect(list.byIndex(4)?.thumbnailPath,
          '/api/v1/archives/82/plate-thumbnail/4');
    });

    test('malformed payload degrades instead of throwing', () {
      expect(PlateList.fromJson(const {}).plates, isEmpty);
      expect(PlateList.fromJson(const {'plates': 'nope'}).plates, isEmpty);
      expect(
        PlateList.fromJson(const {'plates': [], 'unknown_future_key': 1}).plates,
        isEmpty,
      );
    });

    test('string numbers from the server still parse', () {
      final list = PlateList.fromJson({
        'plates': [
          {
            'index': '4',
            'has_thumbnail': false,
            'print_time_seconds': '900',
            'filament_used_grams': '7.25',
            'object_count': '3',
          },
        ],
      });

      final only = list.plates.single;
      expect(only.index, 4);
      expect(only.printTimeSeconds, 900);
      expect(only.filamentUsedGrams, 7.25);
      expect(only.objectCount, 3);
    });
  });

  // The design presets used to arrive through a second request to the same
  // route. They come out of this one payload now; what EmbeddedSettings makes
  // of the individual keys is pinned in embedded_settings_test.dart.
  group('PlateList.embedded', () {
    test('comes out of the same payload as the plates', () {
      final list = PlateList.fromJson({
        'plates': [plate(1), plate(2)],
        'embedded_printer': 'Bambu Lab X2D 0.4 nozzle',
        'embedded_process': '0.20mm Standard @BBL X2D',
        'design_overrides': const [],
      });

      expect(list.plates, hasLength(2));
      expect(list.embedded.printer, 'Bambu Lab X2D 0.4 nozzle');
      expect(list.embedded.isAvailable, isTrue,
          reason: 'an empty override list is still a server that has the key');
    });

    test('a payload without the design keys offers nothing to slice as', () {
      final list = PlateList.fromJson({'plates': [plate(1)]});

      expect(list.embedded.isAvailable, isFalse);
      expect(PlateList.none.embedded.isAvailable, isFalse);
    });
  });

  group('PlateList.byIndex', () {
    final list = PlateList.fromJson({'plates': [plate(1), plate(4)]});

    test('finds the row for a plate the file has', () {
      expect(list.byIndex(4)?.name, 'Plate 4');
    });

    test('null for no plate and for a plate the file does not have', () {
      expect(list.byIndex(null), isNull);
      expect(list.byIndex(2), isNull);
    });
  });
}
