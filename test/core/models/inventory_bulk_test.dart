import 'package:bambuddy_mobile/core/models/inventory_bulk.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bulk-edit patch and the normalized outcome of a bulk call. Both sit
/// between the two backends, which disagree about the fields they accept and
/// about how they report what did not happen.
void main() {
  group('SpoolBulkPatch', () {
    test('sends only the fields that were set', () {
      const patch = SpoolBulkPatch(brand: 'Bambu', labelWeight: 1000);

      expect(patch.toNativeJson(), {'brand': 'Bambu', 'label_weight': 1000});
      expect(patch.fieldCount, 2);
      expect(patch.isEmpty, isFalse);
    });

    test('an untouched patch is empty, so nothing is sent', () {
      const patch = SpoolBulkPatch();

      expect(patch.toNativeJson(), isEmpty);
      expect(patch.toSpoolmanJson(), isEmpty);
      expect(patch.isEmpty, isTrue);
      expect(patch.fieldCount, 0);
    });

    test('an empty string is a value, not an absence', () {
      // Blank input means "unchanged" in the UI, which is why it must arrive
      // here as null. If a caller does pass '', the field IS in the patch —
      // the model must not silently reinterpret it as "leave alone".
      const patch = SpoolBulkPatch(note: '');

      expect(patch.toNativeJson(), {'note': ''});
      expect(patch.isEmpty, isFalse);
    });

    test('every editable field maps to its wire name', () {
      const patch = SpoolBulkPatch(
        material: 'PLA',
        subtype: 'Matte',
        brand: 'Bambu',
        colorName: 'Red',
        rgba: 'FF0000FF',
        storageLocation: 'Shelf A',
        slicerFilament: 'GFA00',
        slicerFilamentName: 'Bambu PLA Basic',
        costPerKg: 24.5,
        note: 'restock',
        labelWeight: 1000,
        coreWeight: 250,
        category: 'prototyping',
        lowStockThresholdPct: 15,
      );

      expect(patch.toNativeJson(), {
        'material': 'PLA',
        'subtype': 'Matte',
        'brand': 'Bambu',
        'color_name': 'Red',
        'rgba': 'FF0000FF',
        'storage_location': 'Shelf A',
        'slicer_filament': 'GFA00',
        'slicer_filament_name': 'Bambu PLA Basic',
        'cost_per_kg': 24.5,
        'note': 'restock',
        'label_weight': 1000,
        'core_weight': 250,
        'category': 'prototyping',
        'low_stock_threshold_pct': 15,
      });
    });

    test('Spoolman drops the two columns its schema has no place for', () {
      const patch = SpoolBulkPatch(
        brand: 'Bambu',
        category: 'prototyping',
        lowStockThresholdPct: 15,
      );

      expect(patch.toSpoolmanJson(), {'brand': 'Bambu'});
    });

    test('a native-only patch reaches Spoolman as nothing to do', () {
      // Not an error, and not something the caller may send: the route
      // answers 400 to an empty `update`.
      const patch = SpoolBulkPatch(category: 'prototyping');

      expect(patch.toNativeJson(), isNotEmpty);
      expect(patch.toSpoolmanJson(), isEmpty);
    });
  });

  group('BulkOutcome from the native shape', () {
    test('reads the count and the unknown ids', () {
      final outcome = BulkOutcome.fromJson({
        'updated': 3,
        'not_found': [98, 99],
      }, okKey: 'updated');

      expect(outcome.ok, 3);
      expect(outcome.skipped, 0);
      expect(outcome.failed, 2);
      expect(outcome.notFound, [98, 99]);
      expect(outcome.isComplete, isFalse);
    });

    test('already-archived rows are skipped, not failed', () {
      final outcome = BulkOutcome.fromJson(
        {
          'archived': 3,
          'already_archived': [7, 8],
          'not_found': [],
        },
        okKey: 'archived',
        skippedKey: 'already_archived',
      );

      expect(outcome.ok, 3);
      expect(outcome.skipped, 2);
      expect(outcome.failed, 0);
      expect(outcome.isComplete, isTrue);
    });

    test('a skipped count instead of a list of ids still reads', () {
      final outcome = BulkOutcome.fromJson(
        {'restored': 1, 'already_active': 4},
        okKey: 'restored',
        skippedKey: 'already_active',
      );

      expect(outcome.skipped, 4);
    });
  });

  group('BulkOutcome from the Spoolman shape', () {
    test('counts the per-spool errors it reports instead of not_found', () {
      final outcome = BulkOutcome.fromJson({
        'updated': 2,
        'errors': [
          {'id': 5, 'status': 404, 'detail': 'not found'},
          {'id': 6, 'status': 500, 'detail': 'boom'},
        ],
      }, okKey: 'updated');

      expect(outcome.ok, 2);
      expect(outcome.failed, 2);
      expect(outcome.notFound, isEmpty);
      expect(outcome.isComplete, isFalse);
    });
  });

  group('BulkOutcome edge shapes', () {
    test('a body that says nothing is zeroes, not a crash', () {
      final outcome = BulkOutcome.fromJson(null, okKey: 'deleted');

      expect(outcome.ok, 0);
      expect(outcome.failed, 0);
      expect(outcome.isComplete, isTrue);
    });

    test('string-typed numbers from a proxy still parse', () {
      final outcome = BulkOutcome.fromJson({
        'deleted': '2',
        'not_found': ['9'],
      }, okKey: 'deleted');

      expect(outcome.ok, 2);
      expect(outcome.notFound, [9]);
    });

    test('the reset route infers failures from the gap it leaves', () {
      // `{reset: n}` reports neither errors nor unknown ids, so the only
      // reading of a short count is that the rest did not happen.
      final outcome = BulkOutcome.fromResetJson({'reset': 3}, 5);

      expect(outcome.ok, 3);
      expect(outcome.failed, 2);
    });

    test('a reset that overshoots the request never reports negative', () {
      final outcome = BulkOutcome.fromResetJson({'reset': 7}, 5);

      expect(outcome.ok, 7);
      expect(outcome.failed, 0);
    });

    test('chunks of one selection add up', () {
      const first = BulkOutcome(ok: 2, skipped: 1, failed: 1, notFound: [9]);
      const second = BulkOutcome(ok: 3, failed: 2, notFound: [11, 12]);

      final total = first + second;

      expect(total.ok, 5);
      expect(total.skipped, 1);
      expect(total.failed, 3);
      expect(total.notFound, [9, 11, 12]);
    });
  });

  group('chunkIds', () {
    test('a selection inside the cap is one request', () {
      expect(chunkIds([1, 2, 3]), [
        [1, 2, 3],
      ]);
    });

    test('the cap itself is still one request', () {
      final ids = [for (var i = 0; i < bulkIdLimit; i++) i];

      expect(chunkIds(ids), hasLength(1));
    });

    test('one id over the cap splits, and nothing is lost or repeated', () {
      final ids = [for (var i = 0; i < bulkIdLimit + 1; i++) i];

      final chunks = chunkIds(ids);

      expect(chunks.map((c) => c.length), [bulkIdLimit, 1]);
      expect(chunks.expand((c) => c), ids);
    });

    test('nothing selected is no requests, not one empty request', () {
      // The routes reject an empty `ids` list, so the right number of calls
      // to make for an empty selection is zero.
      expect(chunkIds([]), isEmpty);
    });
  });
}
