import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/data/slicer_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// `GET /slicer/loaded-spools` (#3172): every key the slice form's filters
/// and spool picker read, off the seeded printer's AMS — and nothing at all
/// from a server that predates the route.
void main() {
  group('slicer loaded spools contract', skip: contractSkipReason, () {
    test('the online printer reports its AMS trays in the shape the app '
        'reads', () async {
      final dio = await authenticatedDio();
      final raw = await dio.get<Map<String, dynamic>>(
        Endpoints.slicerLoadedSpools,
        options: Options(validateStatus: (_) => true),
      );
      final printers = await SlicerRepository(dio).loadedSpools();

      if (raw.statusCode == 404) {
        expect(printers, isNull, reason: 'no filters on an older server');
        markTestSkipped('server predates /slicer/loaded-spools (#3172)');
        return;
      }
      expect(raw.statusCode, 200);

      // Keys first: the parser defaults a missing one, which would read as an
      // empty slot rather than as a renamed field.
      final printer = (raw.data!['printers'] as List).first as Map;
      expect(
        printer.keys,
        containsAll([
          'id',
          'name',
          'model',
          'ams',
          'external',
          'external_holders',
        ]),
      );
      final unit = (printer['ams'] as List).first as Map;
      expect(unit.keys, containsAll(['id', 'is_ams_ht', 'trays']));
      final tray = (unit['trays'] as List).first as Map;
      expect(
        tray.keys,
        containsAll([
          'ams_id',
          'tray_id',
          'tray_type',
          'tray_sub_brands',
          'tray_color',
          'tray_info_idx',
          'exists',
          'state',
          'saved_preset',
        ]),
      );

      // The seed loads two PLA Basic spools into AMS 0 (`seed_bambuddy.sh`).
      final parsed = printers!.first.ams.first;
      expect(parsed.isAmsHt, isFalse);
      expect(parsed.trays.first.isLoaded, isTrue);
      expect(parsed.trays.first.traySubBrands, 'PLA Basic');
      expect(parsed.trays.first.trayColor, 'FF0000FF');
    });
  });
}
